import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

import {
  OBSERVABILITY_ACTIVE_ROUTE_TIMEOUT_MS,
} from "./dock-relay-constants.mjs";
import { sanitizeFields } from "./dock-relay-logger.mjs";
import {
  FAILURE_CATEGORY,
  OBSERVABILITY_CONTRACT,
  PROBE_SAFETY,
  ROUTE_NAMES,
  ROUTE_STATUS,
  allRouteConfigs,
  routeConfigFor,
} from "./dock-relay-observability-contract.mjs";

const TRACE_PARAM_KEY = "_codexDockTrace";
const DEFAULT_MAX_EVENTS = 500;
const DEFAULT_MAX_TRACES = 200;

// Route health is app-path truth. Process liveness stays in /readyz and /healthz.
function nowISO(clock) {
  const value = clock();
  return value instanceof Date ? value.toISOString() : new Date(value).toISOString();
}

function nowMs(clock) {
  const value = clock();
  return value instanceof Date ? value.getTime() : new Date(value).getTime();
}

function newID(prefix) {
  return `${prefix}_${crypto.randomUUID()}`;
}

function boundedPush(items, item, limit) {
  items.push(item);
  while (items.length > limit) {
    items.shift();
  }
}

function sanitizeTraceContext(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return null;
  }
  const trace = {};
  for (const key of [
    "schema",
    "traceID",
    "operationID",
    "parentOperationID",
    "configuredHostID",
    "route",
    "clientBuild",
    "platform",
  ]) {
    const raw = value[key];
    if (typeof raw === "string" && raw.trim()) {
      trace[key] = raw.trim();
    } else if (raw === null && key === "parentOperationID") {
      trace[key] = null;
    }
  }
  return Object.keys(trace).length > 0 ? trace : null;
}

function extractTraceContextFromParams(params) {
  if (!params || typeof params !== "object" || Array.isArray(params)) {
    return { traceContext: null, params };
  }
  const traceContext = sanitizeTraceContext(params[TRACE_PARAM_KEY]);
  if (!Object.prototype.hasOwnProperty.call(params, TRACE_PARAM_KEY)) {
    return { traceContext: null, params };
  }
  const scrubbed = { ...params };
  delete scrubbed[TRACE_PARAM_KEY];
  return { traceContext, params: scrubbed };
}

function failureCategoryFor(errorData, error, routeName) {
  if (errorData?.overload) {
    return FAILURE_CATEGORY.UPSTREAM_OVERLOAD;
  }
  switch (errorData?.subsystem) {
  case "history":
    return FAILURE_CATEGORY.HISTORY;
  case "live-upstream":
    return FAILURE_CATEGORY.LIVE_UPSTREAM;
  case "transcription":
    return FAILURE_CATEGORY.TRANSCRIPTION;
  case "downstream":
    return FAILURE_CATEGORY.DOWNSTREAM;
  case "upstream-overload":
    return FAILURE_CATEGORY.UPSTREAM_OVERLOAD;
  default:
    break;
  }
  if (error?.code === -32601) {
    return FAILURE_CATEGORY.UNSUPPORTED;
  }
  if (error?.code === -32602) {
    return FAILURE_CATEGORY.VALIDATION;
  }
  if (String(error?.message || "").toLowerCase().includes("timed out")) {
    return FAILURE_CATEGORY.TIMEOUT;
  }
  if (String(routeName || "").startsWith("audio/transcription/")) {
    return FAILURE_CATEGORY.TRANSCRIPTION;
  }
  return FAILURE_CATEGORY.RELAY;
}

function statusReasonForFailure({ evidenceID, errorCode, failureCategory, phase, error }) {
  return sanitizeFields({
    code: "failed:last-attempt",
    message: `last attempt failed${phase ? ` at ${phase}` : ""}`,
    threshold: null,
    actual: failureCategory || FAILURE_CATEGORY.RELAY,
    evidenceIDs: [evidenceID],
    errorCode: errorCode ?? null,
    phase: phase || null,
    error: error?.message || null,
  });
}

function statusReasonForStarted({ evidenceID }) {
  return sanitizeFields({
    code: "active:in-flight",
    message: "route operation is currently in flight",
    threshold: null,
    actual: "started",
    evidenceIDs: [evidenceID],
    errorCode: null,
    phase: "dispatch",
  });
}

function statusReasonForTimeout({ evidenceID, timeoutMs, durationMs }) {
  return sanitizeFields({
    code: "failed:in-flight-timeout",
    message: "route operation exceeded the active-operation timeout",
    threshold: timeoutMs,
    actual: durationMs,
    evidenceIDs: [evidenceID],
    errorCode: null,
    phase: "in-flight",
    error: `timed out after ${timeoutMs}ms`,
  });
}

function measurementSummaryForResult(routeName, result) {
  const summary = {
    route: routeName,
    rowCount: null,
    estimatedBytes: null,
    largestRowEstimateBytes: null,
    resultKind: result === null ? "null" : Array.isArray(result) ? "array" : typeof result,
  };
  if (!result || typeof result !== "object") {
    return summary;
  }

  const rows = Array.isArray(result.sessions)
    ? result.sessions
    : Array.isArray(result.data)
      ? result.data
      : Array.isArray(result.rows)
        ? result.rows
        : null;
  if (!rows) {
    return summary;
  }

  summary.rowCount = rows.length;
  let estimatedBytes = 0;
  let largestRowEstimateBytes = 0;
  for (const row of rows) {
    const estimate = estimateJSONBytes(row, 6);
    estimatedBytes += estimate;
    largestRowEstimateBytes = Math.max(largestRowEstimateBytes, estimate);
  }
  summary.estimatedBytes = estimatedBytes;
  summary.largestRowEstimateBytes = largestRowEstimateBytes;
  return summary;
}

function estimateJSONBytes(value, depth) {
  if (depth <= 0) {
    return 32;
  }
  if (value === null || value === undefined) {
    return 4;
  }
  switch (typeof value) {
  case "boolean":
    return value ? 4 : 5;
  case "number":
    return String(value).length;
  case "string":
    return Math.min(4_096, Buffer.byteLength(value, "utf8") + 2);
  case "object": {
    if (Array.isArray(value)) {
      return value.reduce((total, item) => total + estimateJSONBytes(item, depth - 1) + 1, 2);
    }
    let total = 2;
    for (const [key, child] of Object.entries(value)) {
      total += Buffer.byteLength(key, "utf8") + 3 + estimateJSONBytes(child, depth - 1);
    }
    return total;
  }
  default:
    return 8;
  }
}

function routeRecordFromConfig(config, host) {
  return {
    schema: "codexdock.routeHealth.v1",
    configuredHostID: null,
    relayHostID: host.id,
    route: config.name,
    probeSafety: config.probeSafety,
    appCritical: config.appCritical,
    routeStatus: ROUTE_STATUS.UNKNOWN,
    statusReasons: [],
    lastAttempt: null,
    lastSuccess: null,
    lastFailure: null,
    lastMeasurement: null,
    counters: {
      total: 0,
      succeeded: 0,
      failed: 0,
    },
    appImpact: config.appCritical ? "app-critical" : "diagnostic",
  };
}

class RelayObservability {
  constructor({
    hostId = null,
    hostName = null,
    configuredHostID = null,
    clock = () => new Date(),
    maxEvents = DEFAULT_MAX_EVENTS,
    maxTraces = DEFAULT_MAX_TRACES,
    persistenceDir = null,
    activeRouteTimeoutMs = OBSERVABILITY_ACTIVE_ROUTE_TIMEOUT_MS,
  } = {}) {
    this.host = {
      id: hostId,
      displayName: hostName || hostId,
    };
    this.configuredHostID = configuredHostID;
    this.clock = clock;
    this.maxEvents = maxEvents;
    this.maxTraces = maxTraces;
    this.persistenceDir = persistenceDir;
    this.activeRouteTimeoutMs = activeRouteTimeoutMs;
    this.events = [];
    this.traces = new Map();
    this.activeOperations = new Map();
    this.routes = new Map();
    for (const config of allRouteConfigs()) {
      this.routes.set(config.name, routeRecordFromConfig(config, this.host));
    }
  }

  updateHost({ hostId = null, hostName = null, configuredHostID = null } = {}) {
    if (hostId) {
      this.host.id = hostId;
    }
    if (hostName || hostId) {
      this.host.displayName = hostName || hostId;
    }
    if (configuredHostID) {
      this.configuredHostID = configuredHostID;
    }
    for (const [routeName, record] of this.routes) {
      this.routes.set(routeName, {
        ...record,
        relayHostID: this.host.id,
        configuredHostID: record.configuredHostID || this.configuredHostID || null,
      });
    }
  }

  beginOperation({ route, method = route, traceContext = null, parentOperationID = null } = {}) {
    const routeName = String(route || method || "unknown");
    const config = routeConfigFor(routeName);
    this.ensureRoute(routeName);
    const startedAt = nowISO(this.clock);
    const operationID = traceContext?.operationID || newID("op");
    const traceID = traceContext?.traceID || newID("tr");
    const operation = {
      operationID,
      traceID,
      route: routeName,
      method: method || routeName,
      parentOperationID: traceContext?.parentOperationID || parentOperationID || null,
      configuredHostID: traceContext?.configuredHostID || this.configuredHostID || null,
      relayHostID: this.host.id || null,
      startedAt,
      startedAtMs: nowMs(this.clock),
      probeSafety: config.probeSafety,
      appCritical: config.appCritical,
    };
    const event = this.recordEvent({
      operationID,
      traceID,
      route: routeName,
      type: "route.started",
      at: startedAt,
      outcome: "started",
    });
    this.activeOperations.set(operationID, operation);
    this.traces.set(operationID, {
      schema: "codexdock.trace.v1",
      operationID,
      traceID,
      parentOperationID: operation.parentOperationID,
      configuredHostID: operation.configuredHostID,
      relayHostID: operation.relayHostID,
      route: routeName,
      method: operation.method,
      startedAt,
      finishedAt: null,
      durationMs: null,
      outcome: "started",
      failureCategory: null,
      errorCode: null,
      statusReasons: [],
      events: [event],
      measurements: [],
    });
    this.updateRoute(routeName, {
      configuredHostID: operation.configuredHostID,
      relayHostID: operation.relayHostID,
      routeStatus: ROUTE_STATUS.PARTIAL,
      statusReasons: [statusReasonForStarted({ evidenceID: event.evidenceID })],
      lastAttempt: {
        operationID,
        at: startedAt,
        durationMs: null,
        outcome: "started",
        failureCategory: null,
        phase: "dispatch",
      },
    });
    this.trimTraces();
    this.persist();
    return operation;
  }

  finishOperation(operation, {
    ok,
    error = null,
    errorCode = null,
    errorData = null,
    result = undefined,
    measurements = null,
    phase = null,
    outcome = null,
  } = {}) {
    if (!operation) {
      return null;
    }
    this.activeOperations.delete(operation.operationID);
    const finishedAt = nowISO(this.clock);
    const durationMs = Math.max(0, nowMs(this.clock) - operation.startedAtMs);
    const routeName = operation.route;
    const config = routeConfigFor(routeName);
    const succeeded = ok === true;
    const failureCategory = succeeded
      ? FAILURE_CATEGORY.NONE
      : failureCategoryFor(errorData, error, routeName);
    const evidence = this.recordEvent({
      operationID: operation.operationID,
      traceID: operation.traceID,
      route: routeName,
      type: succeeded ? "route.succeeded" : "route.failed",
      at: finishedAt,
      durationMs,
      outcome: outcome || (succeeded ? "succeeded" : "failed"),
      failureCategory: succeeded ? null : failureCategory,
      errorCode,
      phase,
    });
    const computedMeasurements = measurements || measurementSummaryForResult(routeName, result);
    const statusReasons = succeeded ? [] : [
      statusReasonForFailure({
        evidenceID: evidence.evidenceID,
        errorCode,
        failureCategory,
        phase,
        error,
      }),
    ];
    const lastAttempt = sanitizeFields({
      operationID: operation.operationID,
      at: finishedAt,
      durationMs,
      outcome: succeeded ? "succeeded" : "failed",
      failureCategory: succeeded ? null : failureCategory,
      phase,
    });
    this.updateRoute(routeName, {
      configuredHostID: operation.configuredHostID,
      relayHostID: operation.relayHostID,
      routeStatus: succeeded ? ROUTE_STATUS.HEALTHY : ROUTE_STATUS.FAILED,
      statusReasons,
      lastAttempt,
      lastSuccess: succeeded ? lastAttempt : undefined,
      lastFailure: succeeded ? undefined : lastAttempt,
      lastMeasurement: computedMeasurements,
      incrementSuccess: succeeded,
      incrementFailure: !succeeded,
    });
    const trace = this.traces.get(operation.operationID);
    if (trace) {
      trace.finishedAt = finishedAt;
      trace.durationMs = durationMs;
      trace.outcome = succeeded ? "succeeded" : "failed";
      trace.failureCategory = succeeded ? null : failureCategory;
      trace.errorCode = errorCode;
      trace.statusReasons = statusReasons;
      trace.events.push(evidence);
      trace.measurements.push(computedMeasurements);
    }
    this.persist();
    return trace || null;
  }

  recordNotification(routeName, { parentOperationID = null, measurements = null } = {}) {
    const config = routeConfigFor(routeName);
    if (config.probeSafety !== PROBE_SAFETY.PASSIVE_ONLY) {
      return null;
    }
    const operation = this.beginOperation({
      route: routeName,
      parentOperationID,
    });
    return this.finishOperation(operation, {
      ok: true,
      measurements,
      outcome: "observed",
    });
  }

  recordMeasurement(routeName, measurements = {}) {
    this.ensureRoute(routeName);
    this.updateRoute(routeName, {
      lastMeasurement: sanitizeFields({
        route: routeName,
        at: nowISO(this.clock),
        ...measurements,
      }),
    });
    this.persist();
  }

  recordEvent(event) {
    const clean = sanitizeFields({
      schema: "codexdock.observationEvent.v1",
      evidenceID: event.evidenceID || newID("evt"),
      at: event.at || nowISO(this.clock),
      relayHostID: this.host.id || null,
      ...event,
    });
    boundedPush(this.events, clean, this.maxEvents);
    return clean;
  }

  updateRoute(routeName, update) {
    const record = this.ensureRoute(routeName);
    const next = {
      ...record,
      configuredHostID: update.configuredHostID || record.configuredHostID || this.configuredHostID || null,
      relayHostID: update.relayHostID || record.relayHostID || this.host.id || null,
      routeStatus: update.routeStatus || record.routeStatus,
      statusReasons: update.statusReasons ?? record.statusReasons,
      lastAttempt: update.lastAttempt ?? record.lastAttempt,
      lastSuccess: update.lastSuccess !== undefined ? update.lastSuccess : record.lastSuccess,
      lastFailure: update.lastFailure !== undefined ? update.lastFailure : record.lastFailure,
      lastMeasurement: update.lastMeasurement ?? record.lastMeasurement,
      counters: {
        total: record.counters.total + (update.incrementSuccess || update.incrementFailure ? 1 : 0),
        succeeded: record.counters.succeeded + (update.incrementSuccess ? 1 : 0),
        failed: record.counters.failed + (update.incrementFailure ? 1 : 0),
      },
    };
    this.routes.set(routeName, sanitizeFields(next));
    return next;
  }

  ensureRoute(routeName) {
    if (!this.routes.has(routeName)) {
      this.routes.set(routeName, routeRecordFromConfig(routeConfigFor(routeName), this.host));
    }
    return this.routes.get(routeName);
  }

  routeHealth({ persistTimeouts = true } = {}) {
    const changed = this.applyActiveTimeouts();
    if (changed && persistTimeouts) {
      this.persist();
    }
    return [...this.routes.values()].sort((lhs, rhs) => lhs.route.localeCompare(rhs.route));
  }

  appCriticalFailures() {
    return this.routeHealth().filter((route) => route.appCritical && route.routeStatus === ROUTE_STATUS.FAILED);
  }

  applyActiveTimeouts() {
    const timeoutMs = this.activeRouteTimeoutMs;
    if (!Number.isFinite(timeoutMs) || timeoutMs <= 0) {
      return false;
    }
    let changed = false;
    const now = nowMs(this.clock);
    const at = nowISO(this.clock);
    for (const operation of this.activeOperations.values()) {
      const durationMs = Math.max(0, now - operation.startedAtMs);
      if (durationMs < timeoutMs) {
        continue;
      }
      let evidenceID = operation.timeoutEvidenceID || null;
      if (!evidenceID) {
        const event = this.recordEvent({
          operationID: operation.operationID,
          traceID: operation.traceID,
          route: operation.route,
          type: "route.failed",
          at,
          durationMs,
          outcome: "timed_out",
          failureCategory: FAILURE_CATEGORY.TIMEOUT,
          phase: "in-flight",
        });
        evidenceID = event.evidenceID;
        operation.timeoutEvidenceID = evidenceID;
        operation.timeoutCounted = false;
        const trace = this.traces.get(operation.operationID);
        if (trace) {
          trace.outcome = "timed_out";
          trace.durationMs = durationMs;
          trace.failureCategory = FAILURE_CATEGORY.TIMEOUT;
          trace.statusReasons = [statusReasonForTimeout({ evidenceID, timeoutMs, durationMs })];
          trace.events.push(event);
        }
      }
      this.updateRoute(operation.route, {
        configuredHostID: operation.configuredHostID,
        relayHostID: operation.relayHostID,
        routeStatus: ROUTE_STATUS.FAILED,
        statusReasons: [statusReasonForTimeout({ evidenceID, timeoutMs, durationMs })],
        lastAttempt: {
          operationID: operation.operationID,
          at,
          durationMs,
          outcome: "timed_out",
          failureCategory: FAILURE_CATEGORY.TIMEOUT,
          phase: "in-flight",
        },
        lastFailure: {
          operationID: operation.operationID,
          at,
          durationMs,
          outcome: "timed_out",
          failureCategory: FAILURE_CATEGORY.TIMEOUT,
          phase: "in-flight",
        },
        incrementFailure: operation.timeoutCounted !== true,
      });
      operation.timeoutCounted = true;
      changed = true;
    }
    return changed;
  }

  statusSnapshot() {
    return {
      schema: "codexdock.relayObservabilityStatus.v1",
      host: {
        id: this.host.id || null,
        displayName: this.host.displayName || null,
      },
      routes: this.routeHealth(),
      appCriticalFailures: this.appCriticalFailures(),
    };
  }

  metricsSnapshot() {
    const routes = this.routeHealth();
    const requests = routes.reduce((totals, route) => {
      totals.total += route.counters.total;
      totals.succeeded += route.counters.succeeded;
      totals.failed += route.counters.failed;
      totals.byMethod.push({
        method: route.route,
        total: route.counters.total,
        succeeded: route.counters.succeeded,
        failed: route.counters.failed,
        lastCode: route.lastFailure?.errorCode ?? null,
        lastDurationMs: route.lastAttempt?.durationMs ?? null,
        avgDurationMs: null,
        routeStatus: route.routeStatus,
      });
      return totals;
    }, {
      total: 0,
      succeeded: 0,
      failed: 0,
      byMethod: [],
    });
    requests.byMethod = requests.byMethod.filter((entry) => entry.total > 0);
    return {
      schema: "codexdock.relayObservabilityMetrics.v1",
      requests,
      routes: routes.map((route) => ({
        route: route.route,
        routeStatus: route.routeStatus,
        total: route.counters.total,
        succeeded: route.counters.succeeded,
        failed: route.counters.failed,
        appCritical: route.appCritical,
      })),
    };
  }

  recentTraces({ limit = 25 } = {}) {
    return [...this.traces.values()]
      .sort((lhs, rhs) => String(rhs.startedAt).localeCompare(String(lhs.startedAt)))
      .slice(0, Math.max(0, Math.min(limit, this.maxTraces)));
  }

  trace(operationID) {
    return this.traces.get(String(operationID || "")) || null;
  }

  bundle({ status = null, metrics = null, runtime = null } = {}) {
    return {
      schema: "codexdock.bundle.v1",
      createdAt: nowISO(this.clock),
      host: sanitizeFields({ host: this.host }).host,
      manifest: {
        omitted: [
          "prompts",
          "transcripts",
          "audio",
          "headers",
          "full-jsonrpc-payloads",
        ],
      },
      status,
      metrics,
      runtime,
      routes: this.routeHealth(),
      traces: this.recentTraces({ limit: 50 }),
      events: this.events.slice(-100),
    };
  }

  trimTraces() {
    const entries = [...this.traces.entries()]
      .sort((lhs, rhs) => String(rhs[1].startedAt).localeCompare(String(lhs[1].startedAt)));
    for (const [operationID] of entries.slice(this.maxTraces)) {
      this.traces.delete(operationID);
    }
  }

  persist() {
    if (!this.persistenceDir) {
      return;
    }
    try {
      fs.mkdirSync(this.persistenceDir, { recursive: true });
      writeJSONAtomic(path.join(this.persistenceDir, "route-health.json"), this.routeHealth({ persistTimeouts: false }));
      writeJSONAtomic(path.join(this.persistenceDir, "recent-traces.json"), this.recentTraces({ limit: this.maxTraces }));
      writeJSONAtomic(path.join(this.persistenceDir, "events.json"), this.events);
    } catch {
      // Observability persistence must not break the app path; live route health remains in memory.
    }
  }
}

function writeJSONAtomic(filename, value) {
  const temp = `${filename}.${process.pid}.${Date.now()}.tmp`;
  fs.writeFileSync(temp, `${JSON.stringify(value, null, 2)}\n`, "utf8");
  fs.renameSync(temp, filename);
}

function createRelayObservability(options = {}) {
  return new RelayObservability(options);
}

export {
  TRACE_PARAM_KEY,
  RelayObservability,
  createRelayObservability,
  extractTraceContextFromParams,
  measurementSummaryForResult,
};

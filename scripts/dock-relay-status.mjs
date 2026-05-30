import http from "node:http";
import https from "node:https";

import { HEALTH_TIMEOUT_MS } from "./dock-relay-constants.mjs";
import { sanitizeFields } from "./dock-relay-logger.mjs";

function sanitizedField(name, value) {
  return sanitizeFields({ [name]: value })[name];
}

function rawHealthURLForHistoryURL(historyUrl) {
  const url = new URL(historyUrl);
  url.protocol = url.protocol === "wss:" ? "https:" : "http:";
  url.pathname = "/readyz";
  url.search = "";
  url.hash = "";
  url.username = "";
  url.password = "";
  return url.toString();
}

function getJSON(url, timeoutMs = HEALTH_TIMEOUT_MS) {
  const client = url.startsWith("https:") ? https : http;
  return new Promise((resolve, reject) => {
    const request = client.get(url, { timeout: timeoutMs }, (response) => {
      const chunks = [];
      response.on("data", (chunk) => chunks.push(chunk));
      response.on("end", () => {
        const body = Buffer.concat(chunks).toString("utf8");
        let parsed = null;
        if (body) {
          try {
            parsed = JSON.parse(body);
          } catch {
            parsed = null;
          }
        }
        resolve({
          statusCode: response.statusCode,
          ok: response.statusCode >= 200 && response.statusCode < 300,
          body: parsed,
        });
      });
    });
    request.on("timeout", () => {
      request.destroy(new Error(`timed out after ${timeoutMs}ms`));
    });
    request.on("error", reject);
  });
}

function safeErrorSummary(error, extra = {}) {
  return sanitizeFields({
    ...extra,
    message: error?.message || String(error),
    code: error?.code || null,
  });
}

function projectLiveStatus(liveStatus = null) {
  const overlay = liveStatus?.liveOverlay || null;
  return sanitizeFields({
    checkedAt: liveStatus?.checkedAt || null,
    status: liveStatus?.status || "unknown",
    ok: liveStatus?.ok ?? null,
    ageMs: overlay?.ageMs ?? null,
    overlayState: overlay?.state || null,
    endpoints: Array.isArray(liveStatus?.endpoints) ? liveStatus.endpoints.length : 0,
    failedEndpoints: liveStatus?.failedEndpoints || 0,
    rows: Array.isArray(liveStatus?.rows) ? liveStatus.rows.length : 0,
    error: liveStatus?.error || null,
  });
}

function createRelayStatusTracker({ clock = () => new Date() } = {}) {
  const startedAt = clock();
  let lastRawAppServerHealth = {
    checkedAt: null,
    status: "unknown",
    ok: null,
  };
  let lastLiveDiscoveryResult = {
    checkedAt: null,
    status: "unknown",
    ok: null,
  };
  let lastUpstreamError = null;
  let lastClientFacingError = null;
  let lastTranscriptionError = null;
  let reconnect = {
    active: false,
    attempts: 0,
    nextRetryAt: null,
  };
  const requests = {
    total: 0,
    succeeded: 0,
    failed: 0,
    byMethod: new Map(),
  };

  function timestamp() {
    const value = clock();
    return value instanceof Date ? value.toISOString() : new Date(value).toISOString();
  }

  function recordRawHealth(result) {
    lastRawAppServerHealth = {
      checkedAt: timestamp(),
      ...sanitizeFields(result),
    };
  }

  function recordLiveDiscovery(result) {
    lastLiveDiscoveryResult = {
      checkedAt: timestamp(),
      ...sanitizeFields(result),
    };
  }

  function recordUpstreamError(error, context = {}) {
    lastUpstreamError = {
      at: timestamp(),
      ...safeErrorSummary(error, context),
    };
  }

  function recordClientFacingError(error, context = {}) {
    lastClientFacingError = {
      at: timestamp(),
      ...safeErrorSummary(error, context),
    };
  }

  function recordTranscriptionError(error, context = {}) {
    lastTranscriptionError = {
      at: timestamp(),
      ...safeErrorSummary(error, context),
    };
  }

  function recordReconnect({ active, attempts, nextRetryAt = null }) {
    reconnect = sanitizeFields({
      active: Boolean(active),
      attempts: Number(attempts || 0),
      nextRetryAt,
    });
  }

  function recordRequest({ method, ok, code = null, durationMs = null }) {
    const key = String(method || "unknown");
    const existing = requests.byMethod.get(key) || {
      method: key,
      total: 0,
      succeeded: 0,
      failed: 0,
      lastCode: null,
      lastDurationMs: null,
      totalDurationMs: 0,
    };
    existing.total += 1;
    existing.lastCode = code;
    existing.lastDurationMs = Number.isFinite(durationMs) ? Math.max(0, Math.floor(durationMs)) : null;
    if (existing.lastDurationMs !== null) {
      existing.totalDurationMs += existing.lastDurationMs;
    }
    if (ok) {
      existing.succeeded += 1;
      requests.succeeded += 1;
    } else {
      existing.failed += 1;
      requests.failed += 1;
    }
    requests.total += 1;
    requests.byMethod.set(key, existing);
  }

  function requestMetrics() {
    const byMethod = [...requests.byMethod.values()]
      .sort((lhs, rhs) => lhs.method.localeCompare(rhs.method))
      .map((entry) => ({
        method: entry.method,
        total: entry.total,
        succeeded: entry.succeeded,
        failed: entry.failed,
        lastCode: entry.lastCode,
        lastDurationMs: entry.lastDurationMs,
        avgDurationMs: entry.total > 0 ? Math.round(entry.totalDurationMs / entry.total) : null,
      }));
    return {
      total: requests.total,
      succeeded: requests.succeeded,
      failed: requests.failed,
      byMethod,
    };
  }

  function uptimeSeconds() {
    const now = clock();
    const nowMs = now instanceof Date ? now.getTime() : new Date(now).getTime();
    const startedMs = startedAt instanceof Date ? startedAt.getTime() : new Date(startedAt).getTime();
    return Math.max(0, Math.floor((nowMs - startedMs) / 1000));
  }

  function snapshot(config, runtime = {}) {
    const endpointHost = (() => {
      try {
        return new URL(config.openAIRealtimeTranscriptionEndpoint).hostname;
      } catch {
        return null;
      }
    })();
    const observability = config.observability?.statusSnapshot?.() || null;
    const snapshot = sanitizeFields({
      ok: true,
      service: "codex-dock-relay",
      version: config.version,
      host: {
        id: config.hostId || null,
        relayInstanceID: config.hostId || null,
        displayName: config.hostName || config.bonjourName || null,
      },
      uptimeSeconds: uptimeSeconds(),
      listen: {
        host: config.listenHost,
        port: config.port,
      },
      history: {
        url: config.historyUrl,
        lastHealth: lastRawAppServerHealth,
      },
      auth: {
        phoneAuth: config.phoneAuth,
        relayCredentialConfigured: Boolean(config.relayBearerToken),
        historyCredentialConfigured: Boolean(config.historyBearerToken),
      },
      transcription: {
        enabled: Boolean(config.openAIAPIKey),
        model: config.openAIRealtimeTranscriptionModel || null,
        endpointHost,
        keyPresent: Boolean(config.openAIAPIKey),
        lastError: lastTranscriptionError,
      },
      liveDiscovery: lastLiveDiscoveryResult,
      liveStatus: projectLiveStatus(runtime.liveStatus),
      connections: {
        downstreamActive: runtime.downstreamActive || 0,
        upstreamActive: runtime.upstreamActive || 0,
        upstreamPools: Array.isArray(runtime.upstreamPools) ? runtime.upstreamPools : [],
      },
      errors: {
        lastUpstreamError,
        lastClientFacingError,
      },
      reconnect,
    });
    snapshot.routes = observability?.routes || [];
    snapshot.appCriticalFailures = observability?.appCriticalFailures || [];
    return snapshot;
  }

  function metricsSnapshot(config, runtime = {}) {
    const observabilityMetrics = config.observability?.metricsSnapshot?.() || null;
    const snapshot = sanitizeFields({
      ok: true,
      service: "codex-dock-relay",
      version: config.version,
      host: {
        id: config.hostId || null,
        relayInstanceID: config.hostId || null,
        displayName: config.hostName || config.bonjourName || null,
      },
      uptimeSeconds: uptimeSeconds(),
      history: {
        lastHealthStatus: lastRawAppServerHealth.status,
        lastHealthOK: lastRawAppServerHealth.ok,
      },
      liveStatus: projectLiveStatus(runtime.liveStatus),
      connections: {
        downstreamActive: runtime.downstreamActive || 0,
        upstreamActive: runtime.upstreamActive || 0,
        upstreamPools: Array.isArray(runtime.upstreamPools) ? runtime.upstreamPools : [],
      },
      requests: observabilityMetrics?.requests || requestMetrics(),
      reconnect,
    });
    snapshot.routeMetrics = observabilityMetrics?.routes || [];
    return snapshot;
  }

  function debugSessionsSnapshot(config, runtime = {}) {
    const traces = config.observability?.recentTraces?.({ limit: 10 }) || [];
    return sanitizeFields({
      ok: true,
      service: "codex-dock-relay",
      version: config.version,
      host: {
        id: config.hostId || null,
        relayInstanceID: config.hostId || null,
        displayName: config.hostName || config.bonjourName || null,
      },
      liveStatus: projectLiveStatus(runtime.liveStatus),
      liveRows: Array.isArray(runtime.liveRows) ? runtime.liveRows : [],
      sessions: Array.isArray(runtime.sessions) ? runtime.sessions : [],
      connections: {
        downstreamActive: runtime.downstreamActive || 0,
        upstreamActive: runtime.upstreamActive || 0,
        upstreamPools: Array.isArray(runtime.upstreamPools) ? runtime.upstreamPools : [],
      },
      errors: {
        lastUpstreamError,
        lastClientFacingError,
      },
      reconnect,
      recentOperationIDs: traces.map((trace) => trace.operationID).filter(Boolean),
    });
  }

  return {
    debugSessionsSnapshot,
    metricsSnapshot,
    recordClientFacingError,
    recordLiveDiscovery,
    recordRawHealth,
    recordRequest,
    recordReconnect,
    recordTranscriptionError,
    recordUpstreamError,
    snapshot,
  };
}

async function checkRawAppServerHealth(config, tracker) {
  const healthURL = rawHealthURLForHistoryURL(config.historyUrl);
  try {
    const result = await getJSON(healthURL);
    tracker.recordRawHealth({
      status: result.ok ? "up" : "down",
      ok: result.ok,
      statusCode: result.statusCode,
      url: healthURL,
    });
  } catch (error) {
    tracker.recordRawHealth({
      status: "down",
      ok: false,
      url: healthURL,
      error,
    });
  }
}

function classifyRelayRequestError(method, error) {
  if (error?.code === -32001) {
    return {
      subsystem: "upstream-overload",
      retryable: true,
      overload: true,
    };
  }
  if (error?.data?.subsystem) {
    return {
      ...error.data,
      retryable: error.data.retryable ?? error.code !== -32602,
    };
  }
  if (method === "thread/list" || method === "thread/search" || method === "thread/read"
    || method === "thread/turns/list" || method === "thread/goal/get"
    || method === "thread/archive" || method === "thread/unarchive") {
    return {
      subsystem: "history",
      retryable: true,
    };
  }
  if (method === "thread/resume" || method === "turn/start" || method === "turn/steer" || method === "turn/interrupt") {
    return {
      subsystem: "live-upstream",
      retryable: true,
    };
  }
  if (String(method || "").startsWith("audio/transcription/")) {
    return {
      subsystem: "transcription",
      retryable: error?.code !== -32602,
    };
  }
  return undefined;
}

export {
  checkRawAppServerHealth,
  classifyRelayRequestError,
  createRelayStatusTracker,
  projectLiveStatus,
  rawHealthURLForHistoryURL,
  sanitizedField,
};

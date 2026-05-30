import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import {
  DOCK_SESSION_CLIENT_BUFFER_LIMIT_BYTES,
  DOCK_SESSION_INITIAL_REFRESH_TIMEOUT_MS,
  DOCK_SESSION_PERSISTENCE_FILE,
  DOCK_SESSION_REFRESH_INTERVAL_MS,
  DOCK_SESSION_SCHEMA_VERSION,
  DOCK_SESSION_TEXT_MAX_BYTES,
  DOCK_SESSION_TITLE_MAX_BYTES,
  THREAD_LIST_MAX_LIMIT,
} from "./dock-relay-constants.mjs";
import { ROUTE_NAMES } from "./dock-relay-observability-contract.mjs";
import {
  aggregateThreadList,
  liveStatusCacheForConfig,
  preferThread,
  sanitizeRelayFields,
} from "./dock-relay-thread-data.mjs";

const DOCK_SUBSCRIBE_METHOD = "dock/subscribe";
const DOCK_RESYNC_METHOD = "dock/resync";
const DOCK_UPDATE_METHOD = "dock/update";

const AGENT_SOURCE_KINDS = Object.freeze([
  "exec",
  "appServer",
  "subAgent",
  "subAgentReview",
  "subAgentCompact",
  "subAgentThreadSpawn",
  "subAgentOther",
  "unknown",
]);
const DOCK_EXPLICIT_SOURCE_KINDS = Object.freeze([
  "cli",
  "vscode",
  ...AGENT_SOURCE_KINDS,
]);

function nowISOString() {
  return new Date().toISOString();
}

function nonEmpty(value) {
  if (typeof value !== "string") {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function optionalNumber(value) {
  if (value === null || value === undefined || value === "") {
    return null;
  }
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function truncateText(value, maxBytes) {
  const text = nonEmpty(value);
  if (!text) {
    return null;
  }
  if (Buffer.byteLength(text, "utf8") <= maxBytes) {
    return text;
  }
  const suffix = " [truncated]";
  const suffixBytes = Buffer.byteLength(suffix, "utf8");
  const budget = Math.max(0, maxBytes - suffixBytes);
  const chars = Array.from(text);
  let low = 0;
  let high = chars.length;
  while (low < high) {
    const mid = Math.ceil((low + high) / 2);
    if (Buffer.byteLength(chars.slice(0, mid).join(""), "utf8") <= budget) {
      low = mid;
    } else {
      high = mid - 1;
    }
  }
  return `${chars.slice(0, low).join("")}${suffix}`;
}

function sortedJSONString(value) {
  return JSON.stringify(sortJSON(value));
}

function sortJSON(value) {
  if (Array.isArray(value)) {
    return value.map(sortJSON);
  }
  if (value && typeof value === "object") {
    return Object.keys(value).sort().reduce((result, key) => {
      result[key] = sortJSON(value[key]);
      return result;
    }, {});
  }
  return value;
}

function publicHostFromConfig(config) {
  return {
    id: config.hostId || os.hostname(),
    displayName: config.hostName || config.hostId || os.hostname(),
    endpoint: config.hostEndpoint || null,
  };
}

function persistencePath(config) {
  if (config.dockSessionPersistencePath) {
    return config.dockSessionPersistencePath;
  }
  return path.resolve(process.cwd(), DOCK_SESSION_PERSISTENCE_FILE);
}

function readLastGood(pathname) {
  if (!pathname || !fs.existsSync(pathname)) {
    return null;
  }
  try {
    const parsed = JSON.parse(fs.readFileSync(pathname, "utf8"));
    if (parsed?.schemaVersion !== DOCK_SESSION_SCHEMA_VERSION) {
      return null;
    }
    if (!Array.isArray(parsed?.hosts) || !Array.isArray(parsed?.sessions)) {
      return null;
    }
    return parsed;
  } catch {
    return null;
  }
}

function writeLastGoodAtomic(pathname, snapshot) {
  if (!pathname) {
    return;
  }
  fs.mkdirSync(path.dirname(pathname), { recursive: true });
  const tempPath = `${pathname}.${process.pid}.${Date.now()}.tmp`;
  fs.writeFileSync(tempPath, `${JSON.stringify(snapshot, null, 2)}\n`, "utf8");
  fs.renameSync(tempPath, pathname);
}

function lastGoodAvailable(pathname) {
  return Boolean(pathname && fs.existsSync(pathname));
}

function laneForScope(scope) {
  return scope === "automation" ? "agent" : "human";
}

function kindLabelForThread(thread, scope) {
  return nonEmpty(thread?.sourceKind)
    || nonEmpty(thread?.source)
    || (scope === "automation" ? "Agent" : "Human");
}

function sourceKindFromThread(thread, scope) {
  if (scope === "automation") {
    return "automation";
  }
  if (scope === "human") {
    return "human";
  }
  return "unknown";
}

function normalizedStatus(thread) {
  const status = thread?.status;
  if (status?.type === "active") {
    const flags = new Set(status.activeFlags || []);
    if (flags.has("waitingOnApproval")) {
      return "needsApproval";
    }
    if (flags.has("waitingOnUserInput")) {
      return "needsInput";
    }
    return "running";
  }
  switch (status?.type) {
    case "idle":
      return "idle";
    case "systemError":
      return "error";
    case "notLoaded":
      return "dormant";
    default:
      return "unknown";
  }
}

function titleForThread(thread) {
  return nonEmpty(thread?.name)
    || nonEmpty(thread?.preview)
    || nonEmpty(thread?.cwd?.split("/").filter(Boolean).at(-1))
    || (nonEmpty(thread?.id) ? `Thread ${thread.id.slice(0, 8)}` : "Thread");
}

function repositoryForThread(thread) {
  const originURL = nonEmpty(thread?.gitInfo?.originUrl);
  if (originURL) {
    const pieces = originURL.split(/[/:]/).filter(Boolean);
    const last = pieces.at(-1);
    if (last) {
      return last.endsWith(".git") ? last.slice(0, -4) : last;
    }
  }
  return nonEmpty(thread?.cwd?.split("/").filter(Boolean).at(-1));
}

function normalizeThread(thread, host, scope) {
  const threadID = nonEmpty(thread?.id);
  if (!threadID) {
    return null;
  }
  const sessionID = nonEmpty(thread?.sessionId) || threadID;
  const updatedAt = optionalNumber(thread?.updatedAt ?? thread?.createdAt) ?? 0;
  const sourceKind = sourceKindFromThread(thread, scope);
  return sanitizeDockSession({
    id: `${host.id}::${threadID}`,
    hostID: host.id,
    threadID,
    backendSessionID: sessionID,
    title: titleForThread(thread),
    status: normalizedStatus(thread),
    lane: laneForScope(scope),
    kindLabel: kindLabelForThread(thread, scope),
    repository: repositoryForThread(thread),
    workingDirectory: nonEmpty(thread?.cwd) || nonEmpty(thread?.path),
    branch: nonEmpty(thread?.gitInfo?.branch),
    updatedAt,
    summary: nonEmpty(thread?.latestSummary) || nonEmpty(thread?.preview) || titleForThread(thread),
    messageSummary: nonEmpty(thread?.messageSummary),
    messageUpdatedAt: optionalNumber(thread?.messageUpdatedAt),
    source: {
      kind: sourceKind,
    },
  });
}

function sanitizeDockSession(session) {
  if (!session || typeof session !== "object" || Array.isArray(session)) {
    return null;
  }
  const id = nonEmpty(session.id);
  const hostID = nonEmpty(session.hostID);
  const threadID = nonEmpty(session.threadID);
  const backendSessionID = nonEmpty(session.backendSessionID) || threadID;
  if (!id || !hostID || !threadID || !backendSessionID) {
    return null;
  }
  const sourceKind = nonEmpty(session.source?.kind) || "unknown";
  return {
    id,
    hostID,
    threadID,
    backendSessionID,
    title: truncateText(session.title, DOCK_SESSION_TITLE_MAX_BYTES) || `Thread ${threadID.slice(0, 8)}`,
    status: nonEmpty(session.status) || "unknown",
    lane: nonEmpty(session.lane) || "agent",
    kindLabel: truncateText(session.kindLabel, DOCK_SESSION_TITLE_MAX_BYTES),
    repository: truncateText(session.repository, DOCK_SESSION_TITLE_MAX_BYTES),
    workingDirectory: truncateText(session.workingDirectory, DOCK_SESSION_TEXT_MAX_BYTES),
    branch: truncateText(session.branch, DOCK_SESSION_TITLE_MAX_BYTES),
    updatedAt: optionalNumber(session.updatedAt) ?? 0,
    summary: truncateText(session.summary, DOCK_SESSION_TEXT_MAX_BYTES),
    messageSummary: truncateText(session.messageSummary, DOCK_SESSION_TEXT_MAX_BYTES),
    messageUpdatedAt: optionalNumber(session.messageUpdatedAt),
    source: {
      kind: sourceKind,
    },
  };
}

function waitForRefreshOrTimeout(promise, timeoutMs) {
  return new Promise((resolve) => {
    let settled = false;
    const timer = setTimeout(() => {
      if (!settled) {
        settled = true;
        resolve(false);
      }
    }, timeoutMs);
    timer.unref?.();
    promise.then(
      () => {
        if (!settled) {
          settled = true;
          clearTimeout(timer);
          resolve(true);
        }
      },
      () => {
        if (!settled) {
          settled = true;
          clearTimeout(timer);
          resolve(true);
        }
      },
    );
  });
}

function normalizedSourceName(value) {
  return String(value || "").trim().toLowerCase().replace(/[^a-z0-9]/g, "");
}

function sourceNameFromThread(thread) {
  const source = thread?.source;
  if (typeof source === "string") {
    return normalizedSourceName(source);
  }
  if (!source || typeof source !== "object" || Array.isArray(source)) {
    return "";
  }
  for (const key of ["type", "kind", "sourceKind", "source_kind", "source"]) {
    if (typeof source[key] === "string") {
      return normalizedSourceName(source[key]);
    }
  }
  for (const key of Object.keys(source)) {
    const normalized = normalizedSourceName(key);
    if (normalized) {
      return normalized;
    }
  }
  return "";
}

function dockLaneForThread(thread, fallbackLane = "automation") {
  switch (sourceNameFromThread(thread)) {
    case "cli":
    case "vscode":
    case "atlas":
    case "chatgpt":
      return "human";
    default:
      return fallbackLane;
  }
}

function overlayLiveStatus(storedRow, liveRow) {
  if (!liveRow?.status) {
    return storedRow;
  }
  const cleanLiveRow = sanitizeRelayFields(liveRow);
  return {
    ...storedRow,
    sessionId: nonEmpty(cleanLiveRow.sessionId) || storedRow.sessionId,
    status: cleanLiveRow.status,
  };
}

function orderedDockRows(primaryRows, interactiveRows, liveRows = []) {
  const byThreadID = new Map();
  const liveRowsByID = new Map(liveRows.map((row) => [row?.id, row]).filter(([id]) => id));
  const orderedThreadIDs = [];
  const addRow = (row, lane) => {
    if (!row?.id) {
      return;
    }
    const liveRow = liveRowsByID.get(row.id);
    const rowWithLiveStatus = liveRow ? overlayLiveStatus(row, liveRow) : row;
    const existing = byThreadID.get(row.id);
    if (!existing) {
      orderedThreadIDs.push(row.id);
      byThreadID.set(row.id, { lane, row: rowWithLiveStatus });
      return;
    }
    byThreadID.set(row.id, {
      lane: existing.lane,
      row: preferThread(rowWithLiveStatus, existing.row),
    });
  };

  for (const row of primaryRows) {
    addRow(row, dockLaneForThread(row));
  }
  for (const row of interactiveRows) {
    addRow(row, "human");
  }
  return orderedThreadIDs.map((threadID) => byThreadID.get(threadID)).filter(Boolean);
}

async function fetchDockLiveRows(config) {
  try {
    const snapshot = await liveStatusCacheForConfig(config).snapshotForRouting();
    return Array.isArray(snapshot.rows) ? snapshot.rows : [];
  } catch (error) {
    config.logger?.warn?.("dock.live_status_overlay_failed", { error });
    return [];
  }
}

async function fetchDockSessionRows(config) {
  const baseParams = {
    archived: false,
    limit: THREAD_LIST_MAX_LIMIT,
    sortKey: "updated_at",
    sortDirection: "desc",
    modelProviders: [],
  };
  const [primaryRows, interactiveRows, liveRows] = await Promise.all([
    fetchDockThreadListRows(config, {
      ...baseParams,
      sourceKinds: DOCK_EXPLICIT_SOURCE_KINDS,
    }),
    fetchDockThreadListRows(config, baseParams),
    fetchDockLiveRows(config),
  ]);
  return orderedDockRows(primaryRows, interactiveRows, liveRows);
}

async function fetchDockThreadListRows(config, params) {
  let cursor = params.cursor || null;
  const rows = [];
  const seenCursors = new Set();
  while (true) {
    const request = cursor ? { ...params, cursor } : { ...params };
    const response = await aggregateThreadList(config, request);
    if (Array.isArray(response?.data)) {
      rows.push(...response.data);
    }
    const nextCursor = response?.nextCursor || null;
    if (!nextCursor) {
      break;
    }
    const cursorKey = JSON.stringify(nextCursor);
    if (seenCursors.has(cursorKey)) {
      throw new Error(`thread/list returned repeated cursor while refreshing dock sessions: ${cursorKey}`);
    }
    seenCursors.add(cursorKey);
    cursor = nextCursor;
  }
  return rows;
}

class CodexDockSessionProvider {
  constructor(config) {
    this.config = config;
  }

  async listSessions() {
    const host = publicHostFromConfig(this.config);
    const rows = await fetchDockSessionRows(this.config);
    const sessions = rows
      .map(({ row, lane }) => normalizeThread(row, host, lane))
      .filter(Boolean);
    return { host, sessions };
  }
}

class DockSessionTable {
  constructor(config, options = {}) {
    this.schemaVersion = DOCK_SESSION_SCHEMA_VERSION;
    this.epoch = options.epoch || crypto.randomUUID();
    this.seq = 0;
    this.asOf = null;
    this.hostsByID = new Map();
    this.sessionsByID = new Map();
    this.freshness = {
      status: "unknown",
      lastAttemptAt: null,
      lastSyncAt: null,
      lastError: null,
    };

    const loaded = options.lastGood || null;
    if (loaded) {
      this.asOf = loaded.asOf || null;
      for (const host of loaded.hosts || []) {
        if (host?.id) {
          this.hostsByID.set(host.id, host);
        }
      }
      for (const session of loaded.sessions || []) {
        const sanitized = sanitizeDockSession(session);
        if (sanitized?.id) {
          this.sessionsByID.set(sanitized.id, sanitized);
        }
      }
      this.freshness = {
        status: "stale",
        lastAttemptAt: null,
        lastSyncAt: loaded.asOf || null,
        lastError: null,
      };
    }

    const host = publicHostFromConfig(config);
    this.hostsByID.set(host.id, {
      ...(this.hostsByID.get(host.id) || {}),
      ...host,
    });
  }

  snapshot() {
    return {
      kind: "snapshot",
      schemaVersion: this.schemaVersion,
      epoch: this.epoch,
      seq: this.seq,
      asOf: this.asOf,
      freshness: this.freshness,
      hosts: [...this.hostsByID.values()].sort((lhs, rhs) => String(lhs.id).localeCompare(String(rhs.id))),
      sessions: [...this.sessionsByID.values()],
    };
  }

  applySuccessfulRefresh({ host, sessions, asOf = nowISOString() }) {
    const previousSeq = this.seq;
    const previousSessions = new Map(this.sessionsByID);
    const previousHosts = new Map(this.hostsByID);
    const normalizedSessions = sessions.map(sanitizeDockSession).filter(Boolean);
    const nextSessions = new Map(normalizedSessions.map((session) => [session.id, session]));
    const nextHosts = new Map([[host.id, host]]);
    const upsertHosts = [];
    const upsertSessions = [];
    const deleteSessionIDs = [];

    for (const [id, value] of nextHosts) {
      if (sortedJSONString(previousHosts.get(id)) !== sortedJSONString(value)) {
        upsertHosts.push(value);
      }
    }

    for (const [id, value] of nextSessions) {
      if (sortedJSONString(previousSessions.get(id)) !== sortedJSONString(value)) {
        upsertSessions.push(value);
      }
    }

    for (const id of previousSessions.keys()) {
      if (!nextSessions.has(id)) {
        deleteSessionIDs.push(id);
      }
    }

    this.hostsByID = nextHosts;
    this.sessionsByID = nextSessions;
    this.asOf = asOf;
    this.freshness = {
      status: "fresh",
      lastAttemptAt: asOf,
      lastSyncAt: asOf,
      lastError: null,
    };

    if (upsertHosts.length === 0 && upsertSessions.length === 0 && deleteSessionIDs.length === 0) {
      return this.heartbeat();
    }

    this.seq += 1;
    return {
      kind: "delta",
      schemaVersion: this.schemaVersion,
      epoch: this.epoch,
      baseSeq: previousSeq,
      seq: this.seq,
      asOf,
      freshness: this.freshness,
      upsertHosts,
      upsertSessions,
      deleteSessionIDs,
    };
  }

  applyFailedRefresh(error) {
    const attemptedAt = nowISOString();
    this.freshness = {
      status: "stale",
      lastAttemptAt: attemptedAt,
      lastSyncAt: this.freshness.lastSyncAt,
      lastError: error?.message || String(error),
    };
    return this.heartbeat();
  }

  heartbeat() {
    return {
      kind: "heartbeat",
      schemaVersion: this.schemaVersion,
      epoch: this.epoch,
      seq: this.seq,
      asOf: this.asOf,
      freshness: this.freshness,
    };
  }
}

class DockSessionAggregator {
  constructor(config, options = {}) {
    this.config = config;
    this.logger = config.logger;
    this.provider = options.provider
      ?? config.dockSessionProvider
      ?? new CodexDockSessionProvider(config);
    this.refreshIntervalMs = options.refreshIntervalMs
      ?? config.dockSessionRefreshIntervalMs
      ?? DOCK_SESSION_REFRESH_INTERVAL_MS;
    this.persistencePath = options.persistencePath ?? persistencePath(config);
    this.table = new DockSessionTable(config, {
      lastGood: readLastGood(this.persistencePath),
    });
    this.subscribers = new Set();
    this.refreshTimer = null;
    this.refreshPromise = null;
    this.started = false;
  }

  start() {
    if (this.started) {
      return;
    }
    this.started = true;
    this.refreshPromise = this.refreshNow({ notify: true });
    this.refreshTimer = setInterval(() => {
      this.refreshNow({ notify: true }).catch((error) => {
        this.logger?.warn?.("dock.session_refresh_failed", { error });
      });
    }, this.refreshIntervalMs);
    this.refreshTimer.unref?.();
  }

  stop() {
    if (this.refreshTimer) {
      clearInterval(this.refreshTimer);
      this.refreshTimer = null;
    }
    this.subscribers.clear();
    this.started = false;
  }

  subscribe(listener) {
    this.subscribers.add(listener);
    this.start();
    return () => {
      this.subscribers.delete(listener);
    };
  }

  async snapshot() {
    this.start();
    const refresh = this.refreshNow({ notify: false }).catch(() => {});
    const refreshCompleted = await waitForRefreshOrTimeout(
      refresh,
      this.config.dockSessionInitialRefreshTimeoutMs ?? DOCK_SESSION_INITIAL_REFRESH_TIMEOUT_MS,
    );
    if (!refreshCompleted) {
      this.logger?.warn?.("dock.session_snapshot_refresh_timeout", {
        timeoutMs: this.config.dockSessionInitialRefreshTimeoutMs ?? DOCK_SESSION_INITIAL_REFRESH_TIMEOUT_MS,
        rows: this.table.snapshot().sessions.length,
        freshness: this.table.snapshot().freshness.status,
      });
    }
    return this.table.snapshot();
  }

  currentSnapshot() {
    return this.table.snapshot();
  }

  async resync() {
    await this.refreshNow({ notify: false });
    this.config.observability?.recordMeasurement?.(ROUTE_NAMES.dockResync, {
      phase: "refresh",
      outcome: "succeeded",
      rows: this.table.snapshot().sessions.length,
      lastGoodAvailable: lastGoodAvailable(this.persistencePath),
      subscriberCount: this.subscribers.size,
    });
    return this.table.snapshot();
  }

  async refreshNow({ notify }) {
    if (this.refreshPromise) {
      return this.refreshPromise;
    }
    this.refreshPromise = this.performRefresh({ notify }).finally(() => {
      this.refreshPromise = null;
    });
    return this.refreshPromise;
  }

  async performRefresh({ notify }) {
    let update;
    try {
      const { host, sessions } = await this.provider.listSessions();
      update = this.table.applySuccessfulRefresh({
        host,
        sessions,
        asOf: nowISOString(),
      });
      writeLastGoodAtomic(this.persistencePath, this.table.snapshot());
      this.logger?.info?.("dock.session_refresh_succeeded", {
        hostId: host.id,
        rows: sessions.length,
        updateKind: update.kind,
        seq: update.seq,
      });
      this.config.observability?.recordMeasurement?.(ROUTE_NAMES.dockSubscribe, {
        phase: "refresh",
        outcome: "succeeded",
        rows: sessions.length,
        updateKind: update.kind,
        seq: update.seq,
        lastGoodAvailable: lastGoodAvailable(this.persistencePath),
        subscriberCount: this.subscribers.size,
      });
    } catch (error) {
      update = this.table.applyFailedRefresh(error);
      this.logger?.warn?.("dock.session_refresh_failed", {
        error,
        seq: update.seq,
      });
      this.config.observability?.recordMeasurement?.(ROUTE_NAMES.dockSubscribe, {
        phase: "refresh",
        outcome: "failed",
        seq: update.seq,
        lastGoodAvailable: lastGoodAvailable(this.persistencePath),
        subscriberCount: this.subscribers.size,
        failureCategory: "history",
      });
    }

    if (notify) {
      this.notify(update);
    }
    return update;
  }

  notify(update) {
    for (const listener of this.subscribers) {
      try {
        listener(update);
      } catch (error) {
        this.logger?.warn?.("dock.session_subscriber_failed", { error });
      }
    }
  }
}

function dockUpdateForSubscriber(aggregator, downstreamWs, update) {
  if (Number(downstreamWs?.bufferedAmount || 0) > DOCK_SESSION_CLIENT_BUFFER_LIMIT_BYTES) {
    return aggregator.currentSnapshot();
  }
  return update;
}

function bufferedDockUpdateIsAfterSnapshot(snapshot, update) {
  if (!snapshot || !update) {
    return false;
  }
  if (update.epoch !== snapshot.epoch) {
    return false;
  }
  return Number(update.seq || 0) > Number(snapshot.seq || 0);
}

async function handleDockSubscribe({ config, session, downstreamWs, sendJson }) {
  session.dockUnsubscribe?.();
  session.dockUnsubscribe = null;
  const aggregator = dockSessionAggregatorForConfig(config);
  config.observability?.recordMeasurement?.(DOCK_SUBSCRIBE_METHOD, {
    phase: "subscribe",
    subscriberCount: aggregator.subscribers?.size || 0,
  });
  let subscriptionReady = false;
  const bufferedUpdates = [];
  const sendDockUpdate = (update) => {
    config.observability?.recordNotification?.(DOCK_UPDATE_METHOD, {
      measurements: {
        phase: "notify",
        updateKind: update?.kind || null,
        seq: update?.seq ?? null,
        subscriberCount: aggregator.subscribers?.size || 0,
      },
    });
    sendJson(downstreamWs, {
      jsonrpc: "2.0",
      method: DOCK_UPDATE_METHOD,
      params: dockUpdateForSubscriber(aggregator, downstreamWs, update),
    });
  };
  session.dockUnsubscribe = aggregator.subscribe((update) => {
    if (!subscriptionReady) {
      bufferedUpdates.push(update);
      return;
    }
    sendDockUpdate(update);
  });
  try {
    const snapshot = await aggregator.snapshot();
    subscriptionReady = true;
    for (const update of bufferedUpdates) {
      if (bufferedDockUpdateIsAfterSnapshot(snapshot, update)) {
        sendDockUpdate(update);
      }
    }
    bufferedUpdates.length = 0;
    return snapshot;
  } catch (error) {
    session.dockUnsubscribe?.();
    session.dockUnsubscribe = null;
    throw error;
  }
}

function dockSessionAggregatorForConfig(config) {
  if (!config.dockSessionAggregator) {
    config.dockSessionAggregator = new DockSessionAggregator(config);
  }
  return config.dockSessionAggregator;
}

export {
  DOCK_RESYNC_METHOD,
  DOCK_SUBSCRIBE_METHOD,
  DOCK_UPDATE_METHOD,
  CodexDockSessionProvider,
  DockSessionAggregator,
  DockSessionTable,
  bufferedDockUpdateIsAfterSnapshot,
  dockSessionAggregatorForConfig,
  dockUpdateForSubscriber,
  handleDockSubscribe,
  normalizeThread,
  normalizedStatus,
  orderedDockRows,
};

import fs from "node:fs";
import path from "node:path";

import { defaultRelayLogger } from "./dock-relay-logger.mjs";
import {
  HUMAN_THREAD_INDEX_SUPPLEMENT_LIMIT,
  HUMAN_THREAD_READ_ENRICHMENT_CONCURRENCY,
  LIVE_LOADED_LIST_LIMIT,
  LIVE_STATUS_UPSTREAM_TIMEOUT_MS,
  RELAY_VERSION,
  THREAD_LIST_MAX_LIMIT,
  UPSTREAM_POOL_LIMITS,
} from "./dock-relay-constants.mjs";
import { JsonRpcWebSocketClient } from "./dock-relay-json-rpc-client.mjs";
import { LiveStatusCache, SessionRouter } from "./dock-relay-live-status-cache.mjs";
import { latestMeaningfulMessageFromTurns } from "./dock-relay-thread-summary.mjs";
import { UpstreamConnectionPool } from "./dock-relay-upstream-pool.mjs";
import {
  classifyThreadOrigin,
  humanThreadRejectedError,
  isHumanAppFacingCard,
  isHumanStartedThread,
} from "./dock-relay-human-thread-filter.mjs";
import {
  timestampToISO,
  timestampToMs,
} from "./dock-relay-state-views.mjs";

function relayLogger(config) {
  return config?.logger || defaultRelayLogger;
}

function upstreamNotificationCallback(config, source = {}) {
  const handler = config?.upstreamNotificationHandler;
  return typeof handler === "function"
    ? (message) => handler(message, source)
    : null;
}

function upstreamPoolForConfig(config) {
  if (!config.upstreamPool) {
    config.upstreamPool = new UpstreamConnectionPool({
      logger: relayLogger(config),
      maxOpenByLabel: UPSTREAM_POOL_LIMITS,
    });
  }
  return config.upstreamPool;
}

function historyClientForConfig(config) {
  if (!config.appServerRegistry) {
    throw new Error("appServerRegistry is required for relay app-server routing");
  }
  if (!config.registryHistoryClient) {
    config.registryHistoryClient = {
      request: async (method, params = undefined) => {
        await config.appServerRegistry.ensureReady("history_request");
        const endpoint = config.appServerRegistry.historyEndpoint({ required: true });
        return upstreamPoolForConfig(config).request(endpoint, method, params, {
          label: "history",
          initializer: initializeClient,
          onNotification: upstreamNotificationCallback(config, {
            label: endpoint.label || "history",
            url: endpoint.url,
          }),
        });
      },
    };
  }
  return config.registryHistoryClient;
}

function liveStatusCacheForConfig(config) {
  if (!config.liveStatusCache) {
    config.liveStatusCache = new LiveStatusCache({
      collectLiveRows: async () => {
        if (!config.appServerRegistry) {
          throw new Error("appServerRegistry is required for live app-server discovery");
        }
        await config.appServerRegistry.ensureReady("live_status");
        const live = await collectLiveRows({
          logger: relayLogger(config),
          endpoints: config.appServerRegistry.liveEndpoints(),
          excludeURLs: [],
          pool: upstreamPoolForConfig(config),
          onNotification: config.upstreamNotificationHandler || null,
          codexHome: codexHomeForConfig(config),
        });
        const mergedLive = mergePrivateLiveRows(live, config.appServerRegistry, {
          codexHome: codexHomeForConfig(config),
          logger: relayLogger(config),
        });
        for (const row of mergedLive.rows || []) {
          if (row?.dockRelaySource && row.dockRelaySource.endpointType !== "private") {
            config.appServerRegistry.recordLiveRows(row.dockRelaySource, [row]);
          }
        }
        return mergedLive;
      },
      logger: relayLogger(config),
      statusTracker: config.statusTracker || null,
      refreshIntervalMs: config.liveStatusRefreshIntervalMs,
      maxAgeMs: config.liveStatusMaxAgeMs,
    });
  }
  return config.liveStatusCache;
}

function sessionRouterForConfig(config) {
  if (!config.sessionRouter) {
    config.sessionRouter = new SessionRouter({
      liveStatusCache: liveStatusCacheForConfig(config),
      appServerRegistry: config.appServerRegistry,
    });
  }
  return config.sessionRouter;
}

function isHistoryEndpoint(config, endpoint) {
  if (!config.appServerRegistry) {
    throw new Error("appServerRegistry is required for relay app-server routing");
  }
  return config.appServerRegistry.isHistoryEndpoint(endpoint);
}

function statusPriority(thread) {
  const status = thread?.status;
  if (status?.type === "active") {
    const flags = new Set(status.activeFlags || []);
    if (flags.has("waitingOnApproval") || flags.has("waitingOnUserInput")) {
      return 0;
    }
    return 1;
  }
  if (status?.type === "idle") {
    return 2;
  }
  if (status?.type === "systemError") {
    return 3;
  }
  if (status?.type === "notLoaded") {
    return 5;
  }
  return 4;
}

function sleep(ms) {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

function attentionFlagsForServerRequest(message) {
  switch (message?.method) {
    case "item/commandExecution/requestApproval":
    case "item/fileChange/requestApproval":
    case "item/permissions/requestApproval":
    case "applyPatchApproval":
    case "execCommandApproval":
      return ["waitingOnApproval"];
    case "item/tool/requestUserInput":
    case "mcpServer/elicitation/request":
    case "item/tool/call":
    case "account/chatgptAuthTokens/refresh":
    case "attestation/generate":
      return ["waitingOnUserInput"];
    default:
      return [];
  }
}

function mergeActiveFlags(thread, additionalFlags) {
  if (!additionalFlags.length) {
    return thread;
  }
  const activeFlags = new Set(
    thread?.status?.type === "active" ? thread.status.activeFlags || [] : [],
  );
  for (const flag of additionalFlags) {
    activeFlags.add(flag);
  }
  return {
    ...thread,
    status: {
      type: "active",
      activeFlags: [...activeFlags],
    },
  };
}

function rowTimestamp(thread) {
  return Number(thread?.updatedAt ?? thread?.createdAt ?? 0);
}

function maxTimestampMs(values = []) {
  let newest = 0;
  for (const value of values) {
    const timestamp = timestampToMs(value);
    if (timestamp > newest) {
      newest = timestamp;
    }
  }
  return newest;
}

function turnActivityMs(turn) {
  if (!turn || typeof turn !== "object") {
    return 0;
  }
  return maxTimestampMs([
    turn.activityAtMs,
    turn.activityAt,
    turn.updatedAtMs,
    turn.updatedAt,
    turn.completedAtMs,
    turn.completedAt,
    turn.finishedAtMs,
    turn.finishedAt,
    turn.startedAtMs,
    turn.startedAt,
    turn.createdAtMs,
    turn.createdAt,
    turn.timestampMs,
    turn.timestamp,
  ]);
}

function threadActivityMs(thread) {
  return maxTimestampMs([
    thread?.activityAtMs,
    thread?.activityAt,
    thread?.updatedAtMs,
    thread?.updatedAt,
    thread?.createdAtMs,
    thread?.createdAt,
  ]);
}

function preferThread(candidate, existing) {
  if (!existing) {
    return candidate;
  }
  const candidatePriority = statusPriority(candidate);
  const existingPriority = statusPriority(existing);
  if (candidatePriority !== existingPriority) {
    return candidatePriority < existingPriority ? candidate : existing;
  }
  return rowTimestamp(candidate) >= rowTimestamp(existing) ? candidate : existing;
}

function rollupStatusForRejectedThread(row, classification) {
  if (!classification?.parentThreadID) {
    return null;
  }
  if (row?.status?.type === "active") {
    return {
      type: "active",
      activeFlags: Array.isArray(row.status.activeFlags) ? [...row.status.activeFlags] : [],
    };
  }
  if (row?.status?.type === "privateUnattachable") {
    return { type: "active", activeFlags: [] };
  }
  return null;
}

function hiddenActivityRollupRow(row, classification) {
  const status = rollupStatusForRejectedThread(row, classification);
  if (!status) {
    return null;
  }
  return {
    ...row,
    status,
    dockRelayRollupTargetThreadID: classification.parentThreadID,
    dockRelayRollupSource: row?.status?.type === "privateUnattachable"
      ? "private-owner-presence"
      : "hidden-child-live",
  };
}

function parseLimit(value, fallback) {
  const number = Number(value);
  if (!Number.isFinite(number) || number <= 0) {
    return fallback;
  }
  return Math.floor(number);
}

function clampThreadListParams(params = {}) {
  return {
    ...params,
    limit: Math.min(THREAD_LIST_MAX_LIMIT, parseLimit(params.limit, THREAD_LIST_MAX_LIMIT)),
  };
}

function humanOnlyThreadListParams(params = {}) {
  const { sourceKind: _sourceKind, sourceKinds: _sourceKinds, ...rest } = params || {};
  return clampThreadListParams(rest);
}

function nonEmpty(value) {
  const text = String(value ?? "").trim();
  return text.length > 0 ? text : null;
}

function codexHomeForConfig(config) {
  return config?.codexHome || process.env.CODEX_HOME || null;
}

function sessionMetadataGitInfo(git) {
  if (!git || typeof git !== "object" || Array.isArray(git)) {
    return null;
  }
  const branch = nonEmpty(git.branch);
  const originUrl = nonEmpty(git.repository_url) || nonEmpty(git.originUrl);
  const commitHash = nonEmpty(git.commit_hash) || nonEmpty(git.commitHash);
  if (!branch && !originUrl && !commitHash) {
    return null;
  }
  return {
    ...(branch ? { branch } : {}),
    ...(originUrl ? { originUrl } : {}),
    ...(commitHash ? { commitHash } : {}),
  };
}

function threadMetadataFromSessionPayload(payload) {
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
    return null;
  }
  const id = nonEmpty(payload.id);
  if (!id) {
    return null;
  }
  const gitInfo = sessionMetadataGitInfo(payload.git);
  const metadata = {
    id,
    ...(payload.source !== undefined ? { source: payload.source } : {}),
    ...(payload.thread_source !== undefined ? { threadSource: payload.thread_source } : {}),
    ...(payload.forked_from_id !== undefined ? { forkedFromId: payload.forked_from_id } : {}),
    ...(nonEmpty(payload.cwd) ? { cwd: nonEmpty(payload.cwd) } : {}),
    ...(gitInfo ? { gitInfo } : {}),
  };
  return Object.keys(metadata).length > 1 ? metadata : null;
}

function firstSessionMetadataFromFile(filePath) {
  let contents;
  try {
    contents = fs.readFileSync(filePath, "utf8");
  } catch {
    return null;
  }
  for (const line of contents.split(/\r?\n/, 12)) {
    const trimmed = line.trim();
    if (!trimmed) {
      continue;
    }
    let event;
    try {
      event = JSON.parse(trimmed);
    } catch {
      continue;
    }
    if (event?.type === "session_meta") {
      return threadMetadataFromSessionPayload(event.payload);
    }
  }
  return null;
}

function threadIDSet(values = []) {
  const set = new Set();
  for (const value of values || []) {
    const id = nonEmpty(value);
    if (id) {
      set.add(id);
    }
  }
  return set;
}

function fileNameCouldContainThreadID(fileName, wantedIDs) {
  if (!wantedIDs || wantedIDs.size === 0) {
    return true;
  }
  for (const id of wantedIDs) {
    if (fileName.includes(id)) {
      return true;
    }
  }
  return false;
}

function readSessionMetadataIndexForCodexHome(codexHome, logger = defaultRelayLogger, {
  threadIDs = null,
} = {}) {
  const sessionsDir = codexHome ? path.join(codexHome, "sessions") : null;
  if (!sessionsDir) {
    return new Map();
  }
  const wantedIDs = threadIDs ? threadIDSet(threadIDs) : null;
  if (wantedIDs && wantedIDs.size === 0) {
    return new Map();
  }
  const byID = new Map();
  const stack = [sessionsDir];
  while (stack.length > 0) {
    const dir = stack.pop();
    let entries;
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch (error) {
      if (error?.code !== "ENOENT") {
        logger.warn("human_started_thread.session_metadata_unavailable", {
          path: dir,
          error,
        });
      }
      continue;
    }
    entries.sort((lhs, rhs) => lhs.name.localeCompare(rhs.name));
    for (const entry of entries) {
      const entryPath = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        stack.push(entryPath);
        continue;
      }
      if (!entry.isFile() || !entry.name.endsWith(".jsonl")) {
        continue;
      }
      if (!fileNameCouldContainThreadID(entry.name, wantedIDs)) {
        continue;
      }
      const metadata = firstSessionMetadataFromFile(entryPath);
      if (metadata?.id && (!wantedIDs || wantedIDs.has(metadata.id))) {
        byID.set(metadata.id, metadata);
        if (wantedIDs) {
          wantedIDs.delete(metadata.id);
          if (wantedIDs.size === 0) {
            return byID;
          }
        }
      }
    }
  }
  return byID;
}

function mergeSessionMetadata(row, metadata) {
  if (!row || !metadata) {
    return row;
  }
  return {
    ...row,
    ...metadata,
    id: row.id,
    sessionId: row.sessionId,
    status: row.status,
    dockRelaySource: row.dockRelaySource,
  };
}

function parseSessionIndexTimestamp(value) {
  const ms = Date.parse(String(value || ""));
  if (!Number.isFinite(ms)) {
    return 0;
  }
  return ms;
}

function readSessionIndexCandidates(config, { existingThreadIDs = new Set(), limit = HUMAN_THREAD_INDEX_SUPPLEMENT_LIMIT } = {}) {
  const codexHome = codexHomeForConfig(config);
  if (!codexHome) {
    return [];
  }
  const indexPath = path.join(codexHome, "session_index.jsonl");
  let contents;
  try {
    contents = fs.readFileSync(indexPath, "utf8");
  } catch (error) {
    if (error?.code !== "ENOENT") {
      relayLogger(config).warn("human_started_thread.session_index_unavailable", {
        path: indexPath,
        error,
      });
    }
    return [];
  }

  const latestByID = new Map();
  for (const line of contents.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed) {
      continue;
    }
    let row;
    try {
      row = JSON.parse(trimmed);
    } catch {
      continue;
    }
    const id = nonEmpty(row?.id);
    if (!id || existingThreadIDs.has(id)) {
      continue;
    }
    const updatedAtMs = parseSessionIndexTimestamp(row?.updated_at || row?.updatedAt);
    const existing = latestByID.get(id);
    if (!existing || updatedAtMs >= existing.updatedAtMs) {
      latestByID.set(id, {
        id,
        name: nonEmpty(row?.thread_name) || nonEmpty(row?.name) || null,
        updatedAt: updatedAtMs > 0 ? updatedAtMs / 1000 : undefined,
        updatedAtMs,
      });
    }
  }

  return [...latestByID.values()]
    .sort((lhs, rhs) => rhs.updatedAtMs - lhs.updatedAtMs)
    .slice(0, Math.max(0, Math.min(HUMAN_THREAD_INDEX_SUPPLEMENT_LIMIT, Number(limit) || HUMAN_THREAD_INDEX_SUPPLEMENT_LIMIT)));
}

function threadArchiveMatchesParams(thread, params = {}) {
  const archived = params.archived === true;
  const threadPath = String(thread?.path || "");
  const isArchivedThread = threadPath.split(path.sep).includes("archived_sessions");
  if (archived) {
    return isArchivedThread;
  }
  return !isArchivedThread;
}

function mergeSessionIndexCandidate(candidate, readThread) {
  const merged = mergeAuthoritativeThreadRead(candidate, readThread);
  if (!nonEmpty(merged.name) && nonEmpty(candidate?.name)) {
    merged.name = candidate.name;
  }
  if (!merged.updatedAt && candidate?.updatedAt) {
    merged.updatedAt = candidate.updatedAt;
  }
  return merged;
}

function disabledLiveOverlay() {
  return {
    ok: false,
    state: "disabled",
    ageMs: null,
  };
}

function paginateStrings(values, params = {}) {
  const sorted = [...values].sort();
  const cursor = params.cursor;
  let start = 0;
  if (typeof cursor === "string" && cursor.length > 0) {
    const cursorIndex = sorted.findIndex((value) => value === cursor);
    start = cursorIndex >= 0 ? cursorIndex + 1 : sorted.findIndex((value) => value > cursor);
    if (start < 0) {
      start = sorted.length;
    }
  }
  const limit = parseLimit(params.limit, sorted.length || 1);
  const page = sorted.slice(start, start + limit);
  const end = start + page.length;
  return {
    data: page,
    nextCursor: end < sorted.length ? page[page.length - 1] : null,
  };
}

function canonicalURLString(value) {
  try {
    return new URL(value).toString();
  } catch {
    return String(value || "");
  }
}

async function withClient(url, options, operation) {
  const client = new JsonRpcWebSocketClient(url, options);
  await initializeClient(client);
  try {
    return await operation(client);
  } finally {
    client.close();
  }
}

async function initializeClient(client) {
  await client.connect();
  await client.request("initialize", {
    clientInfo: {
      name: "codex_dock_relay",
      title: "Codex Dock Relay",
      version: RELAY_VERSION,
    },
    capabilities: {
      experimentalApi: true,
      requestAttestation: false,
    },
  });
  client.notify("initialized");
}

async function clientForEndpoint(endpoint, {
  logger = defaultRelayLogger,
  pool = null,
  label = "live-status",
  timeoutMs = undefined,
  onNotification = null,
} = {}) {
  const notificationCallback = typeof onNotification === "function"
    ? (message) => onNotification(message, {
        label,
        url: endpoint.url,
      })
    : null;
  if (pool) {
    return pool.clientFor({
      label,
      url: endpoint.url,
      bearerToken: endpoint.bearerToken || null,
      timeoutMs,
      initializer: initializeClient,
      onNotification: notificationCallback,
    });
  }
  const client = new JsonRpcWebSocketClient(endpoint.url, {
    bearerToken: endpoint.bearerToken || null,
    timeoutMs,
    logger,
    onNotification: notificationCallback,
  });
  await initializeClient(client);
  return client;
}

async function withEndpointClient(endpoint, options, operation) {
  const client = await clientForEndpoint(endpoint, options);
  try {
    return await operation(client);
  } finally {
    if (!options?.pool) {
      client.close();
    }
  }
}

async function readLoadedRows(endpoint, {
  logger = defaultRelayLogger,
  pool = null,
  timeoutMs = undefined,
  onNotification = null,
  codexHome = null,
  sessionMetadataByThreadID = null,
} = {}) {
  return withEndpointClient(endpoint, {
    logger,
    pool,
    label: "live-status",
    timeoutMs,
    onNotification,
  }, async (client) => {
    const loaded = await client.request("thread/loaded/list", { limit: LIVE_LOADED_LIST_LIMIT });
    const loadedThreadIDs = (loaded.data || []).map(nonEmpty).filter(Boolean);
    const metadataByThreadID = sessionMetadataByThreadID
      || readSessionMetadataIndexForCodexHome(codexHome, logger, { threadIDs: loadedThreadIDs });
    const results = await Promise.allSettled(loadedThreadIDs.map((threadId) => (
      client.request("thread/read", {
        threadId,
        includeTurns: false,
      })
    )));
    const rows = [];
    const rollupRows = [];
    const rejectedThreadIDs = new Set();
    let failedThreadReads = 0;
    for (let index = 0; index < results.length; index += 1) {
      const result = results[index];
      if (result.status === "rejected") {
        failedThreadReads += 1;
        logger.warn("live.thread_read_failed", {
          threadId: loadedThreadIDs[index],
          endpointUrl: endpoint.url,
          error: result.reason,
        });
        continue;
      }
      if (result.value?.thread?.id) {
        const row = mergeSessionMetadata(
          { ...result.value.thread, dockRelaySource: endpoint },
          metadataByThreadID.get(result.value.thread.id),
        );
        const classification = classifyThreadOrigin(row);
        if (classification.allowed) {
          rows.push(row);
        } else {
          rejectedThreadIDs.add(String(row.id));
          const rollupRow = hiddenActivityRollupRow(row, classification);
          if (rollupRow) {
            rollupRows.push(rollupRow);
          }
          logger.debug("live.thread_rejected_by_human_filter", {
            threadId: row.id,
            endpointUrl: endpoint.url,
            reason: classification.reason,
          });
        }
      }
    }
    return {
      rows,
      rollupRows,
      rejectedThreadIDs: [...rejectedThreadIDs],
      totalThreadReads: loadedThreadIDs.length,
      failedThreadReads,
    };
  });
}

async function allSettledInBatches(values, batchSize, mapper) {
  const results = [];
  for (let start = 0; start < values.length; start += batchSize) {
    const batch = values.slice(start, start + batchSize);
    results.push(...await Promise.allSettled(batch.map(mapper)));
  }
  return results;
}

async function pendingRequestsForActiveThread(endpoint, threadId, logger = defaultRelayLogger) {
  const requests = [];
  const client = new JsonRpcWebSocketClient(endpoint.url, {
    bearerToken: endpoint.bearerToken || null,
    logger,
    onRequest: (message) => {
      if (message?.params?.threadId === threadId) {
        requests.push(message);
      }
    },
  });
  try {
    await initializeClient(client);
    await client.request("thread/resume", { threadId, excludeTurns: true });
    await sleep(100);
    return requests;
  } finally {
    client.close();
  }
}

async function enrichRowAttention(row, endpoint, logger = defaultRelayLogger) {
  if (row?.status?.type !== "active") {
    return row;
  }
  const existingFlags = new Set(row.status.activeFlags || []);
  if (existingFlags.has("waitingOnApproval") || existingFlags.has("waitingOnUserInput")) {
    return row;
  }

  let requests;
  try {
    requests = await pendingRequestsForActiveThread(endpoint, row.id, logger);
  } catch (error) {
    logger.warn("live.pending_requests_failed", {
      threadId: row.id,
      endpointUrl: endpoint.url,
      error,
    });
    return row;
  }

  const flags = requests.flatMap(attentionFlagsForServerRequest);
  return mergeActiveFlags(row, flags);
}

async function collectLiveRows(options = {}) {
  const logger = typeof options?.warn === "function" ? options : options.logger || defaultRelayLogger;
  const requestedPool = typeof options?.warn === "function" ? null : options.pool || null;
  // Live-status scans touch many endpoints; pooled clients stay open by label
  // and can exhaust before later endpoints are queried.
  const pool = null;
  const onNotification = typeof options?.warn === "function" ? null : options.onNotification || null;
  const excludedURLs = new Set((typeof options?.warn === "function" ? [] : options.excludeURLs || [])
    .map(canonicalURLString));
  const endpoints = (typeof options?.warn === "function" ? [] : options.endpoints || [])
    .filter((endpoint) => !excludedURLs.has(canonicalURLString(endpoint.url)));
  const sessionMetadataByThreadID = typeof options?.warn === "function"
    ? null
    : options.sessionMetadataByThreadID || null;
  const codexHome = typeof options?.warn === "function" ? null : options.codexHome || null;
  const configuredMaxConcurrent = typeof options?.warn === "function"
    ? UPSTREAM_POOL_LIMITS["live-status"]
    : options.maxConcurrent
      || requestedPool?.labelLimit?.("live-status")
      || UPSTREAM_POOL_LIMITS["live-status"]
      || endpoints.length
      || 1;
  const maxConcurrent = Math.max(1, Math.min(endpoints.length || 1, Number(configuredMaxConcurrent) || 1));
  const results = await allSettledInBatches(
    endpoints,
    maxConcurrent,
    (endpoint) => readLoadedRows(endpoint, {
      logger,
      pool,
      timeoutMs: LIVE_STATUS_UPSTREAM_TIMEOUT_MS,
      onNotification,
      codexHome,
      sessionMetadataByThreadID,
    }),
  );
  const rowsById = new Map();
  const rollupRowsById = new Map();
  const rejectedThreadIDs = new Set();
  let failedEndpoints = 0;
  let totalThreadReads = 0;
  let failedThreadReads = 0;
  for (let index = 0; index < results.length; index += 1) {
    const result = results[index];
    if (result.status === "rejected") {
      failedEndpoints += 1;
      logger.warn("live.endpoint_query_failed", {
        endpointUrl: endpoints[index].url,
        error: result.reason,
      });
      continue;
    }
    totalThreadReads += Number(result.value?.totalThreadReads || 0);
    failedThreadReads += Number(result.value?.failedThreadReads || 0);
    for (const threadId of result.value?.rejectedThreadIDs || []) {
      rejectedThreadIDs.add(String(threadId));
    }
    for (const row of result.value?.rows || []) {
      rowsById.set(row.id, preferThread(row, rowsById.get(row.id)));
    }
    for (const row of result.value?.rollupRows || []) {
      if (!row?.id) {
        continue;
      }
      rollupRowsById.set(row.id, preferThread(row, rollupRowsById.get(row.id)));
    }
  }
  return {
    endpoints,
    failedEndpoints,
    totalThreadReads,
    failedThreadReads,
    rejectedThreadIDs: [...rejectedThreadIDs],
    rows: [...rowsById.values()],
    rollupRows: [...rollupRowsById.values()],
  };
}

function mergePrivateLiveRows(live = {}, appServerRegistry = null, {
  codexHome = null,
  logger = defaultRelayLogger,
  sessionMetadataByThreadID = null,
} = {}) {
  const privateRows = typeof appServerRegistry?.privateLiveRows === "function"
    ? appServerRegistry.privateLiveRows()
    : [];
  if (privateRows.length === 0) {
    return live;
  }
  const privateThreadIDs = privateRows.map((row) => row?.id).filter(Boolean);
  const metadataByThreadID = sessionMetadataByThreadID
    || readSessionMetadataIndexForCodexHome(codexHome, logger, { threadIDs: privateThreadIDs });
  const rejectedCounts = {};
  const privateRejectedThreadIDs = new Set();
  const rejectedThreadIDs = new Set((live.rejectedThreadIDs || []).map((threadID) => String(threadID)));
  const rowsById = new Map();
  const rollupRowsById = new Map();
  for (const row of live.rollupRows || []) {
    if (row?.id) {
      rollupRowsById.set(row.id, row);
    }
  }
  for (const row of [...(live.rows || []), ...privateRows]) {
    if (!row?.id) {
      continue;
    }
    const mergedRow = mergeSessionMetadata(row, metadataByThreadID.get(row.id));
    const classification = classifyThreadOrigin(mergedRow);
    if (!classification.allowed) {
      rejectedCounts[classification.reason] = Number(rejectedCounts[classification.reason] || 0) + 1;
      rejectedThreadIDs.add(String(row.id));
      privateRejectedThreadIDs.add(String(row.id));
      const rollupRow = hiddenActivityRollupRow(mergedRow, classification);
      if (rollupRow) {
        rollupRowsById.set(rollupRow.id, preferThread(rollupRow, rollupRowsById.get(rollupRow.id)));
      }
      logger.debug("live.private_thread_rejected_by_human_filter", {
        threadId: row.id,
        reason: classification.reason,
      });
      continue;
    }
    rowsById.set(mergedRow.id, preferThread(mergedRow, rowsById.get(mergedRow.id)));
  }
  return {
    ...live,
    privateRows: privateRows.length,
    privateRejectedRows: Object.values(rejectedCounts).reduce((sum, count) => sum + Number(count || 0), 0),
    privateRejectedThreadIDs: [...privateRejectedThreadIDs],
    rejectedThreadIDs: [...rejectedThreadIDs],
    rows: [...rowsById.values()],
    rollupRows: [...rollupRowsById.values()],
  };
}

async function readHistoryThreadList(config, params) {
  return historyClientForConfig(config).request("thread/list", params);
}

async function drainThreadListRows(config, params = {}, {
  name = "active:interactiveDefault",
  sourceScope = "interactiveDefault",
} = {}) {
  const pages = [];
  const rows = [];
  const seenCursors = new Set();
  const historyParams = humanOnlyThreadListParams(params);
  let cursor = historyParams.cursor || null;
  let complete = true;
  let error = null;
  let ordinal = 0;

  try {
    while (true) {
      const request = {
        ...historyParams,
        ...(cursor ? { cursor } : {}),
      };
      const response = await readHistoryThreadList(config, request);
      const data = Array.isArray(response?.data) ? response.data : [];
      pages.push({
        cursor,
        nextCursor: response?.nextCursor || null,
        backwardsCursor: response?.backwardsCursor || null,
        rowCount: data.length,
      });
      for (let index = 0; index < data.length; index += 1) {
        rows.push({
          ordinal,
          pageIndex: pages.length - 1,
          rowIndex: index,
          thread: data[index],
        });
        ordinal += 1;
      }
      const nextCursor = response?.nextCursor || null;
      if (!nextCursor) {
        break;
      }
      if (seenCursors.has(nextCursor)) {
        complete = false;
        error = `repeated thread/list cursor ${nextCursor}`;
        break;
      }
      seenCursors.add(nextCursor);
      cursor = nextCursor;
    }
  } catch (caught) {
    complete = false;
    error = caught?.message || String(caught);
  }

  return {
    name,
    archived: Boolean(historyParams.archived),
    sourceScope,
    complete,
    error,
    pages,
    rowCount: rows.length,
    rows,
  };
}

async function readHistoryThread(config, params) {
  return historyClientForConfig(config).request("thread/read", params);
}

async function readThreadTurnsFromEndpoint(endpoint, params, timeoutMs = undefined, logger = defaultRelayLogger) {
  return withClient(
    endpoint.url,
    { bearerToken: endpoint.bearerToken || null, timeoutMs, logger },
    async (client) => client.request("thread/turns/list", params),
  );
}

async function readThreadFromEndpoint(endpoint, params, logger = defaultRelayLogger) {
  return withClient(
    endpoint.url,
    { bearerToken: endpoint.bearerToken || null, logger },
    async (client) => client.request("thread/read", params),
  );
}

function sanitizeRelayFields(thread) {
  if (!thread || typeof thread !== "object") {
    return thread;
  }
  const { dockRelaySource, ...clean } = thread;
  return clean;
}

function mergeAuthoritativeThreadRead(listRow, readThread) {
  if (!readThread || typeof readThread !== "object") {
    return listRow;
  }
  const merged = { ...listRow };
  for (const [key, value] of Object.entries(readThread)) {
    if (value !== undefined) {
      merged[key] = value;
    }
  }
  // `thread/read` enriches display/detail fields, but it must not downgrade the
  // list identity or activity baseline before turn activity is proven.
  if (listRow?.id) {
    merged.id = listRow.id;
  }
  for (const field of ["createdAt", "updatedAt"]) {
    if (Number.isFinite(Number(listRow?.[field])) && Number.isFinite(Number(readThread?.[field]))) {
      merged[field] = Math.max(Number(listRow[field]), Number(readThread[field]));
    }
  }
  delete merged.turns;
  return merged;
}

async function enrichHumanStartedRows(config, rows = [], {
  route = "thread_list",
  readThread = (threadId) => readHistoryThread(config, { threadId, includeTurns: false }),
} = {}) {
  const logger = relayLogger(config);
  const sessionMetadataByThreadID = readSessionMetadataIndexForCodexHome(
    codexHomeForConfig(config),
    logger,
    { threadIDs: rows.map((row) => row?.id).filter(Boolean) },
  );
  const candidates = [];
  const rejectedCounts = {};

  for (const inputRow of rows) {
    const row = mergeSessionMetadata(inputRow, sessionMetadataByThreadID.get(inputRow?.id));
    const classification = classifyThreadOrigin(row);
    if (classification.allowed) {
      candidates.push(row);
      continue;
    }
    rejectedCounts[classification.reason] = Number(rejectedCounts[classification.reason] || 0) + 1;
  }

  const results = await allSettledInBatches(
    candidates,
    HUMAN_THREAD_READ_ENRICHMENT_CONCURRENCY,
    async (row) => {
      if (!row?.id) {
        throw new Error("thread row missing id");
      }
      const response = await readThread(row.id);
      if (!response?.thread || typeof response.thread !== "object") {
        throw new Error("thread/read returned no thread");
      }
      const authoritative = mergeSessionMetadata(
        mergeAuthoritativeThreadRead(row, response?.thread),
        sessionMetadataByThreadID.get(row.id),
      );
      const classification = classifyThreadOrigin(authoritative);
      return { row, authoritative, classification };
    },
  );

  const acceptedRows = [];
  let validationFailures = 0;
  for (let index = 0; index < results.length; index += 1) {
    const result = results[index];
    const candidate = candidates[index];
    if (result.status === "rejected") {
      validationFailures += 1;
      logger.warn("human_started_thread.enrichment_failed", {
        route,
        threadId: candidate?.id || null,
        error: result.reason,
      });
      continue;
    }
    if (result.value.classification.allowed) {
      acceptedRows.push(result.value.authoritative);
      continue;
    }
    const reason = result.value.classification.reason || "unknown";
    rejectedCounts[reason] = Number(rejectedCounts[reason] || 0) + 1;
  }

  return {
    acceptedRows,
    rejectedCounts,
    validationFailures,
    requestedRows: rows.length,
    candidateRows: candidates.length,
  };
}

async function readSessionIndexHumanStartedSupplements(config, existingRows = [], {
  route = "thread_list",
  params = {},
  limit = HUMAN_THREAD_INDEX_SUPPLEMENT_LIMIT,
  readThread = (threadId) => readHistoryThread(config, { threadId, includeTurns: false }),
} = {}) {
  const logger = relayLogger(config);
  const existingThreadIDs = new Set(existingRows.map((row) => row?.id).filter(Boolean));
  const candidates = readSessionIndexCandidates(config, { existingThreadIDs, limit });
  if (candidates.length === 0) {
    return {
      acceptedRows: [],
      rejectedCounts: {},
      validationFailures: 0,
      candidateRows: 0,
    };
  }
  const sessionMetadataByThreadID = readSessionMetadataIndexForCodexHome(
    codexHomeForConfig(config),
    logger,
    { threadIDs: candidates.map((candidate) => candidate?.id).filter(Boolean) },
  );

  const rejectedCounts = {};
  const results = await allSettledInBatches(
    candidates,
    HUMAN_THREAD_READ_ENRICHMENT_CONCURRENCY,
    async (candidate) => {
      const response = await readThread(candidate.id);
      const thread = mergeSessionMetadata(
        mergeSessionIndexCandidate(candidate, response?.thread),
        sessionMetadataByThreadID.get(candidate.id),
      );
      if (!threadArchiveMatchesParams(thread, params)) {
        return { accepted: false, reason: "archive_scope_mismatch" };
      }
      const classification = classifyThreadOrigin(thread);
      if (!classification.allowed) {
        return { accepted: false, reason: classification.reason };
      }
      return { accepted: true, row: thread };
    },
  );

  const acceptedRows = [];
  let validationFailures = 0;
  for (const result of results) {
    if (result.status === "rejected") {
      validationFailures += 1;
      logger.warn("human_started_thread.session_index_validation_failed", {
        route,
        error: result.reason,
      });
      continue;
    }
    if (result.value?.accepted) {
      acceptedRows.push(result.value.row);
      continue;
    }
    const reason = result.value?.reason || "unknown";
    rejectedCounts[reason] = Number(rejectedCounts[reason] || 0) + 1;
  }

  logger.info("human_started_thread.session_index_supplement", {
    route,
    candidates: candidates.length,
    acceptedRows: acceptedRows.length,
    rejectedCounts,
    validationFailures,
  });

  return {
    acceptedRows,
    rejectedCounts,
    validationFailures,
    candidateRows: candidates.length,
  };
}

function mergeHumanStartedRowsWithSupplements(rows = [], supplements = []) {
  if (supplements.length === 0) {
    return rows;
  }
  const originalOrder = new Map();
  const byID = new Map();
  for (const row of rows) {
    if (!row?.id || byID.has(row.id)) {
      continue;
    }
    originalOrder.set(row.id, originalOrder.size);
    byID.set(row.id, row);
  }
  for (const row of supplements) {
    if (!row?.id || byID.has(row.id)) {
      continue;
    }
    originalOrder.set(row.id, originalOrder.size);
    byID.set(row.id, row);
  }
  return [...byID.values()].sort((lhs, rhs) => {
    const timestampDelta = rowTimestamp(rhs) - rowTimestamp(lhs);
    if (timestampDelta !== 0) {
      return timestampDelta;
    }
    return (originalOrder.get(lhs.id) ?? 0) - (originalOrder.get(rhs.id) ?? 0);
  });
}

function acceptedHumanRowForThread(row, threadId) {
  if (!row || typeof row !== "object") {
    return null;
  }
  if (row.id !== threadId && row.threadId !== threadId && row.threadID !== threadId) {
    return null;
  }
  return classifyThreadOrigin(row).allowed ? row : null;
}

const HUMAN_ROUTE_CONTEXT_FALLBACK_REASONS = new Set([
  "missing_source",
  "not_base_level",
]);

function isRouteAuthoritativeHumanCard(card) {
  return isHumanAppFacingCard(card) && card?.relationship === "root";
}

function appFacingHumanCardForThread(config, threadId) {
  const card = config?.relayStateEngine?.cardForThread?.(threadId);
  return isRouteAuthoritativeHumanCard(card) ? card : null;
}

function assertRouteHumanStartedThread(row, threadId, {
  acceptedHumanRow = null,
  appFacingCard = null,
} = {}) {
  const classification = classifyThreadOrigin(row);
  if (!classification.allowed) {
    const acceptedFallback = acceptedHumanRowForThread(acceptedHumanRow, threadId);
    if (HUMAN_ROUTE_CONTEXT_FALLBACK_REASONS.has(classification.reason) && acceptedFallback) {
      return row;
    }
    if (HUMAN_ROUTE_CONTEXT_FALLBACK_REASONS.has(classification.reason)
      && isRouteAuthoritativeHumanCard(appFacingCard)) {
      return row;
    }
    throw humanThreadRejectedError(threadId || row?.id || row?.threadId || row?.threadID, classification.reason);
  }
  return row;
}

async function readHumanThreadForRoute(config, threadId, {
  allowHistoryFallbackForRejectedLive = false,
  acceptedHumanRow = null,
  allowAppFacingCardRouteFallback = false,
} = {}) {
  const appFacingCard = allowAppFacingCardRouteFallback
    ? appFacingHumanCardForThread(config, threadId)
    : null;
  const liveRow = await sessionRouterForConfig(config).rowForThread(threadId);
  if (liveRow) {
    try {
      return assertRouteHumanStartedThread(liveRow, threadId, {
        acceptedHumanRow,
        appFacingCard,
      });
    } catch (error) {
      if (!allowHistoryFallbackForRejectedLive) {
        throw error;
      }
    }
  }
  const history = await readHistoryThread(config, { threadId, includeTurns: false });
  return assertRouteHumanStartedThread(history?.thread, threadId, {
    acceptedHumanRow,
    appFacingCard,
  });
}

async function assertHumanThreadID(config, threadId, options = {}) {
  return sanitizeRelayFields(await readHumanThreadForRoute(config, threadId, options));
}

async function aggregateThreadList(config, params = {}) {
  const logger = relayLogger(config);
  const historyParams = humanOnlyThreadListParams(params);
  const history = await readHistoryThreadList(config, historyParams);
  const data = Array.isArray(history.data) ? history.data : [];
  const { acceptedRows, rejectedCounts, validationFailures } = await enrichHumanStartedRows(
    config,
    data,
    { route: "thread_list" },
  );
  const supplements = await readSessionIndexHumanStartedSupplements(config, acceptedRows, {
    route: "thread_list",
    params: historyParams,
    limit: historyParams.limit,
  });
  for (const [reason, count] of Object.entries(supplements.rejectedCounts)) {
    rejectedCounts[reason] = Number(rejectedCounts[reason] || 0) + Number(count || 0);
  }
  const returnedRows = mergeHumanStartedRowsWithSupplements(acceptedRows, supplements.acceptedRows);
  const liveOverlay = history.liveOverlay || liveStatusCacheForConfig(config).liveOverlay();
  logger.info("thread_list.loaded", {
    historyRows: data.length,
    requestedLimit: params.limit,
    effectiveLimit: historyParams.limit,
    returnedRows: returnedRows.length,
    supplementedRows: supplements.acceptedRows.length,
    rejectedCounts,
    validationFailures: validationFailures + supplements.validationFailures,
    liveOverlayState: liveOverlay?.state || (liveOverlay?.ok ? "healthy" : "unknown"),
  });
  return {
    ...history,
    data: returnedRows,
    liveOverlay,
  };
}

async function aggregateThreadRead(config, params = {}, options = {}) {
  if (!params.threadId) {
    throw new Error("thread/read requires threadId");
  }
  if (!config.appServerRegistry) {
    throw new Error("appServerRegistry is required for thread/read");
  }
  await config.appServerRegistry.ensureReady("thread_read_route");
  const route = config.appServerRegistry.routeForThreadMethod("thread/read", params.threadId, {
    includeTurns: Boolean(params.includeTurns),
    allowHistoryForPrivateOwner: Boolean(options.allowHistoryForPrivateOwner),
  });
  const appFacingCard = options.allowAppFacingCardRouteFallback
    ? appFacingHumanCardForThread(config, params.threadId)
    : null;
  if (route.source === "live-owner") {
    const result = await readThreadFromEndpoint(route.endpoint, params, relayLogger(config));
    assertRouteHumanStartedThread(result?.thread, params.threadId, { appFacingCard });
    return result;
  }
  const result = await readHistoryThread(config, params);
  assertRouteHumanStartedThread(result?.thread, params.threadId, { appFacingCard });
  return result;
}

async function listThreadTurns(config, params = {}, options = {}) {
  if (!params.threadId) {
    throw new Error("thread/turns/list requires threadId");
  }
  await assertHumanThreadID(config, params.threadId, {
    allowHistoryFallbackForRejectedLive: Boolean(options.allowHistoryForPrivateOwner),
    acceptedHumanRow: options.acceptedHumanRow || null,
    allowAppFacingCardRouteFallback: Boolean(options.allowAppFacingCardRouteFallback),
  });
  const endpoint = await endpointForThread(config, params.threadId, "thread/turns/list", {
    allowHistoryForPrivateOwner: Boolean(options.allowHistoryForPrivateOwner),
  });
  if (isHistoryEndpoint(config, endpoint)) {
    return historyClientForConfig(config).request("thread/turns/list", params);
  }
  return readThreadTurnsFromEndpoint(endpoint, params, undefined, relayLogger(config));
}

async function readNewestTurnActivity(config, threadId, {
  acceptedHumanRow = null,
} = {}) {
  const pages = [];
  const seenCursors = new Set();
  let cursor = null;
  let newestTurnActivityAtMs = 0;
  let latestSummaryMessage = null;

  while (true) {
    const response = await listThreadTurns(config, {
      threadId,
      limit: THREAD_LIST_MAX_LIMIT,
      ...(cursor ? { cursor } : {}),
    }, {
      allowHistoryForPrivateOwner: true,
      acceptedHumanRow,
    });
    const turns = Array.isArray(response?.data) ? response.data : [];
    pages.push({
      cursor,
      nextCursor: response?.nextCursor || null,
      rowCount: turns.length,
    });
    for (const turn of turns) {
      newestTurnActivityAtMs = Math.max(newestTurnActivityAtMs, turnActivityMs(turn));
    }
    const pageSummaryMessage = latestMeaningfulMessageFromTurns(turns, {
      pageIndex: pages.length - 1,
    });
    if (pageSummaryMessage && (
      !latestSummaryMessage
      || latestSummaryMessage.timestampMs < pageSummaryMessage.timestampMs
      || (
        latestSummaryMessage.timestampMs === pageSummaryMessage.timestampMs
        && latestSummaryMessage.pageIndex < pageSummaryMessage.pageIndex
      )
    )) {
      latestSummaryMessage = pageSummaryMessage;
    }
    const nextCursor = response?.nextCursor || null;
    if (!nextCursor) {
      break;
    }
    if (seenCursors.has(nextCursor)) {
      throw new Error(`repeated thread/turns/list cursor ${nextCursor}`);
    }
    seenCursors.add(nextCursor);
    cursor = nextCursor;
  }

  return {
    newestTurnActivityAtMs,
    latestSummary: latestSummaryMessage?.text || null,
    latestSummaryAtMs: latestSummaryMessage?.timestampMs || 0,
    pages,
  };
}

async function canonicalizeThreadRows(config, rows = [], {
  route = "dock_reconcile",
} = {}) {
  // This is the card-truth collapse point. Raw list rows, read metadata,
  // turn pages, live/session candidates, and archive inputs may feed this
  // projection, but only the canonical rows returned here may become Dock or
  // Archive card facts.
  const logger = relayLogger(config);
  const results = await allSettledInBatches(
    rows,
    HUMAN_THREAD_READ_ENRICHMENT_CONCURRENCY,
    async (row) => {
      if (!row?.id) {
        throw new Error("thread row missing id");
      }
      const baseActivityAtMs = threadActivityMs(row);
      const turns = await readNewestTurnActivity(config, row.id, {
        acceptedHumanRow: row,
      });
      const activityAtMs = Math.max(baseActivityAtMs, turns.newestTurnActivityAtMs);
      const latestSummary = typeof turns.latestSummary === "string" && turns.latestSummary.trim().length > 0
        ? turns.latestSummary.trim()
        : null;
      return {
        ...row,
        ...(latestSummary ? {
          latestSummary,
          displaySummary: latestSummary,
          summarySource: "latest_summary",
        } : {}),
        activityAtMs,
        activityAt: timestampToISO(activityAtMs),
        freshness: "fresh",
        completeness: "complete",
        activityProofStatus: "proven",
        activityProofSource: "thread/read+thread/turns/list",
        activityProofCheckedAt: new Date().toISOString(),
      };
    },
  );

  const canonicalRows = [];
  let validationFailures = 0;
  for (let index = 0; index < results.length; index += 1) {
    const result = results[index];
    const row = rows[index];
    if (result.status === "fulfilled") {
      canonicalRows.push(result.value);
      continue;
    }
    validationFailures += 1;
    const fallbackActivityAtMs = threadActivityMs(row);
    logger.warn("card_activity_proof.failed", {
      route,
      threadId: row?.id || null,
      error: result.reason,
    });
    if (row?.id) {
      canonicalRows.push({
        ...row,
        activityAtMs: fallbackActivityAtMs,
        activityAt: timestampToISO(fallbackActivityAtMs),
        freshness: "stale",
        completeness: "partial",
        activityProofStatus: "unproven",
        activityProofSource: "thread/read+thread/turns/list:error",
        activityProofCheckedAt: new Date().toISOString(),
      });
    }
  }

  return {
    rows: canonicalRows,
    complete: validationFailures === 0,
    validationFailures,
  };
}

async function endpointForThread(config, threadId, method = "thread/resume", options = {}) {
  if (!config.appServerRegistry) {
    throw new Error("appServerRegistry is required for relay app-server routing");
  }
  await config.appServerRegistry.ensureReady("thread_route");
  return config.appServerRegistry.routeForThreadMethod(method, threadId, options).endpoint;
}

async function archiveThread(config, params = {}) {
  if (!params.threadId) {
    throw new Error("thread/archive requires threadId");
  }
  await assertHumanThreadID(config, params.threadId);
  const endpoint = await endpointForThread(config, params.threadId, "thread/archive");
  if (isHistoryEndpoint(config, endpoint)) {
    return historyClientForConfig(config).request("thread/archive", params);
  }
  return withClient(
    endpoint.url,
    { bearerToken: endpoint.bearerToken || null, logger: relayLogger(config) },
    async (client) => client.request("thread/archive", params),
  );
}

async function setThreadName(config, params = {}) {
  if (!params.threadId) {
    throw new Error("thread/name/set requires threadId");
  }
  if (typeof params.name !== "string" || params.name.trim().length === 0) {
    throw new Error("thread/name/set requires name");
  }
  await assertHumanThreadID(config, params.threadId);
  const endpoint = await endpointForThread(config, params.threadId, "thread/name/set");
  if (isHistoryEndpoint(config, endpoint)) {
    return historyClientForConfig(config).request("thread/name/set", params);
  }
  return withClient(
    endpoint.url,
    { bearerToken: endpoint.bearerToken || null, logger: relayLogger(config) },
    async (client) => client.request("thread/name/set", params),
  );
}

async function unarchiveThread(config, params = {}) {
  if (!params.threadId) {
    throw new Error("thread/unarchive requires threadId");
  }
  await assertHumanThreadID(config, params.threadId);
  return historyClientForConfig(config).request("thread/unarchive", params);
}

export {
  assertHumanThreadID,
  aggregateThreadList,
  aggregateThreadRead,
  archiveThread,
  attentionFlagsForServerRequest,
  canonicalizeThreadRows,
  collectLiveRows,
  drainThreadListRows,
  endpointForThread,
  enrichHumanStartedRows,
  initializeClient,
  listThreadTurns,
  mergeHumanStartedRowsWithSupplements,
  mergePrivateLiveRows,
  mergeActiveFlags,
  parseLimit,
  clampThreadListParams,
  disabledLiveOverlay,
  pendingRequestsForActiveThread,
  preferThread,
  readHistoryThread,
  readHistoryThreadList,
  readSessionIndexHumanStartedSupplements,
  sanitizeRelayFields,
  setThreadName,
  liveStatusCacheForConfig,
  sessionRouterForConfig,
  statusPriority,
  unarchiveThread,
  upstreamPoolForConfig,
};

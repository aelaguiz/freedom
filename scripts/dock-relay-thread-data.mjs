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
import { ThreadSummaryCache } from "./dock-relay-thread-summary-cache.mjs";
import { HistoryClient, UpstreamConnectionPool } from "./dock-relay-upstream-pool.mjs";
import {
  classifyThreadOrigin,
  humanThreadRejectedError,
  isHumanStartedThread,
} from "./dock-relay-human-thread-filter.mjs";
import {
  timestampToISO,
  timestampToMs,
} from "./dock-relay-state-views.mjs";

function relayLogger(config) {
  return config?.logger || defaultRelayLogger;
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
  if (!config.historyClient) {
    config.historyClient = new HistoryClient({
      pool: upstreamPoolForConfig(config),
      url: config.historyUrl,
      bearerToken: config.historyBearerToken,
      logger: relayLogger(config),
      initializer: initializeClient,
    });
  }
  return config.historyClient;
}

function liveStatusCacheForConfig(config) {
  if (!config.liveStatusCache) {
    config.liveStatusCache = new LiveStatusCache({
      collectLiveRows: () => collectLiveRows({
        logger: relayLogger(config),
        endpoints: configuredLiveEndpointsForConfig(config, { includeHistory: false }),
        excludeURLs: [],
        pool: upstreamPoolForConfig(config),
      }),
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
      historyEndpoint: {
        url: config.historyUrl,
        bearerToken: config.historyBearerToken,
      },
    });
  }
  return config.sessionRouter;
}

function threadSummaryCacheForConfig(config) {
  if (!config.threadSummaryCache) {
    config.threadSummaryCache = new ThreadSummaryCache({
      readThreadTurns: (params) => listThreadTurns(config, params),
      logger: relayLogger(config),
    });
  }
  return config.threadSummaryCache;
}

function configuredLiveEndpointsForConfig(config, { includeHistory = false } = {}) {
  const endpoints = [];
  if (includeHistory && config.historyUrl) {
    endpoints.push({
      label: "history",
      url: config.historyUrl,
      bearerToken: config.historyBearerToken || null,
    });
  }
  for (const endpoint of config.liveEndpoints || []) {
    if (!endpoint?.url) {
      continue;
    }
    endpoints.push({
      label: endpoint.label || endpoint.url,
      url: endpoint.url,
      bearerToken: endpoint.bearerToken || config.historyBearerToken || null,
    });
  }
  const seen = new Set();
  return endpoints.filter((endpoint) => {
    const key = canonicalURLString(endpoint.url);
    if (seen.has(key)) {
      return false;
    }
    seen.add(key);
    return true;
  });
}

function isHistoryEndpoint(config, endpoint) {
  return endpoint?.url === config.historyUrl
    && (endpoint.bearerToken || null) === (config.historyBearerToken || null);
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
} = {}) {
  if (pool) {
    return pool.clientFor({
      label,
      url: endpoint.url,
      bearerToken: endpoint.bearerToken || null,
      timeoutMs,
      initializer: initializeClient,
    });
  }
  const client = new JsonRpcWebSocketClient(endpoint.url, {
    bearerToken: endpoint.bearerToken || null,
    timeoutMs,
    logger,
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
} = {}) {
  return withEndpointClient(endpoint, { logger, pool, label: "live-status", timeoutMs }, async (client) => {
    const loaded = await client.request("thread/loaded/list", { limit: LIVE_LOADED_LIST_LIMIT });
    const results = await Promise.allSettled((loaded.data || []).map((threadId) => (
      client.request("thread/read", {
        threadId,
        includeTurns: false,
      })
    )));
    const rows = [];
    let failedThreadReads = 0;
    for (let index = 0; index < results.length; index += 1) {
      const result = results[index];
      if (result.status === "rejected") {
        failedThreadReads += 1;
        logger.warn("live.thread_read_failed", {
          threadId: loaded.data[index],
          endpointUrl: endpoint.url,
          error: result.reason,
        });
        continue;
      }
      if (result.value?.thread?.id) {
        const row = { ...result.value.thread, dockRelaySource: endpoint };
        const classification = classifyThreadOrigin(row);
        if (classification.allowed) {
          rows.push(row);
        } else {
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
      totalThreadReads: (loaded.data || []).length,
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
  const pool = typeof options?.warn === "function" ? null : options.pool || null;
  const excludedURLs = new Set((typeof options?.warn === "function" ? [] : options.excludeURLs || [])
    .map(canonicalURLString));
  const endpoints = (typeof options?.warn === "function" ? [] : options.endpoints || [])
    .filter((endpoint) => !excludedURLs.has(canonicalURLString(endpoint.url)));
  const maxConcurrent = pool?.labelLimit?.("live-status") || endpoints.length || 1;
  const results = await allSettledInBatches(
    endpoints,
    maxConcurrent,
    (endpoint) => readLoadedRows(endpoint, {
      logger,
      pool,
      timeoutMs: LIVE_STATUS_UPSTREAM_TIMEOUT_MS,
    }),
  );
  const rowsById = new Map();
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
    for (const row of result.value?.rows || []) {
      rowsById.set(row.id, preferThread(row, rowsById.get(row.id)));
    }
  }
  return {
    endpoints,
    failedEndpoints,
    totalThreadReads,
    failedThreadReads,
    rows: [...rowsById.values()],
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
  const candidates = [];
  const rejectedCounts = {};

  for (const row of rows) {
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
      const authoritative = mergeAuthoritativeThreadRead(row, response?.thread);
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

  const rejectedCounts = {};
  const results = await allSettledInBatches(
    candidates,
    HUMAN_THREAD_READ_ENRICHMENT_CONCURRENCY,
    async (candidate) => {
      const response = await readThread(candidate.id);
      const thread = mergeSessionIndexCandidate(candidate, response?.thread);
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

function assertRouteHumanStartedThread(row, threadId) {
  const classification = classifyThreadOrigin(row);
  if (!classification.allowed) {
    throw humanThreadRejectedError(threadId || row?.id || row?.threadId || row?.threadID, classification.reason);
  }
  return row;
}

async function readHumanThreadForRoute(config, threadId) {
  const liveRow = await sessionRouterForConfig(config).rowForThread(threadId);
  if (liveRow) {
    return assertRouteHumanStartedThread(liveRow, threadId);
  }
  const history = await readHistoryThread(config, { threadId, includeTurns: false });
  return assertRouteHumanStartedThread(history?.thread, threadId);
}

async function assertHumanThreadID(config, threadId) {
  return sanitizeRelayFields(await readHumanThreadForRoute(config, threadId));
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

async function aggregateThreadRead(config, params = {}) {
  if (!params.threadId) {
    throw new Error("thread/read requires threadId");
  }
  const liveRow = await sessionRouterForConfig(config).rowForThread(params.threadId);
  if (liveRow) {
    assertRouteHumanStartedThread(liveRow, params.threadId);
    if (params.includeTurns) {
      const result = await readThreadFromEndpoint(liveRow.dockRelaySource, params, relayLogger(config));
      assertRouteHumanStartedThread(result?.thread, params.threadId);
      return result;
    }
    return { thread: sanitizeRelayFields(liveRow) };
  }
  const result = await readHistoryThread(config, params);
  assertRouteHumanStartedThread(result?.thread, params.threadId);
  return result;
}

async function listThreadTurns(config, params = {}) {
  if (!params.threadId) {
    throw new Error("thread/turns/list requires threadId");
  }
  await assertHumanThreadID(config, params.threadId);
  const endpoint = await endpointForThread(config, params.threadId);
  if (isHistoryEndpoint(config, endpoint)) {
    return historyClientForConfig(config).request("thread/turns/list", params);
  }
  return readThreadTurnsFromEndpoint(endpoint, params, undefined, relayLogger(config));
}

async function readNewestTurnActivity(config, threadId) {
  const pages = [];
  const seenCursors = new Set();
  let cursor = null;
  let newestTurnActivityAtMs = 0;

  while (true) {
    const response = await listThreadTurns(config, {
      threadId,
      limit: THREAD_LIST_MAX_LIMIT,
      ...(cursor ? { cursor } : {}),
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
      const turns = await readNewestTurnActivity(config, row.id);
      const activityAtMs = Math.max(baseActivityAtMs, turns.newestTurnActivityAtMs);
      return {
        ...row,
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

async function endpointForThread(config, threadId) {
  return sessionRouterForConfig(config).endpointForThread(threadId);
}

async function archiveThread(config, params = {}) {
  if (!params.threadId) {
    throw new Error("thread/archive requires threadId");
  }
  await assertHumanThreadID(config, params.threadId);
  const endpoint = await endpointForThread(config, params.threadId);
  if (isHistoryEndpoint(config, endpoint)) {
    return historyClientForConfig(config).request("thread/archive", params);
  }
  return withClient(
    endpoint.url,
    { bearerToken: endpoint.bearerToken || null, logger: relayLogger(config) },
    async (client) => client.request("thread/archive", params),
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
  configuredLiveEndpointsForConfig,
  drainThreadListRows,
  endpointForThread,
  enrichHumanStartedRows,
  initializeClient,
  listThreadTurns,
  mergeHumanStartedRowsWithSupplements,
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
  liveStatusCacheForConfig,
  sessionRouterForConfig,
  statusPriority,
  threadSummaryCacheForConfig,
  unarchiveThread,
  upstreamPoolForConfig,
};

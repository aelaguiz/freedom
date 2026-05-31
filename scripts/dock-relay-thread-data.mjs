import { defaultRelayLogger } from "./dock-relay-logger.mjs";
import {
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
  filterHumanBaseThreads,
  humanThreadRejectedError,
  isHumanBaseThread,
} from "./dock-relay-human-thread-filter.mjs";

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
    for (let index = 0; index < results.length; index += 1) {
      const result = results[index];
      if (result.status === "rejected") {
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
    return rows;
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
    for (const row of result.value) {
      rowsById.set(row.id, preferThread(row, rowsById.get(row.id)));
    }
  }
  return {
    endpoints,
    failedEndpoints,
    rows: [...rowsById.values()],
  };
}

async function readHistoryThreadList(config, params) {
  return historyClientForConfig(config).request("thread/list", params);
}

async function readHistoryThreadSearch(config, params) {
  return historyClientForConfig(config).request("thread/search", params);
}

async function readHistoryThread(config, params) {
  return historyClientForConfig(config).request("thread/read", params);
}

async function readHistoryThreadGoal(config, params) {
  return historyClientForConfig(config).request("thread/goal/get", params);
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

async function readThreadGoalFromEndpoint(endpoint, params, logger = defaultRelayLogger) {
  return withClient(
    endpoint.url,
    { bearerToken: endpoint.bearerToken || null, logger },
    async (client) => client.request("thread/goal/get", params),
  );
}

function sanitizeRelayFields(thread) {
  if (!thread || typeof thread !== "object") {
    return thread;
  }
  const { dockRelaySource, ...clean } = thread;
  return clean;
}

function sanitizeThreadSearchResult(result) {
  if (!result || typeof result !== "object") {
    return result;
  }
  if (result.thread && typeof result.thread === "object") {
    return {
      ...result,
      thread: sanitizeRelayFields(result.thread),
    };
  }
  if (result.id) {
    return sanitizeRelayFields(result);
  }
  return result;
}

function threadRowFromSearchResult(result) {
  if (result?.thread && typeof result.thread === "object") {
    return result.thread;
  }
  return result;
}

function filterHumanSearchResults(results = []) {
  const acceptedResults = [];
  const rejectedCounts = {};
  for (const result of results) {
    const classification = classifyThreadOrigin(threadRowFromSearchResult(result));
    if (classification.allowed) {
      acceptedResults.push(result);
      continue;
    }
    rejectedCounts[classification.reason] = Number(rejectedCounts[classification.reason] || 0) + 1;
  }
  return { acceptedResults, rejectedCounts };
}

function assertRouteHumanBaseThread(row, threadId) {
  const classification = classifyThreadOrigin(row);
  if (!classification.allowed) {
    throw humanThreadRejectedError(threadId || row?.id || row?.threadId || row?.threadID, classification.reason);
  }
  return row;
}

async function readHumanThreadForRoute(config, threadId) {
  const liveRow = await sessionRouterForConfig(config).rowForThread(threadId);
  if (liveRow) {
    return assertRouteHumanBaseThread(liveRow, threadId);
  }
  const history = await readHistoryThread(config, { threadId, includeTurns: false });
  return assertRouteHumanBaseThread(history?.thread, threadId);
}

async function assertHumanThreadID(config, threadId) {
  return sanitizeRelayFields(await readHumanThreadForRoute(config, threadId));
}

async function aggregateThreadList(config, params = {}) {
  const logger = relayLogger(config);
  const historyParams = humanOnlyThreadListParams(params);
  const history = await readHistoryThreadList(config, historyParams);
  const data = Array.isArray(history.data) ? history.data : [];
  const { acceptedRows, rejectedCounts } = filterHumanBaseThreads(data);
  const liveOverlay = history.liveOverlay || liveStatusCacheForConfig(config).liveOverlay();
  logger.info("thread_list.loaded", {
    historyRows: data.length,
    requestedLimit: params.limit,
    effectiveLimit: historyParams.limit,
    returnedRows: acceptedRows.length,
    rejectedCounts,
    liveOverlayState: liveOverlay?.state || (liveOverlay?.ok ? "healthy" : "unknown"),
  });
  return {
    ...history,
    data: acceptedRows,
    liveOverlay,
  };
}

async function aggregateThreadSearch(config, params = {}) {
  const logger = relayLogger(config);
  const historyParams = humanOnlyThreadListParams(params);
  const history = await readHistoryThreadSearch(config, historyParams);
  const rawData = Array.isArray(history.data) ? history.data : [];
  const { acceptedResults, rejectedCounts } = filterHumanSearchResults(rawData);
  const data = acceptedResults.map(sanitizeThreadSearchResult);
  logger.info("thread_search.loaded", {
    requestedLimit: params.limit,
    effectiveLimit: historyParams.limit,
    returnedRows: data.length,
    rejectedCounts,
  });
  return {
    ...history,
    data,
  };
}

async function aggregateThreadGoalGet(config, params = {}) {
  if (!params.threadId) {
    throw new Error("thread/goal/get requires threadId");
  }
  await assertHumanThreadID(config, params.threadId);
  const endpoint = await endpointForThread(config, params.threadId);
  const result = isHistoryEndpoint(config, endpoint)
    ? await readHistoryThreadGoal(config, params)
    : await readThreadGoalFromEndpoint(endpoint, params, relayLogger(config));
  relayLogger(config).info("thread_goal_get.loaded", {
    goalPresent: result?.goal != null,
  });
  return result;
}

async function aggregateLoadedList(config, params = {}) {
  const logger = relayLogger(config);
  const snapshot = await liveStatusCacheForConfig(config).snapshotForRouting();
  const rows = snapshot.rows.filter(isHumanBaseThread);
  const ids = rows.map((row) => row.id);
  logger.info("thread_loaded_list.loaded", {
    liveRows: ids.length,
    endpoints: snapshot.endpoints.length,
    failedEndpoints: snapshot.failedEndpoints,
  });
  return paginateStrings(ids, params);
}

async function aggregateThreadRead(config, params = {}) {
  if (!params.threadId) {
    throw new Error("thread/read requires threadId");
  }
  const liveRow = await sessionRouterForConfig(config).rowForThread(params.threadId);
  if (liveRow) {
    assertRouteHumanBaseThread(liveRow, params.threadId);
    if (params.includeTurns) {
      const result = await readThreadFromEndpoint(liveRow.dockRelaySource, params, relayLogger(config));
      assertRouteHumanBaseThread(result?.thread, params.threadId);
      return result;
    }
    return { thread: sanitizeRelayFields(liveRow) };
  }
  const result = await readHistoryThread(config, params);
  assertRouteHumanBaseThread(result?.thread, params.threadId);
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
  aggregateLoadedList,
  aggregateThreadGoalGet,
  aggregateThreadList,
  aggregateThreadRead,
  aggregateThreadSearch,
  archiveThread,
  attentionFlagsForServerRequest,
  collectLiveRows,
  configuredLiveEndpointsForConfig,
  endpointForThread,
  initializeClient,
  listThreadTurns,
  mergeActiveFlags,
  parseLimit,
  clampThreadListParams,
  disabledLiveOverlay,
  pendingRequestsForActiveThread,
  preferThread,
  readHistoryThread,
  readHistoryThreadGoal,
  readHistoryThreadList,
  readHistoryThreadSearch,
  sanitizeRelayFields,
  liveStatusCacheForConfig,
  sessionRouterForConfig,
  statusPriority,
  threadSummaryCacheForConfig,
  unarchiveThread,
  upstreamPoolForConfig,
};

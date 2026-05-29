import { execFileSync } from "node:child_process";

import { defaultRelayLogger } from "./dock-relay-logger.mjs";
import { JsonRpcWebSocketClient } from "./dock-relay-json-rpc-client.mjs";
import { threadMatchesSourceKinds } from "./dock-relay-source-filter.mjs";

const RELAY_VERSION = "0.1.0";
const THREAD_LIST_PREVIEW_TURNS_LIMIT = 5;
const THREAD_LIST_PREVIEW_ENRICH_CONCURRENCY = 16;
const THREAD_LIST_PREVIEW_ENRICH_TIMEOUT_MS = 300;

function relayLogger(config) {
  return config?.logger || defaultRelayLogger;
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

async function mapWithConcurrency(values, limit, mapper) {
  if (!values.length) {
    return [];
  }
  const results = new Array(values.length);
  let nextIndex = 0;
  const workerCount = Math.min(limit, values.length);
  const workers = Array.from({ length: workerCount }, async () => {
    while (nextIndex < values.length) {
      const index = nextIndex;
      nextIndex += 1;
      results[index] = await mapper(values[index], index);
    }
  });
  await Promise.all(workers);
  return results;
}

function nonEmptyText(value) {
  if (typeof value !== "string") {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length ? trimmed : null;
}

function userMessageText(content) {
  if (typeof content === "string") {
    return nonEmptyText(content);
  }
  if (!Array.isArray(content)) {
    return null;
  }
  return nonEmptyText(content.map((item) => {
    if (typeof item === "string") {
      return item;
    }
    if (item && typeof item === "object" && typeof item.text === "string") {
      return item.text;
    }
    return "";
  }).filter(Boolean).join("\n"));
}

function collapsePreview(value, maxLength = 500) {
  const firstLine = String(value).split(/\r?\n/, 1)[0] || "";
  const collapsed = firstLine.split(/\s+/).filter(Boolean).join(" ");
  if (collapsed.length <= maxLength) {
    return collapsed;
  }
  return `${collapsed.slice(0, Math.max(0, maxLength - 3))}...`;
}

function meaningfulTextFromTurnItem(item) {
  if (!item || typeof item !== "object") {
    return null;
  }
  switch (item.type) {
    case "userMessage":
      return userMessageText(item.content);
    case "agentMessage":
      return nonEmptyText(item.text);
    default:
      return null;
  }
}

function turnTimestamp(turn) {
  const seconds = Number(turn?.completedAt ?? turn?.startedAt);
  if (Number.isFinite(seconds)) {
    return seconds;
  }
  const milliseconds = Number(turn?.completedAtMs ?? turn?.startedAtMs);
  if (Number.isFinite(milliseconds)) {
    return milliseconds / 1_000;
  }
  return null;
}

function latestMeaningfulTextFromTurns(turns) {
  if (!Array.isArray(turns)) {
    return null;
  }
  let latest = null;
  for (let turnIndex = 0; turnIndex < turns.length; turnIndex += 1) {
    const turn = turns[turnIndex];
    const items = Array.isArray(turn?.items) ? turn.items : [];
    for (let index = items.length - 1; index >= 0; index -= 1) {
      const text = meaningfulTextFromTurnItem(items[index]);
      if (text) {
        const timestamp = turnTimestamp(turn);
        const candidate = {
          text,
          timestamp,
          turnIndex,
          itemIndex: index,
        };
        if (
          !latest
          || (
            candidate.timestamp !== null
            && latest.timestamp !== null
            && candidate.timestamp > latest.timestamp
          )
          || (
            candidate.timestamp === latest.timestamp
            && candidate.turnIndex > latest.turnIndex
          )
          || (
            candidate.timestamp === latest.timestamp
            && candidate.turnIndex === latest.turnIndex
            && candidate.itemIndex > latest.itemIndex
          )
          || (candidate.timestamp !== null && latest.timestamp === null)
        ) {
          latest = candidate;
        }
        break;
      }
    }
  }
  return latest ? collapsePreview(latest.text) : null;
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

function discoverLoopbackEndpoints() {
  const ps = execFileSync("ps", ["-axo", "pid,command"], { encoding: "utf8" });
  const endpoints = [];
  for (const line of ps.split("\n")) {
    const match = line.match(/^\s*(\d+)\s+.*codex app-server --listen (ws:\/\/127\.0\.0\.1:\d+)/);
    if (match) {
      endpoints.push({ pid: Number(match[1]), url: match[2] });
    }
  }
  const byUrl = new Map();
  for (const endpoint of endpoints) {
    if (!byUrl.has(endpoint.url) || endpoint.pid < byUrl.get(endpoint.url).pid) {
      byUrl.set(endpoint.url, endpoint);
    }
  }
  return [...byUrl.values()].sort((lhs, rhs) => lhs.pid - rhs.pid);
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

async function readLoadedRows(endpoint, logger = defaultRelayLogger) {
  return withClient(endpoint.url, { logger }, async (client) => {
    const loaded = await client.request("thread/loaded/list", { limit: 500 });
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
        rows.push({ ...result.value.thread, dockRelaySource: endpoint });
      }
    }
    return Promise.all(rows.map((row) => enrichRowAttention(row, endpoint, logger)));
  });
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

async function collectLiveRows(logger = defaultRelayLogger) {
  const endpoints = discoverLoopbackEndpoints();
  const results = await Promise.allSettled(endpoints.map((endpoint) => readLoadedRows(endpoint, logger)));
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
  return withClient(
    config.historyUrl,
    { bearerToken: config.historyBearerToken, logger: relayLogger(config) },
    async (client) => client.request("thread/list", params),
  );
}

async function readHistoryThread(config, params) {
  return withClient(
    config.historyUrl,
    { bearerToken: config.historyBearerToken, logger: relayLogger(config) },
    async (client) => client.request("thread/read", params),
  );
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

function shouldCollectLiveRowsForThreadList(params = {}) {
  return params.archived !== true;
}

function mergeLiveRowWithHistoryFreshness(liveRow, historyRow) {
  if (!historyRow) {
    return liveRow;
  }

  const historyTimestamp = rowTimestamp(historyRow);
  if (!Number.isFinite(historyTimestamp)) {
    return liveRow;
  }

  const liveTimestamp = rowTimestamp(liveRow);
  if (Number.isFinite(liveTimestamp) && historyTimestamp <= liveTimestamp) {
    return liveRow;
  }

  return {
    ...liveRow,
    updatedAt: historyTimestamp,
  };
}

function mergeThreadListRows(historyRows = [], liveRows = [], params = {}) {
  const historyById = new Map();
  for (const row of historyRows) {
    if (!row?.id) {
      continue;
    }
    const existing = historyById.get(row.id);
    if (!existing || rowTimestamp(row) >= rowTimestamp(existing)) {
      historyById.set(row.id, row);
    }
  }
  const freshenedLiveRows = liveRows.map((row) => (
    mergeLiveRowWithHistoryFreshness(row, historyById.get(row?.id))
  ));
  const liveIds = new Set(freshenedLiveRows.map((row) => row.id));
  const sortRows = (rows) => [...rows].sort((lhs, rhs) => {
    const timestampDelta = rowTimestamp(rhs) - rowTimestamp(lhs);
    if (timestampDelta !== 0) {
      return timestampDelta;
    }
    const statusDelta = statusPriority(lhs) - statusPriority(rhs);
    if (statusDelta !== 0) {
      return statusDelta;
    }
    return String(lhs.id || "").localeCompare(String(rhs.id || ""));
  });

  const sortedLiveRows = sortRows(freshenedLiveRows.map(sanitizeRelayFields));
  const historyOnlyRows = sortRows(historyRows.filter((row) => !liveIds.has(row.id)));
  const limit = parseLimit(params.limit, sortedLiveRows.length + historyOnlyRows.length || 1);
  return [
    ...sortedLiveRows.slice(0, limit),
    ...historyOnlyRows.slice(0, Math.max(0, limit - sortedLiveRows.length)),
  ];
}

async function enrichThreadListPreviews(config, rows, endpointByThreadId = new Map()) {
  const logger = relayLogger(config);
  return mapWithConcurrency(
    rows,
    THREAD_LIST_PREVIEW_ENRICH_CONCURRENCY,
    async (row) => {
      if (!row?.id) {
        return row;
      }
      const endpoint = endpointByThreadId.get(row.id) || {
        url: config.historyUrl,
        bearerToken: config.historyBearerToken,
      };
      try {
        const turns = await readThreadTurnsFromEndpoint(endpoint, {
          threadId: row.id,
          limit: THREAD_LIST_PREVIEW_TURNS_LIMIT,
        }, THREAD_LIST_PREVIEW_ENRICH_TIMEOUT_MS, logger);
        const preview = latestMeaningfulTextFromTurns(turns?.data);
        if (!preview) {
          return row;
        }
        return {
          ...row,
          preview,
        };
      } catch (error) {
        logger.warn("thread_list.preview_enrich_failed", {
          threadId: row.id,
          endpointUrl: endpoint.url,
          error,
        });
        return row;
      }
    },
  );
}

async function aggregateThreadList(config, params = {}) {
  const logger = relayLogger(config);
  if (!shouldCollectLiveRowsForThreadList(params)) {
    const history = await readHistoryThreadList(config, params);
    const data = await enrichThreadListPreviews(config, history.data || []);
    logger.info("thread_list.archived_loaded", {
      historyRows: history.data?.length || 0,
      liveRows: 0,
      returnedRows: data.length,
    });
    return {
      ...history,
      data,
    };
  }

  const [historyResult, liveResult] = await Promise.allSettled([
    readHistoryThreadList(config, params),
    collectLiveRows(logger),
  ]);
  if (historyResult.status === "rejected" && liveResult.status === "rejected") {
    throw new Error(
      `thread/list failed for history and live sources: history=${historyResult.reason?.message || historyResult.reason}; live=${liveResult.reason?.message || liveResult.reason}`,
    );
  }

  const history = historyResult.status === "fulfilled"
    ? historyResult.value
    : { data: [] };
  const live = liveResult.status === "fulfilled"
    ? liveResult.value
    : { endpoints: [], failedEndpoints: 1, rows: [] };

  if (historyResult.status === "rejected") {
    logger.warn("thread_list.history_failed", {
      error: historyResult.reason,
    });
  }
  if (liveResult.status === "rejected") {
    logger.warn("thread_list.live_failed", {
      error: liveResult.reason,
    });
  }

  const filteredLiveRows = live.rows.filter((row) => (
    threadMatchesSourceKinds(row, params.sourceKinds)
  ));
  const endpointByThreadId = new Map(
    filteredLiveRows
      .filter((row) => row?.id && row.dockRelaySource)
      .map((row) => [row.id, row.dockRelaySource]),
  );
  const data = await enrichThreadListPreviews(
    config,
    mergeThreadListRows(history.data || [], filteredLiveRows, params),
    endpointByThreadId,
  );
  logger.info("thread_list.loaded", {
    historyRows: history.data?.length || 0,
    liveRows: filteredLiveRows.length,
    endpoints: live.endpoints.length,
    failedEndpoints: live.failedEndpoints,
    returnedRows: data.length,
  });
  return {
    data,
    nextCursor: null,
    backwardsCursor: null,
  };
}

async function aggregateLoadedList(params = {}, logger = defaultRelayLogger) {
  const live = await collectLiveRows(logger);
  const ids = live.rows.map((row) => row.id);
  logger.info("thread_loaded_list.loaded", {
    liveRows: ids.length,
    endpoints: live.endpoints.length,
    failedEndpoints: live.failedEndpoints,
  });
  return paginateStrings(ids, params);
}

async function aggregateThreadRead(config, params = {}) {
  if (!params.threadId) {
    throw new Error("thread/read requires threadId");
  }
  const live = await collectLiveRows(relayLogger(config));
  const liveRow = live.rows.find((row) => row.id === params.threadId);
  if (liveRow) {
    if (params.includeTurns) {
      return readThreadFromEndpoint(liveRow.dockRelaySource, params, relayLogger(config));
    }
    return { thread: sanitizeRelayFields(liveRow) };
  }
  return readHistoryThread(config, params);
}

async function listThreadTurns(config, params = {}) {
  if (!params.threadId) {
    throw new Error("thread/turns/list requires threadId");
  }
  const endpoint = await endpointForThread(config, params.threadId);
  return readThreadTurnsFromEndpoint(endpoint, params, undefined, relayLogger(config));
}

async function endpointForThread(config, threadId) {
  const live = await collectLiveRows(relayLogger(config));
  const liveRow = live.rows.find((row) => row.id === threadId);
  if (liveRow?.dockRelaySource) {
    return liveRow.dockRelaySource;
  }
  return {
    url: config.historyUrl,
    bearerToken: config.historyBearerToken,
  };
}

async function archiveThread(config, params = {}) {
  if (!params.threadId) {
    throw new Error("thread/archive requires threadId");
  }
  const endpoint = await endpointForThread(config, params.threadId);
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
  return withClient(
    config.historyUrl,
    { bearerToken: config.historyBearerToken, logger: relayLogger(config) },
    async (client) => client.request("thread/unarchive", params),
  );
}

export {
  aggregateLoadedList,
  aggregateThreadList,
  aggregateThreadRead,
  archiveThread,
  attentionFlagsForServerRequest,
  collectLiveRows,
  endpointForThread,
  initializeClient,
  listThreadTurns,
  mergeActiveFlags,
  mergeThreadListRows,
  parseLimit,
  pendingRequestsForActiveThread,
  preferThread,
  sanitizeRelayFields,
  shouldCollectLiveRowsForThreadList,
  statusPriority,
  unarchiveThread,
};

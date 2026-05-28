#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import fs from "node:fs";
import http from "node:http";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import WebSocket, { WebSocketServer } from "ws";

const DEFAULT_TIMEOUT_MS = 5_000;
const RELAY_VERSION = "0.1.0";

function parseArgs(argv) {
  const result = {};
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (!arg.startsWith("--")) {
      throw new Error(`unexpected argument: ${arg}`);
    }
    const key = arg.slice(2);
    const value = argv[index + 1];
    if (!value || value.startsWith("--")) {
      throw new Error(`missing value for --${key}`);
    }
    result[key] = value;
    index += 1;
  }
  return result;
}

function readToken(path) {
  const value = fs.readFileSync(path, "utf8").trim();
  if (!value) {
    throw new Error(`token file is empty: ${path}`);
  }
  return value;
}

function jsonRpcError(id, code, message, data = undefined) {
  const error = { code, message };
  if (data !== undefined) {
    error.data = data;
  }
  return { jsonrpc: "2.0", id, error };
}

function jsonRpcResult(id, result) {
  return { jsonrpc: "2.0", id, result };
}

function sendJson(ws, value) {
  if (ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify(value));
  }
}

function platformOs() {
  if (process.platform === "darwin") {
    return "macos";
  }
  return process.platform;
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

class JsonRpcWebSocketClient {
  constructor(
    url,
    {
      bearerToken = null,
      timeoutMs = DEFAULT_TIMEOUT_MS,
      onNotification = null,
      onRequest = null,
    } = {},
  ) {
    this.url = url;
    this.bearerToken = bearerToken;
    this.timeoutMs = timeoutMs;
    this.onNotification = onNotification;
    this.onRequest = onRequest;
    this.nextId = 1;
    this.pending = new Map();
    this.ws = null;
  }

  connect() {
    if (this.ws) {
      return Promise.resolve();
    }
    const headers = {};
    if (this.bearerToken) {
      headers.Authorization = `Bearer ${this.bearerToken}`;
    }
    return new Promise((resolve, reject) => {
      const ws = new WebSocket(this.url, { headers });
      const timer = setTimeout(() => {
        reject(new Error(`timed out connecting to ${this.url}`));
        ws.close();
      }, this.timeoutMs);
      ws.on("open", () => {
        clearTimeout(timer);
        this.ws = ws;
        resolve();
      });
      ws.on("message", (data) => this.handleMessage(data));
      ws.on("error", (error) => {
        clearTimeout(timer);
        this.rejectAll(error);
        if (!this.ws) {
          reject(error);
        }
      });
      ws.on("close", () => {
        this.rejectAll(new Error(`websocket closed: ${this.url}`));
        this.ws = null;
      });
    });
  }

  handleMessage(data) {
    let message;
    try {
      message = JSON.parse(data.toString());
    } catch {
      return;
    }
    if (message.id !== undefined && this.pending.has(String(message.id))) {
      const pending = this.pending.get(String(message.id));
      this.pending.delete(String(message.id));
      clearTimeout(pending.timer);
      if (message.error) {
        pending.reject(new Error(`${pending.method}: ${JSON.stringify(message.error)}`));
      } else {
        pending.resolve(message.result);
      }
      return;
    }

    if (message.method && message.id !== undefined) {
      this.onRequest?.(message);
      return;
    }

    if (message.method) {
      this.onNotification?.(message);
    }
  }

  request(method, params = undefined) {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) {
      return Promise.reject(new Error(`not connected: ${this.url}`));
    }
    const id = String(this.nextId);
    this.nextId += 1;
    const payload = { jsonrpc: "2.0", id, method };
    if (params !== undefined) {
      payload.params = params;
    }
    this.ws.send(JSON.stringify(payload));
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`timed out waiting for ${method} from ${this.url}`));
      }, this.timeoutMs);
      this.pending.set(id, { method, resolve, reject, timer });
    });
  }

  notify(method, params = undefined) {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) {
      return;
    }
    const payload = { jsonrpc: "2.0", method };
    if (params !== undefined) {
      payload.params = params;
    }
    this.ws.send(JSON.stringify(payload));
  }

  sendRaw(message) {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) {
      return false;
    }
    this.ws.send(typeof message === "string" ? message : JSON.stringify(message));
    return true;
  }

  close() {
    if (this.ws) {
      this.ws.close();
      this.ws = null;
    }
  }

  rejectAll(error) {
    for (const pending of this.pending.values()) {
      clearTimeout(pending.timer);
      pending.reject(error);
    }
    this.pending.clear();
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

async function readLoadedRows(endpoint) {
  return withClient(endpoint.url, {}, async (client) => {
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
        console.error(
          `dock-relay: failed to read ${loaded.data[index]} from ${endpoint.url}: ${result.reason?.message || result.reason}`,
        );
        continue;
      }
      if (result.value?.thread?.id) {
        rows.push({ ...result.value.thread, dockRelaySource: endpoint });
      }
    }
    return Promise.all(rows.map((row) => enrichRowAttention(row, endpoint)));
  });
}

async function pendingRequestsForActiveThread(endpoint, threadId) {
  const requests = [];
  const client = new JsonRpcWebSocketClient(endpoint.url, {
    bearerToken: endpoint.bearerToken || null,
    onRequest: (message) => {
      if (message?.params?.threadId === threadId) {
        requests.push(message);
      }
    },
  });
  try {
    await initializeClient(client);
    await client.request("thread/resume", { threadId });
    await sleep(100);
    return requests;
  } finally {
    client.close();
  }
}

async function enrichRowAttention(row, endpoint) {
  if (row?.status?.type !== "active") {
    return row;
  }
  const existingFlags = new Set(row.status.activeFlags || []);
  if (existingFlags.has("waitingOnApproval") || existingFlags.has("waitingOnUserInput")) {
    return row;
  }

  let requests;
  try {
    requests = await pendingRequestsForActiveThread(endpoint, row.id);
  } catch (error) {
    console.error(
      `dock-relay: failed to inspect pending requests for ${row.id} from ${endpoint.url}: ${error.message || error}`,
    );
    return row;
  }

  const flags = requests.flatMap(attentionFlagsForServerRequest);
  return mergeActiveFlags(row, flags);
}

async function collectLiveRows() {
  const endpoints = discoverLoopbackEndpoints();
  const results = await Promise.allSettled(endpoints.map(readLoadedRows));
  const rowsById = new Map();
  let failedEndpoints = 0;
  for (let index = 0; index < results.length; index += 1) {
    const result = results[index];
    if (result.status === "rejected") {
      failedEndpoints += 1;
      console.error(
        `dock-relay: failed to query ${endpoints[index].url}: ${result.reason?.message || result.reason}`,
      );
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
    { bearerToken: config.historyBearerToken },
    async (client) => client.request("thread/list", params),
  );
}

async function readHistoryThread(config, params) {
  return withClient(
    config.historyUrl,
    { bearerToken: config.historyBearerToken },
    async (client) => client.request("thread/read", params),
  );
}

async function readThreadFromEndpoint(endpoint, params) {
  return withClient(
    endpoint.url,
    { bearerToken: endpoint.bearerToken || null },
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

async function aggregateThreadList(config, params = {}) {
  if (!shouldCollectLiveRowsForThreadList(params)) {
    const history = await readHistoryThreadList(config, params);
    console.error(
      `dock-relay: thread/list archived history=${history.data?.length || 0} live=0 returned=${history.data?.length || 0}`,
    );
    return history;
  }

  const [historyResult, liveResult] = await Promise.allSettled([
    readHistoryThreadList(config, params),
    collectLiveRows(),
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
    console.error(
      `dock-relay: history thread/list failed: ${historyResult.reason?.message || historyResult.reason}`,
    );
  }
  if (liveResult.status === "rejected") {
    console.error(
      `dock-relay: live thread/list failed: ${liveResult.reason?.message || liveResult.reason}`,
    );
  }

  const liveIds = new Set(live.rows.map((row) => row.id));
  const merged = [];
  for (const row of live.rows) {
    merged.push(sanitizeRelayFields(row));
  }
  for (const row of history.data || []) {
    if (!liveIds.has(row.id)) {
      merged.push(row);
    }
  }

  merged.sort((lhs, rhs) => {
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

  const limit = parseLimit(params.limit, merged.length || 1);
  const data = merged.slice(0, limit);
  console.error(
    `dock-relay: thread/list history=${history.data?.length || 0} live=${live.rows.length} endpoints=${live.endpoints.length} failed=${live.failedEndpoints} returned=${data.length}`,
  );
  return {
    data,
    nextCursor: null,
    backwardsCursor: null,
  };
}

async function aggregateLoadedList(params = {}) {
  const live = await collectLiveRows();
  const ids = live.rows.map((row) => row.id);
  console.error(
    `dock-relay: thread/loaded/list live=${ids.length} endpoints=${live.endpoints.length} failed=${live.failedEndpoints}`,
  );
  return paginateStrings(ids, params);
}

async function aggregateThreadRead(config, params = {}) {
  if (!params.threadId) {
    throw new Error("thread/read requires threadId");
  }
  const live = await collectLiveRows();
  const liveRow = live.rows.find((row) => row.id === params.threadId);
  if (liveRow) {
    if (params.includeTurns) {
      return readThreadFromEndpoint(liveRow.dockRelaySource, params);
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
  return withClient(
    endpoint.url,
    { bearerToken: endpoint.bearerToken || null },
    async (client) => client.request("thread/turns/list", params),
  );
}

async function endpointForThread(config, threadId) {
  const live = await collectLiveRows();
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
    { bearerToken: endpoint.bearerToken || null },
    async (client) => client.request("thread/archive", params),
  );
}

async function unarchiveThread(config, params = {}) {
  if (!params.threadId) {
    throw new Error("thread/unarchive requires threadId");
  }
  return withClient(
    config.historyUrl,
    { bearerToken: config.historyBearerToken },
    async (client) => client.request("thread/unarchive", params),
  );
}

async function resumeThread(config, params = {}, session, downstreamWs) {
  if (!params.threadId) {
    throw new Error("thread/resume requires threadId");
  }

  session.upstream?.close();
  session.upstream = null;

  const live = await collectLiveRows();
  const liveRow = live.rows.find((row) => row.id === params.threadId);
  const endpoint = liveRow?.dockRelaySource || {
    url: config.historyUrl,
    bearerToken: config.historyBearerToken,
  };
  const client = new JsonRpcWebSocketClient(endpoint.url, {
    bearerToken: endpoint.bearerToken || null,
    onNotification: (message) => sendJson(downstreamWs, message),
    onRequest: (message) => sendJson(downstreamWs, message),
  });

  try {
    await initializeClient(client);
    const result = await client.request("thread/resume", params);
    session.upstream = client;
    console.error(
      `dock-relay: thread/resume thread=${params.threadId} upstream=${endpoint.url}`,
    );
    return result;
  } catch (error) {
    client.close();
    throw error;
  }
}

async function forwardToActiveUpstream(session, method, params = {}) {
  if (!session.upstream) {
    throw new Error(`${method} requires thread/resume on this connection first`);
  }
  return session.upstream.request(method, params);
}

async function handleRequest(config, method, params, session, downstreamWs) {
  switch (method) {
    case "initialize":
      return {
        userAgent: `codex_dock_relay/${RELAY_VERSION} (${os.type()} ${os.release()}; ${os.arch()})`,
        codexHome: process.env.CODEX_HOME || `${os.homedir()}/.codex`,
        platformFamily: "unix",
        platformOs: platformOs(),
      };
    case "thread/list":
      return aggregateThreadList(config, params || {});
    case "thread/loaded/list":
      return aggregateLoadedList(params || {});
    case "thread/read":
      return aggregateThreadRead(config, params || {});
    case "thread/turns/list":
      return listThreadTurns(config, params || {});
    case "thread/resume":
      return resumeThread(config, params || {}, session, downstreamWs);
    case "thread/archive":
      return archiveThread(config, params || {});
    case "thread/unarchive":
      return unarchiveThread(config, params || {});
    case "turn/start":
    case "turn/steer":
    case "turn/interrupt":
      return forwardToActiveUpstream(session, method, params || {});
    default:
      throw Object.assign(new Error(`unsupported method: ${method}`), {
        code: -32601,
      });
  }
}

function assertAuthorized(request, token) {
  const header = request.headers.authorization || "";
  return header === `Bearer ${token}`;
}

function startServer(config) {
  const server = http.createServer((request, response) => {
    if (request.url === "/readyz" || request.url === "/healthz") {
      response.writeHead(200, { "content-type": "application/json" });
      response.end(JSON.stringify({ ok: true, service: "codex-dock-relay" }));
      return;
    }
    response.writeHead(404, { "content-type": "text/plain" });
    response.end("not found\n");
  });
  const wss = new WebSocketServer({ noServer: true });

  server.on("upgrade", (request, socket, head) => {
    if (!assertAuthorized(request, config.relayBearerToken)) {
      socket.write("HTTP/1.1 401 Unauthorized\r\nConnection: close\r\n\r\n");
      socket.destroy();
      return;
    }
    wss.handleUpgrade(request, socket, head, (ws) => {
      wss.emit("connection", ws, request);
    });
  });

  wss.on("connection", (ws) => {
    const session = { upstream: null };

    ws.on("close", () => {
      session.upstream?.close();
      session.upstream = null;
    });

    ws.on("message", async (data) => {
      let message;
      try {
        message = JSON.parse(data.toString());
      } catch {
        sendJson(ws, jsonRpcError(null, -32700, "parse error"));
        return;
      }

      if (!message.method && message.id !== undefined) {
        if (!session.upstream?.sendRaw(message)) {
          sendJson(ws, jsonRpcError(message.id, -32000, "no active upstream session"));
        }
        return;
      }

      if (message.id === undefined) {
        return;
      }

      try {
        const result = await handleRequest(config, message.method, message.params, session, ws);
        sendJson(ws, jsonRpcResult(message.id, result));
      } catch (error) {
        sendJson(
          ws,
          jsonRpcError(
            message.id,
            error.code || -32000,
            error.message || "relay error",
          ),
        );
      }
    });
  });

  server.listen(config.port, config.listenHost, () => {
    console.error(
      `codex-dock-relay listening on ws://${config.listenHost}:${config.port}; history=${config.historyUrl}`,
    );
  });
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const relayTokenFile = args["auth-token-file"] || process.env.CODEX_DOCK_RELAY_TOKEN_FILE;
  const historyTokenFile = args["history-auth-token-file"] || process.env.CODEX_DOCK_HISTORY_TOKEN_FILE || relayTokenFile;
  if (!relayTokenFile) {
    throw new Error("--auth-token-file is required");
  }
  if (!historyTokenFile) {
    throw new Error("--history-auth-token-file is required");
  }

  startServer({
    listenHost: args["listen-host"] || process.env.CODEX_DOCK_RELAY_LISTEN_HOST || "0.0.0.0",
    port: parseLimit(args.port || process.env.CODEX_DOCK_RELAY_PORT, 4510),
    relayBearerToken: readToken(relayTokenFile),
    historyBearerToken: readToken(historyTokenFile),
    historyUrl: args["history-url"] || process.env.CODEX_DOCK_HISTORY_APP_SERVER_WS || "ws://127.0.0.1:4500",
  });
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  main();
}

export {
  attentionFlagsForServerRequest,
  mergeActiveFlags,
  preferThread,
  sanitizeRelayFields,
  shouldCollectLiveRowsForThreadList,
  statusPriority,
};

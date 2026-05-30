#!/usr/bin/env node

import crypto from "node:crypto";
import http from "node:http";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import WebSocket, { WebSocketServer } from "ws";

import {
  buildBonjourAdvertisementArgs,
  startBonjourAdvertisement,
} from "./dock-relay-bonjour.mjs";
import {
  DEFAULT_HISTORY_APP_SERVER_WS,
  DEFAULT_PHONE_AUTH,
  DEFAULT_RELAY_LISTEN_HOST,
  DOCK_RELAY_PORT,
  JSON_RPC_MAX_MESSAGE_BYTES,
  RELAY_SHUTDOWN_PROCESS_TIMEOUT_MS,
  RELAY_SHUTDOWN_SOCKET_TIMEOUT_MS,
  RELAY_VERSION,
  UPSTREAM_POOL_LIMITS,
  UPSTREAM_RECONNECT_ATTEMPTS,
  UPSTREAM_RECONNECT_DELAY_MS,
  UPSTREAM_RECONNECT_JITTER_MS,
} from "./dock-relay-constants.mjs";
import {
  defaultRelayLogger,
  installRelayFatalHandlers,
} from "./dock-relay-logger.mjs";
import { JsonRpcWebSocketClient } from "./dock-relay-json-rpc-client.mjs";
import {
  DEFAULT_REALTIME_TRANSCRIPTION_DELAY,
  DEFAULT_REALTIME_TRANSCRIPTION_ENDPOINT,
  DEFAULT_REALTIME_TRANSCRIPTION_LANGUAGE,
  DEFAULT_REALTIME_TRANSCRIPTION_MODEL,
  RealtimeTranscriptionManager,
} from "./dock-relay-realtime-transcription.mjs";
import {
  checkRawAppServerHealth,
  classifyRelayRequestError,
  createRelayStatusTracker,
} from "./dock-relay-status.mjs";
import {
  DOCK_RESYNC_METHOD,
  DOCK_SUBSCRIBE_METHOD,
  dockSessionAggregatorForConfig,
  handleDockSubscribe,
} from "./dock-relay-session-table.mjs";
import { buildRelayStateSnapshot } from "./dock-relay-state-snapshot.mjs";
import {
  loadDotEnvFile,
  parsePhoneAuthMode,
  readToken,
} from "./dock-relay-env.mjs";
import {
  aggregateLoadedList,
  aggregateThreadGoalGet,
  aggregateThreadList,
  aggregateThreadRead,
  aggregateThreadSearch,
  archiveThread,
  attentionFlagsForServerRequest,
  endpointForThread,
  initializeClient,
  listThreadTurns,
  liveStatusCacheForConfig,
  mergeActiveFlags,
  parseLimit,
  pendingRequestsForActiveThread,
  preferThread,
  sanitizeRelayFields,
  sessionRouterForConfig,
  statusPriority,
  unarchiveThread,
} from "./dock-relay-thread-data.mjs";
import { threadMatchesSourceKinds } from "./dock-relay-source-filter.mjs";
import { UpstreamConnectionPool } from "./dock-relay-upstream-pool.mjs";

function shortHash(value) {
  if (!value) {
    return null;
  }
  return crypto.createHash("sha256").update(String(value)).digest("hex").slice(0, 12);
}

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

function relayLogger(config) {
  return config?.logger || defaultRelayLogger;
}

function jsonRpcError(id, code, message, data = undefined) {
  const error = {
    code: Number.isInteger(code) ? code : -32000,
    message,
  };
  if (data !== undefined) {
    error.data = data;
  }
  return { jsonrpc: "2.0", id, error };
}

function jsonRpcErrorCode(error) {
  return Number.isInteger(error?.code) ? error.code : -32000;
}

function jsonRpcResult(id, result) {
  return { jsonrpc: "2.0", id, result };
}

function relayError(message, code = -32000, data = undefined) {
  const error = new Error(message);
  error.code = code;
  if (data !== undefined) {
    error.data = data;
  }
  return error;
}

function sendJson(ws, value) {
  if (ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify(value));
  }
}

function isWebSocketOpen(ws) {
  return ws?.readyState === WebSocket.OPEN;
}

function isSessionActive(session, downstreamWs, generation) {
  return !session.closing
    && session.generation === generation
    && isWebSocketOpen(downstreamWs);
}

function throwIfSessionInactive(session, downstreamWs, generation) {
  if (!isSessionActive(session, downstreamWs, generation)) {
    throw new Error("downstream session closed");
  }
}

function platformOs() {
  if (process.platform === "darwin") {
    return "macos";
  }
  return process.platform;
}

function sleep(ms) {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

function liveResumeParams(params) {
  return {
    ...params,
    excludeTurns: true,
  };
}

function threadIDFromParams(params) {
  const threadId = params?.threadId;
  return typeof threadId === "string" && threadId.length > 0 ? threadId : null;
}

function assertFocusedRequestTargetsBoundThread(session, method, params = {}) {
  if (!session.upstream?.isOpen()) {
    throw new Error(`${method} requires thread/resume on this connection first`);
  }
  const boundThreadId = session.resumeParams?.threadId || null;
  const requestedThreadId = threadIDFromParams(params);
  if (!boundThreadId || !requestedThreadId) {
    throw relayError(`${method} requires threadId matching the active thread`, -32602, {
      subsystem: "live-upstream",
      reason: "missing_thread_id",
    });
  }
  if (requestedThreadId !== boundThreadId) {
    throw relayError(`${method} threadId does not match the active thread`, -32602, {
      subsystem: "live-upstream",
      reason: "thread_mismatch",
      requestedThreadIDHash: shortHash(requestedThreadId),
      activeThreadIDHash: shortHash(boundThreadId),
    });
  }
}

function assertResumeResultMatchesRequestedThread(result, requestedThreadId) {
  const actualThreadId = result?.thread?.id;
  if (actualThreadId !== requestedThreadId) {
    throw relayError("thread/resume returned a different thread", -32000, {
      subsystem: "live-upstream",
      reason: "resume_thread_mismatch",
      requestedThreadIDHash: shortHash(requestedThreadId),
      actualThreadIDHash: shortHash(actualThreadId),
    });
  }
}

function upstreamReconnectDelayMs(attempt) {
  const exponentialDelay = UPSTREAM_RECONNECT_DELAY_MS * (2 ** Math.max(0, attempt - 1));
  const jitter = Math.floor(Math.random() * (UPSTREAM_RECONNECT_JITTER_MS + 1));
  return exponentialDelay + jitter;
}

async function resumeThread(config, params = {}, session, downstreamWs) {
  if (!params.threadId) {
    throw new Error("thread/resume requires threadId");
  }
  const resumeParams = liveResumeParams(params);

  session.generation += 1;
  const generation = session.generation;
  session.retryTask = null;
  session.pendingServerRequests?.clear();
  session.upstream?.close();
  session.upstream = null;

  const logger = relayLogger(config);
  const endpoint = await sessionRouterForConfig(config).endpointForThread(resumeParams.threadId);
  throwIfSessionInactive(session, downstreamWs, generation);
  const client = makeSessionUpstreamClient(config, endpoint, session, downstreamWs, generation);

  try {
    await initializeClient(client);
    throwIfSessionInactive(session, downstreamWs, generation);
    const result = await client.request("thread/resume", resumeParams);
    throwIfSessionInactive(session, downstreamWs, generation);
    assertResumeResultMatchesRequestedThread(result, resumeParams.threadId);
    session.upstream = client;
    session.resumeParams = { ...resumeParams };
    session.endpoint = endpoint;
    logger.info("thread_resume.succeeded", {
      subsystem: "live-upstream",
      hostId: config.hostId,
      threadId: resumeParams.threadId,
      endpointUrl: endpoint.url,
    });
    return result;
  } catch (error) {
    client.close();
    logger.warn("thread_resume.failed", {
      threadId: params.threadId,
      endpointUrl: endpoint.url,
      error,
    });
    config.statusTracker?.recordUpstreamError(error, {
      subsystem: "live-upstream",
      threadId: params.threadId,
      endpointUrl: endpoint.url,
    });
    throw error;
  }
}

function makeSessionUpstreamClient(config, endpoint, session, downstreamWs, generation) {
  let client;
  client = new JsonRpcWebSocketClient(endpoint.url, {
    bearerToken: endpoint.bearerToken || null,
    logger: relayLogger(config),
    onNotification: (message) => {
      if (isSessionActive(session, downstreamWs, generation)) {
        sendJson(downstreamWs, message);
      }
    },
    onRequest: (message) => {
      if (isSessionActive(session, downstreamWs, generation)) {
        session.pendingServerRequests.set(String(message.id), {
          generation,
          threadId: message?.params?.threadId || session.resumeParams?.threadId || null,
          method: message.method,
        });
        sendJson(downstreamWs, message);
      }
    },
    onClose: () => {
      handleSessionUpstreamClose(config, session, downstreamWs, client);
    },
  });
  return client;
}

function handleSessionUpstreamClose(config, session, downstreamWs, closedClient) {
  if (session.closing || session.upstream !== closedClient) {
    return;
  }
  session.upstream = null;
  session.pendingServerRequests?.clear();
  if (!isWebSocketOpen(downstreamWs)) {
    return;
  }
  if (!session.endpoint || !session.resumeParams?.threadId) {
    config.statusTracker?.recordUpstreamError(new Error("upstream closed"), {
      subsystem: "live-upstream",
    });
    downstreamWs.close(1011, "upstream closed");
    return;
  }
  if (session.retryTask) {
    return;
  }
  session.retryTask = recoverSessionUpstream(config, session, downstreamWs, session.generation);
}

async function recoverSessionUpstream(config, session, downstreamWs, generation) {
  const endpoint = session.endpoint;
  const resumeParams = session.resumeParams;
  let lastError = null;
  config.statusTracker?.recordReconnect({
    active: true,
    attempts: 0,
  });

  for (let attempt = 1; attempt <= UPSTREAM_RECONNECT_ATTEMPTS; attempt += 1) {
    if (session.closing || session.generation !== generation || !isWebSocketOpen(downstreamWs)) {
      session.retryTask = null;
      config.statusTracker?.recordReconnect({
        active: false,
        attempts: attempt - 1,
      });
      return;
    }

    const client = makeSessionUpstreamClient(config, endpoint, session, downstreamWs, generation);
    try {
      await initializeClient(client);
      const result = await client.request("thread/resume", resumeParams);
      assertResumeResultMatchesRequestedThread(result, resumeParams.threadId);
      if (!isSessionActive(session, downstreamWs, generation)) {
        client.close();
        session.retryTask = null;
        return;
      }
      session.upstream = client;
      session.retryTask = null;
      config.statusTracker?.recordReconnect({
        active: false,
        attempts: attempt,
      });
      relayLogger(config).info("upstream.recovery_succeeded", {
        threadId: resumeParams.threadId,
        endpointUrl: endpoint.url,
        attempt,
      });
      return;
    } catch (error) {
      lastError = error;
      config.statusTracker?.recordUpstreamError(error, {
        subsystem: "live-upstream",
        threadId: resumeParams.threadId,
        endpointUrl: endpoint.url,
        attempt,
      });
      client.close();
      const delayMs = upstreamReconnectDelayMs(attempt);
      config.statusTracker?.recordReconnect({
        active: true,
        attempts: attempt,
        nextRetryAt: new Date(Date.now() + delayMs).toISOString(),
      });
      await sleep(delayMs);
    }
  }

  session.retryTask = null;
  config.statusTracker?.recordReconnect({
    active: false,
    attempts: UPSTREAM_RECONNECT_ATTEMPTS,
  });
  relayLogger(config).error("upstream.recovery_failed", {
    threadId: resumeParams.threadId,
    endpointUrl: endpoint.url,
    error: lastError,
  });
  if (!session.closing && session.generation === generation && isWebSocketOpen(downstreamWs)) {
    downstreamWs.close(1011, "upstream recovery failed");
  }
}

async function forwardToActiveUpstream(config, session, method, params = {}) {
  assertFocusedRequestTargetsBoundThread(session, method, params);
  relayLogger(config).info("focused_request.route_verified", {
    subsystem: "live-upstream",
    method,
    endpointUrl: session.endpoint?.url || null,
    threadIDHash: shortHash(params.threadId),
    activeThreadIDHash: shortHash(session.resumeParams?.threadId),
    generation: session.generation,
  });
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
        relayInstanceID: config.hostId,
      };
    case "thread/list":
      return aggregateThreadList(config, params || {});
    case "thread/search":
      return aggregateThreadSearch(config, params || {});
    case "thread/goal/get":
      return aggregateThreadGoalGet(config, params || {});
    case DOCK_SUBSCRIBE_METHOD:
      return handleDockSubscribe({ config, session, downstreamWs, sendJson });
    case DOCK_RESYNC_METHOD:
      return dockSessionAggregatorForConfig(config).resync();
    case "relay/state/snapshot":
      return buildRelayStateSnapshot(config, params || {});
    case "thread/loaded/list":
      return aggregateLoadedList(config, params || {});
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
    case "audio/transcription/start":
      return session.realtimeTranscription.start(params || {});
    case "audio/transcription/append":
      return session.realtimeTranscription.append(params || {});
    case "audio/transcription/commit":
      return session.realtimeTranscription.commit(params || {});
    case "audio/transcription/cancel":
      return session.realtimeTranscription.cancel(params || {});
    case "turn/start":
    case "turn/steer":
    case "turn/interrupt":
      return forwardToActiveUpstream(config, session, method, params || {});
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

function isPhoneRequestAuthorized(request, config) {
  if (config.phoneAuth === "none") {
    return true;
  }
  return assertAuthorized(request, config.relayBearerToken);
}

function isLoopbackRemoteAddress(value) {
  return value === "127.0.0.1"
    || value === "::1"
    || value === "::ffff:127.0.0.1";
}

function writeLoopbackOnlyResponse(request, response) {
  if (isLoopbackRemoteAddress(request.socket?.remoteAddress)) {
    return false;
  }
  response.writeHead(403, { "content-type": "application/json" });
  response.end(JSON.stringify({
    ok: false,
    service: "codex-dock-relay",
    error: "loopback only",
  }));
  return true;
}

function sessionDebugSnapshot(sessions) {
  return [...sessions].map((session, index) => ({
    sessionOrdinal: index + 1,
    closing: session.closing,
    generation: session.generation,
    upstreamOpen: Boolean(session.upstream?.isOpen()),
    retryActive: Boolean(session.retryTask),
    endpointUrl: session.endpoint?.url || null,
    threadIDHash: shortHash(session.resumeParams?.threadId),
    pendingServerRequests: session.pendingServerRequests?.size || 0,
  }));
}

function liveRowsDebugSnapshot(liveStatus) {
  return (liveStatus?.rows || []).map((row) => ({
    threadIDHash: shortHash(row?.id),
    endpointUrl: row?.dockRelaySource?.url || null,
    statusType: row?.status?.type || null,
  }));
}

function runtimeSnapshot(config, sessions, downstreamSockets) {
  const liveStatus = config.liveStatusCache?.snapshot?.() || null;
  return {
    downstreamActive: downstreamSockets.size,
    upstreamActive: [...sessions].filter((session) => session.upstream?.isOpen()).length,
    upstreamPools: config.upstreamPool?.stats?.() || [],
    liveStatus,
    sessions: sessionDebugSnapshot(sessions),
    liveRows: liveRowsDebugSnapshot(liveStatus),
  };
}

function startServer(config) {
  config.logger = relayLogger(config);
  const logger = config.logger;
  config.version = config.version || RELAY_VERSION;
  config.hostId = config.hostId || process.env.CODEX_DOCK_REAL_HOST_ID || os.hostname();
  config.hostName = config.hostName || process.env.CODEX_DOCK_REAL_HOST_NAME || config.hostId;
  config.openAIRealtimeTranscriptionModel = config.openAIRealtimeTranscriptionModel
    || DEFAULT_REALTIME_TRANSCRIPTION_MODEL;
  config.openAIRealtimeTranscriptionEndpoint = config.openAIRealtimeTranscriptionEndpoint
    || DEFAULT_REALTIME_TRANSCRIPTION_ENDPOINT;
  config.realtimeTranscriptionLanguage = config.realtimeTranscriptionLanguage
    || DEFAULT_REALTIME_TRANSCRIPTION_LANGUAGE;
  config.realtimeTranscriptionDelay = config.realtimeTranscriptionDelay
    || DEFAULT_REALTIME_TRANSCRIPTION_DELAY;
  config.statusTracker = config.statusTracker || createRelayStatusTracker();
  config.upstreamPool = config.upstreamPool || new UpstreamConnectionPool({
    logger,
    maxOpenByLabel: UPSTREAM_POOL_LIMITS,
  });
  config.liveStatusCache = liveStatusCacheForConfig(config);
  config.sessionRouter = sessionRouterForConfig(config);
  config.liveStatusCache.start();
  config.phoneAuth = parsePhoneAuthMode(config.phoneAuth || DEFAULT_PHONE_AUTH);
  if (config.phoneAuth === "bearer" && !config.relayBearerToken) {
    throw new Error("relayBearerToken is required when phoneAuth is bearer");
  }
  logger.info("relay.starting", {
    subsystem: "relay",
    hostId: config.hostId,
    listenHost: config.listenHost,
    port: config.port,
    historyUrl: config.historyUrl,
    phoneAuth: config.phoneAuth,
    advertiseBonjour: config.advertiseBonjour !== false,
  });

  const sessions = new Set();
  const downstreamSockets = new Set();

  async function writeStatusResponse(response) {
    await checkRawAppServerHealth(config, config.statusTracker);
    response.writeHead(200, { "content-type": "application/json" });
    response.end(JSON.stringify(config.statusTracker.snapshot(
      config,
      runtimeSnapshot(config, sessions, downstreamSockets),
    )));
  }

  function writeMetricsResponse(request, response) {
    if (writeLoopbackOnlyResponse(request, response)) {
      return;
    }
    response.writeHead(200, { "content-type": "application/json" });
    response.end(JSON.stringify(config.statusTracker.metricsSnapshot(
      config,
      runtimeSnapshot(config, sessions, downstreamSockets),
    )));
  }

  function writeDebugSessionsResponse(request, response) {
    if (writeLoopbackOnlyResponse(request, response)) {
      return;
    }
    response.writeHead(200, { "content-type": "application/json" });
    response.end(JSON.stringify(config.statusTracker.debugSessionsSnapshot(
      config,
      runtimeSnapshot(config, sessions, downstreamSockets),
    )));
  }

  const server = http.createServer((request, response) => {
    if (request.url === "/readyz") {
      response.writeHead(200, { "content-type": "application/json" });
      response.end(JSON.stringify({
        ok: true,
        service: "codex-dock-relay",
        auth: config.phoneAuth,
      }));
      return;
    }
    if (request.url === "/healthz") {
      response.writeHead(200, { "content-type": "application/json" });
      response.end(JSON.stringify({
        ok: true,
        service: "codex-dock-relay",
        auth: config.phoneAuth,
        staticConfig: {
          ok: true,
          historyConfigured: Boolean(config.historyUrl),
          transcriptionConfigured: Boolean(config.openAIRealtimeTranscriptionModel),
        },
      }));
      return;
    }
    if (request.url === "/statusz") {
      writeStatusResponse(response).catch((error) => {
        logger.error("statusz.failed", { error });
        response.writeHead(500, { "content-type": "application/json" });
        response.end(JSON.stringify({
          ok: false,
          service: "codex-dock-relay",
          error: "status unavailable",
        }));
      });
      return;
    }
    if (request.url === "/metricsz") {
      writeMetricsResponse(request, response);
      return;
    }
    if (request.url === "/debugz/sessions") {
      writeDebugSessionsResponse(request, response);
      return;
    }
    response.writeHead(404, { "content-type": "text/plain" });
    response.end("not found\n");
  });
  const wss = new WebSocketServer({
    noServer: true,
    maxPayload: JSON_RPC_MAX_MESSAGE_BYTES,
  });
  let advertisement = null;

  server.on("upgrade", (request, socket, head) => {
    if (!isPhoneRequestAuthorized(request, config)) {
      logger.warn("downstream.unauthorized", {
        remoteAddress: socket.remoteAddress,
        phoneAuth: config.phoneAuth,
      });
      socket.write("HTTP/1.1 401 Unauthorized\r\nConnection: close\r\n\r\n");
      socket.destroy();
      return;
    }
    wss.handleUpgrade(request, socket, head, (ws) => {
      wss.emit("connection", ws, request);
    });
  });

  wss.on("connection", (ws, request) => {
    downstreamSockets.add(ws);
    logger.info("downstream.connected", {
      remoteAddress: request?.socket?.remoteAddress,
      activeConnections: downstreamSockets.size,
    });
    const session = {
      upstream: null,
      resumeParams: null,
      endpoint: null,
      retryTask: null,
      closing: false,
      generation: 0,
      pendingServerRequests: new Map(),
      realtimeTranscription: null,
      dockUnsubscribe: null,
    };
    sessions.add(session);
    session.realtimeTranscription = new RealtimeTranscriptionManager(config, {
      sendNotification: (method, params) => {
        sendJson(ws, { jsonrpc: "2.0", method, params });
      },
      logger,
    });

    ws.on("close", () => {
      downstreamSockets.delete(ws);
      sessions.delete(session);
      session.closing = true;
      session.dockUnsubscribe?.();
      session.dockUnsubscribe = null;
      session.realtimeTranscription?.closeAll("downstream_closed");
      session.upstream?.close();
      session.upstream = null;
      logger.info("downstream.closed", {
        activeConnections: downstreamSockets.size,
      });
    });

    ws.on("message", async (data) => {
      const requestStartedAt = Date.now();
      let message;
      try {
        message = JSON.parse(data.toString());
      } catch {
        const parseError = Object.assign(new Error("parse error"), { code: -32700 });
        config.statusTracker?.recordClientFacingError(parseError, {
          subsystem: "downstream",
          method: "parse",
          code: -32700,
          retryable: false,
        });
        logger.warn("downstream.parse_error", {
          subsystem: "downstream",
          hostId: config.hostId,
          bytes: data?.byteLength,
        });
        sendJson(ws, jsonRpcError(null, -32700, "parse error"));
        return;
      }

      if (!message.method && message.id !== undefined) {
        const pendingRequest = session.pendingServerRequests.get(String(message.id));
        if (!pendingRequest || pendingRequest.generation !== session.generation) {
          logger.warn("downstream.raw_response_rejected", {
            id: String(message.id),
            reason: "unknown_or_stale_server_request",
          });
          sendJson(ws, jsonRpcError(message.id, -32000, "no matching active upstream request"));
          return;
        }
        session.pendingServerRequests.delete(String(message.id));
        if (!session.upstream?.sendRaw(message)) {
          logger.warn("downstream.raw_response_rejected", {
            id: String(message.id),
            reason: "no_active_upstream_session",
          });
          sendJson(ws, jsonRpcError(message.id, -32000, "no active upstream session"));
        } else {
          logger.debug("downstream.raw_response_forwarded", {
            id: String(message.id),
          });
        }
        return;
      }

      if (message.id === undefined) {
        logger.debug("downstream.notification_ignored", {
          method: message.method || "missing_method",
        });
        return;
      }

      try {
        const result = await handleRequest(config, message.method, message.params, session, ws);
        config.statusTracker?.recordRequest?.({
          method: message.method,
          ok: true,
          durationMs: Date.now() - requestStartedAt,
        });
        sendJson(ws, jsonRpcResult(message.id, result));
        logger.info("downstream.request_succeeded", {
          subsystem: "downstream",
          hostId: config.hostId,
          method: message.method,
          id: String(message.id),
          durationMs: Date.now() - requestStartedAt,
        });
      } catch (error) {
        const errorData = classifyRelayRequestError(message.method, error);
        const errorCode = jsonRpcErrorCode(error);
        if (String(message.method || "").startsWith("audio/transcription/")) {
          config.statusTracker?.recordTranscriptionError(error, {
            subsystem: "transcription",
            method: message.method,
            code: errorCode,
          });
        }
        config.statusTracker?.recordClientFacingError(error, {
          subsystem: errorData?.subsystem || "relay",
          method: message.method,
          code: errorCode,
          retryable: errorData?.retryable,
        });
        config.statusTracker?.recordRequest?.({
          method: message.method,
          ok: false,
          code: errorCode,
          durationMs: Date.now() - requestStartedAt,
        });
        logger.warn("downstream.request_failed", {
          subsystem: errorData?.subsystem || "relay",
          hostId: config.hostId,
          method: message.method,
          id: String(message.id),
          code: errorCode,
          errorData,
          durationMs: Date.now() - requestStartedAt,
          error,
        });
        sendJson(
          ws,
          jsonRpcError(
            message.id,
            errorCode,
            error.message || "relay error",
            errorData,
          ),
        );
      }
    });
  });

  const listening = new Promise((resolve) => {
    server.listen(config.port, config.listenHost, () => {
      const address = server.address();
      if (address && typeof address === "object") {
        config.port = address.port;
      }
      advertisement = startBonjourAdvertisement(config);
      resolve(address);
      logger.info("relay.listening", {
        subsystem: "relay",
        hostId: config.hostId,
        endpointUrl: `ws://${config.listenHost}:${config.port}`,
        historyUrl: config.historyUrl,
        phoneAuth: config.phoneAuth,
      });
    });
  });

  return {
    server,
    wss,
    get advertisement() {
      return advertisement;
    },
    listening,
    close: () => new Promise((resolve, reject) => {
      logger.info("relay.closing", {
        activeConnections: downstreamSockets.size,
      });
      advertisement?.kill();
      config.dockSessionAggregator?.stop?.();
      config.liveStatusCache?.stop?.();
      for (const ws of downstreamSockets) {
        ws.close(1001, "relay shutting down");
      }
      const forceTerminate = setTimeout(() => {
        for (const ws of downstreamSockets) {
          ws.terminate();
        }
      }, RELAY_SHUTDOWN_SOCKET_TIMEOUT_MS);
      forceTerminate.unref?.();
      wss.close(() => {
        clearTimeout(forceTerminate);
        server.close(async (error) => {
          if (error) {
            logger.error("relay.close_failed", { error });
            reject(error);
          } else {
            try {
              await config.upstreamPool?.closeAll?.({ reason: "relay_close" });
              logger.info("relay.closed");
              resolve();
            } catch (closeError) {
              logger.error("relay.close_failed", { error: closeError });
              reject(closeError);
            }
          }
        });
      });
    }),
  };
}

function installShutdownHandlers(serverHandle) {
  let closing = false;
  const closeAndExit = () => {
    if (closing) {
      return;
    }
    closing = true;
    serverHandle.logger?.info("relay.shutdown_signal");
    const forceExit = setTimeout(() => process.exit(0), RELAY_SHUTDOWN_PROCESS_TIMEOUT_MS);
    forceExit.unref();
    serverHandle.close()
      .then(() => process.exit(0))
      .catch(() => process.exit(1));
  };

  process.once("SIGTERM", closeAndExit);
  process.once("SIGINT", closeAndExit);
  process.once("exit", () => {
    serverHandle.advertisement?.kill();
  });
}

function main() {
  installRelayFatalHandlers(defaultRelayLogger);
  const args = parseArgs(process.argv.slice(2));
  loadDotEnvFile(args["env-file"] || process.env.CODEX_DOCK_ENV_FILE || ".env");
  const relayTokenFile = args["auth-token-file"] || process.env.CODEX_DOCK_RELAY_TOKEN_FILE;
  const phoneAuth = parsePhoneAuthMode(
    args["phone-auth"] || process.env.CODEX_DOCK_PHONE_AUTH || (relayTokenFile ? "bearer" : DEFAULT_PHONE_AUTH),
  );
  const historyTokenFile = args["history-auth-token-file"] || process.env.CODEX_DOCK_HISTORY_TOKEN_FILE || relayTokenFile;
  if (phoneAuth === "bearer" && !relayTokenFile) {
    throw new Error("--auth-token-file is required when --phone-auth bearer");
  }
  if (!historyTokenFile) {
    throw new Error("--history-auth-token-file is required");
  }

  const serverHandle = startServer({
    listenHost: args["listen-host"] || process.env.CODEX_DOCK_RELAY_LISTEN_HOST || DEFAULT_RELAY_LISTEN_HOST,
    port: parseLimit(args.port || process.env.CODEX_DOCK_RELAY_PORT, DOCK_RELAY_PORT),
    phoneAuth,
    relayBearerToken: relayTokenFile ? readToken(relayTokenFile) : null,
    historyBearerToken: readToken(historyTokenFile),
    historyUrl: args["history-url"] || process.env.CODEX_DOCK_HISTORY_APP_SERVER_WS || DEFAULT_HISTORY_APP_SERVER_WS,
    hostId: args["host-id"] || process.env.CODEX_DOCK_REAL_HOST_ID || os.hostname(),
    hostName: args["host-name"] || process.env.CODEX_DOCK_REAL_HOST_NAME || args["bonjour-name"],
    bonjourName: args["bonjour-name"] || process.env.CODEX_DOCK_BONJOUR_NAME || `Codex Dock ${os.hostname()}`,
    advertiseBonjour: (args["advertise-bonjour"] || process.env.CODEX_DOCK_ADVERTISE_BONJOUR || "1") !== "0",
    openAIAPIKey: process.env.OPENAI_API_KEY,
    openAIRealtimeTranscriptionModel: process.env.CODEX_DOCK_OPENAI_REALTIME_TRANSCRIPTION_MODEL
      || DEFAULT_REALTIME_TRANSCRIPTION_MODEL,
    openAIRealtimeTranscriptionEndpoint: process.env.CODEX_DOCK_OPENAI_REALTIME_TRANSCRIPTION_ENDPOINT
      || DEFAULT_REALTIME_TRANSCRIPTION_ENDPOINT,
    realtimeTranscriptionLanguage: process.env.CODEX_DOCK_REALTIME_TRANSCRIPTION_LANGUAGE
      || DEFAULT_REALTIME_TRANSCRIPTION_LANGUAGE,
    realtimeTranscriptionDelay: process.env.CODEX_DOCK_REALTIME_TRANSCRIPTION_DELAY
      || DEFAULT_REALTIME_TRANSCRIPTION_DELAY,
    realtimeTranscriptionAllowedLanguages: process.env.CODEX_DOCK_REALTIME_TRANSCRIPTION_ALLOWED_LANGUAGES,
    realtimeTranscriptionMaxChunkBytes: process.env.CODEX_DOCK_REALTIME_TRANSCRIPTION_MAX_CHUNK_BYTES,
    realtimeTranscriptionMaxPendingBytes: process.env.CODEX_DOCK_REALTIME_TRANSCRIPTION_MAX_PENDING_BYTES,
    realtimeTranscriptionConnectTimeoutMs: process.env.CODEX_DOCK_OPENAI_REALTIME_TRANSCRIPTION_CONNECT_TIMEOUT_MS,
    realtimeTranscriptionMaxDurationMs: process.env.CODEX_DOCK_REALTIME_TRANSCRIPTION_MAX_DURATION_MS,
    openAISafetyIdentifier: process.env.CODEX_DOCK_OPENAI_SAFETY_IDENTIFIER,
    logger: defaultRelayLogger,
  });
  serverHandle.logger = defaultRelayLogger;
  installShutdownHandlers(serverHandle);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  main();
}

export {
  attentionFlagsForServerRequest,
  buildBonjourAdvertisementArgs,
  isLoopbackRemoteAddress,
  isPhoneRequestAuthorized,
  loadDotEnvFile,
  mergeActiveFlags,
  pendingRequestsForActiveThread,
  preferThread,
  RealtimeTranscriptionManager,
  sanitizeRelayFields,
  startServer,
  statusPriority,
  threadMatchesSourceKinds,
};

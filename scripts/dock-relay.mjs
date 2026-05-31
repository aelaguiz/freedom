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
  SELFTEST_ROUTE_TIMEOUT_MS,
  UPSTREAM_POOL_LIMITS,
  UPSTREAM_RECONNECT_ATTEMPTS,
  UPSTREAM_RECONNECT_DELAY_MS,
  UPSTREAM_RECONNECT_JITTER_MS,
} from "./dock-relay-constants.mjs";
import {
  defaultRelayLogger,
  installRelayFatalHandlers,
} from "./dock-relay-logger.mjs";
import {
  FAILURE_CATEGORY,
  ROUTE_NAMES,
  autoProbeSafeRoutes,
} from "./dock-relay-observability-contract.mjs";
import {
  createRelayObservability,
  extractTraceContextFromParams,
} from "./dock-relay-observability.mjs";
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
  ARCHIVE_RESYNC_METHOD,
  ARCHIVE_SUBSCRIBE_METHOD,
  DOCK_RESYNC_METHOD,
  DOCK_SUBSCRIBE_METHOD,
} from "./dock-relay-state-subscriptions.mjs";
import { relayStateEngineForConfig } from "./dock-relay-state-engine.mjs";
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

function parseLiveEndpoints(value) {
  if (!value) {
    return [];
  }
  return String(value)
    .split(",")
    .map((entry) => entry.trim())
    .filter(Boolean)
    .map((entry) => {
      const separator = entry.indexOf("=");
      if (separator > 0) {
        return {
          label: entry.slice(0, separator).trim(),
          url: entry.slice(separator + 1).trim(),
        };
      }
      return {
        label: entry,
        url: entry,
      };
    })
    .filter((endpoint) => endpoint.url);
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
      return relayStateEngineForConfig(config).subscribeDock({ session, downstreamWs, sendJson });
    case DOCK_RESYNC_METHOD:
      return relayStateEngineForConfig(config).resyncDock({ downstreamWs, sendJson });
    case ARCHIVE_SUBSCRIBE_METHOD:
      return relayStateEngineForConfig(config).subscribeArchive({ session, downstreamWs, sendJson });
    case ARCHIVE_RESYNC_METHOD:
      return relayStateEngineForConfig(config).resyncArchive({ downstreamWs, sendJson });
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
    {
      const result = await archiveThread(config, params || {});
      await relayStateEngineForConfig(config).handleArchiveMutation({
        threadId: params?.threadId,
        archived: true,
      });
      return result;
    }
    case "thread/unarchive":
    {
      const result = await unarchiveThread(config, params || {});
      await relayStateEngineForConfig(config).handleArchiveMutation({
        threadId: params?.threadId,
        archived: false,
      });
      return result;
    }
    case "state/query":
      return relayStateEngineForConfig(config).snapshotForView(params?.view || "dock", params || {});
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
    relayState: config.relayStateEngine?.stateSnapshot?.() || null,
    sessions: sessionDebugSnapshot(sessions),
    liveRows: liveRowsDebugSnapshot(liveStatus),
  };
}

function observabilityDirForConfig(config) {
  if (config.observabilityDir === false) {
    return null;
  }
  if (config.observabilityDir) {
    return config.observabilityDir;
  }
  return path.resolve(process.cwd(), ".codex-dock", "observability");
}

function configuredHostIDFromConfig(config) {
  if (config.configuredHostID) {
    return config.configuredHostID;
  }
  if (config.hostEndpoint) {
    return config.hostEndpoint;
  }
  return null;
}

function writeJSONResponse(response, value, statusCode = 200) {
  response.writeHead(statusCode, { "content-type": "application/json" });
  response.end(JSON.stringify(value));
}

function traceOperationIDFromPath(pathname) {
  const prefix = "/tracesz/";
  if (!pathname.startsWith(prefix)) {
    return null;
  }
  const encoded = pathname.slice(prefix.length);
  if (!encoded || encoded === "recent") {
    return null;
  }
  try {
    return decodeURIComponent(encoded);
  } catch {
    return encoded;
  }
}

function semanticRouteOutcome(method, result) {
  return {
    ok: true,
    error: null,
    errorData: null,
    errorCode: null,
    phase: "response",
    outcome: "succeeded",
  };
}

function withSelfTestTimeout(promise, routeName, timeoutMs) {
  let timer = null;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => {
      const error = new Error(`${routeName} self-test timed out after ${timeoutMs}ms`);
      error.code = "SELFTEST_ROUTE_TIMEOUT";
      error.timeoutMs = timeoutMs;
      reject(error);
    }, timeoutMs);
    timer.unref?.();
  });
  return Promise.race([promise, timeout]).finally(() => {
    if (timer) {
      clearTimeout(timer);
    }
  });
}

async function runSelfTest(config) {
  const routeTimeoutMs = config.selftestRouteTimeoutMs || SELFTEST_ROUTE_TIMEOUT_MS;
  const safeRoutes = [];
  for (const route of autoProbeSafeRoutes()) {
    if (route.name === ROUTE_NAMES.dockSubscribe) {
      const state = await withSelfTestTimeout(
        Promise.resolve(config.relayStateEngine?.stateSnapshot?.() || null),
        route.name,
        routeTimeoutMs,
      );
      safeRoutes.push({
        route: route.name,
        probeSafety: route.probeSafety,
        ok: Boolean(state?.ok),
        note: "passive state health read; dock/subscribe not called",
        rows: state?.counts?.active ?? null,
      });
      continue;
    }
    if (route.kind === "http" || route.name === ROUTE_NAMES.statusz) {
      safeRoutes.push({
        route: route.name,
        probeSafety: route.probeSafety,
        ok: true,
        note: "registered auto-probe-safe route; mutating/passive routes skipped",
      });
    }
  }
  return {
    ok: safeRoutes.every((route) => route.ok),
    service: "codex-dock-relay",
    schema: "codexdock.selftest.v1",
    checkedAt: new Date().toISOString(),
    routes: safeRoutes,
  };
}

function startServer(config) {
  config.logger = relayLogger(config);
  const logger = config.logger;
  config.version = config.version || RELAY_VERSION;
  config.hostId = config.hostId || process.env.CODEX_DOCK_REAL_HOST_ID || os.hostname();
  config.hostName = config.hostName || process.env.CODEX_DOCK_REAL_HOST_NAME || config.hostId;
  config.hostEndpoint = config.hostEndpoint || process.env.CODEX_DOCK_HOST_ENDPOINT || null;
  if (!config.relayStateDatabasePath && process.env.NODE_TEST_CONTEXT) {
    config.relayStateDatabasePath = ":memory:";
  }
  config.openAIRealtimeTranscriptionModel = config.openAIRealtimeTranscriptionModel
    || DEFAULT_REALTIME_TRANSCRIPTION_MODEL;
  config.openAIRealtimeTranscriptionEndpoint = config.openAIRealtimeTranscriptionEndpoint
    || DEFAULT_REALTIME_TRANSCRIPTION_ENDPOINT;
  config.realtimeTranscriptionLanguage = config.realtimeTranscriptionLanguage
    || DEFAULT_REALTIME_TRANSCRIPTION_LANGUAGE;
  config.realtimeTranscriptionDelay = config.realtimeTranscriptionDelay
    || DEFAULT_REALTIME_TRANSCRIPTION_DELAY;
  config.statusTracker = config.statusTracker || createRelayStatusTracker();
  config.observability = config.observability || createRelayObservability({
    hostId: config.hostId,
    hostName: config.hostName,
    configuredHostID: configuredHostIDFromConfig(config),
    persistenceDir: observabilityDirForConfig(config),
  });
  config.observability.updateHost?.({
    hostId: config.hostId,
    hostName: config.hostName,
    configuredHostID: configuredHostIDFromConfig(config),
  });
  config.upstreamPool = config.upstreamPool || new UpstreamConnectionPool({
    logger,
    maxOpenByLabel: UPSTREAM_POOL_LIMITS,
  });
  config.liveStatusCache = liveStatusCacheForConfig(config);
  config.sessionRouter = sessionRouterForConfig(config);
  config.liveStatusCache.start();
  config.relayStateEngine = relayStateEngineForConfig(config);
  if (config.relayStateAutoStart === true) {
    config.relayStateEngine.start();
  }
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
    const runtime = runtimeSnapshot(config, sessions, downstreamSockets);
    writeJSONResponse(response, config.statusTracker.snapshot(config, runtime));
  }

  function writeMetricsResponse(request, response) {
    writeJSONResponse(response, config.statusTracker.metricsSnapshot(
      config,
      runtimeSnapshot(config, sessions, downstreamSockets),
    ));
  }

  function writeDebugSessionsResponse(request, response) {
    writeJSONResponse(response, config.statusTracker.debugSessionsSnapshot(
      config,
      runtimeSnapshot(config, sessions, downstreamSockets),
    ));
  }

  function writeRoutesResponse(request, response) {
    writeJSONResponse(response, {
      ok: true,
      service: "codex-dock-relay",
      schema: "codexdock.routesz.v1",
      host: {
        id: config.hostId || null,
        relayInstanceID: config.hostId || null,
        displayName: config.hostName || config.bonjourName || null,
      },
      routes: config.observability.routeHealth(),
    });
  }

  function writeTraceResponse(request, response) {
    const requestURL = new URL(request.url, "http://127.0.0.1");
    if (requestURL.pathname === "/tracesz/recent") {
      writeJSONResponse(response, {
        ok: true,
        service: "codex-dock-relay",
        schema: "codexdock.tracesz.recent.v1",
        traces: config.observability.recentTraces({ limit: 50 }),
      });
      return;
    }
    const operationID = traceOperationIDFromPath(requestURL.pathname);
    const trace = config.observability.trace(operationID);
    if (!trace) {
      writeJSONResponse(response, {
        ok: false,
        service: "codex-dock-relay",
        error: "trace not found",
        operationID,
      }, 404);
      return;
    }
    writeJSONResponse(response, {
      ok: true,
      service: "codex-dock-relay",
      schema: "codexdock.tracesz.operation.v1",
      trace,
    });
  }

  function writeSelfTestResponse(request, response) {
    runSelfTest(config)
      .then((result) => writeJSONResponse(response, result))
      .catch((error) => {
        logger.error("selftestz.failed", { error });
        writeJSONResponse(response, {
          ok: false,
          service: "codex-dock-relay",
          error: "selftest unavailable",
        }, 500);
      });
  }

  async function writeBundleResponse(request, response) {
    await checkRawAppServerHealth(config, config.statusTracker);
    const runtime = runtimeSnapshot(config, sessions, downstreamSockets);
    const status = config.statusTracker.snapshot(config, runtime);
    const metrics = config.statusTracker.metricsSnapshot(config, runtime);
    writeJSONResponse(response, config.observability.bundle({ status, metrics, runtime }));
  }

  const server = http.createServer((request, response) => {
    const requestURL = new URL(request.url, "http://127.0.0.1");
    if (requestURL.pathname === "/readyz") {
      writeJSONResponse(response, {
        ok: true,
        service: "codex-dock-relay",
        auth: config.phoneAuth,
      });
      return;
    }
    if (requestURL.pathname === "/healthz") {
      writeJSONResponse(response, {
        ok: true,
        service: "codex-dock-relay",
        auth: config.phoneAuth,
        routeHealth: false,
        staticConfig: {
          ok: true,
          historyConfigured: Boolean(config.historyUrl),
          transcriptionConfigured: Boolean(config.openAIRealtimeTranscriptionModel),
        },
      });
      return;
    }
    if (requestURL.pathname === "/statusz") {
      writeStatusResponse(response).catch((error) => {
        logger.error("statusz.failed", { error });
        writeJSONResponse(response, {
          ok: false,
          service: "codex-dock-relay",
          error: "status unavailable",
        }, 500);
      });
      return;
    }
    if (requestURL.pathname === "/metricsz") {
      writeMetricsResponse(request, response);
      return;
    }
    if (requestURL.pathname === "/debugz/sessions") {
      writeDebugSessionsResponse(request, response);
      return;
    }
    if (requestURL.pathname === "/routesz") {
      writeRoutesResponse(request, response);
      return;
    }
    if (requestURL.pathname === "/statez") {
      writeJSONResponse(response, config.relayStateEngine.stateSnapshot());
      return;
    }
    if (requestURL.pathname === "/syncz") {
      writeJSONResponse(response, {
        ok: true,
        service: "codex-dock-relay",
        schema: "codexdock.syncz.v1",
        syncScopes: config.relayStateEngine.stateSnapshot().syncScopes,
      });
      return;
    }
    if (requestURL.pathname === "/subscriptionsz") {
      writeJSONResponse(response, {
        ok: true,
        service: "codex-dock-relay",
        schema: "codexdock.subscriptionsz.v1",
        subscribers: config.relayStateEngine.subscriptions.subscribers.size,
      });
      return;
    }
    if (requestURL.pathname === "/dbz") {
      writeJSONResponse(response, {
        ok: true,
        service: "codex-dock-relay",
        schema: "codexdock.dbz.v1",
        db: config.relayStateEngine.stateSnapshot().db,
      });
      return;
    }
    if (requestURL.pathname.startsWith("/explainz/thread/")) {
      const threadID = decodeURIComponent(requestURL.pathname.slice("/explainz/thread/".length));
      writeJSONResponse(response, {
        ok: true,
        service: "codex-dock-relay",
        schema: "codexdock.explainz.thread.v1",
        explanation: config.relayStateEngine.explainThread(threadID),
      });
      return;
    }
    if (requestURL.pathname === "/tracesz/recent" || requestURL.pathname.startsWith("/tracesz/")) {
      writeTraceResponse(request, response);
      return;
    }
    if (requestURL.pathname === "/selftestz") {
      writeSelfTestResponse(request, response);
      return;
    }
    if (requestURL.pathname === "/bundlez") {
      writeBundleResponse(request, response).catch((error) => {
        logger.error("bundlez.failed", { error });
        writeJSONResponse(response, {
          ok: false,
          service: "codex-dock-relay",
          error: "bundle unavailable",
        }, 500);
      });
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
      archiveUnsubscribe: null,
    };
    sessions.add(session);
    session.realtimeTranscription = new RealtimeTranscriptionManager(config, {
      sendNotification: (method, params) => {
        config.observability?.recordNotification?.(method);
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
      session.archiveUnsubscribe?.();
      session.archiveUnsubscribe = null;
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

      let operation = null;
      let params = message.params;
      try {
        const extracted = extractTraceContextFromParams(message.params);
        params = extracted.params;
        operation = config.observability?.beginOperation?.({
          route: message.method,
          method: message.method,
          traceContext: extracted.traceContext,
        });
        const result = await handleRequest(config, message.method, params, session, ws);
        config.statusTracker?.recordRequest?.({
          method: message.method,
          ok: true,
          durationMs: Date.now() - requestStartedAt,
        });
        const routeOutcome = semanticRouteOutcome(message.method, result);
        config.observability?.finishOperation?.(operation, {
          ok: routeOutcome.ok,
          result,
          error: routeOutcome.error,
          errorCode: routeOutcome.errorCode,
          errorData: routeOutcome.errorData,
          phase: routeOutcome.phase,
          outcome: routeOutcome.outcome,
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
        config.observability?.finishOperation?.(operation, {
          ok: false,
          error,
          errorCode,
          errorData,
          phase: errorData?.subsystem || "handler",
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
              await config.relayStateEngine?.close?.();
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
    liveEndpoints: parseLiveEndpoints(args["live-endpoints"] || process.env.CODEX_DOCK_LIVE_APP_SERVER_WS || process.env.CODEX_DOCK_LIVE_ENDPOINTS),
    hostId: args["host-id"] || process.env.CODEX_DOCK_REAL_HOST_ID || os.hostname(),
    hostName: args["host-name"] || process.env.CODEX_DOCK_REAL_HOST_NAME || args["bonjour-name"],
    hostEndpoint: args["host-endpoint"] || process.env.CODEX_DOCK_HOST_ENDPOINT || null,
    relayStateDatabasePath: args["relay-state-db"] || process.env.CODEX_DOCK_RELAY_STATE_DB || null,
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
    relayStateAutoStart: true,
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

#!/usr/bin/env node

import crypto from "node:crypto";
import fs from "node:fs";
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
import { AppServerRegistry } from "./dock-relay-app-server-registry.mjs";
import {
  DEFAULT_PHONE_AUTH,
  DEFAULT_RELAY_LISTEN_HOST,
  DOCK_RELAY_PORT,
  JSON_RPC_MAX_MESSAGE_BYTES,
  RELAY_SHUTDOWN_PROCESS_TIMEOUT_MS,
  RELAY_SHUTDOWN_SOCKET_TIMEOUT_MS,
  RELAY_VERSION,
  THREAD_LIST_MAX_LIMIT,
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
import {
  THREAD_DETAIL_UPDATE_METHOD,
  createThreadDetailLedgerFromThread,
} from "./dock-relay-thread-detail-ledger.mjs";
import {
  loadDotEnvFile,
  parsePhoneAuthMode,
  readToken,
} from "./dock-relay-env.mjs";
import {
  assertHumanThreadID,
  aggregateThreadRead,
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
  setThreadName,
  statusPriority,
  unarchiveThread,
} from "./dock-relay-thread-data.mjs";
import { threadMatchesSourceKinds } from "./dock-relay-source-filter.mjs";
import { UpstreamConnectionPool } from "./dock-relay-upstream-pool.mjs";
import { userMessageCommandEngineForConfig } from "./dock-relay-user-message-command.mjs";

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
    throw relayError("downstream session closed", -32000, {
      subsystem: "downstream",
      reason: "downstream_session_closed",
      cancelled: true,
      retryable: false,
    });
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
  if (session.acceptedHumanThreadId !== boundThreadId) {
    throw relayError(`${method} requires a human-started active thread`, -32602, {
      subsystem: "live-upstream",
      reason: "thread_not_human_verified",
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

async function resumeThread(config, params = {}, session, downstreamWs, options = {}) {
  if (!params.threadId) {
    throw new Error("thread/resume requires threadId");
  }
  const resumeParams = liveResumeParams(params);
  await assertHumanThreadID(config, resumeParams.threadId, {
    allowAppFacingCardRouteFallback: options.detailSubscription === true,
  });

  session.generation += 1;
  const generation = session.generation;
  session.retryTask = null;
  session.pendingServerRequests?.clear();
  session.upstream?.close();
  session.upstream = null;
  session.acceptedHumanThreadId = null;
  session.detailSubscription = options.detailSubscription === true
    ? {
        threadId: resumeParams.threadId,
        generation,
        ledger: null,
        buffering: true,
        pendingMessages: [],
      }
    : null;

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
    session.acceptedHumanThreadId = resumeParams.threadId;
    session.endpoint = endpoint;
    logger.info("thread_resume.succeeded", {
      subsystem: "live-upstream",
      hostId: config.hostId,
      threadId: resumeParams.threadId,
      endpointUrl: endpoint.url,
    });
    return result;
  } catch (error) {
    if (session.detailSubscription?.generation === generation) {
      session.detailSubscription = null;
    }
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

async function readAllThreadDetailTurns(config, threadId, {
  allowHistoryForPrivateOwner = false,
  allowAppFacingCardRouteFallback = false,
} = {}) {
  const turns = [];
  const seenCursors = new Set();
  let cursor = null;

  while (true) {
    const response = await listThreadTurns(config, {
      threadId,
      cursor,
      limit: THREAD_LIST_MAX_LIMIT,
      sortDirection: "desc",
      itemsView: "full",
    }, {
      allowHistoryForPrivateOwner,
      allowAppFacingCardRouteFallback,
    });
    if (Array.isArray(response?.data)) {
      turns.push(...response.data);
    }

    const nextCursor = response?.nextCursor || null;
    if (!nextCursor) {
      break;
    }
    if (seenCursors.has(nextCursor)) {
      throw relayError("thread/detail read saw repeated turns cursor", -32000, {
        subsystem: "thread-detail",
        reason: "repeated_turns_cursor",
      });
    }
    seenCursors.add(nextCursor);
    cursor = nextCursor;
  }

  return turns;
}

async function readThreadDetailLedger(config, params = {}, options = {}) {
  if (!params.threadId) {
    throw new Error("thread/detail requires threadId");
  }
  const thread = await readThreadDetailThread(config, params, options);
  return createThreadDetailLedgerFromThread(thread, {
    sourceHostID: config.hostId,
    threadID: params.threadId,
  });
}

async function readThreadDetailThread(config, params = {}, options = {}) {
  if (!params.threadId) {
    throw new Error("thread/detail requires threadId");
  }
  const readResponse = await aggregateThreadRead(config, {
    threadId: params.threadId,
    includeTurns: false,
  }, {
    allowHistoryForPrivateOwner: Boolean(options.allowHistoryForPrivateOwner),
    allowAppFacingCardRouteFallback: true,
  });
  const turns = await readAllThreadDetailTurns(config, params.threadId, {
    allowHistoryForPrivateOwner: Boolean(options.allowHistoryForPrivateOwner),
    allowAppFacingCardRouteFallback: true,
  });
  return {
    ...(readResponse?.thread || {}),
    id: params.threadId,
    turns,
  };
}

function cloneProjectionEnvelope(envelope) {
  return JSON.parse(JSON.stringify(envelope));
}

function projectionWitnessStore(config) {
  if (!config.projectionWitnessEnabled) {
    return null;
  }
  if (!config.projectionWitnessLog) {
    config.projectionWitnessLog = [];
  }
  return config.projectionWitnessLog;
}

function recordProjectionWitness(config, envelope) {
  const store = projectionWitnessStore(config);
  if (!store || !envelope) {
    return;
  }
  store.push({
    emittedAt: new Date().toISOString(),
    envelope: cloneProjectionEnvelope(envelope),
  });
  const maxEnvelopes = Number(config.projectionWitnessMaxEnvelopes || 1_000);
  while (store.length > maxEnvelopes) {
    store.shift();
  }
}

function recordCanonicalUserMessageRows(config, envelope) {
  const rows = Array.isArray(envelope?.rows) ? envelope.rows : [];
  if (!rows.some((row) => row?.payload?.clientID)) {
    return;
  }
  try {
    userMessageCommandEngineForConfig(config).markCanonicalRows(rows);
  } catch (error) {
    relayLogger(config).warn("user_message_command.canonical_mark_failed", {
      subsystem: "user-message-command",
      error,
    });
  }
}

function projectionWitnessEnvelopeMatches(envelope, params) {
  if (params.sourceHostID && envelope.sourceHostID !== params.sourceHostID) {
    return false;
  }
  if (params.view && envelope.view !== params.view) {
    return false;
  }
  if (params.scope && envelope.scope !== params.scope) {
    return false;
  }
  if (params.threadID && envelope.threadID !== params.threadID) {
    return false;
  }
  if (params.viewParamsKey && envelope.viewParamsKey !== params.viewParamsKey) {
    return false;
  }
  if (params.epoch && envelope.epoch !== params.epoch) {
    return false;
  }
  if (params.fromSeq !== undefined && params.fromSeq !== null && Number(envelope.seq) < Number(params.fromSeq)) {
    return false;
  }
  if (params.throughSeq !== undefined && params.throughSeq !== null && Number(envelope.seq) > Number(params.throughSeq)) {
    return false;
  }
  return true;
}

function projectionIDsFromWitnessEnvelopes(envelopes) {
  const rowsByProjectionID = new Map();
  for (const envelope of envelopes) {
    if (envelope.kind === "delete") {
      for (const projectionID of envelope.projectionIDs || []) {
        rowsByProjectionID.delete(projectionID);
      }
      continue;
    }
    if (envelope.kind === "snapshot" || !envelope.kind) {
      rowsByProjectionID.clear();
    }
    for (const row of envelope.rows || []) {
      if (row?.projectionID) {
        rowsByProjectionID.set(row.projectionID, row);
      }
    }
  }
  return [...rowsByProjectionID.values()]
    .sort((left, right) => String(left.displayOrderKey).localeCompare(String(right.displayOrderKey)))
    .map((row) => row.projectionID);
}

function readProjectionWitness(config, params = {}) {
  if (!config.projectionWitnessEnabled) {
    throw relayError("projection witness is disabled", -32601, {
      subsystem: "projection-witness",
      reason: "disabled",
    });
  }
  const envelopes = (config.projectionWitnessLog || [])
    .map((entry) => entry.envelope)
    .filter((envelope) => projectionWitnessEnvelopeMatches(envelope, params))
    .sort((left, right) => Number(left.seq || 0) - Number(right.seq || 0))
    .map(cloneProjectionEnvelope);
  const lastSeq = envelopes.reduce((max, envelope) => Math.max(max, Number(envelope.seq || 0)), 0);
  return {
    source: "retained-downstream-emitter-log",
    byteEquivalentToDownstream: true,
    sourceHostID: params.sourceHostID || envelopes.at(-1)?.sourceHostID || null,
    view: params.view || envelopes.at(-1)?.view || null,
    scope: params.scope || envelopes.at(-1)?.scope || null,
    threadID: params.threadID || envelopes.at(-1)?.threadID || null,
    viewParamsKey: params.viewParamsKey || envelopes.at(-1)?.viewParamsKey || null,
    epoch: params.epoch || envelopes.at(-1)?.epoch || null,
    lastSeq,
    envelopes,
    projectionIDs: projectionIDsFromWitnessEnvelopes(envelopes),
  };
}

function sendThreadDetailUpdate(config, downstreamWs, update) {
  if (!update) {
    return;
  }
  recordCanonicalUserMessageRows(config, update);
  recordProjectionWitness(config, update);
  sendJson(downstreamWs, {
    jsonrpc: "2.0",
    method: THREAD_DETAIL_UPDATE_METHOD,
    params: update,
  });
}

function threadIDFromRenameNotification(message) {
  return message?.params?.threadId || message?.params?.threadID || null;
}

function threadIDFromStatusNotification(message) {
  return message?.params?.threadId || message?.params?.threadID || null;
}

function threadIDFromGenericNotification(message) {
  return message?.params?.threadId
    || message?.params?.threadID
    || message?.params?.thread?.id
    || null;
}

function ingestRelayStateNotification(config, message, source = {}) {
  const engine = relayStateEngineForConfig(config);
  if (message?.method === "thread/name/updated") {
    try {
      engine
        .handleThreadNameNotification(message)
        .catch((error) => {
          relayLogger(config).warn("state.thread_name_notification_ingest_failed", {
            method: message.method,
            sourceLabel: source?.label || null,
            threadIDHash: shortHash(threadIDFromRenameNotification(message)),
            error,
          });
        });
    } catch (error) {
      relayLogger(config).warn("state.thread_name_notification_ingest_failed", {
        method: message.method,
        sourceLabel: source?.label || null,
        threadIDHash: shortHash(threadIDFromRenameNotification(message)),
        error,
      });
    }
    return true;
  }

  if (message?.method === "thread/status/changed") {
    try {
      engine
        .handleThreadStatusNotification(message)
        .catch((error) => {
          relayLogger(config).warn("state.thread_status_notification_ingest_failed", {
            method: message.method,
            sourceLabel: source?.label || null,
            threadIDHash: shortHash(threadIDFromStatusNotification(message)),
            error,
          });
        });
    } catch (error) {
      relayLogger(config).warn("state.thread_status_notification_ingest_failed", {
        method: message.method,
        sourceLabel: source?.label || null,
        threadIDHash: shortHash(threadIDFromStatusNotification(message)),
        error,
      });
    }
    return true;
  }

  if (message?.method === "thread/started") {
    try {
      engine
        .handleThreadStartedNotification(message)
        .catch((error) => {
          relayLogger(config).warn("state.thread_started_notification_ingest_failed", {
            method: message.method,
            sourceLabel: source?.label || null,
            threadIDHash: shortHash(threadIDFromGenericNotification(message)),
            error,
          });
        });
    } catch (error) {
      relayLogger(config).warn("state.thread_started_notification_ingest_failed", {
        method: message.method,
        sourceLabel: source?.label || null,
        threadIDHash: shortHash(threadIDFromGenericNotification(message)),
        error,
      });
    }
    return true;
  }

  if (message?.method === "thread/archived") {
    try {
      engine
        .handleThreadArchivedNotification(message)
        .catch((error) => {
          relayLogger(config).warn("state.thread_archived_notification_ingest_failed", {
            method: message.method,
            sourceLabel: source?.label || null,
            threadIDHash: shortHash(threadIDFromGenericNotification(message)),
            error,
          });
        });
    } catch (error) {
      relayLogger(config).warn("state.thread_archived_notification_ingest_failed", {
        method: message.method,
        sourceLabel: source?.label || null,
        threadIDHash: shortHash(threadIDFromGenericNotification(message)),
        error,
      });
    }
    return true;
  }

  if (message?.method === "thread/unarchived") {
    try {
      engine
        .handleThreadUnarchivedNotification(message)
        .catch((error) => {
          relayLogger(config).warn("state.thread_unarchived_notification_ingest_failed", {
            method: message.method,
            sourceLabel: source?.label || null,
            threadIDHash: shortHash(threadIDFromGenericNotification(message)),
            error,
          });
        });
    } catch (error) {
      relayLogger(config).warn("state.thread_unarchived_notification_ingest_failed", {
        method: message.method,
        sourceLabel: source?.label || null,
        threadIDHash: shortHash(threadIDFromGenericNotification(message)),
        error,
      });
    }
    return true;
  }

  if (message?.method === "thread/closed") {
    try {
      engine
        .handleThreadClosedNotification(message)
        .catch((error) => {
          relayLogger(config).warn("state.thread_closed_notification_ingest_failed", {
            method: message.method,
            sourceLabel: source?.label || null,
            threadIDHash: shortHash(threadIDFromGenericNotification(message)),
            error,
          });
        });
    } catch (error) {
      relayLogger(config).warn("state.thread_closed_notification_ingest_failed", {
        method: message.method,
        sourceLabel: source?.label || null,
        threadIDHash: shortHash(threadIDFromGenericNotification(message)),
        error,
      });
    }
    return true;
  }

  if (engine.handleThreadDirtyNotification(message)) {
    return true;
  }

  return false;
}

function reconcileThreadNameAfterResponse(config, params = {}) {
  const threadId = params?.threadId || params?.threadID || null;
  try {
    relayStateEngineForConfig(config)
      .handleThreadNameMutation({ threadId, name: params?.name || null })
      .catch((error) => {
        relayLogger(config).warn("state.thread_name_mutation_reconcile_failed", {
          method: "thread/name/set",
          threadIDHash: shortHash(threadId),
          error,
        });
      });
  } catch (error) {
    relayLogger(config).warn("state.thread_name_mutation_reconcile_failed", {
      method: "thread/name/set",
      threadIDHash: shortHash(threadId),
      error,
    });
  }
}

function handleDetailNotification(config, session, downstreamWs, generation, message) {
  const detail = session.detailSubscription;
  if (!detail || detail.generation !== generation) {
    return false;
  }
  if (detail.buffering || !detail.ledger) {
    detail.pendingMessages.push({ type: "notification", message });
    return true;
  }
  sendThreadDetailUpdate(config, downstreamWs, detail.ledger.applyNotification(message));
  return true;
}

function handleDetailRequest(config, session, downstreamWs, generation, message) {
  const detail = session.detailSubscription;
  if (!detail || detail.generation !== generation) {
    return false;
  }
  if (detail.buffering || !detail.ledger) {
    detail.pendingMessages.push({ type: "request", message });
    return true;
  }
  sendThreadDetailUpdate(config, downstreamWs, detail.ledger.applyRequest(message));
  return true;
}

function replayPendingDetailMessages(session) {
  const detail = session.detailSubscription;
  if (!detail?.ledger) {
    return;
  }
  const pending = detail.pendingMessages.splice(0);
  for (const entry of pending) {
    if (entry.type === "notification") {
      detail.ledger.applyNotification(entry.message);
    } else if (entry.type === "request") {
      detail.ledger.applyRequest(entry.message);
    }
  }
}

function isArchivedProjectionThread(config, threadId) {
  const card = relayStateEngineForConfig(config).cardForThread(threadId);
  return card?.archiveState === "archived";
}

function isPrivateOwnerUnattachableError(error) {
  return error?.reason === "private_owner_unattachable"
    || error?.upstreamError?.data?.reason === "private_owner_unattachable"
    || /owned by a private Codex runtime/u.test(error?.message || "");
}

async function readHistoryBackedThreadDetailSnapshot(config, params = {}, source = "thread/detail/subscribe") {
  const ledger = await readThreadDetailLedger(config, params, {
    allowHistoryForPrivateOwner: true,
  });
  const snapshot = ledger.snapshot(source);
  recordCanonicalUserMessageRows(config, snapshot);
  recordProjectionWitness(config, snapshot);
  return snapshot;
}

async function subscribeThreadDetail(config, params = {}, session, downstreamWs) {
  // Archived threads are read-only projection views; upstream thread/resume is
  // only for live command sessions.
  if (isArchivedProjectionThread(config, params.threadId)) {
    const ledger = await readThreadDetailLedger(config, params);
    const snapshot = ledger.snapshot("thread/detail/subscribe");
    recordCanonicalUserMessageRows(config, snapshot);
    recordProjectionWitness(config, snapshot);
    return snapshot;
  }

  try {
    await resumeThread(config, params, session, downstreamWs, { detailSubscription: true });
  } catch (error) {
    if (isPrivateOwnerUnattachableError(error)) {
      return readHistoryBackedThreadDetailSnapshot(config, params, "thread/detail/subscribe");
    }
    throw error;
  }
  const detail = session.detailSubscription;
  try {
    const ledger = await readThreadDetailLedger(config, params);
    detail.ledger = ledger;
    replayPendingDetailMessages(session);
    detail.buffering = false;
    const snapshot = ledger.snapshot("thread/detail/subscribe");
    recordCanonicalUserMessageRows(config, snapshot);
    recordProjectionWitness(config, snapshot);
    return snapshot;
  } catch (error) {
    if (session.detailSubscription === detail) {
      session.detailSubscription = null;
    }
    throw error;
  }
}

async function resyncThreadDetail(config, params = {}, session) {
  const thread = await readThreadDetailThread(config, params, {
    allowHistoryForPrivateOwner: true,
  });
  const detail = session.detailSubscription;
  let ledger;
  if (detail?.threadId === params.threadId && detail.ledger) {
    // Active detail resync must be monotonic. Raw history can lag behind the
    // live session, so merge it into the current ledger instead of replacing
    // visible live rows with an older snapshot.
    ledger = detail.ledger;
    ledger.mergeFromThread(thread, "thread/detail/resync");
    detail.buffering = false;
    detail.pendingMessages = [];
    for (const pending of session.pendingServerRequests?.values?.() || []) {
      if (pending.threadId === params.threadId && pending.message) {
        ledger.applyRequest(pending.message);
      }
    }
  } else {
    ledger = createThreadDetailLedgerFromThread(thread, {
      sourceHostID: config.hostId,
      threadID: params.threadId,
    });
    if (detail?.threadId === params.threadId) {
      detail.ledger = ledger;
      detail.buffering = false;
      detail.pendingMessages = [];
    }
  }
  const snapshot = ledger.snapshot("thread/detail/resync");
  recordCanonicalUserMessageRows(config, snapshot);
  recordProjectionWitness(config, snapshot);
  return snapshot;
}

function makeSessionUpstreamClient(config, endpoint, session, downstreamWs, generation) {
  let client;
  client = new JsonRpcWebSocketClient(endpoint.url, {
    bearerToken: endpoint.bearerToken || null,
    logger: relayLogger(config),
    onNotification: (message) => {
      if (isSessionActive(session, downstreamWs, generation)) {
        ingestRelayStateNotification(config, message, {
          label: endpoint.label || "active-session",
        });
        if (!handleDetailNotification(config, session, downstreamWs, generation, message)) {
          sendJson(downstreamWs, message);
        }
      }
    },
    onRequest: (message) => {
      if (isSessionActive(session, downstreamWs, generation)) {
        session.pendingServerRequests.set(String(message.id), {
          generation,
          threadId: message?.params?.threadId || session.resumeParams?.threadId || null,
          method: message.method,
          message,
        });
        if (!handleDetailRequest(config, session, downstreamWs, generation, message)) {
          sendJson(downstreamWs, message);
        }
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
      // A recovered upstream may have missed live detail events while the
      // socket was down, so force the phone through reconnect + rehydrate.
      client.close();
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
      downstreamWs.close(1012, "upstream recovered; rehydrate");
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
        codexHome: config.codexHome || process.env.CODEX_HOME || path.join(os.homedir(), ".codex"),
        platformFamily: "unix",
        platformOs: platformOs(),
        relayInstanceID: config.hostId,
      };
    case DOCK_SUBSCRIBE_METHOD:
      return relayStateEngineForConfig(config).subscribeDock({ session, downstreamWs, sendJson });
    case DOCK_RESYNC_METHOD:
      return relayStateEngineForConfig(config).resyncDock({ downstreamWs, sendJson });
    case ARCHIVE_SUBSCRIBE_METHOD:
      return relayStateEngineForConfig(config).subscribeArchive({ session, downstreamWs, sendJson });
    case ARCHIVE_RESYNC_METHOD:
      return relayStateEngineForConfig(config).resyncArchive({ downstreamWs, sendJson });
    case "thread/detail/subscribe":
      return subscribeThreadDetail(config, params || {}, session, downstreamWs);
    case "thread/detail/resync":
      return resyncThreadDetail(config, params || {}, session);
    case "projection/witness/read":
      return readProjectionWitness(config, params || {});
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
    case "thread/name/set":
    {
      const result = await setThreadName(config, params || {});
      reconcileThreadNameAfterResponse(config, params || {});
      return result;
    }
    case "thread/message/send":
      return userMessageCommandEngineForConfig(config).send(params || {}, { session });
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
      if (!params?.clientUserMessageId) {
        throw relayError(`${method} through the relay requires clientUserMessageId; use thread/message/send`, -32602, {
          subsystem: "user-message-command",
          reason: "missing_client_user_message_id",
          retryable: false,
        });
      }
      return userMessageCommandEngineForConfig(config).send(params || {}, {
        session,
        preferredMethod: method,
        expectedTurnId: params?.expectedTurnId || null,
      });
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
    acceptedHumanThreadIDHash: shortHash(session.acceptedHumanThreadId),
    pendingServerRequests: session.pendingServerRequests?.size || 0,
    detailSubscribed: Boolean(session.detailSubscription?.ledger),
  }));
}

function runtimeSnapshot(config, sessions, downstreamSockets) {
  const liveStatus = config.liveStatusCache?.snapshot?.() || null;
  return {
    downstreamActive: downstreamSockets.size,
    upstreamActive: [...sessions].filter((session) => session.upstream?.isOpen()).length,
    upstreamPools: config.upstreamPool?.stats?.() || [],
    liveStatus: liveStatus?.liveOverlay || null,
    relayStateHealth: config.relayStateEngine?.stateHealth?.() || null,
    sessions: sessionDebugSnapshot(sessions),
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

function validSourceHostID(value) {
  return /^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/.test(String(value || ""));
}

function sourceHostIDPath(config) {
  if (config.sourceHostIDPath) {
    return config.sourceHostIDPath;
  }
  return path.join(process.cwd(), ".codex-dock", "source-host-id");
}

function stableGeneratedSourceHostID(config) {
  const codexHome = config.codexHome || process.env.CODEX_HOME || path.join(os.homedir(), ".codex");
  const input = [
    os.platform(),
    os.userInfo?.().username || "",
    codexHome,
  ].join("|");
  return `local-${crypto.createHash("sha256").update(input).digest("hex").slice(0, 12)}`;
}

function resolveSourceHostID(config) {
  const explicit = String(config.hostId || process.env.CODEX_DOCK_REAL_HOST_ID || "").trim();
  if (explicit) {
    if (!validSourceHostID(explicit)) {
      throw new Error(`invalid CODEX_DOCK_REAL_HOST_ID/sourceHostID: ${explicit}`);
    }
    return explicit;
  }

  const idPath = sourceHostIDPath(config);
  try {
    const persisted = fs.readFileSync(idPath, "utf8").trim();
    if (persisted) {
      if (!validSourceHostID(persisted)) {
        throw new Error(`invalid persisted sourceHostID: ${persisted}`);
      }
      return persisted;
    }
  } catch (error) {
    if (error?.code !== "ENOENT") {
      throw error;
    }
  }

  const generated = stableGeneratedSourceHostID(config);
  fs.mkdirSync(path.dirname(idPath), { recursive: true, mode: 0o700 });
  fs.writeFileSync(idPath, `${generated}\n`, { mode: 0o600 });
  return generated;
}

function appServerRegistryForConfig(config) {
  if (config.appServerRegistry) {
    return config.appServerRegistry;
  }
  const fixtureHistoryEndpoints = [...(config.registryFixtureHistoryEndpoints || [])];
  const fixtureLiveEndpoints = [...(config.registryFixtureLiveEndpoints || [])];
  const hasFixtureConfig = fixtureHistoryEndpoints.length > 0 || fixtureLiveEndpoints.length > 0;

  return new AppServerRegistry({
    codexHome: config.codexHome || process.env.CODEX_HOME || path.join(os.homedir(), ".codex"),
    includeDaemonHistory: config.registryIncludeDaemonHistory ?? true,
    fixtureHistoryEndpoints,
    fixtureLiveEndpoints,
    processListProvider: config.registryProcessListProvider ?? (hasFixtureConfig ? async () => [] : undefined),
    discoveryProvider: config.registryDiscoveryProvider || null,
    logger: relayLogger(config),
  });
}

function startServer(config) {
  config.logger = relayLogger(config);
  const logger = config.logger;
  config.version = config.version || RELAY_VERSION;
  config.hostId = resolveSourceHostID(config);
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
  const configuredUpstreamNotificationHandler = config.upstreamNotificationHandler || null;
  config.upstreamNotificationHandler = (message, source = {}) => {
    ingestRelayStateNotification(config, message, source);
    configuredUpstreamNotificationHandler?.(message, source);
  };
  config.upstreamPool = config.upstreamPool || new UpstreamConnectionPool({
    logger,
    maxOpenByLabel: UPSTREAM_POOL_LIMITS,
  });
  config.appServerRegistry = appServerRegistryForConfig(config);
  const appServerRegistryReady = config.appServerRegistry.start().catch((error) => {
    logger.warn("app_server_registry.start_failed", { error });
    return null;
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
    phoneAuth: config.phoneAuth,
    advertiseBonjour: config.advertiseBonjour !== false,
  });

  const sessions = new Set();
  const downstreamSockets = new Set();

  async function writeStatusResponse(response) {
    await config.appServerRegistry.ensureReady("statusz");
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
          appServerRegistryConfigured: Boolean(config.appServerRegistry),
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
    if (requestURL.pathname === "/routesz") {
      writeRoutesResponse(request, response);
      return;
    }
    if (requestURL.pathname === "/syncz") {
      writeJSONResponse(response, {
        ok: true,
        service: "codex-dock-relay",
        schema: "codexdock.syncz.v1",
        state: "available",
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
      acceptedHumanThreadId: null,
      detailSubscription: null,
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
      session.detailSubscription = null;
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
        const clientErrorData = errorCode === -32043 && error?.data ? error.data : errorData;
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
            clientErrorData,
          ),
        );
      }
    });
  });

  const listening = new Promise((resolve) => {
    server.listen(config.port, config.listenHost, async () => {
      await appServerRegistryReady;
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
              await config.relayStateEngine?.close?.();
              config.appServerRegistry?.stop?.();
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
  if (phoneAuth === "bearer" && !relayTokenFile) {
    throw new Error("--auth-token-file is required when --phone-auth bearer");
  }

  const serverHandle = startServer({
    listenHost: args["listen-host"] || process.env.CODEX_DOCK_RELAY_LISTEN_HOST || DEFAULT_RELAY_LISTEN_HOST,
    port: parseLimit(args.port || process.env.CODEX_DOCK_RELAY_PORT, DOCK_RELAY_PORT),
    phoneAuth,
    relayBearerToken: relayTokenFile ? readToken(relayTokenFile) : null,
    hostId: args["host-id"] || process.env.CODEX_DOCK_REAL_HOST_ID || null,
    hostName: args["host-name"] || process.env.CODEX_DOCK_REAL_HOST_NAME || args["bonjour-name"],
    hostEndpoint: args["host-endpoint"] || process.env.CODEX_DOCK_HOST_ENDPOINT || null,
    codexHome: args["codex-home"] || process.env.CODEX_HOME || path.join(os.homedir(), ".codex"),
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
  resolveSourceHostID,
  sanitizeRelayFields,
  startServer,
  statusPriority,
  threadMatchesSourceKinds,
};

import crypto from "node:crypto";

import { JsonRpcWebSocketClient } from "./dock-relay-json-rpc-client.mjs";
import { outboundUserMessageStoreForConfig } from "./dock-relay-outbound-user-message-store.mjs";
import { relayStateStoreForConfig } from "./dock-relay-state-store.mjs";
import {
  assertHumanThreadID,
  endpointForThread,
  initializeClient,
} from "./dock-relay-thread-data.mjs";

function relayError(message, code = -32000, data = {}) {
  return Object.assign(new Error(message), { code, data });
}

function stableInputJSON(input) {
  return JSON.stringify(sortJSON(input || []));
}

function inputHash(inputJSON) {
  return crypto.createHash("sha256").update(inputJSON).digest("hex");
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

function nonEmptyString(value) {
  const text = String(value ?? "").trim();
  return text.length > 0 ? text : null;
}

function validateInput(input) {
  if (!Array.isArray(input) || input.length === 0) {
    throw relayError("thread/message/send requires input", -32602, {
      subsystem: "user-message-command",
      reason: "missing_input",
      retryable: false,
    });
  }
  return input;
}

function responseFromRow(row) {
  return {
    clientUserMessageId: row.clientUserMessageID,
    state: row.state,
    turnId: row.codexTurnID || null,
    itemId: row.codexItemID || null,
    error: row.lastErrorMessage || null,
  };
}

function activeSessionMatchesThread(session, threadId) {
  return Boolean(
    session?.upstream?.isOpen?.()
    && session?.resumeParams?.threadId === threadId
    && session?.acceptedHumanThreadId === threadId
  );
}

function activeTurnIDForSession(session) {
  return session?.detailSubscription?.ledger?.activeTurnID || null;
}

function turnIDFromResult(method, result) {
  if (method === "turn/steer") {
    return result?.turnId || result?.turnID || null;
  }
  return result?.turn?.id || result?.turnId || result?.turnID || null;
}

function staleTurnError(error) {
  const text = [
    error?.message,
    error?.data?.reason,
    error?.data?.message,
    error?.upstreamError?.message,
  ].filter(Boolean).join(" ").toLowerCase();
  return text.includes("expectedturn")
    || text.includes("expected turn")
    || text.includes("active turn")
    || text.includes("turn mismatch")
    || text.includes("cannot accept same-turn steering");
}

function ambiguousDeliveryError(error) {
  const text = String(error?.message || "").toLowerCase();
  return text.includes("timed out")
    || text.includes("websocket closed")
    || text.includes("socket")
    || text.includes("transport")
    || text.includes("not connected");
}

async function requestViaEphemeralClient(endpoint, method, params, logger) {
  const client = new JsonRpcWebSocketClient(endpoint.url, {
    bearerToken: endpoint.bearerToken || null,
    logger,
  });
  try {
    await initializeClient(client);
    return await client.request(method, params);
  } finally {
    client.close();
  }
}

async function submitToCodex({
  config,
  session,
  threadId,
  clientUserMessageID,
  input,
  preferredMethod = null,
  expectedTurnId = null,
}) {
  const activeSession = activeSessionMatchesThread(session, threadId);
  const activeTurnID = expectedTurnId || (activeSession ? activeTurnIDForSession(session) : null);
  const method = preferredMethod || (activeTurnID ? "turn/steer" : "turn/start");
  const params = {
    threadId,
    clientUserMessageId: clientUserMessageID,
    input,
    ...(method === "turn/steer" ? { expectedTurnId: activeTurnID } : {}),
  };
  try {
    if (activeSession) {
      return {
        method,
        endpointUrl: session.endpoint?.url || null,
        result: await session.upstream.request(method, params),
      };
    }

    let endpoint;
    if (config.appServerRegistry) {
      await config.appServerRegistry.ensureReady("user_message_route");
      endpoint = config.appServerRegistry.routeForThreadMethod(method, threadId).endpoint;
    } else {
      endpoint = await endpointForThread(config, threadId);
    }
    return {
      method,
      endpointUrl: endpoint.url || null,
      result: await requestViaEphemeralClient(endpoint, method, params, config.logger),
    };
  } catch (error) {
    if (error && typeof error === "object") {
      error.attemptedMethod = method;
    }
    throw error;
  }
}

class RelayUserMessageCommandEngine {
  constructor(config) {
    this.config = config;
    this.stateStore = relayStateStoreForConfig(config);
    this.store = outboundUserMessageStoreForConfig(config, this.stateStore);
  }

  async send(params = {}, { session = null, preferredMethod = null, expectedTurnId = null } = {}) {
    const threadId = nonEmptyString(params.threadId);
    const clientUserMessageID = nonEmptyString(params.clientUserMessageId);
    const input = validateInput(params.input);
    if (!threadId) {
      throw relayError("thread/message/send requires threadId", -32602, {
        subsystem: "user-message-command",
        reason: "missing_thread_id",
        retryable: false,
      });
    }
    if (!clientUserMessageID) {
      throw relayError("thread/message/send requires clientUserMessageId", -32602, {
        subsystem: "user-message-command",
        reason: "missing_client_user_message_id",
        retryable: false,
      });
    }

    await assertHumanThreadID(this.config, threadId);

    const hostID = this.config.hostId;
    const inputJSON = stableInputJSON(input);
    const hash = inputHash(inputJSON);
    const accepted = this.store.upsertAccepted({
      hostID,
      threadID: threadId,
      clientUserMessageID,
      inputJSON,
      inputHash: hash,
    });
    if (accepted.status === "collision") {
      const row = this.store.markFailed({
        hostID,
        threadID: threadId,
        clientUserMessageID,
        state: "failedDefinite",
        errorCode: "client_message_id_collision",
        errorMessage: "A different message already used this clientUserMessageId.",
      });
      throw relayError("clientUserMessageId collision", -32602, {
        subsystem: "user-message-command",
        reason: "client_message_id_collision",
        retryable: false,
        command: responseFromRow(row),
      });
    }
    if (accepted.status === "existing") {
      return responseFromRow(accepted.row);
    }

    try {
      const submitted = await submitToCodex({
        config: this.config,
        session,
        threadId,
        clientUserMessageID,
        input,
        preferredMethod,
        expectedTurnId,
      });
      const turnID = turnIDFromResult(submitted.method, submitted.result);
      const row = this.store.markSubmitted({
        hostID,
        threadID: threadId,
        clientUserMessageID,
        upstreamEndpointUrl: submitted.endpointUrl,
        upstreamMethod: submitted.method,
        codexTurnID: turnID,
      });
      return responseFromRow(row);
    } catch (error) {
      if (error?.attemptedMethod === "turn/steer" && staleTurnError(error)) {
        const submitted = await submitToCodex({
          config: this.config,
          session,
          threadId,
          clientUserMessageID,
          input,
          preferredMethod: "turn/start",
        });
        const turnID = turnIDFromResult(submitted.method, submitted.result);
        const row = this.store.markSubmitted({
          hostID,
          threadID: threadId,
          clientUserMessageID,
          upstreamEndpointUrl: submitted.endpointUrl,
          upstreamMethod: submitted.method,
          codexTurnID: turnID,
        });
        return responseFromRow(row);
      }

      const state = ambiguousDeliveryError(error) ? "failedAmbiguous" : "failedDefinite";
      const row = this.store.markFailed({
        hostID,
        threadID: threadId,
        clientUserMessageID,
        state,
        errorCode: error?.code ? String(error.code) : error?.name || "delivery_error",
        errorMessage: error?.message || "Message delivery failed.",
      });
      if (state === "failedAmbiguous") {
        return responseFromRow(row);
      }
      throw relayError(error?.message || "Message delivery failed.", error?.code || -32000, {
        subsystem: "user-message-command",
        reason: row.lastErrorCode || "delivery_error",
        retryable: false,
        command: responseFromRow(row),
      });
    }
  }

  markCanonicalRows(rows = []) {
    for (const row of rows || []) {
      const threadId = nonEmptyString(row?.threadID);
      const clientUserMessageID = nonEmptyString(row?.payload?.clientID);
      if (!threadId || !clientUserMessageID) {
        continue;
      }
      this.store.markCanonicalObserved({
        hostID: this.config.hostId,
        threadID: threadId,
        clientUserMessageID,
        codexTurnID: row?.payload?.turnID || null,
        codexItemID: row?.payload?.itemID || null,
      });
    }
  }
}

function userMessageCommandEngineForConfig(config) {
  if (!config.userMessageCommandEngine) {
    config.userMessageCommandEngine = new RelayUserMessageCommandEngine(config);
  }
  return config.userMessageCommandEngine;
}

export {
  RelayUserMessageCommandEngine,
  userMessageCommandEngineForConfig,
};

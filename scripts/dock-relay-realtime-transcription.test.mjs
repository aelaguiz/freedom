import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import test from "node:test";
import WebSocket, { WebSocketServer } from "ws";

import { startServer } from "./dock-relay.mjs";
import { createRelayLogger } from "./dock-relay-logger.mjs";
import { RealtimeTranscriptionManager } from "./dock-relay-realtime-transcription.mjs";
import {
  appServerRegistryFixtureConfig,
  closeWebSocketServer,
  jsonRpcRequest,
  onceListening,
  openWebSocket,
  waitForRelayMessage,
  waitForWebSocketClose,
} from "./dock-relay-test-helpers.mjs";

function waitForRealtimeConnection(server) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("timed out waiting for realtime connection")), 1_000);
    server.once("connection", (ws, request) => {
      clearTimeout(timer);
      resolve({ ws, request });
    });
  });
}

function waitForRealtimeMessage(ws, predicate = () => true) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("timed out waiting for realtime message")), 1_000);
    ws.on("message", function onMessage(data) {
      const message = JSON.parse(data.toString());
      if (predicate(message)) {
        clearTimeout(timer);
        ws.off("message", onMessage);
        resolve(message);
      }
    });
  });
}

function makeMemoryLogger(logs = []) {
  return createRelayLogger({
    stream: {
      write(line) {
        logs.push(line);
      },
    },
    clock: () => new Date("2026-05-28T00:00:00.000Z"),
  });
}

class FakeRealtimeWebSocket extends EventEmitter {
  constructor({ bufferedAmount = 0 } = {}) {
    super();
    this.readyState = WebSocket.CONNECTING;
    this.bufferedAmount = bufferedAmount;
    this.sent = [];
    queueMicrotask(() => {
      this.readyState = WebSocket.OPEN;
      this.emit("open");
    });
  }

  send(data) {
    this.sent.push(JSON.parse(data));
  }

  close() {
    if (this.readyState === WebSocket.CLOSED) {
      return;
    }
    this.readyState = WebSocket.CLOSED;
    this.emit("close");
  }
}

async function startRealtimeRelay(config = {}) {
  const realtimeServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await onceListening(realtimeServer);
  const defaultWebSocketFactory = (url, options) => {
    const requestedUrl = new URL(url);
    const localUrl = new URL(`ws://127.0.0.1:${realtimeServer.address().port}`);
    localUrl.pathname = requestedUrl.pathname;
    localUrl.search = requestedUrl.search;
    return new WebSocket(localUrl, options);
  };
  const openAIRealtimeWebSocketFactory = config.openAIRealtimeWebSocketFactory
    || defaultWebSocketFactory;
  const relay = startServer({
    listenHost: "127.0.0.1",
    port: 0,
    phoneAuth: "none",
    ...appServerRegistryFixtureConfig({
      historyUrl: "ws://127.0.0.1:1",
      historyBearerToken: "history-token",
    }),
    advertiseBonjour: false,
    openAIAPIKey: "relay-openai-key",
    openAIRealtimeTranscriptionEndpoint: "wss://api.openai.com/v1/realtime",
    logger: makeMemoryLogger(),
    ...config,
    openAIRealtimeWebSocketFactory,
  });
  await relay.listening;
  const phone = await openWebSocket(`ws://127.0.0.1:${relay.server.address().port}`);
  return { phone, realtimeServer, relay };
}

test("realtime transcription streams relay-owned delta and completion events", async () => {
  const { phone, realtimeServer, relay } = await startRealtimeRelay({
    openAISafetyIdentifier: "hashed-user-id",
    openAIRealtimeTranscriptionEndpoint: "wss://api.openai.com/v1/realtime?model=old-model",
  });
  const connectionPromise = waitForRealtimeConnection(realtimeServer);

  try {
    const startPromise = jsonRpcRequest(phone, "audio/transcription/start", {
      language: "en",
      delay: "minimal",
    });
    const { ws: upstream, request } = await connectionPromise;
    const sessionUpdatePromise = waitForRealtimeMessage(
      upstream,
      (message) => message.type === "session.update",
    );
    const startResponse = await startPromise;
    assert.equal(startResponse.error, undefined);
    assert.equal(startResponse.result.format, "audio/pcm");
    assert.equal(startResponse.result.sampleRate, 24_000);
    assert.equal(startResponse.result.model, "gpt-realtime-whisper");
    assert.equal(startResponse.result.language, "en");
    assert.equal(startResponse.result.delay, "minimal");
    assert.equal(request.headers.authorization, "Bearer relay-openai-key");
    assert.equal(request.headers["openai-safety-identifier"], "hashed-user-id");
    assert.match(request.url, /intent=transcription/);
    assert.doesNotMatch(request.url, /model=/);
    assert.doesNotMatch(request.url, /old-model/);

    const sessionUpdate = await sessionUpdatePromise;
    assert.equal(sessionUpdate.session.type, "transcription");
    assert.deepEqual(sessionUpdate.session.audio.input.format, {
      type: "audio/pcm",
      rate: 24_000,
    });
    assert.deepEqual(sessionUpdate.session.audio.input.transcription, {
      model: "gpt-realtime-whisper",
      language: "en",
      delay: "minimal",
    });

    const audio = Buffer.from("fake pcm").toString("base64");
    const appendEventPromise = waitForRealtimeMessage(
      upstream,
      (message) => message.type === "input_audio_buffer.append",
    );
    const appendPromise = jsonRpcRequest(phone, "audio/transcription/append", {
      sessionId: startResponse.result.sessionId,
      sequence: 1,
      base64Audio: audio,
    });
    const appendEvent = await appendEventPromise;
    const appendResponse = await appendPromise;
    assert.deepEqual(appendResponse.result, {
      sessionId: startResponse.result.sessionId,
      acceptedSequence: 1,
    });
    assert.equal(appendEvent.audio, audio);

    const commitEventPromise = waitForRealtimeMessage(
      upstream,
      (message) => message.type === "input_audio_buffer.commit",
    );
    const commitPromise = jsonRpcRequest(phone, "audio/transcription/commit", {
      sessionId: startResponse.result.sessionId,
    });
    const commitEvent = await commitEventPromise;
    const commitResponse = await commitPromise;
    assert.deepEqual(commitResponse.result, {
      sessionId: startResponse.result.sessionId,
      committed: true,
    });
    assert.equal(commitEvent.type, "input_audio_buffer.commit");

    const firstDeltaPromise = waitForRelayMessage(
      phone,
      (message) => message.method === "audio/transcription/delta",
    );
    upstream.send(JSON.stringify({
      type: "conversation.item.input_audio_transcription.delta",
      item_id: "item_1",
      content_index: 0,
      delta: "Hello",
    }));
    const firstDelta = await firstDeltaPromise;
    assert.deepEqual(firstDelta.params, {
      sessionId: startResponse.result.sessionId,
      itemId: "item_1",
      contentIndex: 0,
      deltaText: "Hello",
      partialText: "Hello",
    });

    const secondDeltaPromise = waitForRelayMessage(
      phone,
      (message) => message.method === "audio/transcription/delta",
    );
    upstream.send(JSON.stringify({
      type: "conversation.item.input_audio_transcription.delta",
      item_id: "item_1",
      content_index: 0,
      delta: " world",
    }));
    const secondDelta = await secondDeltaPromise;
    assert.equal(secondDelta.params.deltaText, " world");
    assert.equal(secondDelta.params.partialText, "Hello world");

    const completedPromise = waitForRelayMessage(
      phone,
      (message) => message.method === "audio/transcription/completed",
    );
    const closedPromise = waitForRelayMessage(
      phone,
      (message) => message.method === "audio/transcription/closed",
    );
    upstream.send(JSON.stringify({
      type: "conversation.item.input_audio_transcription.completed",
      item_id: "item_1",
      content_index: 0,
      transcript: "Hello world",
    }));
    const completed = await completedPromise;
    const closed = await closedPromise;
    assert.deepEqual(completed.params, {
      sessionId: startResponse.result.sessionId,
      itemId: "item_1",
      contentIndex: 0,
      transcript: "Hello world",
    });
    assert.deepEqual(closed.params, {
      sessionId: startResponse.result.sessionId,
      reason: "completed",
    });
  } finally {
    phone.close();
    await relay.close();
    await closeWebSocketServer(realtimeServer);
  }
});

test("realtime transcription logs safe audio totals and limits", async () => {
  const logs = [];
  const { phone, realtimeServer, relay } = await startRealtimeRelay({
    logger: makeMemoryLogger(logs),
  });
  const connectionPromise = waitForRealtimeConnection(realtimeServer);

  try {
    const startPromise = jsonRpcRequest(phone, "audio/transcription/start", {
      language: "en",
    });
    const { ws: upstream } = await connectionPromise;
    const sessionUpdatePromise = waitForRealtimeMessage(
      upstream,
      (message) => message.type === "session.update",
    );
    const startResponse = await startPromise;
    await sessionUpdatePromise;

    const audio = Buffer.from("private audio bytes").toString("base64");
    const appendEventPromise = waitForRealtimeMessage(
      upstream,
      (message) => message.type === "input_audio_buffer.append",
    );
    await jsonRpcRequest(phone, "audio/transcription/append", {
      sessionId: startResponse.result.sessionId,
      sequence: 1,
      base64Audio: audio,
    });
    await appendEventPromise;

    const commitEventPromise = waitForRealtimeMessage(
      upstream,
      (message) => message.type === "input_audio_buffer.commit",
    );
    await jsonRpcRequest(phone, "audio/transcription/commit", {
      sessionId: startResponse.result.sessionId,
    });
    await commitEventPromise;

    const completedPromise = waitForRelayMessage(
      phone,
      (message) => message.method === "audio/transcription/completed",
    );
    const closedPromise = waitForRelayMessage(
      phone,
      (message) => message.method === "audio/transcription/closed",
    );
    upstream.send(JSON.stringify({
      type: "conversation.item.input_audio_transcription.completed",
      item_id: "item_1",
      content_index: 0,
      transcript: "private transcript",
    }));
    await completedPromise;
    await closedPromise;
  } finally {
    phone.close();
    await relay.close();
    await closeWebSocketServer(realtimeServer);
  }

  const records = logs.map((line) => JSON.parse(line));
  const startRequested = records.find((record) => record.event === "transcription.start_requested");
  assert.equal(startRequested.fields.sampleRate, 24_000);
  assert.equal(startRequested.fields.maxChunkBytes, 64 * 1024);
  assert.equal(startRequested.fields.maxPendingBytes, 1024 * 1024);

  const appendAccepted = records.find((record) => record.event === "transcription.append_accepted");
  assert.equal(appendAccepted.fields.sequence, 1);
  assert.equal(appendAccepted.fields.acceptedChunks, 1);
  assert.equal(appendAccepted.fields.acceptedBytes, Buffer.from("private audio bytes").byteLength);
  assert.equal(Number.isInteger(appendAccepted.fields.peakAbs), true);
  assert.equal(Number.isInteger(appendAccepted.fields.rms), true);
  assert.equal(Number.isInteger(appendAccepted.fields.nonSilentChunks), true);

  const commitRequested = records.find((record) => record.event === "transcription.commit_requested");
  assert.equal(commitRequested.fields.lastSequence, 1);
  assert.equal(commitRequested.fields.acceptedChunks, 1);
  assert.equal(commitRequested.fields.acceptedBytes, Buffer.from("private audio bytes").byteLength);
  assert.equal(Number.isInteger(commitRequested.fields.peakAbs), true);
  assert.equal(Number.isInteger(commitRequested.fields.maxRms), true);
  assert.equal(Number.isInteger(commitRequested.fields.nonSilentChunks), true);

  const closing = records.find((record) => (
    record.event === "transcription.session_closing"
      && record.fields.reason === "completed"
  ));
  assert.equal(closing.fields.acceptedChunks, 1);
  assert.equal(closing.fields.acceptedBytes, Buffer.from("private audio bytes").byteLength);
  assert.equal(closing.fields.lastSequence, 1);
  assert.equal(Number.isInteger(closing.fields.peakAbs), true);
  assert.equal(Number.isInteger(closing.fields.maxRms), true);
  assert.equal(Number.isInteger(closing.fields.nonSilentChunks), true);

  const logText = logs.join("\n");
  assert.equal(logText.includes(Buffer.from("private audio bytes").toString("base64")), false);
  assert.equal(logText.includes("private transcript"), false);
});

test("realtime transcription empty upstream completion completes without protocol failure", async () => {
  const { phone, realtimeServer, relay } = await startRealtimeRelay();
  const connectionPromise = waitForRealtimeConnection(realtimeServer);

  try {
    const startPromise = jsonRpcRequest(phone, "audio/transcription/start", {
      language: "en",
    });
    const { ws: upstream } = await connectionPromise;
    const sessionUpdatePromise = waitForRealtimeMessage(
      upstream,
      (message) => message.type === "session.update",
    );
    const startResponse = await startPromise;
    await sessionUpdatePromise;

    const completedPromise = waitForRelayMessage(
      phone,
      (message) => message.method === "audio/transcription/completed",
    );
    const closedPromise = waitForRelayMessage(
      phone,
      (message) => message.method === "audio/transcription/closed",
    );
    upstream.send(JSON.stringify({
      type: "conversation.item.input_audio_transcription.completed",
      item_id: "item_empty",
      content_index: 0,
      transcript: "",
    }));

    const completed = await completedPromise;
    const closed = await closedPromise;
    assert.deepEqual(completed.params, {
      sessionId: startResponse.result.sessionId,
      itemId: "item_empty",
      contentIndex: 0,
      transcript: "",
    });
    assert.deepEqual(closed.params, {
      sessionId: startResponse.result.sessionId,
      reason: "completed_empty",
    });
  } finally {
    phone.close();
    await relay.close();
    await closeWebSocketServer(realtimeServer);
  }
});

test("realtime transcription rejects phone provider config and invalid chunks", async () => {
  const missingKeyRelay = startServer({
    listenHost: "127.0.0.1",
    port: 0,
    phoneAuth: "none",
    ...appServerRegistryFixtureConfig({
      historyUrl: "ws://127.0.0.1:1",
      historyBearerToken: "history-token",
    }),
    advertiseBonjour: false,
  });
  await missingKeyRelay.listening;
  const missingKeyPhone = await openWebSocket(`ws://127.0.0.1:${missingKeyRelay.server.address().port}`);
  try {
    const forbiddenProviderParams = [
      { model: "gpt-4o-transcribe" },
      { endpoint: "wss://example.test/realtime" },
      { headers: { Authorization: "Bearer phone-secret" } },
      { apiKey: "phone-openai-key" },
      { "OpenAI-Safety-Identifier": "phone-user" },
      { openAISafetyIdentifier: "phone-user" },
      { safetyIdentifier: "phone-user" },
      { sendOpenAIEvent: { type: "session.update" } },
    ];
    for (const params of forbiddenProviderParams) {
      const providerResponse = await jsonRpcRequest(
        missingKeyPhone,
        "audio/transcription/start",
        params,
      );
      assert.equal(providerResponse.error.code, -32602);
      assert.match(providerResponse.error.message, /provider configuration is relay-owned/);
    }

    const missingKeyResponse = await jsonRpcRequest(missingKeyPhone, "audio/transcription/start", {
      language: "en",
    });
    assert.equal(missingKeyResponse.error.code, -32000);
    assert.match(missingKeyResponse.error.message, /key is not configured on the relay/);
  } finally {
    missingKeyPhone.close();
    await missingKeyRelay.close();
  }

  const plaintextEndpointRelay = startServer({
    listenHost: "127.0.0.1",
    port: 0,
    phoneAuth: "none",
    ...appServerRegistryFixtureConfig({
      historyUrl: "ws://127.0.0.1:1",
      historyBearerToken: "history-token",
    }),
    advertiseBonjour: false,
    openAIAPIKey: "relay-openai-key",
    openAIRealtimeTranscriptionEndpoint: "ws://127.0.0.1:1/v1/realtime",
  });
  await plaintextEndpointRelay.listening;
  const plaintextEndpointPhone = await openWebSocket(`ws://127.0.0.1:${plaintextEndpointRelay.server.address().port}`);
  try {
    const plaintextResponse = await jsonRpcRequest(
      plaintextEndpointPhone,
      "audio/transcription/start",
      { language: "en" },
    );
    assert.equal(plaintextResponse.error.code, -32000);
    assert.match(plaintextResponse.error.message, /endpoint must use wss/);
  } finally {
    plaintextEndpointPhone.close();
    await plaintextEndpointRelay.close();
  }

  const { phone, realtimeServer, relay } = await startRealtimeRelay({
    realtimeTranscriptionMaxChunkBytes: 4,
  });
  const connectionPromise = waitForRealtimeConnection(realtimeServer);
  try {
    const startPromise = jsonRpcRequest(phone, "audio/transcription/start", {
      language: "en",
    });
    const { ws: upstream } = await connectionPromise;
    const sessionUpdatePromise = waitForRealtimeMessage(
      upstream,
      (message) => message.type === "session.update",
    );
    const startResponse = await startPromise;
    await sessionUpdatePromise;

    const duplicateStart = await jsonRpcRequest(phone, "audio/transcription/start", {
      language: "en",
    });
    assert.equal(duplicateStart.error.code, -32000);
    assert.match(duplicateStart.error.message, /already has an active session/);

    const badAudio = await jsonRpcRequest(phone, "audio/transcription/append", {
      sessionId: startResponse.result.sessionId,
      sequence: 1,
      base64Audio: "not-base64",
    });
    assert.equal(badAudio.error.code, -32602);
    assert.match(badAudio.error.message, /requires base64Audio/);

    const tooLarge = await jsonRpcRequest(phone, "audio/transcription/append", {
      sessionId: startResponse.result.sessionId,
      sequence: 1,
      base64Audio: Buffer.from("large").toString("base64"),
    });
    assert.equal(tooLarge.error.code, -32602);
    assert.match(tooLarge.error.message, /too large/);

    const appendEventPromise = waitForRealtimeMessage(
      upstream,
      (message) => message.type === "input_audio_buffer.append",
    );
    const appendPromise = jsonRpcRequest(phone, "audio/transcription/append", {
      sessionId: startResponse.result.sessionId,
      sequence: 1,
      base64Audio: Buffer.from("ok").toString("base64"),
    });
    await appendEventPromise;
    const appendResponse = await appendPromise;
    assert.equal(appendResponse.error, undefined);

    const duplicateSequence = await jsonRpcRequest(phone, "audio/transcription/append", {
      sessionId: startResponse.result.sessionId,
      sequence: 1,
      base64Audio: Buffer.from("ok").toString("base64"),
    });
    assert.equal(duplicateSequence.error.code, -32602);
    assert.match(duplicateSequence.error.message, /monotonic sequence/);
  } finally {
    phone.close();
    await relay.close();
    await closeWebSocketServer(realtimeServer);
  }
});

test("realtime transcription rejects chunks that would exceed pending queue bounds", async () => {
  const fakeUpstream = new FakeRealtimeWebSocket({ bufferedAmount: 3 });
  const manager = new RealtimeTranscriptionManager({
    openAIAPIKey: "relay-openai-key",
    openAIRealtimeTranscriptionEndpoint: "wss://api.openai.com/v1/realtime",
    realtimeTranscriptionMaxPendingBytes: 4,
    openAIRealtimeWebSocketFactory: () => fakeUpstream,
  });

  const started = await manager.start({ language: "en" });
  assert.throws(
    () => manager.append({
      sessionId: started.sessionId,
      sequence: 1,
      base64Audio: Buffer.from("ok").toString("base64"),
    }),
    /pending audio queue is full/,
  );
  assert.equal(
    fakeUpstream.sent.some((event) => event.type === "input_audio_buffer.append"),
    false,
  );
  manager.closeAll("test_done");
});

test("realtime transcription cancel and downstream close clean upstream sessions", async () => {
  const { phone, realtimeServer, relay } = await startRealtimeRelay();
  let connectionPromise = waitForRealtimeConnection(realtimeServer);

  try {
    let startPromise = jsonRpcRequest(phone, "audio/transcription/start", {
      language: "en",
    });
    let { ws: upstream } = await connectionPromise;
    let sessionUpdatePromise = waitForRealtimeMessage(
      upstream,
      (message) => message.type === "session.update",
    );
    let startResponse = await startPromise;
    await sessionUpdatePromise;

    const canceledPromise = waitForRelayMessage(
      phone,
      (message) => message.method === "audio/transcription/canceled",
    );
    const closedPromise = waitForRelayMessage(
      phone,
      (message) => message.method === "audio/transcription/closed",
    );
    const upstreamClosedPromise = waitForWebSocketClose(upstream);
    const cancelResponse = await jsonRpcRequest(phone, "audio/transcription/cancel", {
      sessionId: startResponse.result.sessionId,
    });
    const canceled = await canceledPromise;
    const closed = await closedPromise;
    await upstreamClosedPromise;
    assert.deepEqual(cancelResponse.result, {
      sessionId: startResponse.result.sessionId,
      canceled: true,
    });
    assert.deepEqual(canceled.params, {
      sessionId: startResponse.result.sessionId,
    });
    assert.deepEqual(closed.params, {
      sessionId: startResponse.result.sessionId,
      reason: "canceled",
    });

    connectionPromise = waitForRealtimeConnection(realtimeServer);
    startPromise = jsonRpcRequest(phone, "audio/transcription/start", {
      language: "en",
    });
    ({ ws: upstream } = await connectionPromise);
    sessionUpdatePromise = waitForRealtimeMessage(
      upstream,
      (message) => message.type === "session.update",
    );
    startResponse = await startPromise;
    await sessionUpdatePromise;
    const downstreamClosePromise = waitForWebSocketClose(upstream);
    phone.close();
    await downstreamClosePromise;
    assert.equal(startResponse.result.sessionId.length > 0, true);
  } finally {
    await relay.close();
    await closeWebSocketServer(realtimeServer);
  }
});

test("realtime transcription malformed upstream transcript events fail safely", async () => {
  const { phone, realtimeServer, relay } = await startRealtimeRelay();
  let connectionPromise = waitForRealtimeConnection(realtimeServer);

  try {
    let startPromise = jsonRpcRequest(phone, "audio/transcription/start", {
      language: "en",
    });
    let { ws: upstream } = await connectionPromise;
    let sessionUpdatePromise = waitForRealtimeMessage(
      upstream,
      (message) => message.type === "session.update",
    );
    let startResponse = await startPromise;
    await sessionUpdatePromise;

    let failedPromise = waitForRelayMessage(
      phone,
      (message) => message.method === "audio/transcription/failed",
    );
    let closedPromise = waitForRelayMessage(
      phone,
      (message) => message.method === "audio/transcription/closed",
    );
    upstream.send(JSON.stringify({
      type: "conversation.item.input_audio_transcription.delta",
      content_index: 0,
      delta: "bad",
    }));
    let failed = await failedPromise;
    let closed = await closedPromise;
    assert.deepEqual(failed.params, {
      sessionId: startResponse.result.sessionId,
      reason: "invalid_upstream_event",
    });
    assert.deepEqual(closed.params, {
      sessionId: startResponse.result.sessionId,
      reason: "invalid_upstream_event",
    });

    connectionPromise = waitForRealtimeConnection(realtimeServer);
    startPromise = jsonRpcRequest(phone, "audio/transcription/start", {
      language: "en",
    });
    ({ ws: upstream } = await connectionPromise);
    sessionUpdatePromise = waitForRealtimeMessage(
      upstream,
      (message) => message.type === "session.update",
    );
    startResponse = await startPromise;
    await sessionUpdatePromise;

    failedPromise = waitForRelayMessage(
      phone,
      (message) => message.method === "audio/transcription/failed",
    );
    closedPromise = waitForRelayMessage(
      phone,
      (message) => message.method === "audio/transcription/closed",
    );
    upstream.send(JSON.stringify({
      type: "conversation.item.input_audio_transcription.completed",
      content_index: 0,
      transcript: "bad",
    }));
    failed = await failedPromise;
    closed = await closedPromise;
    assert.deepEqual(failed.params, {
      sessionId: startResponse.result.sessionId,
      reason: "invalid_upstream_event",
    });
    assert.deepEqual(closed.params, {
      sessionId: startResponse.result.sessionId,
      reason: "invalid_upstream_event",
    });
  } finally {
    phone.close();
    await relay.close();
    await closeWebSocketServer(realtimeServer);
  }
});

test("realtime transcription invalid upstream JSON and upstream close fail safely", async () => {
  const { phone, realtimeServer, relay } = await startRealtimeRelay();
  let connectionPromise = waitForRealtimeConnection(realtimeServer);

  try {
    let startPromise = jsonRpcRequest(phone, "audio/transcription/start", {
      language: "en",
    });
    let { ws: upstream } = await connectionPromise;
    let sessionUpdatePromise = waitForRealtimeMessage(
      upstream,
      (message) => message.type === "session.update",
    );
    let startResponse = await startPromise;
    await sessionUpdatePromise;

    let failedPromise = waitForRelayMessage(
      phone,
      (message) => message.method === "audio/transcription/failed",
    );
    let closedPromise = waitForRelayMessage(
      phone,
      (message) => message.method === "audio/transcription/closed",
    );
    upstream.send("not-json");
    let failed = await failedPromise;
    let closed = await closedPromise;
    assert.deepEqual(failed.params, {
      sessionId: startResponse.result.sessionId,
      reason: "invalid_upstream_event",
    });
    assert.deepEqual(closed.params, {
      sessionId: startResponse.result.sessionId,
      reason: "invalid_upstream_event",
    });

    connectionPromise = waitForRealtimeConnection(realtimeServer);
    startPromise = jsonRpcRequest(phone, "audio/transcription/start", {
      language: "en",
    });
    ({ ws: upstream } = await connectionPromise);
    sessionUpdatePromise = waitForRealtimeMessage(
      upstream,
      (message) => message.type === "session.update",
    );
    startResponse = await startPromise;
    await sessionUpdatePromise;

    failedPromise = waitForRelayMessage(
      phone,
      (message) => message.method === "audio/transcription/failed",
    );
    closedPromise = waitForRelayMessage(
      phone,
      (message) => message.method === "audio/transcription/closed",
    );
    upstream.close();
    failed = await failedPromise;
    closed = await closedPromise;
    assert.deepEqual(failed.params, {
      sessionId: startResponse.result.sessionId,
      reason: "upstream_closed",
    });
    assert.deepEqual(closed.params, {
      sessionId: startResponse.result.sessionId,
      reason: "upstream_closed",
    });
  } finally {
    phone.close();
    await relay.close();
    await closeWebSocketServer(realtimeServer);
  }
});

test("realtime transcription relay shutdown closes active upstream sessions", async () => {
  const { phone, realtimeServer, relay } = await startRealtimeRelay();
  const connectionPromise = waitForRealtimeConnection(realtimeServer);

  try {
    const startPromise = jsonRpcRequest(phone, "audio/transcription/start", {
      language: "en",
    });
    const { ws: upstream } = await connectionPromise;
    const sessionUpdatePromise = waitForRealtimeMessage(
      upstream,
      (message) => message.type === "session.update",
    );
    await startPromise;
    await sessionUpdatePromise;

    const upstreamClosedPromise = waitForWebSocketClose(upstream);
    const phoneClosedPromise = waitForWebSocketClose(phone);
    await relay.close();
    await upstreamClosedPromise;
    await phoneClosedPromise;
  } finally {
    if (phone.readyState !== WebSocket.CLOSED) {
      phone.close();
    }
    await closeWebSocketServer(realtimeServer);
  }
});

test("realtime transcription failure notifications and logs are sanitized", async () => {
  const logs = [];
  const { phone, realtimeServer, relay } = await startRealtimeRelay({
    logger: makeMemoryLogger(logs),
  });
  const connectionPromise = waitForRealtimeConnection(realtimeServer);
  try {
    const startPromise = jsonRpcRequest(phone, "audio/transcription/start", {
      language: "en",
    });
    const { ws: upstream } = await connectionPromise;
    const sessionUpdatePromise = waitForRealtimeMessage(
      upstream,
      (message) => message.type === "session.update",
    );
    const startResponse = await startPromise;
    await sessionUpdatePromise;

    const failedPromise = waitForRelayMessage(
      phone,
      (message) => message.method === "audio/transcription/failed",
    );
    const closedPromise = waitForRelayMessage(
      phone,
      (message) => message.method === "audio/transcription/closed",
    );
    upstream.send(JSON.stringify({
      type: "error",
      error: {
        message: "relay-openai-key raw audio bytes private transcript",
      },
    }));
    const failed = await failedPromise;
    const closed = await closedPromise;
    assert.deepEqual(failed.params, {
      sessionId: startResponse.result.sessionId,
      reason: "upstream_error",
    });
    assert.deepEqual(closed.params, {
      sessionId: startResponse.result.sessionId,
      reason: "upstream_error",
    });

    const phoneVisible = JSON.stringify({ failed, closed });
    assert.equal(phoneVisible.includes("relay-openai-key"), false);
    assert.equal(phoneVisible.includes("raw audio bytes"), false);
    assert.equal(phoneVisible.includes("private transcript"), false);
  } finally {
    phone.close();
    await relay.close();
    await closeWebSocketServer(realtimeServer);
  }

  const logText = logs.join("\n");
  assert.equal(logText.includes("relay-openai-key"), false);
  assert.equal(logText.includes("raw audio bytes"), false);
  assert.equal(logText.includes("private transcript"), false);
});

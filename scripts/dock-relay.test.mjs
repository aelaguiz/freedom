import assert from "node:assert/strict";
import test from "node:test";
import WebSocket, { WebSocketServer } from "ws";

import {
  attentionFlagsForServerRequest,
  buildBonjourAdvertisementArgs,
  decodedAudioTranscribeParams,
  isPhoneRequestAuthorized,
  mergeActiveFlags,
  preferThread,
  sanitizeRelayFields,
  shouldCollectLiveRowsForThreadList,
  startServer,
  statusPriority,
  transcribeAudio,
} from "./dock-relay.mjs";

test("attention flags are derived from real app-server request methods", () => {
  assert.deepEqual(
    attentionFlagsForServerRequest({
      method: "item/commandExecution/requestApproval",
    }),
    ["waitingOnApproval"],
  );
  assert.deepEqual(
    attentionFlagsForServerRequest({
      method: "item/tool/requestUserInput",
    }),
    ["waitingOnUserInput"],
  );
  assert.deepEqual(
    attentionFlagsForServerRequest({
      method: "mcpServer/elicitation/request",
    }),
    ["waitingOnUserInput"],
  );
  assert.deepEqual(
    attentionFlagsForServerRequest({
      method: "thread/status/changed",
    }),
    [],
  );
});

test("mergeActiveFlags preserves existing active flags", () => {
  const row = {
    id: "thread-1",
    status: {
      type: "active",
      activeFlags: ["waitingOnApproval"],
    },
  };

  assert.deepEqual(
    mergeActiveFlags(row, ["waitingOnUserInput"]),
    {
      id: "thread-1",
      status: {
        type: "active",
        activeFlags: ["waitingOnApproval", "waitingOnUserInput"],
      },
    },
  );
});

test("active attention outranks plain active when deduping live rows", () => {
  const plain = {
    id: "thread-1",
    updatedAt: 10,
    status: {
      type: "active",
      activeFlags: [],
    },
  };
  const needsAttention = {
    id: "thread-1",
    updatedAt: 9,
    status: {
      type: "active",
      activeFlags: ["waitingOnUserInput"],
    },
  };

  assert.equal(statusPriority(needsAttention), 0);
  assert.equal(preferThread(plain, needsAttention), needsAttention);
});

test("archived thread/list does not merge live loopback rows", () => {
  assert.equal(shouldCollectLiveRowsForThreadList({ archived: true }), false);
  assert.equal(shouldCollectLiveRowsForThreadList({ archived: false }), true);
  assert.equal(shouldCollectLiveRowsForThreadList({}), true);
});

test("relay source marker is never returned to clients", () => {
  assert.deepEqual(
    sanitizeRelayFields({
      id: "thread-1",
      dockRelaySource: { url: "ws://127.0.0.1:4555" },
    }),
    { id: "thread-1" },
  );
});

test("phone auth none permits local phone connections without a bearer token", () => {
  assert.equal(
    isPhoneRequestAuthorized({ headers: {} }, { phoneAuth: "none" }),
    true,
  );
  assert.equal(
    isPhoneRequestAuthorized(
      { headers: { authorization: "Bearer wrong" } },
      { phoneAuth: "bearer", relayBearerToken: "right" },
    ),
    false,
  );
  assert.equal(
    isPhoneRequestAuthorized(
      { headers: { authorization: "Bearer right" } },
      { phoneAuth: "bearer", relayBearerToken: "right" },
    ),
    true,
  );
});

test("Bonjour advertisement contains only non-secret relay metadata", () => {
  const args = buildBonjourAdvertisementArgs({
    bonjourName: "Codex Dock Test",
    phoneAuth: "none",
    port: 4510,
    version: "0.1.0",
  });

  assert.deepEqual(args.slice(0, 5), [
    "-R",
    "Codex Dock Test",
    "_codexdock._tcp",
    "local",
    "4510",
  ]);
  assert.ok(args.includes("version=0.1.0"));
  assert.ok(args.includes("auth=none"));
  assert.ok(args.includes("scheme=ws"));
  assert.equal(args.some((value) => /token|secret|key/i.test(value)), false);
});

test("audio/transcribe validates phone payload and rejects phone-supplied model", () => {
  const audio = Buffer.from("fake m4a bytes").toString("base64");
  const decoded = decodedAudioTranscribeParams({
    mimeType: "audio/mp4",
    base64Audio: audio,
  });
  assert.equal(decoded.mimeType, "audio/mp4");
  assert.equal(decoded.bytes.toString(), "fake m4a bytes");

  assert.throws(
    () => decodedAudioTranscribeParams({
      mimeType: "audio/mp4",
      base64Audio: audio,
      model: "whisper-1",
    }),
    /model is configured on the relay/,
  );
  assert.throws(
    () => decodedAudioTranscribeParams({
      mimeType: "text/plain",
      base64Audio: audio,
    }),
    /supported audio mimeType/,
  );
  assert.throws(
    () => decodedAudioTranscribeParams({
      mimeType: "audio/mp4",
      base64Audio: audio,
    }, 3),
    /too large/,
  );
});

test("audio/transcribe uses the relay OpenAI key and configured latest model", async () => {
  const audio = Buffer.from("fake m4a bytes").toString("base64");
  const captured = {};
  const result = await transcribeAudio({
    openAIAPIKey: "relay-openai-key",
    openAITranscriptionModel: "gpt-4o-transcribe",
    openAITranscriptionEndpoint: "https://example.test/transcribe",
    fetch: async (url, init) => {
      captured.url = url;
      captured.authorization = init.headers.Authorization;
      captured.model = init.body.get("model");
      captured.responseFormat = init.body.get("response_format");
      captured.file = init.body.get("file");
      return {
        ok: true,
        status: 200,
        json: async () => ({ text: "  Check the relay  " }),
      };
    },
  }, {
    mimeType: "audio/mp4",
    base64Audio: audio,
  });

  assert.deepEqual(result, { text: "Check the relay" });
  assert.equal(captured.url, "https://example.test/transcribe");
  assert.equal(captured.authorization, "Bearer relay-openai-key");
  assert.equal(captured.model, "gpt-4o-transcribe");
  assert.equal(captured.responseFormat, "json");
  assert.equal(captured.file.size, Buffer.from("fake m4a bytes").length);
});

test("audio/transcribe fails safely for missing key and upstream failures", async () => {
  const audio = Buffer.from("fake m4a bytes").toString("base64");
  await assert.rejects(
    () => transcribeAudio({}, {
      mimeType: "audio/mp4",
      base64Audio: audio,
    }),
    /key is not configured on the relay/,
  );

  await assert.rejects(
    () => transcribeAudio({
      openAIAPIKey: "relay-openai-key",
      fetch: async () => ({
        ok: false,
        status: 503,
        json: async () => ({ error: "do not leak this body" }),
      }),
    }, {
      mimeType: "audio/mp4",
      base64Audio: audio,
    }),
    /failed with status 503/,
  );

  await assert.rejects(
    () => transcribeAudio({
      openAIAPIKey: "relay-openai-key",
      fetch: async () => ({
        ok: true,
        status: 200,
        json: async () => ({ text: "" }),
      }),
    }, {
      mimeType: "audio/mp4",
      base64Audio: audio,
    }),
    /returned no text/,
  );
});

test("audio/transcribe timeout returns a safe relay error", async () => {
  const audio = Buffer.from("fake m4a bytes").toString("base64");
  await assert.rejects(
    () => transcribeAudio({
      openAIAPIKey: "relay-openai-key",
      transcriptionTimeoutMs: 1,
      fetch: async (_url, init) => new Promise((_resolve, reject) => {
        if (init.signal.aborted) {
          const error = new Error("request aborted");
          error.name = "AbortError";
          reject(error);
          return;
        }
        init.signal.addEventListener("abort", () => {
          const error = new Error("request aborted");
          error.name = "AbortError";
          reject(error);
        });
      }),
    }, {
      mimeType: "audio/mp4",
      base64Audio: audio,
    }),
    /timed out/,
  );
});

test("audio/transcribe does not log keys, audio, or transcript text", async () => {
  const logs = [];
  const originalError = console.error;
  console.error = (...values) => {
    logs.push(values.join(" "));
  };
  try {
    await transcribeAudio({
      openAIAPIKey: "relay-openai-key",
      fetch: async () => ({
        ok: true,
        status: 200,
        json: async () => ({ text: "private transcript" }),
      }),
    }, {
      mimeType: "audio/mp4",
      base64Audio: Buffer.from("raw audio bytes").toString("base64"),
    });
  } finally {
    console.error = originalError;
  }

  assert.equal(logs.join("\n").includes("relay-openai-key"), false);
  assert.equal(logs.join("\n").includes("raw audio bytes"), false);
  assert.equal(logs.join("\n").includes("private transcript"), false);
});

test("relay server accepts no-auth phone mode and rejects unsupported methods", async () => {
  const relay = startServer({
    listenHost: "127.0.0.1",
    port: 0,
    phoneAuth: "none",
    historyUrl: "ws://127.0.0.1:1",
    historyBearerToken: "history-token",
    advertiseBonjour: false,
  });
  await relay.listening;
  const port = relay.server.address().port;
  const ws = await openWebSocket(`ws://127.0.0.1:${port}`);

  try {
    const response = await jsonRpcRequest(ws, "missing/method");
    assert.equal(response.error.code, -32601);
    assert.match(response.error.message, /unsupported method/);
  } finally {
    ws.close();
    await relay.close();
  }
});

test("relay keeps the raw history app-server token on the Mac side", async () => {
  let observedAuthorization = null;
  const historyServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await onceListening(historyServer);
  historyServer.on("connection", (ws, request) => {
    observedAuthorization = request.headers.authorization;
    ws.on("message", (data) => {
      const message = JSON.parse(data.toString());
      if (message.method === "initialize") {
        ws.send(JSON.stringify({
          id: message.id,
          result: {
            userAgent: "codex-test",
            codexHome: "/tmp/codex",
            platformFamily: "unix",
            platformOs: "macos",
          },
        }));
      } else if (message.method === "thread/list") {
        ws.send(JSON.stringify({
          id: message.id,
          result: {
            data: [],
            nextCursor: null,
            backwardsCursor: null,
          },
        }));
      }
    });
  });

  const relay = startServer({
    listenHost: "127.0.0.1",
    port: 0,
    phoneAuth: "none",
    historyUrl: `ws://127.0.0.1:${historyServer.address().port}`,
    historyBearerToken: "history-token",
    advertiseBonjour: false,
  });
  await relay.listening;
  const ws = await openWebSocket(`ws://127.0.0.1:${relay.server.address().port}`);

  try {
    const response = await jsonRpcRequest(ws, "thread/list", { archived: true });
    assert.deepEqual(response.result.data, []);
    assert.equal(observedAuthorization, "Bearer history-token");
  } finally {
    ws.close();
    await relay.close();
    await closeWebSocketServer(historyServer);
  }
});

function onceListening(server) {
  if (server.address()) {
    return Promise.resolve();
  }
  return new Promise((resolve) => {
    server.once("listening", resolve);
  });
}

function openWebSocket(url, options = undefined) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(url, options);
    ws.once("open", () => resolve(ws));
    ws.once("error", reject);
  });
}

function jsonRpcRequest(ws, method, params = undefined) {
  const id = `${method}-test`;
  const payload = { id, method };
  if (params !== undefined) {
    payload.params = params;
  }
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`timed out waiting for ${method}`)), 1_000);
    ws.on("message", function onMessage(data) {
      const message = JSON.parse(data.toString());
      if (message.id === id) {
        clearTimeout(timer);
        ws.off("message", onMessage);
        resolve(message);
      }
    });
    ws.send(JSON.stringify(payload));
  });
}

function closeWebSocketServer(server) {
  return new Promise((resolve, reject) => {
    server.close((error) => {
      if (error) {
        reject(error);
      } else {
        resolve();
      }
    });
  });
}

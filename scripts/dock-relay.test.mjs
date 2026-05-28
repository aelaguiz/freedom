import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import test from "node:test";
import WebSocket, { WebSocketServer } from "ws";

import {
  attentionFlagsForServerRequest,
  buildBonjourAdvertisementArgs,
  decodedAudioTranscribeParams,
  isPhoneRequestAuthorized,
  mergeThreadListRows,
  mergeActiveFlags,
  preferThread,
  sanitizeRelayFields,
  shouldCollectLiveRowsForThreadList,
  startServer,
  statusPriority,
  threadMatchesSourceKinds,
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

test("default thread/list sourceKinds keeps only interactive live sources", () => {
  const cases = [
    ["cli", { source: "cli" }, true],
    ["vscode", { source: "vscode" }, true],
    ["atlas custom", { source: { custom: "atlas" } }, true],
    ["chatgpt custom", { source: { custom: "chatgpt" } }, true],
    ["atlas legacy string", { source: "atlas" }, true],
    ["exec", { source: "exec" }, false],
    ["appServer", { source: "appServer" }, false],
    ["appServer object", { source: { appServer: {} } }, false],
    ["mcp alias", { source: "mcp" }, false],
    ["mcp object", { source: { mcp: {} } }, false],
    ["subAgent", { source: { subAgent: "review" } }, false],
    ["unknown", { source: "unknown" }, false],
    ["missing source", {}, false],
  ];

  for (const [name, row, expected] of cases) {
    assert.equal(threadMatchesSourceKinds(row), expected, name);
    assert.equal(threadMatchesSourceKinds(row, []), expected, `${name} empty sourceKinds`);
  }
});

test("explicit agent sourceKinds include live automation and unknown rows", () => {
  const agentKinds = [
    "exec",
    "appServer",
    "subAgentReview",
    "subAgentCompact",
    "subAgentThreadSpawn",
    "subAgentOther",
    "unknown",
  ];

  assert.equal(threadMatchesSourceKinds({ source: "exec" }, agentKinds), true);
  assert.equal(threadMatchesSourceKinds({ source: { exec: {} } }, agentKinds), true);
  assert.equal(threadMatchesSourceKinds({ source: "appServer" }, agentKinds), true);
  assert.equal(threadMatchesSourceKinds({ source: { appServer: {} } }, agentKinds), true);
  assert.equal(threadMatchesSourceKinds({ source: "mcp" }, agentKinds), true);
  assert.equal(threadMatchesSourceKinds({ source: { mcp: {} } }, agentKinds), true);
  assert.equal(threadMatchesSourceKinds({ source: { subAgent: "review" } }, agentKinds), true);
  assert.equal(threadMatchesSourceKinds({ source: "subAgentReview" }, agentKinds), true);
  assert.equal(threadMatchesSourceKinds({ source: { sourceKind: "subAgentCompact" } }, agentKinds), true);
  assert.equal(threadMatchesSourceKinds({ source: { subAgent: "memory_consolidation" } }, agentKinds), false);
  assert.equal(threadMatchesSourceKinds({ source: "unknown" }, agentKinds), true);
  assert.equal(threadMatchesSourceKinds({}, agentKinds), true);
  assert.equal(threadMatchesSourceKinds({ source: "cli" }, agentKinds), false);
  assert.equal(threadMatchesSourceKinds({ source: { custom: "atlas" } }, agentKinds), false);
});

test("contradictory live source metadata maps to unknown", () => {
  const familyConflict = {
    source: {
      cli: {},
      subAgent: "review",
    },
  };
  const variantConflict = {
    source: {
      subAgent: ["review", "compact"],
    },
  };

  assert.equal(threadMatchesSourceKinds(familyConflict), false);
  assert.equal(threadMatchesSourceKinds(familyConflict, ["subAgent"]), false);
  assert.equal(threadMatchesSourceKinds(familyConflict, ["unknown"]), true);

  assert.equal(threadMatchesSourceKinds(variantConflict), false);
  assert.equal(threadMatchesSourceKinds(variantConflict, ["subAgentReview"]), false);
  assert.equal(threadMatchesSourceKinds(variantConflict, ["subAgentCompact"]), false);
  assert.equal(threadMatchesSourceKinds(variantConflict, ["unknown"]), true);
});

test("internal memory live source metadata stays out of filtered scopes", () => {
  const row = { source: "unknown", threadSource: "memory_consolidation" };
  const snakeCaseRow = { source: "unknown", thread_source: "memory_consolidation" };
  const sourceStringRow = { source: "memory_consolidation" };
  const subAgentRow = { source: { subAgent: "memory_consolidation" } };

  assert.equal(threadMatchesSourceKinds(row), false);
  assert.equal(threadMatchesSourceKinds(row, ["subAgent"]), false);
  assert.equal(threadMatchesSourceKinds(row, ["unknown"]), false);
  assert.equal(threadMatchesSourceKinds(snakeCaseRow, ["unknown"]), false);
  assert.equal(threadMatchesSourceKinds(sourceStringRow, ["unknown"]), false);
  assert.equal(threadMatchesSourceKinds(subAgentRow, ["subAgent"]), false);
  assert.equal(threadMatchesSourceKinds(subAgentRow, ["unknown"]), false);
});

test("subAgent sourceKinds match broad and specific live variants", () => {
  const review = { source: { subAgent: "review" } };
  const compact = { source: { subAgent: "compact" } };
  const threadSpawn = {
    source: {
      subAgent: {
        thread_spawn: {
          parent_thread_id: "parent-thread",
          depth: 1,
        },
      },
    },
  };
  const other = { source: { subAgent: { other: "custom-agent" } } };

  assert.equal(threadMatchesSourceKinds(review, ["subAgent"]), true);
  assert.equal(threadMatchesSourceKinds(threadSpawn, ["subAgent"]), true);

  assert.equal(threadMatchesSourceKinds(review, ["subAgentReview"]), true);
  assert.equal(threadMatchesSourceKinds(review, ["subAgentCompact"]), false);
  assert.equal(threadMatchesSourceKinds(compact, ["subAgentCompact"]), true);
  assert.equal(threadMatchesSourceKinds(threadSpawn, ["subAgentThreadSpawn"]), true);
  assert.equal(threadMatchesSourceKinds(other, ["subAgentOther"]), true);
});

test("thread/list live merge applies source filtering before sanitizing results", () => {
  const historyRows = [
    { id: "history-human", source: "cli", updatedAt: 10 },
  ];
  const liveRows = [
    {
      id: "live-human",
      source: { custom: "chatgpt" },
      updatedAt: 30,
      dockRelaySource: { url: "ws://127.0.0.1:4555" },
    },
    {
      id: "live-exec",
      source: "exec",
      updatedAt: 40,
      dockRelaySource: { url: "ws://127.0.0.1:4556" },
    },
    {
      id: "live-subagent",
      source: { subAgent: "review" },
      updatedAt: 50,
      dockRelaySource: { url: "ws://127.0.0.1:4557" },
    },
  ];

  const filteredLiveRows = liveRows.filter((row) => threadMatchesSourceKinds(row));
  const data = mergeThreadListRows(historyRows, filteredLiveRows);

  assert.deepEqual(data.map((row) => row.id), ["live-human", "history-human"]);
  assert.equal(Object.hasOwn(data[0], "dockRelaySource"), false);
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

test("relay thread/list filters discovered live rows by sourceKinds", async () => {
  const liveServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await onceListening(liveServer);
  const liveUrl = `ws://127.0.0.1:${liveServer.address().port}`;
  const liveMarker = spawnLoopbackAppServerMarker(liveUrl);
  const historyServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await onceListening(historyServer);

  liveServer.on("connection", (ws) => {
    ws.on("message", (data) => {
      const message = JSON.parse(data.toString());
      if (message.method === "initialize") {
        ws.send(JSON.stringify({
          id: message.id,
          result: {
            userAgent: "live-test",
            codexHome: "/tmp/codex",
            platformFamily: "unix",
            platformOs: "macos",
          },
        }));
      } else if (message.method === "thread/loaded/list") {
        ws.send(JSON.stringify({
          id: message.id,
          result: { data: ["live-human", "live-exec"], nextCursor: null },
        }));
      } else if (message.method === "thread/read") {
        const thread = message.params.threadId === "live-human"
          ? {
              id: "live-human",
              sessionId: "session-live-human",
              updatedAt: 30,
              source: { custom: "chatgpt" },
              status: { type: "idle" },
            }
          : {
              id: "live-exec",
              sessionId: "session-live-exec",
              updatedAt: 40,
              source: "exec",
              status: { type: "idle" },
            };
        ws.send(JSON.stringify({ id: message.id, result: { thread } }));
      }
    });
  });

  historyServer.on("connection", (ws) => {
    ws.on("message", (data) => {
      const message = JSON.parse(data.toString());
      if (message.method === "initialize") {
        ws.send(JSON.stringify({
          id: message.id,
          result: {
            userAgent: "history-test",
            codexHome: "/tmp/codex",
            platformFamily: "unix",
            platformOs: "macos",
          },
        }));
      } else if (message.method === "thread/list") {
        ws.send(JSON.stringify({
          id: message.id,
          result: { data: [], nextCursor: null, backwardsCursor: null },
        }));
      }
    });
  });

  await sleepMs(20);
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
    const defaultResponse = await jsonRpcRequest(ws, "thread/list");
    const defaultIDs = defaultResponse.result.data.map((row) => row.id);
    assert.equal(defaultIDs.includes("live-human"), true);
    assert.equal(defaultIDs.includes("live-exec"), false);
    assert.equal(
      Object.hasOwn(defaultResponse.result.data.find((row) => row.id === "live-human"), "dockRelaySource"),
      false,
    );

    const execResponse = await jsonRpcRequest(ws, "thread/list", { sourceKinds: ["exec"] });
    const execIDs = execResponse.result.data.map((row) => row.id);
    assert.equal(execIDs.includes("live-exec"), true);
    assert.equal(execIDs.includes("live-human"), false);
  } finally {
    ws.close();
    await relay.close();
    await closeProcess(liveMarker);
    await closeWebSocketServer(liveServer);
    await closeWebSocketServer(historyServer);
  }
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

function spawnLoopbackAppServerMarker(url) {
  return spawn(
    process.execPath,
    [
      "-e",
      "setInterval(() => {}, 1000)",
      "codex",
      "app-server",
      "--listen",
      url,
    ],
    { stdio: "ignore" },
  );
}

function sleepMs(milliseconds) {
  return new Promise((resolve) => {
    setTimeout(resolve, milliseconds);
  });
}

function closeProcess(child) {
  return new Promise((resolve) => {
    if (child.exitCode !== null || child.signalCode !== null) {
      resolve();
      return;
    }
    const timer = setTimeout(resolve, 500);
    child.once("exit", () => {
      clearTimeout(timer);
      resolve();
    });
    child.kill();
  });
}

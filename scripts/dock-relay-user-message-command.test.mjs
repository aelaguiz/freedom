import assert from "node:assert/strict";
import test from "node:test";
import { WebSocketServer } from "ws";

import { startServer } from "./dock-relay.mjs";
import {
  appServerRegistryFixtureConfig,
  closeWebSocketServer,
  jsonRpcRequest,
  onceListening,
  openWebSocket,
} from "./dock-relay-test-helpers.mjs";
import { RelayUserMessageCommandEngine } from "./dock-relay-user-message-command.mjs";

function appServerResponse(id, result) {
  return JSON.stringify({ id, result });
}

function humanThread(id = "thread-a") {
  return {
    id,
    sessionId: `${id}-session`,
    preview: "Human thread",
    createdAt: 1_000,
    updatedAt: 2_000,
    source: "cli",
    status: { type: "running" },
    cwd: "/tmp/codex-client",
    gitInfo: { branch: "main" },
  };
}

async function startUserMessageAppServer() {
  const wss = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  const clients = new Set();
  const turnStartRequests = [];
  await onceListening(wss);
  const address = wss.address();
  const url = `ws://127.0.0.1:${address.port}`;
  const thread = humanThread("thread-a");

  wss.on("connection", (ws) => {
    clients.add(ws);
    ws.on("close", () => clients.delete(ws));
    ws.on("message", (raw) => {
      const message = JSON.parse(raw.toString());
      if (message.method === "initialize") {
        ws.send(appServerResponse(message.id, {
          userAgent: "test-app-server",
          codexHome: "/tmp/codex-client-test",
          platformFamily: "unix",
          platformOs: "macos",
        }));
      } else if (message.method === "thread/read") {
        ws.send(appServerResponse(message.id, { thread }));
      } else if (message.method === "turn/start") {
        turnStartRequests.push(message.params);
        ws.send(appServerResponse(message.id, {
          turn: {
            id: "turn-started",
            status: "inProgress",
          },
        }));
      }
    });
  });

  return {
    url,
    turnStartRequests,
    close: async () => {
      for (const ws of clients) {
        ws.close();
      }
      await closeWebSocketServer(wss);
    },
  };
}

async function withRelay(historyUrl, testFn) {
  const config = {
    listenHost: "127.0.0.1",
    port: 0,
    phoneAuth: "none",
    ...appServerRegistryFixtureConfig({
      historyUrl,
      historyBearerToken: "test-token",
    }),
    advertiseBonjour: false,
    relayStateDatabasePath: ":memory:",
    hostId: "home",
    hostName: "Home",
  };
  const server = startServer(config);
  await server.listening;
  try {
    await testFn({ config, wsURL: `ws://127.0.0.1:${config.port}` });
  } finally {
    await server.close();
  }
}

test("thread/message/send persists an idempotent command and forwards the client message id upstream", async () => {
  const appServer = await startUserMessageAppServer();
  try {
    await withRelay(appServer.url, async ({ wsURL }) => {
      const ws = await openWebSocket(wsURL);
      try {
        const params = {
          threadId: "thread-a",
          clientUserMessageId: "dock-msg:test-1",
          input: [{ type: "text", text: "Run the smoke test", text_elements: [] }],
        };
        const first = await jsonRpcRequest(ws, "thread/message/send", params);
        assert.equal(first.error, undefined);
        assert.equal(first.result.clientUserMessageId, "dock-msg:test-1");
        assert.equal(first.result.state, "submittedUpstream");
        assert.equal(first.result.turnId, "turn-started");
        assert.deepEqual(appServer.turnStartRequests, [{
          threadId: "thread-a",
          clientUserMessageId: "dock-msg:test-1",
          input: [{ type: "text", text: "Run the smoke test", text_elements: [] }],
        }]);

        const duplicate = await jsonRpcRequest(ws, "thread/message/send", {
          threadId: "thread-a",
          clientUserMessageId: "dock-msg:test-1",
          input: [{ text_elements: [], text: "Run the smoke test", type: "text" }],
        });
        assert.equal(duplicate.error, undefined);
        assert.equal(duplicate.result.clientUserMessageId, "dock-msg:test-1");
        assert.equal(duplicate.result.state, "submittedUpstream");
        assert.equal(appServer.turnStartRequests.length, 1);

        const legacy = await jsonRpcRequest(ws, "turn/start", {
          threadId: "thread-a",
          input: [{ type: "text", text: "Legacy path", text_elements: [] }],
        });
        assert.equal(legacy.result, undefined);
        assert.equal(legacy.error?.code, -32602);
        assert.equal(legacy.error?.data?.reason, "missing_client_user_message_id");
        assert.equal(appServer.turnStartRequests.length, 1);
      } finally {
        ws.close();
      }
    });
  } finally {
    await appServer.close();
  }
});

test("user message command falls back from stale active-turn steering to turn/start", async () => {
  const requests = [];
  const config = {
    hostId: "home",
    relayStateDatabasePath: ":memory:",
    logger: { info() {}, warn() {}, error() {}, debug() {} },
    sessionRouter: {
      async rowForThread(threadId) {
        return humanThread(threadId);
      },
      async endpointForThread() {
        throw new Error("stale steering fallback should use the active session");
      },
    },
  };
  const engine = new RelayUserMessageCommandEngine(config);
  const session = {
    endpoint: { url: "ws://active-session" },
    resumeParams: { threadId: "thread-a" },
    acceptedHumanThreadId: "thread-a",
    detailSubscription: {
      ledger: { activeTurnID: "active-turn" },
    },
    upstream: {
      isOpen: () => true,
      async request(method, params) {
        requests.push({ method, params });
        if (method === "turn/steer") {
          throw new Error("expectedTurn mismatch");
        }
        return {
          turn: {
            id: "turn-recovered",
            status: "inProgress",
          },
        };
      },
    },
  };

  try {
    const response = await engine.send({
      threadId: "thread-a",
      clientUserMessageId: "dock-msg:stale-fallback",
      input: [{ type: "text", text: "Continue", text_elements: [] }],
    }, { session });

    assert.equal(response.state, "submittedUpstream");
    assert.equal(response.turnId, "turn-recovered");
    assert.deepEqual(requests.map((request) => request.method), ["turn/steer", "turn/start"]);
    assert.equal(requests[0].params.expectedTurnId, "active-turn");
    assert.equal(requests[1].params.expectedTurnId, undefined);
    assert.equal(requests[1].params.clientUserMessageId, "dock-msg:stale-fallback");
  } finally {
    engine.stateStore.close();
  }
});

test("user message command does not resubmit an in-flight accepted duplicate", async () => {
  const requests = [];
  let releaseFirstRequest;
  let firstRequestStarted;
  const firstRequestStartedPromise = new Promise((resolve) => {
    firstRequestStarted = resolve;
  });
  const releaseFirstRequestPromise = new Promise((resolve) => {
    releaseFirstRequest = resolve;
  });
  const config = {
    hostId: "home",
    relayStateDatabasePath: ":memory:",
    logger: { info() {}, warn() {}, error() {}, debug() {} },
    sessionRouter: {
      async rowForThread(threadId) {
        return humanThread(threadId);
      },
      async endpointForThread() {
        throw new Error("in-flight duplicate test should use the active session");
      },
    },
  };
  const engine = new RelayUserMessageCommandEngine(config);
  const session = {
    endpoint: { url: "ws://active-session" },
    resumeParams: { threadId: "thread-a" },
    acceptedHumanThreadId: "thread-a",
    detailSubscription: {
      ledger: { activeTurnID: null },
    },
    upstream: {
      isOpen: () => true,
      async request(method, params) {
        requests.push({ method, params });
        firstRequestStarted();
        await releaseFirstRequestPromise;
        return {
          turn: {
            id: "turn-in-flight",
            status: "inProgress",
          },
        };
      },
    },
  };
  const params = {
    threadId: "thread-a",
    clientUserMessageId: "dock-msg:in-flight",
    input: [{ type: "text", text: "Continue", text_elements: [] }],
  };

  try {
    const first = engine.send(params, { session });
    await firstRequestStartedPromise;

    const duplicate = await engine.send(params, { session });
    assert.equal(duplicate.state, "acceptedByRelay");
    assert.equal(requests.length, 1);

    releaseFirstRequest();
    const firstResponse = await first;
    assert.equal(firstResponse.state, "submittedUpstream");
    assert.equal(firstResponse.turnId, "turn-in-flight");
    assert.equal(requests.length, 1);
  } finally {
    releaseFirstRequest();
    engine.stateStore.close();
  }
});

import assert from "node:assert/strict";
import test from "node:test";
import { WebSocketServer } from "ws";

import {
  isLoopbackRemoteAddress,
  pendingRequestsForActiveThread,
  startServer,
} from "./dock-relay.mjs";
import { JsonRpcWebSocketClient } from "./dock-relay-json-rpc-client.mjs";
import { UpstreamConnectionPool } from "./dock-relay-upstream-pool.mjs";
import {
  closeProcess,
  closeWebSocketServer,
  httpGetJson,
  jsonRpcRequest,
  onceListening,
  openWebSocket,
  sleepMs,
  spawnLoopbackAppServerMarker,
  waitForRelayMessage,
  waitForWebSocketClose,
} from "./dock-relay-test-helpers.mjs";

test("attention probing resumes without replaying turns", async () => {
  let resumeParams = null;
  const upstreamServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await onceListening(upstreamServer);
  upstreamServer.on("connection", (ws) => {
    ws.on("message", (data) => {
      const message = JSON.parse(data.toString());
      if (message.method === "initialize") {
        ws.send(JSON.stringify({
          id: message.id,
          result: {
            userAgent: "attention-test",
            codexHome: "/tmp/codex",
            platformFamily: "unix",
            platformOs: "macos",
          },
        }));
      } else if (message.method === "thread/resume") {
        resumeParams = message.params;
        ws.send(JSON.stringify({
          id: message.id,
          result: { thread: { id: message.params.threadId } },
        }));
        ws.send(JSON.stringify({
          id: "approval-1",
          method: "item/commandExecution/requestApproval",
          params: { threadId: message.params.threadId },
        }));
      }
    });
  });

  try {
    const requests = await pendingRequestsForActiveThread(
      { url: `ws://127.0.0.1:${upstreamServer.address().port}` },
      "thread-1",
    );

    assert.deepEqual(resumeParams, { threadId: "thread-1", excludeTurns: true });
    assert.equal(requests.length, 1);
    assert.equal(requests[0].method, "item/commandExecution/requestApproval");
  } finally {
    await closeWebSocketServer(upstreamServer);
  }
});

test("relay thread/list ignores discovered live rows and preserves history cursor", async () => {
  const liveServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await onceListening(liveServer);
  const liveUrl = `ws://127.0.0.1:${liveServer.address().port}`;
  const liveMarker = spawnLoopbackAppServerMarker(liveUrl);
  const historyServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await onceListening(historyServer);
  let liveConnections = 0;
  let historyListParams = null;

  liveServer.on("connection", (ws) => {
    liveConnections += 1;
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
        historyListParams = message.params;
        ws.send(JSON.stringify({
          id: message.id,
          result: {
            data: [{
              id: "history-owned",
              preview: "History preview",
              updatedAt: 50,
              source: { custom: "chatgpt" },
              status: { type: "idle" },
            }],
            nextCursor: "cursor-next",
            backwardsCursor: "cursor-back",
          },
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
    threadSummaryCache: {
      decorateRows: (rows) => rows,
      warmRows: () => {},
    },
    advertiseBonjour: false,
  });
  await relay.listening;
  const ws = await openWebSocket(`ws://127.0.0.1:${relay.server.address().port}`);

  try {
    const response = await jsonRpcRequest(ws, "thread/list", { limit: 200, sourceKinds: ["exec"] });
    assert.deepEqual(response.result.data.map((row) => row.id), ["history-owned"]);
    assert.equal(response.result.data[0].preview, "History preview");
    assert.equal(response.result.nextCursor, "cursor-next");
    assert.equal(response.result.backwardsCursor, "cursor-back");
    assert.deepEqual(response.result.liveOverlay, {
      ok: false,
      state: "disabled",
      ageMs: null,
    });
    assert.deepEqual(historyListParams, { limit: 200, sourceKinds: ["exec"] });
    assert.equal(liveConnections, 0);
  } finally {
    ws.close();
    await relay.close();
    await closeProcess(liveMarker);
    await closeWebSocketServer(liveServer);
    await closeWebSocketServer(historyServer);
  }
});

test("relay thread/list keeps history status while focused detail can still route live", async () => {
  const liveServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await onceListening(liveServer);
  const liveUrl = `ws://127.0.0.1:${liveServer.address().port}`;
  const liveMarker = spawnLoopbackAppServerMarker(liveUrl);
  const historyServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await onceListening(historyServer);
  let liveTurnsRequests = 0;
  let historyTurnsRequests = 0;

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
          result: { data: ["currently-active"], nextCursor: null },
        }));
      } else if (message.method === "thread/read") {
        ws.send(JSON.stringify({
          id: message.id,
          result: {
            thread: {
              id: "currently-active",
              sessionId: "session-currently-active",
              updatedAt: 10,
              source: "cli",
              status: {
                type: "active",
                activeFlags: ["waitingOnUserInput"],
              },
            },
          },
        }));
      } else if (message.method === "thread/turns/list") {
        liveTurnsRequests += 1;
        ws.send(JSON.stringify({
          id: message.id,
          result: { data: [{ id: "live-turn" }], nextCursor: null, backwardsCursor: null },
        }));
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
          result: {
            data: [{
              id: "currently-active",
              sessionId: "session-currently-active",
              updatedAt: 300,
              source: "cli",
              status: { type: "notLoaded" },
            }],
            nextCursor: null,
            backwardsCursor: null,
          },
        }));
      } else if (message.method === "thread/turns/list") {
        historyTurnsRequests += 1;
        ws.send(JSON.stringify({
          id: message.id,
          result: { data: [{ id: "history-turn" }], nextCursor: null, backwardsCursor: null },
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
    liveEndpoints: [{ label: "live-test", url: liveUrl }],
    threadSummaryCache: {
      decorateRows: (rows) => rows,
      warmRows: () => {},
    },
    advertiseBonjour: false,
  });
  await relay.listening;
  const ws = await openWebSocket(`ws://127.0.0.1:${relay.server.address().port}`);

  try {
    const response = await jsonRpcRequest(ws, "thread/list");
    const rows = response.result.data.filter((row) => row.id === "currently-active");

    assert.equal(rows.length, 1);
    assert.equal(rows[0].updatedAt, 300);
    assert.equal(rows[0].status.type, "notLoaded");
    assert.equal(Object.hasOwn(rows[0], "dockRelaySource"), false);
    assert.equal(liveTurnsRequests, 0);
    assert.equal(historyTurnsRequests, 0);

    const liveTurnsRequestsBeforeDetail = liveTurnsRequests;
    const turnsResponse = await jsonRpcRequest(ws, "thread/turns/list", { threadId: "currently-active" });
    assert.deepEqual(turnsResponse.result.data, [{ id: "live-turn" }]);
    assert.equal(liveTurnsRequests, liveTurnsRequestsBeforeDetail + 1);
    assert.equal(historyTurnsRequests, 0);
  } finally {
    ws.close();
    await relay.close();
    await closeProcess(liveMarker);
    await closeWebSocketServer(liveServer);
    await closeWebSocketServer(historyServer);
  }
});

test("relay thread/list fails loudly when history fails instead of live fallback", async () => {
  const liveServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await onceListening(liveServer);
  const liveUrl = `ws://127.0.0.1:${liveServer.address().port}`;
  const liveMarker = spawnLoopbackAppServerMarker(liveUrl);
  const historyServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await onceListening(historyServer);
  let liveConnections = 0;

  liveServer.on("connection", (ws) => {
    liveConnections += 1;
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
          result: { data: ["live-survives-history-failure"], nextCursor: null },
        }));
      } else if (message.method === "thread/read") {
        ws.send(JSON.stringify({
          id: message.id,
          result: {
            thread: {
              id: "live-survives-history-failure",
              updatedAt: 30,
              source: { custom: "chatgpt" },
              status: { type: "idle" },
            },
          },
        }));
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
          error: { code: -32000, message: "history unavailable" },
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
    const response = await jsonRpcRequest(ws, "thread/list");
    assert.equal(response.result, undefined);
    assert.equal(response.error.code, -32000);
    assert.match(response.error.message, /history unavailable/);
    assert.deepEqual(response.error.data, {
      subsystem: "history",
      retryable: true,
    });
    assert.equal(liveConnections, 0);
  } finally {
    ws.close();
    await relay.close();
    await closeProcess(liveMarker);
    await closeWebSocketServer(liveServer);
    await closeWebSocketServer(historyServer);
  }
});

test("relay thread/list returns history rows when live endpoint fails", async () => {
  const liveServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await onceListening(liveServer);
  const liveUrl = `ws://127.0.0.1:${liveServer.address().port}`;
  const liveMarker = spawnLoopbackAppServerMarker(liveUrl);
  const historyServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await onceListening(historyServer);
  let liveConnections = 0;

  liveServer.on("connection", (ws) => {
    liveConnections += 1;
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
          error: { code: -32000, message: "live unavailable" },
        }));
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
          result: {
            data: [{
              id: "history-survives-live-failure",
              updatedAt: 10,
              source: { custom: "chatgpt" },
              status: { type: "idle" },
            }],
            nextCursor: null,
            backwardsCursor: null,
          },
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
    const response = await jsonRpcRequest(ws, "thread/list");
    assert.equal(
      response.result.data.some((row) => row.id === "history-survives-live-failure"),
      true,
    );
    assert.deepEqual(response.result.liveOverlay, {
      ok: false,
      state: "disabled",
      ageMs: null,
    });
    assert.equal(liveConnections, 0);
  } finally {
    ws.close();
    await relay.close();
    await closeProcess(liveMarker);
    await closeWebSocketServer(liveServer);
    await closeWebSocketServer(historyServer);
  }
});

test("relay thread/list preserves history preview without warming turns", async () => {
  const historyServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await onceListening(historyServer);
  let turnsParams = null;
  let turnsRequests = 0;
  let allowTurnsResponse = false;
  const pendingTurnsResponses = [];

  function turnsListResult(id) {
    return {
      id,
      result: {
        data: [
          {
            id: "turn-old",
            startedAt: 10,
            items: [{
              id: "old-user",
              type: "userMessage",
              content: [{ text: "Original opening prompt" }],
            }],
          },
          {
            id: "turn-new",
            startedAt: 20,
            items: [
              {
                id: "new-agent",
                type: "agentMessage",
                text: "Latest useful agent update",
              },
              {
                id: "new-command",
                type: "commandExecution",
                command: ["rtk", "npm", "run", "test:relay"],
                aggregatedOutput: "Passed",
              },
              {
                id: "new-reasoning",
                type: "reasoning",
                summary: [{ text: "Internal reasoning should stay out of row summaries" }],
              },
            ],
          },
        ],
        nextCursor: null,
      },
    };
  }

  function flushPendingTurnsResponses() {
    while (pendingTurnsResponses.length > 0) {
      const pending = pendingTurnsResponses.shift();
      pending.ws.send(JSON.stringify(turnsListResult(pending.id)));
    }
  }

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
          result: {
            data: [{
              id: "history-latest",
              sessionId: "session-history-latest",
              preview: "Original opening prompt",
              createdAt: 10,
              updatedAt: 30,
              source: { custom: "chatgpt" },
              status: { type: "idle" },
            }],
            nextCursor: null,
            backwardsCursor: null,
          },
        }));
      } else if (message.method === "thread/turns/list") {
        turnsParams = message.params;
        turnsRequests += 1;
        if (allowTurnsResponse) {
          ws.send(JSON.stringify(turnsListResult(message.id)));
        } else {
          pendingTurnsResponses.push({ ws, id: message.id });
        }
      }
    });
  });

  const relayConfig = {
    listenHost: "127.0.0.1",
    port: 0,
    phoneAuth: "none",
    historyUrl: `ws://127.0.0.1:${historyServer.address().port}`,
    historyBearerToken: "history-token",
    advertiseBonjour: false,
  };
  const relay = startServer(relayConfig);
  await relay.listening;
  const ws = await openWebSocket(`ws://127.0.0.1:${relay.server.address().port}`);

  try {
    const firstResponse = await jsonRpcRequest(ws, "thread/list", { archived: true });
    assert.equal(firstResponse.result.data[0].preview, "Original opening prompt");
    assert.equal(firstResponse.result.data[0].latestSummary, undefined);

    const secondResponse = await jsonRpcRequest(ws, "thread/list", { archived: true });
    assert.equal(secondResponse.result.data[0].preview, "Original opening prompt");
    assert.equal(secondResponse.result.data[0].latestSummary, undefined);
    assert.equal(turnsParams, null);
    assert.equal(turnsRequests, 0);
    assert.equal(pendingTurnsResponses.length, 0);
  } finally {
    ws.close();
    await relay.close();
    await closeWebSocketServer(historyServer);
  }
});

test("relay thread/list preserves history preview without warming live owner turns", async () => {
  const liveServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await onceListening(liveServer);
  const liveUrl = `ws://127.0.0.1:${liveServer.address().port}`;
  const liveMarker = spawnLoopbackAppServerMarker(liveUrl);
  const historyServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await onceListening(historyServer);
  let liveTurnsRequests = 0;
  let historyTurnsRequests = 0;

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
          result: { data: ["live-latest"], nextCursor: null },
        }));
      } else if (message.method === "thread/read") {
        ws.send(JSON.stringify({
          id: message.id,
          result: {
            thread: {
              id: "live-latest",
              sessionId: "session-live-latest",
              preview: "Original opening prompt",
              createdAt: 10,
              updatedAt: 30,
              source: "cli",
              status: { type: "active", activeFlags: [] },
            },
          },
        }));
      } else if (message.method === "thread/turns/list") {
        liveTurnsRequests += 1;
        ws.send(JSON.stringify({
          id: message.id,
          result: {
            data: [
              {
                id: "turn-old",
                startedAt: 10,
                items: [{
                  id: "old-user",
                  type: "userMessage",
                  content: [{ text: "Original opening prompt" }],
                }],
              },
              {
                id: "turn-new",
                startedAt: 30,
                items: [{
                  id: "new-agent",
                  type: "agentMessage",
                  text: "Live owner latest agent update",
                }],
              },
            ],
            nextCursor: null,
          },
        }));
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
          result: {
            data: [{
              id: "live-latest",
              sessionId: "session-live-latest",
              preview: "Original opening prompt",
              createdAt: 10,
              updatedAt: 30,
              source: "cli",
              status: { type: "active", activeFlags: [] },
            }],
            nextCursor: null,
            backwardsCursor: null,
          },
        }));
      } else if (message.method === "thread/turns/list") {
        historyTurnsRequests += 1;
        ws.send(JSON.stringify({
          id: message.id,
          result: {
            data: [{
              id: "history-turn",
              startedAt: 30,
              items: [{
                id: "history-agent",
                type: "agentMessage",
                text: "Stale history update",
              }],
            }],
            nextCursor: null,
          },
        }));
      }
    });
  });

  await sleepMs(20);
  const relayConfig = {
    listenHost: "127.0.0.1",
    port: 0,
    phoneAuth: "none",
    historyUrl: `ws://127.0.0.1:${historyServer.address().port}`,
    historyBearerToken: "history-token",
    liveEndpoints: [{ label: "live-test", url: liveUrl }],
    advertiseBonjour: false,
  };
  const relay = startServer(relayConfig);
  await relay.listening;
  const ws = await openWebSocket(`ws://127.0.0.1:${relay.server.address().port}`);

  try {
    const firstResponse = await jsonRpcRequest(ws, "thread/list");
    assert.equal(firstResponse.result.data[0].preview, "Original opening prompt");
    assert.equal(firstResponse.result.data[0].latestSummary, undefined);

    const secondResponse = await jsonRpcRequest(ws, "thread/list");
    assert.equal(secondResponse.result.data[0].preview, "Original opening prompt");
    assert.equal(secondResponse.result.data[0].latestSummary, undefined);
    assert.equal(liveTurnsRequests, 0);
    assert.equal(historyTurnsRequests, 0);
  } finally {
    ws.close();
    await relay.close();
    await closeProcess(liveMarker);
    await closeWebSocketServer(liveServer);
    await closeWebSocketServer(historyServer);
  }
});

test("thread/turns/list routes to the thread owning upstream", async () => {
  const liveServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await onceListening(liveServer);
  const liveUrl = `ws://127.0.0.1:${liveServer.address().port}`;
  const liveMarker = spawnLoopbackAppServerMarker(liveUrl);
  const historyServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await onceListening(historyServer);
  let liveTurnsRequests = 0;
  let historyTurnsRequests = 0;

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
          result: { data: ["live-owner"], nextCursor: null },
        }));
      } else if (message.method === "thread/read") {
        ws.send(JSON.stringify({
          id: message.id,
          result: {
            thread: {
              id: "live-owner",
              updatedAt: 30,
              source: { custom: "chatgpt" },
              status: { type: "idle" },
            },
          },
        }));
      } else if (message.method === "thread/turns/list") {
        liveTurnsRequests += 1;
        ws.send(JSON.stringify({
          id: message.id,
          result: { data: [{ id: "live-turn" }], nextCursor: null },
        }));
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
      } else if (message.method === "thread/turns/list") {
        historyTurnsRequests += 1;
        ws.send(JSON.stringify({
          id: message.id,
          result: { data: [{ id: "history-turn" }], nextCursor: null },
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
    liveEndpoints: [{ label: "live-test", url: liveUrl }],
    advertiseBonjour: false,
  });
  await relay.listening;
  const ws = await openWebSocket(`ws://127.0.0.1:${relay.server.address().port}`);

  try {
    const liveResponse = await jsonRpcRequest(ws, "thread/turns/list", { threadId: "live-owner" });
    assert.deepEqual(liveResponse.result.data, [{ id: "live-turn" }]);
    const historyResponse = await jsonRpcRequest(ws, "thread/turns/list", { threadId: "history-owner" });
    assert.deepEqual(historyResponse.result.data, [{ id: "history-turn" }]);
    assert.equal(liveTurnsRequests, 1);
    assert.equal(historyTurnsRequests, 1);
  } finally {
    ws.close();
    await relay.close();
    await closeProcess(liveMarker);
    await closeWebSocketServer(liveServer);
    await closeWebSocketServer(historyServer);
  }
});

test("thread/goal/get routes to the thread owning upstream", async () => {
  const liveServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await onceListening(liveServer);
  const liveUrl = `ws://127.0.0.1:${liveServer.address().port}`;
  const liveMarker = spawnLoopbackAppServerMarker(liveUrl);
  const historyServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await onceListening(historyServer);
  let liveGoalRequests = 0;
  let historyGoalRequests = 0;

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
          result: { data: ["live-owner"], nextCursor: null },
        }));
      } else if (message.method === "thread/read") {
        ws.send(JSON.stringify({
          id: message.id,
          result: {
            thread: {
              id: "live-owner",
              updatedAt: 30,
              source: { custom: "chatgpt" },
              status: { type: "idle" },
            },
          },
        }));
      } else if (message.method === "thread/goal/get") {
        liveGoalRequests += 1;
        ws.send(JSON.stringify({
          id: message.id,
          result: {
            goal: {
              threadId: message.params.threadId,
              objective: "Live goal",
              status: "in_progress",
              tokenBudget: null,
              tokensUsed: 1,
              timeUsedSeconds: 2,
              createdAt: 3,
              updatedAt: 4,
            },
          },
        }));
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
      } else if (message.method === "thread/goal/get") {
        historyGoalRequests += 1;
        ws.send(JSON.stringify({
          id: message.id,
          result: {
            goal: {
              threadId: message.params.threadId,
              objective: "History goal",
              status: "paused",
              tokenBudget: 100,
              tokensUsed: 10,
              timeUsedSeconds: 20,
              createdAt: 30,
              updatedAt: 40,
            },
          },
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
    liveEndpoints: [{ label: "live-test", url: liveUrl }],
    advertiseBonjour: false,
  });
  await relay.listening;
  const ws = await openWebSocket(`ws://127.0.0.1:${relay.server.address().port}`);

  try {
    const liveResponse = await jsonRpcRequest(ws, "thread/goal/get", { threadId: "live-owner" });
    assert.equal(liveResponse.result.goal.objective, "Live goal");
    const historyResponse = await jsonRpcRequest(ws, "thread/goal/get", { threadId: "history-owner" });
    assert.equal(historyResponse.result.goal.objective, "History goal");
    assert.equal(liveGoalRequests, 1);
    assert.equal(historyGoalRequests, 1);
  } finally {
    ws.close();
    await relay.close();
    await closeProcess(liveMarker);
    await closeWebSocketServer(liveServer);
    await closeWebSocketServer(historyServer);
  }
});

test("thread/resume forwards upstream notifications requests and phone responses", async () => {
  const threadId = "thread-forward-phase5";
  let forwardedResponse = null;
  let upstreamResumeParams = null;
  const forwardedResponsePromise = new Promise((resolve) => {
    forwardedResponse = resolve;
  });
  const historyServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await onceListening(historyServer);
  historyServer.on("connection", (upstreamWs) => {
    upstreamWs.on("message", (data) => {
      const message = JSON.parse(data.toString());
      if (message.method === "initialize") {
        upstreamWs.send(JSON.stringify({
          id: message.id,
          result: {
            userAgent: "history-test",
            codexHome: "/tmp/codex",
            platformFamily: "unix",
            platformOs: "macos",
          },
        }));
      } else if (message.method === "thread/resume") {
        upstreamResumeParams = message.params;
        upstreamWs.send(JSON.stringify({
          id: message.id,
          result: { thread: { id: message.params.threadId } },
        }));
        setTimeout(() => {
          upstreamWs.send(JSON.stringify({
            method: "thread/status/changed",
            params: { threadId: message.params.threadId },
          }));
          upstreamWs.send(JSON.stringify({
            id: "approval-1",
            method: "item/commandExecution/requestApproval",
            params: { threadId: message.params.threadId },
          }));
        }, 10);
      } else if (!message.method && message.id === "approval-1") {
        forwardedResponse(message);
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
    const notificationPromise = waitForRelayMessage(
      ws,
      (message) => message.method === "thread/status/changed",
    );
    const requestPromise = waitForRelayMessage(
      ws,
      (message) => message.method === "item/commandExecution/requestApproval",
    );
    const resume = await jsonRpcRequest(ws, "thread/resume", { threadId });
    assert.equal(resume.result.thread.id, threadId);
    assert.deepEqual(upstreamResumeParams, { threadId, excludeTurns: true });
    const notification = await notificationPromise;
    assert.equal(notification.params.threadId, threadId);
    const request = await requestPromise;
    assert.equal(request.id, "approval-1");

    ws.send(JSON.stringify({ id: "approval-1", result: { decision: "approved" } }));
    assert.deepEqual(await forwardedResponsePromise, {
      id: "approval-1",
      result: { decision: "approved" },
    });
  } finally {
    ws.close();
    await relay.close();
    await closeWebSocketServer(historyServer);
  }
});

test("turn/start rejects requests for a thread different from the resumed session", async () => {
  const resumedThreadId = "thread-bound-phase6";
  let turnStartCalls = 0;
  const historyServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await onceListening(historyServer);
  historyServer.on("connection", (upstreamWs) => {
    upstreamWs.on("message", (data) => {
      const message = JSON.parse(data.toString());
      if (message.method === "initialize") {
        upstreamWs.send(JSON.stringify({
          id: message.id,
          result: {
            userAgent: "history-test",
            codexHome: "/tmp/codex",
            platformFamily: "unix",
            platformOs: "macos",
          },
        }));
      } else if (message.method === "thread/resume") {
        upstreamWs.send(JSON.stringify({
          id: message.id,
          result: { thread: { id: message.params.threadId } },
        }));
      } else if (message.method === "turn/start") {
        turnStartCalls += 1;
        upstreamWs.send(JSON.stringify({
          id: message.id,
          result: { turn: { id: "wrong-turn" } },
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
    const resume = await jsonRpcRequest(ws, "thread/resume", { threadId: resumedThreadId });
    assert.equal(resume.result.thread.id, resumedThreadId);

    const response = await jsonRpcRequest(ws, "turn/start", {
      threadId: "thread-other-phase6",
      input: [{ type: "text", text: "redacted", text_elements: [] }],
    });

    assert.equal(response.error.code, -32602);
    assert.equal(response.error.data.reason, "thread_mismatch");
    assert.equal(response.error.data.requestedThreadIDHash.length, 12);
    assert.equal(response.error.data.activeThreadIDHash.length, 12);
    await sleepMs(25);
    assert.equal(turnStartCalls, 0);
  } finally {
    ws.close();
    await relay.close();
    await closeWebSocketServer(historyServer);
  }
});

test("thread/resume refuses to bind an upstream that returns the wrong thread", async () => {
  const requestedThreadId = "thread-requested-phase6";
  let turnStartCalls = 0;
  const historyServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await onceListening(historyServer);
  historyServer.on("connection", (upstreamWs) => {
    upstreamWs.on("message", (data) => {
      const message = JSON.parse(data.toString());
      if (message.method === "initialize") {
        upstreamWs.send(JSON.stringify({
          id: message.id,
          result: {
            userAgent: "history-test",
            codexHome: "/tmp/codex",
            platformFamily: "unix",
            platformOs: "macos",
          },
        }));
      } else if (message.method === "thread/resume") {
        upstreamWs.send(JSON.stringify({
          id: message.id,
          result: { thread: { id: "thread-actual-wrong-phase6" } },
        }));
      } else if (message.method === "turn/start") {
        turnStartCalls += 1;
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
    const resume = await jsonRpcRequest(ws, "thread/resume", { threadId: requestedThreadId });
    assert.equal(resume.error.code, -32000);
    assert.equal(resume.error.data.reason, "resume_thread_mismatch");

    const turn = await jsonRpcRequest(ws, "turn/start", {
      threadId: requestedThreadId,
      input: [{ type: "text", text: "redacted", text_elements: [] }],
    });
    assert.match(turn.error.message, /requires thread\/resume/);
    await sleepMs(25);
    assert.equal(turnStartCalls, 0);
  } finally {
    ws.close();
    await relay.close();
    await closeWebSocketServer(historyServer);
  }
});

test("phone responses are rejected after their upstream request is made stale by a newer resume", async () => {
  const oldThreadId = "thread-old-request-phase6";
  const newThreadId = "thread-new-request-phase6";
  let forwardedResponses = 0;
  const historyServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await onceListening(historyServer);
  historyServer.on("connection", (upstreamWs) => {
    upstreamWs.on("message", (data) => {
      const message = JSON.parse(data.toString());
      if (message.method === "initialize") {
        upstreamWs.send(JSON.stringify({
          id: message.id,
          result: {
            userAgent: "history-test",
            codexHome: "/tmp/codex",
            platformFamily: "unix",
            platformOs: "macos",
          },
        }));
      } else if (message.method === "thread/resume") {
        upstreamWs.send(JSON.stringify({
          id: message.id,
          result: { thread: { id: message.params.threadId } },
        }));
        if (message.params.threadId === oldThreadId) {
          setTimeout(() => {
            upstreamWs.send(JSON.stringify({
              id: "approval-stale-phase6",
              method: "item/commandExecution/requestApproval",
              params: { threadId: oldThreadId },
            }));
          }, 10);
        }
      } else if (!message.method && message.id === "approval-stale-phase6") {
        forwardedResponses += 1;
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
    const oldRequestPromise = waitForRelayMessage(
      ws,
      (message) => message.method === "item/commandExecution/requestApproval"
        && message.id === "approval-stale-phase6",
    );
    const oldResume = await jsonRpcRequest(ws, "thread/resume", { threadId: oldThreadId });
    assert.equal(oldResume.result.thread.id, oldThreadId);
    await oldRequestPromise;

    const newResume = await jsonRpcRequest(ws, "thread/resume", { threadId: newThreadId });
    assert.equal(newResume.result.thread.id, newThreadId);

    const rejectedResponsePromise = waitForRelayMessage(
      ws,
      (message) => message.id === "approval-stale-phase6" && message.error,
    );
    ws.send(JSON.stringify({
      id: "approval-stale-phase6",
      result: { decision: "approved" },
    }));
    const rejected = await rejectedResponsePromise;

    assert.equal(rejected.error.message, "no matching active upstream request");
    await sleepMs(25);
    assert.equal(forwardedResponses, 0);
  } finally {
    ws.close();
    await relay.close();
    await closeWebSocketServer(historyServer);
  }
});

test("phone responses are rejected after their upstream request is made stale by recovery", async () => {
  const threadId = "thread-recovered-request-phase6";
  let connectionCount = 0;
  let forwardedResponses = 0;
  const historyServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await onceListening(historyServer);
  historyServer.on("connection", (upstreamWs) => {
    connectionCount += 1;
    const connectionNumber = connectionCount;
    upstreamWs.on("message", (data) => {
      const message = JSON.parse(data.toString());
      if (message.method === "initialize") {
        upstreamWs.send(JSON.stringify({
          id: message.id,
          result: {
            userAgent: "history-test",
            codexHome: "/tmp/codex",
            platformFamily: "unix",
            platformOs: "macos",
          },
        }));
      } else if (message.method === "thread/resume") {
        upstreamWs.send(JSON.stringify({
          id: message.id,
          result: { thread: { id: message.params.threadId } },
        }));
        if (connectionNumber === 1) {
          setTimeout(() => {
            upstreamWs.send(JSON.stringify({
              id: "approval-recovery-phase6",
              method: "item/commandExecution/requestApproval",
              params: { threadId },
            }));
          }, 10);
          setTimeout(() => upstreamWs.close(), 25);
        } else {
          setTimeout(() => {
            upstreamWs.send(JSON.stringify({
              method: "thread/status/changed",
              params: { threadId },
            }));
          }, 10);
        }
      } else if (!message.method && message.id === "approval-recovery-phase6") {
        forwardedResponses += 1;
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
    const oldRequestPromise = waitForRelayMessage(
      ws,
      (message) => message.method === "item/commandExecution/requestApproval"
        && message.id === "approval-recovery-phase6",
    );
    const recoveredNotificationPromise = waitForRelayMessage(
      ws,
      (message) => message.method === "thread/status/changed"
        && message.params.threadId === threadId,
    );

    const resume = await jsonRpcRequest(ws, "thread/resume", { threadId });
    assert.equal(resume.result.thread.id, threadId);
    await oldRequestPromise;
    await recoveredNotificationPromise;

    const rejectedResponsePromise = waitForRelayMessage(
      ws,
      (message) => message.id === "approval-recovery-phase6" && message.error,
    );
    ws.send(JSON.stringify({
      id: "approval-recovery-phase6",
      result: { decision: "approved" },
    }));
    const rejected = await rejectedResponsePromise;

    assert.equal(rejected.error.message, "no matching active upstream request");
    await sleepMs(25);
    assert.equal(forwardedResponses, 0);
    assert.equal(connectionCount, 2);
  } finally {
    ws.close();
    await relay.close();
    await closeWebSocketServer(historyServer);
  }
});

test("thread/resume abandons initial upstream if downstream closes before resume completes", async () => {
  const threadId = "thread-initial-resume-close";
  let activeUpstream = null;
  let resumeRequestID = null;
  let resolveResumeSeen = null;
  let resolveUpstreamClosed = null;
  const resumeSeen = new Promise((resolve) => {
    resolveResumeSeen = resolve;
  });
  const upstreamClosed = new Promise((resolve) => {
    resolveUpstreamClosed = resolve;
  });
  const historyServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await onceListening(historyServer);
  historyServer.on("connection", (upstreamWs) => {
    activeUpstream = upstreamWs;
    upstreamWs.once("close", () => {
      resolveUpstreamClosed();
    });
    upstreamWs.on("message", (data) => {
      const message = JSON.parse(data.toString());
      if (message.method === "initialize") {
        upstreamWs.send(JSON.stringify({
          id: message.id,
          result: {
            userAgent: "history-test",
            codexHome: "/tmp/codex",
            platformFamily: "unix",
            platformOs: "macos",
          },
        }));
      } else if (message.method === "thread/resume") {
        resumeRequestID = message.id;
        resolveResumeSeen();
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
    ws.send(JSON.stringify({
      id: "resume-close-test",
      method: "thread/resume",
      params: { threadId, excludeTurns: true },
    }));
    await resumeSeen;
    ws.close();
    await waitForWebSocketClose(ws);
    activeUpstream.send(JSON.stringify({
      id: resumeRequestID,
      result: { thread: { id: threadId } },
    }));

    const closed = await Promise.race([
      upstreamClosed.then(() => true),
      sleepMs(500).then(() => false),
    ]);
    assert.equal(closed, true);
  } finally {
    ws.close();
    activeUpstream?.close();
    await relay.close();
    await closeWebSocketServer(historyServer);
  }
});

test("relay recovers upstream close by re-resuming and forwarding live updates", async () => {
  const threadId = "thread-recover-phase5";
  let connectionCount = 0;
  const resumeParams = [];
  const historyServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await onceListening(historyServer);
  historyServer.on("connection", (upstreamWs) => {
    connectionCount += 1;
    const connectionNumber = connectionCount;
    upstreamWs.on("message", (data) => {
      const message = JSON.parse(data.toString());
      if (message.method === "initialize") {
        upstreamWs.send(JSON.stringify({
          id: message.id,
          result: {
            userAgent: "history-test",
            codexHome: "/tmp/codex",
            platformFamily: "unix",
            platformOs: "macos",
          },
        }));
      } else if (message.method === "thread/resume") {
        resumeParams.push(message.params);
        upstreamWs.send(JSON.stringify({
          id: message.id,
          result: { thread: { id: message.params.threadId } },
        }));
        if (connectionNumber === 1) {
          setTimeout(() => upstreamWs.close(), 10);
        } else {
          setTimeout(() => {
            upstreamWs.send(JSON.stringify({
              method: "thread/status/changed",
              params: { threadId: message.params.threadId },
            }));
          }, 10);
        }
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
    const resume = await jsonRpcRequest(ws, "thread/resume", { threadId });
    assert.equal(resume.result.thread.id, threadId);
    const notification = await waitForRelayMessage(
      ws,
      (message) => message.method === "thread/status/changed",
    );
    assert.equal(notification.params.threadId, threadId);
    assert.equal(connectionCount, 2);
    assert.deepEqual(resumeParams, [
      { threadId, excludeTurns: true },
      { threadId, excludeTurns: true },
    ]);
  } finally {
    ws.close();
    await relay.close();
    await closeWebSocketServer(historyServer);
  }
});

test("relay recovery refuses to bind an upstream that resumes the wrong thread", async () => {
  const threadId = "thread-recovery-requested-phase6";
  let connectionCount = 0;
  const historyServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await onceListening(historyServer);
  historyServer.on("connection", (upstreamWs) => {
    connectionCount += 1;
    const connectionNumber = connectionCount;
    upstreamWs.on("message", (data) => {
      const message = JSON.parse(data.toString());
      if (message.method === "initialize") {
        upstreamWs.send(JSON.stringify({
          id: message.id,
          result: {
            userAgent: "history-test",
            codexHome: "/tmp/codex",
            platformFamily: "unix",
            platformOs: "macos",
          },
        }));
      } else if (message.method === "thread/resume" && connectionNumber === 1) {
        upstreamWs.send(JSON.stringify({
          id: message.id,
          result: { thread: { id: threadId } },
        }));
        setTimeout(() => upstreamWs.close(), 10);
      } else if (message.method === "thread/resume") {
        upstreamWs.send(JSON.stringify({
          id: message.id,
          result: { thread: { id: "thread-recovery-wrong-phase6" } },
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
    const resume = await jsonRpcRequest(ws, "thread/resume", { threadId, excludeTurns: true });
    assert.equal(resume.result.thread.id, threadId);
    const close = await waitForWebSocketClose(ws);
    assert.equal(close.code, 1011);
    assert.equal(connectionCount, 3);
  } finally {
    ws.close();
    await relay.close();
    await closeWebSocketServer(historyServer);
  }
});

test("relay ignores stale upstream recovery after a newer resume", async () => {
  const oldThreadId = "thread-stale-recovery-old";
  const newThreadId = "thread-stale-recovery-new";
  let connectionCount = 0;
  let staleRecovery = null;
  const historyServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await onceListening(historyServer);
  historyServer.on("connection", (upstreamWs) => {
    connectionCount += 1;
    const connectionNumber = connectionCount;
    upstreamWs.on("message", (data) => {
      const message = JSON.parse(data.toString());
      if (message.method === "initialize") {
        upstreamWs.send(JSON.stringify({
          id: message.id,
          result: {
            userAgent: "history-test",
            codexHome: "/tmp/codex",
            platformFamily: "unix",
            platformOs: "macos",
          },
        }));
      } else if (message.method === "thread/resume" && message.params.threadId === oldThreadId) {
        if (connectionNumber === 1) {
          upstreamWs.send(JSON.stringify({
            id: message.id,
            result: { thread: { id: oldThreadId } },
          }));
          setTimeout(() => upstreamWs.close(), 10);
        } else {
          staleRecovery = { upstreamWs, requestID: message.id };
        }
      } else if (message.method === "thread/resume" && message.params.threadId === newThreadId) {
        upstreamWs.send(JSON.stringify({
          id: message.id,
          result: { thread: { id: newThreadId } },
        }));
        setTimeout(() => {
          upstreamWs.send(JSON.stringify({
            method: "thread/status/changed",
            params: { threadId: newThreadId },
          }));
        }, 10);
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
    const oldResume = await jsonRpcRequest(ws, "thread/resume", { threadId: oldThreadId, excludeTurns: true });
    assert.equal(oldResume.result.thread.id, oldThreadId);
    for (let attempt = 0; attempt < 20 && !staleRecovery; attempt += 1) {
      await sleepMs(10);
    }
    assert.notEqual(staleRecovery, null);

    const newNotificationPromise = waitForRelayMessage(
      ws,
      (message) => message.method === "thread/status/changed"
        && message.params.threadId === newThreadId,
    );
    const newResume = await jsonRpcRequest(ws, "thread/resume", { threadId: newThreadId, excludeTurns: true });
    assert.equal(newResume.result.thread.id, newThreadId);

    let staleForwarded = false;
    ws.on("message", function onMessage(data) {
      const message = JSON.parse(data.toString());
      if (message.method === "thread/status/changed" && message.params.threadId === oldThreadId) {
        staleForwarded = true;
      }
    });

    staleRecovery.upstreamWs.send(JSON.stringify({
      id: staleRecovery.requestID,
      result: { thread: { id: oldThreadId } },
    }));
    setTimeout(() => {
      staleRecovery.upstreamWs.send(JSON.stringify({
        method: "thread/status/changed",
        params: { threadId: oldThreadId },
      }));
    }, 20);

    const notification = await newNotificationPromise;
    assert.equal(notification.params.threadId, newThreadId);
    await sleepMs(100);
    assert.equal(staleForwarded, false);
  } finally {
    ws.close();
    await relay.close();
    await closeWebSocketServer(historyServer);
  }
});

test("relay closes downstream when upstream recovery is exhausted", async () => {
  const threadId = "thread-recovery-fails-phase5";
  let connectionCount = 0;
  const historyServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await onceListening(historyServer);
  historyServer.on("connection", (upstreamWs) => {
    connectionCount += 1;
    const connectionNumber = connectionCount;
    upstreamWs.on("message", (data) => {
      const message = JSON.parse(data.toString());
      if (message.method === "initialize") {
        upstreamWs.send(JSON.stringify({
          id: message.id,
          result: {
            userAgent: "history-test",
            codexHome: "/tmp/codex",
            platformFamily: "unix",
            platformOs: "macos",
          },
        }));
      } else if (message.method === "thread/resume" && connectionNumber === 1) {
        upstreamWs.send(JSON.stringify({
          id: message.id,
          result: { thread: { id: message.params.threadId } },
        }));
        setTimeout(() => upstreamWs.close(), 10);
      } else if (message.method === "thread/resume") {
        upstreamWs.close();
      }
    });
    if (connectionNumber > 1) {
      setTimeout(() => upstreamWs.close(), 10);
    }
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
    const resume = await jsonRpcRequest(ws, "thread/resume", { threadId, excludeTurns: true });
    assert.equal(resume.result.thread.id, threadId);
    const close = await waitForWebSocketClose(ws);
    assert.equal(close.code, 1011);
    assert.equal(connectionCount, 3);
  } finally {
    ws.close();
    await relay.close();
    await closeWebSocketServer(historyServer);
  }
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

test("relay records malformed downstream messages as client-facing errors", async () => {
  const relay = startServer({
    listenHost: "127.0.0.1",
    port: 0,
    phoneAuth: "none",
    historyUrl: "ws://127.0.0.1:1",
    historyBearerToken: "history-token",
    advertiseBonjour: false,
  });
  await relay.listening;
  const baseURL = `http://127.0.0.1:${relay.server.address().port}`;
  const ws = await openWebSocket(`ws://127.0.0.1:${relay.server.address().port}`);

  try {
    const errorPromise = waitForRelayMessage(
      ws,
      (message) => message.error?.code === -32700,
    );
    ws.send("{bad-json");
    const response = await errorPromise;
    assert.equal(response.id, null);
    assert.equal(response.error.message, "parse error");

    const status = await httpGetJson(`${baseURL}/statusz`);
    assert.equal(status.errors.lastClientFacingError.subsystem, "downstream");
    assert.equal(status.errors.lastClientFacingError.code, -32700);
    assert.equal(status.errors.lastClientFacingError.retryable, false);
  } finally {
    ws.close();
    await relay.close();
  }
});

test("relay health endpoints report configured phone auth mode", async () => {
  const relay = startServer({
    listenHost: "127.0.0.1",
    port: 0,
    phoneAuth: "bearer",
    relayBearerToken: "phone-token",
    historyUrl: "ws://127.0.0.1:1",
    historyBearerToken: "history-token",
    advertiseBonjour: false,
  });
  await relay.listening;
  const baseURL = `http://127.0.0.1:${relay.server.address().port}`;

  try {
    assert.deepEqual(await httpGetJson(`${baseURL}/readyz`), {
      ok: true,
      service: "codex-dock-relay",
      auth: "bearer",
    });
    assert.deepEqual(await httpGetJson(`${baseURL}/healthz`), {
      ok: true,
      service: "codex-dock-relay",
      auth: "bearer",
      routeHealth: false,
      staticConfig: {
        ok: true,
        historyConfigured: true,
        transcriptionConfigured: true,
      },
    });
  } finally {
    await relay.close();
  }
});

test("upstream client rejects pending requests promptly when socket closes", async () => {
  const upstreamServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await onceListening(upstreamServer);
  upstreamServer.on("connection", (upstreamWs) => {
    upstreamWs.on("message", (data) => {
      const message = JSON.parse(data.toString());
      if (message.method === "slow/method") {
        upstreamWs.close(1011, "closing pending request");
      }
    });
  });

  const client = new JsonRpcWebSocketClient(
    `ws://127.0.0.1:${upstreamServer.address().port}`,
    { timeoutMs: 10_000 },
  );

  try {
    await client.connect();
    const startedAt = Date.now();
    await assert.rejects(
      () => client.request("slow/method", {}),
      /websocket closed/,
    );
    assert.equal(Date.now() - startedAt < 500, true);
  } finally {
    client.close();
    await closeWebSocketServer(upstreamServer);
  }
});

test("upstream pool reuses one multiplexed history socket", async () => {
  const upstreamServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await onceListening(upstreamServer);
  let connections = 0;
  upstreamServer.on("connection", (upstreamWs) => {
    connections += 1;
    upstreamWs.on("message", (data) => {
      const message = JSON.parse(data.toString());
      upstreamWs.send(JSON.stringify({
        id: message.id,
        result: { method: message.method },
      }));
    });
  });

  const pool = new UpstreamConnectionPool({ maxOpenByLabel: { history: 1 } });
  const endpoint = {
    label: "history",
    url: `ws://127.0.0.1:${upstreamServer.address().port}`,
  };

  try {
    assert.deepEqual(await pool.request(endpoint, "first"), { method: "first" });
    assert.deepEqual(await pool.request(endpoint, "second"), { method: "second" });
    assert.equal(connections, 1);
    assert.equal(pool.stats()[0].open, 1);
  } finally {
    await pool.closeAll();
    await closeWebSocketServer(upstreamServer);
  }
});

test("upstream pool enforces max-open per label", async () => {
  const firstServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  const secondServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await onceListening(firstServer);
  await onceListening(secondServer);
  const pool = new UpstreamConnectionPool({ maxOpenByLabel: { history: 1 } });

  try {
    await pool.clientFor({
      label: "history",
      url: `ws://127.0.0.1:${firstServer.address().port}`,
    });
    await assert.rejects(
      () => pool.clientFor({
        label: "history",
        url: `ws://127.0.0.1:${secondServer.address().port}`,
      }),
      /upstream pool history exhausted: 1\/1/,
    );
  } finally {
    await pool.closeAll();
    await closeWebSocketServer(firstServer);
    await closeWebSocketServer(secondServer);
  }
});

test("upstream pool removes timed-out sockets", async () => {
  const upstreamServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await onceListening(upstreamServer);
  upstreamServer.on("connection", () => {});
  const pool = new UpstreamConnectionPool({ maxOpenByLabel: { history: 1 } });
  const endpoint = {
    label: "history",
    url: `ws://127.0.0.1:${upstreamServer.address().port}`,
  };

  try {
    await assert.rejects(
      () => pool.request(endpoint, "slow", {}, { timeoutMs: 20 }),
      /timed out waiting for slow/,
    );
    assert.deepEqual(pool.stats(), []);
  } finally {
    await pool.closeAll();
    await closeWebSocketServer(upstreamServer);
  }
});

test("relay statusz reports redacted service state and realtime config", async () => {
  const relay = startServer({
    listenHost: "127.0.0.1",
    port: 0,
    hostId: "home",
    hostName: "Home",
    phoneAuth: "bearer",
    relayBearerToken: "phone-token",
    historyUrl: "ws://user:pass@127.0.0.1:1/path?token=history-token",
    historyBearerToken: "history-token",
    openAIAPIKey: "sk-status-secret-secret-secret-secret",
    openAIRealtimeTranscriptionModel: "gpt-realtime-whisper",
    openAIRealtimeTranscriptionEndpoint: "wss://api.openai.com/v1/realtime?intent=transcription&api_key=secret",
    advertiseBonjour: false,
  });
  await relay.listening;
  const baseURL = `http://127.0.0.1:${relay.server.address().port}`;

  try {
    const status = await httpGetJson(`${baseURL}/statusz`);
    const statusText = JSON.stringify(status);

    assert.equal(status.ok, true);
    assert.equal(status.service, "codex-dock-relay");
    assert.equal(status.host.id, "home");
    assert.equal(status.host.relayInstanceID, "home");
    assert.equal(status.host.displayName, "Home");
    assert.equal(status.auth.phoneAuth, "bearer");
    assert.equal(status.auth.relayCredentialConfigured, true);
    assert.equal(status.auth.historyCredentialConfigured, true);
    assert.equal(status.history.url, "ws://127.0.0.1:1/path");
    assert.equal(status.history.lastHealth.status, "down");
    assert.equal(status.transcription.enabled, true);
    assert.equal(status.transcription.model, "gpt-realtime-whisper");
    assert.equal(status.transcription.endpointHost, "api.openai.com");
    assert.equal(status.transcription.keyPresent, true);
    assert.equal("language" in status.transcription, false);
    assert.equal("delay" in status.transcription, false);
    assert.equal(status.connections.downstreamActive, 0);
    assert.equal(status.connections.upstreamActive, 0);
    assert.equal(statusText.includes("phone-token"), false);
    assert.equal(statusText.includes("history-token"), false);
    assert.equal(statusText.includes("sk-status-secret"), false);
    assert.equal(statusText.includes("user:pass"), false);
    assert.equal(statusText.includes("api_key=secret"), false);
  } finally {
    await relay.close();
  }
});

test("relay metricsz and debugz sessions expose loopback-safe diagnostics", async () => {
  const relay = startServer({
    listenHost: "127.0.0.1",
    port: 0,
    hostId: "home",
    hostName: "Home",
    phoneAuth: "none",
    historyUrl: "ws://127.0.0.1:1",
    historyBearerToken: "history-token",
    advertiseBonjour: false,
  });
  await relay.listening;
  const baseURL = `http://127.0.0.1:${relay.server.address().port}`;
  const ws = await openWebSocket(`ws://127.0.0.1:${relay.server.address().port}`);

  try {
    const status = await httpGetJson(`${baseURL}/statusz`);
    const metrics = await httpGetJson(`${baseURL}/metricsz`);
    const debug = await httpGetJson(`${baseURL}/debugz/sessions`);
    const combined = JSON.stringify({ status, metrics, debug });

    assert.equal(status.liveStatus.status, "unknown");
    assert.equal(status.liveStatus.overlayState, "disabled");
    assert.equal(metrics.ok, true);
    assert.equal(metrics.host.relayInstanceID, "home");
    assert.equal(debug.host.relayInstanceID, "home");
    assert.equal(metrics.connections.downstreamActive, 1);
    assert.equal(Array.isArray(metrics.connections.upstreamPools), true);
    assert.equal(Array.isArray(metrics.requests.byMethod), true);
    assert.equal(debug.ok, true);
    assert.equal(debug.sessions.length, 1);
    assert.equal("threadId" in debug.sessions[0], false);
    assert.equal("threadIDHash" in debug.sessions[0], true);
    assert.equal(Array.isArray(debug.liveRows), true);
    assert.equal(combined.includes("history-token"), false);
    assert.equal(combined.includes("Bearer"), false);
  } finally {
    ws.close();
    await relay.close();
  }
});

test("relay loopback classifier is available for diagnostics that need address labels", () => {
  assert.equal(isLoopbackRemoteAddress("127.0.0.1"), true);
  assert.equal(isLoopbackRemoteAddress("::1"), true);
  assert.equal(isLoopbackRemoteAddress("::ffff:127.0.0.1"), true);
  assert.equal(isLoopbackRemoteAddress("192.168.50.74"), false);
  assert.equal(isLoopbackRemoteAddress("100.64.0.2"), false);
});

test("relay raw history failure returns subsystem error data and records status", async () => {
  const relay = startServer({
    listenHost: "127.0.0.1",
    port: 0,
    phoneAuth: "none",
    historyUrl: "ws://127.0.0.1:1",
    historyBearerToken: "history-token",
    advertiseBonjour: false,
  });
  await relay.listening;
  const baseURL = `http://127.0.0.1:${relay.server.address().port}`;
  const ws = await openWebSocket(`ws://127.0.0.1:${relay.server.address().port}`);

  try {
    const response = await jsonRpcRequest(ws, "thread/read", { threadId: "missing-history-thread" });
    assert.equal(response.result, undefined);
    assert.equal(response.error.code, -32000);
    assert.deepEqual(response.error.data, {
      subsystem: "history",
      retryable: true,
    });

    const status = await httpGetJson(`${baseURL}/statusz`);
    assert.equal(status.history.lastHealth.status, "down");
    assert.equal(status.errors.lastClientFacingError.subsystem, "history");
    assert.equal(status.errors.lastClientFacingError.retryable, true);
  } finally {
    ws.close();
    await relay.close();
  }
});

test("relay preserves upstream overload code and marks it retryable", async () => {
  const historyServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await onceListening(historyServer);
  historyServer.on("connection", (upstreamWs) => {
    upstreamWs.on("message", (data) => {
      const message = JSON.parse(data.toString());
      if (message.method === "initialize") {
        upstreamWs.send(JSON.stringify({
          id: message.id,
          result: {
            userAgent: "overload-test",
            codexHome: "/tmp/codex",
            platformFamily: "unix",
            platformOs: "macos",
          },
        }));
      } else if (message.method === "thread/read") {
        upstreamWs.send(JSON.stringify({
          id: message.id,
          error: {
            code: -32001,
            message: "app-server overloaded",
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
  const baseURL = `http://127.0.0.1:${relay.server.address().port}`;
  const ws = await openWebSocket(`ws://127.0.0.1:${relay.server.address().port}`);

  try {
    const response = await jsonRpcRequest(ws, "thread/read", { threadId: "overloaded-thread" });
    assert.equal(response.result, undefined);
    assert.equal(response.error.code, -32001);
    assert.match(response.error.message, /app-server overloaded/);
    assert.deepEqual(response.error.data, {
      subsystem: "upstream-overload",
      retryable: true,
      overload: true,
    });

    const status = await httpGetJson(`${baseURL}/statusz`);
    assert.equal(status.errors.lastClientFacingError.code, -32001);
    assert.equal(status.errors.lastClientFacingError.subsystem, "upstream-overload");
    assert.equal(status.errors.lastClientFacingError.retryable, true);
  } finally {
    ws.close();
    await relay.close();
    await closeWebSocketServer(historyServer);
  }
});

test("relay transcription failures are status-visible without leaking secrets", async () => {
  const relay = startServer({
    listenHost: "127.0.0.1",
    port: 0,
    phoneAuth: "none",
    historyUrl: "ws://127.0.0.1:1",
    historyBearerToken: "history-token",
    openAIRealtimeTranscriptionModel: "gpt-realtime-whisper",
    advertiseBonjour: false,
  });
  await relay.listening;
  const baseURL = `http://127.0.0.1:${relay.server.address().port}`;
  const ws = await openWebSocket(`ws://127.0.0.1:${relay.server.address().port}`);

  try {
    const response = await jsonRpcRequest(ws, "audio/transcription/start", {});
    assert.equal(response.result, undefined);
    assert.equal(response.error.code, -32000);
    assert.deepEqual(response.error.data, {
      subsystem: "transcription",
      retryable: true,
    });

    const status = await httpGetJson(`${baseURL}/statusz`);
    const text = JSON.stringify(status);
    assert.equal(status.transcription.enabled, false);
    assert.equal(status.transcription.keyPresent, false);
    assert.equal(status.transcription.lastError.subsystem, "transcription");
    assert.equal(status.errors.lastClientFacingError.subsystem, "transcription");
    assert.equal(status.connections.downstreamActive, 1);
    assert.equal(text.includes("base64Audio"), false);
    assert.equal(text.includes("private transcript"), false);
    assert.equal(text.includes("OPENAI_API_KEY"), false);
  } finally {
    ws.close();
    await relay.close();
  }
});

test("relay bearer phone mode rejects missing or bad authorization", async () => {
  const relay = startServer({
    listenHost: "127.0.0.1",
    port: 0,
    phoneAuth: "bearer",
    relayBearerToken: "phone-token",
    historyUrl: "ws://127.0.0.1:1",
    historyBearerToken: "history-token",
    advertiseBonjour: false,
  });
  await relay.listening;
  const url = `ws://127.0.0.1:${relay.server.address().port}`;

  try {
    await assert.rejects(() => openWebSocket(url), /401/);
    await assert.rejects(
      () => openWebSocket(url, { headers: { Authorization: "Bearer wrong" } }),
      /401/,
    );
    const ws = await openWebSocket(url, { headers: { Authorization: "Bearer phone-token" } });
    ws.close();
  } finally {
    await relay.close();
  }
});

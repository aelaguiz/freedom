import assert from "node:assert/strict";
import test from "node:test";
import { WebSocketServer } from "ws";

import { startServer } from "./dock-relay.mjs";
import {
  closeWebSocketServer,
  jsonRpcRequest,
  onceListening,
  openWebSocket,
  waitForWebSocketClose,
} from "./dock-relay-test-helpers.mjs";

function appServerResponse(id, result) {
  return JSON.stringify({ id, result });
}

function appServerError(id, code, message) {
  return JSON.stringify({ id, error: { code, message } });
}

async function startRecoverableThreadAppServer() {
  const wss = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  const clients = new Set();
  let resumeCount = 0;
  await onceListening(wss);
  const address = wss.address();
  const url = `ws://127.0.0.1:${address.port}`;
  const thread = {
    id: "thread-a",
    sessionId: "session-a",
    preview: "Recoverable thread",
    createdAt: 1_000,
    updatedAt: 2_000,
    source: "cli",
    status: { type: "running" },
    cwd: "/tmp/codex-client",
    gitInfo: { branch: "main" },
  };

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
      } else if (message.method === "thread/turns/list") {
        ws.send(appServerResponse(message.id, {
          data: [],
          nextCursor: null,
          backwardsCursor: null,
        }));
      } else if (message.method === "thread/resume") {
        resumeCount += 1;
        ws.send(appServerResponse(message.id, { thread }));
        if (resumeCount === 1) {
          setTimeout(() => ws.close(1011, "controlled upstream drop"), 0);
        }
      }
    });
  });

  return {
    url,
    get resumeCount() {
      return resumeCount;
    },
    close: async () => {
      for (const ws of clients) {
        ws.close();
      }
      await closeWebSocketServer(wss);
    },
  };
}

async function startArchivedThreadAppServer() {
  const wss = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  const clients = new Set();
  let resumeCount = 0;
  await onceListening(wss);
  const address = wss.address();
  const url = `ws://127.0.0.1:${address.port}`;
  const thread = {
    id: "thread-archived",
    sessionId: "session-archived",
    preview: "Archived thread",
    name: "Archived thread",
    createdAt: 1_000,
    updatedAt: 2_000,
    source: "cli",
    status: { type: "idle" },
    cwd: "/tmp/codex-client",
    gitInfo: { branch: "main" },
    path: "/tmp/codex-client/archived_sessions/thread-archived.jsonl",
  };

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
      } else if (message.method === "thread/list") {
        ws.send(appServerResponse(message.id, {
          data: message.params?.archived === true ? [thread] : [],
          nextCursor: null,
          backwardsCursor: null,
        }));
      } else if (message.method === "thread/read") {
        ws.send(appServerResponse(message.id, { thread }));
      } else if (message.method === "thread/turns/list") {
        ws.send(appServerResponse(message.id, {
          data: [],
          nextCursor: null,
          backwardsCursor: null,
        }));
      } else if (message.method === "thread/resume") {
        resumeCount += 1;
        ws.send(appServerError(message.id, -32000, "archived session cannot resume"));
      }
    });
  });

  return {
    url,
    get resumeCount() {
      return resumeCount;
    },
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
    historyBearerToken: "test-token",
    historyUrl,
    liveEndpoints: [],
    advertiseBonjour: false,
    relayStateDatabasePath: ":memory:",
    hostId: "home",
    hostName: "Home",
    codexHome: "/tmp/codex-client-test",
  };
  const server = startServer(config);
  await server.listening;
  try {
    await testFn({ config, wsURL: `ws://127.0.0.1:${config.port}` });
  } finally {
    await server.close();
  }
}

test("archived detail projection opens without upstream thread/resume", async () => {
  const appServer = await startArchivedThreadAppServer();
  try {
    await withRelay(appServer.url, async ({ config, wsURL }) => {
      await config.relayStateEngine.reconcileArchive({ reason: "test" });
      const ws = await openWebSocket(wsURL);
      try {
        const archive = await jsonRpcRequest(ws, "archive/subscribe", { offset: 0, limit: 10 });
        assert.equal(archive.error, undefined);
        assert.equal(archive.result?.rows?.[0]?.threadID, "thread-archived");
        assert.equal(archive.result?.rows?.[0]?.archiveState, "archived");

        const detail = await jsonRpcRequest(ws, "thread/detail/subscribe", { threadId: "thread-archived" });
        assert.equal(detail.error, undefined);
        assert.equal(detail.result?.threadID, "thread-archived");
        assert.equal(detail.result?.view, "thread.detail");
        assert.equal(appServer.resumeCount, 0);
      } finally {
        ws.close();
      }
    });
  } finally {
    await appServer.close();
  }
});

test("successful live detail upstream recovery closes downstream so the app rehydrates", async () => {
  const appServer = await startRecoverableThreadAppServer();
  try {
    await withRelay(appServer.url, async ({ wsURL }) => {
      const ws = await openWebSocket(wsURL);
      try {
        const response = await jsonRpcRequest(ws, "thread/detail/subscribe", { threadId: "thread-a" });
        assert.equal(response.error, undefined);
        assert.equal(response.result?.threadID, "thread-a");
        const close = await waitForWebSocketClose(ws);
        assert.equal(close.code, 1012);
        assert.equal(close.reason, "upstream recovered; rehydrate");
        assert.equal(appServer.resumeCount, 2);
      } finally {
        ws.close();
      }
    });
  } finally {
    await appServer.close();
  }
});

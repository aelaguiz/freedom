import assert from "node:assert/strict";
import test from "node:test";
import { WebSocketServer } from "ws";

import { startServer } from "./dock-relay.mjs";
import {
  closeWebSocketServer,
  jsonRpcRequest,
  onceListening,
  openWebSocket,
} from "./dock-relay-test-helpers.mjs";

function appServerResponse(id, result) {
  return JSON.stringify({ id, result });
}

async function startCanonicalActivityAppServer({
  failTurnsFor = new Set(),
  loadedThreadIDs = [],
  listUpdatedAt = {},
  readUpdatedAt = {},
} = {}) {
  const wss = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  const clients = new Set();
  await onceListening(wss);
  const address = wss.address();
  const url = `ws://127.0.0.1:${address.port}`;
  const rows = {
    older: {
      id: "older",
      sessionId: "older-session",
      preview: "Older list row",
      createdAt: 1_000,
      updatedAt: listUpdatedAt.older ?? 1_000,
      source: "cli",
      status: { type: "idle" },
      cwd: "/tmp/codex-client",
      gitInfo: { branch: "main" },
    },
    newer: {
      id: "newer",
      sessionId: "newer-session",
      preview: "Newer turn row",
      createdAt: 900,
      updatedAt: listUpdatedAt.newer ?? 900,
      source: "cli",
      status: { type: "idle" },
      cwd: "/tmp/codex-client",
      gitInfo: { branch: "main" },
    },
    "live-only": {
      id: "live-only",
      sessionId: "live-only-session",
      preview: "Live-only row",
      createdAt: 700,
      updatedAt: listUpdatedAt["live-only"] ?? 700,
      source: "cli",
      status: { type: "running" },
      cwd: "/tmp/codex-client",
      gitInfo: { branch: "main" },
    },
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
          data: [rows.older, rows.newer],
          nextCursor: null,
        }));
      } else if (message.method === "thread/loaded/list") {
        ws.send(appServerResponse(message.id, { data: loadedThreadIDs }));
      } else if (message.method === "thread/read") {
        const thread = { ...rows[message.params?.threadId] };
        if (readUpdatedAt[message.params?.threadId] !== undefined) {
          thread.updatedAt = readUpdatedAt[message.params.threadId];
        }
        ws.send(appServerResponse(message.id, { thread }));
      } else if (message.method === "thread/turns/list") {
        if (failTurnsFor.has(message.params?.threadId)) {
          ws.send(JSON.stringify({
            id: message.id,
            error: { code: -32000, message: "turn proof unavailable" },
          }));
          return;
        }
        const startedAt = {
          newer: 3_000,
          older: 2_000,
          "live-only": 5_000,
        }[message.params?.threadId] ?? 1_000;
        ws.send(appServerResponse(message.id, {
          data: [{ id: `${message.params?.threadId}-turn`, startedAt }],
          nextCursor: null,
        }));
      }
    });
  });
  return {
    url,
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

test("dock/subscribe orders cards by proven newest turn activity, not raw thread/list order", async () => {
  const appServer = await startCanonicalActivityAppServer();
  try {
    await withRelay(appServer.url, async ({ config, wsURL }) => {
      await config.relayStateEngine.reconcileDock({ reason: "test" });
      const ws = await openWebSocket(wsURL);
      try {
        const response = await jsonRpcRequest(ws, "dock/subscribe", { offset: 0, limit: 10 });
        assert.equal(response.error, undefined);
        assert.equal(response.result.complete, true);
        assert.equal(response.result.freshness.status, "fresh");
        assert.deepEqual(response.result.cards.map((card) => card.threadID), ["newer", "older"]);
        assert.ok(response.result.cards.every((card) => card.completeness === "complete"));
        assert.ok(response.result.cards.every((card) => card.freshness === "fresh"));
      } finally {
        ws.close();
      }
    });
  } finally {
    await appServer.close();
  }
});

test("dock/subscribe includes live-only rows absent from raw thread/list", async () => {
  const appServer = await startCanonicalActivityAppServer({ loadedThreadIDs: ["live-only"] });
  try {
    await withRelay(appServer.url, async ({ config, wsURL }) => {
      await config.relayStateEngine.reconcileDock({ reason: "test" });
      const ws = await openWebSocket(wsURL);
      try {
        const response = await jsonRpcRequest(ws, "dock/subscribe", { offset: 0, limit: 10 });
        assert.equal(response.error, undefined);
        assert.equal(response.result.complete, true);
        assert.equal(response.result.freshness.status, "fresh");
        assert.deepEqual(response.result.cards.map((card) => card.threadID), [
          "live-only",
          "newer",
          "older",
        ]);
        const liveOnly = response.result.cards.find((card) => card.threadID === "live-only");
        assert.equal(liveOnly?.completeness, "complete");
        assert.equal(liveOnly?.freshness, "fresh");
      } finally {
        ws.close();
      }
    });
  } finally {
    await appServer.close();
  }
});

test("stale thread/read cannot downgrade list activity when turn proof fails", async () => {
  const appServer = await startCanonicalActivityAppServer({
    failTurnsFor: new Set(["newer"]),
    listUpdatedAt: { newer: 4_000 },
    readUpdatedAt: { newer: 500 },
  });
  try {
    await withRelay(appServer.url, async ({ config, wsURL }) => {
      await config.relayStateEngine.reconcileDock({ reason: "test" });
      const ws = await openWebSocket(wsURL);
      try {
        const response = await jsonRpcRequest(ws, "dock/subscribe", { offset: 0, limit: 10 });
        assert.equal(response.error, undefined);
        assert.equal(response.result.complete, false);
        assert.deepEqual(response.result.cards.map((card) => card.threadID), ["newer", "older"]);
        const newer = response.result.cards.find((card) => card.threadID === "newer");
        // Relay card truth is always canonical milliseconds, even when the
        // upstream fixture uses second-shaped app-server timestamps.
        assert.equal(newer?.activityAtMs, 4_000_000_000);
        assert.equal(newer?.freshness, "stale");
        assert.equal(newer?.completeness, "partial");
      } finally {
        ws.close();
      }
    });
  } finally {
    await appServer.close();
  }
});

test("dock/subscribe marks cards partial and stream stale when newest-turn proof fails", async () => {
  const appServer = await startCanonicalActivityAppServer({ failTurnsFor: new Set(["newer"]) });
  try {
    await withRelay(appServer.url, async ({ config, wsURL }) => {
      await config.relayStateEngine.reconcileDock({ reason: "test" });
      const ws = await openWebSocket(wsURL);
      try {
        const response = await jsonRpcRequest(ws, "dock/subscribe", { offset: 0, limit: 10 });
        assert.equal(response.error, undefined);
        assert.equal(response.result.complete, false);
        assert.equal(response.result.freshness.status, "stale");
        const newer = response.result.cards.find((card) => card.threadID === "newer");
        assert.equal(newer?.freshness, "stale");
        assert.equal(newer?.completeness, "partial");
        assert.equal(typeof newer?.activityAtMs, "number");
      } finally {
        ws.close();
      }
    });
  } finally {
    await appServer.close();
  }
});

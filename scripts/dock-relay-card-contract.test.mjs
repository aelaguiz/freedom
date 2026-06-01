import assert from "node:assert/strict";
import test from "node:test";
import { WebSocketServer } from "ws";

import { startServer } from "./dock-relay.mjs";
import {
  closeWebSocketServer,
  jsonRpcRequest,
  onceListening,
  openWebSocket,
  waitForRelayMessage,
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

async function withRelay(historyUrl, testFn, overrides = {}) {
  const config = {
    listenHost: "127.0.0.1",
    port: 0,
    phoneAuth: "none",
    historyBearerToken: "test-token",
    historyUrl,
    liveEndpoints: overrides.liveEndpoints || [],
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

test("dock/subscribe marks stream stale when a live source refresh fails", async () => {
  const appServer = await startCanonicalActivityAppServer();
  try {
    await withRelay(
      appServer.url,
      async ({ config, wsURL }) => {
        await config.relayStateEngine.reconcileDock({ reason: "test" });
        const ws = await openWebSocket(wsURL);
        try {
          const response = await jsonRpcRequest(ws, "dock/subscribe", { offset: 0, limit: 10 });
          assert.equal(response.error, undefined);
          assert.equal(response.result.complete, false);
          assert.equal(response.result.freshness.status, "stale");
          assert.match(response.result.freshness.lastError || "", /live loaded session refresh failed/u);
          assert.deepEqual(response.result.cards.map((card) => card.threadID), ["newer", "older"]);
        } finally {
          ws.close();
        }
      },
      { liveEndpoints: [{ label: "missing-live", url: "ws://127.0.0.1:1/" }] },
    );
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

test("dock/update replacement delta is complete when it carries every current row", async () => {
  let sourceRows = [{
    id: "cached",
    sessionId: "cached-session",
    preview: "Cached row",
    createdAt: 100,
    updatedAt: 100,
    source: "cli",
    status: { type: "idle" },
    cwd: "/tmp/codex-client",
    gitInfo: { branch: "main" },
  }];
  const appServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  const clients = new Set();
  await onceListening(appServer);
  appServer.on("connection", (ws) => {
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
        ws.send(appServerResponse(message.id, { data: sourceRows, nextCursor: null }));
      } else if (message.method === "thread/loaded/list") {
        ws.send(appServerResponse(message.id, { data: [] }));
      } else if (message.method === "thread/read") {
        const row = sourceRows.find((candidate) => candidate.id === message.params?.threadId);
        ws.send(appServerResponse(message.id, { thread: { ...row, turns: [] } }));
      } else if (message.method === "thread/turns/list") {
        const row = sourceRows.find((candidate) => candidate.id === message.params?.threadId);
        ws.send(appServerResponse(message.id, {
          data: row ? [{ id: `${row.id}-turn`, startedAt: row.updatedAt }] : [],
          nextCursor: null,
        }));
      }
    });
  });

  try {
    await withRelay(`ws://127.0.0.1:${appServer.address().port}`, async ({ config, wsURL }) => {
      await config.relayStateEngine.reconcileDock({ reason: "test-initial" });
      const ws = await openWebSocket(wsURL);
      try {
        const initial = await jsonRpcRequest(ws, "dock/subscribe", { offset: 0, limit: 10 });
        assert.equal(initial.error, undefined);
        assert.equal(initial.result.complete, true);
        assert.deepEqual(initial.result.cards.map((card) => card.threadID), ["cached"]);

        const initialDockSeq = initial.result.seq;
        const archiveOnly = config.relayStateEngine.store.applyArchiveReconciliation({
          host: { id: "home", displayName: "Home", endpoint: null },
          cards: [],
          complete: true,
        });
        assert.ok(archiveOnly.seq > initialDockSeq);
        assert.equal(config.relayStateEngine.store.currentSeq(), archiveOnly.seq);
        assert.equal(config.relayStateEngine.store.currentSeqForView("dock"), initialDockSeq);

        sourceRows = [{
          id: "recovered",
          sessionId: "recovered-session",
          preview: "Recovered row",
          createdAt: 200,
          updatedAt: 200,
          source: "cli",
          status: { type: "idle" },
          cwd: "/tmp/codex-client",
          gitInfo: { branch: "main" },
        }];
        const updatePromise = waitForRelayMessage(ws, (message) => (
          message.method === "dock/update"
          && message.params?.kind === "delta"
          && (message.params?.upsertCards || []).some((card) => card.threadID === "recovered")
        ));
        await config.relayStateEngine.reconcileDock({ reason: "test-recovered" });
        const update = await updatePromise;

        assert.equal(update.params.baseSeq, initialDockSeq);
        assert.ok(update.params.seq > archiveOnly.seq);
        assert.equal(update.params.complete, true);
        assert.equal(update.params.totalRows, 1);
        assert.deepEqual(update.params.upsertCards.map((card) => card.threadID), ["recovered"]);
        assert.deepEqual(update.params.deleteCardIDs, ["home::cached"]);
      } finally {
        ws.close();
      }
    });
  } finally {
    for (const ws of clients) {
      ws.close();
    }
    await closeWebSocketServer(appServer);
  }
});

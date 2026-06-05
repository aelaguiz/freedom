import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { WebSocketServer } from "ws";

import { startServer } from "./dock-relay.mjs";
import {
  appServerRegistryFixtureConfig,
  closeWebSocketServer,
  jsonRpcRequest,
  onceListening,
  openWebSocket,
  sleepMs,
  waitForRelayMessage,
} from "./dock-relay-test-helpers.mjs";

function appServerResponse(id, result) {
  return JSON.stringify({ id, result });
}

function appServerNotification(method, params) {
  return JSON.stringify({
    jsonrpc: "2.0",
    method,
    params,
  });
}

async function startCanonicalActivityAppServer({
  emitRenameNotifications = false,
  failReadsFor = new Set(),
  failTurnsFor = new Set(),
  loadedThreadIDs = [],
  listUpdatedAt = {},
  omitReadSourceFor = new Set(),
  readSourceFor = {},
  readUpdatedAt = {},
} = {}) {
  const wss = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  const clients = new Set();
  const initializedClients = new Set();
  const resumedClients = new Set();
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
  const readSourceOverrides = { ...readSourceFor };
  const renameRequests = [];
  const renameThreadLocally = (threadId, name) => {
    const thread = rows[threadId];
    if (!thread) {
      throw new Error(`missing fake thread: ${threadId}`);
    }
    thread.name = name;
    thread.updatedAt = Math.max(Number(thread.updatedAt || 0), 4_000);
  };
  const emitThreadNameUpdated = (threadId, threadName, { resumedOnly = false } = {}) => {
    const targets = resumedOnly ? resumedClients : initializedClients;
    let sent = 0;
    for (const ws of targets) {
      if (ws.readyState !== 1) {
        continue;
      }
      ws.send(appServerNotification("thread/name/updated", { threadId, threadName }));
      sent += 1;
    }
    return sent;
  };
  const setThreadStatusLocally = (threadId, status) => {
    const thread = rows[threadId];
    if (!thread) {
      throw new Error(`missing fake thread: ${threadId}`);
    }
    thread.status = status;
    thread.updatedAt = Math.max(Number(thread.updatedAt || 0), 4_100);
  };
  const emitThreadStatusChanged = (threadId, status, { resumedOnly = false } = {}) => {
    const targets = resumedOnly ? resumedClients : initializedClients;
    let sent = 0;
    for (const ws of targets) {
      if (ws.readyState !== 1) {
        continue;
      }
      ws.send(appServerNotification("thread/status/changed", { threadId, status }));
      sent += 1;
    }
    return sent;
  };
  wss.on("connection", (ws) => {
    clients.add(ws);
    ws.on("close", () => {
      clients.delete(ws);
      initializedClients.delete(ws);
      resumedClients.delete(ws);
    });
    ws.on("message", (raw) => {
      const message = JSON.parse(raw.toString());
      if (message.method === "initialize") {
        ws.send(appServerResponse(message.id, {
          userAgent: "test-app-server",
          codexHome: "/tmp/codex-client-test",
          platformFamily: "unix",
          platformOs: "macos",
        }));
      } else if (message.method === "initialized") {
        initializedClients.add(ws);
      } else if (message.method === "thread/list") {
        ws.send(appServerResponse(message.id, {
          data: [rows.older, rows.newer],
          nextCursor: null,
        }));
      } else if (message.method === "thread/loaded/list") {
        ws.send(appServerResponse(message.id, { data: loadedThreadIDs }));
      } else if (message.method === "thread/read") {
        if (failReadsFor.has(message.params?.threadId)) {
          ws.send(JSON.stringify({
            id: message.id,
            error: { code: -32000, message: "thread read unavailable" },
          }));
          return;
        }
        const thread = { ...rows[message.params?.threadId] };
        if (readUpdatedAt[message.params?.threadId] !== undefined) {
          thread.updatedAt = readUpdatedAt[message.params.threadId];
        }
        if (Object.hasOwn(readSourceOverrides, message.params?.threadId)) {
          thread.source = readSourceOverrides[message.params.threadId];
        }
        if (omitReadSourceFor.has(message.params?.threadId)) {
          delete thread.source;
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
      } else if (message.method === "thread/resume") {
        const thread = rows[message.params?.threadId];
        if (!thread) {
          ws.send(JSON.stringify({
            id: message.id,
            error: { code: -32602, message: "thread not found" },
          }));
          return;
        }
        resumedClients.add(ws);
        ws.send(appServerResponse(message.id, { thread }));
      } else if (message.method === "thread/name/set") {
        const thread = rows[message.params?.threadId];
        if (!thread) {
          ws.send(JSON.stringify({
            id: message.id,
            error: { code: -32602, message: "thread not found" },
          }));
          return;
        }
        renameRequests.push({
          threadId: message.params.threadId,
          name: message.params.name,
        });
        renameThreadLocally(message.params.threadId, message.params.name);
        ws.send(appServerResponse(message.id, {}));
        if (emitRenameNotifications) {
          setTimeout(() => {
            emitThreadNameUpdated(message.params.threadId, message.params.name);
          }, 0);
        }
      }
    });
  });
  return {
    url,
    renameRequests,
    emitThreadNameUpdated,
    emitThreadStatusChanged,
    renameThreadLocally,
    setReadSourceFor: (threadId, source) => {
      readSourceOverrides[threadId] = source;
    },
    setThreadStatusLocally,
    get initializedClientCount() {
      return initializedClients.size;
    },
    get resumedClientCount() {
      return resumedClients.size;
    },
    close: async () => {
      for (const ws of clients) {
        ws.close();
      }
      await closeWebSocketServer(wss);
    },
  };
}

async function withRelay(historyUrl, testFn, overrides = {}) {
  const {
    liveEndpoints = [],
    ...restOverrides
  } = overrides;
  const config = {
    listenHost: "127.0.0.1",
    port: 0,
    phoneAuth: "none",
    ...appServerRegistryFixtureConfig({
      historyUrl,
      historyBearerToken: "test-token",
      liveEndpoints,
    }),
    advertiseBonjour: false,
    relayStateDatabasePath: ":memory:",
    hostId: "home",
    hostName: "Home",
    ...restOverrides,
  };
  const server = startServer(config);
  await server.listening;
  try {
    await testFn({ config, wsURL: `ws://127.0.0.1:${config.port}` });
  } finally {
    await server.close();
  }
}

function writeSessionMeta(codexHome, {
  id,
  cwd = "/tmp/codex-client",
  source = "cli",
  git = { branch: "main", repository_url: "git@example.test:repo/example.git" },
} = {}) {
  const dir = path.join(codexHome, "sessions", "2026", "06", "05");
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(
    path.join(dir, `rollout-2026-06-05T12-00-00-${id}.jsonl`),
    `${JSON.stringify({
      type: "session_meta",
      timestamp: "2026-06-05T12:00:00.000Z",
      payload: {
        id,
        cwd,
        source,
        git,
      },
    })}\n`,
    "utf8",
  );
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
        assert.deepEqual(response.result.rows.map((card) => card.threadID), ["newer", "older"]);
        assert.ok(response.result.rows.every((card) => card.completeness === "complete"));
        assert.ok(response.result.rows.every((card) => card.freshness === "fresh"));
      } finally {
        ws.close();
      }
    });
  } finally {
    await appServer.close();
  }
});

test("dock/subscribe rejects live rows when rollout metadata says they are spawned subagents", async () => {
  const codexHome = fs.mkdtempSync(path.join(os.tmpdir(), "codex-dock-session-meta-"));
  writeSessionMeta(codexHome, {
    id: "live-only",
    cwd: "/tmp/codex-client/subagent-workspace",
    source: {
      subagent: {
        thread_spawn: {
          parent_thread_id: "parent-thread",
          depth: 1,
          agent_nickname: "Arendt",
          agent_role: "explorer",
        },
      },
    },
    git: {
      branch: "subagent-branch",
      repository_url: "git@example.test:repo/subagent.git",
    },
  });
  const appServer = await startCanonicalActivityAppServer({
    loadedThreadIDs: ["live-only"],
  });
  try {
    await withRelay(appServer.url, async ({ config, wsURL }) => {
      await config.relayStateEngine.reconcileDock({ reason: "test-subagent-session-meta" });
      const ws = await openWebSocket(wsURL);
      try {
        const response = await jsonRpcRequest(ws, "dock/subscribe", { offset: 0, limit: 10 });
        assert.equal(response.error, undefined);
        assert.equal(response.result.complete, true);
        assert.deepEqual(response.result.rows.map((card) => card.threadID), ["newer", "older"]);
        assert.equal(response.result.rows.some((card) => card.threadID === "live-only"), false);
      } finally {
        ws.close();
      }
    }, { codexHome });
  } finally {
    await appServer.close();
    fs.rmSync(codexHome, { recursive: true, force: true });
  }
});

test("dock/subscribe rejects history rows when rollout metadata says they are spawned subagents", async () => {
  const codexHome = fs.mkdtempSync(path.join(os.tmpdir(), "codex-dock-history-session-meta-"));
  writeSessionMeta(codexHome, {
    id: "newer",
    cwd: "/tmp/codex-client/subagent-workspace",
    source: {
      subagent: {
        thread_spawn: {
          parent_thread_id: "parent-thread",
          depth: 1,
          agent_nickname: "Mendel",
          agent_role: "explorer",
        },
      },
    },
    git: {
      branch: "subagent-branch",
      repository_url: "git@example.test:repo/subagent.git",
    },
  });
  const appServer = await startCanonicalActivityAppServer();
  try {
    await withRelay(appServer.url, async ({ config, wsURL }) => {
      await config.relayStateEngine.reconcileDock({ reason: "test-history-subagent-session-meta" });
      const ws = await openWebSocket(wsURL);
      try {
        const response = await jsonRpcRequest(ws, "dock/subscribe", { offset: 0, limit: 10 });
        assert.equal(response.error, undefined);
        assert.equal(response.result.complete, true);
        assert.deepEqual(response.result.rows.map((card) => card.threadID), ["older"]);
        assert.equal(response.result.rows.some((card) => card.threadID === "newer"), false);
      } finally {
        ws.close();
      }
    }, { codexHome });
  } finally {
    await appServer.close();
    fs.rmSync(codexHome, { recursive: true, force: true });
  }
});

test("failed optional session-index supplements do not make dock snapshot partial", async () => {
  const codexHome = fs.mkdtempSync(path.join(os.tmpdir(), "codex-dock-session-index-"));
  fs.writeFileSync(
    path.join(codexHome, "session_index.jsonl"),
    `${JSON.stringify({
      id: "missing-supplement",
      thread_name: "Missing supplement",
      updated_at: "2026-06-05T12:00:00.000Z",
    })}\n`,
    "utf8",
  );
  const appServer = await startCanonicalActivityAppServer({
    failReadsFor: new Set(["missing-supplement"]),
  });
  try {
    await withRelay(appServer.url, async ({ config, wsURL }) => {
      await config.relayStateEngine.reconcileDock({ reason: "test" });
      const ws = await openWebSocket(wsURL);
      try {
        const response = await jsonRpcRequest(ws, "dock/subscribe", { offset: 0, limit: 10 });
        assert.equal(response.error, undefined);
        assert.equal(response.result.complete, true);
        assert.equal(response.result.freshness.status, "fresh");
        assert.deepEqual(response.result.rows.map((card) => card.threadID), ["newer", "older"]);
      } finally {
        ws.close();
      }
    }, { codexHome });
  } finally {
    await appServer.close();
    fs.rmSync(codexHome, { recursive: true, force: true });
  }
});

test("thread/name/set forwards to app-server and refreshes dock card title from thread name", async () => {
  const appServer = await startCanonicalActivityAppServer();
  try {
    await withRelay(appServer.url, async ({ config, wsURL }) => {
      await config.relayStateEngine.reconcileDock({ reason: "test-initial" });
      const ws = await openWebSocket(wsURL);
      try {
        const initial = await jsonRpcRequest(ws, "dock/subscribe", { offset: 0, limit: 10 });
        assert.equal(initial.error, undefined);
        const initialCard = initial.result.rows.find((card) => card.threadID === "newer");
        assert.equal(initialCard?.title, "Newer turn row");

        const updatePromise = waitForRelayMessage(ws, (message) => (
          message.method === "dock/update"
          && (message.params?.rows || []).some((card) => (
            card.threadID === "newer" && card.title === "Renamed newer"
          ))
        ));
        const response = await jsonRpcRequest(ws, "thread/name/set", {
          threadId: "newer",
          name: "Renamed newer",
        });
        assert.equal(response.error, undefined);
        const update = await updatePromise;
        const updatedCard = update.params.rows.find((card) => card.threadID === "newer");

        assert.deepEqual(appServer.renameRequests, [
          { threadId: "newer", name: "Renamed newer" },
        ]);
        assert.equal(updatedCard?.title, "Renamed newer");
      } finally {
        ws.close();
      }
    }, { liveEndpoints: [{ label: "canonical-live", url: appServer.url }] });
  } finally {
    await appServer.close();
  }
});

test("thread/name/set responds before dock rename reconcile finishes", async () => {
  const appServer = await startCanonicalActivityAppServer();
  try {
    await withRelay(appServer.url, async ({ config, wsURL }) => {
      await config.relayStateEngine.reconcileDock({ reason: "test-initial" });
      const originalHandleThreadNameMutation = config.relayStateEngine.handleThreadNameMutation
        .bind(config.relayStateEngine);
      let releaseReconcile = () => {};
      const reconcileGate = new Promise((resolve) => {
        releaseReconcile = resolve;
      });
      let mutationStarted = false;
      let mutationFinished = false;
      config.relayStateEngine.handleThreadNameMutation = async (mutation) => {
        mutationStarted = true;
        await reconcileGate;
        const result = await originalHandleThreadNameMutation(mutation);
        mutationFinished = true;
        return result;
      };

      const ws = await openWebSocket(wsURL);
      try {
        const initial = await jsonRpcRequest(ws, "dock/subscribe", { offset: 0, limit: 10 });
        assert.equal(initial.error, undefined);

        const updatePromise = waitForRelayMessage(ws, (message) => (
          message.method === "dock/update"
          && (message.params?.rows || []).some((card) => (
            card.threadID === "newer" && card.title === "Quick response renamed newer"
          ))
        ));
        const startedAt = Date.now();
        const response = await jsonRpcRequest(ws, "thread/name/set", {
          threadId: "newer",
          name: "Quick response renamed newer",
        });
        const responseMs = Date.now() - startedAt;

        assert.equal(response.error, undefined);
        assert.equal(mutationStarted, true);
        assert.equal(mutationFinished, false);
        assert.ok(
          responseMs < 500,
          `expected thread/name/set response before delayed reconcile, got ${responseMs}ms`,
        );

        releaseReconcile();
        const update = await updatePromise;
        const updatedCard = update.params.rows.find((card) => card.threadID === "newer");

        assert.deepEqual(appServer.renameRequests, [
          { threadId: "newer", name: "Quick response renamed newer" },
        ]);
        assert.equal(updatedCard?.title, "Quick response renamed newer");
        const reconcileFinishedDeadline = Date.now() + 1_000;
        while (!mutationFinished && Date.now() < reconcileFinishedDeadline) {
          await sleepMs(5);
        }
        assert.equal(mutationFinished, true);
      } finally {
        releaseReconcile();
        ws.close();
      }
    });
  } finally {
    await appServer.close();
  }
});

test("thread/name/updated from history upstream refreshes dock card title without client rename", async () => {
  const appServer = await startCanonicalActivityAppServer();
  try {
    await withRelay(appServer.url, async ({ config, wsURL }) => {
      await config.relayStateEngine.reconcileDock({ reason: "test-initial" });
      const historyEntry = [...config.upstreamPool.entries.values()]
        .find((entry) => entry.label === "history");
      assert.equal(typeof historyEntry?.client?.onNotification, "function");

      const ws = await openWebSocket(wsURL);
      try {
        const initial = await jsonRpcRequest(ws, "dock/subscribe", { offset: 0, limit: 10 });
        assert.equal(initial.error, undefined);
        const initialCard = initial.result.rows.find((card) => card.threadID === "newer");
        assert.equal(initialCard?.title, "Newer turn row");

        const updatePromise = waitForRelayMessage(ws, (message) => (
          message.method === "dock/update"
          && (message.params?.rows || []).some((card) => (
            card.threadID === "newer" && card.title === "Server renamed newer"
          ))
        ));
        appServer.renameThreadLocally("newer", "Server renamed newer");
        assert.ok(appServer.emitThreadNameUpdated("newer", "Server renamed newer") > 0);
        const update = await updatePromise;
        const updatedCard = update.params.rows.find((card) => card.threadID === "newer");

        assert.deepEqual(appServer.renameRequests, []);
        assert.equal(updatedCard?.title, "Server renamed newer");
      } finally {
        ws.close();
      }
    });
  } finally {
    await appServer.close();
  }
});

test("thread/name/updated from active detail upstream refreshes dock card title before detail ledger can swallow it", async () => {
  const appServer = await startCanonicalActivityAppServer();
  try {
    await withRelay(appServer.url, async ({ config, wsURL }) => {
      await config.relayStateEngine.reconcileDock({ reason: "test-initial" });
      const ws = await openWebSocket(wsURL);
      try {
        const initial = await jsonRpcRequest(ws, "dock/subscribe", { offset: 0, limit: 10 });
        assert.equal(initial.error, undefined);
        const detail = await jsonRpcRequest(ws, "thread/detail/subscribe", { threadId: "newer" });
        assert.equal(detail.error, undefined);
        assert.equal(detail.result?.threadID, "newer");
        assert.equal(appServer.resumedClientCount, 1);

        const updatePromise = waitForRelayMessage(ws, (message) => (
          message.method === "dock/update"
          && (message.params?.rows || []).some((card) => (
            card.threadID === "newer" && card.title === "Detail upstream rename"
          ))
        ));
        appServer.renameThreadLocally("newer", "Detail upstream rename");
        assert.equal(appServer.emitThreadNameUpdated("newer", "Detail upstream rename", {
          resumedOnly: true,
        }), 1);
        const update = await updatePromise;
        const updatedCard = update.params.rows.find((card) => card.threadID === "newer");

        assert.equal(updatedCard?.title, "Detail upstream rename");
      } finally {
        ws.close();
      }
    });
  } finally {
    await appServer.close();
  }
});

test("thread/detail/subscribe falls back to history when a private live owner shadows human history", async () => {
  const appServer = await startCanonicalActivityAppServer();
  try {
    await withRelay(appServer.url, async ({ config, wsURL }) => {
      await config.appServerRegistry.refreshNow("test-private-owner-detail");
      config.appServerRegistry.recordPrivateOwner("newer", { pid: 3333, transport: "stdio" });
      const ws = await openWebSocket(wsURL);
      try {
        const detail = await jsonRpcRequest(ws, "thread/detail/subscribe", { threadId: "newer" });
        assert.equal(detail.error, undefined);
        assert.equal(detail.result?.threadID, "newer");
        assert.equal(detail.result?.view, "thread.detail");
        assert.equal(appServer.resumedClientCount, 0);

        const resync = await jsonRpcRequest(ws, "thread/detail/resync", { threadId: "newer" });
        assert.equal(resync.error, undefined);
        assert.equal(resync.result?.threadID, "newer");
        assert.equal(resync.result?.view, "thread.detail");
        assert.equal(appServer.resumedClientCount, 0);
      } finally {
        ws.close();
      }
    });
  } finally {
    await appServer.close();
  }
});

test("thread/detail/subscribe accepts a visible human Dock card when thread/read omits source metadata", async () => {
  const appServer = await startCanonicalActivityAppServer({
    omitReadSourceFor: new Set(["newer"]),
  });
  try {
    await withRelay(appServer.url, async ({ config, wsURL }) => {
      await config.relayStateEngine.reconcileDock({ reason: "test-missing-read-source" });
      const ws = await openWebSocket(wsURL);
      try {
        const initial = await jsonRpcRequest(ws, "dock/subscribe", { offset: 0, limit: 10 });
        assert.equal(initial.error, undefined);
        assert.equal(initial.result?.complete, true);
        const card = initial.result.rows.find((row) => row.threadID === "newer");
        assert.equal(card?.lane, "human");
        assert.equal(card?.sourceKind, "human");
        assert.equal(card?.freshness, "fresh");
        assert.equal(card?.completeness, "complete");

        const detail = await jsonRpcRequest(ws, "thread/detail/subscribe", { threadId: "newer" });
        assert.equal(detail.error, undefined);
        assert.equal(detail.result?.threadID, "newer");
        assert.equal(detail.result?.view, "thread.detail");
        assert.ok(Array.isArray(detail.result?.rows));

        const resync = await jsonRpcRequest(ws, "thread/detail/resync", { threadId: "newer" });
        assert.equal(resync.error, undefined);
        assert.equal(resync.result?.threadID, "newer");
        assert.equal(resync.result?.view, "thread.detail");
        assert.ok(Array.isArray(resync.result?.rows));
      } finally {
        ws.close();
      }
    });
  } finally {
    await appServer.close();
  }
});

test("thread/detail/subscribe accepts a visible human root Dock card when thread/read reports spawn metadata", async () => {
  const appServer = await startCanonicalActivityAppServer();
  try {
    await withRelay(appServer.url, async ({ config, wsURL }) => {
      await config.relayStateEngine.reconcileDock({ reason: "test-read-source-spawn" });
      const ws = await openWebSocket(wsURL);
      try {
        const initial = await jsonRpcRequest(ws, "dock/subscribe", { offset: 0, limit: 10 });
        assert.equal(initial.error, undefined);
        assert.equal(initial.result?.complete, true);
        const card = initial.result.rows.find((row) => row.threadID === "newer");
        assert.equal(card?.lane, "human");
        assert.equal(card?.sourceKind, "human");
        assert.equal(card?.relationship, "root");

        appServer.setReadSourceFor("newer", {
          subagent: {
            thread_spawn: {
              parent_thread_id: "parent-thread",
            },
          },
        });

        const detail = await jsonRpcRequest(ws, "thread/detail/subscribe", { threadId: "newer" });
        assert.equal(detail.error, undefined);
        assert.equal(detail.result?.threadID, "newer");
        assert.equal(detail.result?.view, "thread.detail");
        assert.ok(Array.isArray(detail.result?.rows));

        const resync = await jsonRpcRequest(ws, "thread/detail/resync", { threadId: "newer" });
        assert.equal(resync.error, undefined);
        assert.equal(resync.result?.threadID, "newer");
        assert.equal(resync.result?.view, "thread.detail");
        assert.ok(Array.isArray(resync.result?.rows));
      } finally {
        ws.close();
      }
    });
  } finally {
    await appServer.close();
  }
});

test("thread/status/changed from history upstream refreshes dock card status without waiting for polling", async () => {
  const appServer = await startCanonicalActivityAppServer();
  try {
    await withRelay(appServer.url, async ({ config, wsURL }) => {
      await config.relayStateEngine.reconcileDock({ reason: "test-initial" });
      const ws = await openWebSocket(wsURL);
      try {
        const initial = await jsonRpcRequest(ws, "dock/subscribe", { offset: 0, limit: 10 });
        assert.equal(initial.error, undefined);
        const initialCard = initial.result.rows.find((card) => card.threadID === "newer");
        assert.equal(initialCard?.status, "idle");

        const updatePromise = waitForRelayMessage(ws, (message) => (
          message.method === "dock/update"
          && (message.params?.rows || []).some((card) => (
            card.threadID === "newer" && card.status === "running"
          ))
        ));
        const runningStatus = { type: "active", activeFlags: [] };
        appServer.setThreadStatusLocally("newer", runningStatus);
        assert.ok(appServer.emitThreadStatusChanged("newer", runningStatus) > 0);
        const update = await updatePromise;
        const updatedCard = update.params.rows.find((card) => card.threadID === "newer");

        assert.equal(updatedCard?.status, "running");
      } finally {
        ws.close();
      }
    });
  } finally {
    await appServer.close();
  }
});

test("thread/name/set plus app-server rename notification produces one visible title transition", async () => {
  const appServer = await startCanonicalActivityAppServer({ emitRenameNotifications: true });
  try {
    await withRelay(appServer.url, async ({ config, wsURL }) => {
      await config.relayStateEngine.reconcileDock({ reason: "test-initial" });
      const ws = await openWebSocket(wsURL);
      const titleUpdates = [];
      ws.on("message", (data) => {
        const message = JSON.parse(data.toString());
        if (message.method !== "dock/update") {
          return;
        }
        for (const card of message.params?.rows || []) {
          if (card.threadID === "newer" && card.title === "Command renamed newer") {
            titleUpdates.push(message);
          }
        }
      });
      try {
        const initial = await jsonRpcRequest(ws, "dock/subscribe", { offset: 0, limit: 10 });
        assert.equal(initial.error, undefined);

        const updatePromise = waitForRelayMessage(ws, (message) => (
          message.method === "dock/update"
          && (message.params?.rows || []).some((card) => (
            card.threadID === "newer" && card.title === "Command renamed newer"
          ))
        ));
        const response = await jsonRpcRequest(ws, "thread/name/set", {
          threadId: "newer",
          name: "Command renamed newer",
        });
        assert.equal(response.error, undefined);
        await updatePromise;
        await sleepMs(100);

        assert.deepEqual(appServer.renameRequests, [
          { threadId: "newer", name: "Command renamed newer" },
        ]);
        assert.equal(titleUpdates.length, 1);
      } finally {
        ws.close();
      }
    });
  } finally {
    await appServer.close();
  }
});

test("thread/detail/read is not a callable projection side door", async () => {
  const appServer = await startCanonicalActivityAppServer();
  try {
    await withRelay(appServer.url, async ({ wsURL }) => {
      const ws = await openWebSocket(wsURL);
      try {
        const read = await jsonRpcRequest(ws, "thread/detail/read", { threadId: "newer" });
        assert.equal(read.error?.code, -32601);
        assert.match(read.error?.message || "", /unsupported method/u);

        const witness = await jsonRpcRequest(ws, "projection/witness/read", {
          sourceHostID: "home",
          view: "thread.detail",
          scope: "thread",
          threadID: "newer",
        });
        assert.equal(witness.error, undefined);
        assert.equal(witness.result.byteEquivalentToDownstream, true);
        assert.equal(witness.result.lastSeq, 0);
        assert.deepEqual(witness.result.envelopes, []);
        assert.deepEqual(witness.result.projectionIDs, []);
      } finally {
        ws.close();
      }
    }, { projectionWitnessEnabled: true });
  } finally {
    await appServer.close();
  }
});

test("dock/subscribe includes live-only rows absent from raw thread/list", async () => {
  const appServer = await startCanonicalActivityAppServer({ loadedThreadIDs: ["live-only"] });
  try {
    await withRelay(
      appServer.url,
      async ({ config, wsURL }) => {
        await config.relayStateEngine.reconcileDock({ reason: "test" });
        const ws = await openWebSocket(wsURL);
        try {
          const response = await jsonRpcRequest(ws, "dock/subscribe", { offset: 0, limit: 10 });
          assert.equal(response.error, undefined);
          assert.equal(response.result.complete, true);
          assert.equal(response.result.freshness.status, "fresh");
          assert.deepEqual(response.result.rows.map((card) => card.threadID), [
            "live-only",
            "newer",
            "older",
          ]);
          const liveOnly = response.result.rows.find((card) => card.threadID === "live-only");
          assert.equal(liveOnly?.completeness, "complete");
          assert.equal(liveOnly?.freshness, "fresh");
        } finally {
          ws.close();
        }
      },
      { liveEndpoints: [{ label: "canonical-live", url: appServer.url }] },
    );
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
        assert.deepEqual(response.result.rows.map((card) => card.threadID), ["newer", "older"]);
        const newer = response.result.rows.find((card) => card.threadID === "newer");
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
          assert.deepEqual(response.result.rows.map((card) => card.threadID), ["newer", "older"]);
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
        const newer = response.result.rows.find((card) => card.threadID === "newer");
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

test("dock/update replacement upsert is complete when it carries every current row", async () => {
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
        assert.deepEqual(initial.result.rows.map((card) => card.threadID), ["cached"]);

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
          && message.params?.kind === "upsert"
          && (message.params?.rows || []).some((card) => card.threadID === "recovered")
        ));
        await config.relayStateEngine.reconcileDock({ reason: "test-recovered" });
        const update = await updatePromise;

        assert.equal("baseSeq" in update.params, false);
        assert.ok(update.params.seq > initialDockSeq);
        assert.equal(update.params.complete, true);
        assert.equal(update.params.totalRows, 1);
        assert.deepEqual(update.params.rows.map((card) => card.threadID), ["recovered"]);
        assert.deepEqual(update.params.projectionIDs, ["host:home/thread:cached/row:threadCard"]);
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

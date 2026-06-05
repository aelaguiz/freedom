import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { WebSocketServer } from "ws";

import {
  AppServerRegistry,
  AppServerRegistryRouteError,
  discoverAppServerEndpointsFromProcesses,
  normalizeAppServerEndpoint,
} from "./dock-relay-app-server-registry.mjs";
import {
  collectLiveRows,
  mergePrivateLiveRows,
} from "./dock-relay-thread-data.mjs";
import {
  normalizedStatus,
} from "./dock-relay-state-views.mjs";
import {
  closeWebSocketServer,
  onceListening,
  startUnixJsonRpcServer,
} from "./dock-relay-test-helpers.mjs";

function jsonRpcResponse(id, result) {
  return JSON.stringify({ id, result });
}

async function startLoopbackAppServer({
  loadedThreadIDs = [],
  rows = {},
} = {}) {
  const wss = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  const clients = new Set();
  await onceListening(wss);
  const url = `ws://127.0.0.1:${wss.address().port}`;
  wss.on("connection", (ws) => {
    clients.add(ws);
    ws.on("close", () => clients.delete(ws));
    ws.on("message", (raw) => {
      const message = JSON.parse(raw.toString());
      if (message.method === "initialize") {
        ws.send(jsonRpcResponse(message.id, {
          userAgent: "registry-live-test",
          codexHome: "/tmp/codex-dock-registry-test",
        }));
      } else if (message.method === "initialized") {
        return;
      } else if (message.method === "thread/loaded/list") {
        ws.send(jsonRpcResponse(message.id, { data: loadedThreadIDs }));
      } else if (message.method === "thread/read") {
        ws.send(jsonRpcResponse(message.id, {
          thread: rows[message.params?.threadId],
        }));
      } else if (message.method === "thread/list") {
        ws.send(jsonRpcResponse(message.id, { data: [], nextCursor: null }));
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

test("app-server registry selects daemon history over Dock-owned raw endpoints", async () => {
  const daemon = await startUnixJsonRpcServer((message) => {
    if (message.method === "initialize") {
      return { id: message.id, result: { userAgent: "daemon-history-test" } };
    }
    if (message.method === "thread/list") {
      return { id: message.id, result: { data: [], nextCursor: null } };
    }
    return null;
  });
  const registry = new AppServerRegistry({
    includeDaemonHistory: false,
    processListProvider: async () => [],
    fixtureHistoryEndpoints: [
      {
        label: "legacy-dock-raw",
        url: "ws://127.0.0.1:4500",
        dockOwnedRaw: true,
      },
      {
        label: "daemon-history",
        url: `unix://${daemon.socketPath}`,
      },
    ],
  });
  try {
    await registry.refreshNow("test");
    const history = registry.historyEndpoint({ required: true });
    assert.equal(history.transport, "unix");
    assert.equal(history.label, "daemon-history");

    const client = await registry.historyClient();
    try {
      const list = await client.request("thread/list", {});
      assert.deepEqual(list, { data: [], nextCursor: null });
    } finally {
      await client.close();
    }
  } finally {
    registry.stop();
    await daemon.close();
  }
});

test("app-server registry discovers loopback live endpoints and records owner leases", async () => {
  const live = await startLoopbackAppServer({
    loadedThreadIDs: ["thread-live"],
    rows: {
      "thread-live": {
        id: "thread-live",
        preview: "Running in another app-server",
        source: "cli",
        updatedAt: 2_000,
        status: { type: "active", activeFlags: [] },
      },
    },
  });
  const registry = new AppServerRegistry({
    includeDaemonHistory: false,
    processListProvider: async () => [{
      pid: 1234,
      ppid: 1,
      command: `/usr/local/bin/codex app-server --listen ${live.url}`,
    }],
  });
  try {
    await registry.refreshNow("test");
    const liveEndpoints = registry.liveEndpoints();
    assert.equal(liveEndpoints.length, 1);
    assert.equal(liveEndpoints[0].url, `${live.url}/`);

    const collected = await registry.collectLiveRows();
    assert.equal(collected.rows.length, 1);
    assert.equal(collected.totalThreadReads, 1);

    const owner = registry.ownerForThread("thread-live");
    assert.equal(owner.endpoint.url, `${live.url}/`);
    const route = registry.routeForThreadMethod("thread/read", "thread-live");
    assert.equal(route.source, "live-owner");
    assert.equal(route.endpoint.url, `${live.url}/`);
  } finally {
    registry.stop();
    await live.close();
  }
});

test("app-server registry probes unix process endpoints as attachable owners", async () => {
  const threadId = "thread-unix-live";
  const unixServer = await startUnixJsonRpcServer((message) => {
    if (message.method === "initialize") {
      return { id: message.id, result: { userAgent: "unix-live-test" } };
    }
    if (message.method === "initialized") {
      return null;
    }
    if (message.method === "thread/loaded/list") {
      return { id: message.id, result: { data: [threadId] } };
    }
    if (message.method === "thread/read") {
      return {
        id: message.id,
        result: {
          thread: {
            id: threadId,
            source: "cli",
            updatedAt: 2_500,
            status: { type: "active", activeFlags: [] },
          },
        },
      };
    }
    if (message.method === "thread/list") {
      return { id: message.id, result: { data: [], nextCursor: null } };
    }
    return null;
  });
  const registry = new AppServerRegistry({
    includeDaemonHistory: false,
    processListProvider: async () => [{
      pid: 4321,
      ppid: 1,
      command: `/usr/local/bin/codex app-server --listen unix://${unixServer.socketPath}`,
    }],
  });
  try {
    await registry.refreshNow("test");
    const liveEndpoints = registry.liveEndpoints();
    assert.equal(liveEndpoints.length, 1);
    assert.equal(liveEndpoints[0].transport, "unix");
    assert.equal(liveEndpoints[0].socketPath, unixServer.socketPath);

    const collected = await registry.collectLiveRows();
    assert.equal(collected.rows.length, 1);
    assert.equal(collected.rows[0].id, threadId);

    const owner = registry.ownerForThread(threadId);
    assert.equal(owner.endpoint.transport, "unix");
    assert.equal(owner.endpoint.socketPath, unixServer.socketPath);

    const route = registry.routeForThreadMethod("thread/detail/subscribe", threadId);
    assert.equal(route.source, "live-owner");
    assert.equal(route.endpoint.transport, "unix");
  } finally {
    registry.stop();
    await unixServer.close();
  }
});

test("app-server registry records private stdio app-servers as unreachable diagnostics", async () => {
  const discovered = discoverAppServerEndpointsFromProcesses([{
    pid: 2222,
    ppid: 1,
    command: "/usr/local/bin/codex app-server",
  }, {
    pid: 2223,
    ppid: 1,
    command: "/Applications/Codex.app/Contents/Resources/node_repl prompt '{\"text\":\"please inspect codex app-server --listen ws://127.0.0.1:65000\"}'",
  }]);
  assert.equal(discovered.endpoints.length, 0);
  assert.equal(discovered.observations.length, 1);

  const registry = new AppServerRegistry({
    includeDaemonHistory: false,
    processListProvider: async () => [{
      pid: 2222,
      ppid: 1,
      command: "/usr/local/bin/codex app-server",
    }],
  });
  await registry.refreshNow("test");
  const snapshot = registry.snapshot();
  assert.equal(snapshot.counts.liveEndpoints, 0);
  assert.equal(snapshot.counts.unreachableObserved, 1);
  assert.equal(snapshot.unreachableObserved[0].failure.reason, "private_transport");
  assert.equal(registry.ownerForThread("thread-private"), null);

  registry.recordPrivateOwner("thread-private", { pid: 2222, transport: "stdio" });
  assert.throws(
    () => registry.routeForThreadMethod("thread/read", "thread-private"),
    (error) => error instanceof AppServerRegistryRouteError
      && error.reason === "private_owner_unattachable",
  );
});

test("app-server registry discovers active codex resume commands as private live owners", async () => {
  const threadId = "019e94e2-1111-4222-8333-0123456789ab";
  const processList = [{
    pid: 2300,
    ppid: 1,
    command: `node /Users/aelaguiz/.local/bin/codex -p yolo resume ${threadId}`,
  }, {
    pid: 2301,
    ppid: 2300,
    command: `/Applications/Codex.app/Contents/Resources/codex -p yolo resume ${threadId}`,
  }, {
    pid: 2302,
    ppid: 1,
    command: "/Applications/Codex.app/Contents/Resources/node_repl prompt '{\"text\":\"please inspect codex resume 019e94e2-aaaa-4bbb-8ccc-0123456789ab\"}'",
  }];
  const discovered = discoverAppServerEndpointsFromProcesses(processList);
  assert.equal(discovered.privateThreadOwners.length, 1);
  assert.equal(discovered.privateThreadOwners[0].threadId, threadId);
  assert.equal(discovered.privateThreadOwners[0].transport, "stdio");

  let currentProcessList = processList;
  const registry = new AppServerRegistry({
    includeDaemonHistory: false,
    processListProvider: async () => currentProcessList,
  });
  await registry.refreshNow("test");
  assert.equal(registry.snapshot().counts.privateOwners, 1);

  const privateRows = registry.privateLiveRows();
  assert.equal(privateRows.length, 1);
  assert.equal(privateRows[0].id, threadId);
  assert.equal(privateRows[0].source, "cli");
  assert.equal(privateRows[0].status.type, "privateUnattachable");
  assert.equal(normalizedStatus(privateRows[0]), "unknown");
  assert.equal(privateRows[0].dockRelaySource.endpointType, "private");

  assert.throws(
    () => registry.routeForThreadMethod("thread/read", threadId),
    (error) => error instanceof AppServerRegistryRouteError
      && error.reason === "private_owner_unattachable",
  );

  currentProcessList = [];
  await registry.refreshNow("test-missing");
  assert.equal(registry.snapshot().counts.privateOwners, 0);
});

test("app-server registry discovers plain codex CLI owners from open session files", async () => {
  const codexHome = "/Users/aelaguiz/.codex";
  const threadId = "019e95a4-4810-7612-818e-22475bcf0874";
  const sessionPath = path.join(
    codexHome,
    "sessions/2026/06/04/rollout-2026-06-04T21-37-12-019e95a4-4810-7612-818e-22475bcf0874.jsonl",
  );
  const discovered = discoverAppServerEndpointsFromProcesses([{
    pid: 52467,
    ppid: 52466,
    command: "/opt/homebrew/lib/node_modules/@openai/codex/vendor/bin/codex -p yolo",
    openSessionPaths: [
      sessionPath,
      "/tmp/rollout-2026-06-04T21-37-12-019e95a4-4810-7612-818e-22475bcf0874.jsonl",
    ],
  }], { codexHome });

  assert.equal(discovered.privateThreadOwners.length, 1);
  assert.deepEqual(discovered.privateThreadOwners[0], {
    threadId,
    source: "process",
    transport: "stdio",
    pid: 52467,
    ppid: 52466,
    ownerKind: "codex-cli-session-file",
  });

  const registry = new AppServerRegistry({
    codexHome,
    includeDaemonHistory: false,
    processListProvider: async () => [{
      pid: 52467,
      ppid: 52466,
      command: "/opt/homebrew/lib/node_modules/@openai/codex/vendor/bin/codex -p yolo",
      openSessionPath: sessionPath,
    }],
  });
  await registry.refreshNow("test");
  assert.equal(registry.snapshot().counts.privateOwners, 1);
  const privateRows = registry.privateLiveRows();
  assert.equal(privateRows.length, 1);
  assert.equal(privateRows[0].id, threadId);
  assert.equal(privateRows[0].dockRelaySource.pid, 52467);
});

test("collectLiveRows uses one-shot live-status sockets instead of exhausting the upstream pool", async () => {
  const first = await startLoopbackAppServer({
    loadedThreadIDs: ["thread-live-a"],
    rows: {
      "thread-live-a": {
        id: "thread-live-a",
        source: "cli",
        updatedAt: 2_000,
        status: { type: "active", activeFlags: [] },
      },
    },
  });
  const second = await startLoopbackAppServer({
    loadedThreadIDs: ["thread-live-b"],
    rows: {
      "thread-live-b": {
        id: "thread-live-b",
        source: "cli",
        updatedAt: 3_000,
        status: { type: "active", activeFlags: [] },
      },
    },
  });
  try {
    const pool = {
      labelLimit: () => 1,
      clientFor: async () => {
        throw new Error("live-status should use one-shot clients");
      },
    };
    const result = await collectLiveRows({
      endpoints: [
        { label: "first", url: first.url },
        { label: "second", url: second.url },
      ],
      pool,
    });
    assert.equal(result.failedEndpoints, 0);
    assert.deepEqual(result.rows.map((row) => row.id).sort(), ["thread-live-a", "thread-live-b"]);
  } finally {
    await first.close();
    await second.close();
  }
});

test("app-server registry resolves relative unix paths only when process cwd is known", () => {
  const processCwd = fs.mkdtempSync(path.join(os.tmpdir(), "codex-dock-registry-cwd-"));
  try {
    const relative = normalizeAppServerEndpoint({
      url: "unix://relative.sock",
      processCwd,
    });
    assert.equal(relative.socketPath, path.join(processCwd, "relative.sock"));
    assert.equal(relative.url, `unix://${path.join(processCwd, "relative.sock")}`);
    assert.equal(relative.failure, null);

    const unknownCwd = normalizeAppServerEndpoint({
      url: "unix://relative.sock",
    });
    assert.equal(unknownCwd.socketPath, null);
    assert.equal(unknownCwd.failure.reason, "unix_socket_relative_cwd_unknown");
  } finally {
    fs.rmSync(processCwd, { recursive: true, force: true });
  }
});

test("app-server registry resolves bare unix history to the default control socket", async () => {
  const tempDir = fs.mkdtempSync("/tmp/cdr-default-unix-");
  const codexHome = path.join(tempDir, "codex-home");
  const socketDir = path.join(codexHome, "app-server-control");
  fs.mkdirSync(socketDir, { recursive: true });
  const socketPath = path.join(socketDir, "app-server-control.sock");
  const daemon = await startUnixJsonRpcServer((message) => {
    if (message.method === "initialize") {
      return { id: message.id, result: { userAgent: "default-unix-history-test" } };
    }
    if (message.method === "initialized") {
      return null;
    }
    if (message.method === "thread/list") {
      return { id: message.id, result: { data: [], nextCursor: null } };
    }
    if (message.method === "thread/loaded/list") {
      return { id: message.id, result: { data: ["thread-daemon-live"] } };
    }
    if (message.method === "thread/read") {
      return {
        id: message.id,
        result: {
          thread: {
            id: "thread-daemon-live",
            source: "cli",
            updatedAt: 3_000,
            status: { type: "active", activeFlags: [] },
          },
        },
      };
    }
    return null;
  }, { socketPath });
  const registry = new AppServerRegistry({
    codexHome,
    includeDaemonHistory: true,
    processListProvider: async () => [],
  });
  try {
    await registry.refreshNow("test");
    const snapshot = registry.snapshot();
    assert.equal(snapshot.history.transport, "unix");
    assert.equal(registry.liveEndpoints().length, 1);

    const client = await registry.historyClient();
    try {
      const list = await client.request("thread/list", {});
      assert.deepEqual(list, { data: [], nextCursor: null });
    } finally {
      await client.close();
    }

    const collected = await registry.collectLiveRows();
    assert.equal(collected.rows.length, 1);
    assert.equal(registry.ownerForThread("thread-daemon-live").endpoint.transport, "unix");
  } finally {
    registry.stop();
    await daemon.close();
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
});

test("app-server registry treats missing bare unix history socket as a diagnostic", async () => {
  const codexHome = fs.mkdtempSync(path.join(os.tmpdir(), "codex-dock-registry-missing-unix-"));
  const registry = new AppServerRegistry({
    codexHome,
    includeDaemonHistory: true,
    processListProvider: async () => [],
  });
  try {
    await registry.refreshNow("test");
    const snapshot = registry.snapshot();
    assert.equal(snapshot.counts.unreachableObserved, 1);
    assert.equal(snapshot.unreachableObserved[0].failure.reason, "unix_socket_missing");
  } finally {
    registry.stop();
    fs.rmSync(codexHome, { recursive: true, force: true });
  }
});

test("app-server registry routes supported relay methods through one table", async () => {
  const historyEndpoint = {
    label: "daemon-history",
    url: "ws://127.0.0.1:61001",
  };
  const liveEndpoint = {
    label: "live-owner",
    url: "ws://127.0.0.1:61002",
  };
  const registry = new AppServerRegistry({
    includeDaemonHistory: false,
    fixtureHistoryEndpoints: [historyEndpoint],
    fixtureLiveEndpoints: [liveEndpoint],
    processListProvider: async () => [],
  });
  await registry.refreshNow("test");
  assert.deepEqual(registry.liveEndpoints().map((endpoint) => endpoint.label), ["live-owner"]);
  const ownerEndpoint = registry.liveEndpoints().find((endpoint) => endpoint.label === "live-owner");
  registry.recordLiveRows(ownerEndpoint, [{
    id: "thread-live",
    source: "cli",
    updatedAt: 10_000,
    status: { type: "active", activeFlags: [] },
  }]);
  registry.recordPrivateOwner("thread-live", { pid: 4444, transport: "stdio" });
  registry.recordPrivateOwner("thread-private", { pid: 3333, transport: "stdio" });

  const merged = mergePrivateLiveRows({
    rows: [{
      id: "thread-live",
      source: "cli",
      updatedAt: 10_000,
      status: { type: "active", activeFlags: [] },
    }],
  }, registry);
  assert.equal(merged.rows.find((row) => row.id === "thread-live").status.type, "active");
  assert.equal(normalizedStatus(merged.rows.find((row) => row.id === "thread-live")), "running");

  for (const method of [
    "thread/read",
    "thread/turns/list",
    "thread/message/send",
    "thread/resume",
    "turn/start",
    "turn/steer",
    "thread/archive",
    "thread/name/set",
    "thread/detail/subscribe",
    "thread/detail/resync",
  ]) {
    const route = registry.routeForThreadMethod(method, "thread-live");
    assert.equal(route.source, "live-owner", method);
    assert.equal(route.endpoint.label, "live-owner", method);
  }

  for (const method of [
    "thread/list",
    "thread/unarchive",
  ]) {
    const route = registry.routeForThreadMethod(method, "thread-live");
    assert.equal(route.source, "history", method);
    assert.equal(route.endpoint.label, "daemon-history", method);
  }

  const unknownThreadRoute = registry.routeForThreadMethod("thread/read", "thread-cold");
  assert.equal(unknownThreadRoute.source, "history");
  assert.equal(unknownThreadRoute.endpoint.label, "daemon-history");

  for (const method of [
    "turn/interrupt",
    "raw-json-rpc/server-request-response",
  ]) {
    assert.throws(
      () => registry.routeForThreadMethod(method, "thread-live"),
      (error) => error instanceof AppServerRegistryRouteError
        && error.reason === "active_session_required",
      method,
    );
    const activeRoute = registry.routeForThreadMethod(method, "thread-live", {
      activeSessionEndpoint: liveEndpoint,
    });
    assert.equal(activeRoute.source, "active-session", method);
  }

  assert.throws(
    () => registry.routeForThreadMethod("thread/read", "thread-private"),
    (error) => error instanceof AppServerRegistryRouteError
      && error.reason === "private_owner_unattachable",
  );
  const privateTurnsRoute = registry.routeForThreadMethod("thread/turns/list", "thread-private", {
    allowHistoryForPrivateOwner: true,
  });
  assert.equal(privateTurnsRoute.source, "history");
  assert.equal(privateTurnsRoute.endpoint.label, "daemon-history");
});

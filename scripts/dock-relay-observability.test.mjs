import assert from "node:assert/strict";
import fs from "node:fs";
import http from "node:http";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import {
  FAILURE_CATEGORY,
  ROUTE_CONFIGS,
  ROUTE_NAMES,
  ROUTE_STATUS,
  autoProbeSafeRoutes,
} from "./dock-relay-observability-contract.mjs";
import { resolveSourceHostID, startServer } from "./dock-relay.mjs";
import { createRelayObservability } from "./dock-relay-observability.mjs";
import {
  appServerRegistryFixtureConfig,
  jsonRpcRequest,
  openWebSocket,
} from "./dock-relay-test-helpers.mjs";

function httpStatus(url) {
  return new Promise((resolve, reject) => {
    http.get(url, (response) => {
      response.resume();
      response.on("end", () => resolve(response.statusCode));
    }).on("error", reject);
  });
}

async function withRelay(testFn) {
  return withRelayConfig({}, testFn);
}

async function withRelayConfig(overrides, testFn) {
  const config = {
    listenHost: "127.0.0.1",
    port: 0,
    phoneAuth: "none",
    ...appServerRegistryFixtureConfig({
      historyUrl: "ws://127.0.0.1:1/",
      historyBearerToken: "test-token",
    }),
    advertiseBonjour: false,
    relayStateDatabasePath: ":memory:",
    hostId: "home",
    hostName: "Home",
    ...overrides,
  };
  const server = startServer(config);
  await server.listening;
  try {
    await testFn({ config, baseURL: `http://127.0.0.1:${config.port}`, wsURL: `ws://127.0.0.1:${config.port}` });
  } finally {
    await server.close();
  }
}

test("observability contract contains only supported app-facing routes", () => {
  assert.equal(ROUTE_NAMES.dockSubscribe, "dock/subscribe");
  assert.equal(ROUTE_NAMES.archiveSubscribe, "archive/subscribe");
  assert.equal(ROUTE_NAMES.threadNameSet, "thread/name/set");
  assert.equal(ROUTE_CONFIGS[ROUTE_NAMES.threadNameSet]?.probeSafety, "passive-only");
  assert.equal(ROUTE_CONFIGS[ROUTE_NAMES.threadNameSet]?.appCritical, true);
  assert.equal(ROUTE_CONFIGS["thread/list"], undefined);
  assert.equal(ROUTE_CONFIGS["thread/search"], undefined);
  assert.equal(ROUTE_CONFIGS["thread/goal/get"], undefined);
  assert.equal(ROUTE_CONFIGS["relay/state/snapshot"], undefined);
  assert.equal(ROUTE_CONFIGS["state/query"], undefined);
  assert.equal(autoProbeSafeRoutes().some((route) => route.name === "thread/list"), false);
});

test("sourceHostID persists when CODEX_DOCK_REAL_HOST_ID is absent", () => {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "codex-dock-source-host-"));
  const sourceHostIDPath = path.join(tempDir, ".codex-dock", "source-host-id");
  const config = {
    hostId: null,
    historyUrl: "ws://127.0.0.1:1/",
    codexHome: path.join(tempDir, "codex-home"),
    sourceHostIDPath,
  };

  const first = resolveSourceHostID(config);
  const second = resolveSourceHostID(config);

  assert.match(first, /^local-[a-f0-9]{12}$/);
  assert.equal(second, first);
  assert.equal(fs.readFileSync(sourceHostIDPath, "utf8").trim(), first);
  fs.rmSync(tempDir, { recursive: true, force: true });
});

test("sourceHostID rejects endpoint-shaped IDs", () => {
  assert.throws(
    () => resolveSourceHostID({ hostId: "127.0.0.1:4510" }),
    /invalid CODEX_DOCK_REAL_HOST_ID/
  );
});

test("removed JSON-RPC side doors are unsupported", async () => withRelay(async ({ wsURL }) => {
  const ws = await openWebSocket(wsURL);
  try {
    for (const method of [
      "thread/list",
      "thread/search",
      "thread/goal/get",
      "thread/loaded/list",
      "relay/state/snapshot",
      "state/query",
    ]) {
      const response = await jsonRpcRequest(ws, method, {});
      assert.equal(response.error?.code, -32601);
      assert.match(response.error?.message || "", /unsupported method/);
    }
  } finally {
    ws.close();
  }
}));

test("projection witness route fails closed unless explicitly enabled", async () => withRelay(async ({ wsURL }) => {
  const ws = await openWebSocket(wsURL);
  try {
    const response = await jsonRpcRequest(ws, "projection/witness/read", {});
    assert.equal(response.error?.code, -32601);
    assert.match(response.error?.message || "", /projection witness is disabled/);
  } finally {
    ws.close();
  }
}));

test("projection witness route returns retained projection envelopes when enabled", async () => withRelayConfig({
  projectionWitnessEnabled: true,
  projectionWitnessLog: [{
    emittedAt: "2026-06-01T00:00:00.000Z",
    envelope: {
      schemaVersion: 1,
      identityVersion: 1,
      projectionEngineVersion: 1,
      sourceHostID: "home",
      view: "thread.detail",
      threadID: "thread-1",
      epoch: "epoch-1",
      seq: 1,
      scope: "thread",
      viewParamsKey: "default-view",
      rows: [{
        projectionID: "host:home/thread:thread-1/turn:turn-1/item:item-1/row:userMessage",
        sourceRef: "host:home/thread:thread-1/turn:turn-1/item:item-1",
        rowRole: "userMessage",
        displayOrderKey: "001",
      }],
    },
  }],
}, async ({ wsURL }) => {
  const ws = await openWebSocket(wsURL);
  try {
    const response = await jsonRpcRequest(ws, "projection/witness/read", {
      sourceHostID: "home",
      view: "thread.detail",
      scope: "thread",
      threadID: "thread-1",
      viewParamsKey: "default-view",
      epoch: "epoch-1",
    });
    assert.equal(response.error, undefined);
    assert.equal(response.result.byteEquivalentToDownstream, true);
    assert.equal(response.result.source, "retained-downstream-emitter-log");
    assert.deepEqual(response.result.projectionIDs, [
      "host:home/thread:thread-1/turn:turn-1/item:item-1/row:userMessage",
    ]);
    assert.equal(response.result.lastSeq, 1);
    assert.equal(response.result.envelopes.length, 1);
  } finally {
    ws.close();
  }
}));

test("removed HTTP diagnostics do not expose card truth", async () => withRelay(async ({ baseURL }) => {
  for (const path of [
    "/statez",
    "/dbz",
    "/explainz/thread/example",
    "/debugz/sessions",
    "/subscriptionsz",
    "/tracesz/recent",
    "/tracesz/example",
    "/selftestz",
    "/bundlez",
  ]) {
    assert.equal(await httpStatus(`${baseURL}${path}`), 404);
  }
  assert.equal(await httpStatus(`${baseURL}/syncz`), 200);
}));

test("downstream-cancelled detail subscribe does not become an app-critical route failure", () => {
  const observability = createRelayObservability({
    hostId: "home",
    hostName: "Home",
    persistenceDir: false,
  });

  const successOperation = observability.beginOperation({ route: ROUTE_NAMES.threadDetailSubscribe });
  observability.finishOperation(successOperation, {
    ok: true,
    result: { thread: { id: "thread-1" } },
  });

  const cancelledOperation = observability.beginOperation({ route: ROUTE_NAMES.threadDetailSubscribe });
  const error = Object.assign(new Error("downstream session closed"), {
    code: -32000,
    data: {
      subsystem: "downstream",
      reason: "downstream_session_closed",
      cancelled: true,
      retryable: false,
    },
  });
  observability.finishOperation(cancelledOperation, {
    ok: false,
    error,
    errorCode: error.code,
    errorData: error.data,
    phase: error.data.subsystem,
  });

  const route = observability.routeHealth().find((entry) => entry.route === ROUTE_NAMES.threadDetailSubscribe);
  assert.equal(route.routeStatus, ROUTE_STATUS.HEALTHY);
  assert.equal(route.lastAttempt.outcome, "cancelled");
  assert.equal(route.lastAttempt.failureCategory, FAILURE_CATEGORY.CANCELLED);
  assert.equal(route.counters.total, 1);
  assert.equal(route.counters.succeeded, 1);
  assert.equal(route.counters.failed, 0);
  assert.deepEqual(route.statusReasons, []);
  assert.deepEqual(observability.appCriticalFailures(), []);
});

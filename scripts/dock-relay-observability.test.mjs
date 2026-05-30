import assert from "node:assert/strict";
import test from "node:test";

import { startServer } from "./dock-relay.mjs";
import {
  OBSERVABILITY_CONTRACT,
  PROBE_SAFETY,
  ROUTE_NAMES,
  assertAutoProbeRoute,
  routeConfigFor,
} from "./dock-relay-observability-contract.mjs";
import {
  createRelayObservability,
  measurementSummaryForResult,
} from "./dock-relay-observability.mjs";
import {
  httpGetJson,
  jsonRpcRequest,
  openWebSocket,
} from "./dock-relay-test-helpers.mjs";

test("observability contract covers relay app routes and keeps passive routes out of auto probes", () => {
  const expectedRoutes = [
    "initialize",
    "initialized",
    "thread/list",
    "thread/read",
    "thread/resume",
    "thread/turns/list",
    "thread/archive",
    "thread/unarchive",
    "dock/subscribe",
    "dock/update",
    "dock/resync",
    "turn/start",
    "turn/steer",
    "turn/interrupt",
    "audio/transcription/start",
    "audio/transcription/append",
    "audio/transcription/commit",
    "audio/transcription/cancel",
    "audio/transcription/delta",
    "audio/transcription/completed",
    "audio/transcription/failed",
    "audio/transcription/canceled",
    "audio/transcription/closed",
  ];

  for (const route of expectedRoutes) {
    assert.equal(OBSERVABILITY_CONTRACT.routes[route].name, route);
  }

  assert.equal(routeConfigFor(ROUTE_NAMES.dockUpdate).probeSafety, PROBE_SAFETY.PASSIVE_ONLY);
  assert.equal(routeConfigFor(ROUTE_NAMES.turnStart).probeSafety, PROBE_SAFETY.PASSIVE_ONLY);
  assert.equal(routeConfigFor(ROUTE_NAMES.audioTranscriptionStart).probeSafety, PROBE_SAFETY.PASSIVE_ONLY);
  assert.throws(() => assertAutoProbeRoute(ROUTE_NAMES.turnStart), /passive-only/);
  assert.throws(() => assertAutoProbeRoute(ROUTE_NAMES.audioTranscriptionStart), /passive-only/);
});

test("relay observability route transitions include status reasons and trace lookup", () => {
  const observability = createRelayObservability({
    hostId: "home",
    configuredHostID: "home.fairy-salmon.ts.net:4510",
    persistenceDir: false,
    clock: () => new Date("2026-05-30T12:00:00.000Z"),
  });

  const operation = observability.beginOperation({
    route: ROUTE_NAMES.dockSubscribe,
    traceContext: {
      operationID: "op-client-1",
      traceID: "tr-client-1",
      configuredHostID: "home.fairy-salmon.ts.net:4510",
    },
  });
  observability.finishOperation(operation, {
    ok: false,
    error: new Error("serialize response failed"),
    errorCode: -32000,
    errorData: { subsystem: "history", retryable: true },
    phase: "serialize-response",
  });

  const route = observability.routeHealth().find((entry) => entry.route === ROUTE_NAMES.dockSubscribe);
  assert.equal(route.routeStatus, "failed");
  assert.equal(route.configuredHostID, "home.fairy-salmon.ts.net:4510");
  assert.equal(route.relayHostID, "home");
  assert.equal(route.statusReasons.length, 1);
  assert.equal(route.statusReasons[0].code, "failed:last-attempt");
  assert.equal(route.lastFailure.operationID, "op-client-1");

  const trace = observability.trace("op-client-1");
  assert.equal(trace.operationID, "op-client-1");
  assert.equal(trace.outcome, "failed");
  assert.equal(trace.statusReasons[0].actual, "history");
});

test("payload measurement summarizes rows without storing raw payload content", () => {
  const summary = measurementSummaryForResult("thread/list", {
    sessions: [
      { id: "thread-1", preview: "first preview", turns: [{ role: "user", text: "omitted in bundle" }] },
      { id: "thread-2", preview: "second preview", turns: [] },
    ],
  });

  assert.equal(summary.route, "thread/list");
  assert.equal(summary.rowCount, 2);
  assert.equal(typeof summary.estimatedBytes, "number");
  assert.equal(typeof summary.largestRowEstimateBytes, "number");
  assert.ok(summary.estimatedBytes >= summary.largestRowEstimateBytes);
});

test("relay diagnostic bundle carries route evidence and content omission manifest", () => {
  const observability = createRelayObservability({
    hostId: "home",
    configuredHostID: "home.fairy-salmon.ts.net:4510",
    persistenceDir: false,
    clock: () => new Date("2026-05-30T12:00:00.000Z"),
  });
  const operation = observability.beginOperation({
    route: ROUTE_NAMES.threadList,
    traceContext: {
      operationID: "op-thread-list",
      traceID: "tr-thread-list",
      configuredHostID: "home.fairy-salmon.ts.net:4510",
    },
  });
  observability.finishOperation(operation, {
    ok: true,
    result: { sessions: [{ id: "thread-1" }] },
  });

  const bundle = observability.bundle();

  assert.equal(bundle.schema, "codexdock.bundle.v1");
  assert.equal(bundle.host.id, "home");
  assert.deepEqual(bundle.manifest.omitted, [
    "prompts",
    "transcripts",
    "audio",
    "headers",
    "full-jsonrpc-payloads",
  ]);
  assert.equal(bundle.routes.length, Object.keys(OBSERVABILITY_CONTRACT.routes).length);
  assert.equal(bundle.routes.some((route) => route.route === "thread/list" && route.routeStatus === "healthy"), true);
  assert.equal(bundle.traces.some((trace) => trace.operationID === "op-thread-list"), true);
});

test("readyz can pass while dock subscribe route health fails in statusz and routesz", async () => {
  const relay = startServer({
    listenHost: "127.0.0.1",
    port: 0,
    phoneAuth: "none",
    hostId: "home",
    hostName: "Home",
    historyUrl: "ws://127.0.0.1:1",
    historyBearerToken: "history-token",
    advertiseBonjour: false,
    observabilityDir: false,
    dockSessionProvider: {
      async listSessions() {
        throw new Error("dock provider offline");
      },
    },
  });
  await relay.listening;
  const baseURL = `http://127.0.0.1:${relay.server.address().port}`;
  const ws = await openWebSocket(`ws://127.0.0.1:${relay.server.address().port}`);

  try {
    const response = await jsonRpcRequest(ws, "dock/subscribe");
    assert.equal(response.error, undefined);
    assert.equal(response.result.freshness.status, "stale");

    const ready = await httpGetJson(`${baseURL}/readyz`);
    const status = await httpGetJson(`${baseURL}/statusz`);
    const routes = await httpGetJson(`${baseURL}/routesz`);
    const traces = await httpGetJson(`${baseURL}/tracesz/recent`);
    const route = status.routes.find((entry) => entry.route === "dock/subscribe");

    assert.equal(ready.ok, true);
    assert.equal(status.routes.length, Object.keys(OBSERVABILITY_CONTRACT.routes).length);
    assert.equal(route.routeStatus, "failed");
    assert.equal(route.statusReasons[0].actual, "history");
    assert.equal(status.appCriticalFailures.some((entry) => entry.route === "dock/subscribe"), true);
    assert.equal(routes.routes.some((entry) => entry.route === "dock/subscribe" && entry.routeStatus === "failed"), true);
    assert.equal(traces.traces.some((trace) => trace.route === "dock/subscribe" && trace.outcome === "failed"), true);
  } finally {
    ws.close();
    await relay.close();
  }
});

test("selftest lists only safe diagnostics and never includes passive mutating routes", async () => {
  const relay = startServer({
    listenHost: "127.0.0.1",
    port: 0,
    phoneAuth: "none",
    historyUrl: "ws://127.0.0.1:1",
    historyBearerToken: "history-token",
    advertiseBonjour: false,
    observabilityDir: false,
    dockSessionProvider: {
      async listSessions() {
        return { host: { id: "home", displayName: "Home" }, sessions: [] };
      },
    },
  });
  await relay.listening;
  const baseURL = `http://127.0.0.1:${relay.server.address().port}`;

  try {
    const selftest = await httpGetJson(`${baseURL}/selftestz`);
    const routeNames = selftest.routes.map((route) => route.route);
    assert.equal(selftest.ok, true);
    assert.equal(routeNames.includes("turn/start"), false);
    assert.equal(routeNames.includes("thread/archive"), false);
    assert.equal(routeNames.includes("audio/transcription/start"), false);
    assert.equal(routeNames.includes("dock/subscribe"), true);
    assert.equal(routeNames.includes("statusz"), true);
  } finally {
    await relay.close();
  }
});

test("selftest reports dock subscribe timeout instead of hanging", async () => {
  const relay = startServer({
    listenHost: "127.0.0.1",
    port: 0,
    phoneAuth: "none",
    historyUrl: "ws://127.0.0.1:1",
    historyBearerToken: "history-token",
    advertiseBonjour: false,
    observabilityDir: false,
    selftestRouteTimeoutMs: 20,
    dockSessionProvider: {
      async listSessions() {
        await new Promise(() => {});
      },
    },
  });
  await relay.listening;
  const baseURL = `http://127.0.0.1:${relay.server.address().port}`;

  try {
    const selftest = await Promise.race([
      httpGetJson(`${baseURL}/selftestz`),
      new Promise((_, reject) => setTimeout(() => reject(new Error("selftest hung")), 500)),
    ]);
    const dockSubscribe = selftest.routes.find((route) => route.route === ROUTE_NAMES.dockSubscribe);

    assert.equal(selftest.ok, false);
    assert.equal(dockSubscribe.ok, false);
    assert.equal(dockSubscribe.failureCategory, "timeout");
    assert.equal(dockSubscribe.timeoutMs, 20);
    assert.match(dockSubscribe.error, /dock\/subscribe self-test timed out after 20ms/);
  } finally {
    await relay.close();
  }
});

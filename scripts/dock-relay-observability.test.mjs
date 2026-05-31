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
import { normalizeThread } from "./dock-relay-state-views.mjs";
import {
  httpGetJson,
  jsonRpcRequest,
  openWebSocket,
  waitForRelayMessage,
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
  "archive/subscribe",
  "archive/update",
  "archive/resync",
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

test("relay observability marks stuck in-flight app routes as failed", () => {
  let now = new Date("2026-05-30T12:00:00.000Z");
  const observability = createRelayObservability({
    hostId: "home",
    configuredHostID: "home.fairy-salmon.ts.net:4510",
    persistenceDir: false,
    activeRouteTimeoutMs: 1_000,
    clock: () => now,
  });

  const operation = observability.beginOperation({
    route: ROUTE_NAMES.dockSubscribe,
  });
  let route = observability.routeHealth().find((entry) => entry.route === ROUTE_NAMES.dockSubscribe);

  assert.equal(route.routeStatus, "partial");
  assert.equal(route.lastAttempt.outcome, "started");

  now = new Date("2026-05-30T12:00:02.000Z");
  route = observability.routeHealth().find((entry) => entry.route === ROUTE_NAMES.dockSubscribe);
  const trace = observability.trace(operation.operationID);

  assert.equal(route.routeStatus, "failed");
  assert.equal(route.statusReasons[0].code, "failed:in-flight-timeout");
  assert.equal(route.statusReasons[0].threshold, 1_000);
  assert.equal(route.statusReasons[0].actual, 2_000);
  assert.equal(route.lastFailure.failureCategory, "timeout");
  assert.equal(route.counters.failed, 1);
  assert.equal(trace.outcome, "timed_out");
  assert.equal(trace.failureCategory, "timeout");
  assert.equal(observability.appCriticalFailures().some((entry) => entry.route === ROUTE_NAMES.dockSubscribe), true);

  route = observability.routeHealth().find((entry) => entry.route === ROUTE_NAMES.dockSubscribe);
  assert.equal(route.counters.failed, 1);
});

test("payload measurement summarizes rows without storing raw payload content", () => {
  const summary = measurementSummaryForResult("thread/list", {
    cards: [
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
    result: { cards: [{ id: "thread-1" }] },
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

test("readyz can pass while dock state freshness is stale after upstream failure", async () => {
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
  });
  await relay.listening;
  const baseURL = `http://127.0.0.1:${relay.server.address().port}`;
  const ws = await openWebSocket(`ws://127.0.0.1:${relay.server.address().port}`);

  try {
    const response = await jsonRpcRequest(ws, "dock/subscribe");
    assert.equal(response.error, undefined);
    await waitForRelayMessage(ws, (message) => message.method === "dock/update");

    const ready = await httpGetJson(`${baseURL}/readyz`);
    const status = await httpGetJson(`${baseURL}/statusz`);
    const state = await httpGetJson(`${baseURL}/statez`);
    const route = status.routes.find((entry) => entry.route === "dock/subscribe");

    assert.equal(ready.ok, true);
    assert.equal(status.routes.length, Object.keys(OBSERVABILITY_CONTRACT.routes).length);
    assert.equal(route.routeStatus, "healthy");
    assert.equal(status.appCriticalFailures.some((entry) => entry.route === "dock/subscribe"), false);
    assert.deepEqual(state.visibility, {
      mode: "app_facing_human_started_threads_only",
      includeRejectedThreads: false,
      rejectedThreadsRequireDiagnosticSnapshotOptIn: true,
    });
    assert.equal(state.counts.incomplete, 1);
    assert.deepEqual(
      state.syncScopes.map((scope) => [scope.scope, scope.complete, Boolean(scope.lastError)]),
      [
        ["active:interactiveDefault", 0, true],
      ],
    );
  } finally {
    ws.close();
    await relay.close();
  }
});

test("dock/subscribe route health stays healthy when serving stale cached state", async () => {
  const config = {
    listenHost: "127.0.0.1",
    port: 0,
    phoneAuth: "none",
    hostId: "home",
    hostName: "Home",
    historyUrl: "ws://127.0.0.1:1",
    historyBearerToken: "history-token",
    advertiseBonjour: false,
    observabilityDir: false,
    relayStateDatabasePath: ":memory:",
  };
  const relay = startServer(config);
  await relay.listening;
  const baseURL = `http://127.0.0.1:${relay.server.address().port}`;
  const host = { id: "home", displayName: "Home", endpoint: null };
  const cachedRow = normalizeThread({
    id: "cached-thread",
    preview: "Cached row",
    updatedAt: 100,
    source: "cli",
    status: { type: "notLoaded" },
  }, host, "human");
  const store = config.relayStateEngine.store;
  store.applyDockReconciliation({
    host,
    cards: [cachedRow],
    scopes: [
      { name: "active:allSourceKinds", archived: false, sourceScope: "allSourceKinds", complete: true },
      { name: "active:interactiveDefault", archived: false, sourceScope: "interactiveDefault", complete: true },
    ],
    complete: true,
  });
  store.markScopeStale("home", "active:allSourceKinds", new Error("history refresh failed"));
  const ws = await openWebSocket(`ws://127.0.0.1:${relay.server.address().port}`);

  try {
    const response = await jsonRpcRequest(ws, "dock/subscribe");
    assert.equal(response.error, undefined);
    assert.equal(response.result.freshness.status, "stale");
    assert.equal(response.result.cards.length, 1);

    const status = await httpGetJson(`${baseURL}/statusz`);
    const state = await httpGetJson(`${baseURL}/statez`);
    const route = status.routes.find((entry) => entry.route === "dock/subscribe");
    assert.equal(route.routeStatus, "healthy");
    assert.equal(status.appCriticalFailures.some((entry) => entry.route === "dock/subscribe"), false);
    assert.ok(state.counts.incomplete >= 1);
  } finally {
    ws.close();
    await relay.close();
  }
});

test("explainz/thread returns one row explanation without source refresh", async () => {
  const config = {
    listenHost: "127.0.0.1",
    port: 0,
    phoneAuth: "none",
    hostId: "home",
    hostName: "Home",
    historyUrl: "ws://127.0.0.1:1",
    historyBearerToken: "history-token",
    advertiseBonjour: false,
    observabilityDir: false,
    relayStateDatabasePath: ":memory:",
  };
  const relay = startServer(config);
  await relay.listening;
  const baseURL = `http://127.0.0.1:${relay.server.address().port}`;
  const host = { id: "home", displayName: "Home", endpoint: null };
  const cachedRow = normalizeThread({
    id: "cached-thread",
    preview: "Cached row",
    updatedAt: 100,
    source: "cli",
    status: { type: "notLoaded" },
  }, host, "human");
  config.relayStateEngine.store.applyDockReconciliation({
    host,
    cards: [cachedRow],
    scopes: [
      { name: "active:allSourceKinds", archived: false, sourceScope: "allSourceKinds", complete: true },
      { name: "active:interactiveDefault", archived: false, sourceScope: "interactiveDefault", complete: true },
    ],
    complete: true,
  });

  try {
    const explain = await httpGetJson(`${baseURL}/explainz/thread/cached-thread`);
    assert.equal(explain.ok, true);
    assert.equal(explain.explanation.found, true);
    assert.equal(explain.explanation.threadID, "cached-thread");
    assert.equal(explain.explanation.visibleInDock, true);
    assert.equal(explain.explanation.archiveState, "active");
    assert.equal(explain.explanation.syncScopes.length, 2);

    const missing = await httpGetJson(`${baseURL}/explainz/thread/missing-thread`);
    assert.equal(missing.explanation.found, false);
    assert.equal(missing.explanation.visibleInDock, false);
  } finally {
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

test("selftest reads passive dock state instead of calling dock subscribe", async () => {
  const relay = startServer({
    listenHost: "127.0.0.1",
    port: 0,
    phoneAuth: "none",
    historyUrl: "ws://127.0.0.1:1",
    historyBearerToken: "history-token",
    advertiseBonjour: false,
    observabilityDir: false,
    selftestRouteTimeoutMs: 20,
  });
  await relay.listening;
  const baseURL = `http://127.0.0.1:${relay.server.address().port}`;

  try {
    const selftest = await Promise.race([
      httpGetJson(`${baseURL}/selftestz`),
      new Promise((_, reject) => setTimeout(() => reject(new Error("selftest hung")), 500)),
    ]);
    const dockSubscribe = selftest.routes.find((route) => route.route === ROUTE_NAMES.dockSubscribe);

    assert.equal(selftest.ok, true);
    assert.equal(dockSubscribe.ok, true);
    assert.equal(dockSubscribe.note, "passive state health read; dock/subscribe not called");
    assert.equal(dockSubscribe.failureCategory, undefined);
    assert.equal(dockSubscribe.timeoutMs, undefined);
  } finally {
    await relay.close();
  }
});

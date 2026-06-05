import assert from "node:assert/strict";
import test from "node:test";

import { RELAY_STATE_STREAM_SCHEMA_VERSION } from "./dock-relay-constants.mjs";
import { threadCardDisplayOrderKey } from "./dock-relay-projection-engine.mjs";
import { RelayStateEngine } from "./dock-relay-state-engine.mjs";
import { NotificationIngestor } from "./dock-relay-state-ingest.mjs";
import { StateSubscriptionHub } from "./dock-relay-state-subscriptions.mjs";

function sleep(ms) {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

function heartbeatForView(store) {
  return (view, { epoch }) => ({
    kind: "heartbeat",
    schemaVersion: RELAY_STATE_STREAM_SCHEMA_VERSION,
    identityVersion: 1,
    projectionEngineVersion: 1,
    sourceHostID: "home",
    view,
    scope: "view",
    viewParamsKey: `${view}:home`,
    order: "displayOrderKeyAscending",
    epoch,
    seq: store.currentSeq(),
    complete: true,
    totalRows: 0,
    window: {
      offset: 0,
      limit: 0,
      rowCount: 0,
      totalRows: 0,
      nextOffset: null,
    },
    freshness: { status: "fresh" },
  });
}

function testDockCard({
  hostID = "home",
  threadID,
  status,
  activityAtMs,
}) {
  const projectionID = `host:${hostID}/thread:${threadID}/row:threadCard`;
  return {
    id: projectionID,
    schemaVersion: 1,
    identityVersion: 1,
    projectionEngineVersion: 1,
    sourceHostID: hostID,
    view: "dock",
    projectionID,
    sourceRef: `host:${hostID}/thread:${threadID}`,
    rowRole: "threadCard",
    displayOrderKey: threadCardDisplayOrderKey({ activityAtMs, status, projectionID }),
    logicalHostID: hostID,
    threadID,
    backendSessionID: threadID,
    hostDisplayName: "Home",
    hostEndpoint: null,
    activityAt: new Date(activityAtMs).toISOString(),
    activityAtMs,
    displaySummary: `summary-${threadID}`,
    title: `title-${threadID}`,
    status,
    sourceKind: "human",
    lane: "human",
    relationship: "root",
    forkedFromID: null,
    archiveState: "active",
    freshness: "fresh",
    completeness: "complete",
    repository: "repo",
    workingDirectory: "/repo",
    branch: "main",
    summarySource: "title",
  };
}

test("StateSubscriptionHub emits heartbeat while subscribed and stops when idle", async () => {
  let seq = 7;
  let currentSeqCalls = 0;
  const store = {
    currentSeq() {
      currentSeqCalls += 1;
      return seq;
    },
  };
  const hub = new StateSubscriptionHub({
    store,
    snapshotForView: () => ({}),
    heartbeatForView: heartbeatForView(store),
    heartbeatIntervalMs: 5,
  });
  const received = [];
  const unsubscribe = hub.subscribe("dock", (update) => {
    received.push(update);
  });

  await sleep(25);
  assert.ok(received.length >= 2);
  for (const update of received) {
    assert.equal(update.kind, "heartbeat");
    assert.equal(update.schemaVersion, RELAY_STATE_STREAM_SCHEMA_VERSION);
    assert.equal(update.view, "dock");
    assert.equal(update.seq, 7);
    assert.equal("stateGeneration" in update, false);
    assert.equal("baseSeq" in update, false);
    assert.equal(update.freshness.status, "fresh");
  }

  seq = 8;
  unsubscribe();
  const countAfterUnsubscribe = received.length;
  await sleep(25);
  assert.equal(received.length, countAfterUnsubscribe);
  assert.ok(currentSeqCalls > 0);
});

test("StateSubscriptionHub heartbeat is per subscribed view", async () => {
  const store = {
    currentSeq() {
      return 3;
    },
  };
  const hub = new StateSubscriptionHub({
    store,
    snapshotForView: () => ({}),
    heartbeatForView: heartbeatForView(store),
    heartbeatIntervalMs: 5,
  });
  const dockUpdates = [];
  const archiveUpdates = [];
  const unsubscribeDock = hub.subscribe("dock", (update) => dockUpdates.push(update));
  const unsubscribeArchive = hub.subscribe("archive", (update) => archiveUpdates.push(update));

  await sleep(20);
  unsubscribeDock();
  unsubscribeArchive();

  assert.ok(dockUpdates.length > 0);
  assert.ok(archiveUpdates.length > 0);
  assert.equal(dockUpdates.every((update) => update.view === "dock"), true);
  assert.equal(archiveUpdates.every((update) => update.view === "archive"), true);
});

test("StateSubscriptionHub default heartbeat uses per-view sequence", async () => {
  const store = {
    currentSeq() {
      return 99;
    },
    currentSeqForView(view) {
      return view === "archive" ? 11 : 7;
    },
  };
  const hub = new StateSubscriptionHub({
    store,
    snapshotForView: () => ({}),
    heartbeatIntervalMs: 5,
  });
  const dockUpdates = [];
  const archiveUpdates = [];
  const unsubscribeDock = hub.subscribe("dock", (update) => dockUpdates.push(update));
  const unsubscribeArchive = hub.subscribe("archive", (update) => archiveUpdates.push(update));

  await sleep(20);
  unsubscribeDock();
  unsubscribeArchive();

  assert.ok(dockUpdates.length > 0);
  assert.ok(archiveUpdates.length > 0);
  assert.equal(dockUpdates.every((update) => update.seq === 7), true);
  assert.equal(archiveUpdates.every((update) => update.seq === 11), true);
});

test("dock subscribe overlays fresh live cache status before returning the first snapshot", async () => {
  const dormantLiveCard = testDockCard({
    threadID: "live-thread",
    status: "dormant",
    activityAtMs: 1_000,
  });
  const idleCard = testDockCard({
    threadID: "idle-thread",
    status: "idle",
    activityAtMs: 2_000,
  });
  let liveCacheRefreshed = false;
  const engine = new RelayStateEngine(
    {
      hostId: "home",
      hostName: "Home",
      logger: null,
      liveStatusCache: {
        async snapshotForRouting() {
          liveCacheRefreshed = true;
          return this.snapshot();
        },
        snapshot() {
          return {
            checkedAt: "2026-06-04T00:00:00.000Z",
            checkedAtMs: Date.now(),
            ok: liveCacheRefreshed,
            status: liveCacheRefreshed ? "up" : "unknown",
            endpoints: [{ url: "ws://127.0.0.1:4500" }],
            failedEndpoints: 0,
            rows: liveCacheRefreshed ? [{
              id: "live-thread",
              sessionId: "live-session",
              status: { type: "active", activeFlags: [] },
              updatedAt: "1970-01-01T00:00:03.000Z",
            }] : [],
            error: null,
            liveOverlay: {
              ok: liveCacheRefreshed,
              state: liveCacheRefreshed ? "ready" : "disabled",
              ageMs: 0,
              endpoints: liveCacheRefreshed ? 1 : 0,
              failedEndpoints: 0,
              rows: liveCacheRefreshed ? 1 : 0,
            },
          };
        },
      },
    },
    {
      store: {
        currentSeq() {
          return 1;
        },
        currentSeqForView() {
          return 1;
        },
        freshnessForHost(_hostID, { archived }) {
          assert.equal(archived, false);
          return { status: "fresh", lastError: null };
        },
        cardTruthCompleteForHost(_hostID, { archived }) {
          assert.equal(archived, false);
          return true;
        },
        listDockCards({ offset = 0, limit = 500 }) {
          const cards = [dormantLiveCard, idleCard]
            .sort((left, right) => left.displayOrderKey.localeCompare(right.displayOrderKey));
          return {
            cards: cards.slice(offset, offset + limit),
            totalRows: cards.length,
          };
        },
        close() {},
      },
    },
  );
  const session = {};
  const snapshot = await engine.subscribeDock({
    session,
    downstreamWs: {},
    sendJson() {},
  });
  session.dockUnsubscribe?.();
  await engine.close();

  assert.equal(liveCacheRefreshed, true);
  assert.equal(snapshot.rows[0].threadID, "live-thread");
  assert.equal(snapshot.rows[0].status, "running");
  assert.equal(snapshot.rows[0].backendSessionID, "live-session");
  assert.equal(snapshot.rows[0].activityAtMs, 3_000);
});

test("dock subscribe overlays hidden child rollups before returning the first snapshot", async () => {
  const parentCard = testDockCard({
    threadID: "parent-thread",
    status: "idle",
    activityAtMs: 1_000,
  });
  let liveCacheRefreshed = false;
  const engine = new RelayStateEngine(
    {
      hostId: "home",
      hostName: "Home",
      logger: null,
      liveStatusCache: {
        async snapshotForRouting() {
          liveCacheRefreshed = true;
          return this.snapshot();
        },
        snapshot() {
          return {
            checkedAt: "2026-06-04T00:00:00.000Z",
            checkedAtMs: Date.now(),
            ok: liveCacheRefreshed,
            status: liveCacheRefreshed ? "up" : "unknown",
            endpoints: [{ url: "ws://127.0.0.1:4500" }],
            failedEndpoints: 0,
            rows: [],
            rollupRows: liveCacheRefreshed ? [{
              id: "hidden-child",
              sessionId: "hidden-child-session",
              dockRelayRollupTargetThreadID: "parent-thread",
              status: { type: "active", activeFlags: [] },
              updatedAt: "1970-01-01T00:00:04.000Z",
            }] : [],
            error: null,
            liveOverlay: {
              ok: liveCacheRefreshed,
              state: liveCacheRefreshed ? "ready" : "disabled",
              ageMs: 0,
              endpoints: liveCacheRefreshed ? 1 : 0,
              failedEndpoints: 0,
              rows: 0,
            },
          };
        },
      },
    },
    {
      store: {
        currentSeq() {
          return 1;
        },
        currentSeqForView() {
          return 1;
        },
        freshnessForHost(_hostID, { archived }) {
          assert.equal(archived, false);
          return { status: "fresh", lastError: null };
        },
        cardTruthCompleteForHost(_hostID, { archived }) {
          assert.equal(archived, false);
          return true;
        },
        listDockCards({ offset = 0, limit = 500 }) {
          return {
            cards: [parentCard].slice(offset, offset + limit),
            totalRows: 1,
          };
        },
        close() {},
      },
    },
  );
  const session = {};
  const snapshot = await engine.subscribeDock({
    session,
    downstreamWs: {},
    sendJson() {},
  });
  session.dockUnsubscribe?.();
  await engine.close();

  assert.equal(liveCacheRefreshed, true);
  assert.equal(snapshot.rows.length, 1);
  assert.equal(snapshot.rows[0].threadID, "parent-thread");
  assert.equal(snapshot.rows[0].status, "running");
  assert.equal(snapshot.rows[0].backendSessionID, "parent-thread");
  assert.equal(snapshot.rows[0].activityAtMs, 4_000);
});

test("archive mutations reconcile and publish dock and archive views", async () => {
  const calls = [];
  const engine = new RelayStateEngine(
    { hostId: "home", logger: null },
    {
      store: {
        currentSeq() {
          return 1;
        },
        close() {},
      },
    },
  );
  engine.reconcileDock = async ({ reason }) => {
    calls.push({ view: "dock", reason });
    return { seq: 2 };
  };
  engine.reconcileArchive = async ({ reason }) => {
    calls.push({ view: "archive", reason });
    return { seq: 3 };
  };

  const result = await engine.handleArchiveMutation({ threadId: "thread-1", archived: true });

  assert.deepEqual(calls, [
    { view: "dock", reason: "thread/archive" },
    { view: "archive", reason: "thread/archive" },
  ]);
  assert.equal(result.reason, "thread/archive");
  assert.deepEqual(result.dock, { seq: 2 });
  assert.deepEqual(result.archive, { seq: 3 });
});

test("thread name mutations reconcile and publish dock and archive views", async () => {
  const calls = [];
  const engine = new RelayStateEngine(
    { hostId: "home", logger: null },
    {
      store: {
        currentSeq() {
          return 1;
        },
        close() {},
      },
    },
  );
  engine.reconcileDock = async ({ reason }) => {
    calls.push({ view: "dock", reason });
    return { seq: 4 };
  };
  engine.reconcileArchive = async ({ reason }) => {
    calls.push({ view: "archive", reason });
    return { seq: 5 };
  };

  const result = await engine.handleThreadNameMutation({ threadId: "thread-1" });

  assert.deepEqual(calls, [
    { view: "dock", reason: "thread/name/set" },
    { view: "archive", reason: "thread/name/set" },
  ]);
  assert.equal(result.reason, "thread/name/set");
  assert.deepEqual(result.dock, { seq: 4 });
  assert.deepEqual(result.archive, { seq: 5 });
});

test("thread/name/updated notifications are parsed as thread-name invalidations", () => {
  const ingestor = new NotificationIngestor({ store: {}, hostId: "home" });

  assert.deepEqual(ingestor.ingestThreadNameUpdated({
    method: "thread/name/updated",
    params: {
      threadId: "thread-1",
      threadName: "Server title",
    },
  }), {
    threadId: "thread-1",
    reason: "thread/name/updated",
  });
  assert.equal(ingestor.ingestThreadNameUpdated({
    method: "thread/status/changed",
    params: { threadId: "thread-1" },
  }), null);
  assert.equal(ingestor.ingestThreadNameUpdated({
    method: "thread/name/updated",
    params: { threadName: "Missing id" },
  }), null);
});

test("thread/status/changed notifications are parsed as status invalidations", () => {
  const ingestor = new NotificationIngestor({ store: {}, hostId: "home" });

  assert.deepEqual(ingestor.ingestThreadStatusChanged({
    method: "thread/status/changed",
    params: {
      threadId: "thread-1",
      status: { type: "active", activeFlags: [] },
    },
  }), {
    threadId: "thread-1",
    reason: "thread/status/changed",
  });
  assert.equal(ingestor.ingestThreadStatusChanged({
    method: "thread/name/updated",
    params: { threadId: "thread-1" },
  }), null);
  assert.equal(ingestor.ingestThreadStatusChanged({
    method: "thread/status/changed",
    params: { status: { type: "active", activeFlags: [] } },
  }), null);
});

test("thread/name/updated notifications reconcile and publish dock and archive views", async () => {
  const calls = [];
  const engine = new RelayStateEngine(
    { hostId: "home", logger: null },
    {
      store: {
        currentSeq() {
          return 1;
        },
        close() {},
      },
    },
  );
  engine.reconcileDock = async ({ reason }) => {
    calls.push({ view: "dock", reason });
    return { seq: 6 };
  };
  engine.reconcileArchive = async ({ reason }) => {
    calls.push({ view: "archive", reason });
    return { seq: 7 };
  };

  const result = await engine.handleThreadNameNotification({
    method: "thread/name/updated",
    params: {
      threadId: "thread-1",
      threadName: "Server title",
    },
  });

  assert.deepEqual(calls, [
    { view: "dock", reason: "thread/name/updated" },
    { view: "archive", reason: "thread/name/updated" },
  ]);
  assert.equal(result.reason, "thread/name/updated");
  assert.deepEqual(result.dock, { seq: 6 });
  assert.deepEqual(result.archive, { seq: 7 });
});

test("thread/status/changed notifications reconcile dock cards without refreshing archive", async () => {
  const calls = [];
  const engine = new RelayStateEngine(
    { hostId: "home", logger: null },
    {
      store: {
        currentSeq() {
          return 1;
        },
        close() {},
      },
    },
  );
  engine.reconcileDock = async ({ reason }) => {
    calls.push({ view: "dock", reason });
    return { seq: 8 };
  };
  engine.reconcileArchive = async ({ reason }) => {
    calls.push({ view: "archive", reason });
    return { seq: 9 };
  };

  const result = await engine.handleThreadStatusNotification({
    method: "thread/status/changed",
    params: {
      threadId: "thread-1",
      status: { type: "active", activeFlags: [] },
    },
  });

  assert.deepEqual(calls, [
    { view: "dock", reason: "thread/status/changed" },
  ]);
  assert.equal(result.reason, "thread/status/changed");
  assert.deepEqual(result.dock, { seq: 8 });
  assert.equal("archive" in result, false);
});

test("thread/name/updated reconcile failures do not log raw thread names", async () => {
  const warnings = [];
  const rawThreadName = "Raw server rename title that must not be logged";
  const engine = new RelayStateEngine(
    {
      hostId: "home",
      logger: {
        warn(event, fields) {
          warnings.push({ event, fields });
        },
      },
    },
    {
      store: {
        currentSeq() {
          return 1;
        },
        close() {},
      },
    },
  );
  engine.reconcileDock = async () => {
    throw new Error("dock reconcile failed");
  };
  engine.reconcileArchive = async ({ reason }) => ({ seq: 8, reason });

  await assert.rejects(
    () => engine.handleThreadNameNotification({
      method: "thread/name/updated",
      params: {
        threadId: "thread-1",
        threadName: rawThreadName,
      },
    }),
    /dock reconcile failed/u
  );

  assert.ok(warnings.some((entry) => entry.event === "state.thread_name_mutation_reconcile_failed"));
  assert.equal(JSON.stringify(warnings).includes(rawThreadName), false);
});

test("RelayStateEngine treats a fresh empty dock view as complete instead of reconciling forever", () => {
  const engine = new RelayStateEngine(
    { hostId: "home", logger: null },
    {
      store: {
        currentSeq() {
          return 1;
        },
        currentSeqForView() {
          return 1;
        },
        freshnessForHost(_hostID, { archived }) {
          assert.equal(archived, false);
          return { status: "fresh", lastError: null };
        },
        close() {},
      },
    },
  );

  assert.equal(engine.shouldReconcileAfterResponse({ archived: false }), false);
});

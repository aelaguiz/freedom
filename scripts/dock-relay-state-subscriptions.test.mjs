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

test("dock subscribe uses committed projection instead of live cache overlay", async () => {
  const dormantLiveCard = testDockCard({
    threadID: "live-thread",
    status: "dormant",
    activityAtMs: 1_000,
  });
  const refreshedLiveCard = {
    ...testDockCard({
      threadID: "live-thread",
      status: "running",
      activityAtMs: 3_000,
    }),
    backendSessionID: "live-session",
  };
  const idleCard = testDockCard({
    threadID: "idle-thread",
    status: "idle",
    activityAtMs: 2_000,
  });
  let liveCacheRefreshed = false;
  let projectionRefreshed = false;
  const reconcileCalls = [];
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
          return projectionRefreshed ? 2 : 1;
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
          const cards = [projectionRefreshed ? refreshedLiveCard : dormantLiveCard, idleCard]
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
  engine.reconcileDock = async ({ reason }) => {
    reconcileCalls.push(reason);
    projectionRefreshed = true;
    return { seq: 2, rows: [refreshedLiveCard], projectionIDs: [], changed: true };
  };
  const session = {};
  const snapshot = await engine.subscribeDock({
    session,
    downstreamWs: {},
    sendJson() {},
  });
  session.dockUnsubscribe?.();
  await engine.close();

  assert.equal(liveCacheRefreshed, true);
  assert.deepEqual(reconcileCalls, ["dock/subscribe:pre_snapshot"]);
  const liveThread = snapshot.rows.find((card) => card.threadID === "live-thread");
  assert.equal(liveThread?.status, "running");
  assert.equal(liveThread?.backendSessionID, "live-session");
  assert.equal(liveThread?.activityAtMs, 3_000);
});

test("dock subscribe uses committed projection instead of hidden child rollup overlay", async () => {
  const parentCard = testDockCard({
    threadID: "parent-thread",
    status: "idle",
    activityAtMs: 1_000,
  });
  let liveCacheRefreshed = false;
  let projectionRefreshed = false;
  const reconcileCalls = [];
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
          return projectionRefreshed ? 2 : 1;
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
  engine.reconcileDock = async ({ reason }) => {
    reconcileCalls.push(reason);
    projectionRefreshed = true;
    return { seq: 2, rows: [parentCard], projectionIDs: [], changed: true };
  };
  const session = {};
  const snapshot = await engine.subscribeDock({
    session,
    downstreamWs: {},
    sendJson() {},
  });
  session.dockUnsubscribe?.();
  await engine.close();

  assert.equal(liveCacheRefreshed, true);
  assert.deepEqual(reconcileCalls, ["dock/subscribe:pre_snapshot"]);
  assert.equal(snapshot.rows.length, 1);
  assert.equal(snapshot.rows[0].threadID, "parent-thread");
  assert.equal(snapshot.rows[0].status, "idle");
  assert.equal(snapshot.rows[0].backendSessionID, "parent-thread");
  assert.equal(snapshot.rows[0].activityAtMs, 1_000);
});

test("archive mutations move one card without broad dock/archive reconcile", async () => {
  const calls = [];
  const engine = new RelayStateEngine(
    { hostId: "home", logger: null },
    {
      store: {
        currentSeq() {
          return 1;
        },
        applyThreadArchiveMove({ threadID, archived, reason }) {
          calls.push({ action: "targeted-archive-move", threadID, archived, reason });
          return {
            dock: { view: "dock", seq: 2, rows: [], projectionIDs: ["host:home/thread:thread-1/row:threadCard"], changed: true },
            archive: { view: "archive", seq: 3, rows: [{ threadID }], projectionIDs: [], changed: true },
            missing: false,
          };
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
  engine.publishTargetedArchiveMove = async (_move, reason) => {
    calls.push({ action: "publish-targeted-archive-move", reason });
  };

  const result = await engine.handleArchiveMutation({ threadId: "thread-1", archived: true });

  assert.deepEqual(calls, [
    { action: "targeted-archive-move", threadID: "thread-1", archived: true, reason: "thread/archive" },
    { action: "publish-targeted-archive-move", reason: "thread/archive" },
  ]);
  assert.equal(result.reason, "thread/archive");
  assert.equal(result.path, "targeted_archive_move");
});

test("thread name mutations patch one card without broad dock/archive reconcile", async () => {
  const calls = [];
  const engine = new RelayStateEngine(
    { hostId: "home", logger: null },
    {
      store: {
        currentSeq() {
          return 1;
        },
        applyThreadCardPatch({ threadID, patch, reason }) {
          calls.push({ action: "targeted-card-patch", threadID, patch, reason });
          return {
            view: "dock",
            seq: 4,
            rows: [{ threadID, title: patch.title }],
            projectionIDs: [],
            changed: true,
            missing: false,
          };
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
  engine.publishTargetedCardResult = async (_result, { view, reason }) => {
    calls.push({ action: "publish-targeted-card", view, reason });
  };

  const result = await engine.handleThreadNameMutation({ threadId: "thread-1", name: "New title" });

  assert.deepEqual(calls, [
    { action: "targeted-card-patch", threadID: "thread-1", patch: { title: "New title" }, reason: "thread/name/set" },
    { action: "publish-targeted-card", view: "dock", reason: "thread/name/set" },
  ]);
  assert.equal(result.reason, "thread/name/set");
  assert.equal(result.path, "direct_patch");
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

test("thread/name/updated notifications patch one card without broad reconcile", async () => {
  const calls = [];
  const engine = new RelayStateEngine(
    { hostId: "home", logger: null },
    {
      store: {
        currentSeq() {
          return 1;
        },
        applyThreadCardPatch({ threadID, patch, reason }) {
          calls.push({ action: "targeted-card-patch", threadID, patch, reason });
          return {
            view: "dock",
            seq: 6,
            rows: [{ threadID, title: patch.title }],
            projectionIDs: [],
            changed: true,
            missing: false,
          };
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
  engine.publishTargetedCardResult = async (_result, { view, reason }) => {
    calls.push({ action: "publish-targeted-card", view, reason });
  };

  const result = await engine.handleThreadNameNotification({
    method: "thread/name/updated",
    params: {
      threadId: "thread-1",
      threadName: "Server title",
    },
  });

  assert.deepEqual(calls, [
    { action: "targeted-card-patch", threadID: "thread-1", patch: { title: "Server title" }, reason: "thread/name/updated" },
    { action: "publish-targeted-card", view: "dock", reason: "thread/name/updated" },
  ]);
  assert.equal(result.reason, "thread/name/updated");
  assert.equal(result.path, "direct_patch");
});

test("thread/status/changed notifications patch one card without broad reconcile", async () => {
  const calls = [];
  const engine = new RelayStateEngine(
    { hostId: "home", logger: null },
    {
      store: {
        currentSeq() {
          return 1;
        },
        applyThreadCardPatch({ threadID, patch, reason }) {
          calls.push({ action: "targeted-card-patch", threadID, patch, reason });
          return {
            view: "dock",
            seq: 8,
            rows: [{ threadID, status: patch.status }],
            projectionIDs: [],
            changed: true,
            missing: false,
          };
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
  engine.publishTargetedCardResult = async (_result, { view, reason }) => {
    calls.push({ action: "publish-targeted-card", view, reason });
  };

  const result = await engine.handleThreadStatusNotification({
    method: "thread/status/changed",
    params: {
      threadId: "thread-1",
      status: { type: "active", activeFlags: [] },
    },
  });

  assert.deepEqual(calls, [
    { action: "targeted-card-patch", threadID: "thread-1", patch: { status: "running" }, reason: "thread/status/changed" },
    { action: "publish-targeted-card", view: "dock", reason: "thread/status/changed" },
  ]);
  assert.equal(result.reason, "thread/status/changed");
  assert.equal(result.path, "direct_patch");
});

test("thread/name/updated ignores hidden scoped cards instead of reviving them", async () => {
  const calls = [];
  const engine = new RelayStateEngine(
    { hostId: "home", logger: null },
    {
      store: {
        currentSeq() {
          return 1;
        },
        applyThreadCardPatch({ threadID, patch, reason }) {
          calls.push({ action: "targeted-card-patch", threadID, patch, reason });
          return {
            view: null,
            seq: null,
            rows: [],
            projectionIDs: [],
            changed: false,
            missing: true,
            hidden: true,
          };
        },
        cardForThread() {
          throw new Error("hidden patched card should not fall through to thread/read");
        },
        close() {},
      },
    },
  );
  engine.publishTargetedCardResult = async () => {
    calls.push({ action: "publish-targeted-card" });
  };

  const result = await engine.handleThreadNameNotification({
    method: "thread/name/updated",
    params: {
      threadId: "thread-1",
      threadName: "Server title",
    },
  });

  assert.deepEqual(calls, [
    { action: "targeted-card-patch", threadID: "thread-1", patch: { title: "Server title" }, reason: "thread/name/updated" },
  ]);
  assert.equal(result.reason, "thread/name/updated");
  assert.equal(result.path, "hidden_card_ignored");
});

test("thread dirty targeted updates ignore hidden scoped cards instead of reviving them", async () => {
  const calls = [];
  const engine = new RelayStateEngine(
    { hostId: "home", logger: null },
    {
      store: {
        currentSeq() {
          return 1;
        },
        cardForThread({ threadID, visibleOnly }) {
          calls.push({ action: "card-for-thread", threadID, visibleOnly });
          return visibleOnly
            ? null
            : {
                threadID,
                archiveState: "active",
              };
        },
        close() {},
      },
    },
  );

  const result = await engine.updateThreadCardFromEvent({
    threadId: "thread-1",
    reason: "turn/started",
  });

  assert.deepEqual(calls, [
    { action: "card-for-thread", threadID: "thread-1", visibleOnly: true },
    { action: "card-for-thread", threadID: "thread-1", visibleOnly: false },
  ]);
  assert.equal(result.reason, "turn/started");
  assert.equal(result.path, "hidden_card_ignored");
});

test("archive mutations ignore hidden scoped cards instead of reviving them", async () => {
  const calls = [];
  const engine = new RelayStateEngine(
    { hostId: "home", logger: null },
    {
      store: {
        currentSeq() {
          return 1;
        },
        applyThreadArchiveMove({ threadID, archived, reason }) {
          calls.push({ action: "targeted-archive-move", threadID, archived, reason });
          return {
            dock: { view: "dock", seq: 1, rows: [], projectionIDs: [], changed: false, missing: true },
            archive: { view: "archive", seq: 1, rows: [], projectionIDs: [], changed: false, missing: true },
            missing: true,
            hidden: true,
          };
        },
        close() {},
      },
    },
  );

  const result = await engine.handleArchiveMutation({ threadId: "thread-1", archived: true });

  assert.deepEqual(calls, [
    { action: "targeted-archive-move", threadID: "thread-1", archived: true, reason: "thread/archive" },
  ]);
  assert.equal(result.reason, "thread/archive");
  assert.equal(result.path, "hidden_card_ignored");
});

test("thread dirty notifications coalesce to one targeted read per thread", async () => {
  const calls = [];
  const engine = new RelayStateEngine(
    { hostId: "home", logger: null, relayStateTargetedDirtyDebounceMs: 5 },
    {
      store: {
        currentSeq() {
          return 1;
        },
        close() {},
      },
    },
  );
  engine.updateThreadCardFromEvent = async ({ threadId, reason }) => {
    calls.push({ threadId, reason });
    return { threadId, reason };
  };

  try {
    engine.handleThreadDirtyNotification({
      method: "turn/started",
      params: { threadId: "thread-1" },
    });
    engine.handleThreadDirtyNotification({
      method: "item/completed",
      params: { threadId: "thread-1" },
    });
    await sleep(30);

    assert.deepEqual(calls, [{ threadId: "thread-1", reason: "item/completed" }]);
  } finally {
    await engine.close();
  }
});

test("thread/name/updated targeted failures do not log raw thread names", async () => {
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
        applyThreadCardPatch() {
          throw new Error("targeted patch failed");
        },
        close() {},
      },
    },
  );

  await assert.rejects(
    () => engine.handleThreadNameNotification({
      method: "thread/name/updated",
      params: {
        threadId: "thread-1",
        threadName: rawThreadName,
      },
    }),
    /targeted patch failed/u
  );

  assert.ok(warnings.length === 0);
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

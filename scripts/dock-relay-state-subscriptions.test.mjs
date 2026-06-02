import assert from "node:assert/strict";
import test from "node:test";

import { RELAY_STATE_STREAM_SCHEMA_VERSION } from "./dock-relay-constants.mjs";
import { RelayStateEngine } from "./dock-relay-state-engine.mjs";
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

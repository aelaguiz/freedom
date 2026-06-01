import assert from "node:assert/strict";
import test from "node:test";

import {
  applyDockPayload,
  compareDockStates,
  emptyDockStreamState,
  parseArgs,
  sanitizeDockSnapshotForReport,
} from "./dock-relay-sync-audit.mjs";

const emptyWindow = {
  offset: 0,
  limit: 0,
  rowCount: 0,
  totalRows: 0,
  nextOffset: null,
};

function snapshot(overrides = {}) {
  return {
    kind: "snapshot",
    schemaVersion: 2,
    epoch: "epoch-1",
    seq: 7,
    view: "dock",
    complete: true,
    totalRows: 0,
    window: emptyWindow,
    freshness: { status: "fresh" },
    hosts: [],
    cards: [],
    ...overrides,
  };
}

test("sync audit applies heartbeat as stream state instead of requiring resync", () => {
  const state = emptyDockStreamState();
  assert.deepEqual(applyDockPayload(state, snapshot()), []);

  const findings = applyDockPayload(state, {
    kind: "heartbeat",
    schemaVersion: 2,
    epoch: "epoch-1",
    seq: 7,
    view: "dock",
    complete: false,
    totalRows: 0,
    window: emptyWindow,
    freshness: { status: "stale", lastError: "fixture stale" },
  });

  assert.deepEqual(findings, []);
  assert.equal(state.needsResync, false);
  assert.equal(state.lastPayloadKind, "heartbeat");
  assert.equal(state.complete, false);
  assert.deepEqual(state.freshness, { status: "stale", lastError: "fixture stale" });
});

test("sync audit flags heartbeat sequence gaps", () => {
  const state = emptyDockStreamState();
  assert.deepEqual(applyDockPayload(state, snapshot()), []);

  const findings = applyDockPayload(state, {
    kind: "heartbeat",
    schemaVersion: 2,
    epoch: "epoch-1",
    seq: 8,
    view: "dock",
    complete: true,
    totalRows: 0,
    window: emptyWindow,
    freshness: { status: "fresh" },
  });

  assert.equal(state.needsResync, true);
  assert.equal(findings.some((finding) => finding.code === "dock_stream_heartbeat_sequence_gap"), true);
});

test("sync audit accepts per-view sequence jumps when baseSeq matches", () => {
  const state = emptyDockStreamState();
  assert.deepEqual(applyDockPayload(state, snapshot({ seq: 7 })), []);

  const findings = applyDockPayload(state, {
    kind: "delta",
    schemaVersion: 2,
    epoch: "epoch-1",
    baseSeq: 7,
    seq: 9,
    view: "dock",
    complete: true,
    totalRows: 0,
    window: emptyWindow,
    freshness: { status: "fresh" },
    upsertCards: [],
    deleteCardIDs: [],
  });

  assert.deepEqual(findings, []);
  assert.equal(state.needsResync, false);
  assert.equal(state.seq, 9);
});

test("sync audit compares long-lived stream freshness to fresh snapshots", () => {
  const comparison = compareDockStates(
    snapshot({ freshness: { status: "stale", lastError: "old proof" } }),
    snapshot({ freshness: { status: "fresh", lastError: null } }),
  );

  assert.equal(comparison.ok, false);
  assert.equal(comparison.findings.some((finding) => finding.code === "dock_stream_freshness_mismatch"), true);
});

test("sync audit ignores freshness timestamp churn when status and error match", () => {
  const comparison = compareDockStates(
    snapshot({ freshness: { status: "fresh", lastAttemptAt: "2026-06-01T00:00:00.000Z", lastError: null } }),
    snapshot({ freshness: { status: "fresh", lastAttemptAt: "2026-06-01T00:00:01.000Z", lastError: null } }),
  );

  assert.equal(comparison.ok, true);
});

test("sync audit report sanitizer preserves relay ordering fields", () => {
  const reportSnapshot = sanitizeDockSnapshotForReport(snapshot({
    totalRows: 1,
    window: {
      offset: 0,
      limit: 1,
      rowCount: 1,
      nextOffset: null,
    },
    cards: [{
      id: "host::thread-a",
      logicalHostID: "host",
      threadID: "thread-a",
      status: "idle",
      lane: "human",
      sourceKind: "human",
      activityAt: "2026-06-01T00:00:00.000Z",
      activityAtMs: 1_780_272_000_000,
      orderKey: "9005418977250991:thread-a",
    }],
  }));

  assert.equal(reportSnapshot.cards[0].orderKey, "9005418977250991:thread-a");
  assert.equal(reportSnapshot.cards[0].activityAtMs, 1_780_272_000_000);
  assert.deepEqual(reportSnapshot.renderOrderCardIDs, ["host::thread-a"]);
});

test("sync audit rejects raw app-server relay URLs", () => {
  assert.throws(
    () => parseArgs(["--relay-url", "ws://127.0.0.1:4500"]),
    /Dock relay, not the raw app-server :4500/u,
  );
});

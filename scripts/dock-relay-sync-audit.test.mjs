import assert from "node:assert/strict";
import crypto from "node:crypto";
import test from "node:test";

import {
  applyDockPayload,
  compareDockStates,
  compareDockThreadCard,
  emptyDockStreamState,
  evaluateStreamConvergenceLag,
  parseArgs,
  sanitizeDockSnapshotForReport,
  selectDetailTargets,
  selectScenarioRenameTarget,
  scenarioLagSummary,
  summarizeClientPathEvents,
} from "./dock-relay-sync-audit.mjs";
import { RELAY_STATE_STREAM_SCHEMA_VERSION } from "./dock-relay-constants.mjs";
import {
  PROJECTION_ENGINE_VERSION,
  PROJECTION_IDENTITY_VERSION,
  PROJECTION_SCHEMA_VERSION,
  projectionIDForThreadCard,
} from "./dock-relay-projection-engine.mjs";

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
    schemaVersion: RELAY_STATE_STREAM_SCHEMA_VERSION,
    epoch: "epoch-1",
    seq: 7,
    generation: 1,
    view: "dock",
    complete: true,
    totalRows: 0,
    window: emptyWindow,
    freshness: { status: "fresh" },
    hosts: [],
    rows: [],
    ...overrides,
  };
}

function threadCard(threadID, order = "001", overrides = {}) {
  const projectionID = projectionIDForThreadCard({ sourceHostID: "host", threadID });
  return {
    id: projectionID,
    projectionID,
    schemaVersion: PROJECTION_SCHEMA_VERSION,
    identityVersion: PROJECTION_IDENTITY_VERSION,
    projectionEngineVersion: PROJECTION_ENGINE_VERSION,
    sourceHostID: "host",
    logicalHostID: "host",
    view: "dock",
    sourceRef: `thread:${threadID}`,
    rowRole: "threadCard",
    threadID,
    status: "idle",
    lane: "human",
    sourceKind: "human",
    activityAt: "2026-06-01T00:00:00.000Z",
    activityAtMs: 1_780_272_000_000,
    displayOrderKey: `${order}|host%3Ahost%2Fthread%3A${threadID}%2Frow%3AthreadCard`,
    ...overrides,
  };
}

test("sync audit applies heartbeat as stream state instead of requiring resync", () => {
  const state = emptyDockStreamState();
  assert.deepEqual(applyDockPayload(state, snapshot()), []);

  const findings = applyDockPayload(state, {
    kind: "heartbeat",
    schemaVersion: RELAY_STATE_STREAM_SCHEMA_VERSION,
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

test("sync audit skips unknown rows when selecting detail proof targets", () => {
  const dockSnapshot = snapshot({
    rows: [
      threadCard("thread-private", "001", { status: "unknown" }),
      threadCard("thread-running", "002", { status: "running" }),
      threadCard("thread-idle", "003", { status: "idle" }),
    ],
  });

  const sampled = selectDetailTargets(dockSnapshot, {
    detail: "sampled",
    detailLimit: 5,
  });
  assert.deepEqual(sampled.map((target) => target.threadID), ["thread-running", "thread-idle"]);

  const all = selectDetailTargets(dockSnapshot, {
    detail: "all",
    detailLimit: 5,
  });
  assert.deepEqual(all.map((target) => target.threadID), ["thread-running", "thread-idle"]);
});

test("sync audit accepts rename-title scenario and counts thread/name/set as client path", () => {
  const options = parseArgs(["--mode", "scenario", "--scenario", "rename-title"]);
  assert.equal(options.scenario, "rename-title");

  const evidence = summarizeClientPathEvents([
    {
      route: "thread/name/set",
      countedAsClientPath: true,
    },
  ]);
  assert.deepEqual(evidence.routes, ["thread/name/set"]);
  assert.deepEqual(evidence.routeCounts, { "thread/name/set": 1 });
});

test("sync audit tracks explicit scenario observation duration", () => {
  const implicit = parseArgs(["--mode", "scenario"]);
  assert.equal(implicit.durationMsExplicit, false);

  const explicit = parseArgs([
    "--mode", "scenario",
    "--duration-ms", "12000",
    "--sample-interval-ms", "250",
  ]);

  assert.equal(explicit.durationMsExplicit, true);
  assert.equal(explicit.durationMs, 12_000);
  assert.equal(explicit.sampleIntervalMs, 250);
});

test("sync audit selects restorable non-private active rows for rename-title", () => {
  const dockSnapshot = snapshot({
    rows: [
      threadCard("thread-private", "001", { status: "unknown", title: "Private row" }),
      threadCard("thread-missing-title", "002", { status: "idle" }),
      threadCard("thread-idle", "003", { status: "idle", title: "Restorable row" }),
    ],
  });

  const target = selectScenarioRenameTarget(dockSnapshot);

  assert.equal(target.threadID, "thread-idle");
  assert.equal(target.title, "Restorable row");
});

test("sync audit sanitizes relay card titles as display-title fingerprints", () => {
  const dockSnapshot = snapshot({
    rows: [
      threadCard("thread-title", "001", { title: "Restorable row " }),
    ],
  });

  const reportSnapshot = sanitizeDockSnapshotForReport(dockSnapshot);
  const title = reportSnapshot.rows[0].title;

  assert.deepEqual(title, {
    kind: "textFingerprint",
    length: "Restorable row".length,
    sha256: crypto.createHash("sha256").update("Restorable row").digest("hex").slice(0, 16),
  });
});

test("scenario lag budgets command transitions from acknowledgement when present", () => {
  const lag = scenarioLagSummary({
    transition: "restore-title",
    startedAtMs: 1_000,
    acknowledgedAtMs: 6_000,
    observedAtMs: 6_020,
    maxStreamLagMs: 2_000,
  });

  assert.equal(lag.lag_change_to_relay_ms, 5_020);
  assert.equal(lag.lag_ack_to_relay_ms, 20);
  assert.equal(lag.observedLagMs, 20);
  assert.equal(lag.ok, true);
  assert.equal(lag.exceeded, false);
});

test("sync audit flags heartbeat sequence gaps", () => {
  const state = emptyDockStreamState();
  assert.deepEqual(applyDockPayload(state, snapshot()), []);

  const findings = applyDockPayload(state, {
    kind: "heartbeat",
    schemaVersion: RELAY_STATE_STREAM_SCHEMA_VERSION,
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

test("sync audit applies canonical upsert updates with contiguous sequence numbers", () => {
  const state = emptyDockStreamState();
  assert.deepEqual(applyDockPayload(state, snapshot({ seq: 7 })), []);

  const findings = applyDockPayload(state, {
    kind: "upsert",
    schemaVersion: RELAY_STATE_STREAM_SCHEMA_VERSION,
    epoch: "epoch-1",
    seq: 8,
    view: "dock",
    complete: true,
    totalRows: 0,
    window: emptyWindow,
    freshness: { status: "fresh" },
    rows: [],
    projectionIDs: [],
  });

  assert.deepEqual(findings, []);
  assert.equal(state.needsResync, false);
  assert.equal(state.seq, 8);
});

test("sync audit applies page catch-up without advancing sequence", () => {
  const state = emptyDockStreamState();
  assert.deepEqual(applyDockPayload(state, snapshot({
    seq: 7,
    complete: false,
    totalRows: 2,
    window: {
      offset: 0,
      limit: 1,
      rowCount: 1,
      totalRows: 2,
      nextOffset: 1,
    },
    rows: [threadCard("thread-a", "001")],
  })), []);

  const findings = applyDockPayload(state, {
    kind: "page",
    schemaVersion: RELAY_STATE_STREAM_SCHEMA_VERSION,
    epoch: "epoch-1",
    seq: 7,
    generation: 1,
    view: "dock",
    complete: true,
    totalRows: 2,
    window: {
      offset: 1,
      limit: 1,
      rowCount: 1,
      totalRows: 2,
      nextOffset: null,
    },
    freshness: { status: "fresh" },
    rows: [threadCard("thread-b", "002")],
    projectionIDs: [],
  });

  assert.deepEqual(findings, []);
  assert.equal(state.needsResync, false);
  assert.equal(state.seq, 7);
  assert.equal(state.lastPayloadKind, "page");
  assert.deepEqual([...state.cardsByID.values()].map((row) => row.threadID).sort(), ["thread-a", "thread-b"]);
});

test("sync audit rejects same-sequence upsert catch-up", () => {
  const state = emptyDockStreamState();
  assert.deepEqual(applyDockPayload(state, snapshot({ seq: 7 })), []);

  const findings = applyDockPayload(state, {
    kind: "upsert",
    schemaVersion: RELAY_STATE_STREAM_SCHEMA_VERSION,
    epoch: "epoch-1",
    seq: 7,
    generation: 1,
    view: "dock",
    complete: false,
    totalRows: 1,
    window: {
      offset: 1,
      limit: 1,
      rowCount: 1,
      totalRows: 1,
      nextOffset: null,
    },
    freshness: { status: "fresh" },
    rows: [threadCard("thread-b", "002")],
    projectionIDs: [],
  });

  assert.equal(state.needsResync, true);
  assert.equal(findings.some((finding) => finding.code === "dock_stream_sequence_gap"), true);
});

test("sync audit clears resync need when a replacement snapshot recovers the stream", () => {
  const state = emptyDockStreamState();
  assert.deepEqual(applyDockPayload(state, snapshot({ seq: 7 })), []);

  const gapFindings = applyDockPayload(state, {
    kind: "upsert",
    schemaVersion: RELAY_STATE_STREAM_SCHEMA_VERSION,
    epoch: "epoch-1",
    seq: 9,
    generation: 1,
    view: "dock",
    complete: true,
    totalRows: 0,
    window: emptyWindow,
    freshness: { status: "fresh" },
    rows: [],
    projectionIDs: [],
  });

  assert.equal(gapFindings.some((finding) => finding.code === "dock_stream_sequence_gap"), true);
  assert.equal(state.needsResync, true);

  const snapshotFindings = applyDockPayload(state, snapshot({
    seq: 9,
    rows: [threadCard("thread-a")],
    totalRows: 1,
    window: {
      offset: 0,
      limit: 1,
      rowCount: 1,
      totalRows: 1,
      nextOffset: null,
    },
  }));

  assert.deepEqual(snapshotFindings, []);
  assert.equal(state.needsResync, false);
  assert.equal(state.seq, 9);
  assert.deepEqual([...state.cardsByID.values()].map((row) => row.threadID), ["thread-a"]);
});

test("sync audit rejects old delta grammar even when baseSeq is present", () => {
  const state = emptyDockStreamState();
  assert.deepEqual(applyDockPayload(state, snapshot({ seq: 7 })), []);

  const findings = applyDockPayload(state, {
    kind: "delta",
    schemaVersion: RELAY_STATE_STREAM_SCHEMA_VERSION,
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

  assert.equal(state.needsResync, true);
  assert.equal(findings.some((finding) => finding.code === "dock_stream_unknown_payload_kind"), true);
});

test("sync audit compares long-lived stream freshness to fresh snapshots", () => {
  const comparison = compareDockStates(
    snapshot({ freshness: { status: "stale", lastError: "old proof" } }),
    snapshot({ freshness: { status: "fresh", lastError: null } }),
  );

  assert.equal(comparison.ok, false);
  assert.equal(comparison.findings.some((finding) => finding.code === "dock_stream_freshness_mismatch"), true);
});

test("sync audit does not count stale fresh snapshots as long-lived stream lag", () => {
  const convergence = evaluateStreamConvergenceLag([
    {
      attempt: 0,
      checkedAt: "2026-06-06T05:19:07.986Z",
      checkedAtMs: 1_780_723_147_986,
      ok: false,
      streamSeq: 4817,
      freshSeq: 4816,
    },
    {
      attempt: 1,
      checkedAt: "2026-06-06T05:19:21.071Z",
      checkedAtMs: 1_780_723_161_071,
      ok: true,
      streamSeq: 4818,
      freshSeq: 4818,
    },
  ], 2_000);

  assert.equal(convergence.ok, true);
  assert.equal(convergence.exceeded, false);
  assert.equal(convergence.observedLagMs, 0);
  assert.equal(convergence.firstMismatchAttempt, null);
  assert.equal(convergence.convergedAttempt, 1);
});

test("sync audit does not claim convergence when only the fresh snapshot is stale", () => {
  const convergence = evaluateStreamConvergenceLag([
    {
      attempt: 0,
      checkedAt: "2026-06-06T05:19:07.986Z",
      checkedAtMs: 1_780_723_147_986,
      ok: false,
      streamSeq: 4817,
      freshSeq: 4816,
    },
    {
      attempt: 1,
      checkedAt: "2026-06-06T05:19:08.986Z",
      checkedAtMs: 1_780_723_148_986,
      ok: false,
      streamSeq: 4818,
      freshSeq: 4817,
    },
  ], 2_000);

  assert.equal(convergence.ok, true);
  assert.equal(convergence.exceeded, false);
  assert.equal(convergence.converged, false);
  assert.equal(convergence.observedLagMs, 0);
  assert.equal(convergence.firstMismatchAttempt, null);
  assert.equal(convergence.convergedAttempt, null);
  assert.equal(convergence.lastCheckedAt, "2026-06-06T05:19:08.986Z");
});

test("sync audit target thread comparison ignores unrelated live row churn", () => {
  const comparison = compareDockThreadCard(
    snapshot({
      rows: [
        threadCard("target", "001", { title: "same" }),
        threadCard("unrelated", "002", { title: "old" }),
      ],
    }),
    snapshot({
      rows: [
        threadCard("target", "001", { title: "same" }),
        threadCard("unrelated", "000", { title: "new" }),
      ],
    }),
    "target",
  );

  assert.equal(comparison.ok, true);
  assert.deepEqual(comparison.findings, []);
});

test("sync audit target thread comparison still fails target payload drift", () => {
  const comparison = compareDockThreadCard(
    snapshot({ rows: [threadCard("target", "001", { title: "old" })] }),
    snapshot({ rows: [threadCard("target", "001", { title: "new" })] }),
    "target",
  );

  assert.equal(comparison.ok, false);
  assert.equal(comparison.findings[0].code, "dock_stream_thread_card_payload_mismatch");
  assert.deepEqual(comparison.findings[0].differingKeys, ["title"]);
});

test("sync audit ignores freshness timestamp churn when status and error match", () => {
  const comparison = compareDockStates(
    snapshot({ freshness: { status: "fresh", lastAttemptAt: "2026-06-01T00:00:00.000Z", lastError: null } }),
    snapshot({ freshness: { status: "fresh", lastAttemptAt: "2026-06-01T00:00:01.000Z", lastError: null } }),
  );

  assert.equal(comparison.ok, true);
});

test("sync audit report sanitizer preserves relay projection display order", () => {
  const projectionID = projectionIDForThreadCard({ sourceHostID: "host", threadID: "thread-a" });
  const displayOrderKey = "9005418977250991|0000000000|9999999999|9999999999|host%3Ahost%2Fthread%3Athread-a%2Frow%3AthreadCard";
  const reportSnapshot = sanitizeDockSnapshotForReport(snapshot({
    totalRows: 1,
    window: {
      offset: 0,
      limit: 1,
      rowCount: 1,
      nextOffset: null,
    },
    rows: [{
      id: projectionID,
      projectionID,
      sourceHostID: "host",
      logicalHostID: "host",
      threadID: "thread-a",
      status: "idle",
      lane: "human",
      sourceKind: "human",
      activityAt: "2026-06-01T00:00:00.000Z",
      activityAtMs: 1_780_272_000_000,
      displayOrderKey,
    }],
  }));

  assert.equal(reportSnapshot.rows[0].displayOrderKey, displayOrderKey);
  assert.equal(reportSnapshot.rows[0].activityAtMs, 1_780_272_000_000);
  assert.equal(reportSnapshot.rows[0].projectionID, projectionID);
  assert.deepEqual(reportSnapshot.renderOrderProjectionIDs, [projectionID]);
});

test("sync audit rejects raw app-server relay URLs", () => {
  assert.throws(
    () => parseArgs(["--relay-url", "ws://127.0.0.1:4500"]),
    /Dock relay, not the raw app-server :4500/u,
  );
});

test("sync audit rejects thread detail read as client path proof", () => {
  const evidence = summarizeClientPathEvents([
    { route: "thread/detail/read", countedAsClientPath: false },
    { route: "thread/detail/subscribe", countedAsClientPath: true },
  ]);

  assert.equal(evidence.routeCounts["thread/detail/read"], undefined);
  assert.equal(evidence.routeCounts["thread/detail/subscribe"], 1);
  assert.deepEqual(evidence.nonClientPathRoutes, [{ route: "thread/detail/read", count: 1 }]);
});

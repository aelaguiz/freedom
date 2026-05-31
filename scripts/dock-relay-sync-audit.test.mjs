import assert from "node:assert/strict";
import test from "node:test";

import {
  applyDockPayload,
  classifyParityForClientContract,
  compareDockStates,
  dockStateFromPayload,
  evaluateStreamConvergenceLag,
  normalizeForComparison,
  parseArgs,
  sanitizeDockSnapshotForReport,
  selectDetailTargets,
  selectScenarioArchiveTarget,
  selectScenarioDetailTarget,
  scenarioLagSummary,
  scenarioRequirementImplemented,
  scenarioTransitionName,
  summarizeClientPathEvents,
  summarizeDetailLiveObservation,
  waitForStreamThreadPresence,
} from "./dock-relay-sync-audit.mjs";

function emptyStreamState() {
  return {
    epoch: null,
    seq: null,
    view: null,
    complete: null,
    totalRows: null,
    window: null,
    freshness: null,
    hosts: [],
    cardsByID: new Map(),
    needsResync: false,
    lastPayloadKind: null,
    lastReceivedAt: null,
  };
}

test("sync audit parseArgs makes exhaustive detail mode include existing parity surfaces", () => {
  const options = parseArgs([
    "--mode", "soak",
    "--duration-ms", "0",
    "--sample-interval-ms", "1",
    "--max-stream-lag-ms", "2000",
    "--exhaustive",
    "--detail", "sampled",
    "--detail-limit", "2",
    "--json-out", "out/report.json",
    "--summary-out", "out/report.md",
  ], {}, "/tmp/codex-client-test");

  assert.equal(options.mode, "soak");
  assert.equal(options.durationMs, 0);
  assert.equal(options.maxStreamLagMs, 2000);
  assert.equal(options.exhaustive, true);
  assert.equal(options.includeThreadReads, true);
  assert.equal(options.includeTurns, true);
  assert.equal(options.includeLoaded, true);
  assert.equal(options.includeGoals, true);
  assert.equal(options.turnItemsView, "full");
  assert.equal(options.detail, "sampled");
  assert.equal(options.detailLimit, 2);
  assert.equal(options.jsonOut, "/tmp/codex-client-test/out/report.json");
  assert.equal(options.summaryOut, "/tmp/codex-client-test/out/report.md");
});

test("sync audit marks slow stream convergence as a lag failure", () => {
  const lag = evaluateStreamConvergenceLag([
    {
      attempt: 0,
      ok: false,
      checkedAt: "2026-05-31T00:00:00.000Z",
      checkedAtMs: 1_000,
    },
    {
      attempt: 1,
      ok: true,
      checkedAt: "2026-05-31T00:00:03.600Z",
      checkedAtMs: 4_600,
    },
  ], 2_000);

  assert.equal(lag.ok, false);
  assert.equal(lag.exceeded, true);
  assert.equal(lag.converged, true);
  assert.equal(lag.observedLagMs, 3_600);
  assert.equal(lag.maxStreamLagMs, 2_000);
});

test("sync audit treats immediate stream agreement as zero lag", () => {
  const lag = evaluateStreamConvergenceLag([
    {
      attempt: 0,
      ok: true,
      checkedAt: "2026-05-31T00:00:00.000Z",
      checkedAtMs: 1_000,
    },
  ], 2_000);

  assert.equal(lag.ok, true);
  assert.equal(lag.exceeded, false);
  assert.equal(lag.converged, true);
  assert.equal(lag.observedLagMs, 0);
});

test("sync audit detail probes do not automatically widen oracle parity reads", () => {
  const options = parseArgs([
    "--detail", "sampled",
    "--detail-limit", "1",
    "--client-path-only",
    "--force-dock-resync",
  ], {}, "/tmp/codex-client-test");

  assert.equal(options.detail, "sampled");
  assert.equal(options.clientPathOnly, true);
  assert.equal(options.forceDockResync, true);
  assert.equal(options.detailBufferInitialLive, true);
  assert.equal(options.includeThreadReads, false);
  assert.equal(options.includeTurns, false);
  assert.equal(options.includeLoaded, false);
  assert.equal(options.includeGoals, false);
});

test("sync audit parses the archive-toggle scenario actuator", () => {
  const options = parseArgs([
    "--mode", "scenario",
    "--scenario", "archive-toggle",
    "--scenario-thread-id", "thread-a",
    "--scenario-hold-ms", "3000",
    "--scenario-repetitions", "3",
  ], {}, "/tmp/codex-client-test");

  assert.equal(options.mode, "scenario");
  assert.equal(options.scenario, "archive-toggle");
  assert.equal(options.scenarioThreadID, "thread-a");
  assert.equal(options.scenarioHoldMs, 3000);
  assert.equal(options.scenarioRepetitions, 3);
});

test("sync audit parses the resync-gap scenario actuator", () => {
  const options = parseArgs([
    "--mode", "scenario",
    "--scenario", "resync-gap",
  ], {}, "/tmp/codex-client-test");

  assert.equal(options.mode, "scenario");
  assert.equal(options.scenario, "resync-gap");
});

test("sync audit parses the detail-reconnect scenario actuator", () => {
  const options = parseArgs([
    "--mode", "scenario",
    "--scenario", "detail-reconnect",
    "--scenario-thread-id", "thread-a",
  ], {}, "/tmp/codex-client-test");

  assert.equal(options.mode, "scenario");
  assert.equal(options.scenario, "detail-reconnect");
  assert.equal(options.scenarioThreadID, "thread-a");
});

test("sync audit parses the goal-change scenario actuator", () => {
  const options = parseArgs([
    "--mode", "scenario",
    "--scenario", "goal-change",
  ], {}, "/tmp/codex-client-test");

  assert.equal(options.mode, "scenario");
  assert.equal(options.scenario, "goal-change");
});

test("sync audit parses the live-lease-expiry scenario actuator", () => {
  const options = parseArgs([
    "--mode", "scenario",
    "--scenario", "live-lease-expiry",
  ], {}, "/tmp/codex-client-test");

  assert.equal(options.mode, "scenario");
  assert.equal(options.scenario, "live-lease-expiry");
});

test("sync audit parses the multi-host-isolation scenario actuator", () => {
  const options = parseArgs([
    "--mode", "scenario",
    "--scenario", "multi-host-isolation",
  ], {}, "/tmp/codex-client-test");

  assert.equal(options.mode, "scenario");
  assert.equal(options.scenario, "multi-host-isolation");
});

test("sync audit parses the source-refresh scenario actuator", () => {
  const options = parseArgs([
    "--mode", "scenario",
    "--scenario", "source-refresh",
  ], {}, "/tmp/codex-client-test");

  assert.equal(options.mode, "scenario");
  assert.equal(options.scenario, "source-refresh");
});

test("sync audit parses the server-request scenario actuator", () => {
  const options = parseArgs([
    "--mode", "scenario",
    "--scenario", "server-request",
  ], {}, "/tmp/codex-client-test");

  assert.equal(options.mode, "scenario");
  assert.equal(options.scenario, "server-request");
});

test("sync audit parses the thread-activity scenario actuator", () => {
  const options = parseArgs([
    "--mode", "scenario",
    "--scenario", "thread-activity",
  ], {}, "/tmp/codex-client-test");

  assert.equal(options.mode, "scenario");
  assert.equal(options.scenario, "thread-activity");
});

test("sync audit parses the spawn-edge scenario actuator", () => {
  const options = parseArgs([
    "--mode", "scenario",
    "--scenario", "spawn-edge",
  ], {}, "/tmp/codex-client-test");

  assert.equal(options.mode, "scenario");
  assert.equal(options.scenario, "spawn-edge");
});

test("sync audit names repeated scenario transitions distinctly", () => {
  assert.equal(scenarioTransitionName("archive", 1, 1), "archive");
  assert.equal(scenarioTransitionName("archive", 1, 3), "archive-1");
  assert.equal(scenarioTransitionName("unarchive", 3, 3), "unarchive-3");
});

test("sync audit requires repeated archive toggles for the rapid mutation scenario", () => {
  const scenario = {
    id: "rapid-archive-toggle",
    implementedBy: "archive-toggle",
    requiresRepetitions: 2,
  };

  assert.equal(scenarioRequirementImplemented(scenario, { scenarioRepetitions: 1 }), false);
  assert.equal(scenarioRequirementImplemented(scenario, { scenarioRepetitions: 2 }), true);
});

test("sync audit counts the stream-gap resync scenario as implemented", () => {
  const scenario = {
    id: "stream-gap-resync",
    implementedBy: "resync-gap",
  };

  assert.equal(scenarioRequirementImplemented(scenario, { scenarioRepetitions: 1 }), true);
});

test("sync audit counts the detail reconnect scenario as implemented", () => {
  const scenario = {
    id: "detail-reconnect",
    implementedBy: "detail-reconnect",
  };

  assert.equal(scenarioRequirementImplemented(scenario, { scenarioRepetitions: 1 }), true);
});

test("sync audit counts the goal-change scenario as implemented", () => {
  const scenario = {
    id: "goal-change",
    implementedBy: "goal-change",
  };

  assert.equal(scenarioRequirementImplemented(scenario, { scenarioRepetitions: 1 }), true);
});

test("sync audit counts the live lease expiry scenario as implemented", () => {
  const scenario = {
    id: "live-lease-expiry",
    implementedBy: "live-lease-expiry",
  };

  assert.equal(scenarioRequirementImplemented(scenario, { scenarioRepetitions: 1 }), true);
});

test("sync audit counts the multi-host isolation scenario as implemented", () => {
  const scenario = {
    id: "multi-host-isolation",
    implementedBy: "multi-host-isolation",
  };

  assert.equal(scenarioRequirementImplemented(scenario, { scenarioRepetitions: 1 }), true);
});

test("sync audit counts source refresh scenarios as implemented", () => {
  assert.equal(scenarioRequirementImplemented({
    id: "source-refresh-fails",
    implementedBy: "source-refresh",
  }, { scenarioRepetitions: 1 }), true);
  assert.equal(scenarioRequirementImplemented({
    id: "source-refresh-recovers",
    implementedBy: "source-refresh",
  }, { scenarioRepetitions: 1 }), true);
});

test("sync audit counts server request scenarios as implemented", () => {
  assert.equal(scenarioRequirementImplemented({
    id: "server-request-visible",
    implementedBy: "server-request",
  }, { scenarioRepetitions: 1 }), true);
  assert.equal(scenarioRequirementImplemented({
    id: "server-request-resolution",
    implementedBy: "server-request",
  }, { scenarioRepetitions: 1 }), true);
});

test("sync audit counts thread activity scenarios as implemented", () => {
  assert.equal(scenarioRequirementImplemented({
    id: "new-thread",
    implementedBy: "thread-activity",
  }, { scenarioRepetitions: 1 }), true);
  assert.equal(scenarioRequirementImplemented({
    id: "new-turn-order",
    implementedBy: "thread-activity",
  }, { scenarioRepetitions: 1 }), true);
});

test("sync audit counts the spawn edge scenario as implemented", () => {
  const scenario = {
    id: "spawn-edge",
    implementedBy: "spawn-edge",
  };

  assert.equal(scenarioRequirementImplemented(scenario, { scenarioRepetitions: 1 }), true);
});

test("sync audit applies dock snapshot and ordered delta updates", () => {
  const state = emptyStreamState();
  const snapshotFindings = applyDockPayload(state, {
    kind: "snapshot",
    schemaVersion: 2,
    epoch: "epoch-1",
    seq: 10,
    view: "dock",
    complete: true,
    totalRows: 1,
    cards: [
      {
        id: "host::thread-a",
        logicalHostID: "host",
        threadID: "thread-a",
        status: "idle",
        displaySummary: "private summary",
      },
    ],
  });
  assert.deepEqual(snapshotFindings, []);
  assert.equal(state.seq, 10);
  assert.deepEqual([...state.cardsByID.keys()], ["host::thread-a"]);

  const deltaFindings = applyDockPayload(state, {
    kind: "delta",
    schemaVersion: 2,
    epoch: "epoch-1",
    baseSeq: 10,
    seq: 11,
    view: "dock",
    complete: true,
    totalRows: 1,
    upsertCards: [
      {
        id: "host::thread-a",
        logicalHostID: "host",
        threadID: "thread-a",
        status: "needsApproval",
        displaySummary: "private changed summary",
      },
    ],
    deleteCardIDs: [],
  });
  assert.deepEqual(deltaFindings, []);
  assert.equal(state.seq, 11);
  assert.equal(state.cardsByID.get("host::thread-a").status, "needsApproval");
});

test("sync audit accepts same-seq dock catch-up delta windows like the Swift client", () => {
  const state = emptyStreamState();
  const snapshotFindings = applyDockPayload(state, {
    kind: "snapshot",
    schemaVersion: 2,
    epoch: "epoch-1",
    seq: 10,
    view: "dock",
    complete: false,
    totalRows: 2,
    window: { offset: 0, limit: 1, rowCount: 1, nextOffset: 1 },
    cards: [
      {
        id: "host::thread-a",
        logicalHostID: "host",
        threadID: "thread-a",
      },
    ],
  });
  assert.deepEqual(snapshotFindings, []);

  const catchupFindings = applyDockPayload(state, {
    kind: "delta",
    schemaVersion: 2,
    epoch: "epoch-1",
    baseSeq: 10,
    seq: 10,
    view: "dock",
    complete: true,
    totalRows: 2,
    window: { offset: 1, limit: 1, rowCount: 1, nextOffset: null },
    upsertCards: [
      {
        id: "host::thread-b",
        logicalHostID: "host",
        threadID: "thread-b",
      },
    ],
    deleteCardIDs: [],
  });

  assert.deepEqual(catchupFindings, []);
  assert.deepEqual([...state.cardsByID.keys()].sort(), ["host::thread-a", "host::thread-b"]);
  assert.equal(state.seq, 10);
  assert.equal(state.complete, true);
});

test("sync audit detects dock stream sequence gaps", () => {
  const state = emptyStreamState();
  applyDockPayload(state, {
    kind: "snapshot",
    schemaVersion: 2,
    epoch: "epoch-1",
    seq: 3,
    view: "dock",
    complete: true,
    totalRows: 0,
    cards: [],
  });

  const findings = applyDockPayload(state, {
    kind: "delta",
    schemaVersion: 2,
    epoch: "epoch-1",
    baseSeq: 99,
    seq: 100,
    view: "dock",
    complete: true,
    totalRows: 0,
    upsertCards: [],
    deleteCardIDs: [],
  });

  assert.equal(findings.some((finding) => finding.code === "dock_stream_sequence_gap"), true);
  assert.equal(state.needsResync, true);
});

test("sync audit compares long-lived dock stream state without leaking summary text", () => {
  const streamSnapshot = dockStateFromPayload({
    kind: "snapshot",
    schemaVersion: 2,
    epoch: "epoch-1",
    seq: 1,
    view: "dock",
    complete: true,
    totalRows: 1,
    cards: [
      {
        id: "host::thread-a",
        logicalHostID: "host",
        threadID: "thread-a",
        status: "idle",
        displaySummary: "private stream text",
      },
    ],
  });
  const freshSnapshot = dockStateFromPayload({
    kind: "snapshot",
    schemaVersion: 2,
    epoch: "epoch-1",
    seq: 2,
    view: "dock",
    complete: true,
    totalRows: 1,
    cards: [
      {
        id: "host::thread-a",
        logicalHostID: "host",
        threadID: "thread-a",
        status: "idle",
        displaySummary: "private fresh text",
      },
    ],
  });

  const comparison = compareDockStates(streamSnapshot, freshSnapshot);
  assert.equal(comparison.ok, false);
  assert.equal(comparison.findings[0].code, "dock_stream_card_payload_mismatch");
  const serialized = JSON.stringify(comparison);
  assert.equal(serialized.includes("private stream text"), false);
  assert.equal(serialized.includes("private fresh text"), false);
  assert.equal(serialized.includes("displaySummary"), true);
});

test("sync audit compares long-lived dock stream render order", () => {
  const streamSnapshot = dockStateFromPayload({
    kind: "snapshot",
    schemaVersion: 2,
    epoch: "epoch-1",
    seq: 1,
    view: "dock",
    complete: true,
    totalRows: 2,
    cards: [
      {
        id: "host::thread-a",
        logicalHostID: "host",
        threadID: "thread-a",
        orderKey: "000000000001:thread-a",
      },
      {
        id: "host::thread-b",
        logicalHostID: "host",
        threadID: "thread-b",
        orderKey: "000000000002:thread-b",
      },
    ],
  });
  const freshSnapshot = dockStateFromPayload({
    kind: "snapshot",
    schemaVersion: 2,
    epoch: "epoch-1",
    seq: 2,
    view: "dock",
    complete: true,
    totalRows: 2,
    cards: [
      {
        id: "host::thread-a",
        logicalHostID: "host",
        threadID: "thread-a",
        orderKey: "000000000002:thread-a",
      },
      {
        id: "host::thread-b",
        logicalHostID: "host",
        threadID: "thread-b",
        orderKey: "000000000001:thread-b",
      },
    ],
  });

  const comparison = compareDockStates(streamSnapshot, freshSnapshot);
  assert.equal(comparison.ok, false);
  assert.equal(
    comparison.findings.some((finding) => finding.code === "dock_stream_render_order_mismatch"),
    true,
  );
});

test("sync audit redacts secret fields and fingerprints text fields", () => {
  const normalized = normalizeForComparison({
    bearerToken: "secret-token",
    displaySummary: "private text",
    nested: {
      prompt: "raw prompt",
    },
  });

  assert.equal(normalized.bearerToken, "[redacted]");
  assert.equal(normalized.displaySummary.kind, "textFingerprint");
  assert.equal(normalized.nested.prompt.kind, "textFingerprint");
  const serialized = JSON.stringify(normalized);
  assert.equal(serialized.includes("secret-token"), false);
  assert.equal(serialized.includes("private text"), false);
  assert.equal(serialized.includes("raw prompt"), false);
});

test("sync audit sanitizes full dock snapshots before writing reports", () => {
  const sanitized = sanitizeDockSnapshotForReport({
    kind: "delta",
    schemaVersion: 2,
    epoch: "epoch-1",
    seq: 4,
    view: "dock",
    complete: true,
    totalRows: 1,
    hosts: [
      {
        id: "host",
        bearerToken: "secret-token",
        displayName: "Private Host",
      },
    ],
    cards: [
      {
        id: "host::thread-a",
        logicalHostID: "host",
        threadID: "thread-a",
        status: "idle",
        title: "private title",
        displaySummary: "private summary",
        latestSummary: "private latest summary",
        preview: "private preview",
        ignoredRawContent: "private ignored raw content",
      },
    ],
    cardIDs: ["host::thread-a"],
  });

  assert.equal(sanitized.cards[0].displaySummary.kind, "textFingerprint");
  assert.equal(sanitized.hosts[0].bearerToken, "[redacted]");
  assert.equal(sanitized.cards[0].ignoredRawContent, undefined);
  const serialized = JSON.stringify(sanitized);
  assert.equal(serialized.includes("secret-token"), false);
  assert.equal(serialized.includes("private title"), false);
  assert.equal(serialized.includes("private summary"), false);
  assert.equal(serialized.includes("private latest summary"), false);
  assert.equal(serialized.includes("private preview"), false);
  assert.equal(serialized.includes("private ignored raw content"), false);
});

test("sync audit selects detail targets from actual dock cards", () => {
  const dockSnapshot = {
    cards: [
      { id: "host::thread-a", logicalHostID: "host", threadID: "thread-a" },
      { id: "host::thread-b", logicalHostID: "host", threadID: "thread-b" },
      { id: "host::missing-thread" },
    ],
  };

  assert.deepEqual(
    selectDetailTargets(dockSnapshot, { detail: "sampled", detailLimit: 1 }),
    [{ cardID: "host::thread-a", threadID: "thread-a", logicalHostID: "host", status: null }],
  );
  assert.deepEqual(
    selectDetailTargets(dockSnapshot, { detail: "all", detailLimit: 1 }).map((target) => target.threadID),
    ["thread-a", "thread-b"],
  );
  assert.deepEqual(selectDetailTargets(dockSnapshot, { detail: "none", detailLimit: 1 }), []);
});

test("sync audit selects scenario archive targets from actual active dock cards", () => {
  const dockSnapshot = {
    cards: [
      { id: "host::thread-running", logicalHostID: "host", threadID: "thread-running", status: "running" },
      { id: "host::thread-a", logicalHostID: "host", threadID: "thread-a", archived: true },
      { id: "host::thread-b", logicalHostID: "host", threadID: "thread-b", status: "idle", archived: false },
      { id: "host::thread-c", logicalHostID: "host", threadID: "thread-c" },
    ],
  };

  assert.deepEqual(selectScenarioArchiveTarget(dockSnapshot), {
    cardID: "host::thread-b",
    threadID: "thread-b",
    logicalHostID: "host",
    status: "idle",
    archived: false,
  });
  assert.deepEqual(selectScenarioArchiveTarget(dockSnapshot, "thread-c"), {
    cardID: "host::thread-c",
    threadID: "thread-c",
    logicalHostID: "host",
    status: null,
    archived: false,
  });
  assert.equal(selectScenarioArchiveTarget(dockSnapshot, "thread-a"), null);
});

test("sync audit selects detail reconnect targets from actual dock cards", () => {
  const dockSnapshot = {
    cards: [
      { id: "host::missing-thread" },
      { id: "host::thread-a", logicalHostID: "host", threadID: "thread-a", status: "idle" },
      { id: "host::thread-b", logicalHostID: "host", threadID: "thread-b", status: "running" },
    ],
  };

  assert.deepEqual(selectScenarioDetailTarget(dockSnapshot), {
    cardID: "host::thread-a",
    threadID: "thread-a",
    logicalHostID: "host",
    status: "idle",
  });
  assert.deepEqual(selectScenarioDetailTarget(dockSnapshot, "thread-b"), {
    cardID: "host::thread-b",
    threadID: "thread-b",
    logicalHostID: "host",
    status: "running",
  });
  assert.equal(selectScenarioDetailTarget(dockSnapshot, "missing"), null);
});

test("sync audit measures scenario lag against the client-visible budget", () => {
  const fast = scenarioLagSummary({
    transition: "archive",
    startedAtMs: 1_000,
    acknowledgedAtMs: 1_100,
    observedAtMs: 2_500,
    maxStreamLagMs: 2_000,
  });
  assert.equal(fast.ok, true);
  assert.equal(fast.exceeded, false);
  assert.equal(fast.lag_change_to_relay_ms, 1_500);
  assert.equal(fast.lag_ack_to_relay_ms, 1_400);

  const slow = scenarioLagSummary({
    transition: "unarchive",
    startedAtMs: 1_000,
    acknowledgedAtMs: 1_100,
    observedAtMs: 3_500,
    maxStreamLagMs: 2_000,
  });
  assert.equal(slow.ok, false);
  assert.equal(slow.exceeded, true);
  assert.equal(slow.lag_change_to_relay_ms, 2_500);
});

test("sync audit measures scenario visibility before full stream catchup completes", async () => {
  let waitForUpdateCalled = false;
  const receivedAt = "2026-05-31T04:22:30.310Z";
  const streamProbe = {
    state: { needsResync: false },
    snapshot() {
      return {
        kind: "delta",
        complete: false,
        totalRows: 1_697,
        lastReceivedAt: receivedAt,
        cards: [{ id: "host::thread-a", threadID: "thread-a" }],
      };
    },
    async waitForUpdate() {
      waitForUpdateCalled = true;
      return true;
    },
    async resync() {
      throw new Error("resync should not be needed for a visible target update");
    },
  };

  const result = await waitForStreamThreadPresence({
    streamProbe,
    threadID: "thread-a",
    present: true,
    timeoutMs: 1_000,
    notBeforeMs: Date.parse("2026-05-31T04:22:29.213Z"),
  });

  assert.equal(result.ok, true);
  assert.equal(result.observedAtMs, Date.parse(receivedAt));
  assert.equal(waitForUpdateCalled, false);
});

test("sync audit ignores stale matching scenario visibility before the mutation starts", async () => {
  let waitForUpdateCalls = 0;
  let receivedAt = "2026-05-31T04:22:28.000Z";
  const streamProbe = {
    state: { needsResync: false },
    snapshot() {
      return {
        kind: "delta",
        complete: false,
        totalRows: 1,
        lastReceivedAt: receivedAt,
        cards: [{ id: "host::thread-a", threadID: "thread-a" }],
      };
    },
    async waitForUpdate() {
      waitForUpdateCalls += 1;
      receivedAt = "2026-05-31T04:22:30.000Z";
      return true;
    },
    async resync() {
      throw new Error("resync should not be needed for a visible target update");
    },
  };

  const result = await waitForStreamThreadPresence({
    streamProbe,
    threadID: "thread-a",
    present: true,
    timeoutMs: 1_000,
    notBeforeMs: Date.parse("2026-05-31T04:22:29.000Z"),
  });

  assert.equal(result.ok, true);
  assert.equal(result.observedAtMs, Date.parse("2026-05-31T04:22:30.000Z"));
  assert.equal(waitForUpdateCalls, 1);
});

test("sync audit fails target-thread live detail messages before the live boundary", () => {
  const observation = summarizeDetailLiveObservation({
    target: { threadID: "thread-a" },
    notifications: [{
      source: "notification",
      phase: "turns",
      receivedAt: "2026-05-31T00:00:00.000Z",
      method: "turn/completed",
      id: null,
      threadID: "thread-a",
    }],
    requests: [],
    liveBoundaryAt: null,
    observeMs: 100,
    bufferInitialLive: false,
  });

  assert.equal(observation.preLiveTargetNotificationCount, 1);
  assert.deepEqual(observation.targetPhaseCounts, { "notification:turns": 1 });
  assert.deepEqual(observation.findings.map((finding) => finding.code), ["detail_live_before_boundary"]);
});

test("sync audit models the Swift initial detail live-event buffer by default", () => {
  const observation = summarizeDetailLiveObservation({
    target: { threadID: "thread-a" },
    notifications: [{
      source: "notification",
      phase: "resume",
      receivedAt: "2026-05-31T00:00:00.000Z",
      method: "thread/status/changed",
      id: null,
      threadID: "thread-a",
    }],
    requests: [],
    liveBoundaryAt: "2026-05-31T00:00:01.000Z",
    observeMs: 100,
  });

  assert.equal(observation.bufferInitialLive, true);
  assert.equal(observation.bufferedInitialLiveEventCount, 1);
  assert.deepEqual(observation.findings, []);
});

test("sync audit fails detail server requests that cannot become request cards", () => {
  const observation = summarizeDetailLiveObservation({
    target: { threadID: "thread-a" },
    notifications: [],
    requests: [
      {
        source: "request",
        phase: "live",
        receivedAt: "2026-05-31T00:00:00.000Z",
        method: "item/commandExecution/requestApproval",
        id: "request-1",
        threadID: null,
      },
      {
        source: "request",
        phase: "live",
        receivedAt: "2026-05-31T00:00:01.000Z",
        method: "item/commandExecution/requestApproval",
        id: "request-1",
        threadID: "thread-a",
      },
    ],
    liveBoundaryAt: "2026-05-31T00:00:00.000Z",
    observeMs: 100,
  });

  assert.equal(observation.requestCount, 2);
  assert.equal(observation.targetRequestCount, 1);
  assert.deepEqual(
    observation.findings.map((finding) => finding.code),
    ["detail_request_missing_thread_id", "detail_duplicate_request"],
  );
});

test("sync audit separates client-path proof from oracle routes", () => {
  const evidence = summarizeClientPathEvents([
    { route: "dock/subscribe", countedAsClientPath: true },
    { route: "dock/update", countedAsClientPath: true },
    { route: "thread/archive", countedAsClientPath: true },
    { route: "thread/unarchive", countedAsClientPath: true },
    { route: "thread/read", countedAsClientPath: true },
    { route: "relay/state/snapshot", countedAsClientPath: false },
    { route: "thread/list", countedAsClientPath: false },
    { route: "thread/goal/get", countedAsClientPath: false },
  ]);

  assert.deepEqual(evidence.routes, ["dock/subscribe", "dock/update", "thread/archive", "thread/read", "thread/unarchive"]);
  assert.deepEqual(evidence.routeCounts, {
    "dock/subscribe": 1,
    "dock/update": 1,
    "thread/archive": 1,
    "thread/read": 1,
    "thread/unarchive": 1,
  });
  assert.deepEqual(evidence.nonClientPathRoutes, {
    "relay/state/snapshot": 1,
    "thread/goal/get": 1,
    "thread/list": 1,
  });
  assert.match(evidence.note, /Oracle reads diagnose drift/);
});

test("sync audit downgrades oracle-only parity failures outside the current client contract", () => {
  const classification = classifyParityForClientContract({
    ok: false,
    summary: {
      errors: 1,
      warnings: 12,
      info: 3,
      completionBoundary: {
        failedAppServerChecks: ["relaySnapshotComplete", "currentThreadGoalsExact"],
      },
    },
  });

  assert.equal(classification.ok, true);
  assert.equal(classification.oracleOK, false);
  assert.deepEqual(classification.clientRequiredFailures, []);
  assert.deepEqual(
    classification.outsideClientContract.map((entry) => entry.check),
    ["relaySnapshotComplete", "currentThreadGoalsExact"],
  );
});

test("sync audit keeps client-required parity failures hard failing", () => {
  const classification = classifyParityForClientContract({
    ok: false,
    summary: {
      errors: 1,
      warnings: 0,
      info: 0,
      completionBoundary: {
        failedAppServerChecks: ["dockActiveRowsExact"],
      },
    },
  });

  assert.equal(classification.ok, false);
  assert.deepEqual(classification.clientRequiredFailures, [{
    check: "dockActiveRowsExact",
    reason: "app-server or relay parity failed for a field used by the client contract",
  }]);
});

test("sync audit treats skipped parity as outside the client-path proof", () => {
  const classification = classifyParityForClientContract(null);

  assert.equal(classification.ok, true);
  assert.equal(classification.oracleOK, null);
  assert.equal(classification.skipped, true);
  assert.deepEqual(classification.clientRequiredFailures, []);
});

import assert from "node:assert/strict";
import test from "node:test";

import {
  buildRenderedUIReport,
  evaluateUISample,
  ignoredScenarioWarmupSampleIndexes,
  parseRootRowCount,
  parseSemicolonValue,
} from "./dock-relay-simulator-ui-sync-proof.mjs";

function relayReport({ finishedAt = "2026-05-31T00:00:01.000Z", status = "idle" } = {}) {
  return {
    startedAt: "2026-05-31T00:00:00.000Z",
    endedAt: finishedAt,
    relayUrl: "ws://127.0.0.1:4510/",
    summary: {
      clientPathOK: true,
    },
    samples: [{
      sampleIndex: 0,
      startedAt: "2026-05-31T00:00:00.500Z",
      finishedAt,
      freshDock: {
        cardCount: 1,
        totalRows: 1,
        cards: [{
          id: "host::thread-a",
          logicalHostID: "host",
          threadID: "thread-a",
          status,
          lane: "human",
          sourceKind: "human",
        }],
      },
    }],
  };
}

function twoRowRelaySample() {
  const report = relayReport();
  report.samples[0].freshDock = {
    cardCount: 2,
    totalRows: 2,
    cards: [
      {
        id: "host::thread-a",
        logicalHostID: "host",
        threadID: "thread-a",
        status: "idle",
        lane: "human",
        sourceKind: "human",
      },
      {
        id: "host::thread-b",
        logicalHostID: "host",
        threadID: "thread-b",
        status: "running",
        lane: "agent",
        sourceKind: "automation",
      },
    ],
  };
  return report.samples[0];
}

function dockRow({ thread = "thread-a", status = "idle", origin = "human" } = {}) {
  return {
    identifier: `codexdock.dock.row.host.${thread}`,
    value: `host=host; thread=${thread}; status=${status}; origin=${origin}; label=none; Not pinned`,
    label: thread,
    frame: { minX: 0, minY: 10, width: 100, height: 44 },
  };
}

function orderedUISample({ sampledAt, threads }) {
  return {
    sampleIndex: 0,
    sampledAt,
    dockRootValue: `loaded; rows=${threads.length}; pinned=0; lens=newest; search=false; filters=0`,
    dockRows: threads.map((thread) => dockRow({
      thread,
      status: thread === "thread-b" ? "running" : "idle",
      origin: thread === "thread-b" ? "automation" : "human",
    })),
    hostSummaries: [],
  };
}

function uiSample({ sampledAt, status = "idle" }) {
  return {
    sampleIndex: 0,
    sampledAt,
    dockRootValue: "loaded; rows=1; pinned=0; lens=newest; search=false; filters=0",
    dockRows: [dockRow({ status })],
    hostSummaries: [],
  };
}

function hostSummary({
  host = "host",
  identifierHost = host,
  text = "1 sessions, partial: controlled source refresh failure",
} = {}) {
  return {
    identifier: `codexdock.dock.host.${identifierHost}`,
    value: `${host}; endpoint=127.0.0.1:4510; ${text}`,
    label: text,
  };
}

function sourceRefreshRelayReport() {
  const base = relayReport({ finishedAt: "2026-05-31T00:00:01.000Z" });
  return {
    ...base,
    mode: "scenario",
    samples: [{
      ...base.samples[0],
      freshDock: {
        ...base.samples[0].freshDock,
        freshness: { status: "fresh" },
      },
    }],
    scenarios: [{
      id: "source-refresh",
      transitions: [
        {
          name: "source-refresh-fails",
          route: "dock/update",
          wait: { observedAt: "2026-05-31T00:00:02.000Z" },
          lag: {
            relaySeenAt: "2026-05-31T00:00:02.000Z",
            lag_change_to_relay_ms: 5,
            maxStreamLagMs: 2_000,
            ok: true,
          },
          freshDock: {
            cardCount: 1,
            totalRows: 1,
            freshness: { status: "stale", lastError: "controlled source refresh failure" },
            cards: [{
              id: "host::thread-a",
              logicalHostID: "host",
              threadID: "thread-a",
              status: "idle",
              lane: "human",
              sourceKind: "human",
            }],
          },
        },
        {
          name: "source-refresh-recovers",
          route: "dock/update",
          wait: { observedAt: "2026-05-31T00:00:05.000Z" },
          lag: {
            relaySeenAt: "2026-05-31T00:00:05.000Z",
            lag_change_to_relay_ms: 5,
            maxStreamLagMs: 2_000,
            ok: true,
          },
          freshDock: {
            cardCount: 1,
            totalRows: 1,
            freshness: { status: "fresh" },
            cards: [{
              id: "host::thread-b",
              logicalHostID: "host",
              threadID: "thread-b",
              status: "idle",
              lane: "human",
              sourceKind: "human",
            }],
          },
        },
      ],
    }],
  };
}

function duplicateUISample({ sampledAt }) {
  const sample = uiSample({ sampledAt });
  sample.dockRows = [
    dockRow(),
    dockRow(),
  ];
  return sample;
}

function emptyUISample({ sampledAt }) {
  return {
    sampleIndex: 0,
    sampledAt,
    dockRootValue: "loaded; rows=0; pinned=0; lens=newest; search=false; filters=0",
    dockRows: [],
  };
}

function detailOnlyUISample({ sampledAt }) {
  return {
    sampleIndex: 0,
    sampledAt,
    dockRootValue: "not-visible",
    dockRows: [],
    detail: {
      rootIdentifier: "codexdock.session.root.thread-a",
      rootValue: "host=host; thread=thread-a",
      headerValue: "host=host; thread=thread-a",
      messageListValue: "loaded",
      messageCardIDs: [],
      requestCardIDs: [],
    },
  };
}

function detailRequestUISample({ sampledAt, finishedAt = null, capturedAt = sampledAt, status = "Pending" }) {
  return {
    sampleIndex: 0,
    sampledAt,
    ...(finishedAt ? { finishedAt } : {}),
    dockRootValue: "not-visible",
    dockRows: [],
    detail: {
      startedAt: sampledAt,
      finishedAt: capturedAt,
      rootIdentifier: "codexdock.session.root.sim-server-request-thread",
      rootCapturedAt: capturedAt,
      rootValue: "loaded; host=sim-server-request-fixture; thread=sim-server-request-thread; live=Live; events=1",
      headerCapturedAt: capturedAt,
      headerValue: "host=sim-server-request-fixture; thread=sim-server-request-thread; live=Live",
      messageListCapturedAt: capturedAt,
      messageListValue: "loaded",
      messageCardsCapturedAt: capturedAt,
      messageCardIDs: ["codexdock.session.message.request-approval-1"],
      requestElementsCapturedAt: capturedAt,
      requestCardIDs: [
        "codexdock.session.request.request-approval-1",
        "codexdock.session.request.request-approval-1.status",
      ],
      messageCards: [{
        identifier: "codexdock.session.message.request-approval-1",
        capturedAt,
        value: "event=request-approval-1; kind=serverRequest; request=request-approval-1; request-status=" + status,
        label: "Command approval",
      }],
      requestElements: [
        {
          identifier: "codexdock.session.request.request-approval-1",
          capturedAt,
          value: `card=request-approval-1; kind=commandApproval; status=${status}; needs-input=false`,
          label: "Command approval",
        },
        {
          identifier: "codexdock.session.request.request-approval-1.status",
          capturedAt,
          value: status,
          label: status,
        },
      ],
    },
  };
}

function scenarioRelayReport() {
  const base = relayReport({ finishedAt: "2026-05-31T00:00:01.000Z" });
  return {
    ...base,
    mode: "scenario",
    scenarios: [{
      id: "archive-toggle",
      transitions: [
        {
          name: "archive",
          route: "thread/archive",
          wait: { observedAt: "2026-05-31T00:00:02.000Z" },
          lag: {
            relaySeenAt: "2026-05-31T00:00:02.000Z",
            lag_change_to_relay_ms: 20,
            maxStreamLagMs: 2_000,
            ok: true,
          },
          freshDock: {
            cardCount: 0,
            totalRows: 0,
            cards: [],
          },
        },
        {
          name: "unarchive",
          route: "thread/unarchive",
          wait: { observedAt: "2026-05-31T00:00:05.000Z" },
          lag: {
            relaySeenAt: "2026-05-31T00:00:05.000Z",
            lag_change_to_relay_ms: 25,
            maxStreamLagMs: 2_000,
            ok: true,
          },
          freshDock: base.samples[0].freshDock,
        },
      ],
    }],
  };
}

function serverRequestRelayReport() {
  const base = relayReport({ finishedAt: "2026-05-31T00:00:01.000Z" });
  return {
    ...base,
    mode: "scenario",
    scenarios: [{
      id: "server-request",
      transitions: [
        {
          name: "server-request-visible",
          route: "thread/resume",
          wait: { observedAt: "2026-05-31T00:00:02.000Z" },
          lag: {
            relaySeenAt: "2026-05-31T00:00:02.000Z",
            lag_change_to_relay_ms: 0,
            maxStreamLagMs: 2_000,
            ok: true,
          },
          detailTruth: {
            kind: "server-request-visible",
            logicalHostID: "sim-server-request-fixture",
            threadID: "sim-server-request-thread",
            requestID: "approval-1",
            requestCardID: "request-approval-1",
            expectedStatus: "Pending",
            requestVisible: true,
          },
        },
        {
          name: "server-request-resolution",
          route: "server/response",
          wait: { observedAt: "2026-05-31T00:00:03.000Z" },
          lag: {
            relaySeenAt: "2026-05-31T00:00:03.000Z",
            lag_change_to_relay_ms: 10,
            maxStreamLagMs: 2_000,
            ok: true,
          },
          detailTruth: {
            kind: "server-request-resolution",
            logicalHostID: "sim-server-request-fixture",
            threadID: "sim-server-request-thread",
            requestID: "approval-1",
            requestCardID: "request-approval-1",
            expectedStatus: "Resolved",
            requestVisible: true,
          },
        },
      ],
    }],
  };
}

function detailHistoryRelayReport() {
  const base = relayReport({ finishedAt: "2026-05-31T00:00:01.000Z" });
  return {
    ...base,
    mode: "scenario",
    scenarios: [{
      id: "detail-history-request",
      transitions: [{
        name: "detail-history-request-resolution",
        route: "server/response",
        wait: { observedAt: "2026-05-31T00:00:03.000Z" },
        lag: {
          relaySeenAt: "2026-05-31T00:00:03.000Z",
          lag_change_to_relay_ms: 10,
          maxStreamLagMs: 2_000,
          ok: true,
        },
        detailTruth: {
          logicalHostID: "sim-detail-history-fixture",
          threadID: "sim-detail-history-request-thread",
          expectedMessageEventIDs: [
            "request-approval-history-1",
            "turn-history-1-agent-seed-agent",
            "turn-history-1-user-seed-user",
          ],
          expectedMessageEventCount: 3,
          requestID: "approval-history-1",
          requestCardID: "request-approval-history-1",
          expectedStatus: "Resolved",
          requestVisible: true,
        },
      }],
    }],
  };
}

function detailHistoryUISample({ sampledAt }) {
  return {
    sampleIndex: 0,
    sampledAt,
    dockRootValue: "not-visible",
    dockRows: [],
    detail: {
      rootIdentifier: "codexdock.session.root.sim-detail-history-request-thread",
      rootValue: "loaded; host=sim-detail-history-fixture; thread=sim-detail-history-request-thread; live=Live; events=3",
      headerValue: "host=sim-detail-history-fixture; thread=sim-detail-history-request-thread; live=Live",
      messageListValue: "events=3; filter=all",
      messageCardIDs: ["codexdock.session.message.request-approval-history-1"],
      requestCardIDs: ["codexdock.session.request.request-approval-history-1"],
      messageCards: [{
        identifier: "codexdock.session.message.request-approval-history-1",
        value: "event=request-approval-history-1; kind=request; request=request-approval-history-1; request-status=Resolved",
        label: "Command approval",
      }],
      requestElements: [{
        identifier: "codexdock.session.request.request-approval-history-1",
        value: "card=request-approval-history-1; kind=commandApproval; status=Resolved; needs-input=false",
        label: "Command approval",
      }],
    },
    detailSweep: {
      startedAt: sampledAt,
      finishedAt: sampledAt,
      stepCount: 2,
      expectedMessageRows: 3,
      messageCardIDs: [
        "codexdock.session.message.request-approval-history-1",
        "codexdock.session.message.turn-history-1-agent-seed-agent",
        "codexdock.session.message.turn-history-1-user-seed-user",
      ],
      requestCardIDs: ["codexdock.session.request.request-approval-history-1"],
      messageCards: [],
      requestElements: [],
    },
  };
}

test("simulator UI proof parses semicolon accessibility values", () => {
  assert.deepEqual(parseSemicolonValue("host=host-a; thread=thread-a; Not pinned"), {
    host: "host-a",
    thread: "thread-a",
    "Not pinned": true,
  });
  assert.equal(parseRootRowCount("loaded; rows=12; pinned=0"), 12);
});

test("simulator UI proof accepts a matching displayed Dock row", () => {
  const evaluation = evaluateUISample(
    uiSample({ sampledAt: "2026-05-31T00:00:01.500Z" }),
    relayReport().samples[0],
  );

  assert.equal(evaluation.ok, true);
  assert.equal(evaluation.scored, true);
  assert.equal(evaluation.rowCount, 1);
  assert.deepEqual(evaluation.failures, []);
});

test("simulator UI proof fails visible row status mismatches", () => {
  const evaluation = evaluateUISample(
    uiSample({ sampledAt: "2026-05-31T00:00:01.500Z", status: "live" }),
    relayReport({ status: "idle" }).samples[0],
  );

  assert.equal(evaluation.ok, false);
  assert.deepEqual(evaluation.failures.map((failure) => failure.code), ["dock_ui_row_status_mismatch"]);
});

test("simulator UI proof accepts checkpoint sweeps that cover all relay rows", () => {
  const sample = uiSample({ sampledAt: "2026-05-31T00:00:01.500Z" });
  sample.dockRootValue = "loaded; rows=2; pinned=0; lens=newest; search=false; filters=0";
  sample.dockRows = [dockRow({ thread: "thread-a" })];
  sample.dockSweep = {
    startedAt: "2026-05-31T00:00:01.500Z",
    finishedAt: "2026-05-31T00:00:01.800Z",
    stepCount: 2,
    expectedRootRows: 2,
    rows: [
      dockRow({ thread: "thread-a" }),
      dockRow({ thread: "thread-b", status: "running", origin: "automation" }),
    ],
  };

  const evaluation = evaluateUISample(sample, twoRowRelaySample());

  assert.equal(evaluation.ok, true);
  assert.equal(evaluation.sweepRowCount, 2);
  assert.deepEqual(evaluation.failures, []);
});

test("simulator UI proof uses stream notification snapshots as timestamped Dock truth", () => {
  const report = relayReport({ finishedAt: "2026-05-31T00:00:01.000Z" });
  report.samples[0].freshDock = {
    cardCount: 2,
    totalRows: 2,
    renderOrderCardIDs: ["host::thread-a", "host::thread-b"],
    cards: twoRowRelaySample().freshDock.cards,
  };
  report.samples[0].stream = {
    notifications: [{
      method: "dock/update",
      receivedAt: "2026-05-31T00:00:02.000Z",
      kind: "delta",
      seq: 2,
      baseSeq: 1,
      snapshot: {
        cardCount: 2,
        totalRows: 2,
        renderOrderCardIDs: ["host::thread-b", "host::thread-a"],
        cards: [
          {
            id: "host::thread-b",
            logicalHostID: "host",
            threadID: "thread-b",
            status: "running",
            lane: "agent",
            sourceKind: "automation",
          },
          {
            id: "host::thread-a",
            logicalHostID: "host",
            threadID: "thread-a",
            status: "idle",
            lane: "human",
            sourceKind: "human",
          },
        ],
      },
    }],
  };

  const proof = buildRenderedUIReport({
    relayReport: report,
    uiSamples: [
      orderedUISample({
        sampledAt: "2026-05-31T00:00:01.500Z",
        threads: ["thread-a", "thread-b"],
      }),
      orderedUISample({
        sampledAt: "2026-05-31T00:00:02.500Z",
        threads: ["thread-b", "thread-a"],
      }),
    ],
    maxUiLagMs: 2_000,
  });

  assert.equal(proof.summary.ok, true);
  assert.equal(proof.evaluations[1].relaySampleIndex, "stream:2");
  assert.deepEqual(proof.failures, []);
});

test("simulator UI proof scores Dock rows at row capture time", () => {
  const report = relayReport({ finishedAt: "2026-05-31T00:00:01.000Z" });
  report.samples[0].freshDock = {
    cardCount: 2,
    totalRows: 2,
    renderOrderCardIDs: ["host::thread-a", "host::thread-b"],
    cards: twoRowRelaySample().freshDock.cards,
  };
  report.samples[0].stream = {
    notifications: [{
      method: "dock/update",
      receivedAt: "2026-05-31T00:00:02.000Z",
      kind: "delta",
      seq: 2,
      baseSeq: 1,
      snapshot: {
        cardCount: 2,
        totalRows: 2,
        renderOrderCardIDs: ["host::thread-b", "host::thread-a"],
        cards: [
          {
            id: "host::thread-b",
            logicalHostID: "host",
            threadID: "thread-b",
            status: "running",
            lane: "agent",
            sourceKind: "automation",
          },
          {
            id: "host::thread-a",
            logicalHostID: "host",
            threadID: "thread-a",
            status: "idle",
            lane: "human",
            sourceKind: "human",
          },
        ],
      },
    }],
  };
  const sample = orderedUISample({
    sampledAt: "2026-05-31T00:00:01.900Z",
    threads: ["thread-b", "thread-a"],
  });
  sample.finishedAt = "2026-05-31T00:00:03.000Z";
  sample.dockRowsCapturedAt = "2026-05-31T00:00:02.100Z";

  const proof = buildRenderedUIReport({
    relayReport: report,
    uiSamples: [sample],
    maxUiLagMs: 2_000,
  });

  assert.equal(proof.summary.ok, true);
  assert.equal(proof.evaluations[0].relaySampleIndex, "stream:2");
});

test("simulator UI proof fails visible Dock rows rendered out of relay order", () => {
  const relaySample = twoRowRelaySample();
  relaySample.freshDock.renderOrderCardIDs = ["host::thread-a", "host::thread-b"];
  const sample = uiSample({ sampledAt: "2026-05-31T00:00:01.500Z" });
  sample.dockRootValue = "loaded; rows=2; pinned=0; lens=newest; search=false; filters=0";
  sample.dockRows = [
    dockRow({ thread: "thread-b", status: "running", origin: "automation" }),
    dockRow({ thread: "thread-a" }),
  ];

  const evaluation = evaluateUISample(sample, relaySample);

  assert.equal(evaluation.ok, false);
  assert.equal(evaluation.visibleOrderChecks, 1);
  assert.equal(evaluation.failures.some((failure) => failure.code === "dock_ui_order_mismatch"), true);
});

test("simulator UI proof skips global order checks for grouped Dock lenses", () => {
  const relaySample = twoRowRelaySample();
  relaySample.freshDock.renderOrderCardIDs = ["host::thread-a", "host::thread-b"];
  const sample = uiSample({ sampledAt: "2026-05-31T00:00:01.500Z" });
  sample.dockRootValue = "loaded; rows=2; pinned=0; lens=branch; search=false; filters=0";
  sample.dockRows = [
    dockRow({ thread: "thread-b", status: "running", origin: "automation" }),
    dockRow({ thread: "thread-a" }),
  ];

  const evaluation = evaluateUISample(sample, relaySample);

  assert.equal(evaluation.ok, true);
  assert.equal(evaluation.visibleOrderChecks, 0);
  assert.equal(evaluation.failures.some((failure) => failure.code === "dock_ui_order_mismatch"), false);
});

test("simulator UI proof still detects duplicate rows for grouped Dock lenses", () => {
  const relaySample = twoRowRelaySample();
  relaySample.freshDock.renderOrderCardIDs = ["host::thread-a", "host::thread-b"];
  const sample = uiSample({ sampledAt: "2026-05-31T00:00:01.500Z" });
  sample.dockRootValue = "loaded; rows=2; pinned=0; lens=host; search=false; filters=0";
  sample.dockRows = [
    dockRow({ thread: "thread-a" }),
    dockRow({ thread: "thread-a" }),
  ];

  const evaluation = evaluateUISample(sample, relaySample);

  assert.equal(evaluation.ok, false);
  assert.equal(evaluation.visibleOrderChecks, 0);
  assert.equal(evaluation.failures.some((failure) => failure.code === "dock_ui_duplicate_row"), true);
});

test("simulator UI proof fails checkpoint sweeps rendered out of relay order", () => {
  const relaySample = twoRowRelaySample();
  relaySample.freshDock.renderOrderCardIDs = ["host::thread-a", "host::thread-b"];
  const sample = uiSample({ sampledAt: "2026-05-31T00:00:01.500Z" });
  sample.dockRootValue = "loaded; rows=2; pinned=0; lens=newest; search=false; filters=0";
  sample.dockRows = [dockRow({ thread: "thread-a" })];
  sample.dockSweep = {
    startedAt: "2026-05-31T00:00:01.500Z",
    finishedAt: "2026-05-31T00:00:01.800Z",
    stepCount: 2,
    expectedRootRows: 2,
    rows: [
      dockRow({ thread: "thread-b", status: "running", origin: "automation" }),
      dockRow({ thread: "thread-a" }),
    ],
  };

  const evaluation = evaluateUISample(sample, relaySample);

  assert.equal(evaluation.ok, false);
  assert.equal(evaluation.sweepOrderChecks, 1);
  assert.equal(evaluation.failures.some((failure) => failure.code === "dock_ui_sweep_order_mismatch"), true);
});

test("simulator UI proof fails checkpoint sweeps that miss relay rows", () => {
  const sample = uiSample({ sampledAt: "2026-05-31T00:00:01.500Z" });
  sample.dockRootValue = "loaded; rows=2; pinned=0; lens=newest; search=false; filters=0";
  sample.dockRows = [dockRow({ thread: "thread-a" })];
  sample.dockSweep = {
    startedAt: "2026-05-31T00:00:01.500Z",
    finishedAt: "2026-05-31T00:00:01.800Z",
    stepCount: 1,
    expectedRootRows: 2,
    rows: [dockRow({ thread: "thread-a" })],
  };

  const evaluation = evaluateUISample(sample, twoRowRelaySample());

  assert.equal(evaluation.ok, false);
  assert.equal(evaluation.failures.some((failure) => failure.code === "dock_ui_sweep_count_mismatch"), true);
  assert.equal(evaluation.failures.some((failure) => failure.code === "dock_ui_sweep_missing_relay_row"), true);
});

test("simulator UI proof treats maxSteps checkpoint sweeps as partial evidence", () => {
  const sample = uiSample({ sampledAt: "2026-05-31T00:00:01.500Z" });
  sample.dockRootValue = "loaded; rows=2; pinned=0; lens=newest; search=false; filters=0";
  sample.dockRows = [dockRow({ thread: "thread-a" })];
  sample.dockSweep = {
    startedAt: "2026-05-31T00:00:01.500Z",
    finishedAt: "2026-05-31T00:00:01.800Z",
    stepCount: 30,
    maxSteps: 30,
    stopReason: "maxSteps",
    expectedRootRows: 2,
    rows: [dockRow({ thread: "thread-a" })],
  };

  const evaluation = evaluateUISample(sample, twoRowRelaySample());

  assert.equal(evaluation.ok, true);
  assert.equal(evaluation.sweepExhaustive, false);
  assert.equal(evaluation.failures.some((failure) => failure.code === "dock_ui_sweep_count_mismatch"), false);
  assert.equal(evaluation.failures.some((failure) => failure.code === "dock_ui_sweep_missing_relay_row"), false);
});

test("simulator UI proof treats timeBudget checkpoint sweeps as partial evidence", () => {
  const sample = uiSample({ sampledAt: "2026-05-31T00:00:01.500Z" });
  sample.dockRootValue = "loaded; rows=2; pinned=0; lens=newest; search=false; filters=0";
  sample.dockRows = [dockRow({ thread: "thread-a" })];
  sample.dockSweep = {
    startedAt: "2026-05-31T00:00:01.500Z",
    finishedAt: "2026-05-31T00:00:21.800Z",
    stepCount: 4,
    maxSteps: 30,
    stopReason: "timeBudget",
    expectedRootRows: 2,
    rows: [dockRow({ thread: "thread-a" })],
  };

  const evaluation = evaluateUISample(sample, twoRowRelaySample());

  assert.equal(evaluation.ok, true);
  assert.equal(evaluation.sweepExhaustive, false);
  assert.equal(evaluation.failures.some((failure) => failure.code === "dock_ui_sweep_count_mismatch"), false);
  assert.equal(evaluation.failures.some((failure) => failure.code === "dock_ui_sweep_missing_relay_row"), false);
});

test("simulator UI proof skips capped sweep order as non-atomic evidence", () => {
  const relaySample = twoRowRelaySample();
  relaySample.freshDock.renderOrderCardIDs = ["host::thread-a", "host::thread-b"];
  const sample = uiSample({ sampledAt: "2026-05-31T00:00:01.500Z" });
  sample.dockRootValue = "loaded; rows=2; pinned=0; lens=newest; search=false; filters=0";
  sample.dockRows = [dockRow({ thread: "thread-a" })];
  sample.dockSweep = {
    startedAt: "2026-05-31T00:00:01.500Z",
    finishedAt: "2026-05-31T00:03:01.500Z",
    stepCount: 30,
    maxSteps: 30,
    stopReason: "maxSteps",
    expectedRootRows: 2,
    rows: [
      dockRow({ thread: "thread-b", status: "running", origin: "automation" }),
      dockRow({ thread: "thread-a" }),
    ],
  };

  const evaluation = evaluateUISample(sample, relaySample);

  assert.equal(evaluation.ok, true);
  assert.equal(evaluation.sweepOrderChecks, 0);
  assert.equal(evaluation.failures.some((failure) => failure.code === "dock_ui_sweep_order_mismatch"), false);
});

test("simulator UI proof does not count detail-only samples as Dock proof", () => {
  const evaluation = evaluateUISample(
    detailOnlyUISample({ sampledAt: "2026-05-31T00:00:01.500Z" }),
    relayReport().samples[0],
  );

  assert.equal(evaluation.ok, true);
  assert.equal(evaluation.scored, false);
});

test("simulator UI proof only scores UI samples after relay truth exists", () => {
  const report = buildRenderedUIReport({
    relayReport: relayReport({ finishedAt: "2026-05-31T00:00:03.000Z" }),
    uiSamples: [
      uiSample({ sampledAt: "2026-05-31T00:00:01.000Z" }),
      uiSample({ sampledAt: "2026-05-31T00:00:03.500Z" }),
      uiSample({ sampledAt: "2026-05-31T00:00:04.000Z" }),
    ],
    maxUiLagMs: 2_000,
  });

  assert.equal(report.summary.ok, true);
  assert.equal(report.summary.uiSampleCount, 3);
  assert.equal(report.summary.scoredUISampleCount, 2);
  assert.equal(report.summary.uiLag.observedLagMs, 0);
  assert.equal(report.summary.bestConsecutivePassingSamples, 2);
});

test("simulator UI proof scores against stream notification truth between sparse relay samples", () => {
  const report = relayReport({ finishedAt: "2026-05-31T00:00:20.000Z" });
  report.samples[0].finishedAt = "2026-05-31T00:00:01.000Z";
  report.samples[0].freshDock = {
    cardCount: 2,
    totalRows: 2,
    cards: [
      {
        id: "host::thread-a",
        logicalHostID: "host",
        threadID: "thread-a",
        status: "idle",
        lane: "human",
        sourceKind: "human",
        orderKey: "001",
      },
      {
        id: "host::thread-b",
        logicalHostID: "host",
        threadID: "thread-b",
        status: "idle",
        lane: "human",
        sourceKind: "human",
        orderKey: "002",
      },
    ],
  };
  report.samples.push({
    sampleIndex: 1,
    startedAt: "2026-05-31T00:00:20.000Z",
    finishedAt: "2026-05-31T00:00:20.000Z",
    freshDock: report.samples[0].freshDock,
    stream: {
      notifications: [{
        receivedAt: "2026-05-31T00:00:05.000Z",
        kind: "delta",
        seq: 2,
        snapshot: {
          cardCount: 2,
          totalRows: 2,
          cards: [
            {
              id: "host::thread-b",
              logicalHostID: "host",
              threadID: "thread-b",
              status: "running",
              lane: "human",
              sourceKind: "human",
              orderKey: "000",
            },
            {
              id: "host::thread-a",
              logicalHostID: "host",
              threadID: "thread-a",
              status: "idle",
              lane: "human",
              sourceKind: "human",
              orderKey: "001",
            },
          ],
        },
      }],
    },
  });

  const sample = uiSample({ sampledAt: "2026-05-31T00:00:06.000Z" });
  sample.dockRootValue = "loaded; rows=2; pinned=0; lens=newest; search=false; filters=0";
  sample.dockRows = [
    dockRow({ thread: "thread-b", status: "running" }),
    dockRow({ thread: "thread-a", status: "idle" }),
  ];

  const result = buildRenderedUIReport({
    relayReport: report,
    uiSamples: [sample],
    maxUiLagMs: 2_000,
  });

  assert.equal(result.summary.ok, true);
  assert.equal(result.evaluations[0].relaySampleIndex, "stream:2");
});

test("simulator UI proof scores visible Dock rows at sampledAt when checkpoint sweep finishes later", () => {
  const report = relayReport({ finishedAt: "2026-05-31T00:00:01.000Z" });
  report.samples[0].freshDock = {
    cardCount: 2,
    totalRows: 2,
    renderOrderCardIDs: ["host::thread-a", "host::thread-b"],
    cards: twoRowRelaySample().freshDock.cards,
  };
  report.samples.push({
    sampleIndex: 1,
    startedAt: "2026-05-31T00:00:10.000Z",
    finishedAt: "2026-05-31T00:00:10.000Z",
    freshDock: {
      cardCount: 2,
      totalRows: 2,
      renderOrderCardIDs: ["host::thread-b", "host::thread-a"],
      cards: [
        {
          id: "host::thread-b",
          logicalHostID: "host",
          threadID: "thread-b",
          status: "running",
          lane: "agent",
          sourceKind: "automation",
        },
        {
          id: "host::thread-a",
          logicalHostID: "host",
          threadID: "thread-a",
          status: "idle",
          lane: "human",
          sourceKind: "human",
        },
      ],
    },
  });

  const sample = orderedUISample({
    sampledAt: "2026-05-31T00:00:02.000Z",
    threads: ["thread-a", "thread-b"],
  });
  sample.finishedAt = "2026-05-31T00:00:12.000Z";
  sample.dockSweep = {
    startedAt: "2026-05-31T00:00:02.100Z",
    finishedAt: "2026-05-31T00:00:12.000Z",
    stepCount: 30,
    maxSteps: 30,
    stopReason: "maxSteps",
    expectedRootRows: 2,
    rows: sample.dockRows,
  };

  const result = buildRenderedUIReport({
    relayReport: report,
    uiSamples: [sample],
    maxUiLagMs: 2_000,
  });

  assert.equal(result.summary.ok, true);
  assert.equal(result.evaluations[0].relaySampleIndex, 0);
  assert.deepEqual(result.failures, []);
});

test("simulator UI proof fails rendered lag after divergence", () => {
  const report = buildRenderedUIReport({
    relayReport: relayReport({ finishedAt: "2026-05-31T00:00:01.000Z", status: "idle" }),
    uiSamples: [
      uiSample({ sampledAt: "2026-05-31T00:00:01.100Z", status: "live" }),
      uiSample({ sampledAt: "2026-05-31T00:00:04.500Z", status: "idle" }),
      uiSample({ sampledAt: "2026-05-31T00:00:05.000Z", status: "idle" }),
    ],
    maxUiLagMs: 2_000,
  });

  assert.equal(report.summary.ok, false);
  assert.equal(report.summary.uiLag.observedLagMs, 3_400);
  assert.equal(report.failures.some((failure) => failure.code === "dock_ui_lag_exceeded"), true);
});

test("simulator UI proof does not fail a large checkpoint sweep solely because max steps capped it", () => {
  const sample = uiSample({ sampledAt: "2026-05-31T00:00:01.500Z" });
  sample.dockRootValue = "loaded; rows=3; pinned=0; lens=newest; search=false; filters=0";
  sample.dockRows = [dockRow({ thread: "thread-a" })];
  sample.dockSweep = {
    startedAt: "2026-05-31T00:00:01.500Z",
    finishedAt: "2026-05-31T00:00:01.800Z",
    stepCount: 30,
    maxSteps: 30,
    stopReason: "maxSteps",
    expectedRootRows: 3,
    rows: [dockRow({ thread: "thread-a" })],
  };
  const relaySample = twoRowRelaySample();
  relaySample.freshDock.cardCount = 3;
  relaySample.freshDock.totalRows = 3;
  relaySample.freshDock.cards.push({
    id: "host::thread-c",
    logicalHostID: "host",
    threadID: "thread-c",
    status: "idle",
    lane: "human",
    sourceKind: "human",
  });

  const evaluation = evaluateUISample(sample, relaySample);

  assert.equal(evaluation.ok, true);
  assert.equal(evaluation.sweepExhaustive, false);
});

test("simulator UI proof scores scenario archive and unarchive transition windows", () => {
  const report = buildRenderedUIReport({
    relayReport: scenarioRelayReport(),
    uiSamples: [
      emptyUISample({ sampledAt: "2026-05-31T00:00:02.400Z" }),
      uiSample({ sampledAt: "2026-05-31T00:00:05.400Z" }),
      uiSample({ sampledAt: "2026-05-31T00:00:05.900Z" }),
    ],
    maxUiLagMs: 2_000,
  });

  assert.equal(report.summary.ok, true);
  assert.equal(report.summary.scenarioTransitionCount, 2);
  assert.equal(report.summary.scenarioTransitionFailures, 0);
  assert.deepEqual(
    report.scenarioTransitionCoverage.checks.map((check) => [check.transition, check.observedLagMs]),
    [["archive", 400], ["unarchive", 400]],
  );
});

test("simulator UI proof fails when no UI sample observes a scenario transition", () => {
  const report = buildRenderedUIReport({
    relayReport: scenarioRelayReport(),
    uiSamples: [
      uiSample({ sampledAt: "2026-05-31T00:00:05.400Z" }),
      uiSample({ sampledAt: "2026-05-31T00:00:05.900Z" }),
    ],
    maxUiLagMs: 2_000,
  });

  assert.equal(report.summary.ok, false);
  assert.equal(report.failures.some((failure) => failure.code === "scenario_ui_transition_not_observed"), true);
});

test("simulator UI proof does not let detail-only samples satisfy scenario transitions", () => {
  const report = buildRenderedUIReport({
    relayReport: scenarioRelayReport(),
    uiSamples: [
      emptyUISample({ sampledAt: "2026-05-31T00:00:02.400Z" }),
      detailOnlyUISample({ sampledAt: "2026-05-31T00:00:05.400Z" }),
    ],
    maxUiLagMs: 2_000,
  });

  assert.equal(report.summary.ok, false);
  assert.equal(report.failures.some((failure) => failure.code === "scenario_ui_transition_not_observed"), true);
});

test("simulator UI proof scores transient transition warmup mismatches against the transition lag budget", () => {
  const report = buildRenderedUIReport({
    relayReport: scenarioRelayReport(),
    uiSamples: [
      uiSample({ sampledAt: "2026-05-31T00:00:02.100Z" }),
      emptyUISample({ sampledAt: "2026-05-31T00:00:02.400Z" }),
      duplicateUISample({ sampledAt: "2026-05-31T00:00:05.200Z" }),
      uiSample({ sampledAt: "2026-05-31T00:00:05.600Z" }),
      uiSample({ sampledAt: "2026-05-31T00:00:05.900Z" }),
    ],
    maxUiLagMs: 2_000,
  });

  assert.equal(report.summary.ok, true);
  assert.equal(report.summary.scenarioTransitionFailures, 0);
  assert.equal(report.summary.scenarioWarmupFailureSamplesIgnored, 2);
  assert.equal(report.failures.some((failure) => failure.code === "dock_ui_duplicate_row"), false);

  const ignored = ignoredScenarioWarmupSampleIndexes(
    [
      uiSample({ sampledAt: "2026-05-31T00:00:02.100Z" }),
      emptyUISample({ sampledAt: "2026-05-31T00:00:02.400Z" }),
      duplicateUISample({ sampledAt: "2026-05-31T00:00:05.200Z" }),
    ],
    report.scenarioTransitionCoverage
  );
  assert.deepEqual([...ignored], [0, 2]);
});

test("simulator UI proof requires visible host freshness for source-refresh stale transitions", () => {
  const report = buildRenderedUIReport({
    relayReport: sourceRefreshRelayReport(),
    uiSamples: [
      uiSample({ sampledAt: "2026-05-31T00:00:02.200Z" }),
      {
        ...uiSample({ sampledAt: "2026-05-31T00:00:02.500Z" }),
        hostSummaries: [hostSummary()],
      },
      {
        ...uiSample({ sampledAt: "2026-05-31T00:00:05.300Z" }),
        dockRows: [dockRow({ thread: "thread-b" })],
        hostSummaries: [],
      },
      {
        ...uiSample({ sampledAt: "2026-05-31T00:00:05.800Z" }),
        dockRows: [dockRow({ thread: "thread-b" })],
        hostSummaries: [],
      },
    ],
    maxUiLagMs: 2_000,
  });

  assert.equal(report.summary.ok, true);
  assert.equal(report.summary.scenarioTransitionCount, 2);
  assert.deepEqual(
    report.scenarioTransitionCoverage.checks.map((check) => [check.transition, check.observedLagMs]),
    [["source-refresh-fails", 500], ["source-refresh-recovers", 300]],
  );
});

test("simulator UI proof accepts single-host configured-host aliases for freshness display", () => {
  const evaluation = evaluateUISample(
    {
      ...uiSample({ sampledAt: "2026-05-31T00:00:02.500Z" }),
      hostSummaries: [hostSummary({ host: "127.0.0.1:55124", identifierHost: "127.0.0.1%3A55124" })],
    },
    sourceRefreshRelayReport().scenarios[0].transitions[0],
  );

  assert.equal(evaluation.ok, true);
  assert.deepEqual(evaluation.failures, []);
});

test("simulator UI proof fails source-refresh stale transitions without visible host freshness", () => {
  const report = buildRenderedUIReport({
    relayReport: sourceRefreshRelayReport(),
    uiSamples: [
      uiSample({ sampledAt: "2026-05-31T00:00:02.500Z" }),
      {
        ...uiSample({ sampledAt: "2026-05-31T00:00:05.300Z" }),
        dockRows: [dockRow({ thread: "thread-b" })],
      },
      {
        ...uiSample({ sampledAt: "2026-05-31T00:00:05.800Z" }),
        dockRows: [dockRow({ thread: "thread-b" })],
      },
    ],
    maxUiLagMs: 2_000,
  });

  assert.equal(report.summary.ok, false);
  assert.equal(report.failures.some((failure) => failure.code === "scenario_ui_transition_not_observed"), true);
  assert.equal(
    report.scenarioTransitionCoverage.checks[0].failures.some((failure) => failure.code === "dock_ui_host_freshness_missing"),
    true,
  );
});

test("simulator UI proof fails recovered source-refresh samples that still expose stale host state", () => {
  const report = buildRenderedUIReport({
    relayReport: sourceRefreshRelayReport(),
    uiSamples: [
      {
        ...uiSample({ sampledAt: "2026-05-31T00:00:02.500Z" }),
        hostSummaries: [hostSummary()],
      },
      {
        ...uiSample({ sampledAt: "2026-05-31T00:00:05.300Z" }),
        dockRows: [dockRow({ thread: "thread-b" })],
        hostSummaries: [hostSummary()],
      },
    ],
    maxUiLagMs: 2_000,
  });

  assert.equal(report.summary.ok, false);
  assert.equal(report.failures.some((failure) => failure.code === "scenario_ui_transition_not_observed"), true);
  assert.equal(
    report.scenarioTransitionCoverage.checks[1].failures.some((failure) => failure.code === "dock_ui_stale_host_summary_after_recovery"),
    true,
  );
});

test("simulator UI proof scores server-request detail visibility and resolution transitions", () => {
  const report = buildRenderedUIReport({
    relayReport: serverRequestRelayReport(),
    uiSamples: [
      uiSample({ sampledAt: "2026-05-31T00:00:01.200Z" }),
      uiSample({ sampledAt: "2026-05-31T00:00:01.500Z" }),
      detailRequestUISample({ sampledAt: "2026-05-31T00:00:02.250Z", status: "Pending" }),
      detailRequestUISample({ sampledAt: "2026-05-31T00:00:03.250Z", status: "Resolved" }),
    ],
    maxUiLagMs: 2_000,
  });

  assert.equal(report.summary.ok, true);
  assert.equal(report.summary.detailTransitionCount, 2);
  assert.equal(report.summary.detailTransitionFailures, 0);
  assert.deepEqual(
    report.detailTransitionCoverage.checks.map((check) => [check.transition, check.observedLagMs]),
    [["server-request-visible", 250], ["server-request-resolution", 250]],
  );
});

test("simulator UI proof scores detail lag from captured evidence time", () => {
  const report = buildRenderedUIReport({
    relayReport: serverRequestRelayReport(),
    uiSamples: [
      uiSample({ sampledAt: "2026-05-31T00:00:01.200Z" }),
      uiSample({ sampledAt: "2026-05-31T00:00:01.500Z" }),
      detailRequestUISample({ sampledAt: "2026-05-31T00:00:02.250Z", status: "Pending" }),
      detailRequestUISample({
        sampledAt: "2026-05-31T00:00:03.250Z",
        capturedAt: "2026-05-31T00:00:03.400Z",
        finishedAt: "2026-05-31T00:00:05.100Z",
        status: "Resolved",
      }),
    ],
    maxUiLagMs: 2_000,
  });

  assert.equal(report.summary.ok, true);
  assert.deepEqual(
    report.detailTransitionCoverage.checks.map((check) => [check.transition, check.observedLagMs]),
    [["server-request-visible", 250], ["server-request-resolution", 400]],
  );
});

test("simulator UI proof scores opened-thread history through a detail sweep", () => {
  const report = buildRenderedUIReport({
    relayReport: detailHistoryRelayReport(),
    uiSamples: [
      uiSample({ sampledAt: "2026-05-31T00:00:01.200Z" }),
      uiSample({ sampledAt: "2026-05-31T00:00:01.500Z" }),
      detailHistoryUISample({ sampledAt: "2026-05-31T00:00:03.250Z" }),
    ],
    maxUiLagMs: 2_000,
  });

  assert.equal(report.summary.ok, true);
  assert.equal(report.summary.detailSweepCount, 1);
  assert.equal(report.summary.detailSweepMessageCardChecks, 3);
  assert.equal(report.summary.detailMessageOrderChecks, 1);
  assert.equal(report.summary.detailTransitionFailures, 0);
});

test("simulator UI proof fails opened-thread detail rows rendered out of newest-first order", () => {
  const sample = detailHistoryUISample({ sampledAt: "2026-05-31T00:00:03.250Z" });
  sample.detailSweep.messageCardIDs = [
    "codexdock.session.message.turn-history-1-user-seed-user",
    "codexdock.session.message.turn-history-1-agent-seed-agent",
    "codexdock.session.message.request-approval-history-1",
  ];

  const report = buildRenderedUIReport({
    relayReport: detailHistoryRelayReport(),
    uiSamples: [
      uiSample({ sampledAt: "2026-05-31T00:00:01.200Z" }),
      uiSample({ sampledAt: "2026-05-31T00:00:01.500Z" }),
      sample,
    ],
    maxUiLagMs: 2_000,
  });

  assert.equal(report.summary.ok, false);
  assert.equal(report.summary.detailMessageOrderChecks, 1);
  assert.equal(report.failures.some((failure) => failure.code === "detail_ui_transition_not_observed"), true);
  assert.equal(
    report.detailTransitionCoverage.checks[0].failures.some((failure) => failure.code === "detail_ui_message_order_mismatch"),
    true,
  );
});

test("simulator UI proof fails server-request detail transitions that lag too long", () => {
  const report = buildRenderedUIReport({
    relayReport: serverRequestRelayReport(),
    uiSamples: [
      uiSample({ sampledAt: "2026-05-31T00:00:01.200Z" }),
      uiSample({ sampledAt: "2026-05-31T00:00:01.500Z" }),
      detailRequestUISample({ sampledAt: "2026-05-31T00:00:04.250Z", status: "Pending" }),
      detailRequestUISample({ sampledAt: "2026-05-31T00:00:05.250Z", status: "Resolved" }),
    ],
    maxUiLagMs: 2_000,
  });

  assert.equal(report.summary.ok, false);
  assert.equal(report.failures.some((failure) => failure.code === "detail_ui_transition_not_observed"), true);
});

import assert from "node:assert/strict";
import test from "node:test";
import {
  assertProofReport,
  sampleProofReports,
  validateProofReport,
} from "./proof-report-contracts.mjs";

function simUIDumpSample() {
  return structuredClone(
    sampleProofReports().find((report) => report.kind === "codex-dock-sim-ui-dump")
  );
}

test("sim UI dump contract accepts the Swift app metadata shape", () => {
  const report = simUIDumpSample();
  report.app = {
    bundleIdentifier: "com.aelaguiz.CodexDockApp",
    configuredBuildNumber: "202606020001",
  };

  assertProofReport(report, { sourcePath: "sim-ui-dump-sample" });
});

test("sim UI dump contract rejects drifted app metadata fields", () => {
  const report = simUIDumpSample();
  report.app = {
    bundleIdentifier: "com.aelaguiz.CodexDockApp",
    configuredBuildNumber: "202606020001",
    relayInstanceID: "side-door",
  };

  assert.throws(
    () => assertProofReport(report, { sourcePath: "sim-ui-dump-sample" }),
    /must NOT have additional properties/u
  );
});

test("sim UI dump contract accepts visible thread detail card identifiers", () => {
  const report = simUIDumpSample();
  report.screenBefore = "thread";
  report.screenAfter = "thread";
  report.sampleAfter = {
    sampleIndex: 0,
    sampledAt: "2026-06-01T00:00:00Z",
    finishedAt: "2026-06-01T00:00:01Z",
    dockRootValue: "not-visible",
    dockRowsCapturedAt: "2026-06-01T00:00:00Z",
    dockRows: [],
    hostSummaries: [],
    detail: {
      startedAt: "2026-06-01T00:00:00Z",
      finishedAt: "2026-06-01T00:00:01Z",
      rootIdentifier: "codexdock.session.root.host.thread",
      rootCapturedAt: "2026-06-01T00:00:00Z",
      rootValue: "host=host; thread=thread",
      headerCapturedAt: "2026-06-01T00:00:00Z",
      headerValue: "host=host; thread=thread",
      messageListCapturedAt: "2026-06-01T00:00:00Z",
      messageListValue: "events=1",
      messageCardsCapturedAt: "2026-06-01T00:00:00Z",
      messageCardIDs: ["codexdock.session.message.host_thread_turn_item"],
      requestElementsCapturedAt: "2026-06-01T00:00:00Z",
      requestCardIDs: ["codexdock.session.request.host_thread_request"],
      messageCards: [],
      requestElements: [],
    },
  };

  assertProofReport(report, { sourcePath: "sim-ui-dump-thread-sample" });
});

test("sim UI dump contract accepts visible global connectivity evidence", () => {
  const report = simUIDumpSample();
  report.sampleAfter = {
    sampleIndex: 0,
    sampledAt: "2026-06-01T00:00:00Z",
    finishedAt: "2026-06-01T00:00:01Z",
    dockRootValue: "loaded; rows=1",
    dockRowsCapturedAt: "2026-06-01T00:00:00Z",
    dockRows: [],
    globalConnectivity: {
      capturedAt: "2026-06-01T00:00:00Z",
      identifier: "codexdock.connectivity.global",
      label: "Online 1/2",
      value: "Partial: Home: JSON-RPC request `initialize` was cancelled",
      frame: { minX: 1, minY: 2, width: 3, height: 4 },
    },
    hostSummaries: [],
  };

  assertProofReport(report, { sourcePath: "sim-ui-dump-connectivity-sample" });
});

test("proof contracts reject unknown nested proof fields", () => {
  const report = simUIDumpSample();
  report.sampleAfter = {
    sampleIndex: 0,
    sampledAt: "2026-06-01T00:00:00Z",
    finishedAt: "2026-06-01T00:00:01Z",
    dockRootValue: "loaded; rows=0",
    dockRowsCapturedAt: "2026-06-01T00:00:00Z",
    dockRows: [],
    hostSummaries: [],
    sideDoorIdentity: "not allowed",
  };

  const errors = validateProofReport(report, { sourcePath: "sim-ui-dump-sample" });

  assert.match(errors.join("\n"), /fields outside the proof allow-list/u);
  assert.match(errors.join("\n"), /sideDoorIdentity/u);
});

test("proof contracts reject legacy expected message projection ids", () => {
  const report = sampleProofReports().find(
    (candidate) => candidate.kind === "codex-dock-controlled-simulator-scenario-relay-report"
  );
  report.scenarios[0].transitions = [{
    name: "detail",
    truth: {
      expectedMessageProjectionIDs: ["legacy-id"],
    },
  }];

  const errors = validateProofReport(report, { sourcePath: "scenario-relay-sample" });

  assert.match(errors.join("\n"), /expectedMessageProjectionIDs/u);
});

test("controlled scenario contract accepts relay render-order proof fields", () => {
  const report = sampleProofReports().find(
    (candidate) => candidate.kind === "codex-dock-controlled-simulator-scenario-relay-report"
  );
  const renderOrderProjectionIDs = ["host:host/thread:thread-a/row:threadCard"];
  const snapshot = {
    kind: "snapshot",
    rowCount: 1,
    renderOrderProjectionIDs,
    rows: [{ projectionID: renderOrderProjectionIDs[0], threadID: "thread-a" }],
  };
  report.samples = [{
    sampleIndex: 0,
    freshDock: snapshot,
  }];
  report.scenarios = [{
    id: "archive-toggle",
    ok: true,
    actuator: {
      type: "controlled archive/unarchive through relay RPC",
      routes: ["thread/archive", "thread/unarchive"],
      clientExercised: true,
    },
    transitions: [{
      name: "archive",
      kind: "archive",
      wait: { ok: true, snapshot },
      freshDock: snapshot,
      archiveStreamWait: { ok: true, snapshot },
      freshArchive: snapshot,
    }],
  }];
  report.stream = {
    finalState: snapshot,
    finalArchiveState: snapshot,
  };
  report.unsupportedFacts = [];

  assertProofReport(report, { sourcePath: "controlled-scenario-render-order-sample" });
});

test("simulator UI sync contract accepts transition coverage sections", () => {
  const report = sampleProofReports().find(
    (candidate) => candidate.kind === "codex-dock-simulator-ui-sync-proof"
  );
  report.scenarioTransitionCoverage = {
    checks: [{
      transition: "archive",
      observedLagMs: 100,
      ok: true,
      failures: [],
    }],
    failures: [],
  };
  report.detailTransitionCoverage = {
    checks: [{
      transition: "detail-open",
      observedLagMs: 100,
      ok: true,
      messageOrderChecks: 1,
      failures: [],
    }],
    failures: [],
  };

  assertProofReport(report, { sourcePath: "sim-ui-transition-coverage-sample" });
});

test("passing proof cannot use thread/detail/read as route evidence", () => {
  const report = sampleProofReports().find(
    (candidate) => candidate.kind === "codex-dock-relay-sync-audit-report"
  );
  report.clientPathEvidence = {
    routes: ["thread/detail/read"],
    routeCounts: { "thread/detail/read": 1 },
  };
  report.summary.clientPathRouteCounts = { "thread/detail/read": 1 };

  const errors = validateProofReport(report, { sourcePath: "relay-sync-audit-sample" });

  assert.match(errors.join("\n"), /property name must be valid/u);
  assert.match(errors.join("\n"), /must include relay-owned Dock, Archive, or Thread Detail client routes/u);
});

test("blocked proof can record non-client route counts without counting them as client path proof", () => {
  const report = sampleProofReports().find(
    (candidate) => candidate.kind === "codex-dock-controlled-simulator-scenario-relay-report"
  );
  report.status = "blocked";
  report.clientPathEvidence = {
    routes: ["thread/detail/subscribe"],
    routeCounts: { "thread/detail/subscribe": 1 },
    nonClientPathRoutes: [
      { route: "thread/detail/read", count: 2 },
      { route: "thread/read", count: 1 },
    ],
  };

  assertProofReport(report, { sourcePath: "controlled-scenario-non-client-route-sample" });
});

test("passing controlled simulator proof rejects simulator-app downstream raw detail routes", () => {
  const report = sampleProofReports().find(
    (candidate) => candidate.kind === "codex-dock-controlled-simulator-scenario-relay-report"
  );
  report.clientPathEvidence = {
    routes: ["dock/subscribe", "thread/detail/subscribe"],
    routeCounts: { "dock/subscribe": 1, "thread/detail/subscribe": 1 },
  };
  report.summary.clientPathRouteCounts = report.clientPathEvidence.routeCounts;
  report.simulatorClientPathEvidence = {
    routes: ["thread/detail/subscribe"],
    routeCounts: { "thread/detail/subscribe": 1 },
    events: [
      {
        route: "thread/read",
        source: "simulatorAppProxy",
        boundary: "simulatorAppToRelay",
      },
      {
        route: "thread/resume",
        source: "fixtureUpstream",
        boundary: "relayToFixtureUpstream",
      },
    ],
  };

  const errors = validateProofReport(report, { sourcePath: "controlled-simulator-sample" });

  assert.match(errors.join("\n"), /simulator app downstream routes outside the proof route allow-list cannot satisfy live-update proof/u);
  assert.match(errors.join("\n"), /thread\/read/u);
  assert.doesNotMatch(errors.join("\n"), /thread\/resume/u);
});

test("controlled simulator proof schema accepts simulator-only client path evidence", () => {
  const report = sampleProofReports().find(
    (candidate) => candidate.kind === "codex-dock-controlled-simulator-scenario-relay-report"
  );
  report.simulatorClientPathEvidence = {
    routes: ["thread/detail/subscribe", "thread/detail/resync"],
    routeCounts: {
      "thread/detail/subscribe": 1,
      "thread/detail/resync": 1,
    },
    events: [
      {
        route: "thread/detail/subscribe",
        source: "simulatorAppProxy",
        boundary: "simulatorAppToRelay",
        hasResponseID: true,
      },
    ],
  };

  assertProofReport(report, { sourcePath: "controlled-simulator-sample" });
});

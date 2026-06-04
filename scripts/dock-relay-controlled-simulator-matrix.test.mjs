import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import {
  buildMatrixReport,
  evaluateReportEntry,
  parseArgs,
  readReportDir,
  validateOptions,
} from "./dock-relay-controlled-simulator-matrix.mjs";
import {
  validateProofReport,
} from "./proof-report-contracts.mjs";

function relayReport({ scenario = "thread-activity", ok = true, routes = {}, proofRunID = "proof-run", events = [] } = {}) {
  return {
    schemaVersion: 1,
    kind: "codex-dock-controlled-simulator-scenario-relay-report",
    status: ok ? "pass" : "fail",
    mode: "scenario",
    scenario,
    startedAt: "2026-06-01T00:00:00Z",
    endedAt: "2026-06-01T00:00:01Z",
    relayUrl: "ws://127.0.0.1:4510",
    proofRunID,
    summary: {
      ok,
      clientPathOK: ok,
      scenario,
      clientPathRouteCounts: routes,
    },
    clientPathEvidence: {
      routes: Object.keys(routes),
      routeCounts: routes,
      events,
    },
    samples: [],
    scenarios: [{ id: scenario, ok }],
    findings: ok ? [] : [{ code: "example", message: "failed" }],
  };
}

function uiReport({
  proofRunID = "proof-run",
  ok = true,
  scenarioChecks = 2,
  detailChecks = 0,
  checkpointSweeps = 1,
  checkpointSweepRowChecks = 3,
  dockVisibleOrderChecks = 0,
  dockSweepOrderChecks = 0,
  detailSweeps = 0,
  detailSweepMessageCardChecks = 0,
  detailMessageOrderChecks = 0,
  scenarioFailures = 0,
  detailFailures = 0,
  observedLagMs = 100,
  transitionLagMs = 100,
} = {}) {
  return {
    schemaVersion: 1,
    kind: "codex-dock-simulator-ui-sync-proof",
    status: ok ? "pass" : "fail",
    proofRunID,
    startedAt: "2026-06-01T00:00:00Z",
    endedAt: "2026-06-01T00:00:01Z",
    relayReport: {
      proofRunID,
      relayUrl: "ws://127.0.0.1:4510",
      clientPathOK: ok,
      clientPathRoutes: ["dock/subscribe"],
    },
    summary: {
      ok,
      uiSampleCount: 5,
      scoredUISampleCount: 5,
      scenarioTransitionChecks: scenarioChecks,
      detailTransitionChecks: detailChecks,
      checkpointSweepCount: checkpointSweeps,
      checkpointSweepRowChecks,
      dockVisibleOrderChecks,
      dockSweepOrderChecks,
      detailSweepCount: detailSweeps,
      detailSweepMessageCardChecks,
      detailMessageOrderChecks,
      scenarioTransitionFailures: scenarioFailures,
      detailTransitionFailures: detailFailures,
      uiLag: {
        ok: observedLagMs <= 2_000,
        observedLagMs,
      },
      failures: ok ? 0 : 1,
    },
    scenarioTransitionCoverage: {
      checks: scenarioChecks > 0
        ? [{ transition: "example", observedLagMs: transitionLagMs, ok: transitionLagMs <= 2_000 }]
        : [],
    },
    detailTransitionCoverage: {
      checks: detailChecks > 0
        ? [{ transition: "detail", observedLagMs: transitionLagMs, ok: transitionLagMs <= 2_000 }]
        : [],
    },
    failures: ok ? [] : [{ code: "example", message: "failed" }],
  };
}

function entry({ scenario = "thread-activity", routes = { "dock/subscribe": 1, "dock/update": 1 }, ui = {}, relay = {} } = {}) {
  const proofRunID = relay.proofRunID || ui.proofRunID || "proof-run";
  return {
    dir: `/tmp/${scenario}`,
    relayReport: relayReport({ scenario, routes, proofRunID, ...relay }),
    uiReport: uiReport({ proofRunID, ...ui }),
  };
}

test("controlled simulator matrix parses report dirs and defaults", () => {
  const options = parseArgs([
    "--report-dir",
    "/tmp/a",
    "--report-dir",
    "/tmp/b",
    "--json-out",
    "/tmp/matrix.json",
    "--summary-out",
    "/tmp/matrix.md",
    "--min-passes",
    "2",
  ]);

  validateOptions(options);

  assert.deepEqual(options.reportDirs, ["/tmp/a", "/tmp/b"]);
  assert.equal(options.jsonOut, "/tmp/matrix.json");
  assert.equal(options.summaryOut, "/tmp/matrix.md");
  assert.equal(options.minPasses, 2);
  assert.ok(options.requiredScenarios.includes("archive-toggle"));
  assert.ok(options.requiredScenarios.includes("detail-reconnect"));
  assert.ok(options.requiredScenarios.includes("detail-history-request"));
  assert.ok(options.requiredScenarios.includes("large-list-checkpoint"));
  assert.ok(options.requiredScenarios.includes("rapid-mutations"));
  assert.ok(options.requiredScenarios.includes("server-rename-notification"));
  assert.ok(options.requiredScenarios.includes("server-status-notification"));
});

test("proof contracts reject passing live proof with no client route evidence", () => {
  const report = relayReport({ scenario: "thread-activity", routes: {} });
  const errors = validateProofReport(report);
  assert.match(errors.join("\n"), /must include relay-owned client route evidence/u);
});

test("controlled simulator matrix validates input reports against proof contracts", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "codex-dock-matrix-test-"));
  try {
    const reportDir = path.join(root, "thread-activity");
    fs.mkdirSync(reportDir, { recursive: true });
    fs.writeFileSync(
      path.join(reportDir, "relay-client-path.json"),
      `${JSON.stringify({ summary: { ok: true, scenario: "thread-activity" } })}\n`
    );
    fs.writeFileSync(
      path.join(reportDir, "simulator-ui-sync.json"),
      `${JSON.stringify(uiReport())}\n`
    );

    assert.throws(
      () => readReportDir(reportDir),
      /proof report contract failed/u
    );
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test("controlled simulator matrix requires archive-toggle routes and transitions", () => {
  const report = buildMatrixReport({
    entries: [
      entry({
        scenario: "archive-toggle",
        routes: { "dock/subscribe": 1, "dock/update": 1, "thread/archive": 1 },
        ui: { scenarioChecks: 1 },
      }),
    ],
    requiredScenarios: ["archive-toggle"],
    minPasses: 1,
    maxUiLagMs: 2_000,
  });

  assert.equal(report.summary.ok, false);
  assert.match(report.findings.map((finding) => finding.code).join(","), /matrix_required_route_missing/u);
  assert.match(report.findings.map((finding) => finding.code).join(","), /matrix_scenario_transition_checks_missing/u);
});

test("controlled simulator matrix accepts a passing required scenario", () => {
  const report = buildMatrixReport({
    entries: [entry()],
    requiredScenarios: ["thread-activity"],
    minPasses: 1,
    maxUiLagMs: 2_000,
  });

  assert.equal(report.summary.ok, true);
  assert.equal(report.summary.passingScenarioCount, 1);
  assert.equal(report.findings.length, 0);
});

test("controlled simulator matrix accepts server rename notification coverage", () => {
  const report = buildMatrixReport({
    entries: [
      entry({
        scenario: "server-rename-notification",
        routes: { "dock/subscribe": 1, "dock/update": 1 },
        ui: { scenarioChecks: 1 },
      }),
    ],
    requiredScenarios: ["server-rename-notification"],
    minPasses: 1,
    maxUiLagMs: 2_000,
  });

  assert.equal(report.summary.ok, true);
  assert.equal(report.scenarios[0].scenario, "server-rename-notification");
  assert.equal(report.scenarios[0].passingReportCount, 1);
  assert.equal(report.findings.length, 0);
});

test("controlled simulator matrix accepts server status notification coverage", () => {
  const report = buildMatrixReport({
    entries: [
      entry({
        scenario: "server-status-notification",
        routes: { "dock/subscribe": 1, "dock/update": 1 },
        ui: { scenarioChecks: 1 },
      }),
    ],
    requiredScenarios: ["server-status-notification"],
    minPasses: 1,
    maxUiLagMs: 2_000,
  });

  assert.equal(report.summary.ok, true);
  assert.equal(report.scenarios[0].scenario, "server-status-notification");
  assert.equal(report.scenarios[0].passingReportCount, 1);
  assert.equal(report.findings.length, 0);
});

test("controlled simulator matrix requires variant fixtures to report the invoked scenario", () => {
  const report = buildMatrixReport({
    entries: [
      entry({
        scenario: "detail-replay-pressure",
        routes: { "thread/detail/subscribe": 1, "thread/detail/update": 1 },
        relay: { scenario: "detail-replay-pressure" },
        ui: {
          scenarioChecks: 0,
          detailChecks: 4,
          detailSweeps: 1,
          detailSweepMessageCardChecks: 10,
          detailMessageOrderChecks: 3,
        },
      }),
    ],
    requiredScenarios: ["detail-replay-pressure"],
    minPasses: 1,
    maxUiLagMs: 2_000,
  });

  assert.equal(report.summary.ok, true);
  assert.equal(report.scenarios[0].scenario, "detail-replay-pressure");
  assert.equal(report.scenarios[0].passingReportCount, 1);
  assert.equal(report.findings.length, 0);
});

test("controlled simulator matrix rejects unapproved invoked-scenario fixture mismatches", () => {
  const result = evaluateReportEntry(
    entry({
      scenario: "detail-replay-pressure",
      routes: { "thread/detail/subscribe": 1, "thread/detail/update": 1 },
      relay: { scenario: "detail-history-request" },
      ui: {
        scenarioChecks: 0,
        detailChecks: 4,
        detailSweeps: 1,
        detailSweepMessageCardChecks: 10,
        detailMessageOrderChecks: 3,
      },
    }),
    { maxUiLagMs: 2_000 }
  );

  assert.equal(result.ok, false);
  assert.match(result.failures.map((failure) => failure.code).join(","), /matrix_reported_scenario_mismatch/u);
});

test("controlled simulator matrix fails missing required scenarios", () => {
  const report = buildMatrixReport({
    entries: [entry()],
    requiredScenarios: ["thread-activity", "resync-gap"],
    minPasses: 1,
    maxUiLagMs: 2_000,
  });

  assert.equal(report.summary.ok, false);
  assert.equal(report.summary.missingScenarioCount, 1);
  assert.match(report.findings.map((finding) => finding.code).join(","), /matrix_required_scenario_missing/u);
});

test("controlled simulator matrix fails reports with missing required routes", () => {
  const result = evaluateReportEntry(
    entry({ scenario: "resync-gap", routes: { "dock/subscribe": 1, "dock/update": 1 }, ui: { scenarioChecks: 1 } }),
    { maxUiLagMs: 2_000 }
  );

  assert.equal(result.ok, false);
  assert.match(result.failures.map((failure) => failure.code).join(","), /matrix_required_route_missing/u);
});

test("controlled simulator matrix requires broad checkpoint row coverage", () => {
  const report = buildMatrixReport({
    entries: [
      entry({
        scenario: "large-list-checkpoint",
        routes: { "dock/subscribe": 1 },
        ui: { scenarioChecks: 0, checkpointSweepRowChecks: 4 },
      }),
    ],
    requiredScenarios: ["large-list-checkpoint"],
    minPasses: 1,
    maxUiLagMs: 2_000,
  });

  assert.equal(report.summary.ok, false);
  assert.match(report.findings.map((finding) => finding.code).join(","), /matrix_checkpoint_sweep_row_checks_missing/u);
});

test("controlled simulator matrix requires checkpoint Dock order coverage", () => {
  const report = buildMatrixReport({
    entries: [
      entry({
        scenario: "large-list-checkpoint",
        routes: { "dock/subscribe": 1 },
        ui: { scenarioChecks: 0, checkpointSweepRowChecks: 12, dockSweepOrderChecks: 0 },
      }),
    ],
    requiredScenarios: ["large-list-checkpoint"],
    minPasses: 1,
    maxUiLagMs: 2_000,
  });

  assert.equal(report.summary.ok, false);
  assert.match(report.findings.map((finding) => finding.code).join(","), /matrix_dock_sweep_order_checks_missing/u);
});

test("controlled simulator matrix accepts root catchup partial sweep with visible order coverage", () => {
  const report = buildMatrixReport({
    entries: [
      entry({
        scenario: "root-catchup-window-contract",
        routes: { "dock/subscribe": 1, "dock/update": 1 },
        ui: {
          scenarioChecks: 0,
          checkpointSweepRowChecks: 17,
          dockVisibleOrderChecks: 1,
          dockSweepOrderChecks: 0,
        },
      }),
    ],
    requiredScenarios: ["root-catchup-window-contract"],
    minPasses: 1,
    maxUiLagMs: 2_000,
  });

  assert.equal(report.summary.ok, true);
  assert.equal(report.findings.length, 0);
});

test("controlled simulator matrix requires opened-thread detail sweep coverage", () => {
  const report = buildMatrixReport({
    entries: [
      entry({
        scenario: "detail-history-request",
        routes: { "thread/detail/subscribe": 1, "thread/detail/update": 1 },
        ui: { scenarioChecks: 0, detailChecks: 3, detailSweeps: 1, detailSweepMessageCardChecks: 4 },
      }),
    ],
    requiredScenarios: ["detail-history-request"],
    minPasses: 1,
    maxUiLagMs: 2_000,
  });

  assert.equal(report.summary.ok, false);
  assert.match(report.findings.map((finding) => finding.code).join(","), /matrix_detail_sweep_message_checks_missing/u);
});

test("controlled simulator matrix requires opened-thread message order coverage", () => {
  const report = buildMatrixReport({
    entries: [
      entry({
        scenario: "detail-history-request",
        routes: { "thread/detail/subscribe": 1, "thread/detail/update": 1 },
        ui: {
          scenarioChecks: 0,
          detailChecks: 3,
          detailSweeps: 1,
          detailSweepMessageCardChecks: 8,
          detailMessageOrderChecks: 0,
        },
      }),
    ],
    requiredScenarios: ["detail-history-request"],
    minPasses: 1,
    maxUiLagMs: 2_000,
  });

  assert.equal(report.summary.ok, false);
  assert.match(report.findings.map((finding) => finding.code).join(","), /matrix_detail_message_order_checks_missing/u);
});

test("controlled simulator matrix requires the detail reconnect projection route shape", () => {
  const report = buildMatrixReport({
    entries: [
      entry({
        scenario: "detail-reconnect",
        routes: { "thread/detail/subscribe": 1 },
        ui: { scenarioChecks: 0, detailChecks: 1, detailSweeps: 1, detailSweepMessageCardChecks: 2 },
      }),
    ],
    requiredScenarios: ["detail-reconnect"],
    minPasses: 1,
    maxUiLagMs: 2_000,
  });

  assert.equal(report.summary.ok, false);
  assert.match(report.findings.map((finding) => finding.code).join(","), /matrix_required_route_count_too_low/u);
});

test("controlled simulator matrix requires the detail reconnect resync transition", () => {
  const report = buildMatrixReport({
    entries: [
      entry({
        scenario: "detail-reconnect",
        routes: { "thread/detail/subscribe": 1, "thread/detail/resync": 1 },
        ui: {
          scenarioChecks: 0,
          detailChecks: 0,
          detailSweeps: 1,
          detailSweepMessageCardChecks: 2,
          detailMessageOrderChecks: 1,
        },
      }),
    ],
    requiredScenarios: ["detail-reconnect"],
    minPasses: 1,
    maxUiLagMs: 2_000,
  });

  assert.equal(report.summary.ok, false);
  assert.match(report.findings.map((finding) => finding.code).join(","), /matrix_detail_transition_checks_missing/u);
});

test("controlled simulator matrix does not accept UI-embedded route counts as relay route proof", () => {
  const reportEntry = entry({
    scenario: "detail-reconnect",
    routes: {},
    ui: {
      scenarioChecks: 0,
      detailChecks: 1,
      detailSweeps: 1,
      detailSweepMessageCardChecks: 2,
      detailMessageOrderChecks: 1,
    },
  });
  reportEntry.uiReport.relayReport.routeCounts = {
    "thread/detail/subscribe": 1,
    "thread/detail/resync": 1,
  };
  const report = buildMatrixReport({
    entries: [reportEntry],
    requiredScenarios: ["detail-reconnect"],
    minPasses: 1,
    maxUiLagMs: 2_000,
  });

  assert.equal(report.summary.ok, false);
  assert.match(report.findings.map((finding) => finding.code).join(","), /matrix_required_route_missing/u);
});

test("controlled simulator matrix fails lagged UI transitions", () => {
  const report = buildMatrixReport({
    entries: [
      entry({
        scenario: "rapid-mutations",
        routes: { "dock/subscribe": 1, "dock/update": 1 },
        ui: { scenarioChecks: 6, observedLagMs: 2_500, transitionLagMs: 2_500 },
      }),
    ],
    requiredScenarios: ["rapid-mutations"],
    minPasses: 1,
    maxUiLagMs: 2_000,
  });

  assert.equal(report.summary.ok, false);
  assert.match(report.findings.map((finding) => finding.code).join(","), /matrix_ui_lag_exceeded/u);
});

test("controlled simulator matrix enforces per-scenario pass count", () => {
  const report = buildMatrixReport({
    entries: [entry()],
    requiredScenarios: ["thread-activity"],
    minPasses: 2,
    maxUiLagMs: 2_000,
  });

  assert.equal(report.summary.ok, false);
  assert.equal(report.scenarios[0].passingReportCount, 1);
  assert.match(report.findings.map((finding) => finding.code).join(","), /matrix_required_scenario_insufficient_passes/u);
});

test("controlled simulator matrix does not count a duplicated report dir as two passes", () => {
  const report = buildMatrixReport({
    entries: [entry(), entry()],
    requiredScenarios: ["thread-activity"],
    minPasses: 2,
    maxUiLagMs: 2_000,
  });

  assert.equal(report.summary.ok, false);
  assert.equal(report.scenarios[0].status, "fail");
  assert.equal(report.scenarios[0].passingReportCount, 2);
  assert.match(report.findings.map((finding) => finding.code).join(","), /matrix_duplicate_report_dir/u);
});

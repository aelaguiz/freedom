import assert from "node:assert/strict";
import test from "node:test";

import {
  buildMatrixReport,
  evaluateReportEntry,
  parseArgs,
  validateOptions,
} from "./dock-relay-controlled-simulator-matrix.mjs";

function relayReport({ scenario = "thread-activity", ok = true, routes = {} } = {}) {
  return {
    summary: {
      ok,
      clientPathOK: ok,
      scenario,
      clientPathRouteCounts: routes,
    },
    clientPathEvidence: {
      routeCounts: routes,
    },
  };
}

function uiReport({
  ok = true,
  scenarioChecks = 2,
  detailChecks = 0,
  checkpointSweeps = 1,
  checkpointSweepRowChecks = 3,
  detailSweeps = 0,
  detailSweepMessageCardChecks = 0,
  scenarioFailures = 0,
  detailFailures = 0,
  observedLagMs = 100,
  transitionLagMs = 100,
} = {}) {
  return {
    summary: {
      ok,
      uiSampleCount: 5,
      scoredUISampleCount: 5,
      scenarioTransitionChecks: scenarioChecks,
      detailTransitionChecks: detailChecks,
      checkpointSweepCount: checkpointSweeps,
      checkpointSweepRowChecks,
      detailSweepCount: detailSweeps,
      detailSweepMessageCardChecks,
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
  return {
    dir: `/tmp/${scenario}`,
    relayReport: relayReport({ scenario, routes, ...relay }),
    uiReport: uiReport(ui),
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
  assert.ok(options.requiredScenarios.includes("detail-history-request"));
  assert.ok(options.requiredScenarios.includes("large-list-checkpoint"));
  assert.ok(options.requiredScenarios.includes("rapid-mutations"));
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

test("controlled simulator matrix requires opened-thread detail sweep coverage", () => {
  const report = buildMatrixReport({
    entries: [
      entry({
        scenario: "detail-history-request",
        routes: { "thread/read": 1, "thread/turns/list": 2, "thread/resume": 1 },
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

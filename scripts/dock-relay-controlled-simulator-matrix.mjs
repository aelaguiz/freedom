#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

import {
  assertProofReport,
  finalizeProofReport,
} from "./proof-report-contracts.mjs";

const DEFAULT_REQUIRED_SCENARIOS = [
  "archive-toggle",
  "current-work-visible",
  "detail-reconnect",
  "detail-history-request",
  "detail-replay-pressure",
  "foreground-resume-all-surfaces",
  "large-list-checkpoint",
  "thread-activity",
  "server-rename-notification",
  "server-status-notification",
  "server-request",
  "source-refresh",
  "live-lease-expiry",
  "multi-host-isolation",
  "mutation-ack-projection-refresh-failure",
  "spawned-private-child-status-rollup",
  "spawn-edge",
  "resync-gap",
  "root-catchup-window-contract",
  "rapid-mutations",
];

const DEFAULT_MAX_UI_LAG_MS = 2_000;

const SCENARIO_REQUIREMENTS = {
  "archive-toggle": {
    routes: ["dock/subscribe", "dock/update", "archive/subscribe", "archive/update", "thread/archive", "thread/unarchive"],
    minScenarioTransitionChecks: 2,
    minCheckpointSweeps: 1,
  },
  "detail-reconnect": {
    routes: ["thread/detail/subscribe", "thread/detail/resync"],
    minRouteCounts: { "thread/detail/subscribe": 1, "thread/detail/resync": 1 },
    minDetailTransitionChecks: 1,
    minDetailSweeps: 1,
    minDetailSweepMessageCardChecks: 2,
    minDetailMessageOrderChecks: 1,
  },
  "foreground-resume-all-surfaces": {
    routes: ["thread/detail/subscribe", "thread/detail/resync"],
    minRouteCounts: { "thread/detail/subscribe": 1, "thread/detail/resync": 1 },
    minDetailTransitionChecks: 1,
    minDetailSweeps: 1,
    minDetailSweepMessageCardChecks: 2,
    minDetailMessageOrderChecks: 1,
  },
  "detail-history-request": {
    routes: ["thread/detail/subscribe", "thread/detail/update"],
    minDetailTransitionChecks: 3,
    minDetailSweeps: 1,
    minDetailSweepMessageCardChecks: 8,
    minDetailMessageOrderChecks: 2,
  },
  "detail-replay-pressure": {
    routes: ["thread/detail/subscribe", "thread/detail/update"],
    minDetailTransitionChecks: 4,
    minDetailSweeps: 1,
    minDetailSweepMessageCardChecks: 10,
    minDetailMessageOrderChecks: 3,
  },
  "large-list-checkpoint": {
    routes: ["dock/subscribe"],
    minCheckpointSweeps: 1,
    minCheckpointSweepRowChecks: 12,
    minDockSweepOrderChecks: 1,
  },
  "root-catchup-window-contract": {
    routes: ["dock/subscribe", "dock/update"],
    minCheckpointSweeps: 1,
    minCheckpointSweepRowChecks: 12,
    minDockVisibleOrderChecks: 1,
  },
  "thread-activity": {
    routes: ["dock/subscribe", "dock/update"],
    minScenarioTransitionChecks: 2,
    minCheckpointSweeps: 1,
  },
  "server-rename-notification": {
    routes: ["dock/subscribe", "dock/update"],
    minScenarioTransitionChecks: 1,
    minCheckpointSweeps: 1,
  },
  "server-status-notification": {
    routes: ["dock/subscribe", "dock/update"],
    minScenarioTransitionChecks: 1,
    minCheckpointSweeps: 1,
  },
  "current-work-visible": {
    routes: ["dock/subscribe", "dock/update"],
    minScenarioTransitionChecks: 2,
    minCheckpointSweeps: 1,
  },
  "server-request": {
    routes: ["thread/detail/subscribe", "thread/detail/update"],
    minDetailTransitionChecks: 2,
    minCheckpointSweeps: 1,
  },
  "source-refresh": {
    routes: ["dock/subscribe", "dock/update"],
    minScenarioTransitionChecks: 2,
    minCheckpointSweeps: 1,
  },
  "live-lease-expiry": {
    routes: ["dock/subscribe", "dock/update"],
    minScenarioTransitionChecks: 1,
    minCheckpointSweeps: 1,
  },
  "multi-host-isolation": {
    routes: ["dock/subscribe", "dock/update"],
    minScenarioTransitionChecks: 1,
    minCheckpointSweeps: 1,
  },
  "spawn-edge": {
    routes: ["dock/subscribe", "dock/update"],
    minScenarioTransitionChecks: 1,
    minCheckpointSweeps: 1,
  },
  "spawned-private-child-status-rollup": {
    routes: ["dock/subscribe", "dock/update"],
    minScenarioTransitionChecks: 1,
    minCheckpointSweeps: 1,
  },
  "resync-gap": {
    routes: ["dock/subscribe", "dock/update", "dock/resync"],
    minScenarioTransitionChecks: 1,
    minCheckpointSweeps: 1,
  },
  "rapid-mutations": {
    routes: ["dock/subscribe", "dock/update"],
    minScenarioTransitionChecks: 6,
    minCheckpointSweeps: 1,
  },
  "mutation-ack-projection-refresh-failure": {
    routes: ["dock/subscribe", "dock/update", "dock/resync", "archive/subscribe", "archive/update", "thread/archive", "thread/unarchive"],
    minScenarioTransitionChecks: 3,
    minCheckpointSweeps: 1,
  },
};

function usage() {
  return [
    "Usage:",
    "  node scripts/dock-relay-controlled-simulator-matrix.mjs --report-dir <dir> [--report-dir <dir> ...] --json-out <path> [options]",
    "",
    "Options:",
    "  --summary-out <path>      Write Markdown summary.",
    "  --require <scenario>      Required scenario. Defaults to the controlled simulator matrix.",
    "  --min-passes <count>      Required passing report count per scenario. Default: 1.",
    "  --max-ui-lag-ms <ms>      Rendered UI lag budget. Default: 2000.",
    "  --fail-on-diff           Exit non-zero when the matrix fails.",
    "  --help                   Show this help.",
  ].join("\n");
}

function parseArgs(argv) {
  const options = {
    reportDirs: [],
    requiredScenarios: [],
    jsonOut: null,
    summaryOut: null,
    minPasses: 1,
    maxUiLagMs: DEFAULT_MAX_UI_LAG_MS,
    failOnDiff: false,
    help: false,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    const next = () => {
      index += 1;
      if (index >= argv.length) {
        throw new Error(`missing value for ${arg}`);
      }
      return argv[index];
    };
    if (arg === "--report-dir") {
      options.reportDirs.push(next());
    } else if (arg === "--require") {
      options.requiredScenarios.push(next());
    } else if (arg === "--json-out") {
      options.jsonOut = next();
    } else if (arg === "--summary-out") {
      options.summaryOut = next();
    } else if (arg === "--min-passes") {
      options.minPasses = Number(next());
    } else if (arg === "--max-ui-lag-ms") {
      options.maxUiLagMs = Number(next());
    } else if (arg === "--fail-on-diff") {
      options.failOnDiff = true;
    } else if (arg === "--help" || arg === "-h") {
      options.help = true;
    } else {
      throw new Error(`unknown argument ${arg}`);
    }
  }
  if (!options.requiredScenarios.length) {
    options.requiredScenarios = [...DEFAULT_REQUIRED_SCENARIOS];
  }
  return options;
}

function validateOptions(options) {
  if (options.help) {
    return;
  }
  if (!options.reportDirs.length) {
    throw new Error("--report-dir is required at least once");
  }
  if (!options.jsonOut) {
    throw new Error("--json-out is required");
  }
  if (!Number.isInteger(options.minPasses) || options.minPasses < 1) {
    throw new Error("--min-passes must be a positive integer");
  }
  if (!Number.isFinite(options.maxUiLagMs) || options.maxUiLagMs < 0) {
    throw new Error("--max-ui-lag-ms must be a non-negative number");
  }
}

function readJSON(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function readReportDir(reportDir) {
  const relayReportPath = path.join(reportDir, "relay-client-path.json");
  const uiReportPath = path.join(reportDir, "simulator-ui-sync.json");
  const relayReport = readJSON(relayReportPath);
  const uiReport = readJSON(uiReportPath);
  assertProofReport(relayReport, { sourcePath: relayReportPath });
  assertProofReport(uiReport, { sourcePath: uiReportPath });
  return {
    dir: reportDir,
    relayReportPath,
    uiReportPath,
    relayReport,
    uiReport,
  };
}

function routeCountsFor(entry) {
  return entry.relayReport?.clientPathEvidence?.routeCounts || {};
}

function directoryScenarioFor(entry) {
  const candidate = path.basename(path.resolve(entry?.dir || ""));
  return Object.prototype.hasOwnProperty.call(SCENARIO_REQUIREMENTS, candidate) ? candidate : null;
}

function reportedScenarioFor(entry) {
  return entry.relayReport?.summary?.scenario
    || entry.relayReport?.scenario
    || entry.uiReport?.relayReport?.scenario
    || null;
}

function scenarioFor(entry) {
  return directoryScenarioFor(entry) || reportedScenarioFor(entry);
}

function allowedReportedScenariosFor(scenario) {
  return new Set([scenario]);
}

function transitionChecks(uiReport) {
  return [
    ...(uiReport?.scenarioTransitionCoverage?.checks || []),
    ...(uiReport?.detailTransitionCoverage?.checks || []),
  ];
}

function maxObservedTransitionLag(uiReport) {
  const values = transitionChecks(uiReport)
    .map((check) => Number(check?.observedLagMs))
    .filter((value) => Number.isFinite(value));
  const uiLag = Number(uiReport?.summary?.uiLag?.observedLagMs);
  if (Number.isFinite(uiLag)) {
    values.push(uiLag);
  }
  return values.length ? Math.max(...values) : null;
}

function evaluateReportEntry(entry, { maxUiLagMs }) {
  const failures = [];
  const scenario = scenarioFor(entry);
  const directoryScenario = directoryScenarioFor(entry);
  const reportedScenario = reportedScenarioFor(entry);
  const requirements = SCENARIO_REQUIREMENTS[scenario] || {};
  const routeCounts = routeCountsFor(entry);
  const relaySummary = entry.relayReport?.summary || {};
  const uiSummary = entry.uiReport?.summary || {};
  const relayProofRunID = entry.relayReport?.proofRunID || null;
  const uiProofRunID = entry.uiReport?.proofRunID || entry.uiReport?.relayReport?.proofRunID || null;
  const scenarioChecks = Number(uiSummary.scenarioTransitionChecks || 0);
  const detailChecks = Number(uiSummary.detailTransitionChecks || 0);
  const checkpointSweeps = Number(uiSummary.checkpointSweepCount || 0);
  const checkpointSweepRowChecks = Number(uiSummary.checkpointSweepRowChecks || 0);
  const dockVisibleOrderChecks = Number(uiSummary.dockVisibleOrderChecks || 0);
  const dockSweepOrderChecks = Number(uiSummary.dockSweepOrderChecks || 0);
  const detailSweeps = Number(uiSummary.detailSweepCount || 0);
  const detailSweepMessageCardChecks = Number(uiSummary.detailSweepMessageCardChecks || 0);
  const detailMessageOrderChecks = Number(uiSummary.detailMessageOrderChecks || 0);
  const maxLag = maxObservedTransitionLag(entry.uiReport);

  if (!scenario) {
    failures.push({
      code: "matrix_scenario_missing",
      message: "Controlled simulator report did not name its scenario.",
    });
  }
  if (
    directoryScenario
    && reportedScenario
    && !allowedReportedScenariosFor(directoryScenario).has(reportedScenario)
  ) {
    failures.push({
      code: "matrix_reported_scenario_mismatch",
      message: `Report directory ${directoryScenario} contained relay scenario ${reportedScenario}; strict matrix proof requires the invoked scenario to report itself.`,
      scenario: directoryScenario,
      expected: [...allowedReportedScenariosFor(directoryScenario)].sort(),
      reportedScenario,
    });
  }
  if (relaySummary.ok !== true || relaySummary.clientPathOK !== true) {
    failures.push({
      code: "matrix_relay_report_failed",
      message: "Relay client-path report did not pass.",
      relayOK: relaySummary.ok ?? null,
      clientPathOK: relaySummary.clientPathOK ?? null,
    });
  }
  if (uiSummary.ok !== true) {
    failures.push({
      code: "matrix_ui_report_failed",
      message: "Simulator displayed-UI report did not pass.",
      uiOK: uiSummary.ok ?? null,
      failureCount: Number(uiSummary.failures || 0),
    });
  }
  if (!relayProofRunID || !uiProofRunID || relayProofRunID !== uiProofRunID) {
    failures.push({
      code: "matrix_proof_run_mismatch",
      message: "Relay and simulator UI reports do not share the same proof run id, so the matrix cannot trust that the artifacts came from the same run.",
      relayProofRunID,
      uiProofRunID,
    });
  }
  for (const route of requirements.routes || []) {
    if (!routeCounts[route]) {
      failures.push({
        code: "matrix_required_route_missing",
        message: `Scenario ${scenario} did not exercise required route ${route}.`,
        scenario,
        route,
      });
    }
  }
  for (const [route, expectedCount] of Object.entries(requirements.minRouteCounts || {})) {
    const actualCount = Number(routeCounts[route] || 0);
    if (actualCount < expectedCount) {
      failures.push({
        code: "matrix_required_route_count_too_low",
        message: `Scenario ${scenario} did not exercise required route ${route} enough times.`,
        scenario,
        route,
        expected: expectedCount,
        observedCount: actualCount,
      });
    }
  }
  if (scenarioChecks < (requirements.minScenarioTransitionChecks || 0)) {
    failures.push({
      code: "matrix_scenario_transition_checks_missing",
      message: `Scenario ${scenario} did not record enough rendered scenario transition checks.`,
      scenario,
      expected: requirements.minScenarioTransitionChecks || 0,
      observedCount: scenarioChecks,
    });
  }
  if (detailChecks < (requirements.minDetailTransitionChecks || 0)) {
    failures.push({
      code: "matrix_detail_transition_checks_missing",
      message: `Scenario ${scenario} did not record enough rendered detail transition checks.`,
      scenario,
      expected: requirements.minDetailTransitionChecks || 0,
      observedCount: detailChecks,
    });
  }
  if (checkpointSweeps < (requirements.minCheckpointSweeps || 0)) {
    failures.push({
      code: "matrix_checkpoint_sweep_missing",
      message: `Scenario ${scenario} did not include the required checkpoint sweep.`,
      scenario,
      expected: requirements.minCheckpointSweeps || 0,
      observedCount: checkpointSweeps,
    });
  }
  if (checkpointSweepRowChecks < (requirements.minCheckpointSweepRowChecks || 0)) {
    failures.push({
      code: "matrix_checkpoint_sweep_row_checks_missing",
      message: `Scenario ${scenario} did not checkpoint enough rendered Dock rows.`,
      scenario,
      expected: requirements.minCheckpointSweepRowChecks || 0,
      observedCount: checkpointSweepRowChecks,
    });
  }
  if (dockVisibleOrderChecks < (requirements.minDockVisibleOrderChecks || 0)) {
    failures.push({
      code: "matrix_dock_visible_order_checks_missing",
      message: `Scenario ${scenario} did not prove enough visible Dock row ordering.`,
      scenario,
      expected: requirements.minDockVisibleOrderChecks || 0,
      observedCount: dockVisibleOrderChecks,
    });
  }
  if (dockSweepOrderChecks < (requirements.minDockSweepOrderChecks || 0)) {
    failures.push({
      code: "matrix_dock_sweep_order_checks_missing",
      message: `Scenario ${scenario} did not prove checkpoint Dock row ordering.`,
      scenario,
      expected: requirements.minDockSweepOrderChecks || 0,
      observedCount: dockSweepOrderChecks,
    });
  }
  if (detailSweeps < (requirements.minDetailSweeps || 0)) {
    failures.push({
      code: "matrix_detail_sweep_missing",
      message: `Scenario ${scenario} did not include the required opened-thread detail sweep.`,
      scenario,
      expected: requirements.minDetailSweeps || 0,
      observedCount: detailSweeps,
    });
  }
  if (detailSweepMessageCardChecks < (requirements.minDetailSweepMessageCardChecks || 0)) {
    failures.push({
      code: "matrix_detail_sweep_message_checks_missing",
      message: `Scenario ${scenario} did not sweep enough opened-thread detail rows.`,
      scenario,
      expected: requirements.minDetailSweepMessageCardChecks || 0,
      observedCount: detailSweepMessageCardChecks,
    });
  }
  if (detailMessageOrderChecks < (requirements.minDetailMessageOrderChecks || 0)) {
    failures.push({
      code: "matrix_detail_message_order_checks_missing",
      message: `Scenario ${scenario} did not prove opened-thread message ordering.`,
      scenario,
      expected: requirements.minDetailMessageOrderChecks || 0,
      observedCount: detailMessageOrderChecks,
    });
  }
  if (uiSummary.scenarioTransitionFailures || uiSummary.detailTransitionFailures) {
    failures.push({
      code: "matrix_transition_failures_present",
      message: `Scenario ${scenario} reported rendered transition failures.`,
      scenario,
      scenarioTransitionFailures: uiSummary.scenarioTransitionFailures || 0,
      detailTransitionFailures: uiSummary.detailTransitionFailures || 0,
    });
  }
  if (entry.uiReport?.summary?.uiLag?.ok === false || (maxLag !== null && maxLag > maxUiLagMs)) {
    failures.push({
      code: "matrix_ui_lag_exceeded",
      message: `Scenario ${scenario} exceeded the rendered UI lag budget.`,
      scenario,
      observedMs: maxLag,
      budgetMs: maxUiLagMs,
    });
  }

  return {
    scenario,
    dir: entry.dir || null,
    relayReportPath: entry.relayReportPath || null,
    uiReportPath: entry.uiReportPath || null,
    proofRunID: relayProofRunID,
    ok: failures.length === 0,
    routeCounts,
    uiSampleCount: Number(uiSummary.uiSampleCount || 0),
    scoredUISampleCount: Number(uiSummary.scoredUISampleCount || 0),
    checkpointSweepCount: checkpointSweeps,
    checkpointSweepRowChecks,
    dockVisibleOrderChecks,
    dockSweepOrderChecks,
    detailSweepCount: detailSweeps,
    detailSweepMessageCardChecks,
    detailMessageOrderChecks,
    scenarioTransitionChecks: scenarioChecks,
    detailTransitionChecks: detailChecks,
    maxObservedUiLagMs: maxLag,
    failures,
  };
}

function buildMatrixReport({ entries, requiredScenarios = DEFAULT_REQUIRED_SCENARIOS, minPasses = 1, maxUiLagMs = DEFAULT_MAX_UI_LAG_MS }) {
  const evaluated = entries.map((entry) => evaluateReportEntry(entry, { maxUiLagMs }));
  const findings = [];
  const byScenario = new Map();
  for (const result of evaluated) {
    if (!result.scenario) {
      findings.push(...result.failures.map((failure) => ({ ...failure, dir: result.dir })));
      continue;
    }
    if (!byScenario.has(result.scenario)) {
      byScenario.set(result.scenario, []);
    }
    byScenario.get(result.scenario).push(result);
    for (const failure of result.failures) {
      findings.push({ ...failure, scenario: result.scenario, dir: result.dir });
    }
  }

  const scenarioSummaries = requiredScenarios.map((scenario) => {
    const reports = byScenario.get(scenario) || [];
    const passingReports = reports.filter((report) => report.ok);
    const reportDirs = passingReports.map((report) => report.dir).filter(Boolean);
    const duplicateReportDirs = reportDirs.filter((dir, index) => reportDirs.indexOf(dir) !== index);
    const status = passingReports.length >= minPasses ? "pass" : reports.length ? "fail" : "missing";
    if (status === "missing") {
      findings.push({
        code: "matrix_required_scenario_missing",
        message: `Required controlled simulator scenario ${scenario} has no report.`,
        scenario,
      });
    } else if (status === "fail") {
      findings.push({
        code: "matrix_required_scenario_insufficient_passes",
        message: `Required controlled simulator scenario ${scenario} has ${passingReports.length} passing report(s), expected ${minPasses}.`,
        scenario,
        expected: minPasses,
        observedCount: passingReports.length,
      });
    }
    if (duplicateReportDirs.length) {
      findings.push({
        code: "matrix_duplicate_report_dir",
        message: `Required controlled simulator scenario ${scenario} repeats a report directory, so it cannot count as an independent matrix pass.`,
        scenario,
        dirs: [...new Set(duplicateReportDirs)].sort(),
      });
    }
    const lagValues = reports
      .map((report) => report.maxObservedUiLagMs)
      .filter((value) => Number.isFinite(value));
    return {
      scenario,
      status: duplicateReportDirs.length ? "fail" : status,
      reportCount: reports.length,
      passingReportCount: passingReports.length,
      maxObservedUiLagMs: lagValues.length ? Math.max(...lagValues) : null,
      reports,
    };
  });

  const unexpectedScenarios = [...byScenario.keys()]
    .filter((scenario) => !requiredScenarios.includes(scenario))
    .sort();
  for (const scenario of unexpectedScenarios) {
    findings.push({
      code: "matrix_unexpected_scenario",
      severity: "warning",
      message: `Controlled simulator matrix included unexpected scenario ${scenario}.`,
      scenario,
    });
  }

  const allLagValues = evaluated
    .map((report) => report.maxObservedUiLagMs)
    .filter((value) => Number.isFinite(value));
  const ok = findings.filter((finding) => finding.severity !== "warning").length === 0;
  return {
    schemaVersion: 1,
    kind: "codex-dock-controlled-simulator-matrix-report",
    generatedAt: new Date().toISOString(),
    config: {
      requiredScenarios,
      minPasses,
      maxUiLagMs,
    },
    summary: {
      ok,
      reportCount: entries.length,
      evaluatedReportCount: evaluated.length,
      requiredScenarioCount: requiredScenarios.length,
      passingScenarioCount: scenarioSummaries.filter((scenario) => scenario.status === "pass").length,
      missingScenarioCount: scenarioSummaries.filter((scenario) => scenario.status === "missing").length,
      failedScenarioCount: scenarioSummaries.filter((scenario) => scenario.status === "fail").length,
      unexpectedScenarioCount: unexpectedScenarios.length,
      maxObservedUiLagMs: allLagValues.length ? Math.max(...allLagValues) : null,
      findings: findings.length,
    },
    scenarios: scenarioSummaries,
    unexpectedScenarios,
    findings,
  };
}

function markdownSummary(report) {
  const lines = [];
  lines.push("# Codex Dock Controlled Simulator Matrix");
  lines.push("");
  lines.push(`Generated: \`${report.generatedAt}\``);
  lines.push("");
  lines.push("## Summary");
  lines.push("");
  lines.push(`- OK: ${report.summary.ok ? "true" : "false"}`);
  lines.push(`- Reports: ${report.summary.reportCount}`);
  lines.push(`- Required scenarios: ${report.summary.requiredScenarioCount}`);
  lines.push(`- Passing scenarios: ${report.summary.passingScenarioCount}`);
  lines.push(`- Missing scenarios: ${report.summary.missingScenarioCount}`);
  lines.push(`- Failed scenarios: ${report.summary.failedScenarioCount}`);
  lines.push(`- Max observed UI lag: ${report.summary.maxObservedUiLagMs ?? "not scored"} ms`);
  lines.push(`- UI lag budget: ${report.config.maxUiLagMs} ms`);
  lines.push("");
  lines.push("## Scenarios");
  lines.push("");
  for (const scenario of report.scenarios) {
    lines.push(`- \`${scenario.scenario}\`: ${scenario.status}, passes ${scenario.passingReportCount}/${report.config.minPasses}, reports ${scenario.reportCount}, max UI lag ${scenario.maxObservedUiLagMs ?? "not scored"} ms`);
  }
  lines.push("");
  lines.push("## Findings");
  lines.push("");
  if (!report.findings.length) {
    lines.push("- None.");
  } else {
    for (const finding of report.findings.slice(0, 80)) {
      lines.push(`- \`${finding.code}\`: ${finding.message}`);
    }
    if (report.findings.length > 80) {
      lines.push(`- ${report.findings.length - 80} more findings omitted from summary.`);
    }
  }
  lines.push("");
  return `${lines.join("\n")}\n`;
}

function writeReportFiles(report, options) {
  finalizeProofReport(report);
  assertProofReport(report);
  fs.mkdirSync(path.dirname(options.jsonOut), { recursive: true });
  fs.writeFileSync(options.jsonOut, `${JSON.stringify(report, null, 2)}\n`, "utf8");
  if (options.summaryOut) {
    fs.mkdirSync(path.dirname(options.summaryOut), { recursive: true });
    fs.writeFileSync(options.summaryOut, markdownSummary(report), "utf8");
  }
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    console.log(usage());
    return;
  }
  validateOptions(options);
  const entries = options.reportDirs.map(readReportDir);
  const report = buildMatrixReport({
    entries,
    requiredScenarios: options.requiredScenarios,
    minPasses: options.minPasses,
    maxUiLagMs: options.maxUiLagMs,
  });
  writeReportFiles(report, options);
  process.stdout.write(`${JSON.stringify({
    ok: report.summary.ok,
    summary: report.summary,
    reportPath: options.jsonOut,
    summaryPath: options.summaryOut || null,
    findings: report.findings.slice(0, 20),
  }, null, 2)}\n`);
  if (options.failOnDiff && !report.summary.ok) {
    process.exitCode = 1;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.error(`controlled-simulator-matrix failed: ${error.message || error}`);
    process.exit(1);
  });
}

export {
  buildMatrixReport,
  evaluateReportEntry,
  markdownSummary,
  parseArgs,
  readReportDir,
  validateOptions,
};

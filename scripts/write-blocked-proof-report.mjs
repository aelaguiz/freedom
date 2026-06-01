#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import process from "node:process";

import {
  assertProofReport,
  finalizeProofReport,
} from "./proof-report-contracts.mjs";

function usage() {
  return [
    "Usage:",
    "  node scripts/write-blocked-proof-report.mjs --kind <relay-sync-audit|controlled-scenario|sim-ui-sync> --json-out <path> --reason <text> [options]",
    "",
    "Options:",
    "  --summary-out <path>    Write Markdown summary.",
    "  --scenario <id>         Scenario id for controlled-scenario reports.",
    "  --relay-url <url>       Relay URL, defaults to ws://127.0.0.1:4510.",
    "  --proof-run-id <id>     Proof run id.",
    "  --relay-report <path>   Embed relay metadata in sim-ui-sync reports.",
  ].join("\n");
}

function parseArgs(argv) {
  const options = {
    kind: null,
    jsonOut: null,
    summaryOut: null,
    reason: null,
    scenario: "unknown",
    relayUrl: "ws://127.0.0.1:4510",
    proofRunID: "blocked-proof",
    relayReport: null,
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
    if (arg === "--kind") {
      options.kind = next();
    } else if (arg === "--json-out") {
      options.jsonOut = next();
    } else if (arg === "--summary-out") {
      options.summaryOut = next();
    } else if (arg === "--reason") {
      options.reason = next();
    } else if (arg === "--scenario") {
      options.scenario = next();
    } else if (arg === "--relay-url") {
      options.relayUrl = next();
    } else if (arg === "--proof-run-id") {
      options.proofRunID = next();
    } else if (arg === "--relay-report") {
      options.relayReport = next();
    } else if (arg === "--help" || arg === "-h") {
      options.help = true;
    } else {
      throw new Error(`unknown argument ${arg}`);
    }
  }
  return options;
}

function validateOptions(options) {
  if (options.help) {
    return;
  }
  if (!["relay-sync-audit", "controlled-scenario", "sim-ui-sync"].includes(options.kind)) {
    throw new Error("--kind must be relay-sync-audit, controlled-scenario, or sim-ui-sync");
  }
  if (!options.jsonOut) {
    throw new Error("--json-out is required");
  }
  if (!options.reason) {
    throw new Error("--reason is required");
  }
}

function clientPathEvidenceFromReport(report) {
  const routes = report?.clientPathEvidence?.routes || [];
  const routeCounts = report?.clientPathEvidence?.routeCounts || report?.summary?.clientPathRouteCounts || {};
  return { routes, routeCounts };
}

function readRelayReport(options) {
  if (!options.relayReport || !fs.existsSync(options.relayReport)) {
    return null;
  }
  try {
    return JSON.parse(fs.readFileSync(options.relayReport, "utf8"));
  } catch {
    return null;
  }
}

function relaySyncAuditReport(options) {
  const now = new Date().toISOString();
  return {
    schemaVersion: 1,
    kind: "codex-dock-relay-sync-audit-report",
    status: "blocked",
    mode: "proof-target",
    relayUrl: options.relayUrl,
    startedAt: now,
    endedAt: now,
    summary: {
      ok: false,
      clientPathOK: false,
    },
    clientPathEvidence: { routes: [], routeCounts: {} },
    failures: [{
      code: "proof_blocked",
      message: options.reason,
    }],
  };
}

function controlledScenarioReport(options) {
  const now = new Date().toISOString();
  return {
    schemaVersion: 1,
    kind: "codex-dock-controlled-simulator-scenario-relay-report",
    status: "blocked",
    proofRunID: options.proofRunID,
    mode: "scenario",
    scenario: options.scenario,
    startedAt: now,
    endedAt: now,
    relayUrl: options.relayUrl,
    summary: {
      ok: false,
      clientPathOK: false,
      scenario: options.scenario,
      scenarioOK: false,
      clientPathRouteCounts: {},
    },
    samples: [],
    scenarios: [{
      id: options.scenario,
      ok: false,
      blocked: true,
      reason: options.reason,
    }],
    clientPathEvidence: { routes: [], routeCounts: {} },
    findings: [{
      severity: "error",
      code: "proof_blocked",
      message: options.reason,
    }],
  };
}

function simUISyncReport(options) {
  const now = new Date().toISOString();
  const relayReport = readRelayReport(options);
  const relayEvidence = clientPathEvidenceFromReport(relayReport);
  const proofRunID = relayReport?.proofRunID || options.proofRunID;
  const relayUrl = relayReport?.relayUrl || options.relayUrl;
  return {
    schemaVersion: 1,
    kind: "codex-dock-simulator-ui-sync-proof",
    status: "blocked",
    proofRunID,
    startedAt: now,
    endedAt: now,
    relayReport: {
      proofRunID,
      relayUrl,
      clientPathOK: relayReport?.summary?.clientPathOK ?? relayReport?.summary?.ok ?? false,
      clientPathRoutes: relayEvidence.routes,
      clientPathEvidence: relayReport?.clientPathEvidence || relayEvidence,
    },
    summary: {
      ok: false,
      uiSampleCount: 0,
      relaySampleCount: 0,
      failures: 1,
    },
    evaluations: [],
    failures: [{
      code: "proof_blocked",
      message: options.reason,
    }],
  };
}

function markdown(report, reason) {
  return [
    "# Codex Dock Blocked Proof Report",
    "",
    `- kind: ${report.kind}`,
    `- status: ${report.status}`,
    `- reason: ${reason}`,
    "",
  ].join("\n");
}

function writeReport(report, options) {
  finalizeProofReport(report);
  assertProofReport(report);
  fs.mkdirSync(path.dirname(options.jsonOut), { recursive: true });
  fs.writeFileSync(options.jsonOut, `${JSON.stringify(report, null, 2)}\n`, "utf8");
  if (options.summaryOut) {
    fs.mkdirSync(path.dirname(options.summaryOut), { recursive: true });
    fs.writeFileSync(options.summaryOut, markdown(report, options.reason), "utf8");
  }
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    console.log(usage());
    return;
  }
  validateOptions(options);
  let report;
  if (options.kind === "relay-sync-audit") {
    report = relaySyncAuditReport(options);
  } else if (options.kind === "controlled-scenario") {
    report = controlledScenarioReport(options);
  } else {
    report = simUISyncReport(options);
  }
  writeReport(report, options);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main();
}

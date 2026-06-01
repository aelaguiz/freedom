import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import { assertProofReport } from "./proof-report-contracts.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const SCRIPT = path.join(__dirname, "write-blocked-proof-report.mjs");

function runBlockedReport(args) {
  execFileSync(process.execPath, [SCRIPT, ...args], {
    cwd: path.resolve(__dirname, ".."),
    stdio: "pipe",
  });
}

test("writes schema-valid blocked relay sync audit reports", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "codex-dock-blocked-proof-"));
  const jsonPath = path.join(dir, "relay-client-path.json");
  const mdPath = path.join(dir, "relay-client-path.md");

  runBlockedReport([
    "--kind", "relay-sync-audit",
    "--json-out", jsonPath,
    "--summary-out", mdPath,
    "--reason", "build failed before relay proof could run",
    "--relay-url", "ws://127.0.0.1:4510",
  ]);

  const report = JSON.parse(fs.readFileSync(jsonPath, "utf8"));
  assert.equal(report.kind, "codex-dock-relay-sync-audit-report");
  assert.equal(report.status, "blocked");
  assertProofReport(report, { sourcePath: jsonPath });
  assert.match(fs.readFileSync(mdPath, "utf8"), /status: blocked/u);
});

test("writes schema-valid blocked simulator UI proof reports using relay metadata", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "codex-dock-blocked-proof-"));
  const relayPath = path.join(dir, "relay-client-path.json");
  const jsonPath = path.join(dir, "simulator-ui-sync.json");

  runBlockedReport([
    "--kind", "controlled-scenario",
    "--json-out", relayPath,
    "--reason", "fixture stopped before UI proof",
    "--scenario", "detail-reconnect",
    "--proof-run-id", "blocked-detail-reconnect",
  ]);
  runBlockedReport([
    "--kind", "sim-ui-sync",
    "--json-out", jsonPath,
    "--reason", "UI sampler failed before proof report",
    "--relay-report", relayPath,
  ]);

  const report = JSON.parse(fs.readFileSync(jsonPath, "utf8"));
  assert.equal(report.kind, "codex-dock-simulator-ui-sync-proof");
  assert.equal(report.status, "blocked");
  assert.equal(report.proofRunID, "blocked-detail-reconnect");
  assert.equal(report.relayReport.proofRunID, "blocked-detail-reconnect");
  assertProofReport(report, { sourcePath: jsonPath });
});

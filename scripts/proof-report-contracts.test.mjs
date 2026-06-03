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

test("passing proof cannot use thread/detail/read as production route evidence", () => {
  const report = sampleProofReports().find(
    (candidate) => candidate.kind === "codex-dock-relay-sync-audit-report"
  );
  report.clientPathEvidence = {
    routes: ["thread/detail/read"],
    routeCounts: { "thread/detail/read": 1 },
  };
  report.summary.clientPathRouteCounts = { "thread/detail/read": 1 };

  const errors = validateProofReport(report, { sourcePath: "relay-sync-audit-sample" });

  assert.match(errors.join("\n"), /manual diagnostic routes cannot satisfy live-update proof/u);
  assert.match(errors.join("\n"), /must include relay-owned Dock, Archive, or Thread Detail client routes/u);
});

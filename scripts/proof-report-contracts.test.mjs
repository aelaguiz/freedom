import assert from "node:assert/strict";
import test from "node:test";
import {
  assertProofReport,
  sampleProofReports,
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

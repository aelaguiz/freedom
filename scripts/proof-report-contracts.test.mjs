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

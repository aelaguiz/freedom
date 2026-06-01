import assert from "node:assert/strict";
import test from "node:test";

import {
  buildMarkdownSummary,
  parseArgs,
  validateOptions,
} from "./dock-relay-controlled-simulator-fixture.mjs";

test("controlled simulator fixture parses thread-activity options", () => {
  const options = parseArgs([
    "--scenario",
    "thread-activity",
    "--ready-out",
    "/tmp/ready.json",
    "--ui-ready-in",
    "/tmp/ui-ready.json",
    "--stop-in",
    "/tmp/stop",
    "--json-out",
    "/tmp/report.json",
    "--summary-out",
    "/tmp/report.md",
    "--scenario-hold-ms",
    "2500",
    "--max-stream-lag-ms",
    "1500",
  ]);

  validateOptions(options);

  assert.equal(options.scenario, "thread-activity");
  assert.equal(options.readyOut, "/tmp/ready.json");
  assert.equal(options.uiReadyIn, "/tmp/ui-ready.json");
  assert.equal(options.stopIn, "/tmp/stop");
  assert.equal(options.jsonOut, "/tmp/report.json");
  assert.equal(options.summaryOut, "/tmp/report.md");
  assert.equal(options.scenarioHoldMs, 2500);
  assert.equal(options.maxStreamLagMs, 1500);
});

test("controlled simulator fixture parses archive-toggle options", () => {
  const options = parseArgs([
    "--scenario",
    "archive-toggle",
    "--ready-out",
    "/tmp/ready.json",
    "--ui-ready-in",
    "/tmp/ui-ready.json",
    "--stop-in",
    "/tmp/stop",
    "--json-out",
    "/tmp/report.json",
  ]);

  validateOptions(options);

  assert.equal(options.scenario, "archive-toggle");
  assert.equal(options.readyOut, "/tmp/ready.json");
  assert.equal(options.uiReadyIn, "/tmp/ui-ready.json");
  assert.equal(options.stopIn, "/tmp/stop");
  assert.equal(options.jsonOut, "/tmp/report.json");
});

test("controlled simulator fixture parses server-request options", () => {
  const options = parseArgs([
    "--scenario",
    "server-request",
    "--ready-out",
    "/tmp/ready.json",
    "--ui-ready-in",
    "/tmp/ui-ready.json",
    "--stop-in",
    "/tmp/stop",
    "--json-out",
    "/tmp/report.json",
  ]);

  validateOptions(options);

  assert.equal(options.scenario, "server-request");
  assert.equal(options.readyOut, "/tmp/ready.json");
  assert.equal(options.uiReadyIn, "/tmp/ui-ready.json");
  assert.equal(options.stopIn, "/tmp/stop");
  assert.equal(options.jsonOut, "/tmp/report.json");
});

test("controlled simulator fixture parses detail-history-request options", () => {
  const options = parseArgs([
    "--scenario",
    "detail-history-request",
    "--ready-out",
    "/tmp/ready.json",
    "--ui-ready-in",
    "/tmp/ui-ready.json",
    "--stop-in",
    "/tmp/stop",
    "--json-out",
    "/tmp/report.json",
  ]);

  validateOptions(options);

  assert.equal(options.scenario, "detail-history-request");
  assert.equal(options.readyOut, "/tmp/ready.json");
  assert.equal(options.uiReadyIn, "/tmp/ui-ready.json");
  assert.equal(options.stopIn, "/tmp/stop");
  assert.equal(options.jsonOut, "/tmp/report.json");
});

test("controlled simulator fixture parses detail-reconnect options", () => {
  const options = parseArgs([
    "--scenario",
    "detail-reconnect",
    "--ready-out",
    "/tmp/ready.json",
    "--ui-ready-in",
    "/tmp/ui-ready.json",
    "--stop-in",
    "/tmp/stop",
    "--json-out",
    "/tmp/report.json",
  ]);

  validateOptions(options);

  assert.equal(options.scenario, "detail-reconnect");
  assert.equal(options.readyOut, "/tmp/ready.json");
  assert.equal(options.uiReadyIn, "/tmp/ui-ready.json");
  assert.equal(options.stopIn, "/tmp/stop");
  assert.equal(options.jsonOut, "/tmp/report.json");
});

test("controlled simulator fixture parses large-list-checkpoint options", () => {
  const options = parseArgs([
    "--scenario",
    "large-list-checkpoint",
    "--ready-out",
    "/tmp/ready.json",
    "--ui-ready-in",
    "/tmp/ui-ready.json",
    "--stop-in",
    "/tmp/stop",
    "--json-out",
    "/tmp/report.json",
  ]);

  validateOptions(options);

  assert.equal(options.scenario, "large-list-checkpoint");
});

test("controlled simulator fixture parses resync-gap options", () => {
  const options = parseArgs([
    "--scenario",
    "resync-gap",
    "--ready-out",
    "/tmp/ready.json",
    "--ui-ready-in",
    "/tmp/ui-ready.json",
    "--stop-in",
    "/tmp/stop",
    "--json-out",
    "/tmp/report.json",
  ]);

  validateOptions(options);

  assert.equal(options.scenario, "resync-gap");
  assert.equal(options.readyOut, "/tmp/ready.json");
  assert.equal(options.uiReadyIn, "/tmp/ui-ready.json");
  assert.equal(options.stopIn, "/tmp/stop");
  assert.equal(options.jsonOut, "/tmp/report.json");
});

test("controlled simulator fixture parses rapid-mutations options", () => {
  const options = parseArgs([
    "--scenario",
    "rapid-mutations",
    "--ready-out",
    "/tmp/ready.json",
    "--ui-ready-in",
    "/tmp/ui-ready.json",
    "--stop-in",
    "/tmp/stop",
    "--json-out",
    "/tmp/report.json",
  ]);

  validateOptions(options);

  assert.equal(options.scenario, "rapid-mutations");
  assert.equal(options.readyOut, "/tmp/ready.json");
  assert.equal(options.uiReadyIn, "/tmp/ui-ready.json");
  assert.equal(options.stopIn, "/tmp/stop");
  assert.equal(options.jsonOut, "/tmp/report.json");
});

test("controlled simulator fixture parses source-refresh options", () => {
  const options = parseArgs([
    "--scenario",
    "source-refresh",
    "--ready-out",
    "/tmp/ready.json",
    "--ui-ready-in",
    "/tmp/ui-ready.json",
    "--stop-in",
    "/tmp/stop",
    "--json-out",
    "/tmp/report.json",
  ]);

  validateOptions(options);

  assert.equal(options.scenario, "source-refresh");
  assert.equal(options.readyOut, "/tmp/ready.json");
  assert.equal(options.uiReadyIn, "/tmp/ui-ready.json");
  assert.equal(options.stopIn, "/tmp/stop");
  assert.equal(options.jsonOut, "/tmp/report.json");
});

test("controlled simulator fixture parses spawn-edge options", () => {
  const options = parseArgs([
    "--scenario",
    "spawn-edge",
    "--ready-out",
    "/tmp/ready.json",
    "--ui-ready-in",
    "/tmp/ui-ready.json",
    "--stop-in",
    "/tmp/stop",
    "--json-out",
    "/tmp/report.json",
  ]);

  validateOptions(options);

  assert.equal(options.scenario, "spawn-edge");
  assert.equal(options.readyOut, "/tmp/ready.json");
  assert.equal(options.uiReadyIn, "/tmp/ui-ready.json");
  assert.equal(options.stopIn, "/tmp/stop");
  assert.equal(options.jsonOut, "/tmp/report.json");
});

test("controlled simulator fixture parses live-lease-expiry options", () => {
  const options = parseArgs([
    "--scenario",
    "live-lease-expiry",
    "--ready-out",
    "/tmp/ready.json",
    "--ui-ready-in",
    "/tmp/ui-ready.json",
    "--stop-in",
    "/tmp/stop",
    "--json-out",
    "/tmp/report.json",
  ]);

  validateOptions(options);

  assert.equal(options.scenario, "live-lease-expiry");
  assert.equal(options.readyOut, "/tmp/ready.json");
  assert.equal(options.uiReadyIn, "/tmp/ui-ready.json");
  assert.equal(options.stopIn, "/tmp/stop");
  assert.equal(options.jsonOut, "/tmp/report.json");
});

test("controlled simulator fixture parses multi-host-isolation options", () => {
  const options = parseArgs([
    "--scenario",
    "multi-host-isolation",
    "--ready-out",
    "/tmp/ready.json",
    "--ui-ready-in",
    "/tmp/ui-ready.json",
    "--stop-in",
    "/tmp/stop",
    "--json-out",
    "/tmp/report.json",
  ]);

  validateOptions(options);

  assert.equal(options.scenario, "multi-host-isolation");
  assert.equal(options.readyOut, "/tmp/ready.json");
  assert.equal(options.uiReadyIn, "/tmp/ui-ready.json");
  assert.equal(options.stopIn, "/tmp/stop");
  assert.equal(options.jsonOut, "/tmp/report.json");
});

test("controlled simulator fixture rejects unsupported simulator scenarios", () => {
  const options = parseArgs([
    "--scenario",
    "unsupported-scenario",
    "--ready-out",
    "/tmp/ready.json",
    "--ui-ready-in",
    "/tmp/ui-ready.json",
    "--stop-in",
    "/tmp/stop",
    "--json-out",
    "/tmp/report.json",
  ]);

  assert.throws(
    () => validateOptions(options),
    /unsupported controlled simulator scenario unsupported-scenario/u
  );
});

test("controlled simulator fixture summary says the simulator must share the temporary relay", () => {
  const summary = buildMarkdownSummary({
    startedAt: "2026-05-31T00:00:00.000Z",
    endedAt: "2026-05-31T00:00:10.000Z",
    relayUrl: "ws://127.0.0.1:4999",
    summary: {
      ok: true,
      scenario: "thread-activity",
      scenarioOK: true,
      clientPathOK: true,
      scenarioTransitionCount: 2,
      failures: 0,
    },
    clientPathEvidence: {
      routeCounts: {
        "dock/subscribe": 2,
        "dock/update": 2,
      },
    },
    findings: [],
  });

  assert.match(summary, /same temporary relay/u);
  assert.match(summary, /Scenario: thread-activity/u);
});

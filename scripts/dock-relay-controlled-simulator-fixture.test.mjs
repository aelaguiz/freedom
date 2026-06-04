import assert from "node:assert/strict";
import test from "node:test";
import WebSocket, { WebSocketServer } from "ws";

import {
  buildMarkdownSummary,
  forbiddenSimulatorDetailRouteFindings,
  parseArgs,
  startSimulatorAppRouteProxy,
  validateOptions,
  waitForRecordedRouteEvent,
} from "./dock-relay-controlled-simulator-fixture.mjs";
import {
  summarizeClientPathEvents,
} from "./dock-relay-sync-audit.mjs";

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

test("controlled simulator fixture parses file-change-review options", () => {
  const options = parseArgs([
    "--scenario",
    "file-change-review",
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

  assert.equal(options.scenario, "file-change-review");
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

test("controlled simulator fixture parses server-rename-notification options", () => {
  const options = parseArgs([
    "--scenario",
    "server-rename-notification",
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

  assert.equal(options.scenario, "server-rename-notification");
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

test("controlled simulator proxy records simulator-app downstream detail routes", async () => {
  const routeEvents = [];
  const upstreamServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await new Promise((resolve) => upstreamServer.once("listening", resolve));
  upstreamServer.on("connection", (ws) => {
    ws.on("message", (data) => {
      const request = JSON.parse(data.toString());
      ws.send(JSON.stringify({ jsonrpc: "2.0", id: request.id, result: { ok: true } }));
      ws.send(JSON.stringify({
        jsonrpc: "2.0",
        method: "thread/detail/update",
        params: { kind: "heartbeat", seq: 1 },
      }));
    });
  });
  const proxy = await startSimulatorAppRouteProxy({
    targetUrl: `ws://127.0.0.1:${upstreamServer.address().port}`,
    routeEvents,
    label: "unit-test",
  });
  const client = new WebSocket(proxy.url);
  try {
    await new Promise((resolve) => client.once("open", resolve));
    client.send(JSON.stringify({
      jsonrpc: "2.0",
      id: 1,
      method: "thread/detail/subscribe",
      params: { threadId: "thread-1" },
    }));
    await new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error("proxy did not observe detail update")), 1_000);
      const poll = () => {
        if (routeEvents.some((event) => event.route === "thread/detail/update")) {
          clearTimeout(timer);
          resolve();
        } else {
          setTimeout(poll, 10);
        }
      };
      poll();
    });
  } finally {
    try {
      client.terminate();
    } catch {
      // Test cleanup should not mask assertion results.
    }
    await proxy.close();
    await new Promise((resolve) => upstreamServer.close(resolve));
  }

  const evidence = summarizeClientPathEvents(routeEvents);
  assert.equal(evidence.routeCounts["thread/detail/subscribe"], 1);
  assert.equal(evidence.routeCounts["thread/detail/update"], 1);
  assert.ok(routeEvents.some((event) => (
    event.route === "thread/detail/subscribe"
    && event.source === "simulatorAppProxy"
    && event.boundary === "simulatorAppToRelay"
  )));
  assert.ok(routeEvents.some((event) => (
    event.route === "thread/detail/update"
    && event.source === "simulatorAppProxy"
    && event.boundary === "relayToSimulatorApp"
  )));
});

test("controlled simulator forbidden detail side doors only fail at simulator-app downstream boundary", () => {
  const findings = forbiddenSimulatorDetailRouteFindings({
    events: [
      {
        route: "thread/read",
        source: "simulatorAppProxy",
        boundary: "simulatorAppToRelay",
        at: "2026-06-03T00:00:00.000Z",
      },
      {
        route: "thread/resume",
        source: "fixtureUpstream",
        boundary: "relayToFixtureUpstream",
      },
      {
        route: "thread/detail/read",
        source: "simulatorAppProxy",
        boundary: "relayToSimulatorApp",
      },
      {
        route: "thread/detail/subscribe",
        source: "simulatorAppProxy",
        boundary: "simulatorAppToRelay",
      },
    ],
  });

  assert.equal(findings.length, 1);
  assert.equal(findings[0].code, "controlled_simulator_forbidden_detail_side_door_route");
  assert.equal(findings[0].route, "thread/read");
});

test("controlled simulator route waiter requires the simulator-app downstream boundary", async () => {
  const events = [
    {
      route: "thread/detail/resync",
      source: "fixtureUpstream",
      boundary: "relayToFixtureUpstream",
      at: "2026-06-03T00:00:00.000Z",
    },
    {
      route: "thread/detail/resync",
      source: "simulatorAppProxy",
      boundary: "simulatorAppToRelay",
      at: "2026-06-03T00:00:01.000Z",
    },
  ];

  const wait = await waitForRecordedRouteEvent({
    events,
    route: "thread/detail/resync",
    source: "simulatorAppProxy",
    boundary: "simulatorAppToRelay",
    afterMs: Date.parse("2026-06-03T00:00:00.500Z"),
    timeoutMs: 50,
  });

  assert.equal(wait.ok, true);
  assert.equal(wait.observedAt, "2026-06-03T00:00:01.000Z");
  assert.equal(wait.event.source, "simulatorAppProxy");
  assert.equal(wait.event.boundary, "simulatorAppToRelay");
});

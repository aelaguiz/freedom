#!/usr/bin/env node
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";
import { WebSocketServer } from "ws";

import { startServer } from "./dock-relay.mjs";
import { threadMatchesSourceKinds } from "./dock-relay-source-filter.mjs";
import {
  DockStreamProbe,
  cardID,
  collectDockClientPathSnapshot,
  compareDockStates,
  normalizeForComparison,
  sanitizeDockSnapshotForReport,
  scenarioLagSummary,
  summarizeClientPathEvents,
} from "./dock-relay-sync-audit.mjs";

const SUPPORTED_SCENARIOS = new Set([
  "detail-history-request",
  "large-list-checkpoint",
  "live-lease-expiry",
  "multi-host-isolation",
  "rapid-mutations",
  "resync-gap",
  "server-request",
  "source-refresh",
  "spawn-edge",
  "thread-activity",
]);
const DEFAULT_DOCK_COLLECTION_TIMEOUT_MS = 120_000;
const DEFAULT_MAX_STREAM_LAG_MS = 2_000;
const DEFAULT_REQUEST_TIMEOUT_MS = 120_000;
const DEFAULT_SCENARIO_HOLD_MS = 3_500;
const DEFAULT_WAIT_TIMEOUT_MS = 120_000;
const DEFAULT_STREAM_COMPARE_ATTEMPTS = 5;
const DEFAULT_STREAM_COMPARE_DELAY_MS = 1_000;

function usage() {
  return [
    "Usage:",
    "  node scripts/dock-relay-controlled-simulator-fixture.mjs --scenario <detail-history-request|large-list-checkpoint|live-lease-expiry|multi-host-isolation|rapid-mutations|resync-gap|server-request|source-refresh|spawn-edge|thread-activity> --ready-out <path> --ui-ready-in <path> --stop-in <path> --json-out <path> [options]",
    "",
    "Options:",
    "  --summary-out <path>                 Write Markdown summary.",
    "  --scenario-hold-ms <ms>              Hold between visible mutations. Default: 3500.",
    "  --dock-collection-timeout-ms <ms>    Wait budget for Dock stream state. Default: 120000.",
    "  --max-stream-lag-ms <ms>             Relay transition lag budget. Default: 2000.",
    "  --request-timeout-ms <ms>            JSON-RPC request timeout. Default: 120000.",
    "  --wait-timeout-ms <ms>               File wait timeout. Default: 120000.",
    "  --help                              Show this help.",
  ].join("\n");
}

function parseArgs(argv) {
  const options = {
    scenario: "thread-activity",
    readyOut: null,
    uiReadyIn: null,
    stopIn: null,
    jsonOut: null,
    summaryOut: null,
    scenarioHoldMs: DEFAULT_SCENARIO_HOLD_MS,
    dockCollectionTimeoutMs: DEFAULT_DOCK_COLLECTION_TIMEOUT_MS,
    maxStreamLagMs: DEFAULT_MAX_STREAM_LAG_MS,
    requestTimeoutMs: DEFAULT_REQUEST_TIMEOUT_MS,
    waitTimeoutMs: DEFAULT_WAIT_TIMEOUT_MS,
    streamCompareAttempts: DEFAULT_STREAM_COMPARE_ATTEMPTS,
    streamCompareDelayMs: DEFAULT_STREAM_COMPARE_DELAY_MS,
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
    if (arg === "--scenario") {
      options.scenario = next();
    } else if (arg === "--ready-out") {
      options.readyOut = next();
    } else if (arg === "--ui-ready-in") {
      options.uiReadyIn = next();
    } else if (arg === "--stop-in") {
      options.stopIn = next();
    } else if (arg === "--json-out") {
      options.jsonOut = next();
    } else if (arg === "--summary-out") {
      options.summaryOut = next();
    } else if (arg === "--scenario-hold-ms") {
      options.scenarioHoldMs = Number(next());
    } else if (arg === "--dock-collection-timeout-ms") {
      options.dockCollectionTimeoutMs = Number(next());
    } else if (arg === "--max-stream-lag-ms") {
      options.maxStreamLagMs = Number(next());
    } else if (arg === "--request-timeout-ms") {
      options.requestTimeoutMs = Number(next());
    } else if (arg === "--wait-timeout-ms") {
      options.waitTimeoutMs = Number(next());
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
  if (!SUPPORTED_SCENARIOS.has(options.scenario)) {
    throw new Error(`unsupported controlled simulator scenario ${options.scenario}`);
  }
  for (const field of ["readyOut", "uiReadyIn", "stopIn", "jsonOut"]) {
    if (!options[field]) {
      throw new Error(`--${field.replace(/[A-Z]/g, (match) => `-${match.toLowerCase()}`)} is required`);
    }
  }
  for (const field of [
    "scenarioHoldMs",
    "dockCollectionTimeoutMs",
    "maxStreamLagMs",
    "requestTimeoutMs",
    "waitTimeoutMs",
  ]) {
    if (!Number.isFinite(Number(options[field])) || Number(options[field]) < 0) {
      throw new Error(`${field} must be a non-negative number`);
    }
  }
}

function writeJSON(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

function writeText(filePath, body) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, body, "utf8");
}

function sleep(ms) {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

async function waitForFile(filePath, timeoutMs, label) {
  const deadline = Date.now() + timeoutMs;
  while (!fs.existsSync(filePath)) {
    if (Date.now() >= deadline) {
      throw new Error(`timed out waiting for ${label}: ${filePath}`);
    }
    await sleep(100);
  }
}

function sendFixtureResult(ws, id, result) {
  ws.send(JSON.stringify({
    jsonrpc: "2.0",
    id,
    result,
  }));
}

function sendFixtureError(ws, id, message) {
  ws.send(JSON.stringify({
    jsonrpc: "2.0",
    id,
    error: {
      code: -32000,
      message,
    },
  }));
}

function fixtureThread(id, preview, updatedAt) {
  return {
    id,
    preview,
    updatedAt,
    source: "cli",
    status: { type: "notLoaded" },
  };
}

function fixtureThreadWithStatus(id, preview, updatedAt, status) {
  return {
    ...fixtureThread(id, preview, updatedAt),
    status,
  };
}

function fixtureTurn(id, startedAt, items) {
  return {
    id,
    startedAt,
    items,
  };
}

function fixtureUserMessageItem(id, text) {
  return {
    id,
    type: "userMessage",
    content: [{ type: "text", text }],
  };
}

function fixtureAgentMessageItem(id, text) {
  return {
    id,
    type: "agentMessage",
    text,
  };
}

function fixtureCommandExecutionItem(id, command, aggregatedOutput) {
  return {
    id,
    type: "commandExecution",
    command,
    aggregatedOutput,
  };
}

function fixturePlanItem(id, text) {
  return {
    id,
    type: "plan",
    text,
  };
}

function fixtureReasoningItem(id, text) {
  return {
    id,
    type: "reasoning",
    summary: [{ text }],
  };
}

function cardThreadID(card) {
  return card?.threadID || card?.threadId || null;
}

function dockRenderOrderIDs(snapshot) {
  return (Array.isArray(snapshot?.cards) ? snapshot.cards : [])
    .slice()
    .sort((left, right) => {
      const leftOrder = typeof left?.orderKey === "string" ? left.orderKey : "";
      const rightOrder = typeof right?.orderKey === "string" ? right.orderKey : "";
      if (leftOrder !== rightOrder) {
        return leftOrder.localeCompare(rightOrder);
      }
      return cardID(left).localeCompare(cardID(right));
    })
    .map(cardID);
}

function dockSnapshotCardForThread(snapshot, threadID) {
  return (Array.isArray(snapshot?.cards) ? snapshot.cards : [])
    .find((card) => cardThreadID(card) === threadID) || null;
}

function dockSnapshotHasThread(snapshot, threadID) {
  return Boolean(dockSnapshotCardForThread(snapshot, threadID));
}

function dockSnapshotThreadIndex(snapshot, threadID) {
  const card = dockSnapshotCardForThread(snapshot, threadID);
  if (!card) {
    return -1;
  }
  return dockRenderOrderIDs(snapshot).indexOf(cardID(card));
}

function observedSnapshotTime(snapshot) {
  const parsed = Date.parse(snapshot?.lastReceivedAt || 0);
  return Number.isFinite(parsed) ? parsed : Date.now();
}

async function waitForStreamCondition({ streamProbe, timeoutMs, predicate }) {
  const deadlineMs = Date.now() + timeoutMs;
  while (true) {
    const snapshot = streamProbe.snapshot();
    const observedAtMs = observedSnapshotTime(snapshot);
    if (predicate(snapshot)) {
      return {
        ok: true,
        observedAt: new Date(observedAtMs).toISOString(),
        observedAtMs,
        snapshot: sanitizeDockSnapshotForReport(snapshot),
      };
    }
    if (streamProbe.state.needsResync) {
      await streamProbe.resync("controlled_simulator_fixture_condition");
      continue;
    }
    const remainingMs = deadlineMs - Date.now();
    if (remainingMs <= 0) {
      return {
        ok: false,
        observedAt: null,
        observedAtMs: null,
        timeoutMs,
        snapshot: sanitizeDockSnapshotForReport(snapshot),
      };
    }
    await streamProbe.waitForUpdate(Math.min(remainingMs, 500));
  }
}

function scenarioComparisonFindings({ phase, comparison }) {
  return (comparison?.findings || []).map((finding) => ({
    ...finding,
    code: `scenario_${phase}_${finding.code || "dock_stream_mismatch"}`,
    message: `controlled simulator scenario ${phase}: ${finding.message || "long-lived Dock stream differs from fresh Dock snapshot"}`,
  }));
}

async function freshComparison({ streamProbe, options, routeEvents }) {
  let freshDock = await collectDockClientPathSnapshot(options, routeEvents);
  let comparison = compareDockStates(streamProbe.snapshot(), freshDock);
  const attempts = [{
    attempt: 0,
    checkedAt: new Date().toISOString(),
    ok: comparison.ok,
    findingCount: comparison.findings.length,
  }];
  for (let attempt = 1; !comparison.ok && attempt <= options.streamCompareAttempts; attempt += 1) {
    await sleep(options.streamCompareDelayMs);
    freshDock = await collectDockClientPathSnapshot(options, routeEvents);
    comparison = compareDockStates(streamProbe.snapshot(), freshDock);
    attempts.push({
      attempt,
      checkedAt: new Date().toISOString(),
      ok: comparison.ok,
      findingCount: comparison.findings.length,
    });
  }
  return { freshDock, comparison, attempts };
}

function transitionFailure(findings, code, message, detail = {}) {
  findings.push({
    code,
    severity: "error",
    message,
    ...detail,
  });
}

function waitForAsyncEvent(promise, timeoutMs) {
  const timeout = Symbol("timeout");
  return Promise.race([
    promise,
    sleep(timeoutMs).then(() => timeout),
  ]).then((value) => {
    if (value === timeout) {
      return {
        ok: false,
        timeoutMs,
        value: null,
      };
    }
    return {
      ok: true,
      timeoutMs,
      value,
    };
  });
}

function recordClientRoute(events, route, purpose, details = {}) {
  if (!Array.isArray(events)) {
    return;
  }
  events.push({
    route,
    purpose,
    countedAsClientPath: true,
    at: new Date().toISOString(),
    ...normalizeForComparison(details),
  });
}

function requiredRouteFindings(clientPathEvidence, routes) {
  const findings = [];
  for (const route of routes) {
    if (!clientPathEvidence.routeCounts?.[route]) {
      transitionFailure(
        findings,
        "controlled_simulator_required_client_route_missing",
        `controlled simulator scenario did not exercise required client route ${route}`,
        { route }
      );
    }
  }
  return findings;
}

function buildMarkdownSummary(report) {
  const lines = [];
  lines.push("# Codex Dock Controlled Simulator Scenario Relay Report");
  lines.push("");
  lines.push(`Started: \`${report.startedAt || "unknown"}\``);
  lines.push(`Ended: \`${report.endedAt || "unknown"}\``);
  lines.push(`Relay: \`${report.relayUrl || "unknown"}\``);
  lines.push("");
  lines.push("## Summary");
  lines.push("");
  lines.push(`- OK: ${report.summary.ok ? "true" : "false"}`);
  lines.push(`- Scenario: ${report.summary.scenario}`);
  lines.push(`- Scenario OK: ${report.summary.scenarioOK ? "true" : "false"}`);
  lines.push(`- Client-path OK: ${report.summary.clientPathOK ? "true" : "false"}`);
  lines.push(`- Transitions: ${report.summary.scenarioTransitionCount}`);
  lines.push(`- Failures: ${report.summary.failures}`);
  lines.push(`- Route counts: \`${JSON.stringify(report.clientPathEvidence.routeCounts || {})}\``);
  lines.push("");
  lines.push("This report is designed for the simulator displayed-UI judge. The simulator app must connect to this same temporary relay before the scenario mutates source rows.");
  lines.push("");
  lines.push("## Failures");
  lines.push("");
  if (!report.findings.length) {
    lines.push("- None.");
  } else {
    for (const finding of report.findings.slice(0, 50)) {
      lines.push(`- \`${finding.code}\`: ${finding.message}`);
    }
  }
  lines.push("");
  return `${lines.join("\n")}\n`;
}

async function closeWebSocketServer(server) {
  await new Promise((resolve) => {
    let finished = false;
    const finish = () => {
      if (finished) {
        return;
      }
      finished = true;
      clearTimeout(forceTimer);
      resolve();
    };
    const forceTimer = setTimeout(() => {
      for (const client of server.clients || []) {
        try {
          client.terminate();
        } catch {
          // The fixture is already shutting down; a dead client should not hang cleanup.
        }
      }
      finish();
    }, 500);
    try {
      server.close(() => finish());
    } catch {
      finish();
    }
    for (const client of server.clients || []) {
      try {
        client.close();
      } catch {
        // The fixture is already shutting down; a dead client should not hang cleanup.
      }
    }
  });
}

function newestTimestamp(values) {
  let newest = null;
  for (const value of values) {
    const parsed = Date.parse(value || 0);
    if (!Number.isFinite(parsed)) {
      continue;
    }
    if (newest === null || parsed > newest) {
      newest = parsed;
    }
  }
  return newest === null ? new Date().toISOString() : new Date(newest).toISOString();
}

function compositeFreshness(snapshots) {
  const freshnesses = snapshots.map((snapshot) => snapshot?.freshness).filter(Boolean);
  const nonFresh = freshnesses.find((freshness) => freshness?.status && freshness.status !== "fresh") || null;
  if (nonFresh) {
    return nonFresh;
  }
  return {
    status: "fresh",
    lastAttemptAt: newestTimestamp(freshnesses.map((freshness) => freshness.lastAttemptAt)),
    lastSyncAt: newestTimestamp(freshnesses.map((freshness) => freshness.lastSyncAt)),
    lastError: null,
  };
}

function mergeDockSnapshotsForSimulatorReport(snapshots) {
  const normalizedSnapshots = snapshots
    .filter(Boolean)
    .map((snapshot) => sanitizeDockSnapshotForReport(snapshot));
  const cards = normalizedSnapshots.flatMap((snapshot) => Array.isArray(snapshot.cards) ? snapshot.cards : []);
  const hostsByID = new Map();
  for (const snapshot of normalizedSnapshots) {
    for (const host of Array.isArray(snapshot.hosts) ? snapshot.hosts : []) {
      if (host?.id && !hostsByID.has(host.id)) {
        hostsByID.set(host.id, host);
      }
    }
  }
  const cardIDs = cards.map(cardID);
  const rowCount = cards.length;
  return {
    kind: "snapshot",
    schemaVersion: 2,
    epoch: `composite-${normalizedSnapshots.map((snapshot) => snapshot.epoch || "unknown").join("-")}`,
    seq: Math.max(0, ...normalizedSnapshots.map((snapshot) => Number(snapshot.seq || 0))),
    view: "dock",
    complete: normalizedSnapshots.every((snapshot) => snapshot.complete !== false),
    totalRows: rowCount,
    window: {
      offset: 0,
      limit: rowCount,
      rowCount,
      nextOffset: null,
    },
    cardCount: rowCount,
    cardIDs,
    renderOrderCardIDs: cards.map(cardID),
    cards,
    hosts: [...hostsByID.values()],
    freshness: compositeFreshness(normalizedSnapshots),
    lastReceivedAt: newestTimestamp(normalizedSnapshots.map((snapshot) => snapshot.lastReceivedAt)),
    needsResync: normalizedSnapshots.some((snapshot) => snapshot.needsResync === true),
    collection: null,
  };
}

async function createControlledMultiHostFixture({ options, tempDir, host, getRows }) {
  const historyServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await new Promise((resolve) => historyServer.once("listening", resolve));
  historyServer.on("connection", (ws) => {
    ws.on("message", (data) => {
      const message = JSON.parse(data.toString());
      if (message.method === "initialize") {
        sendFixtureResult(ws, message.id, {
          userAgent: `codex-sim-${host.id}-fixture`,
          codexHome: tempDir,
          platformFamily: "unix",
          platformOs: "macos",
        });
      } else if (message.method === "thread/list") {
        sendFixtureResult(ws, message.id, {
          data: getRows(),
          nextCursor: null,
          backwardsCursor: null,
        });
      } else if (message.method === "thread/loaded/list") {
        sendFixtureResult(ws, message.id, { data: [], nextCursor: null });
      }
    });
  });

  const relayConfig = {
    listenHost: "127.0.0.1",
    port: 0,
    phoneAuth: "none",
    hostId: host.id,
    hostName: host.displayName,
    hostEndpoint: host.endpoint,
    historyUrl: `ws://127.0.0.1:${historyServer.address().port}`,
    historyBearerToken: "history-token",
    advertiseBonjour: false,
    observabilityDir: false,
    relayStateDatabasePath: path.join(tempDir, `${host.id}-relay-state.sqlite`),
    relayStateAutoStart: false,
    logger: {
      debug() {},
      info() {},
      warn() {},
      error() {},
      fault() {},
      fatalSync() {},
    },
  };
  const relay = startServer(relayConfig);
  await relay.listening;
  const relayPort = relay.server.address().port;
  return {
    host,
    relay,
    relayConfig,
    historyServer,
    relayPort,
    relayUrl: `ws://127.0.0.1:${relayPort}`,
    endpoint: `127.0.0.1:${relayPort}`,
    options: {
      ...options,
      relayUrl: `ws://127.0.0.1:${relayPort}`,
      codexHome: tempDir,
      sqliteHome: tempDir,
      detail: "none",
    },
  };
}

function multiHostIsolationFindings({ label, snapshot, host, expectedThreadIDs, forbiddenThreadIDs = [] }) {
  const findings = [];
  const cards = Array.isArray(snapshot?.cards) ? snapshot.cards : [];
  const cardIDs = new Set(cards.map((card) => cardID(card)));
  for (const card of cards) {
    if (card?.logicalHostID !== host.id) {
      transitionFailure(
        findings,
        "scenario_multi_host_wrong_logical_host",
        "Dock card used the wrong logical host id for this relay host",
        {
          label,
          expectedHostID: host.id,
          actualHostID: card?.logicalHostID || null,
          threadID: cardThreadID(card),
        }
      );
    }
    if (!String(cardID(card) || "").startsWith(`${host.id}::`)) {
      transitionFailure(
        findings,
        "scenario_multi_host_wrong_card_id_scope",
        "Dock card id is not scoped by the relay host id",
        {
          label,
          expectedPrefix: `${host.id}::`,
          cardID: cardID(card),
          threadID: cardThreadID(card),
        }
      );
    }
  }
  for (const threadID of expectedThreadIDs) {
    if (!cardIDs.has(`${host.id}::${threadID}`)) {
      transitionFailure(
        findings,
        "scenario_multi_host_expected_thread_missing",
        "expected host-scoped thread is missing from this relay host",
        {
          label,
          hostID: host.id,
          threadID,
        }
      );
    }
  }
  for (const threadID of forbiddenThreadIDs) {
    if (cards.some((card) => cardThreadID(card) === threadID)) {
      transitionFailure(
        findings,
        "scenario_multi_host_foreign_thread_visible",
        "a thread from another relay host appeared in this host's Dock stream",
        {
          label,
          hostID: host.id,
          forbiddenThreadID: threadID,
        }
      );
    }
  }
  return findings;
}

async function runLargeListCheckpointScenario(options) {
  const routeEvents = [];
  const findings = [];
  const samples = [];
  const startedAtMs = Date.now();
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "codex-dock-sim-large-list-"));
  const hostID = "sim-large-list-fixture";
  const rowCount = 18;
  const sourceRows = Array.from({ length: rowCount }, (_, index) => fixtureThread(
    `sim-large-list-${String(index + 1).padStart(2, "0")}`,
    `Simulator large list row ${index + 1}`,
    10_000 - index
  ));

  const historyServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await new Promise((resolve) => historyServer.once("listening", resolve));
  historyServer.on("connection", (ws) => {
    ws.on("message", (data) => {
      const message = JSON.parse(data.toString());
      if (message.method === "initialize") {
        sendFixtureResult(ws, message.id, {
          userAgent: "codex-sim-large-list-fixture",
          codexHome: tempDir,
          platformFamily: "unix",
          platformOs: "macos",
        });
      } else if (message.method === "thread/list") {
        sendFixtureResult(ws, message.id, {
          data: sourceRows,
          nextCursor: null,
          backwardsCursor: null,
        });
      } else if (message.method === "thread/loaded/list") {
        sendFixtureResult(ws, message.id, { data: [], nextCursor: null });
      } else if (message.method === "thread/read" || message.method === "thread/resume") {
        const threadID = message.params?.threadId || message.params?.threadID;
        const thread = sourceRows.find((row) => row.id === threadID);
        if (!thread) {
          sendFixtureError(ws, message.id, `unknown thread: ${threadID || "missing"}`);
          return;
        }
        sendFixtureResult(ws, message.id, {
          thread: {
            ...thread,
            turns: [],
          },
        });
      } else if (message.method === "thread/turns/list") {
        sendFixtureResult(ws, message.id, {
          data: [],
          nextCursor: null,
          backwardsCursor: null,
        });
      }
    });
  });

  const relayConfig = {
    listenHost: "127.0.0.1",
    port: 0,
    phoneAuth: "none",
    hostId: hostID,
    hostName: "Simulator Large List Fixture",
    hostEndpoint: "127.0.0.1:0",
    historyUrl: `ws://127.0.0.1:${historyServer.address().port}`,
    historyBearerToken: "history-token",
    advertiseBonjour: false,
    observabilityDir: false,
    relayStateDatabasePath: path.join(tempDir, "relay-state.sqlite"),
    relayStateAutoStart: false,
    logger: {
      debug() {},
      info() {},
      warn() {},
      error() {},
      fault() {},
      fatalSync() {},
    },
  };
  const relay = startServer(relayConfig);
  await relay.listening;
  const relayPort = relay.server.address().port;
  const relayUrl = `ws://127.0.0.1:${relayPort}`;
  const fixtureOptions = {
    ...options,
    relayUrl,
    codexHome: tempDir,
    sqliteHome: tempDir,
    detail: "none",
  };
  const streamProbe = new DockStreamProbe(fixtureOptions);

  try {
    await streamProbe.open();
    const initialWait = await waitForStreamCondition({
      streamProbe,
      timeoutMs: options.dockCollectionTimeoutMs,
      predicate: (snapshot) => (
        Array.isArray(snapshot?.cards)
          && snapshot.cards.length === rowCount
          && dockSnapshotThreadIndex(snapshot, sourceRows[0].id) === 0
          && dockSnapshotHasThread(snapshot, sourceRows[rowCount - 1].id)
      ),
    });
    if (!initialWait.ok) {
      transitionFailure(
        findings,
        "scenario_large_list_initial_rows_missing",
        "large-list fixture did not expose all expected rows through the fixture relay stream",
        { expectedRows: rowCount }
      );
    }

    const initial = await freshComparison({ streamProbe, options: fixtureOptions, routeEvents });
    findings.push(...scenarioComparisonFindings({ phase: "large-list-initial", comparison: initial.comparison }));
    samples.push({
      sampleIndex: 0,
      startedAt: new Date(startedAtMs).toISOString(),
      finishedAt: new Date().toISOString(),
      freshDock: sanitizeDockSnapshotForReport(initial.freshDock),
    });

    findings.push(...requiredRouteFindings(
      summarizeClientPathEvents([...streamProbe.routeEvents, ...routeEvents]),
      ["dock/subscribe"]
    ));

    writeJSON(options.readyOut, {
      ready: true,
      scenario: "large-list-checkpoint",
      relayUrl,
      hosts: `127.0.0.1:${relayPort}`,
      target: {
        logicalHostID: hostID,
        rowCount,
        firstThreadID: sourceRows[0].id,
        lastThreadID: sourceRows[rowCount - 1].id,
      },
      at: new Date().toISOString(),
    });
    await waitForFile(options.uiReadyIn, options.waitTimeoutMs, "simulator UI sampler readiness");
    if (options.scenarioHoldMs > 0) {
      await sleep(Math.min(Math.max(options.scenarioHoldMs, 500), 1_500));
    }

    const checkpoint = await freshComparison({ streamProbe, options: fixtureOptions, routeEvents });
    findings.push(...scenarioComparisonFindings({ phase: "large-list-checkpoint", comparison: checkpoint.comparison }));
    samples.push({
      sampleIndex: 1,
      startedAt: new Date().toISOString(),
      finishedAt: new Date().toISOString(),
      freshDock: sanitizeDockSnapshotForReport(checkpoint.freshDock),
    });

    const clientPathEvidence = summarizeClientPathEvents([...streamProbe.routeEvents, ...routeEvents]);
    const scenarioOK = !findings.some((finding) => finding.severity === "error" || finding.severity === "warning");
    const report = {
      schemaVersion: 1,
      kind: "codex-dock-controlled-simulator-scenario-relay-report",
      mode: "scenario",
      scenario: "large-list-checkpoint",
      startedAt: new Date(startedAtMs).toISOString(),
      endedAt: new Date().toISOString(),
      relayUrl,
      summary: {
        ok: scenarioOK,
        clientPathOK: scenarioOK,
        scenario: "large-list-checkpoint",
        scenarioOK,
        scenarioCount: 1,
        scenarioTransitionCount: 0,
        implementedScenarios: ["large-list-checkpoint"],
        unimplementedRequiredScenarios: [],
        failures: findings.length,
        clientPathRouteCounts: clientPathEvidence.routeCounts,
      },
      samples,
      scenarios: [{
        id: "large-list-checkpoint",
        ok: scenarioOK,
        actuator: {
          type: "controlled large Dock list through real relay and simulator checkpoint sweep",
          routes: ["dock/subscribe"],
          clientExercised: true,
          note: "The fixture exposes enough Dock rows that the actual simulator checkpoint sweep must scroll and compare rows beyond the initial viewport.",
        },
        target: {
          logicalHostID: hostID,
          rowCount,
          threadIDs: sourceRows.map((row) => row.id),
        },
        transitions: [],
        findings,
      }],
      stream: {
        notificationCount: streamProbe.notifications.length,
        resyncCount: streamProbe.resyncs.length,
        finalState: sanitizeDockSnapshotForReport(streamProbe.snapshot()),
      },
      clientPathEvidence,
      findings,
      unsupportedFacts: [],
    };

    writeJSON(options.jsonOut, report);
    if (options.summaryOut) {
      writeText(options.summaryOut, buildMarkdownSummary(report));
    }
    await waitForFile(options.stopIn, options.waitTimeoutMs, "simulator UI sampler completion");
    return report;
  } finally {
    await streamProbe.close().catch(() => null);
    await relay.close().catch(() => null);
    await closeWebSocketServer(historyServer).catch(() => null);
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

async function runThreadActivityScenario(options) {
  const routeEvents = [];
  const findings = [];
  const transitions = [];
  const samples = [];
  const startedAtMs = Date.now();
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "codex-dock-sim-thread-activity-"));
  const hostID = "sim-thread-activity-fixture";
  const stableThreadID = "sim-thread-activity-stable";
  const movingThreadID = "sim-thread-activity-moving";
  const newThreadID = "sim-thread-activity-new";
  const updatedPreview = "Simulator fixture existing row after new turn";
  let sourceRows = [
    fixtureThread(stableThreadID, "Simulator fixture stable row", 200),
    fixtureThread(movingThreadID, "Simulator fixture moving row before update", 100),
  ];

  const historyServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await new Promise((resolve) => historyServer.once("listening", resolve));
  historyServer.on("connection", (ws) => {
    ws.on("message", (data) => {
      const message = JSON.parse(data.toString());
      if (message.method === "initialize") {
        sendFixtureResult(ws, message.id, {
          userAgent: "codex-sim-thread-activity-fixture",
          codexHome: tempDir,
          platformFamily: "unix",
          platformOs: "macos",
        });
      } else if (message.method === "thread/list") {
        sendFixtureResult(ws, message.id, {
          data: sourceRows,
          nextCursor: null,
          backwardsCursor: null,
        });
      } else if (message.method === "thread/loaded/list") {
        sendFixtureResult(ws, message.id, { data: [], nextCursor: null });
      }
    });
  });

  const relayConfig = {
    listenHost: "127.0.0.1",
    port: 0,
    phoneAuth: "none",
    hostId: hostID,
    hostName: "Simulator Thread Activity Fixture",
    hostEndpoint: "127.0.0.1:0",
    historyUrl: `ws://127.0.0.1:${historyServer.address().port}`,
    historyBearerToken: "history-token",
    advertiseBonjour: false,
    observabilityDir: false,
    relayStateDatabasePath: path.join(tempDir, "relay-state.sqlite"),
    relayStateAutoStart: false,
    logger: {
      debug() {},
      info() {},
      warn() {},
      error() {},
      fault() {},
      fatalSync() {},
    },
  };
  const relay = startServer(relayConfig);
  await relay.listening;
  const relayPort = relay.server.address().port;
  const relayUrl = `ws://127.0.0.1:${relayPort}`;
  const fixtureOptions = {
    ...options,
    relayUrl,
    codexHome: tempDir,
    sqliteHome: tempDir,
    detail: "none",
  };
  const streamProbe = new DockStreamProbe(fixtureOptions);

  try {
    await streamProbe.open();
    const initialWait = await waitForStreamCondition({
      streamProbe,
      timeoutMs: options.dockCollectionTimeoutMs,
      predicate: (snapshot) => (
        dockSnapshotThreadIndex(snapshot, stableThreadID) === 0
        && dockSnapshotThreadIndex(snapshot, movingThreadID) === 1
      ),
    });
    if (!initialWait.ok) {
      transitionFailure(
        findings,
        "scenario_thread_activity_initial_order_missing",
        "initial fixture rows did not appear in the expected Dock order before simulator launch",
        { expectedOrder: [stableThreadID, movingThreadID] }
      );
    }
    const initial = await freshComparison({ streamProbe, options: fixtureOptions, routeEvents });
    findings.push(...scenarioComparisonFindings({ phase: "initial", comparison: initial.comparison }));
    const initialFinishedAt = new Date().toISOString();
    samples.push({
      sampleIndex: 0,
      startedAt: new Date(startedAtMs).toISOString(),
      finishedAt: initialFinishedAt,
      freshDock: sanitizeDockSnapshotForReport(initial.freshDock),
    });

    writeJSON(options.readyOut, {
      ready: true,
      scenario: "thread-activity",
      relayUrl,
      hosts: `127.0.0.1:${relayPort}`,
      target: {
        logicalHostID: hostID,
        stableThreadID,
        movingThreadID,
        newThreadID,
      },
      at: new Date().toISOString(),
    });
    await waitForFile(options.uiReadyIn, options.waitTimeoutMs, "simulator UI sampler readiness");
    await sleep(Math.min(Math.max(options.scenarioHoldMs, 500), 1_500));

    const newStartedAtMs = Date.now();
    sourceRows = [
      fixtureThread(newThreadID, "Simulator fixture newly created row", 300),
      fixtureThread(stableThreadID, "Simulator fixture stable row", 200),
      fixtureThread(movingThreadID, "Simulator fixture moving row before update", 100),
    ];
    await relayConfig.relayStateEngine.reconcileDock({ reason: "controlled_simulator_thread_activity_new_thread" });
    const newWait = await waitForStreamCondition({
      streamProbe,
      timeoutMs: options.dockCollectionTimeoutMs,
      predicate: (snapshot) => (
        dockSnapshotThreadIndex(snapshot, newThreadID) === 0
        && dockSnapshotThreadIndex(snapshot, stableThreadID) === 1
        && dockSnapshotThreadIndex(snapshot, movingThreadID) === 2
      ),
    });
    const newLag = scenarioLagSummary({
      transition: "new-thread",
      startedAtMs: newStartedAtMs,
      acknowledgedAtMs: newStartedAtMs,
      observedAtMs: newWait.observedAtMs,
      maxStreamLagMs: options.maxStreamLagMs,
    });
    if (!newWait.ok) {
      transitionFailure(findings, "scenario_new_thread_not_seen", "new thread did not appear at the top of the fixture relay stream", {
        threadID: newThreadID,
      });
    } else if (newLag.exceeded) {
      transitionFailure(findings, "scenario_new_thread_lag_exceeded", "new thread appeared after the relay lag budget", {
        observedLagMs: newLag.lag_change_to_relay_ms,
        maxStreamLagMs: options.maxStreamLagMs,
      });
    }
    const newComparison = await freshComparison({ streamProbe, options: fixtureOptions, routeEvents });
    findings.push(...scenarioComparisonFindings({ phase: "new-thread", comparison: newComparison.comparison }));
    transitions.push({
      name: "new-thread",
      kind: "new-thread",
      iteration: 1,
      route: "dock/update",
      wait: newWait,
      lag: newLag,
      freshDock: sanitizeDockSnapshotForReport(newComparison.freshDock),
      streamComparison: newComparison.comparison,
      streamComparisonAttempts: newComparison.attempts,
    });

    if (options.scenarioHoldMs > 0) {
      await sleep(options.scenarioHoldMs);
    }

    const turnStartedAtMs = Date.now();
    sourceRows = [
      fixtureThread(movingThreadID, updatedPreview, 400),
      fixtureThread(newThreadID, "Simulator fixture newly created row", 300),
      fixtureThread(stableThreadID, "Simulator fixture stable row", 200),
    ];
    await relayConfig.relayStateEngine.reconcileDock({ reason: "controlled_simulator_thread_activity_new_turn_order" });
    const turnWait = await waitForStreamCondition({
      streamProbe,
      timeoutMs: options.dockCollectionTimeoutMs,
      predicate: (snapshot) => {
        const card = dockSnapshotCardForThread(snapshot, movingThreadID);
        return dockSnapshotThreadIndex(snapshot, movingThreadID) === 0
          && dockSnapshotThreadIndex(snapshot, newThreadID) === 1
          && card?.displaySummary === updatedPreview;
      },
    });
    const turnLag = scenarioLagSummary({
      transition: "new-turn-order",
      startedAtMs: turnStartedAtMs,
      acknowledgedAtMs: turnStartedAtMs,
      observedAtMs: turnWait.observedAtMs,
      maxStreamLagMs: options.maxStreamLagMs,
    });
    if (!turnWait.ok) {
      transitionFailure(findings, "scenario_new_turn_order_not_seen", "existing thread update did not move the row to the top in the fixture relay stream", {
        threadID: movingThreadID,
      });
    } else if (turnLag.exceeded) {
      transitionFailure(findings, "scenario_new_turn_order_lag_exceeded", "existing thread update moved order after the relay lag budget", {
        observedLagMs: turnLag.lag_change_to_relay_ms,
        maxStreamLagMs: options.maxStreamLagMs,
      });
    }
    const turnComparison = await freshComparison({ streamProbe, options: fixtureOptions, routeEvents });
    findings.push(...scenarioComparisonFindings({ phase: "new-turn-order", comparison: turnComparison.comparison }));
    transitions.push({
      name: "new-turn-order",
      kind: "new-turn-order",
      iteration: 1,
      route: "dock/update",
      wait: turnWait,
      lag: turnLag,
      freshDock: sanitizeDockSnapshotForReport(turnComparison.freshDock),
      streamComparison: turnComparison.comparison,
      streamComparisonAttempts: turnComparison.attempts,
    });

    const clientPathEvidence = summarizeClientPathEvents([...streamProbe.routeEvents, ...routeEvents]);
    const scenarioOK = !findings.some((finding) => finding.severity === "error" || finding.severity === "warning");
    const report = {
      schemaVersion: 1,
      kind: "codex-dock-controlled-simulator-scenario-relay-report",
      mode: "scenario",
      scenario: "thread-activity",
      startedAt: new Date(startedAtMs).toISOString(),
      endedAt: new Date().toISOString(),
      relayUrl,
      summary: {
        ok: scenarioOK,
        clientPathOK: scenarioOK,
        scenario: "thread-activity",
        scenarioOK,
        scenarioCount: 1,
        scenarioTransitionCount: transitions.length,
        implementedScenarios: ["thread-activity"],
        unimplementedRequiredScenarios: [],
        failures: findings.length,
        clientPathRouteCounts: clientPathEvidence.routeCounts,
      },
      samples,
      scenarios: [{
        id: "thread-activity",
        ok: scenarioOK,
        target: {
          logicalHostID: hostID,
          stableThreadID,
          movingThreadID,
          newThreadID,
        },
        transitions,
        findings,
      }],
      stream: {
        notificationCount: streamProbe.notifications.length,
        resyncCount: streamProbe.resyncs.length,
        finalState: sanitizeDockSnapshotForReport(streamProbe.snapshot()),
      },
      clientPathEvidence,
      findings,
      unsupportedFacts: [],
    };

    writeJSON(options.jsonOut, report);
    if (options.summaryOut) {
      writeText(options.summaryOut, buildMarkdownSummary(report));
    }
    await waitForFile(options.stopIn, options.waitTimeoutMs, "simulator UI sampler completion");
    return report;
  } finally {
    await streamProbe.close().catch(() => null);
    await relay.close().catch(() => null);
    await closeWebSocketServer(historyServer).catch(() => null);
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

async function runRapidMutationsScenario(options) {
  const routeEvents = [];
  const findings = [];
  const transitions = [];
  const samples = [];
  const startedAtMs = Date.now();
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "codex-dock-sim-rapid-mutations-"));
  const hostID = "sim-rapid-mutations-fixture";
  const targetThreadID = "sim-rapid-mutations-target";
  const stableThreadID = "sim-rapid-mutations-stable";
  const stableRow = () => fixtureThreadWithStatus(
    stableThreadID,
    "Simulator rapid mutations stable row",
    100,
    { type: "active", activeFlags: [] }
  );
  const targetRow = ({ preview, updatedAt, status }) => fixtureThreadWithStatus(
    targetThreadID,
    preview,
    updatedAt,
    status
  );
  const mutationSteps = [
    {
      name: "rapid-needs-approval-1",
      expectedStatus: "needsApproval",
      preview: "Simulator rapid mutation step 1 needs approval",
      updatedAt: 300,
      status: { type: "active", activeFlags: ["waitingOnApproval"] },
    },
    {
      name: "rapid-needs-input-1",
      expectedStatus: "needsInput",
      preview: "Simulator rapid mutation step 2 needs input",
      updatedAt: 400,
      status: { type: "active", activeFlags: ["waitingOnUserInput"] },
    },
    {
      name: "rapid-error-1",
      expectedStatus: "error",
      preview: "Simulator rapid mutation step 3 error",
      updatedAt: 500,
      status: { type: "systemError" },
    },
    {
      name: "rapid-running",
      expectedStatus: "running",
      preview: "Simulator rapid mutation step 4 running",
      updatedAt: 600,
      status: { type: "active", activeFlags: [] },
    },
    {
      name: "rapid-needs-approval-2",
      expectedStatus: "needsApproval",
      preview: "Simulator rapid mutation step 5 needs approval again",
      updatedAt: 700,
      status: { type: "active", activeFlags: ["waitingOnApproval"] },
    },
    {
      name: "rapid-needs-input-2",
      expectedStatus: "needsInput",
      preview: "Simulator rapid mutation step 6 needs input again",
      updatedAt: 800,
      status: { type: "active", activeFlags: ["waitingOnUserInput"] },
    },
  ];
  let sourceRows = [
    targetRow({
      preview: "Simulator rapid mutations initial running row",
      updatedAt: 200,
      status: { type: "active", activeFlags: [] },
    }),
    stableRow(),
  ];

  const historyServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await new Promise((resolve) => historyServer.once("listening", resolve));
  historyServer.on("connection", (ws) => {
    ws.on("message", (data) => {
      const message = JSON.parse(data.toString());
      if (message.method === "initialize") {
        sendFixtureResult(ws, message.id, {
          userAgent: "codex-sim-rapid-mutations-fixture",
          codexHome: tempDir,
          platformFamily: "unix",
          platformOs: "macos",
        });
      } else if (message.method === "thread/list") {
        sendFixtureResult(ws, message.id, {
          data: sourceRows,
          nextCursor: null,
          backwardsCursor: null,
        });
      } else if (message.method === "thread/loaded/list") {
        sendFixtureResult(ws, message.id, { data: [], nextCursor: null });
      }
    });
  });

  const relayConfig = {
    listenHost: "127.0.0.1",
    port: 0,
    phoneAuth: "none",
    hostId: hostID,
    hostName: "Simulator Rapid Mutations Fixture",
    hostEndpoint: "127.0.0.1:0",
    historyUrl: `ws://127.0.0.1:${historyServer.address().port}`,
    historyBearerToken: "history-token",
    advertiseBonjour: false,
    observabilityDir: false,
    relayStateDatabasePath: path.join(tempDir, "relay-state.sqlite"),
    relayStateAutoStart: false,
    logger: {
      debug() {},
      info() {},
      warn() {},
      error() {},
      fault() {},
      fatalSync() {},
    },
  };
  const relay = startServer(relayConfig);
  await relay.listening;
  const relayPort = relay.server.address().port;
  const relayUrl = `ws://127.0.0.1:${relayPort}`;
  const fixtureOptions = {
    ...options,
    relayUrl,
    codexHome: tempDir,
    sqliteHome: tempDir,
    detail: "none",
  };
  const streamProbe = new DockStreamProbe(fixtureOptions);

  try {
    await streamProbe.open();
    const initialWait = await waitForStreamCondition({
      streamProbe,
      timeoutMs: options.dockCollectionTimeoutMs,
      predicate: (snapshot) => (
        dockSnapshotThreadIndex(snapshot, targetThreadID) === 0
        && dockSnapshotThreadIndex(snapshot, stableThreadID) === 1
        && dockSnapshotCardForThread(snapshot, targetThreadID)?.status === "running"
        && dockSnapshotCardForThread(snapshot, stableThreadID)?.status === "running"
      ),
    });
    if (!initialWait.ok) {
      transitionFailure(
        findings,
        "scenario_rapid_mutations_initial_state_missing",
        "rapid-mutations initial rows did not appear in the expected Dock state before simulator launch",
        {
          targetThreadID,
          stableThreadID,
          expectedOrder: [targetThreadID, stableThreadID],
        }
      );
    }
    const initial = await freshComparison({ streamProbe, options: fixtureOptions, routeEvents });
    findings.push(...scenarioComparisonFindings({ phase: "initial", comparison: initial.comparison }));
    const initialFinishedAt = new Date().toISOString();
    samples.push({
      sampleIndex: 0,
      startedAt: new Date(startedAtMs).toISOString(),
      finishedAt: initialFinishedAt,
      freshDock: sanitizeDockSnapshotForReport(initial.freshDock),
    });

    writeJSON(options.readyOut, {
      ready: true,
      scenario: "rapid-mutations",
      relayUrl,
      hosts: `127.0.0.1:${relayPort}`,
      target: {
        logicalHostID: hostID,
        targetThreadID,
        stableThreadID,
        mutationCount: mutationSteps.length,
      },
      at: new Date().toISOString(),
    });
    await waitForFile(options.uiReadyIn, options.waitTimeoutMs, "simulator UI sampler readiness");
    await sleep(Math.min(Math.max(options.scenarioHoldMs, 500), 1_500));

    for (let index = 0; index < mutationSteps.length; index += 1) {
      const step = mutationSteps[index];
      const mutationStartedAtMs = Date.now();
      sourceRows = [
        targetRow(step),
        stableRow(),
      ];
      await relayConfig.relayStateEngine.reconcileDock({ reason: `controlled_simulator_${step.name}` });
      const mutationWait = await waitForStreamCondition({
        streamProbe,
        timeoutMs: options.dockCollectionTimeoutMs,
        predicate: (snapshot) => (
          dockSnapshotThreadIndex(snapshot, targetThreadID) === 0
          && dockSnapshotThreadIndex(snapshot, stableThreadID) === 1
          && dockSnapshotCardForThread(snapshot, targetThreadID)?.status === step.expectedStatus
        ),
      });
      const mutationLag = scenarioLagSummary({
        transition: step.name,
        startedAtMs: mutationStartedAtMs,
        acknowledgedAtMs: mutationStartedAtMs,
        observedAtMs: mutationWait.observedAtMs,
        maxStreamLagMs: options.maxStreamLagMs,
      });
      if (!mutationWait.ok) {
        transitionFailure(
          findings,
          "scenario_rapid_mutation_not_seen",
          "rapid repeated mutation did not appear through the fixture relay stream",
          {
            transition: step.name,
            targetThreadID,
            expectedStatus: step.expectedStatus,
          }
        );
      } else if (mutationLag.exceeded) {
        transitionFailure(
          findings,
          "scenario_rapid_mutation_lag_exceeded",
          "rapid repeated mutation appeared after the relay lag budget",
          {
            transition: step.name,
            targetThreadID,
            expectedStatus: step.expectedStatus,
            observedLagMs: mutationLag.lag_change_to_relay_ms,
            maxStreamLagMs: options.maxStreamLagMs,
          }
        );
      }
      const mutationComparison = await freshComparison({ streamProbe, options: fixtureOptions, routeEvents });
      const targetCard = dockSnapshotCardForThread(mutationComparison.freshDock, targetThreadID);
      if (targetCard?.status !== step.expectedStatus) {
        transitionFailure(
          findings,
          "scenario_rapid_mutation_fresh_dock_status_mismatch",
          "fresh Dock client-path snapshot did not match the expected repeated mutation status",
          {
            transition: step.name,
            targetThreadID,
            expectedStatus: step.expectedStatus,
            actualStatus: targetCard?.status || null,
          }
        );
      }
      findings.push(...scenarioComparisonFindings({ phase: step.name, comparison: mutationComparison.comparison }));
      transitions.push({
        name: step.name,
        kind: "rapid-mutation",
        iteration: index + 1,
        route: "dock/update",
        expectedStatus: step.expectedStatus,
        wait: mutationWait,
        lag: mutationLag,
        freshDock: sanitizeDockSnapshotForReport(mutationComparison.freshDock),
        streamComparison: mutationComparison.comparison,
        streamComparisonAttempts: mutationComparison.attempts,
      });

      if (index < mutationSteps.length - 1 && options.scenarioHoldMs > 0) {
        await sleep(options.scenarioHoldMs);
      }
    }

    const clientPathEvidence = summarizeClientPathEvents([...streamProbe.routeEvents, ...routeEvents]);
    const scenarioOK = !findings.some((finding) => finding.severity === "error" || finding.severity === "warning");
    const report = {
      schemaVersion: 1,
      kind: "codex-dock-controlled-simulator-scenario-relay-report",
      mode: "scenario",
      scenario: "rapid-mutations",
      startedAt: new Date(startedAtMs).toISOString(),
      endedAt: new Date().toISOString(),
      relayUrl,
      summary: {
        ok: scenarioOK,
        clientPathOK: scenarioOK,
        scenario: "rapid-mutations",
        scenarioOK,
        scenarioCount: 1,
        scenarioTransitionCount: transitions.length,
        implementedScenarios: ["rapid-mutations"],
        unimplementedRequiredScenarios: [],
        failures: findings.length,
        clientPathRouteCounts: clientPathEvidence.routeCounts,
      },
      samples,
      scenarios: [{
        id: "rapid-mutations",
        ok: scenarioOK,
        actuator: {
          type: "controlled app-server thread/list mutation through real relay Dock routes",
          routes: ["dock/subscribe", "dock/update"],
          clientExercised: true,
          mutationCount: mutationSteps.length,
          note: "The fixture changes one visible Dock row through ordered statuses while the simulator sampler is running; the UI judge must observe every transition before the next one.",
        },
        target: {
          logicalHostID: hostID,
          targetThreadID,
          stableThreadID,
        },
        transitions,
        findings,
      }],
      stream: {
        notificationCount: streamProbe.notifications.length,
        resyncCount: streamProbe.resyncs.length,
        finalState: sanitizeDockSnapshotForReport(streamProbe.snapshot()),
      },
      clientPathEvidence,
      findings,
      unsupportedFacts: [],
    };

    writeJSON(options.jsonOut, report);
    if (options.summaryOut) {
      writeText(options.summaryOut, buildMarkdownSummary(report));
    }
    await waitForFile(options.stopIn, options.waitTimeoutMs, "simulator UI sampler completion");
    return report;
  } finally {
    await streamProbe.close().catch(() => null);
    await relay.close().catch(() => null);
    await closeWebSocketServer(historyServer).catch(() => null);
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

async function runSourceRefreshScenario(options) {
  const routeEvents = [];
  const findings = [];
  const transitions = [];
  const samples = [];
  const startedAtMs = Date.now();
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "codex-dock-sim-source-refresh-"));
  const hostID = "sim-source-refresh-fixture";
  const cachedThreadID = "sim-source-refresh-cached";
  const recoveredThreadID = "sim-source-refresh-recovered";
  let upstreamAvailable = true;
  let sourceRows = [
    fixtureThread(cachedThreadID, "Simulator source refresh cached row", 100),
  ];

  const historyServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await new Promise((resolve) => historyServer.once("listening", resolve));
  historyServer.on("connection", (ws) => {
    ws.on("message", (data) => {
      const message = JSON.parse(data.toString());
      if (message.method === "initialize") {
        sendFixtureResult(ws, message.id, {
          userAgent: "codex-sim-source-refresh-fixture",
          codexHome: tempDir,
          platformFamily: "unix",
          platformOs: "macos",
        });
      } else if (message.method === "thread/list") {
        if (!upstreamAvailable) {
          sendFixtureError(ws, message.id, "controlled source refresh failure");
          return;
        }
        sendFixtureResult(ws, message.id, {
          data: sourceRows,
          nextCursor: null,
          backwardsCursor: null,
        });
      } else if (message.method === "thread/loaded/list") {
        sendFixtureResult(ws, message.id, { data: [], nextCursor: null });
      }
    });
  });

  const relayConfig = {
    listenHost: "127.0.0.1",
    port: 0,
    phoneAuth: "none",
    hostId: hostID,
    hostName: "Simulator Source Refresh Fixture",
    hostEndpoint: "127.0.0.1:0",
    historyUrl: `ws://127.0.0.1:${historyServer.address().port}`,
    historyBearerToken: "history-token",
    advertiseBonjour: false,
    observabilityDir: false,
    relayStateDatabasePath: path.join(tempDir, "relay-state.sqlite"),
    relayStateAutoStart: false,
    logger: {
      debug() {},
      info() {},
      warn() {},
      error() {},
      fault() {},
      fatalSync() {},
    },
  };
  const relay = startServer(relayConfig);
  await relay.listening;
  const relayPort = relay.server.address().port;
  const relayUrl = `ws://127.0.0.1:${relayPort}`;
  const fixtureOptions = {
    ...options,
    relayUrl,
    codexHome: tempDir,
    sqliteHome: tempDir,
    detail: "none",
  };
  const streamProbe = new DockStreamProbe(fixtureOptions);

  try {
    await streamProbe.open();
    const initialWait = await waitForStreamCondition({
      streamProbe,
      timeoutMs: options.dockCollectionTimeoutMs,
      predicate: (snapshot) => dockSnapshotThreadIndex(snapshot, cachedThreadID) === 0
        && snapshot?.freshness?.status !== "stale",
    });
    if (!initialWait.ok) {
      transitionFailure(
        findings,
        "scenario_source_refresh_initial_row_missing",
        "source-refresh fixture row did not appear fresh in the fixture relay stream before simulator launch",
        { threadID: cachedThreadID }
      );
    }
    const initial = await freshComparison({ streamProbe, options: fixtureOptions, routeEvents });
    findings.push(...scenarioComparisonFindings({ phase: "initial", comparison: initial.comparison }));
    const initialFinishedAt = new Date().toISOString();
    samples.push({
      sampleIndex: 0,
      startedAt: new Date(startedAtMs).toISOString(),
      finishedAt: initialFinishedAt,
      freshDock: sanitizeDockSnapshotForReport(initial.freshDock),
    });

    writeJSON(options.readyOut, {
      ready: true,
      scenario: "source-refresh",
      relayUrl,
      hosts: `127.0.0.1:${relayPort}`,
      target: {
        logicalHostID: hostID,
        cachedThreadID,
        recoveredThreadID,
      },
      at: new Date().toISOString(),
    });
    await waitForFile(options.uiReadyIn, options.waitTimeoutMs, "simulator UI sampler readiness");
    await sleep(Math.min(Math.max(options.scenarioHoldMs, 500), 1_500));

    const failStartedAtMs = Date.now();
    upstreamAvailable = false;
    await relayConfig.relayStateEngine.reconcileDock({ reason: "controlled_simulator_source_refresh_fails" });
    const staleWait = await waitForStreamCondition({
      streamProbe,
      timeoutMs: options.dockCollectionTimeoutMs,
      predicate: (snapshot) => (
        snapshot?.freshness?.status === "stale"
        && dockSnapshotHasThread(snapshot, cachedThreadID)
      ),
    });
    const failLag = scenarioLagSummary({
      transition: "source-refresh-fails",
      startedAtMs: failStartedAtMs,
      acknowledgedAtMs: failStartedAtMs,
      observedAtMs: staleWait.observedAtMs,
      maxStreamLagMs: options.maxStreamLagMs,
    });
    if (!staleWait.ok) {
      transitionFailure(
        findings,
        "scenario_source_refresh_stale_not_seen",
        "source refresh failure did not become explicit stale freshness through the fixture relay stream",
        { threadID: cachedThreadID }
      );
    } else if (failLag.exceeded) {
      transitionFailure(
        findings,
        "scenario_source_refresh_stale_lag_exceeded",
        "source refresh stale state appeared after the relay lag budget",
        {
          observedLagMs: failLag.lag_change_to_relay_ms,
          maxStreamLagMs: options.maxStreamLagMs,
        }
      );
    }
    const staleSnapshot = streamProbe.snapshot();
    if (!dockSnapshotHasThread(staleSnapshot, cachedThreadID)) {
      transitionFailure(
        findings,
        "scenario_source_refresh_stale_dropped_cached_row",
        "stale source refresh dropped the cached row instead of serving explicit stale cached state",
        { threadID: cachedThreadID }
      );
    }
    transitions.push({
      name: "source-refresh-fails",
      kind: "source-refresh-fails",
      iteration: 1,
      route: "dock/update",
      wait: staleWait,
      lag: failLag,
      freshDock: sanitizeDockSnapshotForReport(staleSnapshot),
    });

    if (options.scenarioHoldMs > 0) {
      await sleep(options.scenarioHoldMs);
    }

    const recoverStartedAtMs = Date.now();
    upstreamAvailable = true;
    sourceRows = [
      fixtureThread(recoveredThreadID, "Simulator source refresh recovered row", 200),
    ];
    await relayConfig.relayStateEngine.reconcileDock({ reason: "controlled_simulator_source_refresh_recovers" });
    const recoveredWait = await waitForStreamCondition({
      streamProbe,
      timeoutMs: options.dockCollectionTimeoutMs,
      predicate: (snapshot) => (
        snapshot?.freshness?.status === "fresh"
        && dockSnapshotHasThread(snapshot, recoveredThreadID)
        && !dockSnapshotHasThread(snapshot, cachedThreadID)
      ),
    });
    const recoverLag = scenarioLagSummary({
      transition: "source-refresh-recovers",
      startedAtMs: recoverStartedAtMs,
      acknowledgedAtMs: recoverStartedAtMs,
      observedAtMs: recoveredWait.observedAtMs,
      maxStreamLagMs: options.maxStreamLagMs,
    });
    if (!recoveredWait.ok) {
      transitionFailure(
        findings,
        "scenario_source_refresh_recovery_not_seen",
        "source refresh recovery did not reconcile stale rows to the recovered source row through the fixture relay stream",
        { staleThreadID: cachedThreadID, recoveredThreadID }
      );
    } else if (recoverLag.exceeded) {
      transitionFailure(
        findings,
        "scenario_source_refresh_recovery_lag_exceeded",
        "source refresh recovery appeared after the relay lag budget",
        {
          observedLagMs: recoverLag.lag_change_to_relay_ms,
          maxStreamLagMs: options.maxStreamLagMs,
        }
      );
    }
    const recoveredComparison = await freshComparison({ streamProbe, options: fixtureOptions, routeEvents });
    findings.push(...scenarioComparisonFindings({ phase: "source-refresh-recovers", comparison: recoveredComparison.comparison }));
    transitions.push({
      name: "source-refresh-recovers",
      kind: "source-refresh-recovers",
      iteration: 1,
      route: "dock/update",
      wait: recoveredWait,
      lag: recoverLag,
      freshDock: sanitizeDockSnapshotForReport(recoveredComparison.freshDock),
      streamComparison: recoveredComparison.comparison,
      streamComparisonAttempts: recoveredComparison.attempts,
    });

    const clientPathEvidence = summarizeClientPathEvents([...streamProbe.routeEvents, ...routeEvents]);
    const scenarioOK = !findings.some((finding) => finding.severity === "error" || finding.severity === "warning");
    const report = {
      schemaVersion: 1,
      kind: "codex-dock-controlled-simulator-scenario-relay-report",
      mode: "scenario",
      scenario: "source-refresh",
      startedAt: new Date(startedAtMs).toISOString(),
      endedAt: new Date().toISOString(),
      relayUrl,
      summary: {
        ok: scenarioOK,
        clientPathOK: scenarioOK,
        scenario: "source-refresh",
        scenarioOK,
        scenarioCount: 1,
        scenarioTransitionCount: transitions.length,
        implementedScenarios: ["source-refresh"],
        unimplementedRequiredScenarios: [],
        failures: findings.length,
        clientPathRouteCounts: clientPathEvidence.routeCounts,
      },
      samples,
      scenarios: [{
        id: "source-refresh",
        ok: scenarioOK,
        target: {
          logicalHostID: hostID,
          cachedThreadID,
          recoveredThreadID,
        },
        transitions,
        findings,
      }],
      stream: {
        notificationCount: streamProbe.notifications.length,
        resyncCount: streamProbe.resyncs.length,
        finalState: sanitizeDockSnapshotForReport(streamProbe.snapshot()),
      },
      clientPathEvidence,
      findings,
      unsupportedFacts: [],
    };

    writeJSON(options.jsonOut, report);
    if (options.summaryOut) {
      writeText(options.summaryOut, buildMarkdownSummary(report));
    }
    await waitForFile(options.stopIn, options.waitTimeoutMs, "simulator UI sampler completion");
    return report;
  } finally {
    await streamProbe.close().catch(() => null);
    await relay.close().catch(() => null);
    await closeWebSocketServer(historyServer).catch(() => null);
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

async function runLiveLeaseExpiryScenario(options) {
  const routeEvents = [];
  const findings = [];
  const transitions = [];
  const samples = [];
  const startedAtMs = Date.now();
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "codex-dock-sim-live-lease-expiry-"));
  const hostID = "sim-live-lease-expiry-fixture";
  const threadID = "sim-live-lease-expiry-thread";
  const sessionID = "sim-live-lease-expiry-session";
  const startupLiveStatusMaxAgeMs = Math.max(options.waitTimeoutMs + 5_000, 65_000);
  const controlledLiveStatusMaxAgeMs = Math.max(
    3_000,
    Math.min(8_000, options.scenarioHoldMs + options.maxStreamLagMs + 1_000)
  );
  const liveRunningHoldMs = Math.min(
    Math.max(options.scenarioHoldMs, 500),
    Math.max(500, controlledLiveStatusMaxAgeMs - options.maxStreamLagMs - 500)
  );
  let liveRowsEnabled = true;

  const liveServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  const historyServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await Promise.all([
    new Promise((resolve) => liveServer.once("listening", resolve)),
    new Promise((resolve) => historyServer.once("listening", resolve)),
  ]);

  liveServer.on("connection", (ws) => {
    ws.on("message", (data) => {
      const message = JSON.parse(data.toString());
      if (message.method === "initialize") {
        sendFixtureResult(ws, message.id, {
          userAgent: "codex-sim-live-lease-fixture",
          codexHome: tempDir,
          platformFamily: "unix",
          platformOs: "macos",
        });
      } else if (message.method === "thread/loaded/list") {
        sendFixtureResult(ws, message.id, {
          data: liveRowsEnabled ? [threadID] : [],
          nextCursor: null,
        });
      } else if (message.method === "thread/read") {
        sendFixtureResult(ws, message.id, {
          thread: {
            id: threadID,
            sessionId: sessionID,
            preview: "Simulator live row before lease expiry",
            updatedAt: 100,
            source: "cli",
            status: { type: "active", activeFlags: [] },
          },
        });
      }
    });
  });

  historyServer.on("connection", (ws) => {
    ws.on("message", (data) => {
      const message = JSON.parse(data.toString());
      if (message.method === "initialize") {
        sendFixtureResult(ws, message.id, {
          userAgent: "codex-sim-live-lease-history-fixture",
          codexHome: tempDir,
          platformFamily: "unix",
          platformOs: "macos",
        });
      } else if (message.method === "thread/list") {
        sendFixtureResult(ws, message.id, {
          data: [fixtureThread(threadID, "Simulator stored row after lease expiry", 100)],
          nextCursor: null,
          backwardsCursor: null,
        });
      } else if (message.method === "thread/loaded/list") {
        sendFixtureResult(ws, message.id, { data: [], nextCursor: null });
      }
    });
  });

  const relayConfig = {
    listenHost: "127.0.0.1",
    port: 0,
    phoneAuth: "none",
    hostId: hostID,
    hostName: "Simulator Live Lease Expiry Fixture",
    hostEndpoint: "127.0.0.1:0",
    historyUrl: `ws://127.0.0.1:${historyServer.address().port}`,
    historyBearerToken: "history-token",
    liveEndpoints: [{ label: "sim-live-lease-fixture", url: `ws://127.0.0.1:${liveServer.address().port}` }],
    liveStatusMaxAgeMs: startupLiveStatusMaxAgeMs,
    advertiseBonjour: false,
    observabilityDir: false,
    relayStateDatabasePath: path.join(tempDir, "relay-state.sqlite"),
    relayStateAutoStart: false,
    logger: {
      debug() {},
      info() {},
      warn() {},
      error() {},
      fault() {},
      fatalSync() {},
    },
  };
  const relay = startServer(relayConfig);
  await relay.listening;
  const relayPort = relay.server.address().port;
  const relayUrl = `ws://127.0.0.1:${relayPort}`;
  const fixtureOptions = {
    ...options,
    relayUrl,
    codexHome: tempDir,
    sqliteHome: tempDir,
    detail: "none",
  };
  const streamProbe = new DockStreamProbe(fixtureOptions);

  try {
    await streamProbe.open();
    const initialWait = await waitForStreamCondition({
      streamProbe,
      timeoutMs: options.dockCollectionTimeoutMs,
      predicate: (snapshot) => dockSnapshotCardForThread(snapshot, threadID)?.status === "running",
    });
    if (!initialWait.ok) {
      transitionFailure(
        findings,
        "scenario_live_lease_initial_live_not_seen",
        "live fixture row did not appear as running through the fixture relay stream before simulator launch",
        { threadID }
      );
    }
    const initial = await freshComparison({ streamProbe, options: fixtureOptions, routeEvents });
    findings.push(...scenarioComparisonFindings({ phase: "initial", comparison: initial.comparison }));
    const initialFinishedAt = new Date().toISOString();
    samples.push({
      sampleIndex: 0,
      startedAt: new Date(startedAtMs).toISOString(),
      finishedAt: initialFinishedAt,
      freshDock: sanitizeDockSnapshotForReport(initial.freshDock),
    });

    writeJSON(options.readyOut, {
      ready: true,
      scenario: "live-lease-expiry",
      relayUrl,
      hosts: `127.0.0.1:${relayPort}`,
      target: {
        logicalHostID: hostID,
        threadID,
        sessionID,
      },
      at: new Date().toISOString(),
    });
    await waitForFile(options.uiReadyIn, options.waitTimeoutMs, "simulator UI sampler readiness");

    relayConfig.liveStatusMaxAgeMs = controlledLiveStatusMaxAgeMs;
    await relayConfig.relayStateEngine.reconcileDock({ reason: "controlled_simulator_live_lease_refresh" });
    const refreshedWait = await waitForStreamCondition({
      streamProbe,
      timeoutMs: options.dockCollectionTimeoutMs,
      predicate: (snapshot) => dockSnapshotCardForThread(snapshot, threadID)?.status === "running",
    });
    if (!refreshedWait.ok) {
      transitionFailure(
        findings,
        "scenario_live_lease_refresh_not_seen",
        "live fixture row was not running after the simulator UI sampler connected",
        { threadID }
      );
    }
    if (liveRunningHoldMs > 0) {
      await sleep(liveRunningHoldMs);
    }

    const explained = relayConfig.relayStateEngine.store.explainThread({ hostID, threadID });
    const leaseExpiresAtMs = Number(explained?.liveLease?.expiresAtMs || 0);
    liveRowsEnabled = false;
    const expireStartedAtMs = Number.isFinite(leaseExpiresAtMs) && leaseExpiresAtMs > 0
      ? leaseExpiresAtMs
      : Date.now();
    const expiredWait = await waitForStreamCondition({
      streamProbe,
      timeoutMs: options.dockCollectionTimeoutMs,
      predicate: (snapshot) => dockSnapshotCardForThread(snapshot, threadID)?.status === "unknown",
    });
    const expiredLag = scenarioLagSummary({
      transition: "live-lease-expiry",
      startedAtMs: expireStartedAtMs,
      acknowledgedAtMs: expireStartedAtMs,
      observedAtMs: expiredWait.observedAtMs,
      maxStreamLagMs: options.maxStreamLagMs,
    });
    if (!expiredWait.ok) {
      transitionFailure(
        findings,
        "scenario_live_lease_expiry_not_seen",
        "live lease expiry did not publish the non-live status through the fixture relay stream",
        {
          threadID,
          leaseExpiresAt: Number.isFinite(leaseExpiresAtMs) && leaseExpiresAtMs > 0
            ? new Date(leaseExpiresAtMs).toISOString()
            : null,
        }
      );
    } else if (expiredLag.exceeded) {
      transitionFailure(
        findings,
        "scenario_live_lease_expiry_lag_exceeded",
        "live lease expiry reached the fixture relay stream after the client-visible lag budget",
        {
          threadID,
          observedLagMs: expiredLag.lag_change_to_relay_ms,
          maxStreamLagMs: options.maxStreamLagMs,
        }
      );
    }
    const expiredComparison = await freshComparison({ streamProbe, options: fixtureOptions, routeEvents });
    const expiredCard = dockSnapshotCardForThread(expiredComparison.freshDock, threadID);
    if (expiredCard?.status !== "unknown") {
      transitionFailure(
        findings,
        "scenario_live_lease_expiry_fresh_dock_status_mismatch",
        "fresh Dock client-path snapshot did not agree that the live lease expired",
        {
          threadID,
          status: expiredCard?.status || null,
        }
      );
    }
    findings.push(...scenarioComparisonFindings({ phase: "live-lease-expiry", comparison: expiredComparison.comparison }));
    transitions.push({
      name: "live-lease-expiry",
      kind: "live-lease-expiry",
      iteration: 1,
      route: "dock/update",
      wait: expiredWait,
      lag: expiredLag,
      freshDock: sanitizeDockSnapshotForReport(expiredComparison.freshDock),
      streamComparison: expiredComparison.comparison,
      streamComparisonAttempts: expiredComparison.attempts,
    });

    const clientPathEvidence = summarizeClientPathEvents([...streamProbe.routeEvents, ...routeEvents]);
    const scenarioOK = !findings.some((finding) => finding.severity === "error" || finding.severity === "warning");
    const report = {
      schemaVersion: 1,
      kind: "codex-dock-controlled-simulator-scenario-relay-report",
      mode: "scenario",
      scenario: "live-lease-expiry",
      startedAt: new Date(startedAtMs).toISOString(),
      endedAt: new Date().toISOString(),
      relayUrl,
      summary: {
        ok: scenarioOK,
        clientPathOK: scenarioOK,
        scenario: "live-lease-expiry",
        scenarioOK,
        scenarioCount: 1,
        scenarioTransitionCount: transitions.length,
        implementedScenarios: ["live-lease-expiry"],
        unimplementedRequiredScenarios: [],
        failures: findings.length,
        clientPathRouteCounts: clientPathEvidence.routeCounts,
      },
      samples,
      scenarios: [{
        id: "live-lease-expiry",
        ok: scenarioOK,
        actuator: {
          type: "controlled live app-server lease through real relay Dock routes",
          routes: ["dock/subscribe", "dock/update"],
          clientExercised: true,
          startupLiveStatusMaxAgeMs,
          controlledLiveStatusMaxAgeMs,
          liveRunningHoldMs,
          note: "The fixture keeps the row live until the simulator UI sampler is connected, then refreshes the real live lease with the controlled max age and waits for expiry to publish through Dock routes.",
        },
        target: {
          logicalHostID: hostID,
          threadID,
          sessionID,
          leaseExpiresAt: Number.isFinite(leaseExpiresAtMs) && leaseExpiresAtMs > 0
            ? new Date(leaseExpiresAtMs).toISOString()
            : null,
        },
        transitions,
        findings,
      }],
      stream: {
        notificationCount: streamProbe.notifications.length,
        resyncCount: streamProbe.resyncs.length,
        finalState: sanitizeDockSnapshotForReport(streamProbe.snapshot()),
      },
      clientPathEvidence,
      findings,
      unsupportedFacts: [],
    };

    writeJSON(options.jsonOut, report);
    if (options.summaryOut) {
      writeText(options.summaryOut, buildMarkdownSummary(report));
    }
    await waitForFile(options.stopIn, options.waitTimeoutMs, "simulator UI sampler completion");
    return report;
  } finally {
    await streamProbe.close().catch(() => null);
    await relay.close().catch(() => null);
    await closeWebSocketServer(liveServer).catch(() => null);
    await closeWebSocketServer(historyServer).catch(() => null);
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

async function runMultiHostIsolationScenario(options) {
  const routeEvents = [];
  const findings = [];
  const transitions = [];
  const samples = [];
  const startedAtMs = Date.now();
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "codex-dock-sim-multi-host-"));
  const sharedThreadID = "sim-shared-thread-id";
  const hostAOnlyThreadID = "sim-host-a-only";
  const hostBOnlyThreadID = "sim-host-b-only";
  const hostANewThreadID = "sim-host-a-new";
  const hostA = {
    id: "sim-multi-host-a",
    displayName: "Simulator Multi Host A",
    endpoint: "127.0.0.1:0/a",
  };
  const hostB = {
    id: "sim-multi-host-b",
    displayName: "Simulator Multi Host B",
    endpoint: "127.0.0.1:0/b",
  };
  let hostARows = [
    fixtureThread(sharedThreadID, "Simulator shared id from host A", 200),
    fixtureThread(hostAOnlyThreadID, "Simulator only host A", 100),
  ];
  let hostBRows = [
    fixtureThread(sharedThreadID, "Simulator shared id from host B", 200),
    fixtureThread(hostBOnlyThreadID, "Simulator only host B", 100),
  ];
  const fixtures = [];
  const streamProbes = [];

  try {
    const fixtureA = await createControlledMultiHostFixture({
      options,
      tempDir,
      host: hostA,
      getRows: () => hostARows,
    });
    const fixtureB = await createControlledMultiHostFixture({
      options,
      tempDir,
      host: hostB,
      getRows: () => hostBRows,
    });
    fixtures.push(fixtureA, fixtureB);
    const streamA = new DockStreamProbe(fixtureA.options);
    const streamB = new DockStreamProbe(fixtureB.options);
    streamProbes.push(streamA, streamB);

    await Promise.all([streamA.open(), streamB.open()]);
    const initialAWait = await waitForStreamCondition({
      streamProbe: streamA,
      timeoutMs: options.dockCollectionTimeoutMs,
      predicate: (snapshot) => (
        dockSnapshotHasThread(snapshot, sharedThreadID)
        && dockSnapshotHasThread(snapshot, hostAOnlyThreadID)
      ),
    });
    const initialBWait = await waitForStreamCondition({
      streamProbe: streamB,
      timeoutMs: options.dockCollectionTimeoutMs,
      predicate: (snapshot) => (
        dockSnapshotHasThread(snapshot, sharedThreadID)
        && dockSnapshotHasThread(snapshot, hostBOnlyThreadID)
      ),
    });
    if (!initialAWait.ok) {
      transitionFailure(
        findings,
        "scenario_multi_host_initial_a_missing",
        "host A initial Dock stream did not expose its expected rows"
      );
    }
    if (!initialBWait.ok) {
      transitionFailure(
        findings,
        "scenario_multi_host_initial_b_missing",
        "host B initial Dock stream did not expose its expected rows"
      );
    }
    findings.push(...multiHostIsolationFindings({
      label: "initial-host-a",
      snapshot: streamA.snapshot(),
      host: hostA,
      expectedThreadIDs: [sharedThreadID, hostAOnlyThreadID],
      forbiddenThreadIDs: [hostBOnlyThreadID],
    }));
    findings.push(...multiHostIsolationFindings({
      label: "initial-host-b",
      snapshot: streamB.snapshot(),
      host: hostB,
      expectedThreadIDs: [sharedThreadID, hostBOnlyThreadID],
      forbiddenThreadIDs: [hostAOnlyThreadID],
    }));

    const sharedA = dockSnapshotCardForThread(streamA.snapshot(), sharedThreadID);
    const sharedB = dockSnapshotCardForThread(streamB.snapshot(), sharedThreadID);
    if (cardID(sharedA) === cardID(sharedB)) {
      transitionFailure(
        findings,
        "scenario_multi_host_shared_thread_collision",
        "same thread id from two relay hosts produced the same client card id",
        {
          sharedThreadID,
          cardID: cardID(sharedA),
        }
      );
    }

    const initialA = await freshComparison({ streamProbe: streamA, options: fixtureA.options, routeEvents });
    const initialB = await freshComparison({ streamProbe: streamB, options: fixtureB.options, routeEvents });
    findings.push(...scenarioComparisonFindings({ phase: "initial-host-a", comparison: initialA.comparison }));
    findings.push(...scenarioComparisonFindings({ phase: "initial-host-b", comparison: initialB.comparison }));
    const initialFinishedAt = new Date().toISOString();
    samples.push({
      sampleIndex: 0,
      startedAt: new Date(startedAtMs).toISOString(),
      finishedAt: initialFinishedAt,
      freshDock: mergeDockSnapshotsForSimulatorReport([initialA.freshDock, initialB.freshDock]),
    });

    writeJSON(options.readyOut, {
      ready: true,
      scenario: "multi-host-isolation",
      relayUrl: fixtureA.relayUrl,
      hosts: `${fixtureA.endpoint},${fixtureB.endpoint}`,
      target: {
        hostIDs: [hostA.id, hostB.id],
        sharedThreadID,
        hostAOnlyThreadID,
        hostBOnlyThreadID,
        hostANewThreadID,
      },
      at: new Date().toISOString(),
    });
    await waitForFile(options.uiReadyIn, options.waitTimeoutMs, "simulator UI sampler readiness");
    await sleep(Math.min(Math.max(options.scenarioHoldMs, 500), 1_500));

    const updateStartedAtMs = Date.now();
    hostARows = [
      fixtureThread(hostANewThreadID, "Simulator new host A row", 300),
      fixtureThread(sharedThreadID, "Simulator shared id from host A", 200),
      fixtureThread(hostAOnlyThreadID, "Simulator only host A", 100),
    ];
    await fixtureA.relayConfig.relayStateEngine.reconcileDock({ reason: "controlled_simulator_multi_host_a_update" });
    const updateAWait = await waitForStreamCondition({
      streamProbe: streamA,
      timeoutMs: options.dockCollectionTimeoutMs,
      predicate: (snapshot) => dockSnapshotThreadIndex(snapshot, hostANewThreadID) === 0,
    });
    const updateLag = scenarioLagSummary({
      transition: "multi-host-isolation",
      startedAtMs: updateStartedAtMs,
      acknowledgedAtMs: updateStartedAtMs,
      observedAtMs: updateAWait.observedAtMs,
      maxStreamLagMs: options.maxStreamLagMs,
    });
    if (!updateAWait.ok) {
      transitionFailure(
        findings,
        "scenario_multi_host_update_not_seen",
        "host A update did not appear on host A long-lived Dock stream",
        { threadID: hostANewThreadID }
      );
    } else if (updateLag.exceeded) {
      transitionFailure(
        findings,
        "scenario_multi_host_update_lag_exceeded",
        "host A update reached its Dock stream after the client-visible lag budget",
        {
          observedLagMs: updateLag.lag_change_to_relay_ms,
          maxStreamLagMs: options.maxStreamLagMs,
        }
      );
    }

    const freshA = await collectDockClientPathSnapshot(fixtureA.options, routeEvents);
    const freshB = await collectDockClientPathSnapshot(fixtureB.options, routeEvents);
    const comparisonA = compareDockStates(streamA.snapshot(), freshA);
    const comparisonB = compareDockStates(streamB.snapshot(), freshB);
    findings.push(...scenarioComparisonFindings({ phase: "multi-host-a", comparison: comparisonA }));
    findings.push(...scenarioComparisonFindings({ phase: "multi-host-b", comparison: comparisonB }));
    findings.push(...multiHostIsolationFindings({
      label: "updated-host-a",
      snapshot: freshA,
      host: hostA,
      expectedThreadIDs: [hostANewThreadID, sharedThreadID, hostAOnlyThreadID],
      forbiddenThreadIDs: [hostBOnlyThreadID],
    }));
    findings.push(...multiHostIsolationFindings({
      label: "unchanged-host-b",
      snapshot: freshB,
      host: hostB,
      expectedThreadIDs: [sharedThreadID, hostBOnlyThreadID],
      forbiddenThreadIDs: [hostAOnlyThreadID, hostANewThreadID],
    }));
    if (dockSnapshotHasThread(freshB, hostANewThreadID)) {
      transitionFailure(
        findings,
        "scenario_multi_host_update_leaked",
        "host A update leaked into host B fresh Dock client-path snapshot",
        { threadID: hostANewThreadID }
      );
    }
    const compositeFreshDock = mergeDockSnapshotsForSimulatorReport([freshA, freshB]);
    transitions.push({
      name: "multi-host-isolation",
      kind: "multi-host-isolation",
      iteration: 1,
      route: "dock/update",
      wait: updateAWait,
      lag: updateLag,
      freshDock: compositeFreshDock,
      freshDockA: sanitizeDockSnapshotForReport(freshA),
      freshDockB: sanitizeDockSnapshotForReport(freshB),
      streamComparisonA: comparisonA,
      streamComparisonB: comparisonB,
    });

    const clientPathEvidence = summarizeClientPathEvents([
      ...streamA.routeEvents,
      ...streamB.routeEvents,
      ...routeEvents,
    ]);
    const scenarioOK = !findings.some((finding) => finding.severity === "error" || finding.severity === "warning");
    const report = {
      schemaVersion: 1,
      kind: "codex-dock-controlled-simulator-scenario-relay-report",
      mode: "scenario",
      scenario: "multi-host-isolation",
      startedAt: new Date(startedAtMs).toISOString(),
      endedAt: new Date().toISOString(),
      relayUrl: fixtureA.relayUrl,
      summary: {
        ok: scenarioOK,
        clientPathOK: scenarioOK,
        scenario: "multi-host-isolation",
        scenarioOK,
        scenarioCount: 1,
        scenarioTransitionCount: transitions.length,
        implementedScenarios: ["multi-host-isolation"],
        unimplementedRequiredScenarios: [],
        failures: findings.length,
        clientPathRouteCounts: clientPathEvidence.routeCounts,
      },
      samples,
      scenarios: [{
        id: "multi-host-isolation",
        ok: scenarioOK,
        actuator: {
          type: "two controlled app-server fixtures through two real relay Dock routes",
          routes: ["dock/subscribe", "dock/update"],
          clientExercised: true,
          note: "Both fixtures expose the same thread id under different relay host ids; the simulator app is configured with both temporary relay endpoints and must render host-scoped rows without leaking host A changes into host B.",
        },
        target: {
          hostIDs: [hostA.id, hostB.id],
          sharedThreadID,
          hostAOnlyThreadID,
          hostBOnlyThreadID,
          hostANewThreadID,
        },
        transitions,
        findings,
      }],
      stream: {
        hostA: {
          notificationCount: streamA.notifications.length,
          resyncCount: streamA.resyncs.length,
          finalState: sanitizeDockSnapshotForReport(streamA.snapshot()),
        },
        hostB: {
          notificationCount: streamB.notifications.length,
          resyncCount: streamB.resyncs.length,
          finalState: sanitizeDockSnapshotForReport(streamB.snapshot()),
        },
      },
      clientPathEvidence,
      findings,
      unsupportedFacts: [],
    };

    writeJSON(options.jsonOut, report);
    if (options.summaryOut) {
      writeText(options.summaryOut, buildMarkdownSummary(report));
    }
    await waitForFile(options.stopIn, options.waitTimeoutMs, "simulator UI sampler completion");
    return report;
  } finally {
    await Promise.all(streamProbes.map((probe) => probe.close().catch(() => null)));
    for (const fixture of fixtures) {
      await fixture.relay.close().catch(() => null);
      await closeWebSocketServer(fixture.historyServer).catch(() => null);
    }
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

async function runResyncGapScenario(options) {
  const routeEvents = [];
  const findings = [];
  const transitions = [];
  const samples = [];
  const startedAtMs = Date.now();
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "codex-dock-sim-resync-gap-"));
  const hostID = "sim-resync-gap-fixture";
  const stableThreadID = "sim-resync-gap-stable";
  const resyncThreadID = "sim-resync-gap-recovered";
  let sourceRows = [
    fixtureThread(stableThreadID, "Simulator resync stable row", 100),
  ];

  const historyServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await new Promise((resolve) => historyServer.once("listening", resolve));
  historyServer.on("connection", (ws) => {
    ws.on("message", (data) => {
      const message = JSON.parse(data.toString());
      if (message.method === "initialize") {
        sendFixtureResult(ws, message.id, {
          userAgent: "codex-sim-resync-gap-fixture",
          codexHome: tempDir,
          platformFamily: "unix",
          platformOs: "macos",
        });
      } else if (message.method === "thread/list") {
        sendFixtureResult(ws, message.id, {
          data: sourceRows,
          nextCursor: null,
          backwardsCursor: null,
        });
      } else if (message.method === "thread/loaded/list") {
        sendFixtureResult(ws, message.id, { data: [], nextCursor: null });
      } else if (message.method === "thread/read" || message.method === "thread/resume") {
        const threadID = message.params?.threadId || message.params?.threadID;
        const thread = sourceRows.find((row) => row.id === threadID);
        if (!thread) {
          sendFixtureError(ws, message.id, `unknown thread: ${threadID || "missing"}`);
          return;
        }
        sendFixtureResult(ws, message.id, {
          thread: {
            ...thread,
            turns: [],
          },
        });
      } else if (message.method === "thread/turns/list") {
        sendFixtureResult(ws, message.id, {
          data: [],
          nextCursor: null,
          backwardsCursor: null,
        });
      }
    });
  });

  const relayConfig = {
    listenHost: "127.0.0.1",
    port: 0,
    phoneAuth: "none",
    hostId: hostID,
    hostName: "Simulator Resync Gap Fixture",
    hostEndpoint: "127.0.0.1:0",
    historyUrl: `ws://127.0.0.1:${historyServer.address().port}`,
    historyBearerToken: "history-token",
    advertiseBonjour: false,
    observabilityDir: false,
    relayStateDatabasePath: path.join(tempDir, "relay-state.sqlite"),
    relayStateAutoStart: false,
    logger: {
      debug() {},
      info() {},
      warn() {},
      error() {},
      fault() {},
      fatalSync() {},
    },
  };
  const relay = startServer(relayConfig);
  await relay.listening;
  const relayPort = relay.server.address().port;
  const relayUrl = `ws://127.0.0.1:${relayPort}`;
  const fixtureOptions = {
    ...options,
    relayUrl,
    codexHome: tempDir,
    sqliteHome: tempDir,
    detail: "none",
  };
  const streamProbe = new DockStreamProbe(fixtureOptions);

  try {
    await streamProbe.open();
    const initialWait = await waitForStreamCondition({
      streamProbe,
      timeoutMs: options.dockCollectionTimeoutMs,
      predicate: (snapshot) => (
        dockSnapshotThreadIndex(snapshot, stableThreadID) === 0
        && !dockSnapshotHasThread(snapshot, resyncThreadID)
      ),
    });
    if (!initialWait.ok) {
      transitionFailure(
        findings,
        "scenario_resync_gap_initial_row_missing",
        "resync-gap fixture did not start with the stable row visible through the fixture relay stream",
        { stableThreadID, resyncThreadID }
      );
    }
    const initial = await freshComparison({ streamProbe, options: fixtureOptions, routeEvents });
    findings.push(...scenarioComparisonFindings({ phase: "initial", comparison: initial.comparison }));
    const initialFinishedAt = new Date().toISOString();
    samples.push({
      sampleIndex: 0,
      startedAt: new Date(startedAtMs).toISOString(),
      finishedAt: initialFinishedAt,
      freshDock: sanitizeDockSnapshotForReport(initial.freshDock),
    });

    writeJSON(options.readyOut, {
      ready: true,
      scenario: "resync-gap",
      relayUrl,
      hosts: `127.0.0.1:${relayPort}`,
      target: {
        logicalHostID: hostID,
        stableThreadID,
        resyncThreadID,
      },
      at: new Date().toISOString(),
    });
    await waitForFile(options.uiReadyIn, options.waitTimeoutMs, "simulator UI sampler readiness");
    await sleep(Math.min(Math.max(options.scenarioHoldMs, 500), 1_500));

    sourceRows = [
      fixtureThread(resyncThreadID, "Simulator row recovered by resync", 300),
      fixtureThread(stableThreadID, "Simulator resync stable row", 100),
    ];
    // Advance relay state without the normal delta so subscribers must recover through dock/resync.
    const subscribers = relayConfig.relayStateEngine.subscriptions.subscribers;
    const savedSubscribers = [...subscribers];
    subscribers.clear();
    try {
      await relayConfig.relayStateEngine.reconcileDock({ reason: "controlled_simulator_resync_gap_hidden_state" });
    } finally {
      subscribers.clear();
      for (const subscriber of savedSubscribers) {
        subscribers.add(subscriber);
      }
    }

    const afterSnapshot = await relayConfig.relayStateEngine.subscriptions.snapshot("dock");
    const gapDelta = relayConfig.relayStateEngine.subscriptions.cardDelta({
      view: "dock",
      baseSeq: Number(afterSnapshot.seq || 0) + 10,
      seq: Number(afterSnapshot.seq || 0),
      freshness: afterSnapshot.freshness,
      upsertHosts: afterSnapshot.hosts || [],
      upsertCards: afterSnapshot.cards || [],
      deleteCardIDs: [],
      totalRows: Number(afterSnapshot.totalRows || afterSnapshot.cardCount || 0),
      complete: true,
      window: afterSnapshot.window || undefined,
    });
    const gapPublishedAtMs = Date.now();
    await relayConfig.relayStateEngine.subscriptions.publishDelta(gapDelta);

    const gapDetected = await waitForAsyncEvent((async () => {
      while (!streamProbe.state.needsResync) {
        await streamProbe.waitForUpdate(500);
      }
      return sanitizeDockSnapshotForReport(streamProbe.snapshot());
    })(), options.dockCollectionTimeoutMs);
    if (!gapDetected.ok) {
      transitionFailure(
        findings,
        "scenario_resync_gap_not_detected",
        "long-lived Dock stream did not detect the injected sequence gap",
        { timeoutMs: options.dockCollectionTimeoutMs }
      );
    }

    let resyncResponse = null;
    let resyncAcknowledgedAtMs = null;
    if (gapDetected.ok) {
      try {
        resyncResponse = await streamProbe.resync("controlled_simulator_sequence_gap");
        resyncAcknowledgedAtMs = Date.now();
      } catch (error) {
        resyncAcknowledgedAtMs = Date.now();
        transitionFailure(
          findings,
          "scenario_resync_gap_request_failed",
          "dock/resync failed after the controlled simulator fixture injected a sequence gap",
          { error: error?.message || String(error) }
        );
      }
    }
    if (streamProbe.state.needsResync) {
      transitionFailure(
        findings,
        "scenario_resync_gap_still_needs_resync",
        "long-lived Dock stream still required resync after dock/resync completed"
      );
    }

    const resyncedWait = await waitForStreamCondition({
      streamProbe,
      timeoutMs: options.dockCollectionTimeoutMs,
      predicate: (snapshot) => (
        dockSnapshotThreadIndex(snapshot, resyncThreadID) === 0
        && dockSnapshotHasThread(snapshot, stableThreadID)
      ),
    });
    const resyncLag = scenarioLagSummary({
      transition: "resync-gap",
      startedAtMs: gapPublishedAtMs,
      acknowledgedAtMs: resyncAcknowledgedAtMs || gapPublishedAtMs,
      observedAtMs: resyncedWait.observedAtMs,
      maxStreamLagMs: options.maxStreamLagMs,
    });
    if (!resyncedWait.ok) {
      transitionFailure(
        findings,
        "scenario_resync_gap_recovered_row_not_seen",
        "resync-gap fixture did not recover the new row through dock/resync",
        { resyncThreadID }
      );
    } else if (resyncLag.exceeded) {
      transitionFailure(
        findings,
        "scenario_resync_gap_lag_exceeded",
        "dock/resync recovery reached the fixture relay stream after the client-visible lag budget",
        {
          observedLagMs: resyncLag.lag_change_to_relay_ms,
          maxStreamLagMs: options.maxStreamLagMs,
        }
      );
    }

    const resyncComparison = await freshComparison({ streamProbe, options: fixtureOptions, routeEvents });
    findings.push(...scenarioComparisonFindings({ phase: "resync-gap", comparison: resyncComparison.comparison }));
    findings.push(...requiredRouteFindings(
      summarizeClientPathEvents([...streamProbe.routeEvents, ...routeEvents]),
      ["dock/resync"]
    ));
    transitions.push({
      name: "resync-gap",
      kind: "resync-gap",
      iteration: 1,
      route: "dock/resync",
      response: normalizeForComparison(resyncResponse || null),
      wait: resyncedWait,
      lag: resyncLag,
      injectedGap: normalizeForComparison({
        baseSeq: gapDelta.baseSeq,
        seq: gapDelta.seq,
        publishedAt: new Date(gapPublishedAtMs).toISOString(),
      }),
      freshDock: sanitizeDockSnapshotForReport(resyncComparison.freshDock),
      streamComparison: resyncComparison.comparison,
      streamComparisonAttempts: resyncComparison.attempts,
    });

    const clientPathEvidence = summarizeClientPathEvents([...streamProbe.routeEvents, ...routeEvents]);
    const scenarioOK = !findings.some((finding) => finding.severity === "error" || finding.severity === "warning");
    const report = {
      schemaVersion: 1,
      kind: "codex-dock-controlled-simulator-scenario-relay-report",
      mode: "scenario",
      scenario: "resync-gap",
      startedAt: new Date(startedAtMs).toISOString(),
      endedAt: new Date().toISOString(),
      relayUrl,
      summary: {
        ok: scenarioOK,
        clientPathOK: scenarioOK,
        scenario: "resync-gap",
        scenarioOK,
        scenarioCount: 1,
        scenarioTransitionCount: transitions.length,
        implementedScenarios: ["resync-gap"],
        unimplementedRequiredScenarios: [],
        failures: findings.length,
        clientPathRouteCounts: clientPathEvidence.routeCounts,
      },
      samples,
      scenarios: [{
        id: "resync-gap",
        ok: scenarioOK,
        actuator: {
          type: "controlled sequence-gap Dock stream through real relay resync route",
          routes: ["dock/subscribe", "dock/update", "dock/resync"],
          clientExercised: true,
          note: "The fixture updates relay state without publishing the normal delta, then publishes a malformed Dock delta so the actual client must reject it and recover through dock/resync before the new row can display.",
        },
        target: {
          logicalHostID: hostID,
          stableThreadID,
          resyncThreadID,
        },
        transitions,
        findings,
      }],
      stream: {
        notificationCount: streamProbe.notifications.length,
        resyncCount: streamProbe.resyncs.length,
        finalState: sanitizeDockSnapshotForReport(streamProbe.snapshot()),
      },
      clientPathEvidence,
      findings,
      unsupportedFacts: [],
    };

    writeJSON(options.jsonOut, report);
    if (options.summaryOut) {
      writeText(options.summaryOut, buildMarkdownSummary(report));
    }
    await waitForFile(options.stopIn, options.waitTimeoutMs, "simulator UI sampler completion");
    return report;
  } finally {
    await streamProbe.close().catch(() => null);
    await relay.close().catch(() => null);
    await closeWebSocketServer(historyServer).catch(() => null);
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

async function runSpawnEdgeScenario(options) {
  const routeEvents = [];
  const findings = [];
  const transitions = [];
  const samples = [];
  const startedAtMs = Date.now();
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "codex-dock-sim-spawn-edge-"));
  const hostID = "sim-spawn-edge-fixture";
  const parentThreadID = "sim-spawn-edge-parent";
  const childThreadID = "sim-spawn-edge-child";
  const parentRow = fixtureThread(parentThreadID, "Simulator spawn parent row", 100);
  const childRow = {
    id: childThreadID,
    sessionId: "sim-spawn-edge-child-session",
    preview: "Simulator spawned child row",
    updatedAt: 300,
    source: {
      subAgent: {
        thread_spawn: {
          parent_thread_id: parentThreadID,
          child_thread_id: childThreadID,
          status: "created",
        },
      },
    },
    threadSource: "subagent",
    forkedFromId: parentThreadID,
    status: { type: "notLoaded" },
  };
  let sourceRows = [parentRow];

  const historyServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await new Promise((resolve) => historyServer.once("listening", resolve));
  historyServer.on("connection", (ws) => {
    ws.on("message", (data) => {
      const message = JSON.parse(data.toString());
      if (message.method === "initialize") {
        sendFixtureResult(ws, message.id, {
          userAgent: "codex-sim-spawn-edge-fixture",
          codexHome: tempDir,
          platformFamily: "unix",
          platformOs: "macos",
        });
      } else if (message.method === "thread/list") {
        const sourceKinds = message.params?.sourceKinds;
        const rows = sourceRows.filter((row) => threadMatchesSourceKinds(row, sourceKinds));
        sendFixtureResult(ws, message.id, {
          data: rows,
          nextCursor: null,
          backwardsCursor: null,
        });
      } else if (message.method === "thread/loaded/list") {
        sendFixtureResult(ws, message.id, { data: [], nextCursor: null });
      } else if (message.method === "thread/read" || message.method === "thread/resume") {
        const threadID = message.params?.threadId || message.params?.threadID;
        const thread = sourceRows.find((row) => row.id === threadID);
        if (!thread) {
          sendFixtureError(ws, message.id, `unknown thread: ${threadID || "missing"}`);
          return;
        }
        sendFixtureResult(ws, message.id, {
          thread: {
            ...thread,
            turns: [],
          },
        });
      } else if (message.method === "thread/turns/list") {
        sendFixtureResult(ws, message.id, {
          data: [],
          nextCursor: null,
          backwardsCursor: null,
        });
      }
    });
  });

  const relayConfig = {
    listenHost: "127.0.0.1",
    port: 0,
    phoneAuth: "none",
    hostId: hostID,
    hostName: "Simulator Spawn Edge Fixture",
    hostEndpoint: "127.0.0.1:0",
    historyUrl: `ws://127.0.0.1:${historyServer.address().port}`,
    historyBearerToken: "history-token",
    advertiseBonjour: false,
    observabilityDir: false,
    relayStateDatabasePath: path.join(tempDir, "relay-state.sqlite"),
    relayStateAutoStart: false,
    logger: {
      debug() {},
      info() {},
      warn() {},
      error() {},
      fault() {},
      fatalSync() {},
    },
  };
  const relay = startServer(relayConfig);
  await relay.listening;
  const relayPort = relay.server.address().port;
  const relayUrl = `ws://127.0.0.1:${relayPort}`;
  const fixtureOptions = {
    ...options,
    relayUrl,
    codexHome: tempDir,
    sqliteHome: tempDir,
    detail: "none",
  };
  const streamProbe = new DockStreamProbe(fixtureOptions);

  try {
    await streamProbe.open();
    const initialWait = await waitForStreamCondition({
      streamProbe,
      timeoutMs: options.dockCollectionTimeoutMs,
      predicate: (snapshot) => (
        dockSnapshotThreadIndex(snapshot, parentThreadID) === 0
        && !dockSnapshotHasThread(snapshot, childThreadID)
      ),
    });
    if (!initialWait.ok) {
      transitionFailure(
        findings,
        "scenario_spawn_edge_initial_state_wrong",
        "spawn-edge fixture did not start with only the parent row visible through the fixture relay stream",
        { parentThreadID, childThreadID }
      );
    }
    const initial = await freshComparison({ streamProbe, options: fixtureOptions, routeEvents });
    findings.push(...scenarioComparisonFindings({ phase: "initial", comparison: initial.comparison }));
    const initialFinishedAt = new Date().toISOString();
    samples.push({
      sampleIndex: 0,
      startedAt: new Date(startedAtMs).toISOString(),
      finishedAt: initialFinishedAt,
      freshDock: sanitizeDockSnapshotForReport(initial.freshDock),
    });

    writeJSON(options.readyOut, {
      ready: true,
      scenario: "spawn-edge",
      relayUrl,
      hosts: `127.0.0.1:${relayPort}`,
      target: {
        logicalHostID: hostID,
        parentThreadID,
        childThreadID,
      },
      at: new Date().toISOString(),
    });
    await waitForFile(options.uiReadyIn, options.waitTimeoutMs, "simulator UI sampler readiness");
    await sleep(Math.min(Math.max(options.scenarioHoldMs, 500), 1_500));

    const spawnStartedAtMs = Date.now();
    sourceRows = [childRow, parentRow];
    await relayConfig.relayStateEngine.reconcileDock({ reason: "controlled_simulator_spawn_edge_child_added" });
    const spawnWait = await waitForStreamCondition({
      streamProbe,
      timeoutMs: options.dockCollectionTimeoutMs,
      predicate: (snapshot) => {
        const card = dockSnapshotCardForThread(snapshot, childThreadID);
        return dockSnapshotThreadIndex(snapshot, childThreadID) === 0
          && dockSnapshotHasThread(snapshot, parentThreadID)
          && card?.lane === "agent"
          && card?.sourceKind === "automation";
      },
    });
    const spawnLag = scenarioLagSummary({
      transition: "spawn-edge",
      startedAtMs: spawnStartedAtMs,
      acknowledgedAtMs: spawnStartedAtMs,
      observedAtMs: spawnWait.observedAtMs,
      maxStreamLagMs: options.maxStreamLagMs,
    });
    if (!spawnWait.ok) {
      transitionFailure(
        findings,
        "scenario_spawn_edge_not_seen",
        "spawned child row did not appear as an automation Dock card through the fixture relay stream",
        { parentThreadID, childThreadID }
      );
    } else if (spawnLag.exceeded) {
      transitionFailure(
        findings,
        "scenario_spawn_edge_lag_exceeded",
        "spawned child row appeared after the relay lag budget",
        {
          observedLagMs: spawnLag.lag_change_to_relay_ms,
          maxStreamLagMs: options.maxStreamLagMs,
        }
      );
    }

    const spawnComparison = await freshComparison({ streamProbe, options: fixtureOptions, routeEvents });
    findings.push(...scenarioComparisonFindings({ phase: "spawn-edge", comparison: spawnComparison.comparison }));
    const freshChildCard = dockSnapshotCardForThread(spawnComparison.freshDock, childThreadID);
    if (!freshChildCard) {
      transitionFailure(
        findings,
        "scenario_spawn_edge_fresh_child_missing",
        "spawned child row was missing from a fresh Dock client-path subscription",
        { childThreadID }
      );
    } else {
      if (freshChildCard.lane !== "agent") {
        transitionFailure(
          findings,
          "scenario_spawn_edge_wrong_lane",
          "spawned child row did not reach the client path as an agent-lane card",
          {
            childThreadID,
            actualLane: freshChildCard.lane || null,
          }
        );
      }
      if (freshChildCard.sourceKind !== "automation") {
        transitionFailure(
          findings,
          "scenario_spawn_edge_wrong_source_kind",
          "spawned child row did not reach the client path as automation source kind",
          {
            childThreadID,
            actualSourceKind: freshChildCard.sourceKind || null,
          }
        );
      }
    }
    transitions.push({
      name: "spawn-edge",
      kind: "spawn-edge",
      iteration: 1,
      route: "dock/update",
      wait: spawnWait,
      lag: spawnLag,
      freshDock: sanitizeDockSnapshotForReport(spawnComparison.freshDock),
      streamComparison: spawnComparison.comparison,
      streamComparisonAttempts: spawnComparison.attempts,
    });

    const clientPathEvidence = summarizeClientPathEvents([...streamProbe.routeEvents, ...routeEvents]);
    const scenarioOK = !findings.some((finding) => finding.severity === "error" || finding.severity === "warning");
    const report = {
      schemaVersion: 1,
      kind: "codex-dock-controlled-simulator-scenario-relay-report",
      mode: "scenario",
      scenario: "spawn-edge",
      startedAt: new Date(startedAtMs).toISOString(),
      endedAt: new Date().toISOString(),
      relayUrl,
      summary: {
        ok: scenarioOK,
        clientPathOK: scenarioOK,
        scenario: "spawn-edge",
        scenarioOK,
        scenarioCount: 1,
        scenarioTransitionCount: transitions.length,
        implementedScenarios: ["spawn-edge"],
        unimplementedRequiredScenarios: [],
        failures: findings.length,
        clientPathRouteCounts: clientPathEvidence.routeCounts,
      },
      samples,
      scenarios: [{
        id: "spawn-edge",
        ok: scenarioOK,
        actuator: {
          type: "controlled app-server subagent spawn fixture through real relay Dock routes",
          routes: ["dock/subscribe", "dock/update"],
          clientExercised: true,
          note: "The fixture changes app-server thread/list rows to model a new subagent spawn; proof only counts delivery through the same Dock routes and literal simulator row accessibility values the client uses.",
        },
        target: {
          logicalHostID: hostID,
          parentThreadID,
          childThreadID,
        },
        transitions,
        findings,
      }],
      stream: {
        notificationCount: streamProbe.notifications.length,
        resyncCount: streamProbe.resyncs.length,
        finalState: sanitizeDockSnapshotForReport(streamProbe.snapshot()),
      },
      clientPathEvidence,
      findings,
      unsupportedFacts: [],
    };

    writeJSON(options.jsonOut, report);
    if (options.summaryOut) {
      writeText(options.summaryOut, buildMarkdownSummary(report));
    }
    await waitForFile(options.stopIn, options.waitTimeoutMs, "simulator UI sampler completion");
    return report;
  } finally {
    await streamProbe.close().catch(() => null);
    await relay.close().catch(() => null);
    await closeWebSocketServer(historyServer).catch(() => null);
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

async function runDetailHistoryRequestScenario(options) {
  const routeEvents = [];
  const findings = [];
  const transitions = [];
  const samples = [];
  const startedAtMs = Date.now();
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "codex-dock-sim-detail-history-"));
  const hostID = "sim-detail-history-fixture";
  const threadID = "sim-detail-history-request-thread";
  const requestID = "approval-history-1";
  const requestCardID = `request-${requestID}`;
  const historicalTurns = [
    fixtureTurn("turn-history-1", 1_700_000_001, [
      fixtureUserMessageItem("user-seed", "Simulator detail history user seed"),
      fixtureAgentMessageItem("agent-seed", "Simulator detail history agent seed"),
      fixtureCommandExecutionItem("cmd-seed", ["make", "test"], "fixture command output"),
    ]),
    fixtureTurn("turn-history-2", 1_700_000_002, [
      fixturePlanItem("plan-seed", "Fixture plan row"),
      fixtureReasoningItem("reason-seed", "Fixture reasoning row"),
      fixtureAgentMessageItem("agent-two", "Simulator detail second agent seed"),
    ]),
  ];
  const expectedHistoricalEventIDs = [
    "turn-history-1-user-seed-user",
    "turn-history-1-agent-seed-agent",
    "turn-history-1-cmd-seed-command",
    "turn-history-1-cmd-seed-output",
    "turn-history-2-plan-seed-plan",
    "turn-history-2-reason-seed-reasoning",
    "turn-history-2-agent-two-agent",
  ];
  const liveEventID = "turn-live-agent-live-item%2FagentMessage%2Fdelta";
  const liveRawEventID = "turn-live-agent-live-item/agentMessage/delta";
  const requestEventID = requestCardID;
  let detailWs = null;
  let detailLoadedAtMs = null;
  let liveUpdateSentAtMs = null;
  let upstreamRequestSentAtMs = null;
  let upstreamResponseReceivedAtMs = null;
  let resolutionSentAtMs = null;
  let forwardedResponse = null;
  let turnsListCallCount = 0;
  let resolveDetailLoaded;
  let resolveLiveUpdateSent;
  let resolveRequestSent;
  let resolveForwardedResponse;
  let resolveResolutionSent;
  const detailLoadedPromise = new Promise((resolve) => {
    resolveDetailLoaded = resolve;
  });
  const liveUpdateSentPromise = new Promise((resolve) => {
    resolveLiveUpdateSent = resolve;
  });
  const requestSentPromise = new Promise((resolve) => {
    resolveRequestSent = resolve;
  });
  const forwardedResponsePromise = new Promise((resolve) => {
    resolveForwardedResponse = resolve;
  });
  const resolutionSentPromise = new Promise((resolve) => {
    resolveResolutionSent = resolve;
  });

  const historyServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await new Promise((resolve) => historyServer.once("listening", resolve));
  historyServer.on("connection", (ws) => {
    ws.on("message", (data) => {
      const message = JSON.parse(data.toString());
      if (message.method === "initialize") {
        recordClientRoute(routeEvents, "initialize", "simulator app initialized detail-history fixture", { threadID });
        sendFixtureResult(ws, message.id, {
          userAgent: "codex-sim-detail-history-fixture",
          codexHome: tempDir,
          platformFamily: "unix",
          platformOs: "macos",
        });
      } else if (message.method === "initialized") {
        recordClientRoute(routeEvents, "initialized", "simulator app sent initialized notification", { threadID });
      } else if (message.method === "thread/list") {
        sendFixtureResult(ws, message.id, {
          data: [fixtureThread(threadID, "Simulator full detail fixture row", 100)],
          nextCursor: null,
          backwardsCursor: null,
        });
      } else if (message.method === "thread/loaded/list") {
        sendFixtureResult(ws, message.id, { data: [], nextCursor: null });
      } else if (message.method === "thread/read") {
        recordClientRoute(routeEvents, "thread/read", "simulator app read target thread detail", {
          threadID: message.params?.threadId || threadID,
          includeTurns: message.params?.includeTurns ?? null,
        });
        sendFixtureResult(ws, message.id, {
          thread: {
            id: message.params?.threadId || threadID,
            turns: [],
          },
        });
      } else if (message.method === "thread/turns/list") {
        turnsListCallCount += 1;
        const cursor = message.params?.cursor || null;
        recordClientRoute(routeEvents, "thread/turns/list", "simulator app drained paged historical thread turns", {
          threadID: message.params?.threadId || threadID,
          cursor,
          call: turnsListCallCount,
        });
        if (!cursor) {
          sendFixtureResult(ws, message.id, {
            data: [historicalTurns[0]],
            nextCursor: "page-2",
            backwardsCursor: null,
          });
        } else if (cursor === "page-2") {
          sendFixtureResult(ws, message.id, {
            data: [historicalTurns[1]],
            nextCursor: null,
            backwardsCursor: null,
          });
        } else {
          sendFixtureResult(ws, message.id, {
            data: [],
            nextCursor: null,
            backwardsCursor: null,
          });
        }
      } else if (message.method === "thread/resume") {
        detailWs = ws;
        detailLoadedAtMs = Date.now();
        recordClientRoute(routeEvents, "thread/resume", "simulator app resumed target thread live detail", {
          threadID: message.params?.threadId || threadID,
          excludeTurns: message.params?.excludeTurns ?? null,
        });
        sendFixtureResult(ws, message.id, {
          thread: {
            id: message.params?.threadId || threadID,
            turns: [],
          },
        });
        resolveDetailLoaded({
          observedAtMs: detailLoadedAtMs,
          turnsListCallCount,
        });
      } else if (!message.method && String(message.id) === requestID) {
        upstreamResponseReceivedAtMs = Date.now();
        forwardedResponse = normalizeForComparison({
          id: message.id,
          result: message.result || null,
        });
        resolveForwardedResponse({
          receivedAtMs: upstreamResponseReceivedAtMs,
          message: forwardedResponse,
        });
        setTimeout(() => {
          resolutionSentAtMs = Date.now();
          const notification = {
            jsonrpc: "2.0",
            method: "serverRequest/resolved",
            params: {
              threadId: threadID,
              requestId: requestID,
            },
          };
          ws.send(JSON.stringify(notification));
          resolveResolutionSent({
            sentAtMs: resolutionSentAtMs,
            message: normalizeForComparison(notification),
          });
        }, 10);
      }
    });
  });

  const relayConfig = {
    listenHost: "127.0.0.1",
    port: 0,
    phoneAuth: "none",
    hostId: hostID,
    hostName: "Simulator Detail History Fixture",
    hostEndpoint: "127.0.0.1:0",
    historyUrl: `ws://127.0.0.1:${historyServer.address().port}`,
    historyBearerToken: "history-token",
    advertiseBonjour: false,
    observabilityDir: false,
    relayStateDatabasePath: path.join(tempDir, "relay-state.sqlite"),
    relayStateAutoStart: false,
    logger: {
      debug() {},
      info() {},
      warn() {},
      error() {},
      fault() {},
      fatalSync() {},
    },
  };
  const relay = startServer(relayConfig);
  await relay.listening;
  const relayPort = relay.server.address().port;
  const relayUrl = `ws://127.0.0.1:${relayPort}`;
  const fixtureOptions = {
    ...options,
    relayUrl,
    codexHome: tempDir,
    sqliteHome: tempDir,
    detail: "none",
  };
  const streamProbe = new DockStreamProbe(fixtureOptions);

  try {
    await streamProbe.open();
    const initialWait = await waitForStreamCondition({
      streamProbe,
      timeoutMs: options.dockCollectionTimeoutMs,
      predicate: (snapshot) => dockSnapshotThreadIndex(snapshot, threadID) === 0,
    });
    if (!initialWait.ok) {
      transitionFailure(
        findings,
        "scenario_detail_history_initial_row_missing",
        "detail-history fixture row did not appear in the fixture relay stream before simulator launch",
        { threadID }
      );
    }
    const initial = await freshComparison({ streamProbe, options: fixtureOptions, routeEvents });
    findings.push(...scenarioComparisonFindings({ phase: "detail-history-initial", comparison: initial.comparison }));
    samples.push({
      sampleIndex: 0,
      startedAt: new Date(startedAtMs).toISOString(),
      finishedAt: new Date().toISOString(),
      freshDock: sanitizeDockSnapshotForReport(initial.freshDock),
    });

    writeJSON(options.readyOut, {
      ready: true,
      scenario: "detail-history-request",
      relayUrl,
      hosts: `127.0.0.1:${relayPort}`,
      target: {
        logicalHostID: hostID,
        threadID,
        requestID,
        requestCardID,
      },
      uiConfig: {
        openHostID: hostID,
        openThreadID: threadID,
        requestCardID,
        requestAction: "approve",
        detailFilter: "all",
        detailCheckpointSweep: true,
      },
      at: new Date().toISOString(),
    });
    await waitForFile(options.uiReadyIn, options.waitTimeoutMs, "simulator UI full detail sampler readiness");

    const detailWaitTimeoutMs = Math.min(options.dockCollectionTimeoutMs, options.waitTimeoutMs);
    const detailLoadedWait = await waitForAsyncEvent(detailLoadedPromise, detailWaitTimeoutMs);
    if (!detailLoadedWait.ok) {
      transitionFailure(
        findings,
        "scenario_detail_history_not_opened",
        "simulator app did not open and resume the controlled detail session",
        { threadID, timeoutMs: detailWaitTimeoutMs }
      );
    }
    if (turnsListCallCount < 2) {
      transitionFailure(
        findings,
        "scenario_detail_history_turn_pagination_missing",
        "simulator app did not exercise the paged thread/turns/list detail path",
        { threadID, turnsListCallCount }
      );
    }

    if (detailWs) {
      await sleep(Math.min(options.scenarioHoldMs, 1_000));
      liveUpdateSentAtMs = Date.now();
      const liveNotification = {
        jsonrpc: "2.0",
        method: "item/agentMessage/delta",
        params: {
          threadId: threadID,
          turnId: "turn-live",
          itemId: "agent-live",
          delta: "Simulator live detail delta",
        },
      };
      detailWs.send(JSON.stringify(liveNotification));
      resolveLiveUpdateSent({
        sentAtMs: liveUpdateSentAtMs,
        message: normalizeForComparison(liveNotification),
      });

      await sleep(options.scenarioHoldMs);
      upstreamRequestSentAtMs = Date.now();
      const requestMessage = {
        jsonrpc: "2.0",
        id: requestID,
        method: "item/commandExecution/requestApproval",
        params: {
          threadId: threadID,
          turnId: "turn-live-request",
          itemId: "cmd-history-live",
          command: ["make", "detail-proof"],
          cwd: tempDir,
        },
      };
      detailWs.send(JSON.stringify(requestMessage));
      resolveRequestSent({
        sentAtMs: upstreamRequestSentAtMs,
        message: {
          id: requestID,
          method: requestMessage.method,
          threadID,
          requestCardID,
        },
      });
    }

    const liveWait = await waitForAsyncEvent(liveUpdateSentPromise, detailWaitTimeoutMs);
    const requestWait = await waitForAsyncEvent(requestSentPromise, detailWaitTimeoutMs);
    const responseWait = await waitForAsyncEvent(forwardedResponsePromise, detailWaitTimeoutMs);
    const resolutionWait = await waitForAsyncEvent(resolutionSentPromise, detailWaitTimeoutMs);
    const liveLag = scenarioLagSummary({
      transition: "detail-history-live-update",
      startedAtMs: liveUpdateSentAtMs || detailLoadedAtMs || startedAtMs,
      acknowledgedAtMs: liveUpdateSentAtMs || detailLoadedAtMs || startedAtMs,
      observedAtMs: liveUpdateSentAtMs,
      maxStreamLagMs: options.maxStreamLagMs,
    });
    const requestLag = scenarioLagSummary({
      transition: "detail-history-request-visible",
      startedAtMs: upstreamRequestSentAtMs || liveUpdateSentAtMs || startedAtMs,
      acknowledgedAtMs: upstreamRequestSentAtMs || liveUpdateSentAtMs || startedAtMs,
      observedAtMs: upstreamRequestSentAtMs,
      maxStreamLagMs: options.maxStreamLagMs,
    });
    const resolutionLag = scenarioLagSummary({
      transition: "detail-history-request-resolution",
      startedAtMs: upstreamResponseReceivedAtMs || upstreamRequestSentAtMs || startedAtMs,
      acknowledgedAtMs: upstreamResponseReceivedAtMs || upstreamRequestSentAtMs || startedAtMs,
      observedAtMs: resolutionSentAtMs,
      maxStreamLagMs: options.maxStreamLagMs,
    });

    if (!liveWait.ok) {
      transitionFailure(
        findings,
        "scenario_detail_history_live_update_not_sent",
        "fixture did not send a live detail update after the simulator opened detail",
        { threadID, timeoutMs: detailWaitTimeoutMs }
      );
    }
    if (!requestWait.ok) {
      transitionFailure(
        findings,
        "scenario_detail_history_request_not_sent",
        "fixture did not send a live request after the simulator opened detail",
        { threadID, requestID, timeoutMs: detailWaitTimeoutMs }
      );
    }
    if (!responseWait.ok) {
      transitionFailure(
        findings,
        "scenario_detail_history_response_not_forwarded",
        "simulator app did not forward an approval response for the full-detail request card",
        { requestID, requestCardID, timeoutMs: detailWaitTimeoutMs }
      );
    }
    if (responseWait.ok && responseWait.value?.message?.result?.decision !== "accept") {
      transitionFailure(
        findings,
        "scenario_detail_history_response_wrong_payload",
        "simulator app sent the wrong approval response payload for the full-detail request",
        { requestID, response: responseWait.value?.message || null }
      );
    }
    if (!resolutionWait.ok) {
      transitionFailure(
        findings,
        "scenario_detail_history_resolution_not_sent",
        "fixture did not send serverRequest/resolved after the full-detail approval response",
        { requestID, timeoutMs: detailWaitTimeoutMs }
      );
    }

    const baseDetailTruth = {
      logicalHostID: hostID,
      detailHostID: `127.0.0.1:${relayPort}`,
      threadID,
      expectedMessageEventIDs: expectedHistoricalEventIDs,
    };
    transitions.push({
      name: "detail-history-live-update",
      kind: "detail-history-live-update",
      iteration: 1,
      route: "thread/resume",
      wait: {
        ok: liveWait.ok,
        observedAt: liveUpdateSentAtMs ? new Date(liveUpdateSentAtMs).toISOString() : null,
        observedAtMs: liveUpdateSentAtMs,
      },
      lag: liveLag,
      notification: liveWait.value?.message || null,
      detailTruth: {
        ...baseDetailTruth,
        kind: "detail-history-live-update",
        expectedMessageEventIDs: [...expectedHistoricalEventIDs, liveRawEventID],
        expectedMessageEventCount: expectedHistoricalEventIDs.length + 1,
      },
    });
    transitions.push({
      name: "detail-history-request-visible",
      kind: "detail-history-request-visible",
      iteration: 1,
      route: "thread/resume",
      wait: {
        ok: requestWait.ok,
        observedAt: upstreamRequestSentAtMs ? new Date(upstreamRequestSentAtMs).toISOString() : null,
        observedAtMs: upstreamRequestSentAtMs,
      },
      lag: requestLag,
      request: requestWait.value?.message || null,
      detailTruth: {
        ...baseDetailTruth,
        kind: "detail-history-request-visible",
        expectedMessageEventIDs: [],
        requestID,
        requestCardID,
        expectedStatus: "Pending",
        requestVisible: true,
      },
    });
    transitions.push({
      name: "detail-history-request-resolution",
      kind: "detail-history-request-resolution",
      iteration: 1,
      route: "server/response",
      wait: {
        ok: responseWait.ok && resolutionWait.ok,
        responseForwardedAt: upstreamResponseReceivedAtMs ? new Date(upstreamResponseReceivedAtMs).toISOString() : null,
        resolutionSentAt: resolutionSentAtMs ? new Date(resolutionSentAtMs).toISOString() : null,
      },
      lag: resolutionLag,
      forwardedResponse,
      resolution: resolutionWait.value?.message || null,
      detailTruth: {
        ...baseDetailTruth,
        kind: "detail-history-request-resolution",
        expectedMessageEventIDs: [...expectedHistoricalEventIDs, liveRawEventID, requestEventID],
        expectedMessageEventCount: expectedHistoricalEventIDs.length + 2,
        requestID,
        requestCardID,
        expectedStatus: "Resolved",
        requestVisible: true,
      },
    });

    const clientPathEvidence = summarizeClientPathEvents([...streamProbe.routeEvents, ...routeEvents]);
    findings.push(...requiredRouteFindings(clientPathEvidence, ["thread/read", "thread/turns/list", "thread/resume"]));
    const scenarioOK = !findings.some((finding) => finding.severity === "error" || finding.severity === "warning");
    const report = {
      schemaVersion: 1,
      kind: "codex-dock-controlled-simulator-scenario-relay-report",
      mode: "scenario",
      scenario: "detail-history-request",
      startedAt: new Date(startedAtMs).toISOString(),
      endedAt: new Date().toISOString(),
      relayUrl,
      summary: {
        ok: scenarioOK,
        clientPathOK: scenarioOK,
        scenario: "detail-history-request",
        scenarioOK,
        scenarioCount: 1,
        scenarioTransitionCount: transitions.length,
        implementedScenarios: ["detail-history-request"],
        unimplementedRequiredScenarios: [],
        failures: findings.length,
        clientPathRouteCounts: clientPathEvidence.routeCounts,
      },
      samples,
      scenarios: [{
        id: "detail-history-request",
        ok: scenarioOK,
        target: {
          logicalHostID: hostID,
          threadID,
          requestID,
          requestCardID,
          expectedHistoricalEventIDs,
          expectedLiveEventID: liveEventID,
        },
        transitions,
        findings,
      }],
      stream: {
        notificationCount: streamProbe.notifications.length,
        resyncCount: streamProbe.resyncs.length,
        finalState: sanitizeDockSnapshotForReport(streamProbe.snapshot()),
      },
      clientPathEvidence,
      findings,
      unsupportedFacts: [],
    };

    writeJSON(options.jsonOut, report);
    if (options.summaryOut) {
      writeText(options.summaryOut, buildMarkdownSummary(report));
    }
    await waitForFile(options.stopIn, options.waitTimeoutMs, "simulator UI sampler completion");
    return report;
  } finally {
    await streamProbe.close().catch(() => null);
    await relay.close().catch(() => null);
    await closeWebSocketServer(historyServer).catch(() => null);
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

async function runServerRequestScenario(options) {
  const routeEvents = [];
  const findings = [];
  const transitions = [];
  const samples = [];
  const startedAtMs = Date.now();
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "codex-dock-sim-server-request-"));
  const hostID = "sim-server-request-fixture";
  const threadID = "sim-server-request-thread";
  const requestID = "approval-1";
  const requestCardID = `request-${requestID}`;
  let upstreamRequestSentAtMs = null;
  let upstreamResponseReceivedAtMs = null;
  let resolutionSentAtMs = null;
  let forwardedResponse = null;
  let resolveRequestSent;
  let resolveForwardedResponse;
  let resolveResolutionSent;
  const requestSentPromise = new Promise((resolve) => {
    resolveRequestSent = resolve;
  });
  const forwardedResponsePromise = new Promise((resolve) => {
    resolveForwardedResponse = resolve;
  });
  const resolutionSentPromise = new Promise((resolve) => {
    resolveResolutionSent = resolve;
  });

  const historyServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await new Promise((resolve) => historyServer.once("listening", resolve));
  historyServer.on("connection", (ws) => {
    ws.on("message", (data) => {
      const message = JSON.parse(data.toString());
      if (message.method === "initialize") {
        recordClientRoute(routeEvents, "initialize", "simulator app initialized server-request fixture", { threadID });
        sendFixtureResult(ws, message.id, {
          userAgent: "codex-sim-server-request-fixture",
          codexHome: tempDir,
          platformFamily: "unix",
          platformOs: "macos",
        });
      } else if (message.method === "initialized") {
        recordClientRoute(routeEvents, "initialized", "simulator app sent initialized notification", { threadID });
      } else if (message.method === "thread/list") {
        sendFixtureResult(ws, message.id, {
          data: [fixtureThread(threadID, "Simulator server request fixture row", 100)],
          nextCursor: null,
          backwardsCursor: null,
        });
      } else if (message.method === "thread/loaded/list") {
        sendFixtureResult(ws, message.id, { data: [], nextCursor: null });
      } else if (message.method === "thread/read") {
        recordClientRoute(routeEvents, "thread/read", "simulator app read target thread detail", {
          threadID: message.params?.threadId || threadID,
        });
        sendFixtureResult(ws, message.id, {
          thread: {
            id: message.params?.threadId || threadID,
            turns: [],
          },
        });
      } else if (message.method === "thread/turns/list") {
        recordClientRoute(routeEvents, "thread/turns/list", "simulator app drained historical thread turns", {
          threadID: message.params?.threadId || threadID,
        });
        sendFixtureResult(ws, message.id, {
          data: [],
          nextCursor: null,
          backwardsCursor: null,
        });
      } else if (message.method === "thread/resume") {
        recordClientRoute(routeEvents, "thread/resume", "simulator app resumed target thread live detail", {
          threadID: message.params?.threadId || threadID,
        });
        sendFixtureResult(ws, message.id, {
          thread: {
            id: message.params?.threadId || threadID,
            turns: [],
          },
        });
        setTimeout(() => {
          upstreamRequestSentAtMs = Date.now();
          const requestMessage = {
            jsonrpc: "2.0",
            id: requestID,
            method: "item/commandExecution/requestApproval",
            params: {
              threadId: message.params?.threadId || threadID,
              turnId: "turn-live",
              itemId: "cmd-live",
              command: ["make", "test"],
              cwd: tempDir,
            },
          };
          ws.send(JSON.stringify(requestMessage));
          resolveRequestSent({
            sentAtMs: upstreamRequestSentAtMs,
            message: {
              id: requestID,
              method: requestMessage.method,
              threadID,
              requestCardID,
            },
          });
        }, 10);
      } else if (!message.method && String(message.id) === requestID) {
        upstreamResponseReceivedAtMs = Date.now();
        forwardedResponse = normalizeForComparison({
          id: message.id,
          result: message.result || null,
        });
        resolveForwardedResponse({
          receivedAtMs: upstreamResponseReceivedAtMs,
          message: forwardedResponse,
        });
        setTimeout(() => {
          resolutionSentAtMs = Date.now();
          const notification = {
            jsonrpc: "2.0",
            method: "serverRequest/resolved",
            params: {
              threadId: threadID,
              requestId: requestID,
            },
          };
          ws.send(JSON.stringify(notification));
          resolveResolutionSent({
            sentAtMs: resolutionSentAtMs,
            message: normalizeForComparison(notification),
          });
        }, 10);
      }
    });
  });

  const relayConfig = {
    listenHost: "127.0.0.1",
    port: 0,
    phoneAuth: "none",
    hostId: hostID,
    hostName: "Simulator Server Request Fixture",
    hostEndpoint: "127.0.0.1:0",
    historyUrl: `ws://127.0.0.1:${historyServer.address().port}`,
    historyBearerToken: "history-token",
    advertiseBonjour: false,
    observabilityDir: false,
    relayStateDatabasePath: path.join(tempDir, "relay-state.sqlite"),
    relayStateAutoStart: false,
    logger: {
      debug() {},
      info() {},
      warn() {},
      error() {},
      fault() {},
      fatalSync() {},
    },
  };
  const relay = startServer(relayConfig);
  await relay.listening;
  const relayPort = relay.server.address().port;
  const relayUrl = `ws://127.0.0.1:${relayPort}`;
  const fixtureOptions = {
    ...options,
    relayUrl,
    codexHome: tempDir,
    sqliteHome: tempDir,
    detail: "none",
  };
  const streamProbe = new DockStreamProbe(fixtureOptions);

  try {
    await streamProbe.open();
    const initialWait = await waitForStreamCondition({
      streamProbe,
      timeoutMs: options.dockCollectionTimeoutMs,
      predicate: (snapshot) => dockSnapshotThreadIndex(snapshot, threadID) === 0,
    });
    if (!initialWait.ok) {
      transitionFailure(
        findings,
        "scenario_server_request_initial_row_missing",
        "server-request fixture row did not appear in the fixture relay stream before simulator launch",
        { threadID }
      );
    }
    const initial = await freshComparison({ streamProbe, options: fixtureOptions, routeEvents });
    findings.push(...scenarioComparisonFindings({ phase: "initial", comparison: initial.comparison }));
    const initialFinishedAt = new Date().toISOString();
    samples.push({
      sampleIndex: 0,
      startedAt: new Date(startedAtMs).toISOString(),
      finishedAt: initialFinishedAt,
      freshDock: sanitizeDockSnapshotForReport(initial.freshDock),
    });

    writeJSON(options.readyOut, {
      ready: true,
      scenario: "server-request",
      relayUrl,
      hosts: `127.0.0.1:${relayPort}`,
      target: {
        logicalHostID: hostID,
        threadID,
        requestID,
        requestCardID,
      },
      uiConfig: {
        openHostID: hostID,
        openThreadID: threadID,
        requestCardID,
        requestAction: "approve",
      },
      at: new Date().toISOString(),
    });
    await waitForFile(options.uiReadyIn, options.waitTimeoutMs, "simulator UI detail sampler readiness");

    const detailWaitTimeoutMs = Math.min(options.dockCollectionTimeoutMs, options.waitTimeoutMs);
    const requestWait = await waitForAsyncEvent(requestSentPromise, detailWaitTimeoutMs);
    const responseWait = await waitForAsyncEvent(forwardedResponsePromise, detailWaitTimeoutMs);
    const resolutionWait = await waitForAsyncEvent(resolutionSentPromise, detailWaitTimeoutMs);
    const requestLag = scenarioLagSummary({
      transition: "server-request-visible",
      startedAtMs: upstreamRequestSentAtMs || startedAtMs,
      acknowledgedAtMs: upstreamRequestSentAtMs || startedAtMs,
      observedAtMs: upstreamRequestSentAtMs,
      maxStreamLagMs: options.maxStreamLagMs,
    });
    const resolutionLag = scenarioLagSummary({
      transition: "server-request-resolution",
      startedAtMs: upstreamResponseReceivedAtMs || upstreamRequestSentAtMs || startedAtMs,
      acknowledgedAtMs: upstreamResponseReceivedAtMs || upstreamRequestSentAtMs || startedAtMs,
      observedAtMs: resolutionSentAtMs,
      maxStreamLagMs: options.maxStreamLagMs,
    });

    if (!requestWait.ok) {
      transitionFailure(
        findings,
        "scenario_server_request_not_sent",
        "server request was not emitted after the simulator app resumed the detail session",
        { threadID, requestID, timeoutMs: detailWaitTimeoutMs }
      );
    }
    if (!responseWait.ok) {
      transitionFailure(
        findings,
        "scenario_server_request_response_not_forwarded",
        "simulator app did not forward an approval response for the displayed request card",
        { requestID, requestCardID, timeoutMs: detailWaitTimeoutMs }
      );
    }
    if (responseWait.ok && responseWait.value?.message?.result?.decision !== "accept") {
      transitionFailure(
        findings,
        "scenario_server_request_response_wrong_payload",
        "simulator app sent the wrong approval response payload",
        { requestID, response: responseWait.value?.message || null }
      );
    }
    if (!resolutionWait.ok) {
      transitionFailure(
        findings,
        "scenario_server_request_resolution_not_sent",
        "fixture did not send serverRequest/resolved after the simulator app approval response",
        { requestID, timeoutMs: detailWaitTimeoutMs }
      );
    }

    transitions.push({
      name: "server-request-visible",
      kind: "server-request-visible",
      iteration: 1,
      route: "thread/resume",
      wait: {
        ok: requestWait.ok,
        observedAt: upstreamRequestSentAtMs ? new Date(upstreamRequestSentAtMs).toISOString() : null,
        observedAtMs: upstreamRequestSentAtMs,
      },
      lag: requestLag,
      request: requestWait.value?.message || null,
      detailTruth: {
        kind: "server-request-visible",
        logicalHostID: hostID,
        detailHostID: `127.0.0.1:${relayPort}`,
        threadID,
        requestID,
        requestCardID,
        expectedStatus: "Pending",
        requestVisible: true,
      },
    });
    transitions.push({
      name: "server-request-resolution",
      kind: "server-request-resolution",
      iteration: 1,
      route: "server/response",
      wait: {
        ok: responseWait.ok && resolutionWait.ok,
        responseForwardedAt: upstreamResponseReceivedAtMs ? new Date(upstreamResponseReceivedAtMs).toISOString() : null,
        resolutionSentAt: resolutionSentAtMs ? new Date(resolutionSentAtMs).toISOString() : null,
      },
      lag: resolutionLag,
      forwardedResponse,
      resolution: resolutionWait.value?.message || null,
      detailTruth: {
        kind: "server-request-resolution",
        logicalHostID: hostID,
        detailHostID: `127.0.0.1:${relayPort}`,
        threadID,
        requestID,
        requestCardID,
        expectedStatus: "Resolved",
        requestVisible: true,
      },
    });

    const clientPathEvidence = summarizeClientPathEvents([...streamProbe.routeEvents, ...routeEvents]);
    findings.push(...requiredRouteFindings(clientPathEvidence, ["thread/read", "thread/turns/list", "thread/resume"]));
    const scenarioOK = !findings.some((finding) => finding.severity === "error" || finding.severity === "warning");
    const report = {
      schemaVersion: 1,
      kind: "codex-dock-controlled-simulator-scenario-relay-report",
      mode: "scenario",
      scenario: "server-request",
      startedAt: new Date(startedAtMs).toISOString(),
      endedAt: new Date().toISOString(),
      relayUrl,
      summary: {
        ok: scenarioOK,
        clientPathOK: scenarioOK,
        scenario: "server-request",
        scenarioOK,
        scenarioCount: 1,
        scenarioTransitionCount: transitions.length,
        implementedScenarios: ["server-request"],
        unimplementedRequiredScenarios: [],
        failures: findings.length,
        clientPathRouteCounts: clientPathEvidence.routeCounts,
      },
      samples,
      scenarios: [{
        id: "server-request",
        ok: scenarioOK,
        target: {
          logicalHostID: hostID,
          threadID,
          requestID,
          requestCardID,
        },
        transitions,
        findings,
      }],
      stream: {
        notificationCount: streamProbe.notifications.length,
        resyncCount: streamProbe.resyncs.length,
        finalState: sanitizeDockSnapshotForReport(streamProbe.snapshot()),
      },
      clientPathEvidence,
      findings,
      unsupportedFacts: [],
    };

    writeJSON(options.jsonOut, report);
    if (options.summaryOut) {
      writeText(options.summaryOut, buildMarkdownSummary(report));
    }
    await waitForFile(options.stopIn, options.waitTimeoutMs, "simulator UI sampler completion");
    return report;
  } finally {
    await streamProbe.close().catch(() => null);
    await relay.close().catch(() => null);
    await closeWebSocketServer(historyServer).catch(() => null);
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    console.log(usage());
    return;
  }
  validateOptions(options);
  let report;
  if (options.scenario === "detail-history-request") {
    report = await runDetailHistoryRequestScenario(options);
  } else if (options.scenario === "large-list-checkpoint") {
    report = await runLargeListCheckpointScenario(options);
  } else if (options.scenario === "server-request") {
    report = await runServerRequestScenario(options);
  } else if (options.scenario === "live-lease-expiry") {
    report = await runLiveLeaseExpiryScenario(options);
  } else if (options.scenario === "multi-host-isolation") {
    report = await runMultiHostIsolationScenario(options);
  } else if (options.scenario === "rapid-mutations") {
    report = await runRapidMutationsScenario(options);
  } else if (options.scenario === "resync-gap") {
    report = await runResyncGapScenario(options);
  } else if (options.scenario === "source-refresh") {
    report = await runSourceRefreshScenario(options);
  } else if (options.scenario === "spawn-edge") {
    report = await runSpawnEdgeScenario(options);
  } else {
    report = await runThreadActivityScenario(options);
  }
  await new Promise((resolve, reject) => {
    process.stdout.write(`${JSON.stringify({
      ok: report.summary.ok,
      relayUrl: report.relayUrl,
      summary: report.summary,
      reportPath: options.jsonOut,
      summaryPath: options.summaryOut || null,
      failures: report.findings.slice(0, 20),
    }, null, 2)}\n`, (error) => {
      if (error) {
        reject(error);
      } else {
        resolve();
      }
    });
  });
  process.exit(0);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.error(`controlled-simulator-fixture failed: ${error.message || error}`);
    process.exit(1);
  });
}

export {
  buildMarkdownSummary,
  parseArgs,
  validateOptions,
};

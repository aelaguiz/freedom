#!/usr/bin/env node
import fs from "node:fs";
import crypto from "node:crypto";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";
import WebSocket, { WebSocketServer } from "ws";

import { startServer } from "./dock-relay.mjs";
import { RELAY_STATE_STREAM_SCHEMA_VERSION } from "./dock-relay-constants.mjs";
import { threadMatchesSourceKinds } from "./dock-relay-source-filter.mjs";
import {
  projectionIDForThreadCard,
  projectionIDForThreadItem,
} from "./dock-relay-projection-engine.mjs";
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
import {
  assertProofReport,
  finalizeProofReport,
} from "./proof-report-contracts.mjs";
const SUPPORTED_SCENARIOS = new Set([
  "archive-toggle",
  "current-work-visible",
  "detail-reconnect",
  "file-change-review",
  "detail-history-request",
  "detail-replay-pressure",
  "foreground-resume-all-surfaces",
  "large-list-checkpoint",
  "live-lease-expiry",
  "multi-host-isolation",
  "mutation-ack-projection-refresh-failure",
  "rapid-mutations",
  "resync-gap",
  "root-catchup-window-contract",
  "server-request",
  "server-rename-notification",
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
const CLIENT_PATH_ROUTES = new Set([
  "initialize",
  "initialized",
  "dock/subscribe",
  "dock/update",
  "dock/resync",
  "archive/subscribe",
  "archive/update",
  "archive/resync",
  "thread/archive",
  "thread/unarchive",
  "thread/detail/subscribe",
  "thread/detail/resync",
  "thread/detail/update",
]);
const FORBIDDEN_SIMULATOR_DETAIL_SIDE_DOOR_ROUTES = new Set([
  "thread/read",
  "thread/turns/list",
  "thread/resume",
  "thread/detail/read",
]);

function usage() {
  return [
    "Usage:",
    "  node scripts/dock-relay-controlled-simulator-fixture.mjs --scenario <archive-toggle|current-work-visible|detail-reconnect|detail-history-request|detail-replay-pressure|file-change-review|foreground-resume-all-surfaces|large-list-checkpoint|live-lease-expiry|multi-host-isolation|mutation-ack-projection-refresh-failure|rapid-mutations|resync-gap|root-catchup-window-contract|server-request|server-rename-notification|source-refresh|spawn-edge|thread-activity> --ready-out <path> --ui-ready-in <path> --stop-in <path> --json-out <path> [options]",
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

function retargetScenarioReport(report, scenario) {
  if (!report || report.scenario === scenario) {
    return report;
  }
  report.scenario = scenario;
  if (report.summary) {
    report.summary.scenario = scenario;
    report.summary.implementedScenarios = [scenario];
  }
  if (Array.isArray(report.scenarios) && report.scenarios.length === 1) {
    report.scenarios[0].id = scenario;
    if (typeof report.scenarios[0].name === "string") {
      report.scenarios[0].name = scenario;
    }
  }
  return report;
}

function writeJSON(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

function proofRunIDForReportPath(filePath) {
  const reportDir = path.resolve(path.dirname(filePath || "."));
  return crypto.createHash("sha256").update(reportDir).digest("hex").slice(0, 16);
}

function writeProofReport(filePath, report) {
  if (!report.proofRunID) {
    report.proofRunID = proofRunIDForReportPath(filePath);
  }
  finalizeProofReport(report);
  assertProofReport(report);
  writeJSON(filePath, report);
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

function projectionRowsFromWitness(witness) {
  const rowsByProjectionID = new Map();
  for (const envelope of witness?.envelopes || []) {
    if (envelope.kind === "delete") {
      for (const projectionID of envelope.projectionIDs || []) {
        rowsByProjectionID.delete(projectionID);
      }
      continue;
    }
    if (envelope.kind === "snapshot" || !envelope.kind) {
      rowsByProjectionID.clear();
    }
    for (const row of envelope.rows || []) {
      if (row?.projectionID) {
        rowsByProjectionID.set(row.projectionID, row);
      }
    }
  }
  return [...rowsByProjectionID.values()]
    .sort((left, right) => String(left.displayOrderKey).localeCompare(String(right.displayOrderKey)));
}

function requestProjectionIDFromWitness(witness, requestID) {
  if (requestID === null || requestID === undefined) {
    return null;
  }
  const expected = String(requestID);
  return projectionRowsFromWitness(witness).find((row) => {
    const payload = row?.payload || {};
    const request = payload.request || {};
    return String(payload.requestID ?? request.requestID ?? "") === expected;
  })?.projectionID || null;
}

function requestStatusFromWitness(witness, requestID) {
  if (requestID === null || requestID === undefined) {
    return null;
  }
  const expected = String(requestID);
  return projectionRowsFromWitness(witness).find((row) => {
    const payload = row?.payload || {};
    const request = payload.request || {};
    return String(payload.requestID ?? request.requestID ?? "") === expected;
  })?.payload?.request?.status || null;
}

function projectionWitnessTruth(witness) {
  return {
    source: witness?.source || null,
    byteEquivalentToDownstream: witness?.byteEquivalentToDownstream === true,
    sourceHostID: witness?.sourceHostID || null,
    view: witness?.view || null,
    scope: witness?.scope || null,
    threadID: witness?.threadID || null,
    viewParamsKey: witness?.viewParamsKey || null,
    epoch: witness?.epoch || null,
    lastSeq: witness?.lastSeq ?? null,
    projectionIDs: Array.isArray(witness?.projectionIDs) ? witness.projectionIDs : [],
  };
}

async function readDetailProjectionWitness(client, {
  sourceHostID,
  threadID,
}) {
  return client.request("projection/witness/read", {
    sourceHostID,
    view: "thread.detail",
    scope: "thread",
    threadID,
  });
}

async function waitForDetailProjectionWitness({
  client,
  sourceHostID,
  threadID,
  minProjectionCount = 0,
  requestID = null,
  requestStatus = null,
  timeoutMs,
}) {
  const deadline = Date.now() + timeoutMs;
  let lastWitness = null;
  while (Date.now() < deadline) {
    lastWitness = await readDetailProjectionWitness(client, { sourceHostID, threadID });
    const projectionCount = Array.isArray(lastWitness?.projectionIDs) ? lastWitness.projectionIDs.length : 0;
    const hasEnoughRows = projectionCount >= minProjectionCount;
    const hasRequest = requestID === null || requestProjectionIDFromWitness(lastWitness, requestID);
    const hasRequestStatus = requestStatus === null || requestStatusFromWitness(lastWitness, requestID) === requestStatus;
    if (lastWitness?.byteEquivalentToDownstream === true && hasEnoughRows && hasRequest && hasRequestStatus) {
      return lastWitness;
    }
    await sleep(100);
  }
  return null;
}

function detailTransitionWitnessTimeoutMs(options, fallbackTimeoutMs) {
  const lagBudget = Number(options.maxStreamLagMs || DEFAULT_MAX_STREAM_LAG_MS);
  if (!Number.isFinite(lagBudget) || lagBudget <= 0) {
    return fallbackTimeoutMs;
  }
  return Math.min(fallbackTimeoutMs, Math.max(lagBudget + 500, 2_000));
}

function detailTruthFromWitness({
  kind,
  logicalHostID,
  sourceHostID,
  detailHostID,
  threadID,
  witness,
  requestID = null,
  expectedStatus = null,
  requestVisible = false,
}) {
  const projectionWitness = projectionWitnessTruth(witness);
  const requestCardID = requestProjectionIDFromWitness(witness, requestID);
  return {
    kind,
    sourceHostID: projectionWitness.sourceHostID || sourceHostID || logicalHostID || null,
    detailHostID,
    threadID,
    projectionWitness,
    relayMessageEventCount: projectionWitness.projectionIDs.length,
    ...(requestID ? { requestID } : {}),
    ...(requestCardID ? { requestCardID } : {}),
    ...(expectedStatus ? { expectedStatus } : {}),
    requestVisible: requestVisible && Boolean(requestCardID),
  };
}

function projectionIDForCommandApprovalRequest({ sourceHostID, threadID, turnID, itemID }) {
  // Item-backed command approvals are request-decorated command rows. Keep the
  // UI sampler on the same relay-owned row identity instead of generic buttons.
  return projectionIDForThreadItem({
    sourceHostID,
    threadID,
    turnID,
    itemID,
    rowRole: "command",
  });
}

function projectionIDForFileChangeRequest({ sourceHostID, threadID, turnID, itemID }) {
  return projectionIDForThreadItem({
    sourceHostID,
    threadID,
    turnID,
    itemID,
    rowRole: "fileChange",
  });
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

function activeFixtureRows(message, rows) {
  return message.params?.archived === true ? [] : rows;
}

function proofMessageSummary(message, overrides = {}) {
  if (!message) {
    return null;
  }
  const params = message.params || {};
  const result = message.result || {};
  const summary = {
    id: message.id ?? overrides.id ?? null,
    method: message.method ?? overrides.method ?? null,
    threadID: params.threadId ?? overrides.threadID ?? null,
    turnID: params.turnId ?? overrides.turnID ?? null,
    itemID: params.itemId ?? overrides.itemID ?? null,
    requestID: params.requestId ?? overrides.requestID ?? null,
    status: result.decision ?? message.status ?? overrides.status ?? null,
  };
  return Object.fromEntries(Object.entries(summary).filter(([, value]) => value !== null && value !== undefined));
}

function fixtureMessageThreadID(message) {
  return message?.params?.threadId || message?.params?.threadID;
}

function fixtureRowForMessage(rows, message) {
  const threadID = fixtureMessageThreadID(message);
  return (rows || []).find((row) => row.id === threadID) || null;
}

function sendFixtureThreadRead(ws, message, row) {
  if (!row) {
    sendFixtureError(ws, message.id, `unknown thread: ${fixtureMessageThreadID(message) || "missing"}`);
    return;
  }
  sendFixtureResult(ws, message.id, {
    thread: {
      ...row,
      turns: [],
    },
  });
}

function sendFixtureThreadTurnsList(ws, message, row) {
  sendFixtureResult(ws, message.id, {
    data: row ? [fixtureTurn(`${row.id}-turn`, row.updatedAt, [])] : [],
    nextCursor: null,
    backwardsCursor: null,
  });
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

function compareDockCardRenderOrder(left, right) {
  const leftOrder = typeof left?.displayOrderKey === "string" ? left.displayOrderKey : "";
  const rightOrder = typeof right?.displayOrderKey === "string" ? right.displayOrderKey : "";
  if (leftOrder !== rightOrder) {
    return leftOrder.localeCompare(rightOrder);
  }
  return cardID(left).localeCompare(cardID(right));
}

function dockCardsInRenderOrder(snapshot) {
  return (Array.isArray(snapshot?.rows) ? snapshot.rows : [])
    .slice()
    .sort(compareDockCardRenderOrder);
}

function dockRenderOrderIDs(snapshot) {
  return dockCardsInRenderOrder(snapshot).map(cardID);
}

function dockSnapshotCardForThread(snapshot, threadID) {
  return (Array.isArray(snapshot?.rows) ? snapshot.rows : [])
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

async function waitForStableDockClientPathThread({
  streamProbe,
  options,
  routeEvents,
  threadID,
  timeoutMs,
}) {
  const deadlineMs = Date.now() + timeoutMs;
  let lastComparison = null;
  while (Date.now() < deadlineMs) {
    lastComparison = await freshComparison({ streamProbe, options, routeEvents });
    if (dockSnapshotHasThread(lastComparison.freshDock, threadID)) {
      return {
        ok: true,
        observedAt: new Date().toISOString(),
        observedAtMs: Date.now(),
        ...lastComparison,
      };
    }
    await sleep(500);
  }
  return {
    ok: false,
    observedAt: null,
    observedAtMs: null,
    timeoutMs,
    ...(lastComparison || { freshDock: null, comparison: null, attempts: [] }),
  };
}

async function waitForArchiveStreamCondition({ streamProbe, timeoutMs, predicate }) {
  const deadlineMs = Date.now() + timeoutMs;
  while (true) {
    const snapshot = streamProbe.archiveSnapshot();
    const observedAtMs = observedSnapshotTime(snapshot);
    if (predicate(snapshot)) {
      return {
        ok: true,
        observedAt: new Date(observedAtMs).toISOString(),
        observedAtMs,
        snapshot: sanitizeDockSnapshotForReport(snapshot),
      };
    }
    if (streamProbe.archiveState.needsResync) {
      await streamProbe.archiveResync("controlled_simulator_fixture_archive_condition");
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

function routeEventObservedAtMS(event) {
  const parsed = Date.parse(event?.at || 0);
  return Number.isFinite(parsed) ? parsed : null;
}

async function waitForRecordedRouteEvent({
  events,
  route,
  source = null,
  boundary = null,
  afterMs = 0,
  timeoutMs,
}) {
  const deadline = Date.now() + timeoutMs;
  let lastMatchingEvent = null;
  while (Date.now() < deadline) {
    lastMatchingEvent = (Array.isArray(events) ? events : []).find((event) => {
      if (event?.route !== route) {
        return false;
      }
      if (source !== null && event.source !== source) {
        return false;
      }
      if (boundary !== null && event.boundary !== boundary) {
        return false;
      }
      return (routeEventObservedAtMS(event) ?? 0) >= afterMs;
    }) || lastMatchingEvent;
    if (lastMatchingEvent) {
      const observedAtMs = routeEventObservedAtMS(lastMatchingEvent) ?? Date.now();
      return {
        ok: true,
        route,
        source,
        boundary,
        observedAt: new Date(observedAtMs).toISOString(),
        observedAtMs,
        event: lastMatchingEvent,
      };
    }
    await sleep(100);
  }
  return {
    ok: false,
    route,
    source,
    boundary,
    observedAt: null,
    observedAtMs: null,
    timeoutMs,
    event: null,
  };
}

function recordClientRoute(events, route, purpose, details = {}) {
  if (!Array.isArray(events)) {
    return;
  }
  const countedAsClientPath = CLIENT_PATH_ROUTES.has(route);
  events.push({
    route,
    purpose,
    countedAsClientPath,
    routeClass: countedAsClientPath ? "clientPath" : "relayInternalAdapter",
    at: new Date().toISOString(),
    ...normalizeForComparison(details),
  });
}

function recordProxyRoute(events, data, direction, label) {
  let message;
  try {
    message = JSON.parse(data.toString());
  } catch {
    return;
  }
  if (!message?.method) {
    return;
  }
  recordClientRoute(events, message.method, "simulator app relay proxy observed JSON-RPC route", {
    source: "simulatorAppProxy",
    boundary: direction,
    label,
    hasResponseID: message.id !== undefined,
  });
}

async function startSimulatorAppRouteProxy({ targetUrl, routeEvents, label }) {
  const server = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  const pairs = new Set();
  await new Promise((resolve) => server.once("listening", resolve));
  server.on("connection", (clientWs) => {
    const upstreamWs = new WebSocket(targetUrl);
    const pending = [];
    const pair = { clientWs, upstreamWs };
    pairs.add(pair);
    const sendToUpstream = (data, isBinary) => {
      if (upstreamWs.readyState === WebSocket.OPEN) {
        upstreamWs.send(data, { binary: isBinary });
      } else if (upstreamWs.readyState === WebSocket.CONNECTING) {
        pending.push({ data, isBinary });
      } else if (clientWs.readyState === WebSocket.OPEN) {
        clientWs.close(1011, "relay proxy upstream closed");
      }
    };
    const closeBoth = () => {
      pairs.delete(pair);
      try {
        if (clientWs.readyState === WebSocket.OPEN || clientWs.readyState === WebSocket.CONNECTING) {
          clientWs.close();
        }
      } catch {
        // Proxy shutdown should not mask the scenario result.
      }
      try {
        if (upstreamWs.readyState === WebSocket.OPEN || upstreamWs.readyState === WebSocket.CONNECTING) {
          upstreamWs.close();
        }
      } catch {
        // Proxy shutdown should not mask the scenario result.
      }
    };
    upstreamWs.on("open", () => {
      while (pending.length > 0 && upstreamWs.readyState === WebSocket.OPEN) {
        const item = pending.shift();
        upstreamWs.send(item.data, { binary: item.isBinary });
      }
    });
    clientWs.on("message", (data, isBinary) => {
      recordProxyRoute(routeEvents, data, "simulatorAppToRelay", label);
      sendToUpstream(data, isBinary);
    });
    upstreamWs.on("message", (data, isBinary) => {
      recordProxyRoute(routeEvents, data, "relayToSimulatorApp", label);
      if (clientWs.readyState === WebSocket.OPEN) {
        clientWs.send(data, { binary: isBinary });
      }
    });
    clientWs.on("close", closeBoth);
    upstreamWs.on("close", closeBoth);
    clientWs.on("error", closeBoth);
    upstreamWs.on("error", closeBoth);
  });
  const port = server.address().port;
  return {
    endpoint: `127.0.0.1:${port}`,
    url: `ws://127.0.0.1:${port}`,
    close: async () => {
      for (const { clientWs, upstreamWs } of pairs) {
        try {
          clientWs.terminate();
        } catch {
          // Proxy shutdown should not mask the scenario result.
        }
        try {
          upstreamWs.terminate();
        } catch {
          // Proxy shutdown should not mask the scenario result.
        }
      }
      await closeWebSocketServer(server);
    },
  };
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

function forbiddenSimulatorDetailRouteFindings(simulatorClientPathEvidence) {
  const findings = [];
  const events = Array.isArray(simulatorClientPathEvidence?.events)
    ? simulatorClientPathEvidence.events
    : [];
  for (const event of events) {
    if (event.source !== "simulatorAppProxy" || event.boundary !== "simulatorAppToRelay") {
      continue;
    }
    if (!FORBIDDEN_SIMULATOR_DETAIL_SIDE_DOOR_ROUTES.has(event.route)) {
      continue;
    }
    transitionFailure(
      findings,
      "controlled_simulator_forbidden_detail_side_door_route",
      "simulator app sent a forbidden raw detail route instead of the thread/detail projection route",
      {
        route: event.route,
        at: event.at || null,
      }
    );
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
  const rows = dockCardsInRenderOrder({
    rows: normalizedSnapshots.flatMap((snapshot) => Array.isArray(snapshot.rows) ? snapshot.rows : []),
  });
  const projectionIDs = rows.map(cardID);
  const rowCount = rows.length;
  return {
    kind: "snapshot",
    schemaVersion: RELAY_STATE_STREAM_SCHEMA_VERSION,
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
    rowCount,
    projectionIDs,
    renderOrderProjectionIDs: dockRenderOrderIDs({ rows }),
    rows,
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
          data: activeFixtureRows(message, getRows()),
          nextCursor: null,
          backwardsCursor: null,
        });
      } else if (message.method === "thread/loaded/list") {
        sendFixtureResult(ws, message.id, { data: [], nextCursor: null });
      } else if (message.method === "thread/read" || message.method === "thread/resume") {
        sendFixtureThreadRead(ws, message, fixtureRowForMessage(getRows(), message));
      } else if (message.method === "thread/turns/list") {
        sendFixtureThreadTurnsList(ws, message, fixtureRowForMessage(getRows(), message));
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

async function runArchiveToggleScenario(options) {
  const scenarioName = options.scenario;
  const isMutationAckProjectionRefresh = scenarioName === "mutation-ack-projection-refresh-failure";
  const routeEvents = [];
  const findings = [];
  const transitions = [];
  const samples = [];
  const startedAtMs = Date.now();
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), `codex-dock-sim-${scenarioName}-`));
  const hostID = `sim-${scenarioName}-fixture`;
  const threadID = `sim-${scenarioName}-thread`;
  const existingArchivedID = `sim-${scenarioName}-existing-archived`;
  const archivedThreadIDs = new Set([existingArchivedID]);
  const rows = [
    fixtureThreadWithStatus(threadID, `Simulator ${scenarioName} active row`, 2_000, { type: "idle" }),
    fixtureThreadWithStatus(existingArchivedID, `Simulator ${scenarioName} archived row`, 1_000, { type: "idle" }),
  ];

  const rowForID = (thread) => rows.find((row) => row.id === thread) || null;
  const visibleRows = (archived) => rows.filter((row) => archivedThreadIDs.has(row.id) === archived);

  const historyServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await new Promise((resolve) => historyServer.once("listening", resolve));
  historyServer.on("connection", (ws) => {
    ws.on("message", (data) => {
      const message = JSON.parse(data.toString());
      if (message.method === "initialize") {
        sendFixtureResult(ws, message.id, {
          userAgent: `codex-sim-${scenarioName}-fixture`,
          codexHome: tempDir,
          platformFamily: "unix",
          platformOs: "macos",
        });
      } else if (message.method === "thread/list") {
        sendFixtureResult(ws, message.id, {
          data: visibleRows(message.params?.archived === true),
          nextCursor: null,
          backwardsCursor: null,
        });
      } else if (message.method === "thread/loaded/list") {
        sendFixtureResult(ws, message.id, { data: [], nextCursor: null });
      } else if (message.method === "thread/read" || message.method === "thread/resume") {
        const thread = rowForID(message.params?.threadId || message.params?.threadID);
        if (!thread) {
          sendFixtureError(ws, message.id, "unknown thread");
          return;
        }
        sendFixtureResult(ws, message.id, { thread: { ...thread, turns: [] } });
      } else if (message.method === "thread/turns/list") {
        const thread = rowForID(message.params?.threadId || message.params?.threadID);
        sendFixtureResult(ws, message.id, {
          data: thread ? [fixtureTurn(`${thread.id}-turn`, thread.updatedAt, [])] : [],
          nextCursor: null,
          backwardsCursor: null,
        });
      } else if (message.method === "thread/archive") {
        const thread = rowForID(message.params?.threadId || message.params?.threadID);
        if (!thread) {
          sendFixtureError(ws, message.id, "unknown thread");
          return;
        }
        archivedThreadIDs.add(thread.id);
        sendFixtureResult(ws, message.id, { thread: { ...thread, archived: true } });
      } else if (message.method === "thread/unarchive") {
        const thread = rowForID(message.params?.threadId || message.params?.threadID);
        if (!thread) {
          sendFixtureError(ws, message.id, "unknown thread");
          return;
        }
        archivedThreadIDs.delete(thread.id);
        sendFixtureResult(ws, message.id, { thread: { ...thread, archived: false } });
      }
    });
  });

  const relayConfig = {
    listenHost: "127.0.0.1",
    port: 0,
    phoneAuth: "none",
    hostId: hostID,
    hostName: `Simulator ${scenarioName} Fixture`,
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
    await streamProbe.openArchive();
    const initialWait = await waitForStreamCondition({
      streamProbe,
      timeoutMs: options.dockCollectionTimeoutMs,
      predicate: (snapshot) => (
        dockSnapshotHasThread(snapshot, threadID)
        && !dockSnapshotHasThread(snapshot, existingArchivedID)
      ),
    });
    const initialArchiveWait = await waitForArchiveStreamCondition({
      streamProbe,
      timeoutMs: options.dockCollectionTimeoutMs,
      predicate: (snapshot) => (
        !dockSnapshotHasThread(snapshot, threadID)
        && dockSnapshotHasThread(snapshot, existingArchivedID)
      ),
    });
    if (!initialWait.ok) {
      transitionFailure(
        findings,
        `scenario_${scenarioName}_initial_row_missing`,
        `${scenarioName} fixture did not start with only the active row visible through the fixture relay stream`,
        { threadID, existingArchivedID }
      );
    }
    if (!initialArchiveWait.ok) {
      transitionFailure(
        findings,
        `scenario_${scenarioName}_initial_archive_row_missing`,
        `${scenarioName} fixture did not start with the existing archived row visible through the fixture Archive stream`,
        { threadID, existingArchivedID }
      );
    }

    const initial = await freshComparison({ streamProbe, options: fixtureOptions, routeEvents });
    findings.push(...scenarioComparisonFindings({ phase: `${scenarioName}-initial`, comparison: initial.comparison }));
    samples.push({
      sampleIndex: 0,
      startedAt: new Date(startedAtMs).toISOString(),
      finishedAt: new Date().toISOString(),
      freshDock: sanitizeDockSnapshotForReport(initial.freshDock),
    });

    writeJSON(options.readyOut, {
      ready: true,
      scenario: scenarioName,
      relayUrl,
      hosts: `127.0.0.1:${relayPort}`,
      target: {
        sourceHostID: hostID,
        threadID,
        existingArchivedID,
      },
      at: new Date().toISOString(),
    });
    await waitForFile(options.uiReadyIn, options.waitTimeoutMs, "simulator UI sampler readiness");
    await sleep(Math.min(Math.max(options.scenarioHoldMs, 500), 5_000));

    const archiveStartedAtMs = Date.now();
    recordClientRoute(routeEvents, "thread/archive", `controlled ${scenarioName} archives active row`, { threadID });
    const archiveResponse = await streamProbe.client.request("thread/archive", { threadId: threadID });
    const archiveAcknowledgedAtMs = Date.now();
    const archiveWait = await waitForStreamCondition({
      streamProbe,
      timeoutMs: options.dockCollectionTimeoutMs,
      predicate: (snapshot) => !dockSnapshotHasThread(snapshot, threadID),
    });
    const archiveViewWait = await waitForArchiveStreamCondition({
      streamProbe,
      timeoutMs: options.dockCollectionTimeoutMs,
      predicate: (snapshot) => dockSnapshotHasThread(snapshot, threadID),
    });
    const archiveLag = scenarioLagSummary({
      transition: "archive",
      startedAtMs: archiveStartedAtMs,
      acknowledgedAtMs: archiveAcknowledgedAtMs,
      observedAtMs: archiveWait.observedAtMs,
      maxStreamLagMs: options.maxStreamLagMs,
    });
    if (!archiveWait.ok) {
      transitionFailure(
        findings,
        `scenario_${scenarioName}_archive_not_seen`,
        `${scenarioName} fixture did not remove the archived row from the long-lived Dock stream`,
        { threadID }
      );
    }
    if (!archiveViewWait.ok) {
      transitionFailure(
        findings,
        `scenario_${scenarioName}_archive_not_seen_in_archive_stream`,
        `${scenarioName} fixture did not add the archived row to the long-lived Archive stream`,
        { threadID }
      );
    } else if (archiveLag.exceeded) {
      transitionFailure(
        findings,
        `scenario_${scenarioName}_archive_lag_exceeded`,
        `${scenarioName} archive transition exceeded the stream lag budget`,
        { threadID, observedLagMs: archiveLag.lag_change_to_relay_ms, maxStreamLagMs: options.maxStreamLagMs }
      );
    }
    const afterArchive = await freshComparison({ streamProbe, options: fixtureOptions, routeEvents });
    findings.push(...scenarioComparisonFindings({ phase: `${scenarioName}-archive`, comparison: afterArchive.comparison }));
    transitions.push({
      name: "archive",
      kind: "archive",
      route: "thread/archive",
      response: normalizeForComparison(archiveResponse),
      wait: archiveWait,
      lag: archiveLag,
      freshDock: sanitizeDockSnapshotForReport(afterArchive.freshDock),
      archiveStreamWait: archiveViewWait,
      freshArchive: sanitizeDockSnapshotForReport(streamProbe.archiveSnapshot()),
      streamComparison: afterArchive.comparison,
    });
    samples.push({
      sampleIndex: 1,
      startedAt: new Date(archiveStartedAtMs).toISOString(),
      finishedAt: new Date().toISOString(),
      freshDock: sanitizeDockSnapshotForReport(afterArchive.freshDock),
    });
    await sleep(Math.min(Math.max(options.scenarioHoldMs, 500), 5_000));

    const unarchiveStartedAtMs = Date.now();
    recordClientRoute(routeEvents, "thread/unarchive", `controlled ${scenarioName} unarchives row`, { threadID });
    const unarchiveResponse = await streamProbe.client.request("thread/unarchive", { threadId: threadID });
    const unarchiveAcknowledgedAtMs = Date.now();
    const unarchiveWait = await waitForStreamCondition({
      streamProbe,
      timeoutMs: options.dockCollectionTimeoutMs,
      predicate: (snapshot) => dockSnapshotHasThread(snapshot, threadID),
    });
    const unarchiveViewWait = await waitForArchiveStreamCondition({
      streamProbe,
      timeoutMs: options.dockCollectionTimeoutMs,
      predicate: (snapshot) => !dockSnapshotHasThread(snapshot, threadID),
    });
    const unarchiveLag = scenarioLagSummary({
      transition: "unarchive",
      startedAtMs: unarchiveStartedAtMs,
      acknowledgedAtMs: unarchiveAcknowledgedAtMs,
      observedAtMs: unarchiveWait.observedAtMs,
      maxStreamLagMs: options.maxStreamLagMs,
    });
    if (!unarchiveWait.ok) {
      transitionFailure(
        findings,
        `scenario_${scenarioName}_unarchive_not_seen`,
        `${scenarioName} fixture did not restore the unarchived row to the long-lived Dock stream`,
        { threadID }
      );
    }
    if (!unarchiveViewWait.ok) {
      transitionFailure(
        findings,
        `scenario_${scenarioName}_unarchive_not_seen_in_archive_stream`,
        `${scenarioName} fixture did not remove the unarchived row from the long-lived Archive stream`,
        { threadID }
      );
    } else if (unarchiveLag.exceeded) {
      transitionFailure(
        findings,
        `scenario_${scenarioName}_unarchive_lag_exceeded`,
        `${scenarioName} unarchive transition exceeded the stream lag budget`,
        { threadID, observedLagMs: unarchiveLag.lag_change_to_relay_ms, maxStreamLagMs: options.maxStreamLagMs }
      );
    }
    const afterUnarchive = await freshComparison({ streamProbe, options: fixtureOptions, routeEvents });
    findings.push(...scenarioComparisonFindings({ phase: `${scenarioName}-unarchive`, comparison: afterUnarchive.comparison }));
    transitions.push({
      name: "unarchive",
      kind: "unarchive",
      route: "thread/unarchive",
      response: normalizeForComparison(unarchiveResponse),
      wait: unarchiveWait,
      lag: unarchiveLag,
      freshDock: sanitizeDockSnapshotForReport(afterUnarchive.freshDock),
      archiveStreamWait: unarchiveViewWait,
      freshArchive: sanitizeDockSnapshotForReport(streamProbe.archiveSnapshot()),
      streamComparison: afterUnarchive.comparison,
    });
    samples.push({
      sampleIndex: 2,
      startedAt: new Date(unarchiveStartedAtMs).toISOString(),
      finishedAt: new Date().toISOString(),
      freshDock: sanitizeDockSnapshotForReport(afterUnarchive.freshDock),
    });

    if (isMutationAckProjectionRefresh) {
      const refreshStartedAtMs = Date.now();
      const refreshResult = await streamProbe.resync("controlled_simulator_mutation_ack_projection_refresh");
      const refreshComparison = await freshComparison({ streamProbe, options: fixtureOptions, routeEvents });
      findings.push(...scenarioComparisonFindings({ phase: `${scenarioName}-projection-refresh`, comparison: refreshComparison.comparison }));
      transitions.push({
        name: "projection-refresh-after-mutation-ack",
        kind: "projection-refresh-after-mutation-ack",
        route: "dock/resync",
        wait: {
          ok: true,
          observedAt: refreshResult.finishedAt,
          observedAtMs: Date.parse(refreshResult.finishedAt),
        },
        lag: scenarioLagSummary({
          transition: "projection-refresh-after-mutation-ack",
          startedAtMs: refreshStartedAtMs,
          acknowledgedAtMs: refreshStartedAtMs,
          observedAtMs: Date.parse(refreshResult.finishedAt),
          maxStreamLagMs: options.maxStreamLagMs,
        }),
        resync: refreshResult,
        freshDock: sanitizeDockSnapshotForReport(refreshComparison.freshDock),
        streamComparison: refreshComparison.comparison,
      });
    }

    const clientPathEvidence = summarizeClientPathEvents([...streamProbe.routeEvents, ...routeEvents]);
    findings.push(...requiredRouteFindings(
      clientPathEvidence,
      isMutationAckProjectionRefresh
        ? ["dock/subscribe", "dock/update", "dock/resync", "archive/subscribe", "archive/update", "thread/archive", "thread/unarchive"]
        : ["dock/subscribe", "dock/update", "archive/subscribe", "archive/update", "thread/archive", "thread/unarchive"]
    ));
    const scenarioOK = !findings.some((finding) => finding.severity === "error" || finding.severity === "warning");
    const report = {
      schemaVersion: 1,
      kind: "codex-dock-controlled-simulator-scenario-relay-report",
      mode: "scenario",
      scenario: scenarioName,
      startedAt: new Date(startedAtMs).toISOString(),
      endedAt: new Date().toISOString(),
      relayUrl,
      summary: {
        ok: scenarioOK,
        clientPathOK: scenarioOK,
        scenario: scenarioName,
        scenarioOK,
        scenarioCount: 1,
        scenarioTransitionCount: transitions.length,
        implementedScenarios: [scenarioName],
        unimplementedRequiredScenarios: [],
        failures: findings.length,
        clientPathRouteCounts: clientPathEvidence.routeCounts,
      },
      samples,
      scenarios: [{
        id: scenarioName,
        ok: scenarioOK,
        actuator: {
          type: isMutationAckProjectionRefresh
            ? "controlled archive/unarchive through relay RPC plus explicit projection refresh proof"
            : "controlled archive/unarchive through relay RPC",
          routes: isMutationAckProjectionRefresh ? ["thread/archive", "thread/unarchive", "dock/resync"] : ["thread/archive", "thread/unarchive"],
          clientExercised: true,
        },
        target: {
          sourceHostID: hostID,
          threadID,
          existingArchivedID,
        },
        transitions,
        findings,
      }],
      stream: {
        notificationCount: streamProbe.notifications.length,
        archiveNotificationCount: streamProbe.archiveNotifications.length,
        resyncCount: streamProbe.resyncs.length,
        archiveResyncCount: streamProbe.archiveResyncs.length,
        finalState: sanitizeDockSnapshotForReport(streamProbe.snapshot()),
        finalArchiveState: sanitizeDockSnapshotForReport(streamProbe.archiveSnapshot()),
      },
      clientPathEvidence,
      findings,
      unsupportedFacts: [],
    };

    writeProofReport(options.jsonOut, report);
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

function multiHostIsolationFindings({ label, snapshot, host, expectedThreadIDs, forbiddenThreadIDs = [] }) {
  const findings = [];
  const rows = Array.isArray(snapshot?.rows) ? snapshot.rows : [];
  const projectionIDs = new Set(rows.map((card) => cardID(card)));
  for (const card of rows) {
    if (card?.sourceHostID !== host.id) {
      transitionFailure(
        findings,
        "scenario_multi_host_wrong_source_host",
        "Dock card used the wrong relay projection source host id",
        {
          label,
          expectedHostID: host.id,
          actualHostID: card?.sourceHostID || null,
          logicalHostID: card?.logicalHostID || null,
          threadID: cardThreadID(card),
        }
      );
    }
    const relayScopedProjectionID = cardThreadID(card)
      ? projectionIDForThreadCard({ sourceHostID: host.id, threadID: cardThreadID(card) })
      : null;
    if (relayScopedProjectionID && cardID(card) !== relayScopedProjectionID) {
      transitionFailure(
        findings,
        "scenario_multi_host_wrong_card_id_scope",
        "Dock card projectionID is not scoped by the relay source host id",
        {
          label,
          relayScopedProjectionID,
          cardID: cardID(card),
          threadID: cardThreadID(card),
        }
      );
    }
  }
  for (const threadID of expectedThreadIDs) {
    const relayScopedProjectionID = projectionIDForThreadCard({ sourceHostID: host.id, threadID });
    if (!projectionIDs.has(relayScopedProjectionID)) {
      transitionFailure(
        findings,
        "scenario_multi_host_expected_thread_missing",
        "expected host-scoped thread is missing from this relay host",
        {
          label,
          hostID: host.id,
          threadID,
          relayScopedProjectionID,
        }
      );
    }
  }
  for (const threadID of forbiddenThreadIDs) {
    if (rows.some((card) => cardThreadID(card) === threadID)) {
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
  const scenarioName = options.scenario;
  const isRootCatchupWindowContract = scenarioName === "root-catchup-window-contract";
  const routeEvents = [];
  const findings = [];
  const samples = [];
  const startedAtMs = Date.now();
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), `codex-dock-sim-${scenarioName}-`));
  const hostID = `sim-${scenarioName}-fixture`;
  const rowCount = isRootCatchupWindowContract ? 32 : 18;
  const sourceRows = Array.from({ length: rowCount }, (_, index) => fixtureThread(
    `sim-${scenarioName}-${String(index + 1).padStart(2, "0")}`,
    `Simulator ${scenarioName} row ${index + 1}`,
    10_000 - index
  ));

  const historyServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await new Promise((resolve) => historyServer.once("listening", resolve));
  historyServer.on("connection", (ws) => {
    ws.on("message", (data) => {
      const message = JSON.parse(data.toString());
      if (message.method === "initialize") {
        sendFixtureResult(ws, message.id, {
          userAgent: `codex-sim-${scenarioName}-fixture`,
          codexHome: tempDir,
          platformFamily: "unix",
          platformOs: "macos",
        });
      } else if (message.method === "thread/list") {
        sendFixtureResult(ws, message.id, {
          data: activeFixtureRows(message, sourceRows),
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
    hostName: `Simulator ${scenarioName} Fixture`,
    hostEndpoint: "127.0.0.1:0",
    historyUrl: `ws://127.0.0.1:${historyServer.address().port}`,
    historyBearerToken: "history-token",
    advertiseBonjour: false,
    observabilityDir: false,
    relayStateDatabasePath: path.join(tempDir, "relay-state.sqlite"),
    relayStateAutoStart: false,
    relayStateSnapshotSoftLimitBytes: isRootCatchupWindowContract ? 4_096 : undefined,
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
  if (isRootCatchupWindowContract) {
    await relayConfig.relayStateEngine.reconcileDock({ reason: "controlled_simulator_root_catchup_preload" });
  }
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
        Array.isArray(snapshot?.rows)
          && snapshot.rows.length === rowCount
          && dockSnapshotThreadIndex(snapshot, sourceRows[0].id) === 0
          && dockSnapshotHasThread(snapshot, sourceRows[rowCount - 1].id)
      ),
    });
    if (!initialWait.ok) {
      transitionFailure(
        findings,
        `scenario_${scenarioName}_initial_rows_missing`,
        `${scenarioName} fixture did not expose all expected rows through the fixture relay stream`,
        { expectedRows: rowCount }
      );
    }
    if (isRootCatchupWindowContract && !streamProbe.notifications.some((notification) => notification.kind === "page")) {
      transitionFailure(
        findings,
        "scenario_root_catchup_window_page_missing",
        "root-catchup-window-contract did not force an explicit page update after the bounded snapshot"
      );
    }

    const initial = await freshComparison({ streamProbe, options: fixtureOptions, routeEvents });
    findings.push(...scenarioComparisonFindings({ phase: `${scenarioName}-initial`, comparison: initial.comparison }));
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
      scenario: scenarioName,
      relayUrl,
      hosts: `127.0.0.1:${relayPort}`,
      target: {
        sourceHostID: hostID,
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
    findings.push(...scenarioComparisonFindings({ phase: `${scenarioName}-checkpoint`, comparison: checkpoint.comparison }));
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
      scenario: scenarioName,
      startedAt: new Date(startedAtMs).toISOString(),
      endedAt: new Date().toISOString(),
      relayUrl,
      summary: {
        ok: scenarioOK,
        clientPathOK: scenarioOK,
        scenario: scenarioName,
        scenarioOK,
        scenarioCount: 1,
        scenarioTransitionCount: 0,
        implementedScenarios: [scenarioName],
        unimplementedRequiredScenarios: [],
        failures: findings.length,
        clientPathRouteCounts: clientPathEvidence.routeCounts,
      },
      samples,
      scenarios: [{
        id: scenarioName,
        ok: scenarioOK,
        actuator: {
          type: isRootCatchupWindowContract
            ? "controlled bounded root snapshot plus explicit page catch-up through real relay and simulator checkpoint sweep"
            : "controlled large Dock list through real relay and simulator checkpoint sweep",
          routes: isRootCatchupWindowContract ? ["dock/subscribe", "dock/update"] : ["dock/subscribe"],
          clientExercised: true,
          note: "The fixture exposes enough Dock rows that the actual simulator checkpoint sweep must scroll and compare rows beyond the initial viewport.",
        },
        target: {
          sourceHostID: hostID,
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

    writeProofReport(options.jsonOut, report);
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
  const scenarioName = options.scenario;
  const isCurrentWorkVisible = scenarioName === "current-work-visible";
  const routeEvents = [];
  const findings = [];
  const transitions = [];
  const samples = [];
  const startedAtMs = Date.now();
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), `codex-dock-sim-${scenarioName}-`));
  const hostID = `sim-${scenarioName}-fixture`;
  const stableThreadID = `sim-${scenarioName}-stable`;
  const movingThreadID = `sim-${scenarioName}-moving`;
  const newThreadID = isCurrentWorkVisible ? `sim-${scenarioName}-loaded-work` : `sim-${scenarioName}-new`;
  const updatedPreview = isCurrentWorkVisible
    ? "Simulator current work advanced while loaded"
    : "Simulator fixture existing row after new turn";
  let sourceRows = [
    fixtureThread(stableThreadID, "Simulator fixture stable row", 200),
    fixtureThread(movingThreadID, "Simulator fixture moving row before update", 100),
  ];
  let currentWorkRow = fixtureThread(newThreadID, "Simulator current work absent from thread list", 300);
  let loadedThreadIDs = [];
  const allRows = () => isCurrentWorkVisible ? [...sourceRows, currentWorkRow] : sourceRows;

  const historyServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await new Promise((resolve) => historyServer.once("listening", resolve));
  historyServer.on("connection", (ws) => {
    ws.on("message", (data) => {
      const message = JSON.parse(data.toString());
      if (message.method === "initialize") {
        sendFixtureResult(ws, message.id, {
          userAgent: `codex-sim-${scenarioName}-fixture`,
          codexHome: tempDir,
          platformFamily: "unix",
          platformOs: "macos",
        });
      } else if (message.method === "thread/list") {
        sendFixtureResult(ws, message.id, {
          data: activeFixtureRows(message, sourceRows),
          nextCursor: null,
          backwardsCursor: null,
        });
      } else if (message.method === "thread/loaded/list") {
        sendFixtureResult(ws, message.id, { data: loadedThreadIDs, nextCursor: null });
      } else if (message.method === "thread/read" || message.method === "thread/resume") {
        sendFixtureThreadRead(ws, message, fixtureRowForMessage(allRows(), message));
      } else if (message.method === "thread/turns/list") {
        sendFixtureThreadTurnsList(ws, message, fixtureRowForMessage(allRows(), message));
      }
    });
  });

  const relayConfig = {
    listenHost: "127.0.0.1",
    port: 0,
    phoneAuth: "none",
    hostId: hostID,
    hostName: `Simulator ${scenarioName} Fixture`,
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
      predicate: (snapshot) => isCurrentWorkVisible
        ? (
          dockSnapshotThreadIndex(snapshot, stableThreadID) === 0
          && dockSnapshotThreadIndex(snapshot, movingThreadID) === 1
          && !dockSnapshotHasThread(snapshot, newThreadID)
        )
        : (
          dockSnapshotThreadIndex(snapshot, stableThreadID) === 0
          && dockSnapshotThreadIndex(snapshot, movingThreadID) === 1
        ),
    });
    if (!initialWait.ok) {
      transitionFailure(
        findings,
        `scenario_${scenarioName}_initial_order_missing`,
        `initial ${scenarioName} fixture rows did not appear in the expected Dock order before simulator launch`,
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
      scenario: scenarioName,
      relayUrl,
      hosts: `127.0.0.1:${relayPort}`,
      target: {
        sourceHostID: hostID,
        stableThreadID,
        movingThreadID,
        newThreadID,
      },
      at: new Date().toISOString(),
    });
    await waitForFile(options.uiReadyIn, options.waitTimeoutMs, "simulator UI sampler readiness");
    await sleep(Math.min(Math.max(options.scenarioHoldMs, 500), 1_500));

    const newStartedAtMs = Date.now();
    if (isCurrentWorkVisible) {
      loadedThreadIDs = [newThreadID];
      await relayConfig.relayStateEngine.reconcileDock({ reason: "controlled_simulator_current_work_loaded_session" });
    } else {
      sourceRows = [
        fixtureThread(newThreadID, "Simulator fixture newly created row", 300),
        fixtureThread(stableThreadID, "Simulator fixture stable row", 200),
        fixtureThread(movingThreadID, "Simulator fixture moving row before update", 100),
      ];
      await relayConfig.relayStateEngine.reconcileDock({ reason: "controlled_simulator_thread_activity_new_thread" });
    }
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
      transitionFailure(findings, `scenario_${scenarioName}_new_thread_not_seen`, "new or loaded thread did not appear at the top of the fixture relay stream", {
        threadID: newThreadID,
      });
    } else if (newLag.exceeded) {
      transitionFailure(findings, `scenario_${scenarioName}_new_thread_lag_exceeded`, "new or loaded thread appeared after the relay lag budget", {
        observedLagMs: newLag.lag_change_to_relay_ms,
        maxStreamLagMs: options.maxStreamLagMs,
      });
    }
    const newComparison = await freshComparison({ streamProbe, options: fixtureOptions, routeEvents });
    findings.push(...scenarioComparisonFindings({ phase: "new-thread", comparison: newComparison.comparison }));
    transitions.push({
      name: "new-thread",
      kind: isCurrentWorkVisible ? "current-work-loaded-session" : "new-thread",
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
    if (isCurrentWorkVisible) {
      currentWorkRow = fixtureThread(newThreadID, updatedPreview, 500);
      await relayConfig.relayStateEngine.reconcileDock({ reason: "controlled_simulator_current_work_live_advance" });
    } else {
      sourceRows = [
        fixtureThread(movingThreadID, updatedPreview, 400),
        fixtureThread(newThreadID, "Simulator fixture newly created row", 300),
        fixtureThread(stableThreadID, "Simulator fixture stable row", 200),
      ];
      await relayConfig.relayStateEngine.reconcileDock({ reason: "controlled_simulator_thread_activity_new_turn_order" });
    }
    const turnWait = await waitForStreamCondition({
      streamProbe,
      timeoutMs: options.dockCollectionTimeoutMs,
      predicate: (snapshot) => {
        const targetThreadID = isCurrentWorkVisible ? newThreadID : movingThreadID;
        const card = dockSnapshotCardForThread(snapshot, targetThreadID);
        return dockSnapshotThreadIndex(snapshot, targetThreadID) === 0
          && (isCurrentWorkVisible || dockSnapshotThreadIndex(snapshot, newThreadID) === 1)
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
      transitionFailure(findings, `scenario_${scenarioName}_new_turn_order_not_seen`, "existing or loaded thread update did not move the row to the top in the fixture relay stream", {
        threadID: isCurrentWorkVisible ? newThreadID : movingThreadID,
      });
    } else if (turnLag.exceeded) {
      transitionFailure(findings, `scenario_${scenarioName}_new_turn_order_lag_exceeded`, "existing or loaded thread update moved order after the relay lag budget", {
        observedLagMs: turnLag.lag_change_to_relay_ms,
        maxStreamLagMs: options.maxStreamLagMs,
      });
    }
    const turnComparison = await freshComparison({ streamProbe, options: fixtureOptions, routeEvents });
    findings.push(...scenarioComparisonFindings({ phase: "new-turn-order", comparison: turnComparison.comparison }));
    transitions.push({
      name: "new-turn-order",
      kind: isCurrentWorkVisible ? "current-work-live-advance" : "new-turn-order",
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
      scenario: scenarioName,
      startedAt: new Date(startedAtMs).toISOString(),
      endedAt: new Date().toISOString(),
      relayUrl,
      summary: {
        ok: scenarioOK,
        clientPathOK: scenarioOK,
        scenario: scenarioName,
        scenarioOK,
        scenarioCount: 1,
        scenarioTransitionCount: transitions.length,
        implementedScenarios: [scenarioName],
        unimplementedRequiredScenarios: [],
        failures: findings.length,
        clientPathRouteCounts: clientPathEvidence.routeCounts,
      },
      samples,
      scenarios: [{
        id: scenarioName,
        ok: scenarioOK,
        target: {
          sourceHostID: hostID,
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

    writeProofReport(options.jsonOut, report);
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

async function runServerRenameNotificationScenario(options) {
  const scenarioName = "server-rename-notification";
  const routeEvents = [];
  const findings = [];
  const transitions = [];
  const samples = [];
  const startedAtMs = Date.now();
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), `codex-dock-sim-${scenarioName}-`));
  const hostID = `sim-${scenarioName}-fixture`;
  const stableThreadID = `sim-${scenarioName}-stable`;
  const renamedThreadID = `sim-${scenarioName}-renamed`;
  const initialTitle = "Simulator server rename before notification";
  const renamedTitle = "Simulator server rename after notification";
  const initializedClients = new Set();
  let notificationSentAtMs = null;
  let sourceRows = [
    {
      ...fixtureThread(stableThreadID, "Simulator server rename stable row", 200),
      name: "Simulator server rename stable title",
    },
    {
      ...fixtureThread(renamedThreadID, "Simulator server rename row preview", 100),
      name: initialTitle,
    },
  ];
  const rowForThread = (threadID) => sourceRows.find((row) => row.id === threadID) || null;
  const emitThreadNameUpdated = (threadID, threadName) => {
    let sent = 0;
    for (const ws of initializedClients) {
      if (ws.readyState !== WebSocket.OPEN) {
        continue;
      }
      ws.send(JSON.stringify({
        jsonrpc: "2.0",
        method: "thread/name/updated",
        params: { threadId: threadID, threadName },
      }));
      sent += 1;
    }
    recordClientRoute(
      routeEvents,
      "thread/name/updated",
      "fixture upstream emitted server-side thread rename notification",
      { threadID, count: sent }
    );
    return sent;
  };

  const historyServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await new Promise((resolve) => historyServer.once("listening", resolve));
  historyServer.on("connection", (ws) => {
    ws.on("close", () => {
      initializedClients.delete(ws);
    });
    ws.on("message", (data) => {
      const message = JSON.parse(data.toString());
      if (message.method === "initialize") {
        recordClientRoute(routeEvents, "initialize", "relay initialized server-rename fixture upstream", { threadID: renamedThreadID });
        sendFixtureResult(ws, message.id, {
          userAgent: `codex-sim-${scenarioName}-fixture`,
          codexHome: tempDir,
          platformFamily: "unix",
          platformOs: "macos",
        });
      } else if (message.method === "initialized") {
        initializedClients.add(ws);
        recordClientRoute(routeEvents, "initialized", "relay sent initialized notification to server-rename fixture upstream", { threadID: renamedThreadID });
      } else if (message.method === "thread/list") {
        sendFixtureResult(ws, message.id, {
          data: activeFixtureRows(message, sourceRows),
          nextCursor: null,
          backwardsCursor: null,
        });
      } else if (message.method === "thread/loaded/list") {
        sendFixtureResult(ws, message.id, { data: [], nextCursor: null });
      } else if (message.method === "thread/read" || message.method === "thread/resume") {
        sendFixtureThreadRead(ws, message, rowForThread(fixtureMessageThreadID(message)));
      } else if (message.method === "thread/turns/list") {
        sendFixtureThreadTurnsList(ws, message, rowForThread(fixtureMessageThreadID(message)));
      } else if (message.method === "thread/name/set") {
        transitionFailure(
          findings,
          "scenario_server_rename_notification_client_rename_request_seen",
          "server-side rename notification scenario unexpectedly sent a client thread/name/set request",
          { threadID: fixtureMessageThreadID(message) }
        );
        sendFixtureResult(ws, message.id, {});
      }
    });
  });

  const relayConfig = {
    listenHost: "127.0.0.1",
    port: 0,
    phoneAuth: "none",
    hostId: hostID,
    hostName: "Simulator Server Rename Fixture",
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
      predicate: (snapshot) => {
        const renamedCard = dockSnapshotCardForThread(snapshot, renamedThreadID);
        return dockSnapshotThreadIndex(snapshot, stableThreadID) === 0
          && dockSnapshotThreadIndex(snapshot, renamedThreadID) === 1
          && renamedCard?.title === initialTitle;
      },
    });
    if (!initialWait.ok) {
      transitionFailure(
        findings,
        "scenario_server_rename_notification_initial_title_missing",
        "initial server-rename fixture rows did not appear with the expected title before simulator launch",
        { threadID: renamedThreadID }
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
      scenario: scenarioName,
      relayUrl,
      hosts: `127.0.0.1:${relayPort}`,
      target: {
        sourceHostID: hostID,
        stableThreadID,
        threadID: renamedThreadID,
      },
      at: new Date().toISOString(),
    });
    await waitForFile(options.uiReadyIn, options.waitTimeoutMs, "simulator UI sampler readiness");
    await sleep(Math.min(Math.max(options.scenarioHoldMs, 500), 1_500));

    notificationSentAtMs = Date.now();
    sourceRows = [
      {
        ...fixtureThread(renamedThreadID, "Simulator server rename row preview", 300),
        name: renamedTitle,
      },
      {
        ...fixtureThread(stableThreadID, "Simulator server rename stable row", 200),
        name: "Simulator server rename stable title",
      },
    ];
    const notificationCount = emitThreadNameUpdated(renamedThreadID, renamedTitle);
    if (notificationCount < 1) {
      transitionFailure(
        findings,
        "scenario_server_rename_notification_no_upstream_client",
        "server-side rename notification scenario had no initialized upstream relay client to notify",
        { threadID: renamedThreadID }
      );
    }

    const renameWait = await waitForStreamCondition({
      streamProbe,
      timeoutMs: options.dockCollectionTimeoutMs,
      predicate: (snapshot) => {
        const renamedCard = dockSnapshotCardForThread(snapshot, renamedThreadID);
        return dockSnapshotThreadIndex(snapshot, renamedThreadID) === 0
          && dockSnapshotThreadIndex(snapshot, stableThreadID) === 1
          && renamedCard?.title === renamedTitle;
      },
    });
    const renameLag = scenarioLagSummary({
      transition: "server-rename-notification",
      startedAtMs: notificationSentAtMs,
      acknowledgedAtMs: notificationSentAtMs,
      observedAtMs: renameWait.observedAtMs,
      maxStreamLagMs: options.maxStreamLagMs,
    });
    if (!renameWait.ok) {
      transitionFailure(
        findings,
        "scenario_server_rename_notification_title_not_seen",
        "server-side thread/name/updated notification did not change the Dock stream card title",
        { threadID: renamedThreadID }
      );
    } else if (renameLag.exceeded) {
      transitionFailure(
        findings,
        "scenario_server_rename_notification_lag_exceeded",
        "server-side rename notification changed the Dock stream after the relay lag budget",
        {
          observedLagMs: renameLag.lag_change_to_relay_ms,
          maxStreamLagMs: options.maxStreamLagMs,
        }
      );
    }
    const renameComparison = await freshComparison({ streamProbe, options: fixtureOptions, routeEvents });
    findings.push(...scenarioComparisonFindings({ phase: "server-rename-notification", comparison: renameComparison.comparison }));
    transitions.push({
      name: "server-rename-notification",
      kind: "server-thread-name-updated-notification",
      iteration: 1,
      route: "dock/update",
      wait: renameWait,
      lag: renameLag,
      freshDock: sanitizeDockSnapshotForReport(renameComparison.freshDock),
      streamComparison: renameComparison.comparison,
      streamComparisonAttempts: renameComparison.attempts,
    });

    const clientPathEvidence = summarizeClientPathEvents([...streamProbe.routeEvents, ...routeEvents]);
    findings.push(...requiredRouteFindings(
      clientPathEvidence,
      ["dock/subscribe", "dock/update"]
    ));
    const scenarioOK = !findings.some((finding) => finding.severity === "error" || finding.severity === "warning");
    const report = {
      schemaVersion: 1,
      kind: "codex-dock-controlled-simulator-scenario-relay-report",
      mode: "scenario",
      scenario: scenarioName,
      startedAt: new Date(startedAtMs).toISOString(),
      endedAt: new Date().toISOString(),
      relayUrl,
      summary: {
        ok: scenarioOK,
        clientPathOK: scenarioOK,
        scenario: scenarioName,
        scenarioOK,
        scenarioCount: 1,
        scenarioTransitionCount: transitions.length,
        implementedScenarios: [scenarioName],
        unimplementedRequiredScenarios: [],
        failures: findings.length,
        clientPathRouteCounts: clientPathEvidence.routeCounts,
      },
      samples,
      scenarios: [{
        id: scenarioName,
        ok: scenarioOK,
        target: {
          sourceHostID: hostID,
          stableThreadID,
          threadID: renamedThreadID,
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

    writeProofReport(options.jsonOut, report);
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
          data: activeFixtureRows(message, sourceRows),
          nextCursor: null,
          backwardsCursor: null,
        });
      } else if (message.method === "thread/loaded/list") {
        sendFixtureResult(ws, message.id, { data: [], nextCursor: null });
      } else if (message.method === "thread/read" || message.method === "thread/resume") {
        sendFixtureThreadRead(ws, message, fixtureRowForMessage(sourceRows, message));
      } else if (message.method === "thread/turns/list") {
        sendFixtureThreadTurnsList(ws, message, fixtureRowForMessage(sourceRows, message));
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
        sourceHostID: hostID,
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
          sourceHostID: hostID,
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

    writeProofReport(options.jsonOut, report);
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
          data: activeFixtureRows(message, sourceRows),
          nextCursor: null,
          backwardsCursor: null,
        });
      } else if (message.method === "thread/loaded/list") {
        sendFixtureResult(ws, message.id, { data: [], nextCursor: null });
      } else if (message.method === "thread/read" || message.method === "thread/resume") {
        if (!upstreamAvailable) {
          sendFixtureError(ws, message.id, "controlled source refresh failure");
          return;
        }
        sendFixtureThreadRead(ws, message, fixtureRowForMessage(sourceRows, message));
      } else if (message.method === "thread/turns/list") {
        if (!upstreamAvailable) {
          sendFixtureError(ws, message.id, "controlled source refresh failure");
          return;
        }
        sendFixtureThreadTurnsList(ws, message, fixtureRowForMessage(sourceRows, message));
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
        sourceHostID: hostID,
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
          sourceHostID: hostID,
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

    writeProofReport(options.jsonOut, report);
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
  const liveThreadRow = {
    id: threadID,
    sessionId: sessionID,
    preview: "Simulator live row before lease expiry",
    updatedAt: 100,
    source: "cli",
    status: { type: "active", activeFlags: [] },
  };
  const storedThreadRow = fixtureThread(threadID, "Simulator stored row after lease expiry", 100);

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
        sendFixtureThreadRead(ws, message, liveThreadRow);
      } else if (message.method === "thread/turns/list") {
        sendFixtureThreadTurnsList(ws, message, liveThreadRow);
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
          data: activeFixtureRows(message, [storedThreadRow]),
          nextCursor: null,
          backwardsCursor: null,
        });
      } else if (message.method === "thread/loaded/list") {
        sendFixtureResult(ws, message.id, { data: [], nextCursor: null });
      } else if (message.method === "thread/read" || message.method === "thread/resume") {
        sendFixtureThreadRead(ws, message, storedThreadRow);
      } else if (message.method === "thread/turns/list") {
        sendFixtureThreadTurnsList(ws, message, storedThreadRow);
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
        sourceHostID: hostID,
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
    const leaseExpiresAtMs = relayConfig.relayStateEngine.store.nextUnpublishedLiveLeaseExpiryMs(hostID, 0);
    if (liveRunningHoldMs > 0) {
      await sleep(liveRunningHoldMs);
    }

    liveRowsEnabled = false;
    const expireStartedAtMs = Date.now();
    const expiryBoundaryMs = Number.isFinite(Number(leaseExpiresAtMs)) && Number(leaseExpiresAtMs) > 0
      ? Number(leaseExpiresAtMs)
      : expireStartedAtMs;
    const expiredWait = await waitForStreamCondition({
      streamProbe,
      timeoutMs: options.dockCollectionTimeoutMs,
      predicate: (snapshot) => dockSnapshotCardForThread(snapshot, threadID)?.status === "dormant",
    });
    const expiredLag = scenarioLagSummary({
      transition: "live-lease-expiry",
      startedAtMs: expiryBoundaryMs,
      acknowledgedAtMs: expiryBoundaryMs,
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
    if (expiredCard?.status !== "dormant") {
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
          sourceHostID: hostID,
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

    writeProofReport(options.jsonOut, report);
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
  // Keep activity times distinct so this scenario proves host scoping and live
  // updates, not an arbitrary cross-host tie-break for equal timestamps.
  let hostARows = [
    fixtureThread(sharedThreadID, "Simulator shared id from host A", 250),
    fixtureThread(hostAOnlyThreadID, "Simulator only host A", 100),
  ];
  let hostBRows = [
    fixtureThread(sharedThreadID, "Simulator shared id from host B", 200),
    fixtureThread(hostBOnlyThreadID, "Simulator only host B", 50),
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
      fixtureThread(sharedThreadID, "Simulator shared id from host A", 250),
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

    writeProofReport(options.jsonOut, report);
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
          data: activeFixtureRows(message, sourceRows),
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
        sourceHostID: hostID,
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
      seq: Number(afterSnapshot.seq || 0) + 10,
      sourceHostID: afterSnapshot.sourceHostID,
      freshness: afterSnapshot.freshness,
      rows: afterSnapshot.rows || [],
      projectionIDs: [],
      totalRows: Number(afterSnapshot.totalRows || afterSnapshot.rows?.length || 0),
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
          sourceHostID: hostID,
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

    writeProofReport(options.jsonOut, report);
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
        const rows = activeFixtureRows(
          message,
          sourceRows.filter((row) => threadMatchesSourceKinds(row, sourceKinds)),
        );
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
        sourceHostID: hostID,
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
      predicate: (snapshot) => (
        dockSnapshotHasThread(snapshot, parentThreadID)
        && !dockSnapshotHasThread(snapshot, childThreadID)
      ),
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
        "scenario_spawn_edge_child_leaked_or_parent_missing",
        "spawned child row was not kept out of the human-only fixture relay stream",
        { parentThreadID, childThreadID }
      );
    } else if (spawnLag.exceeded) {
      transitionFailure(
        findings,
        "scenario_spawn_edge_lag_exceeded",
        "human-only spawn-edge state settled after the relay lag budget",
        {
          observedLagMs: spawnLag.lag_change_to_relay_ms,
          maxStreamLagMs: options.maxStreamLagMs,
        }
      );
    }

    const spawnComparison = await freshComparison({ streamProbe, options: fixtureOptions, routeEvents });
    findings.push(...scenarioComparisonFindings({ phase: "spawn-edge", comparison: spawnComparison.comparison }));
    const freshChildCard = dockSnapshotCardForThread(spawnComparison.freshDock, childThreadID);
    if (freshChildCard) {
      transitionFailure(
        findings,
        "scenario_spawn_edge_fresh_child_leaked",
        "spawned child row reached a fresh human-only Dock client-path subscription",
        {
          childThreadID,
          actualLane: freshChildCard.lane || null,
          actualSourceKind: freshChildCard.sourceKind || null,
        }
      );
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
          type: "controlled app-server subagent spawn absence fixture through real relay Dock routes",
          routes: ["dock/subscribe", "dock/update"],
          clientExercised: true,
          note: "The fixture changes app-server thread/list rows to model a new subagent spawn; proof expects the child to stay absent from the human-only Dock routes and literal simulator row accessibility values the client uses.",
        },
        target: {
          sourceHostID: hostID,
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

    writeProofReport(options.jsonOut, report);
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

async function runDetailReconnectScenario(options) {
  const scenarioName = options.scenario;
  const isForegroundResumeScenario = scenarioName === "foreground-resume-all-surfaces";
  const routeEvents = [];
  const simulatorRouteEvents = [];
  const findings = [];
  const transitions = [];
  const samples = [];
  const startedAtMs = Date.now();
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), `codex-dock-sim-${scenarioName}-`));
  const hostID = `sim-${scenarioName}-fixture`;
  const threadID = `sim-${scenarioName}-thread`;
  const threadRow = fixtureThread(threadID, `Simulator ${scenarioName} fixture row`, 100);
  const initialTurn = fixtureTurn("turn-reconnect-initial", 1_700_000_001, [
    fixtureAgentMessageItem("agent-initial", "Simulator detail before reconnect"),
  ]);
  const recoveredTurn = fixtureTurn("turn-reconnect-recovered", 1_700_000_002, [
    fixtureAgentMessageItem("agent-recovered", "Simulator detail after reconnect"),
  ]);
  const expectedInitialEventIDs = ["turn-reconnect-initial-agent-initial-agent"];
  const expectedRecoveredEventIDs = [
    "turn-reconnect-recovered-agent-recovered-agent",
    ...expectedInitialEventIDs,
  ];
  let historicalTurns = [initialTurn];
  let initialDetailWs = null;
  let readCallCount = 0;
  let turnsListCallCount = 0;
  let resumeCallCount = 0;
  let detailLoadedAtMs = null;
  let uiReadyAtMs = null;
  let recoveryStartedAtMs = null;
  let rehydratedAtMs = null;
  let initialProjectionWitness = null;
  let rehydratedProjectionWitness = null;

  const historyServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await new Promise((resolve) => historyServer.once("listening", resolve));
  historyServer.on("connection", (ws) => {
    ws.on("message", (data) => {
      const message = JSON.parse(data.toString());
      if (message.method === "initialize") {
        recordClientRoute(routeEvents, "initialize", "relay initialized detail-reconnect fixture upstream", { threadID });
        sendFixtureResult(ws, message.id, {
          userAgent: `codex-sim-${scenarioName}-fixture`,
          codexHome: tempDir,
          platformFamily: "unix",
          platformOs: "macos",
        });
      } else if (message.method === "initialized") {
        recordClientRoute(routeEvents, "initialized", "relay sent initialized notification to detail-reconnect fixture upstream", { threadID });
      } else if (message.method === "thread/list") {
        sendFixtureResult(ws, message.id, {
          data: activeFixtureRows(message, [threadRow]),
          nextCursor: null,
          backwardsCursor: null,
        });
      } else if (message.method === "thread/loaded/list") {
        sendFixtureResult(ws, message.id, { data: [], nextCursor: null });
      } else if (message.method === "thread/read") {
        readCallCount += 1;
        recordClientRoute(routeEvents, "thread/read", "relay read target thread detail from fixture upstream", {
          threadID: message.params?.threadId || threadID,
          includeTurns: message.params?.includeTurns ?? null,
          call: readCallCount,
        });
        sendFixtureResult(ws, message.id, {
          thread: {
            ...threadRow,
            id: message.params?.threadId || threadID,
            turns: [],
          },
        });
      } else if (message.method === "thread/turns/list") {
        turnsListCallCount += 1;
        recordClientRoute(routeEvents, "thread/turns/list", "relay drained historical thread turns from fixture upstream", {
          threadID: message.params?.threadId || threadID,
          itemsView: message.params?.itemsView ?? null,
          call: turnsListCallCount,
        });
        sendFixtureResult(ws, message.id, {
          data: historicalTurns,
          nextCursor: null,
          backwardsCursor: null,
        });
      } else if (message.method === "thread/resume") {
        resumeCallCount += 1;
        recordClientRoute(routeEvents, "thread/resume", "relay resumed target thread live detail from fixture upstream", {
          threadID: message.params?.threadId || threadID,
          excludeTurns: message.params?.excludeTurns ?? null,
          call: resumeCallCount,
        });
        sendFixtureResult(ws, message.id, {
          thread: {
            ...threadRow,
            id: message.params?.threadId || threadID,
            turns: [],
          },
        });
        if (resumeCallCount === 1) {
          initialDetailWs = ws;
          detailLoadedAtMs = Date.now();
        }
      }
    });
  });

  const relayConfig = {
    listenHost: "127.0.0.1",
    port: 0,
    phoneAuth: "none",
    hostId: hostID,
    hostName: `Simulator ${scenarioName} Fixture`,
    hostEndpoint: "127.0.0.1:0",
    historyUrl: `ws://127.0.0.1:${historyServer.address().port}`,
    historyBearerToken: "history-token",
    advertiseBonjour: false,
    observabilityDir: false,
    relayStateDatabasePath: path.join(tempDir, "relay-state.sqlite"),
    relayStateAutoStart: false,
    projectionWitnessEnabled: true,
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
  const simulatorProxy = await startSimulatorAppRouteProxy({
    targetUrl: relayUrl,
    routeEvents: simulatorRouteEvents,
    label: "detail-reconnect",
  });
  const fixtureOptions = {
    ...options,
    relayUrl,
    codexHome: tempDir,
    sqliteHome: tempDir,
    detail: "none",
  };
  const simulatorProxyOptions = {
    ...fixtureOptions,
    relayUrl: simulatorProxy.url,
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
        "scenario_detail_reconnect_initial_row_missing",
        "detail-reconnect fixture row did not appear in the fixture relay stream before simulator launch",
        { threadID }
      );
    }
    const initial = await waitForStableDockClientPathThread({
      streamProbe,
      options: simulatorProxyOptions,
      routeEvents,
      threadID,
      timeoutMs: options.dockCollectionTimeoutMs,
    });
    if (!initial.ok) {
      const detail = {
        threadID,
        freshDockRows: Array.isArray(initial.freshDock?.rows) ? initial.freshDock.rows.length : null,
        freshDockFreshness: initial.freshDock?.freshness || null,
        freshDockCollection: initial.freshDock?.collection || null,
        comparison: initial.comparison || null,
        attempts: initial.attempts || [],
        streamSnapshot: sanitizeDockSnapshotForReport(streamProbe.snapshot()),
        routeCounts: summarizeClientPathEvents(routeEvents).routeCounts,
      };
      transitionFailure(
        findings,
        "scenario_detail_reconnect_app_path_initial_row_missing",
        "detail-reconnect fixture app-facing proxy path did not expose the target Dock row before simulator launch",
        detail
      );
      throw new Error(`detail-reconnect app-facing proxy path did not expose the target Dock row before simulator launch: ${JSON.stringify(detail)}`);
    }
    findings.push(...scenarioComparisonFindings({ phase: "detail-reconnect-initial", comparison: initial.comparison }));
    samples.push({
      sampleIndex: 0,
      startedAt: new Date(startedAtMs).toISOString(),
      finishedAt: new Date().toISOString(),
      freshDock: sanitizeDockSnapshotForReport(initial.freshDock),
    });

    writeJSON(options.readyOut, {
      ready: true,
      scenario: scenarioName,
      relayUrl,
      simulatorRelayUrl: simulatorProxy.url,
      hosts: simulatorProxy.endpoint,
      target: {
        sourceHostID: hostID,
        threadID,
      },
      uiConfig: {
        openHostID: hostID,
        openThreadID: threadID,
        detailFilter: "all",
        detailCheckpointSweep: true,
        foregroundCycleBeforeReady: isForegroundResumeScenario,
        foregroundResumeDelayMS: isForegroundResumeScenario
          ? Math.max(options.scenarioHoldMs + 750, 1_250)
          : undefined,
      },
      at: new Date().toISOString(),
    });
    await waitForFile(options.uiReadyIn, options.waitTimeoutMs, "simulator UI detail reconnect sampler readiness");
    uiReadyAtMs = Date.now();

    const detailWaitTimeoutMs = Math.min(options.dockCollectionTimeoutMs, options.waitTimeoutMs);
    const detailSubscribeWait = await waitForRecordedRouteEvent({
      events: simulatorRouteEvents,
      route: "thread/detail/subscribe",
      source: "simulatorAppProxy",
      boundary: "simulatorAppToRelay",
      afterMs: startedAtMs,
      timeoutMs: detailWaitTimeoutMs,
    });
    if (!detailSubscribeWait.ok) {
      transitionFailure(
        findings,
        "scenario_detail_reconnect_not_opened",
        "simulator app did not open the controlled detail session through thread/detail/subscribe before reconnect",
        { threadID, timeoutMs: detailWaitTimeoutMs }
      );
    }

    if (detailSubscribeWait.ok) {
      initialProjectionWitness = await waitForDetailProjectionWitness({
        client: streamProbe.client,
        sourceHostID: hostID,
        threadID,
        minProjectionCount: expectedInitialEventIDs.length,
        timeoutMs: detailWaitTimeoutMs,
      });
      if (initialProjectionWitness?.byteEquivalentToDownstream !== true) {
        transitionFailure(
          findings,
          "scenario_detail_reconnect_initial_projection_witness_missing",
          "detail-reconnect initial state did not produce byte-equivalent relay projection witness rows",
          { threadID, minimumRelayProjectionCount: expectedInitialEventIDs.length }
        );
      }

      await sleep(Math.max(options.scenarioHoldMs, 500));
      historicalTurns = [initialTurn, recoveredTurn];
      recoveryStartedAtMs = Date.now();
      initialDetailWs?.terminate();
    }

    const rehydratedRouteWait = recoveryStartedAtMs === null
      ? {
        ok: false,
        route: "thread/detail/resync",
        source: "simulatorAppProxy",
        boundary: "simulatorAppToRelay",
        observedAt: null,
        observedAtMs: null,
        timeoutMs: detailWaitTimeoutMs,
        event: null,
      }
      : await waitForRecordedRouteEvent({
        events: simulatorRouteEvents,
        route: "thread/detail/resync",
        source: "simulatorAppProxy",
        boundary: "simulatorAppToRelay",
        afterMs: recoveryStartedAtMs,
        timeoutMs: detailWaitTimeoutMs,
      });
    if (!rehydratedRouteWait.ok) {
      transitionFailure(
        findings,
        "scenario_detail_reconnect_rehydrate_missing",
        "simulator app did not request canonical thread/detail/resync after relay upstream recovery",
        {
          threadID,
          timeoutMs: detailWaitTimeoutMs,
          readCallCount,
          turnsListCallCount,
          resumeCallCount,
        }
      );
    }

    if (rehydratedRouteWait.ok) {
      rehydratedProjectionWitness = await waitForDetailProjectionWitness({
        client: streamProbe.client,
        sourceHostID: hostID,
        threadID,
        minProjectionCount: expectedRecoveredEventIDs.length,
        timeoutMs: detailWaitTimeoutMs,
      });
      rehydratedAtMs = Date.now();
      if (rehydratedProjectionWitness?.byteEquivalentToDownstream !== true) {
        transitionFailure(
          findings,
          "scenario_detail_reconnect_rehydrated_projection_witness_missing",
          "detail-reconnect rehydrated state did not produce byte-equivalent relay projection witness rows",
          { threadID, minimumRelayProjectionCount: expectedRecoveredEventIDs.length }
        );
      }
    }

    transitions.push({
      name: "detail-reconnect-rehydrated",
      kind: "detail-reconnect-rehydrated",
      iteration: 1,
      route: "thread/detail/resync",
      wait: {
        ok: rehydratedRouteWait.ok && rehydratedProjectionWitness?.byteEquivalentToDownstream === true,
        observedAt: rehydratedAtMs ? new Date(rehydratedAtMs).toISOString() : null,
        observedAtMs: rehydratedAtMs,
      },
      lag: scenarioLagSummary({
        transition: "detail-reconnect-rehydrated",
        startedAtMs: recoveryStartedAtMs || detailLoadedAtMs || startedAtMs,
        acknowledgedAtMs: recoveryStartedAtMs || detailLoadedAtMs || startedAtMs,
        observedAtMs: rehydratedAtMs,
        maxStreamLagMs: options.maxStreamLagMs,
      }),
      routeCountsAtTransition: { readCallCount, turnsListCallCount, resumeCallCount },
      detailTruth: detailTruthFromWitness({
        kind: "detail-reconnect-rehydrated",
        sourceHostID: hostID,
        detailHostID: simulatorProxy.endpoint,
        threadID,
        witness: rehydratedProjectionWitness || initialProjectionWitness,
      }),
    });

    const simulatorClientPathEvidence = summarizeClientPathEvents(simulatorRouteEvents);
    findings.push(...requiredRouteFindings(
      simulatorClientPathEvidence,
      ["thread/detail/subscribe", "thread/detail/resync"]
    ));
    findings.push(...forbiddenSimulatorDetailRouteFindings(simulatorClientPathEvidence));
    const clientPathEvidence = summarizeClientPathEvents([
      ...streamProbe.routeEvents,
      ...routeEvents,
      ...simulatorRouteEvents,
    ]);

    const scenarioOK = !findings.some((finding) => finding.severity === "error" || finding.severity === "warning");
    const report = {
      schemaVersion: 1,
      kind: "codex-dock-controlled-simulator-scenario-relay-report",
      mode: "scenario",
      scenario: scenarioName,
      startedAt: new Date(startedAtMs).toISOString(),
      endedAt: new Date().toISOString(),
      relayUrl,
      summary: {
        ok: scenarioOK,
        clientPathOK: scenarioOK,
        scenario: scenarioName,
        scenarioOK,
        scenarioCount: 1,
        scenarioTransitionCount: transitions.length,
        implementedScenarios: [scenarioName],
        unimplementedRequiredScenarios: [],
        failures: findings.length,
        clientPathRouteCounts: clientPathEvidence.routeCounts,
      },
      samples,
      scenarios: [{
        id: scenarioName,
        ok: scenarioOK,
        target: {
          sourceHostID: hostID,
          threadID,
          expectedInitialEventIDs,
          expectedRecoveredEventIDs,
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
      simulatorClientPathEvidence,
      findings,
      unsupportedFacts: [],
    };

    writeProofReport(options.jsonOut, report);
    if (options.summaryOut) {
      writeText(options.summaryOut, buildMarkdownSummary(report));
    }
    await waitForFile(options.stopIn, options.waitTimeoutMs, "simulator UI sampler completion");
    return report;
  } finally {
    await streamProbe.close().catch(() => null);
    await simulatorProxy.close().catch(() => null);
    await relay.close().catch(() => null);
    await closeWebSocketServer(historyServer).catch(() => null);
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

async function runDetailHistoryRequestScenario(options) {
  const scenarioName = options.scenario;
  const isReplayPressure = scenarioName === "detail-replay-pressure";
  const routeEvents = [];
  const simulatorRouteEvents = [];
  const findings = [];
  const transitions = [];
  const samples = [];
  const startedAtMs = Date.now();
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), `codex-dock-sim-${scenarioName}-`));
  const hostID = `sim-${scenarioName}-fixture`;
  const threadID = `sim-${scenarioName}-thread`;
  const requestID = isReplayPressure ? "approval-replay-pressure-1" : "approval-history-1";
  const requestTurnID = "turn-live-request";
  const requestItemID = "cmd-history-live";
  const requestCardID = projectionIDForCommandApprovalRequest({
    sourceHostID: hostID,
    threadID,
    turnID: requestTurnID,
    itemID: requestItemID,
  });
  const threadRow = fixtureThread(threadID, `Simulator ${scenarioName} fixture row`, 100);
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
  let detailWs = null;
  let detailLoadedAtMs = null;
  let liveUpdateSentAtMs = null;
  let replayPressureBurstSentAtMs = null;
  let replayPressureWitnessAtMs = null;
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
        recordClientRoute(routeEvents, "initialize", "relay initialized detail-history fixture upstream", { threadID });
        sendFixtureResult(ws, message.id, {
          userAgent: `codex-sim-${scenarioName}-fixture`,
          codexHome: tempDir,
          platformFamily: "unix",
          platformOs: "macos",
        });
      } else if (message.method === "initialized") {
        recordClientRoute(routeEvents, "initialized", "relay sent initialized notification to detail-history fixture upstream", { threadID });
      } else if (message.method === "thread/list") {
        sendFixtureResult(ws, message.id, {
          data: activeFixtureRows(message, [threadRow]),
          nextCursor: null,
          backwardsCursor: null,
        });
      } else if (message.method === "thread/loaded/list") {
        sendFixtureResult(ws, message.id, { data: [], nextCursor: null });
      } else if (message.method === "thread/read") {
        recordClientRoute(routeEvents, "thread/read", "relay read target thread detail from fixture upstream", {
          threadID: message.params?.threadId || threadID,
          includeTurns: message.params?.includeTurns ?? null,
        });
        sendFixtureResult(ws, message.id, {
          thread: {
            ...threadRow,
            id: message.params?.threadId || threadID,
            turns: [],
          },
        });
      } else if (message.method === "thread/turns/list") {
        turnsListCallCount += 1;
        const cursor = message.params?.cursor || null;
        recordClientRoute(routeEvents, "thread/turns/list", "relay drained paged historical thread turns from fixture upstream", {
          threadID: message.params?.threadId || threadID,
          cursor,
          call: turnsListCallCount,
          itemsView: message.params?.itemsView ?? null,
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
        recordClientRoute(routeEvents, "thread/resume", "relay resumed target thread live detail from fixture upstream", {
          threadID: message.params?.threadId || threadID,
          excludeTurns: message.params?.excludeTurns ?? null,
        });
        sendFixtureResult(ws, message.id, {
          thread: {
            ...threadRow,
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
        forwardedResponse = proofMessageSummary({
          id: message.id,
          result: message.result || null,
        }, { requestID });
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
            message: proofMessageSummary(notification, { requestID }),
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
    hostName: `Simulator ${scenarioName} Fixture`,
    hostEndpoint: "127.0.0.1:0",
    projectionWitnessEnabled: true,
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
  const simulatorProxy = await startSimulatorAppRouteProxy({
    targetUrl: relayUrl,
    routeEvents: simulatorRouteEvents,
    label: "detail-history-request",
  });
  const fixtureOptions = {
    ...options,
    relayUrl,
    codexHome: tempDir,
    sqliteHome: tempDir,
    detail: "none",
  };
  const simulatorProxyOptions = {
    ...fixtureOptions,
    relayUrl: simulatorProxy.url,
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
    const initial = await waitForStableDockClientPathThread({
      streamProbe,
      options: simulatorProxyOptions,
      routeEvents,
      threadID,
      timeoutMs: options.dockCollectionTimeoutMs,
    });
    if (!initial.ok) {
      const detail = {
        threadID,
        freshDockRows: Array.isArray(initial.freshDock?.rows) ? initial.freshDock.rows.length : null,
        freshDockFreshness: initial.freshDock?.freshness || null,
        freshDockCollection: initial.freshDock?.collection || null,
        comparison: initial.comparison || null,
        attempts: initial.attempts || [],
        streamSnapshot: sanitizeDockSnapshotForReport(streamProbe.snapshot()),
        routeCounts: summarizeClientPathEvents(routeEvents).routeCounts,
      };
      transitionFailure(
        findings,
        "scenario_detail_history_app_path_initial_row_missing",
        "detail-history fixture app-facing proxy path did not expose the target Dock row before simulator launch",
        detail
      );
      throw new Error(`detail-history app-facing proxy path did not expose the target Dock row before simulator launch: ${JSON.stringify(detail)}`);
    }
    findings.push(...scenarioComparisonFindings({ phase: "detail-history-initial", comparison: initial.comparison }));
    samples.push({
      sampleIndex: 0,
      startedAt: new Date(startedAtMs).toISOString(),
      finishedAt: new Date().toISOString(),
      freshDock: sanitizeDockSnapshotForReport(initial.freshDock),
    });

    writeJSON(options.readyOut, {
      ready: true,
      scenario: scenarioName,
      relayUrl,
      simulatorRelayUrl: simulatorProxy.url,
      hosts: simulatorProxy.endpoint,
      target: {
        sourceHostID: hostID,
        threadID,
        requestID,
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
    const projectionTransitionTimeoutMs = detailTransitionWitnessTimeoutMs(options, detailWaitTimeoutMs);
    const detailSubscribeWait = await waitForRecordedRouteEvent({
      events: simulatorRouteEvents,
      route: "thread/detail/subscribe",
      source: "simulatorAppProxy",
      boundary: "simulatorAppToRelay",
      afterMs: startedAtMs,
      timeoutMs: detailWaitTimeoutMs,
    });
    if (!detailSubscribeWait.ok) {
      transitionFailure(
        findings,
        "scenario_detail_history_detail_subscribe_missing",
        "simulator app did not open the controlled detail session through thread/detail/subscribe",
        { threadID, timeoutMs: detailWaitTimeoutMs }
      );
    }
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
        "relay upstream adapter did not exercise the paged thread/turns/list detail path",
        { threadID, turnsListCallCount }
      );
    }

    let initialProjectionWitness = null;
    let liveProjectionWitness = null;
    let replayPressureProjectionWitness = null;
    let requestProjectionWitness = null;
    let resolutionProjectionWitness = null;
    if (detailLoadedWait.ok && detailSubscribeWait.ok) {
      initialProjectionWitness = await waitForDetailProjectionWitness({
        client: streamProbe.client,
        sourceHostID: hostID,
        threadID,
        minProjectionCount: 1,
        timeoutMs: detailWaitTimeoutMs,
      });
    }
    if (detailLoadedWait.ok && detailSubscribeWait.ok && initialProjectionWitness?.byteEquivalentToDownstream !== true) {
      transitionFailure(
        findings,
        "scenario_detail_history_initial_projection_witness_missing",
        "detail-history initial state did not produce byte-equivalent relay projection witness rows",
        { threadID, minimumRelayProjectionCount: 1 }
      );
    }
    const initialProjectionCount = initialProjectionWitness?.projectionIDs?.length || 0;

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
        message: proofMessageSummary(liveNotification),
      });
      liveProjectionWitness = await waitForDetailProjectionWitness({
        client: streamProbe.client,
        sourceHostID: hostID,
        threadID,
        minProjectionCount: initialProjectionCount + 1,
        timeoutMs: projectionTransitionTimeoutMs,
      });
      if (liveProjectionWitness?.byteEquivalentToDownstream !== true) {
        transitionFailure(
          findings,
          "scenario_detail_history_live_projection_witness_missing",
          "detail-history live update did not produce a byte-equivalent relay projection witness row",
          {
            threadID,
            minimumRelayProjectionCount: initialProjectionCount + 1,
            timeoutMs: projectionTransitionTimeoutMs,
          }
        );
      }

      if (isReplayPressure) {
        replayPressureBurstSentAtMs = Date.now();
        for (let index = 0; index < 3; index += 1) {
          const pressureNotification = {
            jsonrpc: "2.0",
            method: "item/agentMessage/delta",
            params: {
              threadId: threadID,
              turnId: `turn-replay-pressure-${index + 1}`,
              itemId: `agent-replay-pressure-${index + 1}`,
              delta: `Simulator replay pressure detail delta ${index + 1}`,
            },
          };
          detailWs.send(JSON.stringify(pressureNotification));
          await sleep(25);
        }
        replayPressureProjectionWitness = await waitForDetailProjectionWitness({
          client: streamProbe.client,
          sourceHostID: hostID,
          threadID,
          minProjectionCount: (liveProjectionWitness?.projectionIDs?.length || initialProjectionCount) + 3,
          timeoutMs: projectionTransitionTimeoutMs,
        });
        replayPressureWitnessAtMs = replayPressureProjectionWitness ? Date.now() : null;
        if (replayPressureProjectionWitness?.byteEquivalentToDownstream !== true) {
          transitionFailure(
            findings,
            "scenario_detail_replay_pressure_projection_witness_missing",
            "detail-replay-pressure burst did not produce byte-equivalent relay projection witness rows",
            {
              threadID,
              minimumRelayProjectionCount: (liveProjectionWitness?.projectionIDs?.length || initialProjectionCount) + 3,
              timeoutMs: projectionTransitionTimeoutMs,
            }
          );
        }
      }

      await sleep(options.scenarioHoldMs);
      upstreamRequestSentAtMs = Date.now();
      const requestMessage = {
        jsonrpc: "2.0",
        id: requestID,
        method: "item/commandExecution/requestApproval",
        params: {
          threadId: threadID,
          turnId: requestTurnID,
          itemId: requestItemID,
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
        },
      });
      requestProjectionWitness = await waitForDetailProjectionWitness({
        client: streamProbe.client,
        sourceHostID: hostID,
        threadID,
        minProjectionCount: (replayPressureProjectionWitness?.projectionIDs?.length || liveProjectionWitness?.projectionIDs?.length || initialProjectionCount) + 1,
        requestID,
        timeoutMs: projectionTransitionTimeoutMs,
      });
      if (!requestProjectionIDFromWitness(requestProjectionWitness, requestID)) {
        transitionFailure(
          findings,
          "scenario_detail_history_request_projection_witness_missing",
          "detail-history request did not produce a relay projection witness row for the request card",
          { threadID, requestID, timeoutMs: projectionTransitionTimeoutMs }
        );
      }
    }

    const liveWait = await waitForAsyncEvent(liveUpdateSentPromise, detailWaitTimeoutMs);
    const requestWait = await waitForAsyncEvent(requestSentPromise, detailWaitTimeoutMs);
    const responseWait = await waitForAsyncEvent(forwardedResponsePromise, detailWaitTimeoutMs);
    const resolutionWait = await waitForAsyncEvent(resolutionSentPromise, detailWaitTimeoutMs);
    if (resolutionWait.ok) {
      resolutionProjectionWitness = await waitForDetailProjectionWitness({
        client: streamProbe.client,
        sourceHostID: hostID,
        threadID,
        minProjectionCount: requestProjectionWitness?.projectionIDs?.length || liveProjectionWitness?.projectionIDs?.length || initialProjectionCount,
        requestID,
        requestStatus: "resolved",
        timeoutMs: projectionTransitionTimeoutMs,
      });
      if (requestStatusFromWitness(resolutionProjectionWitness, requestID) !== "resolved") {
        transitionFailure(
          findings,
          "scenario_detail_history_resolution_projection_witness_missing",
          "detail-history request resolution did not produce a resolved relay projection witness row",
          { threadID, requestID, timeoutMs: projectionTransitionTimeoutMs }
        );
      }
    }
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
        { requestID, timeoutMs: detailWaitTimeoutMs }
      );
    }
    if (responseWait.ok && responseWait.value?.message?.status !== "accept") {
      transitionFailure(
        findings,
        "scenario_detail_history_response_wrong_payload",
        "simulator app sent the wrong approval response payload for the full-detail request",
        { requestID, response: proofMessageSummary(responseWait.value?.message, { requestID }) }
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

    transitions.push({
      name: "detail-history-live-update",
      kind: "detail-history-live-update",
      iteration: 1,
      route: "thread/detail/update",
      wait: {
        ok: liveWait.ok,
        observedAt: liveUpdateSentAtMs ? new Date(liveUpdateSentAtMs).toISOString() : null,
        observedAtMs: liveUpdateSentAtMs,
      },
      lag: liveLag,
      notification: liveWait.value?.message || null,
      detailTruth: detailTruthFromWitness({
        kind: "detail-history-live-update",
        sourceHostID: hostID,
        detailHostID: simulatorProxy.endpoint,
        threadID,
        witness: liveProjectionWitness,
      }),
    });
    if (isReplayPressure) {
      transitions.push({
        name: "detail-replay-pressure-burst",
        kind: "detail-replay-pressure-burst",
        iteration: 1,
        route: "thread/detail/update",
        wait: {
          ok: replayPressureProjectionWitness?.byteEquivalentToDownstream === true,
          observedAt: replayPressureWitnessAtMs ? new Date(replayPressureWitnessAtMs).toISOString() : null,
          observedAtMs: replayPressureWitnessAtMs,
        },
        lag: scenarioLagSummary({
          transition: "detail-replay-pressure-burst",
          startedAtMs: replayPressureBurstSentAtMs || liveUpdateSentAtMs || detailLoadedAtMs || startedAtMs,
          acknowledgedAtMs: replayPressureBurstSentAtMs || liveUpdateSentAtMs || detailLoadedAtMs || startedAtMs,
          observedAtMs: replayPressureWitnessAtMs,
          maxStreamLagMs: options.maxStreamLagMs,
        }),
        detailTruth: detailTruthFromWitness({
          kind: "detail-replay-pressure-burst",
          sourceHostID: hostID,
          detailHostID: simulatorProxy.endpoint,
          threadID,
          witness: replayPressureProjectionWitness,
        }),
      });
    }
    transitions.push({
      name: "detail-history-request-visible",
      kind: "detail-history-request-visible",
      iteration: 1,
      route: "thread/detail/update",
      wait: {
        ok: requestWait.ok,
        observedAt: upstreamRequestSentAtMs ? new Date(upstreamRequestSentAtMs).toISOString() : null,
        observedAtMs: upstreamRequestSentAtMs,
      },
      lag: requestLag,
      request: requestWait.value?.message || null,
      detailTruth: detailTruthFromWitness({
        kind: "detail-history-request-visible",
        sourceHostID: hostID,
        detailHostID: simulatorProxy.endpoint,
        threadID,
        witness: requestProjectionWitness,
        requestID,
        expectedStatus: "Pending",
        requestVisible: true,
      }),
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
      detailTruth: detailTruthFromWitness({
        kind: "detail-history-request-resolution",
        sourceHostID: hostID,
        detailHostID: simulatorProxy.endpoint,
        threadID,
        witness: resolutionProjectionWitness,
        requestID,
        expectedStatus: "Resolved",
        requestVisible: true,
      }),
    });

    const simulatorClientPathEvidence = summarizeClientPathEvents(simulatorRouteEvents);
    findings.push(...requiredRouteFindings(
      simulatorClientPathEvidence,
      ["thread/detail/subscribe", "thread/detail/update"]
    ));
    findings.push(...forbiddenSimulatorDetailRouteFindings(simulatorClientPathEvidence));
    const clientPathEvidence = summarizeClientPathEvents([
      ...streamProbe.routeEvents,
      ...routeEvents,
      ...simulatorRouteEvents,
    ]);
    const scenarioOK = !findings.some((finding) => finding.severity === "error" || finding.severity === "warning");
    const report = {
      schemaVersion: 1,
      kind: "codex-dock-controlled-simulator-scenario-relay-report",
      mode: "scenario",
      scenario: scenarioName,
      startedAt: new Date(startedAtMs).toISOString(),
      endedAt: new Date().toISOString(),
      relayUrl,
      summary: {
        ok: scenarioOK,
        clientPathOK: scenarioOK,
        scenario: scenarioName,
        scenarioOK,
        scenarioCount: 1,
        scenarioTransitionCount: transitions.length,
        implementedScenarios: [scenarioName],
        unimplementedRequiredScenarios: [],
        failures: findings.length,
        clientPathRouteCounts: clientPathEvidence.routeCounts,
      },
      samples,
      scenarios: [{
        id: scenarioName,
        ok: scenarioOK,
        target: {
          sourceHostID: hostID,
          threadID,
          requestID,
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
      simulatorClientPathEvidence,
      findings,
      unsupportedFacts: [],
    };

    writeProofReport(options.jsonOut, report);
    if (options.summaryOut) {
      writeText(options.summaryOut, buildMarkdownSummary(report));
    }
    await waitForFile(options.stopIn, options.waitTimeoutMs, "simulator UI sampler completion");
    return report;
  } finally {
    await streamProbe.close().catch(() => null);
    await simulatorProxy.close().catch(() => null);
    await relay.close().catch(() => null);
    await closeWebSocketServer(historyServer).catch(() => null);
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

async function runFileChangeReviewScenario(options) {
  const routeEvents = [];
  const simulatorRouteEvents = [];
  const findings = [];
  const transitions = [];
  const samples = [];
  const startedAtMs = Date.now();
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "codex-dock-sim-file-change-review-"));
  const hostID = "sim-file-change-review-fixture";
  const threadID = "sim-file-change-review-thread";
  const requestID = "approval-file-change-1";
  const turnID = "turn-file-change-1";
  const itemID = "item-file-change-1";
  const filePath = "CodexDock/Features/Session/ThreadMessageListView.swift";
  const fileID = `0:update::${filePath}`;
  const requestCardID = projectionIDForFileChangeRequest({
    sourceHostID: hostID,
    threadID,
    turnID,
    itemID,
  });
  const threadRow = fixtureThread(threadID, "Simulator file-change review fixture row", 100);
  const fileChangeTurn = {
    id: turnID,
    startedAt: 1_700_000_001,
    completedAt: 1_700_000_002,
    items: [{
      id: itemID,
      type: "fileChange",
      status: "completed",
      changes: [{
        path: filePath,
        kind: {
          type: "update",
          move_path: null,
        },
        diff: "@@ -1,4 +1,5 @@\n import SwiftUI\n-old placeholder\n+FileChangeReviewCard(event: event)\n+Review changes\n context\n",
      }],
    }],
  };
  let detailWs = null;
  let detailLoadedAtMs = null;
  let upstreamRequestSentAtMs = null;
  let upstreamResponseReceivedAtMs = null;
  let resolutionSentAtMs = null;
  let forwardedResponse = null;
  let resolveDetailLoaded;
  let resolveRequestSent;
  let resolveForwardedResponse;
  let resolveResolutionSent;
  const detailLoadedPromise = new Promise((resolve) => {
    resolveDetailLoaded = resolve;
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

  const sendFileChangeRequest = (ws) => {
    if (upstreamRequestSentAtMs !== null) {
      return;
    }
    upstreamRequestSentAtMs = Date.now();
    const requestMessage = {
      jsonrpc: "2.0",
      id: requestID,
      method: "item/fileChange/requestApproval",
      params: {
        threadId: threadID,
        turnId: turnID,
        itemId: itemID,
        reason: "Review 1 file before approving, +2 -1",
      },
    };
    ws.send(JSON.stringify(requestMessage));
    resolveRequestSent({
      sentAtMs: upstreamRequestSentAtMs,
      message: {
        id: requestID,
        method: requestMessage.method,
        threadID,
      },
    });
  };

  const historyServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await new Promise((resolve) => historyServer.once("listening", resolve));
  historyServer.on("connection", (ws) => {
    ws.on("message", (data) => {
      const message = JSON.parse(data.toString());
      if (message.method === "initialize") {
        recordClientRoute(routeEvents, "initialize", "relay initialized file-change-review fixture upstream", { threadID });
        sendFixtureResult(ws, message.id, {
          userAgent: "codex-sim-file-change-review-fixture",
          codexHome: tempDir,
          platformFamily: "unix",
          platformOs: "macos",
        });
      } else if (message.method === "initialized") {
        recordClientRoute(routeEvents, "initialized", "relay sent initialized notification to file-change-review fixture upstream", { threadID });
      } else if (message.method === "thread/list") {
        sendFixtureResult(ws, message.id, {
          data: activeFixtureRows(message, [threadRow]),
          nextCursor: null,
          backwardsCursor: null,
        });
      } else if (message.method === "thread/loaded/list") {
        sendFixtureResult(ws, message.id, { data: [], nextCursor: null });
      } else if (message.method === "thread/read") {
        recordClientRoute(routeEvents, "thread/read", "relay read target file-change detail from fixture upstream", {
          threadID: message.params?.threadId || threadID,
          includeTurns: message.params?.includeTurns ?? null,
        });
        sendFixtureResult(ws, message.id, {
          thread: {
            ...threadRow,
            id: message.params?.threadId || threadID,
            turns: [],
          },
        });
      } else if (message.method === "thread/turns/list") {
        recordClientRoute(routeEvents, "thread/turns/list", "relay drained file-change historical turns from fixture upstream", {
          threadID: message.params?.threadId || threadID,
          itemsView: message.params?.itemsView ?? null,
        });
        sendFixtureResult(ws, message.id, {
          data: [fileChangeTurn],
          nextCursor: null,
          backwardsCursor: null,
        });
      } else if (message.method === "thread/resume") {
        recordClientRoute(routeEvents, "thread/resume", "relay resumed target file-change live detail from fixture upstream", {
          threadID: message.params?.threadId || threadID,
        });
        sendFixtureResult(ws, message.id, {
          thread: {
            ...threadRow,
            id: message.params?.threadId || threadID,
            turns: [],
          },
        });
        detailWs = ws;
        detailLoadedAtMs = Date.now();
        resolveDetailLoaded({ ws });
      } else if (!message.method && String(message.id) === requestID) {
        upstreamResponseReceivedAtMs = Date.now();
        forwardedResponse = proofMessageSummary({
          id: message.id,
          result: message.result || null,
        }, { requestID });
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
            message: proofMessageSummary(notification, { requestID }),
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
    hostName: "Simulator File Change Review Fixture",
    hostEndpoint: "127.0.0.1:0",
    projectionWitnessEnabled: true,
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
  const simulatorProxy = await startSimulatorAppRouteProxy({
    targetUrl: relayUrl,
    routeEvents: simulatorRouteEvents,
    label: "file-change-review",
  });
  const fixtureOptions = {
    ...options,
    relayUrl,
    codexHome: tempDir,
    sqliteHome: tempDir,
    detail: "none",
  };
  const simulatorProxyOptions = {
    ...fixtureOptions,
    relayUrl: simulatorProxy.url,
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
        "scenario_file_change_review_initial_row_missing",
        "file-change-review fixture row did not appear in the fixture relay stream before simulator launch",
        { threadID }
      );
    }
    const initial = await waitForStableDockClientPathThread({
      streamProbe,
      options: simulatorProxyOptions,
      routeEvents,
      threadID,
      timeoutMs: options.dockCollectionTimeoutMs,
    });
    if (!initial.ok) {
      const detail = {
        threadID,
        freshDockRows: Array.isArray(initial.freshDock?.rows) ? initial.freshDock.rows.length : null,
        freshDockFreshness: initial.freshDock?.freshness || null,
        freshDockCollection: initial.freshDock?.collection || null,
        comparison: initial.comparison || null,
        attempts: initial.attempts || [],
        streamSnapshot: sanitizeDockSnapshotForReport(streamProbe.snapshot()),
        routeCounts: summarizeClientPathEvents(routeEvents).routeCounts,
      };
      transitionFailure(
        findings,
        "scenario_file_change_review_app_path_initial_row_missing",
        "file-change-review app-facing proxy path did not expose the target Dock row before simulator launch",
        detail
      );
      throw new Error(`file-change-review app-facing proxy path did not expose the target Dock row before simulator launch: ${JSON.stringify(detail)}`);
    }
    findings.push(...scenarioComparisonFindings({ phase: "initial", comparison: initial.comparison }));
    samples.push({
      sampleIndex: 0,
      startedAt: new Date(startedAtMs).toISOString(),
      finishedAt: new Date().toISOString(),
      freshDock: sanitizeDockSnapshotForReport(initial.freshDock),
    });

    writeJSON(options.readyOut, {
      ready: true,
      scenario: "file-change-review",
      relayUrl,
      simulatorRelayUrl: simulatorProxy.url,
      hosts: simulatorProxy.endpoint,
      target: {
        sourceHostID: hostID,
        threadID,
        requestID,
        requestCardID,
        fileID,
      },
      uiConfig: {
        openHostID: hostID,
        openThreadID: threadID,
        detailFilter: "all",
        checkpointSweep: false,
        detailCheckpointSweep: true,
        fileChangeReviewEventID: requestCardID,
        fileChangeReviewFileID: fileID,
        fileChangeReviewRequestCardID: requestCardID,
      },
      at: new Date().toISOString(),
    });
    await waitForFile(options.uiReadyIn, options.waitTimeoutMs, "simulator UI file-change sampler readiness");

    const detailWaitTimeoutMs = Math.min(options.dockCollectionTimeoutMs, options.waitTimeoutMs);
    const projectionTransitionTimeoutMs = detailTransitionWitnessTimeoutMs(options, detailWaitTimeoutMs);
    const detailSubscribeWait = await waitForRecordedRouteEvent({
      events: simulatorRouteEvents,
      route: "thread/detail/subscribe",
      source: "simulatorAppProxy",
      boundary: "simulatorAppToRelay",
      afterMs: startedAtMs,
      timeoutMs: detailWaitTimeoutMs,
    });
    if (!detailSubscribeWait.ok) {
      transitionFailure(
        findings,
        "scenario_file_change_review_detail_subscribe_missing",
        "simulator app did not open the controlled file-change detail session through thread/detail/subscribe",
        { threadID, timeoutMs: detailWaitTimeoutMs }
      );
    }
    const detailLoadedWait = await waitForAsyncEvent(detailLoadedPromise, detailWaitTimeoutMs);
    if (detailLoadedWait.ok && detailWs) {
      await sleep(Math.min(Math.max(options.scenarioHoldMs, 500), 1_500));
      sendFileChangeRequest(detailWs);
    }
    const requestWait = await waitForAsyncEvent(requestSentPromise, detailWaitTimeoutMs);
    const requestProjectionWitness = requestWait.ok
      ? await waitForDetailProjectionWitness({
        client: streamProbe.client,
        sourceHostID: hostID,
        threadID,
        minProjectionCount: 1,
        requestID,
        timeoutMs: projectionTransitionTimeoutMs,
      })
      : null;
    if (requestWait.ok && !requestProjectionIDFromWitness(requestProjectionWitness, requestID)) {
      transitionFailure(
        findings,
        "scenario_file_change_review_projection_witness_missing",
        "file-change approval did not produce a relay projection witness row for the file-change card",
        { threadID, requestID, timeoutMs: projectionTransitionTimeoutMs }
      );
    }
    const responseWait = await waitForAsyncEvent(forwardedResponsePromise, detailWaitTimeoutMs);
    const resolutionWait = await waitForAsyncEvent(resolutionSentPromise, detailWaitTimeoutMs);
    const resolutionProjectionWitness = resolutionWait.ok
      ? await waitForDetailProjectionWitness({
        client: streamProbe.client,
        sourceHostID: hostID,
        threadID,
        minProjectionCount: requestProjectionWitness?.projectionIDs?.length || 1,
        requestID,
        requestStatus: "resolved",
        timeoutMs: projectionTransitionTimeoutMs,
      })
      : null;
    if (resolutionWait.ok && requestStatusFromWitness(resolutionProjectionWitness, requestID) !== "resolved") {
      transitionFailure(
        findings,
        "scenario_file_change_review_resolution_projection_witness_missing",
        "file-change approval resolution did not produce a resolved relay projection witness row",
        { threadID, requestID, timeoutMs: projectionTransitionTimeoutMs }
      );
    }

    if (!detailLoadedWait.ok) {
      transitionFailure(
        findings,
        "scenario_file_change_review_detail_not_resumed",
        "fixture did not observe the simulator app resume the file-change detail session",
        { threadID, timeoutMs: detailWaitTimeoutMs }
      );
    }
    if (!requestWait.ok) {
      transitionFailure(
        findings,
        "scenario_file_change_review_request_not_sent",
        "fixture did not emit a file-change approval request after the simulator opened detail",
        { threadID, requestID, timeoutMs: detailWaitTimeoutMs }
      );
    }
    if (!responseWait.ok) {
      transitionFailure(
        findings,
        "scenario_file_change_review_response_not_forwarded",
        "simulator app did not forward an approval response after reviewing the file-change diff",
        { requestID, timeoutMs: detailWaitTimeoutMs }
      );
    }
    if (responseWait.ok && responseWait.value?.message?.status !== "accept") {
      transitionFailure(
        findings,
        "scenario_file_change_review_response_wrong_payload",
        "simulator app sent the wrong file-change approval response payload",
        { requestID, response: proofMessageSummary(responseWait.value?.message, { requestID }) }
      );
    }
    if (!resolutionWait.ok) {
      transitionFailure(
        findings,
        "scenario_file_change_review_resolution_not_sent",
        "fixture did not send serverRequest/resolved after the file-change approval response",
        { requestID, timeoutMs: detailWaitTimeoutMs }
      );
    }

    transitions.push({
      name: "file-change-review-visible",
      kind: "file-change-review-visible",
      iteration: 1,
      route: "thread/detail/update",
      wait: {
        ok: requestWait.ok,
        observedAt: upstreamRequestSentAtMs ? new Date(upstreamRequestSentAtMs).toISOString() : null,
        observedAtMs: upstreamRequestSentAtMs,
      },
      lag: scenarioLagSummary({
        transition: "file-change-review-visible",
        startedAtMs: upstreamRequestSentAtMs || detailLoadedAtMs || startedAtMs,
        acknowledgedAtMs: upstreamRequestSentAtMs || detailLoadedAtMs || startedAtMs,
        observedAtMs: upstreamRequestSentAtMs,
        maxStreamLagMs: options.maxStreamLagMs,
      }),
      request: requestWait.value?.message || null,
      detailTruth: detailTruthFromWitness({
        kind: "file-change-review-visible",
        sourceHostID: hostID,
        detailHostID: simulatorProxy.endpoint,
        threadID,
        witness: requestProjectionWitness,
        requestID,
        expectedStatus: "Pending",
        requestVisible: true,
      }),
    });
    transitions.push({
      name: "file-change-review-approval",
      kind: "file-change-review-approval",
      iteration: 1,
      route: "server/response",
      wait: {
        ok: responseWait.ok && resolutionWait.ok,
        responseForwardedAt: upstreamResponseReceivedAtMs ? new Date(upstreamResponseReceivedAtMs).toISOString() : null,
        resolutionSentAt: resolutionSentAtMs ? new Date(resolutionSentAtMs).toISOString() : null,
      },
      lag: scenarioLagSummary({
        transition: "file-change-review-approval",
        startedAtMs: upstreamResponseReceivedAtMs || upstreamRequestSentAtMs || detailLoadedAtMs || startedAtMs,
        acknowledgedAtMs: upstreamResponseReceivedAtMs || upstreamRequestSentAtMs || detailLoadedAtMs || startedAtMs,
        observedAtMs: resolutionSentAtMs,
        maxStreamLagMs: options.maxStreamLagMs,
      }),
      forwardedResponse,
      resolution: resolutionWait.value?.message || null,
      detailTruth: detailTruthFromWitness({
        kind: "file-change-review-approval",
        sourceHostID: hostID,
        detailHostID: simulatorProxy.endpoint,
        threadID,
        witness: resolutionProjectionWitness || requestProjectionWitness,
        requestID,
        expectedStatus: "Resolved",
        requestVisible: true,
      }),
    });

    const simulatorClientPathEvidence = summarizeClientPathEvents(simulatorRouteEvents);
    findings.push(...requiredRouteFindings(
      simulatorClientPathEvidence,
      ["thread/detail/subscribe", "thread/detail/update"]
    ));
    findings.push(...forbiddenSimulatorDetailRouteFindings(simulatorClientPathEvidence));
    const clientPathEvidence = summarizeClientPathEvents([
      ...streamProbe.routeEvents,
      ...routeEvents,
      ...simulatorRouteEvents,
    ]);
    const scenarioOK = !findings.some((finding) => finding.severity === "error" || finding.severity === "warning");
    const report = {
      schemaVersion: 1,
      kind: "codex-dock-controlled-simulator-scenario-relay-report",
      mode: "scenario",
      scenario: "file-change-review",
      startedAt: new Date(startedAtMs).toISOString(),
      endedAt: new Date().toISOString(),
      relayUrl,
      summary: {
        ok: scenarioOK,
        clientPathOK: scenarioOK,
        scenario: "file-change-review",
        scenarioOK,
        scenarioCount: 1,
        scenarioTransitionCount: transitions.length,
        implementedScenarios: ["file-change-review"],
        unimplementedRequiredScenarios: [],
        failures: findings.length,
        clientPathRouteCounts: clientPathEvidence.routeCounts,
      },
      samples,
      scenarios: [{
        id: "file-change-review",
        ok: scenarioOK,
        target: {
          sourceHostID: hostID,
          threadID,
          requestID,
          requestCardID,
          fileID,
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
      simulatorClientPathEvidence,
      findings,
      unsupportedFacts: [],
    };

    writeProofReport(options.jsonOut, report);
    if (options.summaryOut) {
      writeText(options.summaryOut, buildMarkdownSummary(report));
    }
    await waitForFile(options.stopIn, options.waitTimeoutMs, "simulator UI sampler completion");
    return report;
  } finally {
    await streamProbe.close().catch(() => null);
    await simulatorProxy.close().catch(() => null);
    await relay.close().catch(() => null);
    await closeWebSocketServer(historyServer).catch(() => null);
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

async function runServerRequestScenario(options) {
  const routeEvents = [];
  const simulatorRouteEvents = [];
  const findings = [];
  const transitions = [];
  const samples = [];
  const startedAtMs = Date.now();
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "codex-dock-sim-server-request-"));
  const hostID = "sim-server-request-fixture";
  const threadID = "sim-server-request-thread";
  const requestID = "approval-1";
  const requestTurnID = "turn-live";
  const requestItemID = "cmd-live";
  const requestCardID = projectionIDForCommandApprovalRequest({
    sourceHostID: hostID,
    threadID,
    turnID: requestTurnID,
    itemID: requestItemID,
  });
  const threadRow = fixtureThread(threadID, "Simulator server request fixture row", 100);
  let upstreamRequestSentAtMs = null;
  let upstreamResponseReceivedAtMs = null;
  let resolutionSentAtMs = null;
  let forwardedResponse = null;
  let resolveRequestSent;
  let resolveForwardedResponse;
  let resolveResolutionSent;
  let resolveResumeReady;
  const requestSentPromise = new Promise((resolve) => {
    resolveRequestSent = resolve;
  });
  const forwardedResponsePromise = new Promise((resolve) => {
    resolveForwardedResponse = resolve;
  });
  const resolutionSentPromise = new Promise((resolve) => {
    resolveResolutionSent = resolve;
  });
  const resumeReadyPromise = new Promise((resolve) => {
    resolveResumeReady = resolve;
  });
  const sendServerRequest = ({ ws, resumedThreadID }) => {
    if (upstreamRequestSentAtMs !== null) {
      return;
    }
    upstreamRequestSentAtMs = Date.now();
    const requestMessage = {
      jsonrpc: "2.0",
      id: requestID,
      method: "item/commandExecution/requestApproval",
      params: {
        threadId: resumedThreadID,
        turnId: requestTurnID,
        itemId: requestItemID,
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
      },
    });
  };

  const historyServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await new Promise((resolve) => historyServer.once("listening", resolve));
  historyServer.on("connection", (ws) => {
    ws.on("message", (data) => {
      const message = JSON.parse(data.toString());
      if (message.method === "initialize") {
        recordClientRoute(routeEvents, "initialize", "relay initialized server-request fixture upstream", { threadID });
        sendFixtureResult(ws, message.id, {
          userAgent: "codex-sim-server-request-fixture",
          codexHome: tempDir,
          platformFamily: "unix",
          platformOs: "macos",
        });
      } else if (message.method === "initialized") {
        recordClientRoute(routeEvents, "initialized", "relay sent initialized notification to server-request fixture upstream", { threadID });
      } else if (message.method === "thread/list") {
        sendFixtureResult(ws, message.id, {
          data: activeFixtureRows(message, [threadRow]),
          nextCursor: null,
          backwardsCursor: null,
        });
      } else if (message.method === "thread/loaded/list") {
        sendFixtureResult(ws, message.id, { data: [], nextCursor: null });
      } else if (message.method === "thread/read") {
        recordClientRoute(routeEvents, "thread/read", "relay read target thread detail from fixture upstream", {
          threadID: message.params?.threadId || threadID,
        });
        sendFixtureResult(ws, message.id, {
          thread: {
            ...threadRow,
            id: message.params?.threadId || threadID,
            turns: [],
          },
        });
      } else if (message.method === "thread/turns/list") {
        recordClientRoute(routeEvents, "thread/turns/list", "relay drained historical thread turns from fixture upstream", {
          threadID: message.params?.threadId || threadID,
          itemsView: message.params?.itemsView ?? null,
        });
        sendFixtureResult(ws, message.id, {
          data: [],
          nextCursor: null,
          backwardsCursor: null,
        });
      } else if (message.method === "thread/resume") {
        recordClientRoute(routeEvents, "thread/resume", "relay resumed target thread live detail from fixture upstream", {
          threadID: message.params?.threadId || threadID,
        });
        sendFixtureResult(ws, message.id, {
          thread: {
            ...threadRow,
            id: message.params?.threadId || threadID,
            turns: [],
          },
        });
        resolveResumeReady({
          ws,
          resumedThreadID: message.params?.threadId || threadID,
        });
      } else if (!message.method && String(message.id) === requestID) {
        upstreamResponseReceivedAtMs = Date.now();
        forwardedResponse = proofMessageSummary({
          id: message.id,
          result: message.result || null,
        }, { requestID });
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
            message: proofMessageSummary(notification, { requestID }),
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
    projectionWitnessEnabled: true,
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
  const simulatorProxy = await startSimulatorAppRouteProxy({
    targetUrl: relayUrl,
    routeEvents: simulatorRouteEvents,
    label: "server-request",
  });
  const fixtureOptions = {
    ...options,
    relayUrl,
    codexHome: tempDir,
    sqliteHome: tempDir,
    detail: "none",
  };
  const simulatorProxyOptions = {
    ...fixtureOptions,
    relayUrl: simulatorProxy.url,
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
    const initial = await waitForStableDockClientPathThread({
      streamProbe,
      options: simulatorProxyOptions,
      routeEvents,
      threadID,
      timeoutMs: options.dockCollectionTimeoutMs,
    });
    if (!initial.ok) {
      const detail = {
        threadID,
        freshDockRows: Array.isArray(initial.freshDock?.rows) ? initial.freshDock.rows.length : null,
        freshDockFreshness: initial.freshDock?.freshness || null,
        freshDockCollection: initial.freshDock?.collection || null,
        comparison: initial.comparison || null,
        attempts: initial.attempts || [],
        streamSnapshot: sanitizeDockSnapshotForReport(streamProbe.snapshot()),
        routeCounts: summarizeClientPathEvents(routeEvents).routeCounts,
      };
      transitionFailure(
        findings,
        "scenario_server_request_app_path_initial_row_missing",
        "server-request fixture app-facing proxy path did not expose the target Dock row before simulator launch",
        detail
      );
      throw new Error(`server-request app-facing proxy path did not expose the target Dock row before simulator launch: ${JSON.stringify(detail)}`);
    }
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
      simulatorRelayUrl: simulatorProxy.url,
      hosts: simulatorProxy.endpoint,
      target: {
        sourceHostID: hostID,
        threadID,
        requestID,
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
    const projectionTransitionTimeoutMs = detailTransitionWitnessTimeoutMs(options, detailWaitTimeoutMs);
    const resumeReadyWait = await waitForAsyncEvent(resumeReadyPromise, detailWaitTimeoutMs);
    if (resumeReadyWait.ok) {
      sendServerRequest(resumeReadyWait.value);
    }
    const detailSubscribeWait = await waitForRecordedRouteEvent({
      events: simulatorRouteEvents,
      route: "thread/detail/subscribe",
      source: "simulatorAppProxy",
      boundary: "simulatorAppToRelay",
      afterMs: startedAtMs,
      timeoutMs: detailWaitTimeoutMs,
    });
    if (!detailSubscribeWait.ok) {
      transitionFailure(
        findings,
        "scenario_server_request_detail_subscribe_missing",
        "simulator app did not open the controlled detail session through thread/detail/subscribe",
        { threadID, timeoutMs: detailWaitTimeoutMs }
      );
    }
    const requestWait = await waitForAsyncEvent(requestSentPromise, detailWaitTimeoutMs);
    const requestProjectionWitness = requestWait.ok
      ? await waitForDetailProjectionWitness({
        client: streamProbe.client,
        sourceHostID: hostID,
        threadID,
        minProjectionCount: 1,
        requestID,
        timeoutMs: projectionTransitionTimeoutMs,
      })
      : null;
    if (requestWait.ok && !requestProjectionIDFromWitness(requestProjectionWitness, requestID)) {
      transitionFailure(
        findings,
        "scenario_server_request_projection_witness_missing",
        "server request did not produce a relay projection witness row for the request card",
        { threadID, requestID, timeoutMs: projectionTransitionTimeoutMs }
      );
    }
    const responseWait = await waitForAsyncEvent(forwardedResponsePromise, detailWaitTimeoutMs);
    const resolutionWait = await waitForAsyncEvent(resolutionSentPromise, detailWaitTimeoutMs);
    const resolutionProjectionWitness = resolutionWait.ok
      ? await waitForDetailProjectionWitness({
        client: streamProbe.client,
        sourceHostID: hostID,
        threadID,
        minProjectionCount: requestProjectionWitness?.projectionIDs?.length || 1,
        requestID,
        requestStatus: "resolved",
        timeoutMs: projectionTransitionTimeoutMs,
      })
      : null;
    if (resolutionWait.ok && requestStatusFromWitness(resolutionProjectionWitness, requestID) !== "resolved") {
      transitionFailure(
        findings,
        "scenario_server_request_resolution_projection_witness_missing",
        "server request resolution did not produce a resolved relay projection witness row",
        { threadID, requestID, timeoutMs: projectionTransitionTimeoutMs }
      );
    }
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
        { requestID, timeoutMs: detailWaitTimeoutMs }
      );
    }
    if (responseWait.ok && responseWait.value?.message?.status !== "accept") {
      transitionFailure(
        findings,
        "scenario_server_request_response_wrong_payload",
        "simulator app sent the wrong approval response payload",
        { requestID, response: proofMessageSummary(responseWait.value?.message, { requestID }) }
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
      route: "thread/detail/update",
      wait: {
        ok: requestWait.ok,
        observedAt: upstreamRequestSentAtMs ? new Date(upstreamRequestSentAtMs).toISOString() : null,
        observedAtMs: upstreamRequestSentAtMs,
      },
      lag: requestLag,
      request: requestWait.value?.message || null,
      detailTruth: detailTruthFromWitness({
        kind: "server-request-visible",
        sourceHostID: hostID,
        detailHostID: simulatorProxy.endpoint,
        threadID,
        witness: requestProjectionWitness,
        requestID,
        expectedStatus: "Pending",
        requestVisible: true,
      }),
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
      detailTruth: detailTruthFromWitness({
        kind: "server-request-resolution",
        sourceHostID: hostID,
        detailHostID: simulatorProxy.endpoint,
        threadID,
        witness: resolutionProjectionWitness || requestProjectionWitness,
        requestID,
        expectedStatus: "Resolved",
        requestVisible: true,
      }),
    });

    const simulatorClientPathEvidence = summarizeClientPathEvents(simulatorRouteEvents);
    findings.push(...requiredRouteFindings(
      simulatorClientPathEvidence,
      ["thread/detail/subscribe", "thread/detail/update"]
    ));
    findings.push(...forbiddenSimulatorDetailRouteFindings(simulatorClientPathEvidence));
    const clientPathEvidence = summarizeClientPathEvents([
      ...streamProbe.routeEvents,
      ...routeEvents,
      ...simulatorRouteEvents,
    ]);
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
          sourceHostID: hostID,
          threadID,
          requestID,
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
      simulatorClientPathEvidence,
      findings,
      unsupportedFacts: [],
    };

    writeProofReport(options.jsonOut, report);
    if (options.summaryOut) {
      writeText(options.summaryOut, buildMarkdownSummary(report));
    }
    await waitForFile(options.stopIn, options.waitTimeoutMs, "simulator UI sampler completion");
    return report;
  } finally {
    await streamProbe.close().catch(() => null);
    await simulatorProxy.close().catch(() => null);
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
  const requestedScenario = options.scenario;
  if (options.scenario === "archive-toggle" || options.scenario === "mutation-ack-projection-refresh-failure") {
    report = await runArchiveToggleScenario(options);
  } else if (options.scenario === "detail-reconnect" || options.scenario === "foreground-resume-all-surfaces") {
    report = await runDetailReconnectScenario(options);
  } else if (options.scenario === "detail-history-request" || options.scenario === "detail-replay-pressure") {
    report = await runDetailHistoryRequestScenario(options);
  } else if (options.scenario === "large-list-checkpoint" || options.scenario === "root-catchup-window-contract") {
    report = await runLargeListCheckpointScenario(options);
  } else if (options.scenario === "file-change-review") {
    report = await runFileChangeReviewScenario(options);
  } else if (options.scenario === "server-request") {
    report = await runServerRequestScenario(options);
  } else if (options.scenario === "server-rename-notification") {
    report = await runServerRenameNotificationScenario(options);
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
  report = retargetScenarioReport(report, requestedScenario);
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
  forbiddenSimulatorDetailRouteFindings,
  parseArgs,
  startSimulatorAppRouteProxy,
  validateOptions,
  waitForRecordedRouteEvent,
};

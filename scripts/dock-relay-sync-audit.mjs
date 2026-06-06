#!/usr/bin/env node

import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";
import { WebSocketServer } from "ws";

import {
  DEFAULT_RELAY_WS,
  RELAY_STATE_STREAM_SCHEMA_VERSION,
  THREAD_LIST_MAX_LIMIT,
} from "./dock-relay-constants.mjs";
import { JsonRpcWebSocketClient } from "./dock-relay-json-rpc-client.mjs";
import { appServerRegistryFixtureConfig } from "./dock-relay-test-helpers.mjs";
import {
  PROJECTION_ENGINE_VERSION,
  PROJECTION_IDENTITY_VERSION,
  PROJECTION_SCHEMA_VERSION,
  projectionIDForThreadCard,
} from "./dock-relay-projection-engine.mjs";
import { startServer } from "./dock-relay.mjs";
import { threadMatchesSourceKinds } from "./dock-relay-source-filter.mjs";
import { initializeClient } from "./dock-relay-thread-data.mjs";
import {
  assertProofReport,
  finalizeProofReport,
} from "./proof-report-contracts.mjs";

const MODES = new Set(["one-shot", "read-only-real-home", "soak", "scenario"]);
const DETAIL_MODES = new Set(["none", "sampled", "all"]);
const TURN_SORT_DIRECTIONS = new Set(["asc", "desc"]);
const TURN_ITEMS_VIEWS = new Set(["notLoaded", "summary", "full"]);
const SCENARIOS = new Set(["archive-toggle", "detail-reconnect", "live-lease-expiry", "multi-host-isolation", "rename-title", "resync-gap", "server-request", "source-refresh", "spawn-edge", "thread-activity", "all"]);
const DEFAULT_SCENARIO = "archive-toggle";
const DEFAULT_REQUEST_TIMEOUT_MS = 120_000;
const DEFAULT_SOAK_DURATION_MS = 900_000;
const DEFAULT_SAMPLE_INTERVAL_MS = 30_000;
const DEFAULT_STREAM_SETTLE_MS = 250;
const DEFAULT_DOCK_COLLECTION_TIMEOUT_MS = 120_000;
const DEFAULT_STREAM_COMPARE_ATTEMPTS = 3;
const DEFAULT_STREAM_COMPARE_DELAY_MS = 1_000;
const DEFAULT_MAX_STREAM_LAG_MS = 2_000;
const DEFAULT_SCENARIO_HOLD_MS = 0;
const DEFAULT_SCENARIO_REPETITIONS = 1;
const DEFAULT_DETAIL_LIMIT = 5;
const DEFAULT_DETAIL_OBSERVE_MS = 100;
const TEXT_FIELD_RE = /(^|_|\b)(title|summary|preview|message|text|content|transcript|prompt|firstUserMessage|displaySummary|latestSummary)($|_|\b)/i;
const SECRET_FIELD_RE = /(token|secret|authorization|apiKey|bearer|password|credential)/i;
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
  "thread/name/set",
  "thread/unarchive",
  "thread/detail/subscribe",
  "thread/detail/resync",
  "thread/detail/update",
]);
const FORBIDDEN_DOCK_STREAM_KEYS = new Set([
  "baseSeq",
  "stateGeneration",
  "cards",
  "cardIDs",
  "cardCount",
  "renderOrderCardIDs",
  "upsertCards",
  "deleteCardIDs",
]);
const REQUIRED_SCENARIOS = Object.freeze([
  { id: "existing-active", label: "Existing idle active thread appears in Dock", implementedBy: "archive-toggle" },
  { id: "existing-archived", label: "Existing archived thread appears only in archived views", implementedBy: "archive-toggle" },
  { id: "rename-title", label: "Thread rename updates the active Dock title through the real app-server route", implementedBy: "rename-title" },
  { id: "new-thread", label: "New thread is created and appears within the convergence budget", implementedBy: "thread-activity" },
  { id: "new-turn-order", label: "Existing thread receives a new turn and moves order correctly", implementedBy: "thread-activity" },
  { id: "live-lease-expiry", label: "Active live thread appears as live and later expires when no longer live", implementedBy: "live-lease-expiry" },
  { id: "archive-removal", label: "Thread is archived and disappears from active Dock after complete refresh", implementedBy: "archive-toggle" },
  { id: "unarchive-return", label: "Thread is unarchived and reappears in active Dock after complete refresh", implementedBy: "archive-toggle" },
  { id: "spawn-edge", label: "Subagent spawn edge stays out of human-only app-facing streams", implementedBy: "spawn-edge" },
  { id: "server-request-visible", label: "Server request appears in detail as both event and request card", implementedBy: "server-request" },
  { id: "server-request-resolution", label: "Server request resolution updates the card", implementedBy: "server-request" },
  { id: "source-refresh-fails", label: "Relay source refresh fails and stale state is explicit", implementedBy: "source-refresh" },
  { id: "source-refresh-recovers", label: "Relay source refresh recovers and stale rows are reconciled", implementedBy: "source-refresh" },
  { id: "stream-gap-resync", label: "Stream sequence gap triggers resync and converges", implementedBy: "resync-gap" },
  { id: "detail-reconnect", label: "Reconnect reloads thread detail before live", implementedBy: "detail-reconnect" },
  { id: "multi-host-isolation", label: "Multi-host configuration keeps rows isolated by host", implementedBy: "multi-host-isolation" },
  { id: "rapid-archive-toggle", label: "Rapid repeated archive/unarchive transitions preserve every ordered client-visible change", implementedBy: "archive-toggle", requiresRepetitions: 2 },
]);
const SCENARIO_ARCHIVE_STATUS_PRIORITY = Object.freeze({
  idle: 0,
  dormant: 1,
  unknown: 2,
  error: 3,
  needsInput: 4,
  needsApproval: 5,
  running: 6,
});
function usage() {
  return [
    "Usage: node scripts/dock-relay-sync-audit.mjs [options]",
    "",
    "Options:",
    "  --mode <one-shot|read-only-real-home|soak|scenario>  Audit mode. Defaults to one-shot.",
    "  --relay-url <ws-url>       Relay WebSocket URL. Defaults to CODEX_DOCK_RELAY_WS or ws://127.0.0.1:4510.",
    "  --codex-home <path>        Codex home. Defaults to CODEX_HOME or ~/.codex.",
    "  --sqlite-home <path>       SQLite home. Defaults to CODEX_SQLITE_HOME or codex home.",
    "  --limit <n>                App-server page size, capped at 250. Defaults to 250.",
    "  --turn-sort-direction <asc|desc>  Turn order to request. Defaults to desc.",
    "  --turn-items-view <notLoaded|summary|full>  Turn detail to request. Exhaustive defaults to full.",
    "  --scenario <archive-toggle|detail-reconnect|live-lease-expiry|multi-host-isolation|rename-title|resync-gap|server-request|source-refresh|spawn-edge|thread-activity|all>  Scenario actuator set for scenario mode. Defaults to archive-toggle.",
    "  --scenario-thread-id <id>   Select an exact thread id for scenario mode instead of the first active Dock row.",
    "  --scenario-hold-ms <n>      Hold after each scenario mutation before the next mutation. Defaults to 0.",
    "  --scenario-repetitions <n>  Repeat the selected scenario. Defaults to 1.",
    "  --client-path-only         Accepted for compatibility; this script only proves actual client-exercised relay routes.",
    "  --force-dock-resync        In soak mode, explicitly call dock/resync each sample and verify convergence.",
    "  --duration-ms <n>          Soak duration, or explicit scenario relay-truth observation window. Defaults to 900000.",
    "  --sample-interval-ms <n>   Soak sample interval. Defaults to 30000.",
    "  --settle-ms <n>            Time to let stream updates arrive before comparisons. Defaults to 250.",
    "  --dock-collection-timeout-ms <n>  Time to wait for streamed Dock catch-up. Defaults to 120000.",
    "  --stream-compare-attempts <n>  Extra fresh-vs-long-lived comparisons before failure. Defaults to 3.",
    "  --stream-compare-delay-ms <n>  Delay between stream comparison attempts. Defaults to 1000.",
    "  --max-stream-lag-ms <n>  Max allowed long-lived stream lag after divergence. Defaults to 2000.",
    "  --detail <none|sampled|all> Detail probe mode. Defaults to sampled.",
    "  --detail-limit <n>         Max detail targets for sampled mode. Defaults to 5.",
    "  --detail-observe-ms <n>    Time to observe notifications after projection subscribe. Defaults to 100.",
    "  --no-detail-live           Skip thread/detail/subscribe and thread/detail/resync in detail probes.",
    "  --no-detail-buffer-initial-live  Fail instead of modeling the Swift initial live-event buffer.",
    "  --request-timeout-ms <n>   JSON-RPC request timeout. Defaults to 120000.",
    "  --json-out <path>          Write sanitized JSON report to a file.",
    "  --summary-out <path>       Write Markdown summary to a file.",
    "  --summary-only             Print compact stdout summary instead of full JSON.",
    "  --fail-on-diff            Exit 1 when failures are present.",
    "  --help                    Show this help text.",
  ].join("\n");
}

function nonEmpty(value) {
  if (typeof value !== "string") {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function expandHome(value) {
  if (!value) {
    return value;
  }
  if (value === "~") {
    return os.homedir();
  }
  if (value.startsWith("~/")) {
    return path.join(os.homedir(), value.slice(2));
  }
  return value;
}

function resolveUserPath(value, cwd = process.cwd()) {
  if (!value) {
    return value;
  }
  const expanded = expandHome(value);
  return path.isAbsolute(expanded) ? expanded : path.resolve(cwd, expanded);
}

function parsePositiveInteger(value, label) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    throw new Error(`${label} must be a positive number`);
  }
  return Math.floor(parsed);
}

function parseNonNegativeInteger(value, label) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed < 0) {
    throw new Error(`${label} must be a non-negative number`);
  }
  return Math.floor(parsed);
}

function sanitizeURLForReport(value) {
  try {
    const url = new URL(value);
    url.username = "";
    url.password = "";
    url.search = "";
    url.hash = "";
    return url.toString();
  } catch {
    return String(value || "");
  }
}

function parseArgs(argv, env = process.env, cwd = process.cwd()) {
  const options = {
    mode: "one-shot",
    relayUrl: env.CODEX_DOCK_RELAY_WS || DEFAULT_RELAY_WS,
    codexHome: env.CODEX_HOME || path.join(os.homedir(), ".codex"),
    sqliteHome: env.CODEX_SQLITE_HOME || null,
    limit: THREAD_LIST_MAX_LIMIT,
    clientPathOnly: false,
    forceDockResync: false,
    turnSortDirection: "desc",
    turnItemsView: "full",
    turnItemsViewExplicit: false,
    scenario: DEFAULT_SCENARIO,
    scenarioThreadID: null,
    scenarioHoldMs: DEFAULT_SCENARIO_HOLD_MS,
    scenarioRepetitions: DEFAULT_SCENARIO_REPETITIONS,
    durationMs: DEFAULT_SOAK_DURATION_MS,
    durationMsExplicit: false,
    sampleIntervalMs: DEFAULT_SAMPLE_INTERVAL_MS,
    settleMs: DEFAULT_STREAM_SETTLE_MS,
    dockCollectionTimeoutMs: DEFAULT_DOCK_COLLECTION_TIMEOUT_MS,
    streamCompareAttempts: DEFAULT_STREAM_COMPARE_ATTEMPTS,
    streamCompareDelayMs: DEFAULT_STREAM_COMPARE_DELAY_MS,
    maxStreamLagMs: DEFAULT_MAX_STREAM_LAG_MS,
    detail: "sampled",
    detailLimit: DEFAULT_DETAIL_LIMIT,
    detailObserveMs: DEFAULT_DETAIL_OBSERVE_MS,
    detailLive: true,
    detailBufferInitialLive: true,
    requestTimeoutMs: DEFAULT_REQUEST_TIMEOUT_MS,
    jsonOut: null,
    summaryOut: null,
    summaryOnly: false,
    failOnDiff: false,
    help: false,
  };

  function readValue(index, flag) {
    const value = argv[index + 1];
    if (!value || value.startsWith("--")) {
      throw new Error(`${flag} requires a value`);
    }
    return value;
  }

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--help" || arg === "-h") {
      options.help = true;
    } else if (arg === "--mode") {
      options.mode = readValue(index, arg);
      index += 1;
    } else if (arg.startsWith("--mode=")) {
      options.mode = arg.slice("--mode=".length);
    } else if (arg === "--relay-url") {
      options.relayUrl = readValue(index, arg);
      index += 1;
    } else if (arg.startsWith("--relay-url=")) {
      options.relayUrl = arg.slice("--relay-url=".length);
    } else if (arg === "--codex-home") {
      options.codexHome = readValue(index, arg);
      index += 1;
    } else if (arg.startsWith("--codex-home=")) {
      options.codexHome = arg.slice("--codex-home=".length);
    } else if (arg === "--sqlite-home") {
      options.sqliteHome = readValue(index, arg);
      index += 1;
    } else if (arg.startsWith("--sqlite-home=")) {
      options.sqliteHome = arg.slice("--sqlite-home=".length);
    } else if (arg === "--limit") {
      options.limit = parsePositiveInteger(readValue(index, arg), "--limit");
      index += 1;
    } else if (arg.startsWith("--limit=")) {
      options.limit = parsePositiveInteger(arg.slice("--limit=".length), "--limit");
    } else if (arg === "--client-path-only") {
      options.clientPathOnly = true;
    } else if (arg === "--force-dock-resync") {
      options.forceDockResync = true;
    } else if (arg === "--turn-sort-direction") {
      options.turnSortDirection = readValue(index, arg);
      index += 1;
    } else if (arg.startsWith("--turn-sort-direction=")) {
      options.turnSortDirection = arg.slice("--turn-sort-direction=".length);
    } else if (arg === "--turn-items-view") {
      options.turnItemsView = readValue(index, arg);
      options.turnItemsViewExplicit = true;
      index += 1;
    } else if (arg.startsWith("--turn-items-view=")) {
      options.turnItemsView = arg.slice("--turn-items-view=".length);
      options.turnItemsViewExplicit = true;
    } else if (arg === "--scenario") {
      options.scenario = readValue(index, arg);
      index += 1;
    } else if (arg.startsWith("--scenario=")) {
      options.scenario = arg.slice("--scenario=".length);
    } else if (arg === "--scenario-thread-id") {
      options.scenarioThreadID = readValue(index, arg);
      index += 1;
    } else if (arg.startsWith("--scenario-thread-id=")) {
      options.scenarioThreadID = arg.slice("--scenario-thread-id=".length);
    } else if (arg === "--scenario-hold-ms") {
      options.scenarioHoldMs = parseNonNegativeInteger(readValue(index, arg), "--scenario-hold-ms");
      index += 1;
    } else if (arg.startsWith("--scenario-hold-ms=")) {
      options.scenarioHoldMs = parseNonNegativeInteger(arg.slice("--scenario-hold-ms=".length), "--scenario-hold-ms");
    } else if (arg === "--scenario-repetitions") {
      options.scenarioRepetitions = parsePositiveInteger(readValue(index, arg), "--scenario-repetitions");
      index += 1;
    } else if (arg.startsWith("--scenario-repetitions=")) {
      options.scenarioRepetitions = parsePositiveInteger(arg.slice("--scenario-repetitions=".length), "--scenario-repetitions");
    } else if (arg === "--duration-ms") {
      options.durationMs = parseNonNegativeInteger(readValue(index, arg), "--duration-ms");
      options.durationMsExplicit = true;
      index += 1;
    } else if (arg.startsWith("--duration-ms=")) {
      options.durationMs = parseNonNegativeInteger(arg.slice("--duration-ms=".length), "--duration-ms");
      options.durationMsExplicit = true;
    } else if (arg === "--sample-interval-ms") {
      options.sampleIntervalMs = parsePositiveInteger(readValue(index, arg), "--sample-interval-ms");
      index += 1;
    } else if (arg.startsWith("--sample-interval-ms=")) {
      options.sampleIntervalMs = parsePositiveInteger(arg.slice("--sample-interval-ms=".length), "--sample-interval-ms");
    } else if (arg === "--settle-ms") {
      options.settleMs = parseNonNegativeInteger(readValue(index, arg), "--settle-ms");
      index += 1;
    } else if (arg.startsWith("--settle-ms=")) {
      options.settleMs = parseNonNegativeInteger(arg.slice("--settle-ms=".length), "--settle-ms");
    } else if (arg === "--dock-collection-timeout-ms") {
      options.dockCollectionTimeoutMs = parsePositiveInteger(readValue(index, arg), "--dock-collection-timeout-ms");
      index += 1;
    } else if (arg.startsWith("--dock-collection-timeout-ms=")) {
      options.dockCollectionTimeoutMs = parsePositiveInteger(arg.slice("--dock-collection-timeout-ms=".length), "--dock-collection-timeout-ms");
    } else if (arg === "--stream-compare-attempts") {
      options.streamCompareAttempts = parseNonNegativeInteger(readValue(index, arg), "--stream-compare-attempts");
      index += 1;
    } else if (arg.startsWith("--stream-compare-attempts=")) {
      options.streamCompareAttempts = parseNonNegativeInteger(arg.slice("--stream-compare-attempts=".length), "--stream-compare-attempts");
    } else if (arg === "--stream-compare-delay-ms") {
      options.streamCompareDelayMs = parseNonNegativeInteger(readValue(index, arg), "--stream-compare-delay-ms");
      index += 1;
    } else if (arg.startsWith("--stream-compare-delay-ms=")) {
      options.streamCompareDelayMs = parseNonNegativeInteger(arg.slice("--stream-compare-delay-ms=".length), "--stream-compare-delay-ms");
    } else if (arg === "--max-stream-lag-ms") {
      options.maxStreamLagMs = parseNonNegativeInteger(readValue(index, arg), "--max-stream-lag-ms");
      index += 1;
    } else if (arg.startsWith("--max-stream-lag-ms=")) {
      options.maxStreamLagMs = parseNonNegativeInteger(arg.slice("--max-stream-lag-ms=".length), "--max-stream-lag-ms");
    } else if (arg === "--detail") {
      options.detail = readValue(index, arg);
      index += 1;
    } else if (arg.startsWith("--detail=")) {
      options.detail = arg.slice("--detail=".length);
    } else if (arg === "--detail-limit") {
      options.detailLimit = parsePositiveInteger(readValue(index, arg), "--detail-limit");
      index += 1;
    } else if (arg.startsWith("--detail-limit=")) {
      options.detailLimit = parsePositiveInteger(arg.slice("--detail-limit=".length), "--detail-limit");
    } else if (arg === "--detail-observe-ms") {
      options.detailObserveMs = parseNonNegativeInteger(readValue(index, arg), "--detail-observe-ms");
      index += 1;
    } else if (arg.startsWith("--detail-observe-ms=")) {
      options.detailObserveMs = parseNonNegativeInteger(arg.slice("--detail-observe-ms=".length), "--detail-observe-ms");
    } else if (arg === "--no-detail-live") {
      options.detailLive = false;
    } else if (arg === "--no-detail-buffer-initial-live") {
      options.detailBufferInitialLive = false;
    } else if (arg === "--request-timeout-ms") {
      options.requestTimeoutMs = parsePositiveInteger(readValue(index, arg), "--request-timeout-ms");
      index += 1;
    } else if (arg.startsWith("--request-timeout-ms=")) {
      options.requestTimeoutMs = parsePositiveInteger(arg.slice("--request-timeout-ms=".length), "--request-timeout-ms");
    } else if (arg === "--json-out") {
      options.jsonOut = readValue(index, arg);
      index += 1;
    } else if (arg.startsWith("--json-out=")) {
      options.jsonOut = arg.slice("--json-out=".length);
    } else if (arg === "--summary-out") {
      options.summaryOut = readValue(index, arg);
      index += 1;
    } else if (arg.startsWith("--summary-out=")) {
      options.summaryOut = arg.slice("--summary-out=".length);
    } else if (arg === "--summary-only") {
      options.summaryOnly = true;
    } else if (arg === "--fail-on-diff") {
      options.failOnDiff = true;
    } else {
      throw new Error(`unknown option: ${arg}`);
    }
  }

  if (!MODES.has(options.mode)) {
    throw new Error("--mode must be one-shot, read-only-real-home, soak, or scenario");
  }
  if (!DETAIL_MODES.has(options.detail)) {
    throw new Error("--detail must be none, sampled, or all");
  }
  if (!TURN_SORT_DIRECTIONS.has(options.turnSortDirection)) {
    throw new Error("--turn-sort-direction must be asc or desc");
  }
  if (!TURN_ITEMS_VIEWS.has(options.turnItemsView)) {
    throw new Error("--turn-items-view must be notLoaded, summary, or full");
  }
  if (!SCENARIOS.has(options.scenario)) {
    throw new Error("--scenario must be archive-toggle, detail-reconnect, live-lease-expiry, multi-host-isolation, rename-title, resync-gap, server-request, source-refresh, spawn-edge, thread-activity, or all");
  }
  try {
    const relayURL = new URL(options.relayUrl);
    if (!["ws:", "wss:"].includes(relayURL.protocol)) {
      throw new Error("invalid relay websocket protocol");
    }
    if (relayURL.port === "4500") {
      throw new Error("--relay-url must point at the Dock relay, not the raw app-server :4500 endpoint");
    }
  } catch (error) {
    if (String(error?.message || error).includes("raw app-server")) {
      throw error;
    }
    throw new Error(`--relay-url must be a valid ws:// or wss:// URL: ${options.relayUrl}`);
  }

  options.limit = Math.min(options.limit, THREAD_LIST_MAX_LIMIT);
  options.codexHome = resolveUserPath(options.codexHome, cwd);
  options.sqliteHome = resolveUserPath(options.sqliteHome || options.codexHome, cwd);
  options.jsonOut = options.jsonOut ? resolveUserPath(options.jsonOut, cwd) : null;
  options.summaryOut = options.summaryOut ? resolveUserPath(options.summaryOut, cwd) : null;
  delete options.turnItemsViewExplicit;
  return options;
}

function textFingerprint(value) {
  if (typeof value !== "string") {
    return value;
  }
  return {
    kind: "textFingerprint",
    length: value.length,
    sha256: crypto.createHash("sha256").update(value).digest("hex").slice(0, 16),
  };
}

function displayTitleFingerprint(value) {
  if (typeof value !== "string") {
    return value ?? null;
  }
  return textFingerprint(value.trimEnd());
}

function normalizeForComparison(value, key = "") {
  if (value === null || value === undefined) {
    return value ?? null;
  }
  if (typeof value === "string") {
    if (SECRET_FIELD_RE.test(key)) {
      return "[redacted]";
    }
    if (TEXT_FIELD_RE.test(key)) {
      return textFingerprint(value);
    }
    return value;
  }
  if (typeof value === "number" || typeof value === "boolean") {
    return value;
  }
  if (Array.isArray(value)) {
    return value.map((entry) => normalizeForComparison(entry, key));
  }
  if (typeof value === "object") {
    const normalized = {};
    for (const objectKey of Object.keys(value).sort()) {
      if (SECRET_FIELD_RE.test(objectKey)) {
        normalized[objectKey] = "[redacted]";
      } else {
        normalized[objectKey] = normalizeForComparison(value[objectKey], objectKey);
      }
    }
    return normalized;
  }
  return String(value);
}

function stableJSONString(value) {
  return JSON.stringify(normalizeForComparison(value));
}

function recordRoute(events, route, purpose, details = {}) {
  if (!Array.isArray(events)) {
    return;
  }
  events.push({
    route,
    purpose,
    countedAsClientPath: CLIENT_PATH_ROUTES.has(route),
    at: new Date().toISOString(),
    ...normalizeForComparison(details),
  });
}

function summarizeClientPathEvents(events = []) {
    const routeCounts = {};
    const nonClientPathRouteCounts = new Map();
    for (const event of events) {
        if (event.countedAsClientPath) {
            routeCounts[event.route] = (routeCounts[event.route] || 0) + 1;
        } else {
            nonClientPathRouteCounts.set(event.route, (nonClientPathRouteCounts.get(event.route) || 0) + 1);
        }
    }
    return {
        routes: Object.keys(routeCounts).sort(),
        routeCounts,
        nonClientPathRoutes: [...nonClientPathRouteCounts.entries()]
            .sort(([left], [right]) => left.localeCompare(right))
            .map(([route, count]) => ({ route, count })),
        eventCount: events.length,
        events,
        note: "Only countedAsClientPath=true events are proof that the relay routes used by the client were exercised. Oracle reads diagnose drift but do not count as client-path proof.",
    };
}

function cardID(card) {
  return card?.projectionID || null;
}

function projectionCardValidationFindings(card, { receivedAt, index, view }) {
  const findings = [];
  const requiredStrings = [
    "sourceHostID",
    "view",
    "projectionID",
    "sourceRef",
    "rowRole",
    "displayOrderKey",
    "threadID",
  ];
  for (const field of requiredStrings) {
    if (typeof card?.[field] !== "string" || card[field].trim().length === 0) {
      findings.push({
        code: "dock_stream_projection_row_missing_field",
        severity: "error",
        message: `dock stream projection row is missing ${field}`,
        field,
        rowIndex: index,
        receivedAt,
      });
    }
  }
  if (card?.schemaVersion !== PROJECTION_SCHEMA_VERSION
      || card?.identityVersion !== PROJECTION_IDENTITY_VERSION
      || card?.projectionEngineVersion !== PROJECTION_ENGINE_VERSION) {
    findings.push({
      code: "dock_stream_projection_row_version_mismatch",
      severity: "error",
      message: "dock stream projection row version fields do not match the expected projection contract",
      rowIndex: index,
      expected: {
        schemaVersion: PROJECTION_SCHEMA_VERSION,
        identityVersion: PROJECTION_IDENTITY_VERSION,
        projectionEngineVersion: PROJECTION_ENGINE_VERSION,
      },
      actual: {
        schemaVersion: card?.schemaVersion ?? null,
        identityVersion: card?.identityVersion ?? null,
        projectionEngineVersion: card?.projectionEngineVersion ?? null,
      },
      receivedAt,
    });
  }
  if (view && card?.view !== view) {
    findings.push({
      code: "dock_stream_projection_row_view_mismatch",
      severity: "error",
      message: "dock stream projection row view does not match the stream view",
      rowIndex: index,
      expected: view,
      actual: card?.view || null,
      receivedAt,
    });
  }
  if (card?.id !== card?.projectionID) {
    findings.push({
      code: "dock_stream_projection_row_id_mismatch",
      severity: "error",
      message: "dock stream projection row id must equal projectionID",
      rowIndex: index,
      id: card?.id || null,
      projectionID: card?.projectionID || null,
      receivedAt,
    });
  }
  if (card?.logicalHostID !== undefined && card?.logicalHostID !== card?.sourceHostID) {
    findings.push({
      code: "dock_stream_projection_row_logical_host_mismatch",
      severity: "error",
      message: "dock stream projection row logicalHostID must not diverge from sourceHostID",
      rowIndex: index,
      logicalHostID: card?.logicalHostID || null,
      sourceHostID: card?.sourceHostID || null,
      receivedAt,
    });
  }
  if (card?.rowRole !== "threadCard") {
    findings.push({
      code: "dock_stream_projection_row_role_mismatch",
      severity: "error",
      message: "dock stream projection row role must be threadCard",
      rowIndex: index,
      rowRole: card?.rowRole || null,
      receivedAt,
    });
  }
  return findings;
}

function cardThreadID(card) {
  return card?.threadID || card?.threadId || null;
}

function sanitizeCardForReport(card) {
  const projectionID = cardID(card);
  return normalizeForComparison({
    id: projectionID,
    projectionID,
    sourceHostID: card?.sourceHostID || null,
    threadID: cardThreadID(card),
    status: card?.status || null,
    lane: card?.lane || null,
    sourceKind: card?.sourceKind || null,
    archived: card?.archived ?? null,
    title: displayTitleFingerprint(card?.title ?? null),
    displaySummary: card?.displaySummary ?? null,
    latestSummary: card?.latestSummary ?? null,
    preview: card?.preview ?? null,
    updatedAt: card?.updatedAt ?? null,
    activityAt: card?.activityAt ?? null,
    activityAtMs: card?.activityAtMs ?? null,
    displayOrderKey: card?.displayOrderKey ?? null,
  });
}

function sanitizeDockSnapshotForReport(snapshot) {
  if (!snapshot) {
    return null;
  }
  const rows = Array.isArray(snapshot.rows) ? snapshot.rows : [];
  const orderedRows = rows.slice().sort((left, right) => {
    const leftOrder = typeof left?.displayOrderKey === "string" ? left.displayOrderKey : "";
    const rightOrder = typeof right?.displayOrderKey === "string" ? right.displayOrderKey : "";
    if (leftOrder !== rightOrder) {
      return leftOrder.localeCompare(rightOrder);
    }
    return String(cardID(left) || "").localeCompare(String(cardID(right) || ""));
  });
  return {
    kind: snapshot.kind || null,
    schemaVersion: snapshot.schemaVersion ?? null,
    epoch: snapshot.epoch || null,
    seq: snapshot.seq ?? null,
    view: snapshot.view || null,
    complete: snapshot.complete ?? null,
    totalRows: snapshot.totalRows ?? null,
    window: snapshot.window || null,
    rowCount: rows.length,
    projectionIDs: rows.map(cardID).filter(Boolean).sort(),
    renderOrderProjectionIDs: orderedRows.map(cardID).filter(Boolean),
    rows: orderedRows.map(sanitizeCardForReport),
    freshness: snapshot.freshness || null,
    lastReceivedAt: snapshot.lastReceivedAt || null,
    needsResync: Boolean(snapshot.needsResync),
    collection: snapshot.collection || null,
  };
}

function cardsByID(cards = []) {
  const map = new Map();
  for (const card of Array.isArray(cards) ? cards : []) {
    const id = cardID(card);
    if (id) {
      map.set(id, card);
    }
  }
  return map;
}

function dockStateFromPayload(payload) {
  const rows = Array.isArray(payload?.rows) ? payload.rows : [];
  return {
    kind: payload?.kind || null,
    schemaVersion: payload?.schemaVersion ?? null,
    epoch: payload?.epoch || null,
    seq: Number.isFinite(Number(payload?.seq)) ? Number(payload.seq) : null,
    view: payload?.view || null,
    complete: payload?.complete ?? null,
    totalRows: Number.isFinite(Number(payload?.totalRows)) ? Number(payload.totalRows) : null,
    window: payload?.window || null,
    freshness: payload?.freshness || null,
    rows,
    projectionIDs: rows.map(cardID).filter(Boolean).sort(),
  };
}

function dockRenderOrderIDs(snapshot) {
  return (Array.isArray(snapshot?.rows) ? snapshot.rows : [])
    .slice()
    .sort((left, right) => {
      const leftOrder = typeof left?.displayOrderKey === "string" ? left.displayOrderKey : "";
      const rightOrder = typeof right?.displayOrderKey === "string" ? right.displayOrderKey : "";
      if (leftOrder !== rightOrder) {
        return leftOrder.localeCompare(rightOrder);
      }
      return String(cardID(left) || "").localeCompare(String(cardID(right) || ""));
    })
    .map(cardID)
    .filter(Boolean);
}

function emptyDockStreamState() {
  return {
    epoch: null,
    seq: null,
    generation: null,
    view: null,
    complete: null,
    totalRows: null,
    window: null,
    freshness: null,
    cardsByID: new Map(),
    needsResync: false,
    lastPayloadKind: null,
    lastReceivedAt: null,
  };
}

function applyDockPayload(state, payload, receivedAt = new Date().toISOString()) {
  const findings = [];
  if (!payload || typeof payload !== "object") {
    findings.push({
      code: "dock_stream_invalid_payload",
      severity: "error",
      message: "dock stream payload is not an object",
      receivedAt,
    });
    return findings;
  }
  if (payload.schemaVersion !== RELAY_STATE_STREAM_SCHEMA_VERSION) {
    findings.push({
      code: "dock_stream_schema_mismatch",
      severity: "error",
      message: `dock stream schema version differs from expected schemaVersion ${RELAY_STATE_STREAM_SCHEMA_VERSION}`,
      expected: RELAY_STATE_STREAM_SCHEMA_VERSION,
      actual: payload.schemaVersion ?? null,
      receivedAt,
    });
    state.needsResync = true;
  }
  for (const key of Object.keys(payload)) {
    if (FORBIDDEN_DOCK_STREAM_KEYS.has(key)) {
      findings.push({
        code: "dock_stream_forbidden_legacy_key",
        severity: "error",
        message: "dock stream payload contains a forbidden legacy key",
        key,
        receivedAt,
      });
      state.needsResync = true;
    }
  }

  if (payload.kind === "snapshot") {
    const rows = Array.isArray(payload.rows) ? payload.rows : [];
    rows.forEach((card, index) => {
      findings.push(...projectionCardValidationFindings(card, {
        receivedAt,
        index,
        view: payload.view,
      }));
    });
    const hasErrors = findings.some((finding) => finding.severity === "error");
    state.epoch = payload.epoch || null;
    state.seq = Number.isFinite(Number(payload.seq)) ? Number(payload.seq) : null;
    state.generation = Number.isFinite(Number(payload.generation)) ? Number(payload.generation) : null;
    state.view = payload.view || null;
    state.complete = payload.complete ?? null;
    state.totalRows = Number.isFinite(Number(payload.totalRows)) ? Number(payload.totalRows) : null;
    state.window = payload.window || null;
    state.freshness = payload.freshness || null;
    state.cardsByID = cardsByID(rows);
    state.needsResync = hasErrors;
    state.lastPayloadKind = "snapshot";
    state.lastReceivedAt = receivedAt;
    return findings;
  }

  if (payload.kind === "heartbeat") {
    const seq = Number.isFinite(Number(payload.seq)) ? Number(payload.seq) : null;
    const totalRows = Number.isFinite(Number(payload.totalRows)) ? Number(payload.totalRows) : null;
    const generation = Number.isFinite(Number(payload.generation)) ? Number(payload.generation) : null;
    if (state.epoch && payload.epoch && state.epoch !== payload.epoch) {
      findings.push({
        code: "dock_stream_epoch_changed",
        severity: "warning",
        message: "dock stream epoch changed; resync is required",
        previousEpoch: state.epoch,
        actualEpoch: payload.epoch,
        receivedAt,
      });
      state.needsResync = true;
    }
    if (seq !== null && state.seq !== null && seq !== state.seq) {
      findings.push({
        code: "dock_stream_heartbeat_sequence_gap",
        severity: "error",
        message: "dock/update heartbeat seq does not match current stream seq",
        expectedSeq: state.seq,
        actualSeq: seq,
        receivedAt,
      });
      state.needsResync = true;
    }
    if (generation !== null && state.generation !== null && generation !== state.generation) {
      findings.push({
        code: "dock_stream_generation_changed",
        severity: "warning",
        message: "dock/update heartbeat generation does not match current stream generation",
        expectedGeneration: state.generation,
        actualGeneration: generation,
        receivedAt,
      });
      state.needsResync = true;
    }
    state.epoch = payload.epoch || state.epoch;
    state.seq = seq ?? state.seq;
    state.generation = generation ?? state.generation;
    state.view = payload.view || state.view;
    if (payload.complete === true) {
      state.complete = totalRows === null ? state.complete : state.cardsByID.size >= totalRows;
    } else if (payload.complete === false) {
      state.complete = false;
    }
    state.totalRows = totalRows ?? state.totalRows;
    state.window = payload.window || state.window;
    state.freshness = payload.freshness || state.freshness;
    state.lastPayloadKind = "heartbeat";
    state.lastReceivedAt = receivedAt;
    return findings;
  }

  if (payload.kind === "page") {
    const seq = Number.isFinite(Number(payload.seq)) ? Number(payload.seq) : null;
    const generation = Number.isFinite(Number(payload.generation)) ? Number(payload.generation) : null;
    const totalRows = Number.isFinite(Number(payload.totalRows)) ? Number(payload.totalRows) : null;
    const window = payload.window && typeof payload.window === "object" ? payload.window : null;
    if (!state.epoch || state.seq === null || state.generation === null) {
      findings.push({
        code: "dock_stream_page_without_snapshot",
        severity: "error",
        message: "dock/update page arrived before an initial snapshot opened the stream",
        receivedAt,
      });
      state.needsResync = true;
    }
    if (state.epoch && payload.epoch && state.epoch !== payload.epoch) {
      findings.push({
        code: "dock_stream_epoch_changed",
        severity: "warning",
        message: "dock stream epoch changed; resync is required",
        previousEpoch: state.epoch,
        actualEpoch: payload.epoch,
        receivedAt,
      });
      state.needsResync = true;
    }
    if (seq !== null && state.seq !== null && seq !== state.seq) {
      findings.push({
        code: "dock_stream_page_sequence_gap",
        severity: "error",
        message: "dock/update page seq must match the current stream seq",
        expectedSeq: state.seq,
        actualSeq: seq,
        receivedAt,
      });
      state.needsResync = true;
    }
    if (generation !== null && state.generation !== null && generation !== state.generation) {
      findings.push({
        code: "dock_stream_page_generation_gap",
        severity: "error",
        message: "dock/update page generation must match the current stream generation",
        expectedGeneration: state.generation,
        actualGeneration: generation,
        receivedAt,
      });
      state.needsResync = true;
    }
    const rows = Array.isArray(payload.rows) ? payload.rows : [];
    if (
      !window
      || !Number.isFinite(Number(window.offset))
      || !Number.isFinite(Number(window.limit))
      || !Number.isFinite(Number(window.rowCount))
      || totalRows === null
      || Number(window.offset) < 0
      || Number(window.limit) < 0
      || Number(window.rowCount) !== rows.length
      || totalRows < Number(window.rowCount)
    ) {
      findings.push({
        code: "dock_stream_page_window_invalid",
        severity: "error",
        message: "dock/update page is missing its catch-up window contract",
        receivedAt,
      });
      state.needsResync = true;
    }
    rows.forEach((card, index) => {
      findings.push(...projectionCardValidationFindings(card, {
        receivedAt,
        index,
        view: payload.view || state.view,
      }));
    });
    if (Array.isArray(payload.projectionIDs) && payload.projectionIDs.length > 0) {
      findings.push({
        code: "dock_stream_page_delete_ids_present",
        severity: "error",
        message: "dock/update page must extend the catch-up window without deleting projection IDs",
        receivedAt,
      });
      state.needsResync = true;
    }
    if (findings.some((finding) => finding.severity === "error")) {
      state.needsResync = true;
    }
    for (const card of rows) {
      const id = cardID(card);
      if (id) {
        state.cardsByID.set(id, card);
      }
    }
    state.epoch = payload.epoch || state.epoch;
    state.seq = seq ?? state.seq;
    state.generation = generation ?? state.generation;
    state.view = payload.view || state.view;
    state.complete = payload.complete ?? state.complete;
    state.totalRows = totalRows ?? state.totalRows;
    state.window = window || state.window;
    state.freshness = payload.freshness || state.freshness;
    state.lastPayloadKind = "page";
    state.lastReceivedAt = receivedAt;
    return findings;
  }

  if (payload.kind === "resyncRequired") {
    state.needsResync = true;
    state.lastPayloadKind = "resyncRequired";
    state.lastReceivedAt = receivedAt;
    return findings;
  }

  if (payload.kind !== "upsert" && payload.kind !== "delete") {
    findings.push({
      code: "dock_stream_unknown_payload_kind",
      severity: "error",
      message: "dock stream payload kind is neither snapshot, page, upsert, delete, heartbeat, nor resyncRequired",
      actual: payload.kind || null,
      receivedAt,
    });
    state.needsResync = true;
    return findings;
  }

  const seq = Number.isFinite(Number(payload.seq)) ? Number(payload.seq) : null;
  const generation = Number.isFinite(Number(payload.generation)) ? Number(payload.generation) : null;
  if (state.epoch && payload.epoch && state.epoch !== payload.epoch) {
    findings.push({
      code: "dock_stream_epoch_changed",
      severity: "warning",
      message: "dock stream epoch changed; resync is required",
      previousEpoch: state.epoch,
      actualEpoch: payload.epoch,
      receivedAt,
    });
    state.needsResync = true;
  }
  if (seq !== null && state.seq !== null && seq !== state.seq + 1) {
    findings.push({
      code: "dock_stream_sequence_gap",
      severity: "error",
      message: "dock/update seq is not contiguous with current stream seq",
      expectedSeq: state.seq + 1,
      actualSeq: seq,
      receivedAt,
    });
      state.needsResync = true;
  }
  if (generation !== null && state.generation !== null && generation !== state.generation) {
    findings.push({
      code: "dock_stream_generation_changed",
      severity: "warning",
      message: "dock/update mutation generation does not match current stream generation",
      expectedGeneration: state.generation,
      actualGeneration: generation,
      receivedAt,
    });
    state.needsResync = true;
  }

  const rows = Array.isArray(payload.rows) ? payload.rows : [];
  rows.forEach((card, index) => {
    findings.push(...projectionCardValidationFindings(card, {
      receivedAt,
      index,
      view: payload.view || state.view,
    }));
  });
  if (findings.some((finding) => finding.severity === "error")) {
    state.needsResync = true;
  }
  for (const card of rows) {
    const id = cardID(card);
    if (id) {
      state.cardsByID.set(id, card);
    }
  }
  for (const id of Array.isArray(payload.projectionIDs) ? payload.projectionIDs : []) {
    state.cardsByID.delete(id);
  }
  state.epoch = payload.epoch || state.epoch;
  state.seq = seq ?? state.seq;
  state.generation = generation ?? state.generation;
  state.view = payload.view || state.view;
  state.complete = payload.complete ?? state.complete;
  state.totalRows = Number.isFinite(Number(payload.totalRows)) ? Number(payload.totalRows) : state.totalRows;
  state.window = payload.window || state.window;
  state.freshness = payload.freshness || state.freshness;
  state.lastPayloadKind = payload.kind;
  state.lastReceivedAt = receivedAt;
  return findings;
}

function isDockStreamStateComplete(state, lastUpdate = null) {
  const totalRows = Number.isFinite(Number(lastUpdate?.totalRows))
    ? Number(lastUpdate.totalRows)
    : (Number.isFinite(Number(state.totalRows)) ? Number(state.totalRows) : null);
  if (lastUpdate?.complete === true || state.complete === true) {
    return totalRows === null ? true : state.cardsByID.size >= totalRows;
  }
  const window = lastUpdate?.window || state.window || null;
  if (!window || window.nextOffset !== null) {
    return false;
  }
  return totalRows !== null && state.cardsByID.size >= totalRows;
}

function snapshotFromStreamState(state) {
  const cards = [...(state.cardsByID || new Map()).values()];
  return {
    kind: state.lastPayloadKind || null,
    schemaVersion: RELAY_STATE_STREAM_SCHEMA_VERSION,
    epoch: state.epoch || null,
    seq: state.seq ?? null,
    generation: state.generation ?? null,
    view: state.view || null,
    complete: state.complete ?? null,
    totalRows: state.totalRows ?? cards.length,
    window: state.window || null,
    freshness: state.freshness || null,
    rows: cards,
    projectionIDs: cards.map(cardID).filter(Boolean).sort(),
    lastReceivedAt: state.lastReceivedAt || null,
    needsResync: Boolean(state.needsResync),
  };
}

function firstDifferingKeys(left, right) {
  const keys = new Set([
    ...Object.keys(left || {}),
    ...Object.keys(right || {}),
  ]);
  return [...keys].filter((key) => stableJSONString(left?.[key]) !== stableJSONString(right?.[key])).sort();
}

function compareDockStates(streamSnapshot, freshSnapshot) {
  const findings = [];
  const streamCardsByID = cardsByID(streamSnapshot.rows || []);
  const freshCardsByID = cardsByID(freshSnapshot.rows || []);
  const streamIDs = [...streamCardsByID.keys()].sort();
  const freshIDs = [...freshCardsByID.keys()].sort();
  const streamRenderOrderIDs = dockRenderOrderIDs(streamSnapshot);
  const freshRenderOrderIDs = dockRenderOrderIDs(freshSnapshot);
  if (stableJSONString(streamIDs) !== stableJSONString(freshIDs)) {
    const streamSet = new Set(streamIDs);
    const freshSet = new Set(freshIDs);
    findings.push({
      code: "dock_stream_card_set_mismatch",
      severity: "error",
      message: "long-lived dock stream card set differs from fresh dock/subscribe snapshot",
      missingFromStream: freshIDs.filter((id) => !streamSet.has(id)),
      extraInStream: streamIDs.filter((id) => !freshSet.has(id)),
    });
  }
  if (stableJSONString(streamRenderOrderIDs) !== stableJSONString(freshRenderOrderIDs)) {
    findings.push({
      code: "dock_stream_render_order_mismatch",
      severity: "error",
      message: "long-lived dock stream render order differs from fresh dock/subscribe snapshot",
      streamOrder: streamRenderOrderIDs,
      freshOrder: freshRenderOrderIDs,
    });
  }
  if (streamSnapshot.complete !== freshSnapshot.complete) {
    findings.push({
      code: "dock_stream_complete_mismatch",
      severity: "error",
      message: "long-lived dock stream complete flag differs from fresh dock/subscribe snapshot",
      stream: streamSnapshot.complete,
      fresh: freshSnapshot.complete,
    });
  }
  if (streamSnapshot.totalRows !== freshSnapshot.totalRows) {
    findings.push({
      code: "dock_stream_total_rows_mismatch",
      severity: "error",
      message: "long-lived dock stream totalRows differs from fresh dock/subscribe snapshot",
      stream: streamSnapshot.totalRows,
      fresh: freshSnapshot.totalRows,
    });
  }
  const streamFreshness = comparableFreshness(streamSnapshot.freshness);
  const freshFreshness = comparableFreshness(freshSnapshot.freshness);
  if (stableJSONString(streamFreshness) !== stableJSONString(freshFreshness)) {
    findings.push({
      code: "dock_stream_freshness_mismatch",
      severity: "error",
      message: "long-lived dock stream freshness differs from fresh dock/subscribe snapshot",
      stream: streamFreshness,
      fresh: freshFreshness,
    });
  }
  for (const id of streamIDs.filter((candidate) => freshCardsByID.has(candidate))) {
    const streamCard = normalizeForComparison(streamCardsByID.get(id));
    const freshCard = normalizeForComparison(freshCardsByID.get(id));
    if (stableJSONString(streamCard) !== stableJSONString(freshCard)) {
      findings.push({
        code: "dock_stream_card_payload_mismatch",
        severity: "error",
        message: "long-lived dock stream card payload differs from fresh dock/subscribe snapshot",
        cardID: id,
        threadID: cardThreadID(streamCardsByID.get(id)) || cardThreadID(freshCardsByID.get(id)),
        differingKeys: firstDifferingKeys(streamCard, freshCard),
      });
    }
  }
  return {
    ok: findings.length === 0,
    findings,
    streamCardCount: streamIDs.length,
    freshCardCount: freshIDs.length,
  };
}

function compareDockThreadCard(streamSnapshot, freshSnapshot, threadID) {
  const findings = [];
  const streamCard = dockSnapshotCardForThread(streamSnapshot, threadID);
  const freshCard = dockSnapshotCardForThread(freshSnapshot, threadID);
  if (!streamCard || !freshCard) {
    if (Boolean(streamCard) !== Boolean(freshCard)) {
      findings.push({
        code: "dock_stream_thread_card_presence_mismatch",
        severity: "error",
        message: "long-lived dock stream target thread presence differs from fresh dock/subscribe snapshot",
        threadID,
        present: Boolean(streamCard),
        expected: Boolean(freshCard),
      });
    }
    return {
      ok: findings.length === 0,
      findings,
      streamCardCount: streamCard ? 1 : 0,
      freshCardCount: freshCard ? 1 : 0,
    };
  }

  const streamComparable = normalizeForComparison(streamCard);
  const freshComparable = normalizeForComparison(freshCard);
  if (stableJSONString(streamComparable) !== stableJSONString(freshComparable)) {
    findings.push({
      code: "dock_stream_thread_card_payload_mismatch",
      severity: "error",
      message: "long-lived dock stream target thread card payload differs from fresh dock/subscribe snapshot",
      cardID: cardID(streamCard) || cardID(freshCard),
      threadID,
      differingKeys: firstDifferingKeys(streamComparable, freshComparable),
    });
  }
  return {
    ok: findings.length === 0,
    findings,
    streamCardCount: 1,
    freshCardCount: 1,
  };
}

function comparableFreshness(freshness) {
  if (!freshness || typeof freshness !== "object") {
    return null;
  }
  return {
    status: freshness.status || null,
    lastError: freshness.lastError || null,
  };
}

function evaluateStreamConvergenceLag(attempts, maxStreamLagMs) {
  const checkedAttempts = (attempts || [])
    .filter((attempt) => Number.isFinite(Number(attempt?.checkedAtMs)))
    .map((attempt) => ({
      ...attempt,
      checkedAtMs: Number(attempt.checkedAtMs),
    }));
  const firstMismatch = checkedAttempts.find((attempt) => attempt.ok === false) || null;
  if (!firstMismatch) {
    const firstAttempt = checkedAttempts[0] || null;
    return {
      ok: true,
      exceeded: false,
      converged: true,
      observedLagMs: 0,
      maxStreamLagMs,
      firstMismatchAttempt: null,
      firstMismatchAt: null,
      convergedAttempt: firstAttempt?.attempt ?? null,
      convergedAt: firstAttempt?.checkedAt || null,
      lastCheckedAt: firstAttempt?.checkedAt || null,
    };
  }

  const converged = checkedAttempts.find(
    (attempt) => attempt.ok === true && attempt.checkedAtMs >= firstMismatch.checkedAtMs,
  ) || null;
  const lastAttempt = checkedAttempts[checkedAttempts.length - 1] || firstMismatch;
  const observedLagMs = Math.max(
    0,
    (converged?.checkedAtMs ?? lastAttempt.checkedAtMs) - firstMismatch.checkedAtMs,
  );
  const exceeded = observedLagMs > maxStreamLagMs;
  return {
    ok: Boolean(converged) && !exceeded,
    exceeded,
    converged: Boolean(converged),
    observedLagMs,
    maxStreamLagMs,
    firstMismatchAttempt: firstMismatch.attempt ?? null,
    firstMismatchAt: firstMismatch.checkedAt || null,
    convergedAttempt: converged?.attempt ?? null,
    convergedAt: converged?.checkedAt || null,
    lastCheckedAt: lastAttempt?.checkedAt || null,
  };
}

function applyStreamLagBudget(comparison, streamLag) {
  if (!streamLag?.exceeded) {
    return comparison;
  }
  const lagFinding = {
    code: "dock_stream_lag_exceeded",
    severity: "error",
    message: "long-lived Dock stream converged too slowly after diverging from a fresh client-path snapshot",
    observedLagMs: streamLag.observedLagMs,
    maxStreamLagMs: streamLag.maxStreamLagMs,
    firstMismatchAttempt: streamLag.firstMismatchAttempt,
    firstMismatchAt: streamLag.firstMismatchAt,
    convergedAttempt: streamLag.convergedAttempt,
    convergedAt: streamLag.convergedAt,
    lastCheckedAt: streamLag.lastCheckedAt,
  };
  return {
    ...comparison,
    ok: false,
    findings: [...(comparison.findings || []), lagFinding],
  };
}

async function compareStreamToFreshDock({ streamProbe, freshDock, options, routeEvents, threadID = null }) {
  let currentFreshDock = freshDock;
  const attempts = [];
  for (let attempt = 0; attempt <= options.streamCompareAttempts; attempt += 1) {
    await streamProbe.waitForComplete(options.dockCollectionTimeoutMs);
    if (attempt > 0) {
      currentFreshDock = await collectDockClientPathSnapshot(options, routeEvents);
    }
    const checkedAtMs = Date.now();
    const checkedAt = new Date(checkedAtMs).toISOString();
    const streamSnapshot = streamProbe.snapshot();
    const comparison = threadID
      ? compareDockThreadCard(streamSnapshot, currentFreshDock, threadID)
      : compareDockStates(streamSnapshot, currentFreshDock);
    attempts.push({
      attempt,
      checkedAt,
      checkedAtMs,
      ok: comparison.ok,
      findingCount: comparison.findings.length,
      streamCardCount: comparison.streamCardCount,
      freshCardCount: comparison.freshCardCount,
      streamSeq: streamSnapshot.seq ?? null,
      freshSeq: currentFreshDock?.seq ?? null,
      streamLastReceivedAt: streamSnapshot.lastReceivedAt || null,
      freshLastReceivedAt: currentFreshDock?.lastReceivedAt || null,
    });
    if (comparison.ok || attempt >= options.streamCompareAttempts) {
      const streamLag = evaluateStreamConvergenceLag(attempts, options.maxStreamLagMs);
      const finalComparison = applyStreamLagBudget(comparison, streamLag);
      return {
        freshDock: currentFreshDock,
        streamSnapshot,
        comparison: finalComparison,
        attempts,
        streamLag,
        settledAfterAttempts: attempt,
      };
    }
    if (options.streamCompareDelayMs > 0) {
      await sleep(options.streamCompareDelayMs);
    }
  }
  throw new Error("unreachable stream comparison loop");
}

function sleep(ms) {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

function waitForAsyncEvent(promise, timeoutMs) {
  let timer = null;
  return Promise.race([
    promise.then((value) => ({ ok: true, value })),
    new Promise((resolve) => {
      timer = setTimeout(() => {
        resolve({ ok: false, value: null, timeoutMs });
      }, timeoutMs);
    }),
  ]).finally(() => {
    if (timer) {
      clearTimeout(timer);
    }
  });
}

function closeWebSocketServer(server) {
  return new Promise((resolve, reject) => {
    server.close((error) => {
      if (error) {
        reject(error);
      } else {
        resolve();
      }
    });
  });
}

async function withRelayClient(options, callbacks, operation, routeEvents = null) {
  const client = new JsonRpcWebSocketClient(options.relayUrl, {
    requestTimeoutMs: options.requestTimeoutMs,
    onNotification: callbacks?.onNotification || null,
    onRequest: callbacks?.onRequest || null,
    onClose: callbacks?.onClose || null,
  });
  recordRoute(routeEvents, "initialize", "open relay client session");
  await initializeClient(client);
  recordRoute(routeEvents, "initialized", "relay client initialized notification sent");
  try {
    return await operation(client);
  } finally {
    await client.close();
  }
}

async function requestDockSnapshot(options, routeEvents = null) {
  return withRelayClient(options, null, async (client) => {
    recordRoute(routeEvents, "dock/subscribe", "fresh client-path Dock snapshot");
    return client.request("dock/subscribe", {});
  }, routeEvents);
}

async function collectDockClientPathSnapshot(options, routeEvents = null) {
  const state = emptyDockStreamState();
  const findings = [];
  const notifications = [];
  const resyncs = [];
  const pendingNotifications = [];
  let initialSnapshotApplied = false;
  let lastUpdate = null;
  let lastAppliedAtMs = null;
  let wake = null;
  const wakeWaiter = () => {
    if (wake) {
      const resolve = wake;
      wake = null;
      resolve();
    }
  };
  const waitForUpdate = (timeoutMs) => new Promise((resolve) => {
    const timer = setTimeout(() => {
      if (wake === done) {
        wake = null;
      }
      resolve(false);
    }, timeoutMs);
    const done = () => {
      clearTimeout(timer);
      resolve(true);
    };
    wake = done;
  });
  const apply = (payload, source, receivedAt = new Date().toISOString()) => {
    lastUpdate = payload;
    lastAppliedAtMs = Date.now();
    const appliedFindings = applyDockPayload(state, payload, receivedAt)
      .map((finding) => ({ ...finding, source }));
    findings.push(...appliedFindings);
    wakeWaiter();
    return appliedFindings;
  };
  const client = new JsonRpcWebSocketClient(options.relayUrl, {
    requestTimeoutMs: options.requestTimeoutMs,
    onNotification: (message) => {
      if (message?.method !== "dock/update") {
        return;
      }
      const receivedAt = new Date().toISOString();
      recordRoute(routeEvents, "dock/update", "collect complete Dock state from streamed client-path update", {
        at: receivedAt,
        kind: message.params?.kind || null,
        seq: message.params?.seq ?? null,
      });
      notifications.push({
        method: message.method,
        receivedAt,
        kind: message.params?.kind || null,
        seq: message.params?.seq ?? null,
        window: message.params?.window || null,
      });
      if (!initialSnapshotApplied) {
        pendingNotifications.push({ payload: message.params, receivedAt });
        return;
      }
      apply(message.params, "notification", receivedAt);
    },
  });
  recordRoute(routeEvents, "initialize", "open complete Dock client-path collector");
  await initializeClient(client);
  recordRoute(routeEvents, "initialized", "complete Dock collector initialized notification sent");
  try {
    recordRoute(routeEvents, "dock/subscribe", "collect complete Dock state from client-path subscription");
    const snapshot = await client.request("dock/subscribe", {});
    apply(snapshot, "subscribe");
    initialSnapshotApplied = true;
    for (const notification of pendingNotifications.splice(0)) {
      apply(notification.payload, "notification", notification.receivedAt);
    }
    const deadline = Date.now() + options.dockCollectionTimeoutMs;

    while (!isDockStreamStateComplete(state, lastUpdate)) {
      if (state.needsResync) {
        const reason = "collector_stream_contract";
        recordRoute(routeEvents, "dock/resync", "resync complete Dock client-path collector", { reason });
        const resynced = await client.request("dock/resync", {});
        apply(resynced, "resync");
        state.needsResync = false;
        resyncs.push({
          reason,
          at: new Date().toISOString(),
          seq: resynced?.seq ?? null,
          rowCount: Array.isArray(resynced?.rows) ? resynced.rows.length : null,
        });
        continue;
      }
      const remainingMs = deadline - Date.now();
      if (remainingMs <= 0) {
        findings.push({
          code: "dock_client_path_collection_timeout",
          severity: "error",
          message: "complete Dock client-path collection timed out before the stream reached complete state",
          timeoutMs: options.dockCollectionTimeoutMs,
          visibleRows: state.cardsByID.size,
          totalRows: state.totalRows,
          window: state.window,
        });
        break;
      }
      await waitForUpdate(Math.min(remainingMs, 1_000));
    }

    // A fresh client can receive a complete-but-stale snapshot before the
    // relay's subscribe-triggered reconciliation publishes the visible rows.
    // Stay on the same production stream through the strict lag budget instead
    // of treating that pre-refresh snapshot as final proof truth.
    while (isDockStreamStateComplete(state, lastUpdate)
      && state.freshness?.status
      && state.freshness.status !== "fresh") {
      const remainingMs = deadline - Date.now();
      const settleBudgetMs = Math.min(
        remainingMs,
        Math.max(0, Number(options.maxStreamLagMs || 0)),
      );
      if (settleBudgetMs <= 0) {
        break;
      }
      const beforeWaitAppliedAtMs = lastAppliedAtMs;
      const sawUpdate = await waitForUpdate(settleBudgetMs);
      if (!sawUpdate || beforeWaitAppliedAtMs === lastAppliedAtMs) {
        break;
      }
      while (!isDockStreamStateComplete(state, lastUpdate)) {
        if (state.needsResync) {
          const reason = "collector_stream_contract";
          recordRoute(routeEvents, "dock/resync", "resync complete Dock client-path collector", { reason });
          const resynced = await client.request("dock/resync", {});
          apply(resynced, "resync");
          state.needsResync = false;
          resyncs.push({
            reason,
            at: new Date().toISOString(),
            seq: resynced?.seq ?? null,
            rowCount: Array.isArray(resynced?.rows) ? resynced.rows.length : null,
          });
          continue;
        }
        const remainingAfterUpdateMs = deadline - Date.now();
        if (remainingAfterUpdateMs <= 0) {
          findings.push({
            code: "dock_client_path_collection_timeout",
            severity: "error",
            message: "complete Dock client-path collection timed out before the stream reached complete state",
            timeoutMs: options.dockCollectionTimeoutMs,
            visibleRows: state.cardsByID.size,
            totalRows: state.totalRows,
            window: state.window,
          });
          break;
        }
        await waitForUpdate(Math.min(remainingAfterUpdateMs, 1_000));
      }
    }

    const collected = snapshotFromStreamState(state);
    const complete = isDockStreamStateComplete(state, lastUpdate);
    return {
      ...collected,
      complete,
      collection: {
        ok: complete && !findings.some((finding) => finding.severity === "error"),
        complete,
        timeoutMs: options.dockCollectionTimeoutMs,
        notificationCount: notifications.length,
        resyncCount: resyncs.length,
        findings,
        notifications,
        resyncs,
      },
    };
  } finally {
    wakeWaiter();
    await client.close();
  }
}

class DockStreamProbe {
  constructor(options) {
    this.options = options;
    this.routeEvents = [];
    this.notifications = [];
    this.findings = [];
    this.resyncs = [];
    this.archiveNotifications = [];
    this.archiveResyncs = [];
    this.closed = false;
    this.wake = null;
    this.dockInitialSnapshotApplied = false;
    this.archiveInitialSnapshotApplied = false;
    this.pendingDockNotifications = [];
    this.pendingArchiveNotifications = [];
    this.state = emptyDockStreamState();
    this.archiveState = emptyDockStreamState();
    this.client = new JsonRpcWebSocketClient(options.relayUrl, {
      requestTimeoutMs: options.requestTimeoutMs,
      onNotification: (message) => this.handleNotification(message),
      onClose: () => {
        this.closed = true;
      },
    });
  }

  async open() {
    recordRoute(this.routeEvents, "initialize", "open long-lived Dock stream client");
    await initializeClient(this.client);
    recordRoute(this.routeEvents, "initialized", "long-lived Dock stream initialized notification sent");
    recordRoute(this.routeEvents, "dock/subscribe", "open long-lived Dock stream subscription");
    const snapshot = await this.client.request("dock/subscribe", {});
    this.applyPayload(snapshot, "subscribe");
    this.dockInitialSnapshotApplied = true;
    this.flushPendingDockNotifications();
    return snapshot;
  }

  async openArchive() {
    recordRoute(this.routeEvents, "archive/subscribe", "open long-lived Archive stream subscription");
    const snapshot = await this.client.request("archive/subscribe", {});
    this.applyArchivePayload(snapshot, "subscribe");
    this.archiveInitialSnapshotApplied = true;
    this.flushPendingArchiveNotifications();
    return snapshot;
  }

  handleNotification(message) {
    const receivedAt = new Date().toISOString();
    if (message?.method === "archive/update") {
      recordRoute(this.routeEvents, "archive/update", "receive long-lived Archive stream update", {
        at: receivedAt,
        kind: message.params?.kind || null,
        seq: message.params?.seq ?? null,
      });
      const notification = {
        method: message.method,
        receivedAt,
        kind: message.params?.kind || null,
        seq: message.params?.seq ?? null,
      };
      if (!this.archiveInitialSnapshotApplied) {
        this.pendingArchiveNotifications.push({ message, receivedAt, notification });
        return;
      }
      this.applyArchiveNotification(message, receivedAt, notification);
      return;
    }
    if (message?.method !== "dock/update") {
      return;
    }
    recordRoute(this.routeEvents, "dock/update", "receive long-lived Dock stream update", {
      at: receivedAt,
      kind: message.params?.kind || null,
      seq: message.params?.seq ?? null,
    });
    const notification = {
      method: message.method,
      receivedAt,
      kind: message.params?.kind || null,
      seq: message.params?.seq ?? null,
    };
    if (!this.dockInitialSnapshotApplied) {
      this.pendingDockNotifications.push({ message, receivedAt, notification });
      return;
    }
    this.applyDockNotification(message, receivedAt, notification);
  }

  applyArchiveNotification(message, receivedAt, notification) {
      this.applyArchivePayload(message.params, "notification", receivedAt);
      if (message.params?.kind === "upsert" || message.params?.kind === "delete" || message.params?.kind === "snapshot" || message.params?.kind === "page") {
        // Store the post-apply stream state so simulator UI proof can compare
        // against live truth at notification time, not just sparse resyncs.
        notification.snapshot = sanitizeDockSnapshotForReport(this.archiveSnapshot());
      }
      this.archiveNotifications.push(notification);
  }

  applyDockNotification(message, receivedAt, notification) {
    this.applyPayload(message.params, "notification", receivedAt);
    if (message.params?.kind === "upsert" || message.params?.kind === "delete" || message.params?.kind === "snapshot" || message.params?.kind === "page") {
      // Store the post-apply stream state so simulator UI proof can compare
      // against live truth at notification time, not just sparse resyncs.
      notification.snapshot = sanitizeDockSnapshotForReport(this.snapshot());
    }
    this.notifications.push(notification);
  }

  flushPendingDockNotifications() {
    for (const pending of this.pendingDockNotifications.splice(0)) {
      this.applyDockNotification(pending.message, pending.receivedAt, pending.notification);
    }
  }

  flushPendingArchiveNotifications() {
    for (const pending of this.pendingArchiveNotifications.splice(0)) {
      this.applyArchiveNotification(pending.message, pending.receivedAt, pending.notification);
    }
  }

  applyPayload(payload, source, receivedAt = new Date().toISOString()) {
    const findings = applyDockPayload(this.state, payload, receivedAt)
      .map((finding) => ({
        ...finding,
        source,
      }));
    this.findings.push(...findings);
    this.wakeWaiter();
    return findings;
  }

  applyArchivePayload(payload, source, receivedAt = new Date().toISOString()) {
    const findings = applyDockPayload(this.archiveState, payload, receivedAt)
      .map((finding) => ({
        ...finding,
        source,
        stream: "archive",
      }));
    this.findings.push(...findings);
    this.wakeWaiter();
    return findings;
  }

  wakeWaiter() {
    if (!this.wake) {
      return;
    }
    const resolve = this.wake;
    this.wake = null;
    resolve();
  }

  waitForUpdate(timeoutMs) {
    return new Promise((resolve) => {
      const timer = setTimeout(() => {
        if (this.wake === done) {
          this.wake = null;
        }
        resolve(false);
      }, timeoutMs);
      const done = () => {
        clearTimeout(timer);
        resolve(true);
      };
      this.wake = done;
    });
  }

  async resync(reason = "manual") {
    const startedAt = new Date().toISOString();
    recordRoute(this.routeEvents, "dock/resync", "resync long-lived Dock stream", { reason });
    const snapshot = await this.client.request("dock/resync", {});
    this.applyPayload(snapshot, "resync");
    this.state.needsResync = false;
    const result = {
      reason,
      startedAt,
      finishedAt: new Date().toISOString(),
      seq: snapshot?.seq ?? null,
      rowCount: Array.isArray(snapshot?.rows) ? snapshot.rows.length : null,
    };
    this.resyncs.push(result);
    return result;
  }

  async archiveResync(reason = "manual") {
    const startedAt = new Date().toISOString();
    recordRoute(this.routeEvents, "archive/resync", "resync long-lived Archive stream", { reason });
    const snapshot = await this.client.request("archive/resync", {});
    this.applyArchivePayload(snapshot, "resync");
    this.archiveState.needsResync = false;
    const result = {
      reason,
      startedAt,
      finishedAt: new Date().toISOString(),
      seq: snapshot?.seq ?? null,
      rowCount: Array.isArray(snapshot?.rows) ? snapshot.rows.length : null,
    };
    this.archiveResyncs.push(result);
    return result;
  }

  async waitForComplete(timeoutMs) {
    const deadline = Date.now() + timeoutMs;
    while (!isDockStreamStateComplete(this.state)) {
      if (this.state.needsResync) {
        await this.resync("wait_for_complete_stream_contract");
        continue;
      }
      const remainingMs = deadline - Date.now();
      if (remainingMs <= 0) {
        const finding = {
          code: "dock_long_lived_stream_collection_timeout",
          severity: "error",
          message: "long-lived Dock stream did not reach complete state before comparison",
          timeoutMs,
          visibleRows: this.state.cardsByID.size,
          totalRows: this.state.totalRows,
          window: this.state.window,
        };
        this.findings.push(finding);
        return {
          complete: false,
          visibleRows: this.state.cardsByID.size,
          totalRows: this.state.totalRows,
        };
      }
      await this.waitForUpdate(Math.min(remainingMs, 1_000));
    }
    return {
      complete: true,
      visibleRows: this.state.cardsByID.size,
      totalRows: this.state.totalRows,
    };
  }

  snapshot() {
    return snapshotFromStreamState(this.state);
  }

  archiveSnapshot() {
    return snapshotFromStreamState(this.archiveState);
  }

  async close() {
    this.wakeWaiter();
    await this.client.close();
  }
}

function selectDetailTargets(dockSnapshot, options) {
  if (options.detail === "none") {
    return [];
  }
  const cards = Array.isArray(dockSnapshot?.rows) ? dockSnapshot.rows : [];
  const targets = cards
    .map((card) => ({
      cardID: cardID(card),
      threadID: cardThreadID(card),
      logicalHostID: card?.logicalHostID || null,
      status: card?.status || null,
    }))
    .filter((target) => nonEmpty(target.threadID) && target.status !== "unknown");
  if (options.detail === "sampled") {
    return targets.slice(0, options.detailLimit);
  }
  return targets;
}

function selectScenarioArchiveTarget(dockSnapshot, requestedThreadID = null) {
  const cards = Array.isArray(dockSnapshot?.rows) ? dockSnapshot.rows : [];
  const candidates = cards
    .map((card) => ({
      cardID: cardID(card),
      threadID: cardThreadID(card),
      logicalHostID: card?.logicalHostID || null,
      status: card?.status || null,
      archived: card?.archived ?? false,
    }))
    .filter((target) => nonEmpty(target.threadID) && target.archived !== true);
  if (requestedThreadID) {
    return candidates.find((target) => target.threadID === requestedThreadID) || null;
  }
  return candidates.sort((left, right) => {
    const leftRank = SCENARIO_ARCHIVE_STATUS_PRIORITY[left.status || "unknown"] ?? 99;
    const rightRank = SCENARIO_ARCHIVE_STATUS_PRIORITY[right.status || "unknown"] ?? 99;
    if (leftRank !== rightRank) {
      return leftRank - rightRank;
    }
    return left.cardID.localeCompare(right.cardID);
  })[0] || null;
}

function selectScenarioRenameTarget(dockSnapshot, requestedThreadID = null) {
  const cards = Array.isArray(dockSnapshot?.rows) ? dockSnapshot.rows : [];
  const candidates = cards
    .map((card) => {
      const title = nonEmpty(card?.title) || nonEmpty(card?.displayTitle) || null;
      return {
        cardID: cardID(card),
        threadID: cardThreadID(card),
        logicalHostID: card?.logicalHostID || null,
        status: card?.status || null,
        archived: card?.archived ?? false,
        title,
      };
    })
    .filter((target) => nonEmpty(target.threadID)
      && target.archived !== true
      && target.status !== "unknown"
      && nonEmpty(target.title));
  if (requestedThreadID) {
    return candidates.find((target) => target.threadID === requestedThreadID) || null;
  }
  return candidates.sort((left, right) => {
    const leftRank = SCENARIO_ARCHIVE_STATUS_PRIORITY[left.status || "unknown"] ?? 99;
    const rightRank = SCENARIO_ARCHIVE_STATUS_PRIORITY[right.status || "unknown"] ?? 99;
    if (leftRank !== rightRank) {
      return leftRank - rightRank;
    }
    return left.cardID.localeCompare(right.cardID);
  })[0] || null;
}

function sanitizeScenarioTargetForReport(target) {
  if (!target) {
    return null;
  }
  return normalizeForComparison({
    cardID: target.cardID || null,
    threadID: target.threadID || null,
    logicalHostID: target.logicalHostID || null,
    status: target.status || null,
    archived: target.archived ?? null,
    title: displayTitleFingerprint(target.title || null),
  });
}

function selectScenarioDetailTarget(dockSnapshot, requestedThreadID = null) {
  const targets = selectDetailTargets(dockSnapshot, {
    detail: "all",
    detailLimit: THREAD_LIST_MAX_LIMIT,
  });
  if (requestedThreadID) {
    return targets.find((target) => target.threadID === requestedThreadID) || null;
  }
  return targets[0] || null;
}

function dockSnapshotHasThread(dockSnapshot, threadID) {
  if (!threadID) {
    return false;
  }
  return (Array.isArray(dockSnapshot?.rows) ? dockSnapshot.rows : [])
    .some((card) => cardThreadID(card) === threadID);
}

function dockSnapshotCardForThread(dockSnapshot, threadID) {
  if (!threadID) {
    return null;
  }
  return (Array.isArray(dockSnapshot?.rows) ? dockSnapshot.rows : [])
    .find((card) => cardThreadID(card) === threadID) || null;
}

function dockSnapshotThreadIndex(dockSnapshot, threadID) {
  const card = dockSnapshotCardForThread(dockSnapshot, threadID);
  if (!card) {
    return -1;
  }
  return dockRenderOrderIDs(dockSnapshot).indexOf(cardID(card));
}

function scenarioLagSummary({ transition, startedAtMs, acknowledgedAtMs, observedAtMs, maxStreamLagMs }) {
  const changeToRelayMs = Number.isFinite(Number(observedAtMs))
    ? Math.max(0, Number(observedAtMs) - Number(startedAtMs))
    : null;
  const ackToRelayMs = Number.isFinite(Number(observedAtMs)) && Number.isFinite(Number(acknowledgedAtMs))
    ? Math.max(0, Number(observedAtMs) - Number(acknowledgedAtMs))
    : null;
  const observedLagMs = ackToRelayMs ?? changeToRelayMs;
  const exceeded = observedLagMs !== null && observedLagMs > maxStreamLagMs;
  return {
    transition,
    startedAt: new Date(startedAtMs).toISOString(),
    acknowledgedAt: Number.isFinite(Number(acknowledgedAtMs)) ? new Date(acknowledgedAtMs).toISOString() : null,
    relaySeenAt: Number.isFinite(Number(observedAtMs)) ? new Date(observedAtMs).toISOString() : null,
    lag_change_to_relay_ms: changeToRelayMs,
    lag_ack_to_relay_ms: ackToRelayMs,
    observedLagMs,
    maxStreamLagMs,
    ok: observedLagMs !== null && !exceeded,
    exceeded,
  };
}

function scenarioTransitionName(baseName, iteration, repetitions) {
  if (Number(repetitions) <= 1) {
    return baseName;
  }
  return `${baseName}-${iteration}`;
}

function scenarioRequirementImplemented(scenario, options) {
  if (!SCENARIOS.has(scenario.implementedBy)) {
    return false;
  }
  const requiredRepetitions = Number(scenario.requiresRepetitions || 1);
  if (scenario.implementedBy !== "archive-toggle") {
    return true;
  }
  return Number(options.scenarioRepetitions || 1) >= requiredRepetitions;
}

function unsupportedScenarioFindingsFor(options) {
  if (options.scenario !== "all") {
    return [];
  }
  return REQUIRED_SCENARIOS
    .filter((scenario) => !scenarioRequirementImplemented(scenario, options))
    .map((scenario) => ({
      code: "scenario_required_case_not_implemented",
      severity: "warning",
      scenarioID: scenario.id,
      message: scenario.requiresRepetitions
        ? `required scenario needs archive-toggle repetitions >= ${scenario.requiresRepetitions}: ${scenario.label}`
        : `required scenario is not implemented in this slice: ${scenario.label}`,
    }));
}

function detailMessageThreadID(message) {
  return message?.params?.threadId || message?.params?.threadID || null;
}

function sanitizeDetailLiveMessage(message, { phase, receivedAt, source }) {
  return {
    source,
    phase,
    receivedAt,
    method: message?.method || null,
    id: message?.id ?? null,
    threadID: detailMessageThreadID(message),
  };
}

function summarizeDetailLiveObservation({ target, notifications, requests, liveBoundaryAt, observeMs, bufferInitialLive = true }) {
  const phaseCounts = {};
  const targetPhaseCounts = {};
  const requestIDs = [];
  const findings = [];
  let bufferedInitialLiveEventCount = 0;
  const increment = (map, key) => {
    map[key] = (map[key] || 0) + 1;
  };
  const beforeLivePhases = new Set(["read", "subscribe"]);

  for (const message of [...notifications, ...requests]) {
    increment(phaseCounts, `${message.source}:${message.phase || "unknown"}`);
    if (message.threadID === target.threadID) {
      increment(targetPhaseCounts, `${message.source}:${message.phase || "unknown"}`);
      if (beforeLivePhases.has(message.phase)) {
        bufferedInitialLiveEventCount += 1;
        if (!bufferInitialLive) {
          findings.push({
            code: "detail_live_before_boundary",
            severity: "error",
            message: "target-thread live detail message arrived before projection read and subscribe completed",
            threadID: target.threadID,
            source: message.source,
            method: message.method,
            phase: message.phase,
          });
        }
      }
    }
    if (message.source === "request") {
      if (message.id !== null && message.id !== undefined) {
        requestIDs.push(String(message.id));
      }
      if (!message.threadID) {
        findings.push({
          code: "detail_request_missing_thread_id",
          severity: "error",
          message: "server request arrived without a thread id, so the client cannot attach it to the selected detail view",
          method: message.method,
          phase: message.phase,
        });
      }
    }
  }

  const duplicateRequestIDs = [...new Set(requestIDs.filter((id, index) => requestIDs.indexOf(id) !== index))];
  if (duplicateRequestIDs.length > 0) {
    findings.push({
      code: "detail_duplicate_request",
      severity: "error",
      message: "server request stream delivered duplicate request ids during detail observation",
      threadID: target.threadID,
      duplicateRequestIDs,
    });
  }

  return {
    observeMs,
    liveBoundaryAt,
    notificationCount: notifications.length,
    requestCount: requests.length,
    targetNotificationCount: notifications.filter((message) => message.threadID === target.threadID).length,
    targetRequestCount: requests.filter((message) => message.threadID === target.threadID).length,
    bufferInitialLive,
    bufferedInitialLiveEventCount,
    preLiveTargetNotificationCount: notifications.filter((message) => message.threadID === target.threadID && beforeLivePhases.has(message.phase)).length,
    preLiveTargetRequestCount: requests.filter((message) => message.threadID === target.threadID && beforeLivePhases.has(message.phase)).length,
    phaseCounts,
    targetPhaseCounts,
    notifications,
    requests,
    findings,
  };
}

function duplicateProjectionIDs(rows = []) {
  const ids = rows
    .map((row) => row?.projectionID || null)
    .filter(Boolean);
  return [...new Set(ids.filter((id, index) => ids.indexOf(id) !== index))];
}

function projectionSnapshotSummary(snapshot, expectedThreadID) {
  const rows = Array.isArray(snapshot?.rows) ? snapshot.rows : [];
  const duplicateIDs = duplicateProjectionIDs(rows);
  const malformedRows = rows.flatMap((row, index) => {
    const issues = [];
    const requiredStrings = ["sourceHostID", "projectionID", "sourceRef", "rowRole", "displayOrderKey", "threadID"];
    for (const field of requiredStrings) {
      if (typeof row?.[field] !== "string" || row[field].trim().length === 0) {
        issues.push({ index, field, code: "missing" });
      }
    }
    if (row?.schemaVersion !== PROJECTION_SCHEMA_VERSION
        || row?.identityVersion !== PROJECTION_IDENTITY_VERSION
        || row?.projectionEngineVersion !== PROJECTION_ENGINE_VERSION) {
      issues.push({ index, field: "version", code: "mismatch" });
    }
    if (row?.sourceHostID !== snapshot?.sourceHostID) {
      issues.push({ index, field: "sourceHostID", code: "snapshot_mismatch" });
    }
    if (row?.threadID !== expectedThreadID) {
      issues.push({ index, field: "threadID", code: "thread_mismatch" });
    }
    return issues;
  });
  return {
    ok: snapshot?.threadID === expectedThreadID
      && snapshot?.view === "thread.detail"
      && snapshot?.schemaVersion === PROJECTION_SCHEMA_VERSION
      && snapshot?.identityVersion === PROJECTION_IDENTITY_VERSION
      && snapshot?.projectionEngineVersion === PROJECTION_ENGINE_VERSION
      && typeof snapshot?.sourceHostID === "string"
      && snapshot.sourceHostID.trim().length > 0
      && snapshot?.order === "displayOrderKeyAscending"
      && duplicateIDs.length === 0
      && malformedRows.length === 0,
    threadID: snapshot?.threadID || null,
    sourceHostID: snapshot?.sourceHostID || null,
    view: snapshot?.view || null,
    order: snapshot?.order || null,
    seq: snapshot?.seq ?? null,
    rowCount: rows.length,
    duplicateProjectionIDs: duplicateIDs,
    malformedRows,
    complete: snapshot?.complete ?? null,
    projectionEngineVersion: snapshot?.projectionEngineVersion ?? null,
  };
}

async function probeThreadDetail(target, options, routeEvents = null) {
  const startedAt = new Date().toISOString();
  const notifications = [];
  const requests = [];
  let phase = "connecting";
  const client = new JsonRpcWebSocketClient(options.relayUrl, {
    requestTimeoutMs: options.requestTimeoutMs,
    onNotification: (message) => {
      notifications.push(sanitizeDetailLiveMessage(message, {
        phase,
        receivedAt: new Date().toISOString(),
        source: "notification",
      }));
    },
    onRequest: (message) => {
      requests.push(sanitizeDetailLiveMessage(message, {
        phase,
        receivedAt: new Date().toISOString(),
        source: "request",
      }));
    },
  });
  const findings = [];
  recordRoute(routeEvents, "initialize", "open detail client-path session", {
    threadID: target.threadID,
  });
  await initializeClient(client);
  recordRoute(routeEvents, "initialized", "detail client-path session initialized notification sent", {
    threadID: target.threadID,
  });
  try {
    let subscribe = null;
    let subscribeOk = null;
    let resync = null;
    let resyncOk = null;
    let liveBoundaryAt = null;
    if (options.detailLive) {
      try {
        phase = "subscribe";
        recordRoute(routeEvents, "thread/detail/subscribe", "detail client-path projection subscribe", {
          threadID: target.threadID,
        });
        const subscribeResponse = await client.request("thread/detail/subscribe", {
          threadId: target.threadID,
        });
        subscribe = projectionSnapshotSummary(subscribeResponse, target.threadID);
        subscribeOk = subscribe.ok;
        liveBoundaryAt = new Date().toISOString();
        phase = "live";
        if (!subscribe.ok) {
          findings.push({
            code: "detail_subscribe_wrong_thread",
            severity: "error",
            message: "thread/detail/subscribe returned a malformed projection or the wrong selected thread",
            expectedThreadID: target.threadID,
            actualThreadID: subscribe.threadID,
            view: subscribe.view,
            duplicateProjectionIDs: subscribe.duplicateProjectionIDs,
            malformedRows: subscribe.malformedRows,
          });
        }
        if (options.detailObserveMs > 0) {
          await sleep(options.detailObserveMs);
        }
        phase = "resync";
        recordRoute(routeEvents, "thread/detail/resync", "detail client-path projection resync", {
          threadID: target.threadID,
        });
        const resyncResponse = await client.request("thread/detail/resync", {
          threadId: target.threadID,
        });
        resync = projectionSnapshotSummary(resyncResponse, target.threadID);
        resyncOk = resync.ok;
        phase = "live";
        if (!resync.ok) {
          findings.push({
            code: "detail_resync_wrong_thread",
            severity: "error",
            message: "thread/detail/resync returned a malformed projection or the wrong selected thread",
            expectedThreadID: target.threadID,
            actualThreadID: resync.threadID,
            view: resync.view,
            duplicateProjectionIDs: resync.duplicateProjectionIDs,
            malformedRows: resync.malformedRows,
          });
        }
      } catch (error) {
        subscribeOk = false;
        findings.push({
          code: "detail_subscribe_failed",
          severity: "error",
          message: "thread/detail/subscribe or thread/detail/resync failed for selected Dock card",
          threadID: target.threadID,
          error: error?.message || String(error),
        });
      }
    }
    if (!options.detailLive) {
      phase = "live";
    }

    const liveObservation = summarizeDetailLiveObservation({
      target,
      notifications,
      requests,
      liveBoundaryAt,
      observeMs: options.detailObserveMs,
      bufferInitialLive: options.detailBufferInitialLive,
    });
    findings.push(...liveObservation.findings);

    return {
      ok: findings.length === 0,
      startedAt,
      endedAt: new Date().toISOString(),
      target,
      read: {
        attempted: false,
        ok: null,
        diagnosticOnly: true,
      },
      subscribe: {
        attempted: options.detailLive,
        ok: subscribeOk,
        ...(subscribe || {}),
        liveBoundaryAt,
      },
      resync: {
        attempted: options.detailLive,
        ok: resyncOk,
        ...(resync || {}),
        liveBoundaryAt,
      },
      liveObservation,
      findings,
    };
  } catch (error) {
    const liveObservation = summarizeDetailLiveObservation({
      target,
      notifications,
      requests,
      liveBoundaryAt: null,
      observeMs: options.detailObserveMs,
      bufferInitialLive: options.detailBufferInitialLive,
    });
    return {
      ok: false,
      startedAt,
      endedAt: new Date().toISOString(),
      target,
      read: { attempted: false, ok: null, diagnosticOnly: true },
      turns: null,
      resume: { attempted: false, ok: null, threadID: null },
      liveObservation,
      findings: [
        ...liveObservation.findings,
        {
        code: "detail_probe_failed",
        severity: "error",
        message: "thread detail probe failed",
        threadID: target.threadID,
        error: error?.message || String(error),
        },
      ],
    };
  } finally {
    await client.close();
  }
}

async function probeDetailTargets(dockSnapshot, options, routeEvents = null) {
  const targets = selectDetailTargets(dockSnapshot, options);
  const probes = [];
  for (const target of targets) {
    probes.push(await probeThreadDetail(target, options, routeEvents));
  }
  const findings = probes.flatMap((probe) => probe.findings || []);
  if (options.detail !== "none" && targets.length === 0) {
    findings.push({
      code: "detail_no_targets",
      severity: "warning",
      message: "detail mode requested but fresh Dock snapshot had no selectable thread cards",
    });
  }
  return {
    ok: findings.every((finding) => finding.severity !== "error" && finding.severity !== "warning"),
    mode: options.detail,
    targetCount: targets.length,
    probes,
    findings,
  };
}

function findingCounts(findings) {
  return findings.reduce((counts, finding) => {
    const severity = finding?.severity || "info";
    counts[severity] = (counts[severity] || 0) + 1;
    return counts;
  }, { error: 0, warning: 0, info: 0 });
}

function summarizeParity() {
  return {
    included: false,
    ok: null,
    findings: [],
    blindSpots: [],
  };
}

function classifyParityForClientContract() {
  return {
    ok: true,
    skipped: true,
    clientRequiredFailures: [],
  };
}

function findingsForParityClientContract() {
  return [];
}

function sampleOK(sample) {
  return Boolean(sample?.ok);
}

async function buildSample({ options, sampleIndex, streamProbe = null }) {
  const startedAt = new Date().toISOString();
  const sampleRouteEvents = [];
  const streamRouteStart = streamProbe ? streamProbe.routeEvents.length : 0;
  if (streamProbe) {
    if (options.settleMs > 0) {
      await sleep(options.settleMs);
    }
    await streamProbe.waitForComplete(options.dockCollectionTimeoutMs);
  }
  const parity = null;
  let freshDock = await collectDockClientPathSnapshot(options, sampleRouteEvents);
  const streamComparisonResult = streamProbe
    ? await compareStreamToFreshDock({
      streamProbe,
      freshDock,
      options,
      routeEvents: sampleRouteEvents,
    })
    : null;
  if (streamComparisonResult) {
    freshDock = streamComparisonResult.freshDock;
  }
  const parityClientContract = classifyParityForClientContract(parity);
  const streamBefore = streamComparisonResult?.streamSnapshot || null;
  const streamComparison = streamComparisonResult?.comparison || null;
  let resync = null;
  let streamAfterResync = null;
  let streamComparisonAfterResync = null;
  let streamComparisonAfterResyncAttempts = null;
  let streamComparisonAfterResyncLag = null;
  const shouldForceResync = Boolean(streamProbe && options.forceDockResync);
  if (streamProbe && (shouldForceResync || !streamComparison.ok || streamProbe.state.needsResync)) {
    const resyncReason = shouldForceResync
      ? "forced_client_path_probe"
      : (streamProbe.state.needsResync ? "sequence_or_schema" : "fresh_snapshot_mismatch");
    resync = await streamProbe.resync(resyncReason);
    if (options.settleMs > 0) {
      await sleep(options.settleMs);
    }
    const afterResyncResult = await compareStreamToFreshDock({
      streamProbe,
      freshDock: await collectDockClientPathSnapshot(options, sampleRouteEvents),
      options,
      routeEvents: sampleRouteEvents,
    });
    streamAfterResync = afterResyncResult.streamSnapshot;
    streamComparisonAfterResync = afterResyncResult.comparison;
    streamComparisonAfterResyncAttempts = afterResyncResult.attempts;
    streamComparisonAfterResyncLag = afterResyncResult.streamLag;
  }
  const detail = await probeDetailTargets(freshDock, options, sampleRouteEvents);
  const streamRouteEvents = streamProbe ? streamProbe.routeEvents.slice(streamRouteStart) : [];
  const clientPathEvents = [...streamRouteEvents, ...sampleRouteEvents];
  const clientPathFindings = [
    ...(streamProbe?.findings || []).map((finding) => ({ ...finding, surface: "dock.long_lived_stream" })),
    ...(freshDock.collection?.findings || []).map((finding) => ({ ...finding, surface: "dock.client_path_complete_collection" })),
    ...(streamComparison?.findings || []).map((finding) => ({ ...finding, surface: "dock.long_lived_stream" })),
    ...(streamComparisonAfterResync && !streamComparisonAfterResync.ok
      ? streamComparisonAfterResync.findings.map((finding) => ({ ...finding, surface: "dock.long_lived_stream_after_resync" }))
      : []),
    ...(detail.findings || []).map((finding) => ({ ...finding, surface: "thread.detail_probe" })),
  ];
  const findings = [
    ...findingsForParityClientContract(parityClientContract),
    ...clientPathFindings,
  ];
  const counts = findingCounts(findings);
  const clientPathCounts = findingCounts(clientPathFindings);
  return {
    ok: counts.error === 0 && counts.warning === 0,
    sampleIndex,
    startedAt,
    finishedAt: new Date().toISOString(),
    parity: summarizeParity(parity),
    freshDock: {
      kind: freshDock?.kind || null,
      schemaVersion: freshDock?.schemaVersion ?? null,
      epoch: freshDock?.epoch || null,
      seq: freshDock?.seq ?? null,
      view: freshDock?.view || null,
      complete: freshDock?.complete ?? null,
      totalRows: freshDock?.totalRows ?? null,
      window: freshDock?.window || null,
      rowCount: Array.isArray(freshDock?.rows) ? freshDock.rows.length : 0,
      projectionIDs: (freshDock?.rows || []).map(cardID).filter(Boolean).sort(),
      rows: (freshDock?.rows || []).map(sanitizeCardForReport),
      freshness: freshDock?.freshness || null,
      collection: freshDock?.collection || null,
    },
    stream: streamProbe ? {
      before: sanitizeDockSnapshotForReport(streamBefore),
      comparison: streamComparison,
      comparisonAttempts: streamComparisonResult?.attempts || [],
      convergence: streamComparisonResult?.streamLag || null,
      resync,
      afterResync: sanitizeDockSnapshotForReport(streamAfterResync),
      comparisonAfterResync: streamComparisonAfterResync,
      comparisonAfterResyncAttempts: streamComparisonAfterResyncAttempts,
      convergenceAfterResync: streamComparisonAfterResyncLag,
      notifications: [...streamProbe.notifications],
      resyncs: [...streamProbe.resyncs],
    } : null,
    detail,
    clientPath: {
      ok: clientPathCounts.error === 0 && clientPathCounts.warning === 0,
      findingCounts: clientPathCounts,
    },
    clientContract: parityClientContract,
    clientPathEvidence: summarizeClientPathEvents(clientPathEvents),
    oracleEvidence: null,
    findings,
    findingCounts: counts,
  };
}

async function buildOneShotReport(options) {
  const sample = await buildSample({ options, sampleIndex: 0, streamProbe: null });
  return {
    schemaVersion: 1,
    mode: options.mode,
    startedAt: sample.startedAt,
    endedAt: sample.finishedAt,
    relayUrl: sanitizeURLForReport(options.relayUrl),
    codexHome: options.codexHome,
    sqliteHome: options.sqliteHome,
    config: reportConfig(options),
    samples: [sample],
    summary: summarizeSamples([sample], null),
    clientPathEvidence: summarizeClientPathEvents(sample.clientPathEvidence.events),
    oracleEvidence: null,
    failures: sample.findings.filter((finding) => finding.severity === "error" || finding.severity === "warning"),
    unsupportedFacts: [],
  };
}

async function buildSoakReport(options) {
  const startedAtMs = Date.now();
  const deadlineMs = startedAtMs + options.durationMs;
  const streamProbe = new DockStreamProbe(options);
  const samples = [];
  await streamProbe.open();
  await streamProbe.waitForComplete(options.dockCollectionTimeoutMs);
  try {
    let sampleIndex = 0;
    do {
      samples.push(await buildSample({ options, sampleIndex, streamProbe }));
      sampleIndex += 1;
      if (Date.now() >= deadlineMs) {
        break;
      }
      await sleep(Math.min(options.sampleIntervalMs, Math.max(0, deadlineMs - Date.now())));
    } while (Date.now() <= deadlineMs);
  } finally {
    await streamProbe.close();
  }
  return {
    schemaVersion: 1,
    mode: options.mode,
    startedAt: new Date(startedAtMs).toISOString(),
    endedAt: new Date().toISOString(),
    relayUrl: sanitizeURLForReport(options.relayUrl),
    codexHome: options.codexHome,
    sqliteHome: options.sqliteHome,
    config: reportConfig(options),
    samples,
    stream: {
      notificationCount: streamProbe.notifications.length,
      resyncCount: streamProbe.resyncs.length,
      closed: streamProbe.closed,
      finalState: sanitizeDockSnapshotForReport(streamProbe.snapshot()),
    },
    summary: summarizeSamples(samples, streamProbe),
    clientPathEvidence: summarizeClientPathEvents([
      ...streamProbe.routeEvents,
      ...samples.flatMap((sample) => sample.clientPathEvidence?.events || []),
    ]),
    oracleEvidence: null,
    failures: samples.flatMap((sample) => sample.findings || [])
      .filter((finding) => finding.severity === "error" || finding.severity === "warning"),
    unsupportedFacts: [],
  };
}

async function requestScenarioThreadMutation({ options, method, target, routeEvents, params = {} }) {
  return withRelayClient(options, null, async (client) => {
    recordRoute(routeEvents, method, `scenario ${method} selected Dock row`, {
      threadID: target.threadID,
      cardID: target.cardID,
      logicalHostID: target.logicalHostID,
      paramKeys: Object.keys(params).sort(),
      name: params.name ? textFingerprint(params.name) : undefined,
    });
    return client.request(method, { threadId: target.threadID, ...params });
  }, routeEvents);
}

function mutationResponseSummary(response) {
  if (response === null || response === undefined) {
    return null;
  }
  if (typeof response !== "object") {
    return { type: typeof response };
  }
  return {
    type: Array.isArray(response) ? "array" : "object",
    keys: Object.keys(response).sort(),
  };
}

function observedSnapshotTime(snapshot) {
  const parsed = Date.parse(snapshot?.lastReceivedAt || "");
  if (Number.isFinite(parsed)) {
    return parsed;
  }
  return Date.now();
}

async function waitForStreamThreadPresence({ streamProbe, threadID, present, timeoutMs, notBeforeMs = 0 }) {
  const deadlineMs = Date.now() + timeoutMs;
  while (true) {
    const snapshot = streamProbe.snapshot();
    const actualPresent = dockSnapshotHasThread(snapshot, threadID);
    const observedAtMs = observedSnapshotTime(snapshot);
    if (actualPresent === present && observedAtMs >= Number(notBeforeMs || 0)) {
      return {
        ok: true,
        observedAt: new Date(observedAtMs).toISOString(),
        observedAtMs,
        present: actualPresent,
        snapshot: sanitizeDockSnapshotForReport(snapshot),
      };
    }
    if (streamProbe.state.needsResync) {
      await streamProbe.resync("scenario_stream_contract");
      continue;
    }
    const remainingMs = deadlineMs - Date.now();
    if (remainingMs <= 0) {
      return {
        ok: false,
        observedAt: null,
        observedAtMs: null,
        present: actualPresent,
        timeoutMs,
        snapshot: sanitizeDockSnapshotForReport(snapshot),
      };
    }
    await streamProbe.waitForUpdate(Math.min(remainingMs, 500));
  }
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
      await streamProbe.resync("scenario_stream_condition");
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
    message: `scenario ${phase}: ${finding.message || "long-lived Dock stream differs from fresh Dock snapshot"}`,
  }));
}

async function runRenameTitleScenario(options) {
  const routeEvents = [];
  const findings = [];
  const transitions = [];
  const streamProbe = new DockStreamProbe(options);
  const startedAtMs = Date.now();
  let target = null;
  let originalTitle = null;
  let renamed = false;
  let restored = false;
  await streamProbe.open();
  await streamProbe.waitForComplete(options.dockCollectionTimeoutMs);
  try {
    const beforeDock = await collectDockClientPathSnapshot(options, routeEvents);
    target = selectScenarioRenameTarget(beforeDock, options.scenarioThreadID);
    if (!target) {
      findings.push({
        code: "scenario_rename_title_no_restorable_active_thread",
        severity: "error",
        message: options.scenarioThreadID
          ? "scenario rename-title could not find the requested active Dock row with a restorable title"
          : "scenario rename-title could not find an active Dock row with a restorable title",
        requestedThreadID: options.scenarioThreadID || null,
      });
      return {
        id: "rename-title",
        ok: false,
        startedAt: new Date(startedAtMs).toISOString(),
        endedAt: new Date().toISOString(),
        target: null,
        beforeDock: sanitizeDockSnapshotForReport(beforeDock),
        transitions,
        stream: {
          notificationCount: streamProbe.notifications.length,
          resyncCount: streamProbe.resyncs.length,
          finalState: sanitizeDockSnapshotForReport(streamProbe.snapshot()),
        },
        clientPathEvidence: summarizeClientPathEvents([...streamProbe.routeEvents, ...routeEvents]),
        findings,
      };
    }
    originalTitle = target.title;

    if (!dockSnapshotHasThread(streamProbe.snapshot(), target.threadID)) {
      findings.push({
        code: "scenario_rename_title_initial_stream_missing_thread",
        severity: "error",
        message: "long-lived Dock stream did not contain the selected active Dock row before rename",
        threadID: target.threadID,
        cardID: target.cardID,
      });
    }

    const proofTitle = `Codex Dock realtime proof ${new Date(startedAtMs).toISOString()} ${crypto.randomUUID().slice(0, 8)}`;
    const renameStartedAtMs = Date.now();
    let renameAcknowledgedAtMs = null;
    let renameResponse = null;
    try {
      renameResponse = await requestScenarioThreadMutation({
        options,
        method: "thread/name/set",
        target,
        routeEvents,
        params: { name: proofTitle },
      });
      renamed = true;
      renameAcknowledgedAtMs = Date.now();
    } catch (error) {
      renameAcknowledgedAtMs = Date.now();
      findings.push({
        code: "scenario_rename_title_request_failed",
        severity: "error",
        message: "thread/name/set failed for the selected Dock row",
        threadID: target.threadID,
        error: error?.message || String(error),
      });
    }

    const renameWait = renameAcknowledgedAtMs
      ? await waitForStreamCondition({
        streamProbe,
        timeoutMs: options.dockCollectionTimeoutMs,
        predicate: (snapshot) => observedSnapshotTime(snapshot) >= renameStartedAtMs
          && dockSnapshotCardForThread(snapshot, target.threadID)?.title === proofTitle,
      })
      : { ok: false, observedAtMs: null, observedAt: null };
    const renameLag = scenarioLagSummary({
      transition: "rename-title",
      startedAtMs: renameStartedAtMs,
      acknowledgedAtMs: renameAcknowledgedAtMs,
      observedAtMs: renameWait.observedAtMs,
      maxStreamLagMs: options.maxStreamLagMs,
    });
    if (!renameWait.ok) {
      findings.push({
        code: "scenario_rename_title_not_seen_on_dock_stream",
        severity: "error",
        message: "long-lived Dock stream did not show the renamed thread title within the collection timeout",
        threadID: target.threadID,
        timeoutMs: options.dockCollectionTimeoutMs,
      });
    } else if (renameLag.exceeded) {
      findings.push({
        code: "scenario_rename_title_lag_exceeded",
        severity: "error",
        message: "renamed thread title appeared on the long-lived Dock stream after the client-visible lag budget",
        threadID: target.threadID,
        observedLagMs: renameLag.observedLagMs,
        maxStreamLagMs: options.maxStreamLagMs,
      });
    }

    const afterRenameDock = await collectDockClientPathSnapshot(options, routeEvents);
    const renameComparisonResult = await compareStreamToFreshDock({
      streamProbe,
      freshDock: afterRenameDock,
      options,
      routeEvents,
      threadID: target.threadID,
    });
    if (dockSnapshotCardForThread(renameComparisonResult.freshDock, target.threadID)?.title !== proofTitle) {
      findings.push({
        code: "scenario_rename_title_fresh_dock_title_mismatch",
        severity: "error",
        message: "fresh Dock client-path snapshot did not show the renamed title",
        threadID: target.threadID,
      });
    }
    const renameComparison = renameComparisonResult.comparison;
    findings.push(...scenarioComparisonFindings({ phase: "rename-title", comparison: renameComparison }));
    transitions.push({
      name: "rename-title",
      kind: "rename",
      route: "thread/name/set",
      response: normalizeForComparison(mutationResponseSummary(renameResponse)),
      wait: renameWait,
      lag: renameLag,
      title: displayTitleFingerprint(proofTitle),
      freshDock: sanitizeDockSnapshotForReport(renameComparisonResult.freshDock),
      streamComparison: renameComparison,
      streamComparisonAttempts: renameComparisonResult.attempts,
      convergence: renameComparisonResult.streamLag,
    });
    if (options.scenarioHoldMs > 0) {
      await sleep(options.scenarioHoldMs);
    }

    const restoreStartedAtMs = Date.now();
    let restoreAcknowledgedAtMs = null;
    let restoreResponse = null;
    try {
      restoreResponse = await requestScenarioThreadMutation({
        options,
        method: "thread/name/set",
        target,
        routeEvents,
        params: { name: originalTitle },
      });
      restoreAcknowledgedAtMs = Date.now();
    } catch (error) {
      restoreAcknowledgedAtMs = Date.now();
      findings.push({
        code: "scenario_rename_title_restore_request_failed",
        severity: "error",
        message: "thread/name/set failed while restoring the selected Dock row title",
        threadID: target.threadID,
        error: error?.message || String(error),
      });
    }

    const restoreWait = restoreAcknowledgedAtMs
      ? await waitForStreamCondition({
        streamProbe,
        timeoutMs: options.dockCollectionTimeoutMs,
        predicate: (snapshot) => observedSnapshotTime(snapshot) >= restoreStartedAtMs
          && dockSnapshotCardForThread(snapshot, target.threadID)?.title === originalTitle,
      })
      : { ok: false, observedAtMs: null, observedAt: null };
    const restoreLag = scenarioLagSummary({
      transition: "restore-title",
      startedAtMs: restoreStartedAtMs,
      acknowledgedAtMs: restoreAcknowledgedAtMs,
      observedAtMs: restoreWait.observedAtMs,
      maxStreamLagMs: options.maxStreamLagMs,
    });
    if (!restoreWait.ok) {
      findings.push({
        code: "scenario_rename_title_restore_not_seen_on_dock_stream",
        severity: "error",
        message: "long-lived Dock stream did not show the restored thread title within the collection timeout",
        threadID: target.threadID,
        timeoutMs: options.dockCollectionTimeoutMs,
      });
    } else if (restoreLag.exceeded) {
      findings.push({
        code: "scenario_rename_title_restore_lag_exceeded",
        severity: "error",
        message: "restored thread title appeared on the long-lived Dock stream after the client-visible lag budget",
        threadID: target.threadID,
        observedLagMs: restoreLag.observedLagMs,
        maxStreamLagMs: options.maxStreamLagMs,
      });
    }

    const afterRestoreDock = await collectDockClientPathSnapshot(options, routeEvents);
    const restoreComparisonResult = await compareStreamToFreshDock({
      streamProbe,
      freshDock: afterRestoreDock,
      options,
      routeEvents,
      threadID: target.threadID,
    });
    if (dockSnapshotCardForThread(restoreComparisonResult.freshDock, target.threadID)?.title !== originalTitle) {
      findings.push({
        code: "scenario_rename_title_fresh_dock_restore_mismatch",
        severity: "error",
        message: "fresh Dock client-path snapshot did not show the restored title",
        threadID: target.threadID,
      });
    } else {
      restored = true;
    }
    const restoreComparison = restoreComparisonResult.comparison;
    findings.push(...scenarioComparisonFindings({ phase: "restore-title", comparison: restoreComparison }));
    transitions.push({
      name: "restore-title",
      kind: "rename",
      route: "thread/name/set",
      response: normalizeForComparison(mutationResponseSummary(restoreResponse)),
      wait: restoreWait,
      lag: restoreLag,
      title: displayTitleFingerprint(originalTitle),
      freshDock: sanitizeDockSnapshotForReport(restoreComparisonResult.freshDock),
      streamComparison: restoreComparison,
      streamComparisonAttempts: restoreComparisonResult.attempts,
      convergence: restoreComparisonResult.streamLag,
    });

    return {
      id: "rename-title",
      ok: !findings.some((finding) => finding.severity === "error" || finding.severity === "warning"),
      startedAt: new Date(startedAtMs).toISOString(),
      endedAt: new Date().toISOString(),
      actuator: {
        type: "app-server RPC through relay",
        routes: ["thread/name/set"],
        clientExercised: true,
        reversible: true,
        realData: true,
      },
      target: sanitizeScenarioTargetForReport(target),
      beforeDock: sanitizeDockSnapshotForReport(beforeDock),
      transitions,
      stream: {
        notificationCount: streamProbe.notifications.length,
        resyncCount: streamProbe.resyncs.length,
        finalState: sanitizeDockSnapshotForReport(streamProbe.snapshot()),
      },
      clientPathEvidence: summarizeClientPathEvents([...streamProbe.routeEvents, ...routeEvents]),
      findings,
    };
  } finally {
    if (renamed && !restored && target && originalTitle) {
      try {
        await requestScenarioThreadMutation({
          options,
          method: "thread/name/set",
          target,
          routeEvents: [],
          params: { name: originalTitle },
        });
      } catch {
        // The report already records the scenario failure. This best-effort
        // restore avoids leaking title text into logs or proof artifacts.
      }
    }
    await streamProbe.close();
  }
}

async function runArchiveToggleScenario(options) {
  const routeEvents = [];
  const findings = [];
  const transitions = [];
  const streamProbe = new DockStreamProbe(options);
  const startedAtMs = Date.now();
  await streamProbe.open();
  await streamProbe.waitForComplete(options.dockCollectionTimeoutMs);
  try {
    const beforeDock = await collectDockClientPathSnapshot(options, routeEvents);
    const target = selectScenarioArchiveTarget(beforeDock, options.scenarioThreadID);
    if (!target) {
      findings.push({
        code: "scenario_archive_toggle_no_active_thread",
        severity: "error",
        message: options.scenarioThreadID
          ? "scenario archive-toggle could not find the requested thread in the active Dock client path"
          : "scenario archive-toggle could not find an active Dock row to mutate",
        requestedThreadID: options.scenarioThreadID || null,
      });
      return {
        id: "archive-toggle",
        ok: false,
        startedAt: new Date(startedAtMs).toISOString(),
        endedAt: new Date().toISOString(),
        target: null,
        beforeDock: sanitizeDockSnapshotForReport(beforeDock),
        transitions,
        stream: {
          notificationCount: streamProbe.notifications.length,
          resyncCount: streamProbe.resyncs.length,
          finalState: sanitizeDockSnapshotForReport(streamProbe.snapshot()),
        },
        clientPathEvidence: summarizeClientPathEvents([...streamProbe.routeEvents, ...routeEvents]),
        findings,
      };
    }

    if (!dockSnapshotHasThread(streamProbe.snapshot(), target.threadID)) {
      findings.push({
        code: "scenario_archive_toggle_initial_stream_missing_thread",
        severity: "error",
        message: "long-lived Dock stream did not contain the selected active Dock row before mutation",
        threadID: target.threadID,
        cardID: target.cardID,
      });
    }

    for (let iteration = 1; iteration <= options.scenarioRepetitions; iteration += 1) {
      const archiveName = scenarioTransitionName("archive", iteration, options.scenarioRepetitions);
      const archiveStartedAtMs = Date.now();
      let archiveAcknowledgedAtMs = null;
      let archiveResponse = null;
      try {
        archiveResponse = await requestScenarioThreadMutation({
          options,
          method: "thread/archive",
          target,
          routeEvents,
        });
        archiveAcknowledgedAtMs = Date.now();
      } catch (error) {
        archiveAcknowledgedAtMs = Date.now();
        findings.push({
          code: "scenario_archive_request_failed",
          severity: "error",
          message: "thread/archive failed for the selected Dock row",
          threadID: target.threadID,
          iteration,
          error: error?.message || String(error),
        });
      }

      const archiveWait = archiveAcknowledgedAtMs
        ? await waitForStreamThreadPresence({
          streamProbe,
          threadID: target.threadID,
          present: false,
          timeoutMs: options.dockCollectionTimeoutMs,
          notBeforeMs: archiveStartedAtMs,
        })
        : { ok: false, observedAtMs: null, observedAt: null, present: true };
      const archiveLag = scenarioLagSummary({
        transition: archiveName,
        startedAtMs: archiveStartedAtMs,
        acknowledgedAtMs: archiveAcknowledgedAtMs,
        observedAtMs: archiveWait.observedAtMs,
        maxStreamLagMs: options.maxStreamLagMs,
      });
      if (!archiveWait.ok) {
        findings.push({
          code: "scenario_archive_not_seen_on_dock_stream",
          severity: "error",
          message: "long-lived Dock stream did not remove the archived thread within the collection timeout",
          threadID: target.threadID,
          iteration,
          timeoutMs: options.dockCollectionTimeoutMs,
        });
      } else if (archiveLag.exceeded) {
        findings.push({
          code: "scenario_archive_lag_exceeded",
          severity: "error",
          message: "archived thread disappeared from the long-lived Dock stream after the client-visible lag budget",
          threadID: target.threadID,
          iteration,
          observedLagMs: archiveLag.observedLagMs,
          maxStreamLagMs: options.maxStreamLagMs,
        });
      }
      const afterArchiveDock = await collectDockClientPathSnapshot(options, routeEvents);
      const archiveComparisonResult = await compareStreamToFreshDock({
        streamProbe,
        freshDock: afterArchiveDock,
        options,
        routeEvents,
        threadID: target.threadID,
      });
      if (dockSnapshotHasThread(archiveComparisonResult.freshDock, target.threadID)) {
        findings.push({
          code: "scenario_archive_fresh_dock_still_contains_thread",
          severity: "error",
          message: "fresh Dock client-path snapshot still contains the archived thread",
          threadID: target.threadID,
          iteration,
        });
      }
      const archiveComparison = archiveComparisonResult.comparison;
      findings.push(...scenarioComparisonFindings({ phase: archiveName, comparison: archiveComparison }));
      transitions.push({
        name: archiveName,
        kind: "archive",
        iteration,
        route: "thread/archive",
        response: normalizeForComparison(mutationResponseSummary(archiveResponse)),
        wait: archiveWait,
        lag: archiveLag,
        freshDock: sanitizeDockSnapshotForReport(archiveComparisonResult.freshDock),
        streamComparison: archiveComparison,
        streamComparisonAttempts: archiveComparisonResult.attempts,
        convergence: archiveComparisonResult.streamLag,
      });
      if (options.scenarioHoldMs > 0) {
        await sleep(options.scenarioHoldMs);
      }

      const unarchiveName = scenarioTransitionName("unarchive", iteration, options.scenarioRepetitions);
      const unarchiveStartedAtMs = Date.now();
      let unarchiveAcknowledgedAtMs = null;
      let unarchiveResponse = null;
      try {
        unarchiveResponse = await requestScenarioThreadMutation({
          options,
          method: "thread/unarchive",
          target,
          routeEvents,
        });
        unarchiveAcknowledgedAtMs = Date.now();
      } catch (error) {
        unarchiveAcknowledgedAtMs = Date.now();
        findings.push({
          code: "scenario_unarchive_request_failed",
          severity: "error",
          message: "thread/unarchive failed for the selected Dock row after archive",
          threadID: target.threadID,
          iteration,
          error: error?.message || String(error),
        });
      }

      const unarchiveWait = unarchiveAcknowledgedAtMs
        ? await waitForStreamThreadPresence({
          streamProbe,
          threadID: target.threadID,
          present: true,
          timeoutMs: options.dockCollectionTimeoutMs,
          notBeforeMs: unarchiveStartedAtMs,
        })
        : { ok: false, observedAtMs: null, observedAt: null, present: false };
      const unarchiveLag = scenarioLagSummary({
        transition: unarchiveName,
        startedAtMs: unarchiveStartedAtMs,
        acknowledgedAtMs: unarchiveAcknowledgedAtMs,
        observedAtMs: unarchiveWait.observedAtMs,
        maxStreamLagMs: options.maxStreamLagMs,
      });
      if (!unarchiveWait.ok) {
        findings.push({
          code: "scenario_unarchive_not_seen_on_dock_stream",
          severity: "error",
          message: "long-lived Dock stream did not restore the unarchived thread within the collection timeout",
          threadID: target.threadID,
          iteration,
          timeoutMs: options.dockCollectionTimeoutMs,
        });
      } else if (unarchiveLag.exceeded) {
        findings.push({
          code: "scenario_unarchive_lag_exceeded",
          severity: "error",
          message: "unarchived thread reappeared on the long-lived Dock stream after the client-visible lag budget",
          threadID: target.threadID,
          iteration,
          observedLagMs: unarchiveLag.observedLagMs,
          maxStreamLagMs: options.maxStreamLagMs,
        });
      }
      const afterUnarchiveDock = await collectDockClientPathSnapshot(options, routeEvents);
      const unarchiveComparisonResult = await compareStreamToFreshDock({
        streamProbe,
        freshDock: afterUnarchiveDock,
        options,
        routeEvents,
        threadID: target.threadID,
      });
      if (!dockSnapshotHasThread(unarchiveComparisonResult.freshDock, target.threadID)) {
        findings.push({
          code: "scenario_unarchive_fresh_dock_missing_thread",
          severity: "error",
          message: "fresh Dock client-path snapshot is missing the unarchived thread",
          threadID: target.threadID,
          iteration,
        });
      }
      const unarchiveComparison = unarchiveComparisonResult.comparison;
      findings.push(...scenarioComparisonFindings({ phase: unarchiveName, comparison: unarchiveComparison }));
      transitions.push({
        name: unarchiveName,
        kind: "unarchive",
        iteration,
        route: "thread/unarchive",
        response: normalizeForComparison(mutationResponseSummary(unarchiveResponse)),
        wait: unarchiveWait,
        lag: unarchiveLag,
        freshDock: sanitizeDockSnapshotForReport(unarchiveComparisonResult.freshDock),
        streamComparison: unarchiveComparison,
        streamComparisonAttempts: unarchiveComparisonResult.attempts,
        convergence: unarchiveComparisonResult.streamLag,
      });
      if (iteration < options.scenarioRepetitions && options.scenarioHoldMs > 0) {
        await sleep(options.scenarioHoldMs);
      }
    }

    return {
      id: "archive-toggle",
      ok: !findings.some((finding) => finding.severity === "error" || finding.severity === "warning"),
      startedAt: new Date(startedAtMs).toISOString(),
      endedAt: new Date().toISOString(),
      actuator: {
        type: "app-server RPC through relay",
        routes: ["thread/archive", "thread/unarchive"],
        clientExercised: true,
        scenarioRepetitions: options.scenarioRepetitions,
      },
      target: sanitizeScenarioTargetForReport(target),
      beforeDock: sanitizeDockSnapshotForReport(beforeDock),
      transitions,
      stream: {
        notificationCount: streamProbe.notifications.length,
        resyncCount: streamProbe.resyncs.length,
        finalState: sanitizeDockSnapshotForReport(streamProbe.snapshot()),
      },
      clientPathEvidence: summarizeClientPathEvents([...streamProbe.routeEvents, ...routeEvents]),
      findings,
    };
  } finally {
    await streamProbe.close();
  }
}

function detailReconnectProbeFindings({ label, probe }) {
  const findings = [];
  if (!probe?.ok) {
    findings.push({
      code: `scenario_detail_reconnect_${label}_probe_failed`,
      severity: "error",
      message: `detail ${label} probe failed before reconnect scenario could accept live state`,
      threadID: probe?.target?.threadID || null,
      probeFindings: probe?.findings || [],
    });
  }
  if (probe?.subscribe?.ok !== true) {
    findings.push({
      code: `scenario_detail_reconnect_${label}_subscribe_failed`,
      severity: "error",
      message: `detail ${label} probe did not subscribe through thread/detail/subscribe`,
      threadID: probe?.target?.threadID || null,
    });
  }
  if (probe?.resync?.attempted !== true || probe?.resync?.ok !== true) {
    findings.push({
      code: `scenario_detail_reconnect_${label}_resync_failed`,
      severity: "error",
      message: `detail ${label} probe did not complete thread/detail/resync after subscribe`,
      threadID: probe?.target?.threadID || null,
    });
  }
  if (probe?.subscribe?.liveBoundaryAt === null || probe?.subscribe?.liveBoundaryAt === undefined) {
    findings.push({
      code: `scenario_detail_reconnect_${label}_missing_live_boundary`,
      severity: "error",
      message: `detail ${label} probe did not record a live boundary after projection subscribe`,
      threadID: probe?.target?.threadID || null,
    });
  }
  return findings;
}

function detailReconnectRouteFindings(clientPathEvidence) {
  const routeCounts = clientPathEvidence?.routeCounts || {};
  const required = ["thread/detail/subscribe", "thread/detail/resync"];
  return required
    .filter((route) => Number(routeCounts[route] || 0) < 2)
    .map((route) => ({
      code: "scenario_detail_reconnect_route_not_repeated",
      severity: "error",
      message: "detail reconnect scenario did not exercise the required projection detail route once before reconnect and once after reconnect",
      route,
      observedCount: Number(routeCounts[route] || 0),
      requiredCount: 2,
    }));
}

async function runDetailReconnectScenario(options) {
  const routeEvents = [];
  const findings = [];
  const transitions = [];
  const startedAtMs = Date.now();
  const detailOptions = {
    ...options,
    detail: "sampled",
    detailLimit: 1,
    detailLive: true,
  };
  const beforeDock = await collectDockClientPathSnapshot(options, routeEvents);
  const target = selectScenarioDetailTarget(beforeDock, options.scenarioThreadID);
  if (!target) {
    findings.push({
      code: "scenario_detail_reconnect_no_thread",
      severity: "error",
      message: options.scenarioThreadID
        ? "scenario detail-reconnect could not find the requested thread in the active Dock client path"
        : "scenario detail-reconnect could not find an active Dock row to open",
      requestedThreadID: options.scenarioThreadID || null,
    });
    return {
      id: "detail-reconnect",
      ok: false,
      startedAt: new Date(startedAtMs).toISOString(),
      endedAt: new Date().toISOString(),
      actuator: {
        type: "relay detail projection reconnect through actual client routes",
        routes: ["thread/detail/subscribe", "thread/detail/resync"],
        clientExercised: true,
      },
      target: null,
      beforeDock: sanitizeDockSnapshotForReport(beforeDock),
      transitions,
      clientPathEvidence: summarizeClientPathEvents(routeEvents),
      findings,
    };
  }

  const firstProbe = await probeThreadDetail(target, detailOptions, routeEvents);
  findings.push(...detailReconnectProbeFindings({ label: "initial", probe: firstProbe }));
  const reconnectStartedAtMs = Date.now();
  const secondProbe = await probeThreadDetail(target, detailOptions, routeEvents);
  findings.push(...detailReconnectProbeFindings({ label: "reconnect", probe: secondProbe }));
  const liveBoundaryAtMs = Date.parse(secondProbe?.subscribe?.liveBoundaryAt || "");
  const reconnectObservedAtMs = Number.isFinite(liveBoundaryAtMs) ? liveBoundaryAtMs : Date.now();
  const reconnectLag = scenarioLagSummary({
    transition: "detail-reconnect",
    startedAtMs: reconnectStartedAtMs,
    acknowledgedAtMs: reconnectObservedAtMs,
    observedAtMs: reconnectObservedAtMs,
    maxStreamLagMs: options.maxStreamLagMs,
  });
  if (reconnectLag.exceeded) {
    findings.push({
      code: "scenario_detail_reconnect_lag_exceeded",
      severity: "error",
      message: "detail reconnect historical reload and live boundary exceeded the client-visible lag budget",
      threadID: target.threadID,
      observedLagMs: reconnectLag.observedLagMs,
      maxStreamLagMs: options.maxStreamLagMs,
    });
  }

  const clientPathEvidence = summarizeClientPathEvents(routeEvents);
  findings.push(...detailReconnectRouteFindings(clientPathEvidence));
  transitions.push({
    name: "detail-reconnect",
    kind: "detail-reconnect",
    iteration: 1,
    routes: ["thread/detail/subscribe", "thread/detail/resync"],
    wait: {
      ok: secondProbe?.subscribe?.ok === true,
      observedAt: Number.isFinite(Number(reconnectObservedAtMs)) ? new Date(reconnectObservedAtMs).toISOString() : null,
      observedAtMs: Number.isFinite(Number(reconnectObservedAtMs)) ? reconnectObservedAtMs : null,
    },
    lag: reconnectLag,
    firstProbe,
    reconnectProbe: secondProbe,
  });

  return {
    id: "detail-reconnect",
    ok: !findings.some((finding) => finding.severity === "error" || finding.severity === "warning"),
    startedAt: new Date(startedAtMs).toISOString(),
    endedAt: new Date().toISOString(),
    actuator: {
      type: "relay detail projection reconnect through actual client routes",
      routes: ["thread/detail/subscribe", "thread/detail/resync"],
      clientExercised: true,
      note: "The scenario opens an actual Dock row, completes live projection subscribe and projection resync, closes that detail session, then repeats the same client route sequence before accepting live state.",
    },
    target,
    beforeDock: sanitizeDockSnapshotForReport(beforeDock),
    transitions,
    detail: {
      probes: [firstProbe, secondProbe],
    },
    clientPathEvidence,
    findings,
  };
}

async function runResyncGapScenario(options) {
  const routeEvents = [];
  const findings = [];
  const transitions = [];
  const streamProbe = new DockStreamProbe(options);
  const startedAtMs = Date.now();
  await streamProbe.open();
  await streamProbe.waitForComplete(options.dockCollectionTimeoutMs);
  try {
    const beforeDock = await collectDockClientPathSnapshot(options, routeEvents);
    const beforeComparisonResult = await compareStreamToFreshDock({
      streamProbe,
      freshDock: beforeDock,
      options,
      routeEvents,
    });
    findings.push(...scenarioComparisonFindings({
      phase: "resync-gap-initial",
      comparison: beforeComparisonResult.comparison,
    }));

    const resyncName = "resync-gap";
    const detectedAtMs = Date.now();
    streamProbe.state.needsResync = true;
    let acknowledgedAtMs = null;
    let resyncResponse = null;
    try {
      resyncResponse = await streamProbe.resync("scenario_sequence_gap");
      acknowledgedAtMs = Date.now();
    } catch (error) {
      acknowledgedAtMs = Date.now();
      findings.push({
        code: "scenario_resync_gap_request_failed",
        severity: "error",
        message: "dock/resync failed after the scenario marked the stream as needing resync",
        error: error?.message || String(error),
      });
    }

    if (!resyncResponse) {
      findings.push({
        code: "scenario_resync_gap_not_exercised",
        severity: "error",
        message: "scenario could not exercise the dock/resync client path after a detected stream gap",
      });
    }
    if (streamProbe.state.needsResync) {
      findings.push({
        code: "scenario_resync_gap_still_needs_resync",
        severity: "error",
        message: "long-lived Dock stream still required resync after dock/resync completed",
      });
    }

    const afterDock = await collectDockClientPathSnapshot(options, routeEvents);
    const afterComparisonResult = await compareStreamToFreshDock({
      streamProbe,
      freshDock: afterDock,
      options,
      routeEvents,
    });
    const resyncFinishedAtMs = Date.parse(resyncResponse?.finishedAt || "");
    const observedAtMs = Number.isFinite(resyncFinishedAtMs)
      ? resyncFinishedAtMs
      : observedSnapshotTime(afterComparisonResult.streamSnapshot || streamProbe.snapshot());
    const lag = scenarioLagSummary({
      transition: resyncName,
      startedAtMs: detectedAtMs,
      acknowledgedAtMs,
      observedAtMs,
      maxStreamLagMs: options.maxStreamLagMs,
    });
    if (lag.exceeded) {
      findings.push({
        code: "scenario_resync_gap_lag_exceeded",
        severity: "error",
        message: "dock/resync recovery completed after the client-visible lag budget",
        observedLagMs: lag.observedLagMs,
        maxStreamLagMs: options.maxStreamLagMs,
      });
    }
    findings.push(...scenarioComparisonFindings({
      phase: resyncName,
      comparison: afterComparisonResult.comparison,
    }));
    transitions.push({
      name: resyncName,
      kind: "resync",
      iteration: 1,
      route: "dock/resync",
      response: normalizeForComparison(resyncResponse || null),
      wait: {
        ok: Boolean(resyncResponse) && !streamProbe.state.needsResync,
        observedAt: Number.isFinite(Number(observedAtMs)) ? new Date(observedAtMs).toISOString() : null,
        observedAtMs: Number.isFinite(Number(observedAtMs)) ? observedAtMs : null,
      },
      lag,
      freshDock: sanitizeDockSnapshotForReport(afterComparisonResult.freshDock || afterDock),
      streamComparison: afterComparisonResult.comparison,
      streamComparisonAttempts: afterComparisonResult.attempts,
      streamConvergence: afterComparisonResult.streamLag,
    });

    return {
      id: "resync-gap",
      ok: !findings.some((finding) => finding.severity === "error" || finding.severity === "warning"),
      startedAt: new Date(startedAtMs).toISOString(),
      endedAt: new Date().toISOString(),
      actuator: {
        type: "client-side stream gap detector plus relay RPC",
        routes: ["dock/resync"],
        clientExercised: true,
        note: "The scenario does not invent relay rows; it marks the probe state as needing resync, then uses the same dock/resync route the client uses after a sequence gap.",
      },
      target: null,
      beforeDock: sanitizeDockSnapshotForReport(beforeComparisonResult.freshDock || beforeDock),
      transitions,
      stream: {
        notificationCount: streamProbe.notifications.length,
        resyncCount: streamProbe.resyncs.length,
        finalState: sanitizeDockSnapshotForReport(streamProbe.snapshot()),
      },
      clientPathEvidence: summarizeClientPathEvents([...streamProbe.routeEvents, ...routeEvents]),
      findings,
    };
  } finally {
    await streamProbe.close();
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

async function runThreadActivityScenario(options) {
  const routeEvents = [];
  const findings = [];
  const transitions = [];
  const startedAtMs = Date.now();
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "codex-dock-thread-activity-"));
  const hostID = "thread-activity-fixture";
  const host = {
    id: hostID,
    displayName: "Thread Activity Fixture",
    endpoint: "127.0.0.1:0",
  };
  const stableThreadID = "thread-activity-stable";
  const movingThreadID = "thread-activity-moving";
  const newThreadID = "thread-activity-new";
  const updatedPreview = "Existing row after new turn";
  let sourceRows = [
    fixtureThread(stableThreadID, "Stable row before update", 200),
    fixtureThread(movingThreadID, "Existing row before new turn", 100),
  ];

  const historyServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  const listening = new Promise((resolve) => historyServer.once("listening", resolve));
  await listening;
  historyServer.on("connection", (ws) => {
    ws.on("message", (data) => {
      const message = JSON.parse(data.toString());
      if (message.method === "initialize") {
        sendFixtureResult(ws, message.id, {
          userAgent: "codex-thread-activity-fixture",
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
    hostId: host.id,
    hostName: host.displayName,
    hostEndpoint: host.endpoint,
    ...appServerRegistryFixtureConfig({
      historyUrl: `ws://127.0.0.1:${historyServer.address().port}`,
      historyBearerToken: "history-token",
    }),
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
  const fixtureOptions = {
    ...options,
    relayUrl: `ws://127.0.0.1:${relay.server.address().port}`,
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
      findings.push({
        code: "scenario_thread_activity_initial_order_missing",
        severity: "error",
        message: "initial fixture rows did not appear in the expected Dock order",
        expectedOrder: [stableThreadID, movingThreadID],
      });
    }

    const newStartedAtMs = Date.now();
    sourceRows = [
      fixtureThread(newThreadID, "Newly created row", 300),
      fixtureThread(stableThreadID, "Stable row before update", 200),
      fixtureThread(movingThreadID, "Existing row before new turn", 100),
    ];
    await relayConfig.relayStateEngine.reconcileDock({ reason: "scenario_thread_activity_new_thread" });
    const newWait = await waitForStreamCondition({
      streamProbe,
      timeoutMs: options.dockCollectionTimeoutMs,
      predicate: (snapshot) => (
        dockSnapshotThreadIndex(snapshot, newThreadID) === 0
        && dockSnapshotHasThread(snapshot, stableThreadID)
        && dockSnapshotHasThread(snapshot, movingThreadID)
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
      findings.push({
        code: "scenario_new_thread_not_seen",
        severity: "error",
        message: "new thread did not appear at the top of the long-lived Dock stream",
        threadID: newThreadID,
      });
    } else if (newLag.exceeded) {
      findings.push({
        code: "scenario_new_thread_lag_exceeded",
        severity: "error",
        message: "new thread appeared after the client-visible lag budget",
        observedLagMs: newLag.observedLagMs,
        maxStreamLagMs: options.maxStreamLagMs,
      });
    }
    const newDock = await collectDockClientPathSnapshot(fixtureOptions, routeEvents);
    const newComparison = compareDockStates(streamProbe.snapshot(), newDock);
    findings.push(...scenarioComparisonFindings({ phase: "new-thread", comparison: newComparison }));
    transitions.push({
      name: "new-thread",
      kind: "new-thread",
      iteration: 1,
      route: "dock/update",
      wait: newWait,
      lag: newLag,
      freshDock: sanitizeDockSnapshotForReport(newDock),
      streamComparison: newComparison,
    });

    const turnStartedAtMs = Date.now();
    sourceRows = [
      fixtureThread(movingThreadID, updatedPreview, 400),
      fixtureThread(newThreadID, "Newly created row", 300),
      fixtureThread(stableThreadID, "Stable row before update", 200),
    ];
    await relayConfig.relayStateEngine.reconcileDock({ reason: "scenario_thread_activity_new_turn_order" });
    const turnWait = await waitForStreamCondition({
      streamProbe,
      timeoutMs: options.dockCollectionTimeoutMs,
      predicate: (snapshot) => {
        const card = dockSnapshotCardForThread(snapshot, movingThreadID);
        return dockSnapshotThreadIndex(snapshot, movingThreadID) === 0
          && card?.displaySummary === updatedPreview
          && dockSnapshotThreadIndex(snapshot, newThreadID) === 1;
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
      findings.push({
        code: "scenario_new_turn_order_not_seen",
        severity: "error",
        message: "existing thread update did not move the row to the top with the updated preview",
        threadID: movingThreadID,
      });
    } else if (turnLag.exceeded) {
      findings.push({
        code: "scenario_new_turn_order_lag_exceeded",
        severity: "error",
        message: "existing thread update moved order after the client-visible lag budget",
        observedLagMs: turnLag.observedLagMs,
        maxStreamLagMs: options.maxStreamLagMs,
      });
    }
    const turnDock = await collectDockClientPathSnapshot(fixtureOptions, routeEvents);
    const turnComparison = compareDockStates(streamProbe.snapshot(), turnDock);
    findings.push(...scenarioComparisonFindings({ phase: "new-turn-order", comparison: turnComparison }));
    transitions.push({
      name: "new-turn-order",
      kind: "new-turn-order",
      iteration: 1,
      route: "dock/update",
      wait: turnWait,
      lag: turnLag,
      freshDock: sanitizeDockSnapshotForReport(turnDock),
      streamComparison: turnComparison,
    });

    return {
      id: "thread-activity",
      ok: !findings.some((finding) => finding.severity === "error" || finding.severity === "warning"),
      startedAt: new Date(startedAtMs).toISOString(),
      endedAt: new Date().toISOString(),
      actuator: {
        type: "controlled app-server thread/list fixture through real relay Dock routes",
        routes: ["dock/subscribe", "dock/update"],
        clientExercised: true,
        note: "The fixture changes app-server thread/list rows to model a new session and a new turn; proof only counts delivery through real relay Dock client routes.",
      },
      target: {
        sourceHostID: host.id,
        stableThreadID,
        movingThreadID,
        newThreadID,
      },
      transitions,
      stream: {
        notificationCount: streamProbe.notifications.length,
        resyncCount: streamProbe.resyncs.length,
        finalState: sanitizeDockSnapshotForReport(streamProbe.snapshot()),
      },
      clientPathEvidence: summarizeClientPathEvents([...streamProbe.routeEvents, ...routeEvents]),
      findings,
    };
  } finally {
    await streamProbe.close();
    await relay.close();
    await closeWebSocketServer(historyServer);
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

async function runSpawnEdgeScenario(options) {
  const routeEvents = [];
  const findings = [];
  const transitions = [];
  const startedAtMs = Date.now();
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "codex-dock-spawn-edge-"));
  const hostID = "spawn-edge-fixture";
  const host = {
    id: hostID,
    displayName: "Spawn Edge Fixture",
    endpoint: "127.0.0.1:0",
  };
  const parentThreadID = "spawn-edge-parent";
  const childThreadID = "spawn-edge-child";
  const parentRow = fixtureThread(parentThreadID, "Parent row before spawn", 100);
  const childRow = {
    id: childThreadID,
    sessionId: "spawn-edge-child-session",
    preview: "Spawned child row",
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
  const listening = new Promise((resolve) => historyServer.once("listening", resolve));
  await listening;
  historyServer.on("connection", (ws) => {
    ws.on("message", (data) => {
      const message = JSON.parse(data.toString());
      if (message.method === "initialize") {
        sendFixtureResult(ws, message.id, {
          userAgent: "codex-spawn-edge-fixture",
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
      } else if (message.method === "thread/read") {
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
    ...appServerRegistryFixtureConfig({
      historyUrl: `ws://127.0.0.1:${historyServer.address().port}`,
      historyBearerToken: "history-token",
    }),
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
  const fixtureOptions = {
    ...options,
    relayUrl: `ws://127.0.0.1:${relay.server.address().port}`,
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
        dockSnapshotHasThread(snapshot, parentThreadID)
        && !dockSnapshotHasThread(snapshot, childThreadID)
      ),
    });
    if (!initialWait.ok) {
      findings.push({
        code: "scenario_spawn_edge_initial_state_wrong",
        severity: "error",
        message: "spawn-edge fixture did not start with only the parent row visible through the Dock stream",
        parentThreadID,
        childThreadID,
      });
    }

    const spawnStartedAtMs = Date.now();
    sourceRows = [childRow, parentRow];
    await relayConfig.relayStateEngine.reconcileDock({ reason: "scenario_spawn_edge_child_added" });
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
      findings.push({
        code: "scenario_spawn_edge_child_leaked_or_parent_missing",
        severity: "error",
        message: "spawned child row was not kept out of the human-only long-lived Dock stream",
        parentThreadID,
        childThreadID,
      });
    } else if (spawnLag.exceeded) {
      findings.push({
        code: "scenario_spawn_edge_lag_exceeded",
        severity: "error",
        message: "human-only spawn-edge state settled after the client-visible lag budget",
        observedLagMs: spawnLag.observedLagMs,
        maxStreamLagMs: options.maxStreamLagMs,
      });
    }

    const freshDock = await collectDockClientPathSnapshot(fixtureOptions, routeEvents);
    const streamComparison = compareDockStates(streamProbe.snapshot(), freshDock);
    findings.push(...scenarioComparisonFindings({ phase: "spawn-edge", comparison: streamComparison }));
    const freshChildCard = dockSnapshotCardForThread(freshDock, childThreadID);
    if (freshChildCard) {
      findings.push({
        code: "scenario_spawn_edge_fresh_child_leaked",
        severity: "error",
        message: "spawned child row reached a fresh human-only Dock client-path subscription",
        childThreadID,
        actualLane: freshChildCard.lane || null,
        actualSourceKind: freshChildCard.sourceKind || null,
      });
    }

    let subscribeRejection = null;
    try {
      await withRelayClient(fixtureOptions, null, async (client) => {
        recordRoute(routeEvents, "thread/detail/subscribe", "spawn-edge scenario child projection rejection subscribe", {
          threadID: childThreadID,
        });
        return client.request("thread/detail/subscribe", {
          threadId: childThreadID,
        });
      }, routeEvents);
    } catch (error) {
      subscribeRejection = error;
    }
    if (subscribeRejection?.code !== -32043) {
      findings.push({
        code: "scenario_spawn_edge_subscribe_not_rejected",
        severity: "error",
        message: "thread/detail/subscribe for spawned child did not reject with the human-only filter code",
        threadID: childThreadID,
        actualCode: subscribeRejection?.code || null,
        actualMessage: subscribeRejection?.message || null,
      });
    } else if (subscribeRejection?.data?.reason !== "not_base_level" && subscribeRejection?.data?.reason !== "sub_agent") {
      findings.push({
        code: "scenario_spawn_edge_subscribe_wrong_rejection_reason",
        severity: "error",
        message: "thread/detail/subscribe for spawned child rejected with an unexpected human-only reason",
        threadID: childThreadID,
        actualReason: subscribeRejection?.data?.reason || null,
      });
    }

    transitions.push({
      name: "spawn-edge",
      kind: "spawn-edge",
      iteration: 1,
      routes: ["dock/update", "dock/subscribe", "thread/detail/subscribe"],
      wait: spawnWait,
      lag: spawnLag,
      freshDock: sanitizeDockSnapshotForReport(freshDock),
      streamComparison,
      subscribeRejection: normalizeForComparison({
        code: subscribeRejection?.code || null,
        reason: subscribeRejection?.data?.reason || null,
      }),
    });

    return {
      id: "spawn-edge",
      ok: !findings.some((finding) => finding.severity === "error" || finding.severity === "warning"),
      startedAt: new Date(startedAtMs).toISOString(),
      endedAt: new Date().toISOString(),
      actuator: {
        type: "controlled app-server subagent spawn absence fixture through real relay Dock and detail routes",
        routes: ["dock/subscribe", "dock/update", "thread/detail/subscribe"],
        clientExercised: true,
        note: "The fixture changes app-server thread/list rows to model a new subagent spawn; proof expects the child to stay absent from human-only Dock streams and to reject through thread/detail/subscribe.",
      },
      target: {
        sourceHostID: host.id,
        parentThreadID,
        childThreadID,
      },
      transitions,
      stream: {
        notificationCount: streamProbe.notifications.length,
        resyncCount: streamProbe.resyncs.length,
        finalState: sanitizeDockSnapshotForReport(streamProbe.snapshot()),
      },
      clientPathEvidence: summarizeClientPathEvents([...streamProbe.routeEvents, ...routeEvents]),
      findings,
    };
  } finally {
    await streamProbe.close();
    await relay.close();
    await closeWebSocketServer(historyServer);
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

async function runLiveLeaseExpiryScenario(options) {
  const routeEvents = [];
  const findings = [];
  const transitions = [];
  const startedAtMs = Date.now();
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "codex-dock-live-lease-expiry-"));
  const hostID = "live-lease-expiry-fixture";
  const host = {
    id: hostID,
    displayName: "Live Lease Expiry Fixture",
    endpoint: "127.0.0.1:0",
  };
  const threadID = "live-lease-expiry-thread";
  const sessionID = "live-lease-expiry-session";
  const liveStatusMaxAgeMs = 250;
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
          userAgent: "codex-live-lease-fixture",
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
            preview: "Live row before lease expiry",
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
          userAgent: "codex-live-lease-history-fixture",
          codexHome: tempDir,
          platformFamily: "unix",
          platformOs: "macos",
        });
      } else if (message.method === "thread/list") {
        sendFixtureResult(ws, message.id, {
          data: [fixtureThread(threadID, "Stored row after lease expiry", 100)],
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
    ...appServerRegistryFixtureConfig({
      historyUrl: `ws://127.0.0.1:${historyServer.address().port}`,
      historyBearerToken: "history-token",
      liveEndpoints: [{ label: "live-lease-fixture", url: `ws://127.0.0.1:${liveServer.address().port}` }],
    }),
    liveStatusMaxAgeMs,
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
  const fixtureOptions = {
    ...options,
    relayUrl: `ws://127.0.0.1:${relay.server.address().port}`,
    codexHome: tempDir,
    sqliteHome: tempDir,
    detail: "none",
  };
  const streamProbe = new DockStreamProbe(fixtureOptions);

  try {
    await streamProbe.open();
    const liveWait = await waitForStreamCondition({
      streamProbe,
      timeoutMs: options.dockCollectionTimeoutMs,
      predicate: (snapshot) => dockSnapshotCardForThread(snapshot, threadID)?.status === "running",
    });
    if (!liveWait.ok) {
      findings.push({
        code: "scenario_live_lease_initial_live_not_seen",
        severity: "error",
        message: "live fixture row did not appear as running through the long-lived Dock stream",
        threadID,
      });
    }

    liveRowsEnabled = false;
    const expireStartedAtMs = Date.now();
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
      findings.push({
        code: "scenario_live_lease_expiry_not_seen",
        severity: "error",
        message: "live lease expiry did not publish the non-live status through the long-lived Dock stream",
        threadID,
      });
    } else if (expiredLag.exceeded) {
      findings.push({
        code: "scenario_live_lease_expiry_lag_exceeded",
        severity: "error",
        message: "live lease expiry reached the long-lived Dock stream after the client-visible lag budget",
        threadID,
        observedLagMs: expiredLag.observedLagMs,
        maxStreamLagMs: options.maxStreamLagMs,
      });
    }
    const expiredDock = await collectDockClientPathSnapshot(fixtureOptions, routeEvents);
    const expiredCard = dockSnapshotCardForThread(expiredDock, threadID);
    if (expiredCard?.status !== "unknown") {
      findings.push({
        code: "scenario_live_lease_expiry_fresh_dock_status_mismatch",
        severity: "error",
        message: "fresh Dock client-path snapshot did not agree that the live lease expired",
        threadID,
        status: expiredCard?.status || null,
      });
    }
    const expiredComparison = compareDockStates(streamProbe.snapshot(), expiredDock);
    findings.push(...scenarioComparisonFindings({ phase: "live-lease-expiry", comparison: expiredComparison }));
    transitions.push({
      name: "live-lease-expiry",
      kind: "live-lease-expiry",
      iteration: 1,
      route: "dock/update",
      wait: expiredWait,
      lag: expiredLag,
      freshDock: sanitizeDockSnapshotForReport(expiredDock),
      streamComparison: expiredComparison,
    });

    return {
      id: "live-lease-expiry",
      ok: !findings.some((finding) => finding.severity === "error" || finding.severity === "warning"),
      startedAt: new Date(startedAtMs).toISOString(),
      endedAt: new Date().toISOString(),
      actuator: {
        type: "controlled live app-server lease through real relay Dock routes",
        routes: ["dock/subscribe", "dock/update"],
        clientExercised: true,
        liveStatusMaxAgeMs,
        note: "The fixture first exposes the thread through thread/loaded/list and thread/read, then removes it from the live loaded list. Proof only counts the resulting state observed through real Dock client routes.",
      },
      target: {
        sourceHostID: host.id,
        threadID,
        sessionID,
        leaseExpiresAt: Number.isFinite(leaseExpiresAtMs) && leaseExpiresAtMs > 0 ? new Date(leaseExpiresAtMs).toISOString() : null,
      },
      transitions,
      stream: {
        notificationCount: streamProbe.notifications.length,
        resyncCount: streamProbe.resyncs.length,
        finalState: sanitizeDockSnapshotForReport(streamProbe.snapshot()),
      },
      clientPathEvidence: summarizeClientPathEvents([...streamProbe.routeEvents, ...routeEvents]),
      findings,
    };
  } finally {
    await streamProbe.close();
    await relay.close();
    await closeWebSocketServer(liveServer);
    await closeWebSocketServer(historyServer);
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

async function createMultiHostFixture({ options, tempDir, host, getRows }) {
  const historyServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await new Promise((resolve) => historyServer.once("listening", resolve));
  historyServer.on("connection", (ws) => {
    ws.on("message", (data) => {
      const message = JSON.parse(data.toString());
      if (message.method === "initialize") {
        sendFixtureResult(ws, message.id, {
          userAgent: `codex-${host.id}-fixture`,
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
    ...appServerRegistryFixtureConfig({
      historyUrl: `ws://127.0.0.1:${historyServer.address().port}`,
      historyBearerToken: "history-token",
    }),
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
  return {
    host,
    relay,
    relayConfig,
    historyServer,
    options: {
      ...options,
      relayUrl: `ws://127.0.0.1:${relay.server.address().port}`,
      codexHome: tempDir,
      sqliteHome: tempDir,
      detail: "none",
    },
  };
}

function multiHostIsolationFindings({ label, snapshot, host, expectedThreadIDs, forbiddenThreadIDs = [] }) {
  const findings = [];
  const rows = Array.isArray(snapshot?.rows) ? snapshot.rows : [];
  const projectionIDs = new Set(rows.map((card) => cardID(card)).filter(Boolean));
  for (const card of rows) {
    if (card?.sourceHostID !== host.id) {
      findings.push({
        code: "scenario_multi_host_wrong_source_host",
        severity: "error",
        message: "Dock card used the wrong projection source host id for this relay host",
        label,
        expectedHostID: host.id,
        actualHostID: card?.sourceHostID || null,
        threadID: cardThreadID(card),
      });
    }
    const relayScopedProjectionID = cardThreadID(card)
      ? projectionIDForThreadCard({ sourceHostID: host.id, threadID: cardThreadID(card) })
      : null;
    if (relayScopedProjectionID && card?.projectionID !== relayScopedProjectionID) {
      findings.push({
        code: "scenario_multi_host_wrong_projection_id",
        severity: "error",
        message: "Dock card projectionID is not scoped by the relay sourceHostID and threadID",
        label,
        relayScopedProjectionID,
        cardID: cardID(card),
        threadID: cardThreadID(card),
      });
    }
  }
  for (const threadID of expectedThreadIDs) {
    const relayScopedProjectionID = projectionIDForThreadCard({ sourceHostID: host.id, threadID });
    if (!projectionIDs.has(relayScopedProjectionID)) {
      findings.push({
        code: "scenario_multi_host_expected_thread_missing",
        severity: "error",
        message: "expected host-scoped thread is missing from this relay host",
        label,
        hostID: host.id,
        threadID,
        relayScopedProjectionID,
      });
    }
  }
  for (const threadID of forbiddenThreadIDs) {
    if (rows.some((card) => cardThreadID(card) === threadID)) {
      findings.push({
        code: "scenario_multi_host_foreign_thread_visible",
        severity: "error",
        message: "a thread from another relay host appeared in this host's Dock stream",
        label,
        hostID: host.id,
        forbiddenThreadID: threadID,
      });
    }
  }
  return findings;
}

async function runMultiHostIsolationScenario(options) {
  const routeEvents = [];
  const findings = [];
  const transitions = [];
  const startedAtMs = Date.now();
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "codex-dock-multi-host-"));
  const sharedThreadID = "shared-thread-id";
  const hostAOnlyThreadID = "host-a-only";
  const hostBOnlyThreadID = "host-b-only";
  const hostANewThreadID = "host-a-new";
  const hostA = {
    id: "multi-host-a",
    displayName: "Multi Host A",
    endpoint: "127.0.0.1:0/a",
  };
  const hostB = {
    id: "multi-host-b",
    displayName: "Multi Host B",
    endpoint: "127.0.0.1:0/b",
  };
  let hostARows = [
    fixtureThread(sharedThreadID, "Shared id from host A", 200),
    fixtureThread(hostAOnlyThreadID, "Only host A", 100),
  ];
  let hostBRows = [
    fixtureThread(sharedThreadID, "Shared id from host B", 200),
    fixtureThread(hostBOnlyThreadID, "Only host B", 100),
  ];
  const fixtures = [];
  const streamProbes = [];

  try {
    const fixtureA = await createMultiHostFixture({
      options,
      tempDir,
      host: hostA,
      getRows: () => hostARows,
    });
    const fixtureB = await createMultiHostFixture({
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
      findings.push({
        code: "scenario_multi_host_initial_a_missing",
        severity: "error",
        message: "host A initial Dock stream did not expose its expected rows",
      });
    }
    if (!initialBWait.ok) {
      findings.push({
        code: "scenario_multi_host_initial_b_missing",
        severity: "error",
        message: "host B initial Dock stream did not expose its expected rows",
      });
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
      findings.push({
        code: "scenario_multi_host_shared_thread_collision",
        severity: "error",
        message: "same thread id from two relay hosts produced the same client card id",
        sharedThreadID,
        cardID: cardID(sharedA),
      });
    }

    const updateStartedAtMs = Date.now();
    hostARows = [
      fixtureThread(hostANewThreadID, "New host A row", 300),
      fixtureThread(sharedThreadID, "Shared id from host A", 200),
      fixtureThread(hostAOnlyThreadID, "Only host A", 100),
    ];
    await fixtureA.relayConfig.relayStateEngine.reconcileDock({ reason: "scenario_multi_host_a_update" });
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
      findings.push({
        code: "scenario_multi_host_update_not_seen",
        severity: "error",
        message: "host A update did not appear on host A long-lived Dock stream",
        threadID: hostANewThreadID,
      });
    } else if (updateLag.exceeded) {
      findings.push({
        code: "scenario_multi_host_update_lag_exceeded",
        severity: "error",
        message: "host A update reached its Dock stream after the client-visible lag budget",
        observedLagMs: updateLag.observedLagMs,
        maxStreamLagMs: options.maxStreamLagMs,
      });
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
      findings.push({
        code: "scenario_multi_host_update_leaked",
        severity: "error",
        message: "host A update leaked into host B fresh Dock client-path snapshot",
        threadID: hostANewThreadID,
      });
    }

    transitions.push({
      name: "multi-host-isolation",
      kind: "multi-host-isolation",
      iteration: 1,
      route: "dock/update",
      wait: updateAWait,
      lag: updateLag,
      freshDockA: sanitizeDockSnapshotForReport(freshA),
      freshDockB: sanitizeDockSnapshotForReport(freshB),
      streamComparisonA: comparisonA,
      streamComparisonB: comparisonB,
    });

    return {
      id: "multi-host-isolation",
      ok: !findings.some((finding) => finding.severity === "error" || finding.severity === "warning"),
      startedAt: new Date(startedAtMs).toISOString(),
      endedAt: new Date().toISOString(),
      actuator: {
        type: "two controlled app-server fixtures through two real relay Dock routes",
        routes: ["dock/subscribe", "dock/update"],
        clientExercised: true,
        note: "Both fixtures expose the same thread id under different relay host ids; proof only counts host-scoped cards observed through each relay's real Dock client routes.",
      },
      target: {
        hostIDs: [hostA.id, hostB.id],
        sharedThreadID,
        hostAOnlyThreadID,
        hostBOnlyThreadID,
        hostANewThreadID,
      },
      transitions,
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
      clientPathEvidence: summarizeClientPathEvents([
        ...streamA.routeEvents,
        ...streamB.routeEvents,
        ...routeEvents,
      ]),
      findings,
    };
  } finally {
    await Promise.all(streamProbes.map((probe) => probe.close().catch(() => null)));
    for (const fixture of fixtures) {
      await fixture.relay.close().catch(() => null);
      await closeWebSocketServer(fixture.historyServer).catch(() => null);
    }
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

async function runServerRequestScenario(options) {
  const routeEvents = [];
  const findings = [];
  const transitions = [];
  const notifications = [];
  const requests = [];
  const startedAtMs = Date.now();
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "codex-dock-server-request-"));
  const hostID = "server-request-fixture";
  const host = {
    id: hostID,
    displayName: "Server Request Fixture",
    endpoint: "127.0.0.1:0",
  };
  const threadID = "server-request-thread";
  const requestID = "approval-1";
  let upstreamRequestSentAtMs = null;
  let clientRequestReceivedAtMs = null;
  let clientResponseSentAtMs = null;
  let upstreamResponseReceivedAtMs = null;
  let resolutionReceivedAtMs = null;
  let forwardedResponse = null;
  let resolveClientRequest;
  let resolveForwardedResponse;
  let resolveResolution;
  const clientRequestPromise = new Promise((resolve) => {
    resolveClientRequest = resolve;
  });
  const forwardedResponsePromise = new Promise((resolve) => {
    resolveForwardedResponse = resolve;
  });
  const resolutionPromise = new Promise((resolve) => {
    resolveResolution = resolve;
  });

  const historyServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  const listening = new Promise((resolve) => historyServer.once("listening", resolve));
  await listening;
  historyServer.on("connection", (ws) => {
    ws.on("message", (data) => {
      const message = JSON.parse(data.toString());
      if (message.method === "initialize") {
        sendFixtureResult(ws, message.id, {
          userAgent: "codex-server-request-fixture",
          codexHome: tempDir,
          platformFamily: "unix",
          platformOs: "macos",
        });
      } else if (message.method === "thread/list") {
        sendFixtureResult(ws, message.id, {
          data: [fixtureThread(threadID, "Server request fixture row", 100)],
          nextCursor: null,
          backwardsCursor: null,
        });
      } else if (message.method === "thread/loaded/list") {
        sendFixtureResult(ws, message.id, { data: [], nextCursor: null });
      } else if (message.method === "thread/read") {
        sendFixtureResult(ws, message.id, {
          thread: {
            id: message.params?.threadId || threadID,
            turns: [],
          },
        });
      } else if (message.method === "thread/turns/list") {
        sendFixtureResult(ws, message.id, {
          data: [],
          nextCursor: null,
          backwardsCursor: null,
        });
      } else if (message.method === "thread/resume") {
        sendFixtureResult(ws, message.id, {
          thread: {
            id: message.params?.threadId || threadID,
            turns: [],
          },
        });
        setTimeout(() => {
          upstreamRequestSentAtMs = Date.now();
          ws.send(JSON.stringify({
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
          }));
        }, 10);
      } else if (!message.method && String(message.id) === requestID) {
        upstreamResponseReceivedAtMs = Date.now();
        forwardedResponse = normalizeForComparison(message);
        resolveForwardedResponse({
          receivedAtMs: upstreamResponseReceivedAtMs,
          message: forwardedResponse,
        });
        setTimeout(() => {
          ws.send(JSON.stringify({
            jsonrpc: "2.0",
            method: "serverRequest/resolved",
            params: {
              threadId: threadID,
              requestId: requestID,
            },
          }));
        }, 10);
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
    ...appServerRegistryFixtureConfig({
      historyUrl: `ws://127.0.0.1:${historyServer.address().port}`,
      historyBearerToken: "history-token",
    }),
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
  const fixtureOptions = {
    ...options,
    relayUrl: `ws://127.0.0.1:${relay.server.address().port}`,
    codexHome: tempDir,
    sqliteHome: tempDir,
    detail: "none",
  };
  const streamProbe = new DockStreamProbe(fixtureOptions);
  let detailClient = null;

  try {
    await streamProbe.open();
    const rowWait = await waitForStreamThreadPresence({
      streamProbe,
      threadID,
      present: true,
      timeoutMs: options.dockCollectionTimeoutMs,
      notBeforeMs: startedAtMs,
    });
    if (!rowWait.ok) {
      findings.push({
        code: "scenario_server_request_dock_row_missing",
        severity: "error",
        message: "server-request fixture row did not appear through the Dock client path",
        threadID,
      });
    }

    const target = {
      cardID: projectionIDForThreadCard({ sourceHostID: host.id, threadID }),
      threadID,
      sourceHostID: host.id,
      status: "idle",
      archived: false,
    };
    let phase = "connecting";
    detailClient = new JsonRpcWebSocketClient(fixtureOptions.relayUrl, {
      requestTimeoutMs: options.requestTimeoutMs,
      onNotification: (message) => {
        const receivedAtMs = Date.now();
        const sanitized = sanitizeDetailLiveMessage(message, {
          phase,
          receivedAt: new Date(receivedAtMs).toISOString(),
          source: "notification",
        });
        notifications.push(sanitized);
        if (message?.method === "serverRequest/resolved") {
          resolutionReceivedAtMs = receivedAtMs;
          resolveResolution({
            receivedAtMs,
            message: normalizeForComparison(message),
          });
        }
      },
      onRequest: (message) => {
        const receivedAtMs = Date.now();
        clientRequestReceivedAtMs = receivedAtMs;
        const sanitized = sanitizeDetailLiveMessage(message, {
          phase,
          receivedAt: new Date(receivedAtMs).toISOString(),
          source: "request",
        });
        requests.push(sanitized);
        recordRoute(routeEvents, "server/request", "receive live server request on detail client path", {
          method: message.method,
          threadID: detailMessageThreadID(message),
          requestID: message.id ?? null,
        });
        resolveClientRequest({
          receivedAtMs,
          message: normalizeForComparison(message),
        });
        clientResponseSentAtMs = Date.now();
        recordRoute(routeEvents, "server/response", "send client response for live server request", {
          requestID: message.id ?? null,
        });
        detailClient?.sendRaw({
          jsonrpc: "2.0",
          id: message.id,
          result: {
            decision: "accept",
          },
        });
      },
    });

    recordRoute(routeEvents, "initialize", "open server-request detail client-path session", { threadID });
    await initializeClient(detailClient);
    recordRoute(routeEvents, "initialized", "server-request detail client initialized notification sent", { threadID });

    phase = "subscribe";
    const subscribeStartedAtMs = Date.now();
    recordRoute(routeEvents, "thread/detail/subscribe", "server-request scenario detail projection subscribe", {
      threadID,
    });
    const subscribeResponse = await detailClient.request("thread/detail/subscribe", {
      threadId: threadID,
    });
    const liveBoundaryAt = new Date().toISOString();
    const subscribeAckMs = Date.now();
    phase = "live";
    const subscribe = projectionSnapshotSummary(subscribeResponse, threadID);
    if (!subscribe.ok) {
      findings.push({
        code: "scenario_server_request_subscribe_wrong_thread",
        severity: "error",
        message: "server-request scenario thread/detail/subscribe returned a malformed projection or the wrong thread",
        expectedThreadID: threadID,
        actualThreadID: subscribe.threadID,
        view: subscribe.view,
        duplicateProjectionIDs: subscribe.duplicateProjectionIDs,
      });
    }

    const requestWait = await waitForAsyncEvent(clientRequestPromise, options.dockCollectionTimeoutMs);
    const responseWait = await waitForAsyncEvent(forwardedResponsePromise, options.dockCollectionTimeoutMs);
    const resolutionWait = await waitForAsyncEvent(resolutionPromise, options.dockCollectionTimeoutMs);
    const requestLag = scenarioLagSummary({
      transition: "server-request-visible",
      startedAtMs: upstreamRequestSentAtMs || subscribeStartedAtMs,
      acknowledgedAtMs: upstreamRequestSentAtMs || subscribeAckMs,
      observedAtMs: clientRequestReceivedAtMs,
      maxStreamLagMs: options.maxStreamLagMs,
    });
    const resolutionLag = scenarioLagSummary({
      transition: "server-request-resolution",
      startedAtMs: clientResponseSentAtMs || clientRequestReceivedAtMs || subscribeStartedAtMs,
      acknowledgedAtMs: upstreamResponseReceivedAtMs || clientResponseSentAtMs || subscribeAckMs,
      observedAtMs: resolutionReceivedAtMs,
      maxStreamLagMs: options.maxStreamLagMs,
    });

    if (!requestWait.ok) {
      findings.push({
        code: "scenario_server_request_not_seen",
        severity: "error",
        message: "server request did not arrive on the detail client path after thread/detail/subscribe",
        threadID,
        timeoutMs: options.dockCollectionTimeoutMs,
      });
    } else if (requestLag.exceeded) {
      findings.push({
        code: "scenario_server_request_lag_exceeded",
        severity: "error",
        message: "server request arrived after the client-visible lag budget",
        observedLagMs: requestLag.observedLagMs,
        maxStreamLagMs: options.maxStreamLagMs,
      });
    }
    if (requestWait.ok && requestWait.value?.message?.method !== "item/commandExecution/requestApproval") {
      findings.push({
        code: "scenario_server_request_wrong_method",
        severity: "error",
        message: "server request method is not one the client can render as the expected request card",
        actualMethod: requestWait.value?.message?.method || null,
      });
    }
    if (!responseWait.ok) {
      findings.push({
        code: "scenario_server_request_response_not_forwarded",
        severity: "error",
        message: "client response to server request did not reach the upstream app-server path",
        requestID,
        timeoutMs: options.dockCollectionTimeoutMs,
      });
    }
    if (responseWait.ok && responseWait.value?.message?.result?.decision !== "accept") {
      findings.push({
        code: "scenario_server_request_response_wrong_payload",
        severity: "error",
        message: "upstream received the wrong client response payload for server request resolution",
        requestID,
        response: responseWait.value?.message || null,
      });
    }
    if (!resolutionWait.ok) {
      findings.push({
        code: "scenario_server_request_resolution_not_seen",
        severity: "error",
        message: "server request resolution notification did not arrive back on the detail client path",
        requestID,
        timeoutMs: options.dockCollectionTimeoutMs,
      });
    } else if (resolutionLag.exceeded) {
      findings.push({
        code: "scenario_server_request_resolution_lag_exceeded",
        severity: "error",
        message: "server request resolution arrived after the client-visible lag budget",
        observedLagMs: resolutionLag.observedLagMs,
        maxStreamLagMs: options.maxStreamLagMs,
      });
    }
    if (
      resolutionWait.ok
      && (
        resolutionWait.value?.message?.method !== "serverRequest/resolved"
        || resolutionWait.value?.message?.params?.requestId !== requestID
        || resolutionWait.value?.message?.params?.threadId !== threadID
      )
    ) {
      findings.push({
        code: "scenario_server_request_resolution_wrong_payload",
        severity: "error",
        message: "server request resolution notification did not identify the selected thread and request",
        requestID,
        notification: resolutionWait.value?.message || null,
      });
    }

    const liveObservation = summarizeDetailLiveObservation({
      target,
      notifications,
      requests,
      liveBoundaryAt,
      observeMs: options.detailObserveMs,
      bufferInitialLive: options.detailBufferInitialLive,
    });
    findings.push(...liveObservation.findings);
    if (liveObservation.targetRequestCount < 1) {
      findings.push({
        code: "scenario_server_request_target_request_missing",
        severity: "error",
        message: "server request did not carry the selected thread id, so the client cannot attach it to the detail view",
        threadID,
      });
    }

    transitions.push({
      name: "server-request-visible",
      kind: "server-request-visible",
      iteration: 1,
      route: "thread/detail/subscribe",
      wait: {
        ok: requestWait.ok,
        observedAt: clientRequestReceivedAtMs ? new Date(clientRequestReceivedAtMs).toISOString() : null,
        observedAtMs: clientRequestReceivedAtMs,
      },
      lag: requestLag,
      request: requestWait.value?.message || null,
      liveObservation,
    });
    transitions.push({
      name: "server-request-resolution",
      kind: "server-request-resolution",
      iteration: 1,
      route: "server/response",
      wait: {
        ok: responseWait.ok && resolutionWait.ok,
        responseForwardedAt: upstreamResponseReceivedAtMs ? new Date(upstreamResponseReceivedAtMs).toISOString() : null,
        resolutionObservedAt: resolutionReceivedAtMs ? new Date(resolutionReceivedAtMs).toISOString() : null,
      },
      lag: resolutionLag,
      forwardedResponse,
      resolution: resolutionWait.value?.message || null,
    });

    return {
      id: "server-request",
      ok: !findings.some((finding) => finding.severity === "error" || finding.severity === "warning"),
      startedAt: new Date(startedAtMs).toISOString(),
      endedAt: new Date().toISOString(),
      actuator: {
        type: "controlled app-server detail fixture through real relay detail routes",
        routes: ["thread/detail/subscribe"],
        clientExercised: true,
        note: "The fixture creates the live server request; proof only counts delivery and response through the real relay detail client path.",
      },
      target,
      transitions,
      detail: {
        subscribe: {
          ok: subscribe.ok,
          threadID: subscribe.threadID,
          liveBoundaryAt,
        },
        liveObservation,
      },
      stream: {
        notificationCount: streamProbe.notifications.length,
        resyncCount: streamProbe.resyncs.length,
        finalState: sanitizeDockSnapshotForReport(streamProbe.snapshot()),
      },
      clientPathEvidence: summarizeClientPathEvents([...streamProbe.routeEvents, ...routeEvents]),
      findings,
    };
  } finally {
    await detailClient?.close?.();
    await streamProbe.close();
    await relay.close();
    await closeWebSocketServer(historyServer);
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

async function runSourceRefreshScenario(options) {
  const routeEvents = [];
  const findings = [];
  const transitions = [];
  const startedAtMs = Date.now();
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "codex-dock-source-refresh-"));
  const hostID = "source-refresh-fixture";
  const host = {
    id: hostID,
    displayName: "Source Refresh Fixture",
    endpoint: "127.0.0.1:0",
  };
  const cachedThreadID = "source-refresh-cached";
  const recoveredThreadID = "source-refresh-recovered";
  let upstreamAvailable = true;
  let sourceRows = [
    fixtureThread(cachedThreadID, "Cached row before source outage", 100),
  ];
  const historyServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  const listening = new Promise((resolve) => historyServer.once("listening", resolve));
  await listening;
  historyServer.on("connection", (ws) => {
    ws.on("message", (data) => {
      const message = JSON.parse(data.toString());
      if (message.method === "initialize") {
        sendFixtureResult(ws, message.id, {
          userAgent: "codex-source-refresh-fixture",
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
    hostId: host.id,
    hostName: host.displayName,
    hostEndpoint: host.endpoint,
    ...appServerRegistryFixtureConfig({
      historyUrl: `ws://127.0.0.1:${historyServer.address().port}`,
      historyBearerToken: "history-token",
    }),
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
  const fixtureOptions = {
    ...options,
    relayUrl: `ws://127.0.0.1:${relay.server.address().port}`,
    codexHome: tempDir,
    sqliteHome: tempDir,
    detail: "none",
  };
  const streamProbe = new DockStreamProbe(fixtureOptions);

  try {
    await streamProbe.open();
    const initialWait = await waitForStreamThreadPresence({
      streamProbe,
      threadID: cachedThreadID,
      present: true,
      timeoutMs: options.dockCollectionTimeoutMs,
      notBeforeMs: startedAtMs,
    });
    if (!initialWait.ok) {
      findings.push({
        code: "scenario_source_refresh_initial_row_missing",
        severity: "error",
        message: "controlled fixture row did not appear through the Dock client path before source failure",
        threadID: cachedThreadID,
      });
    }

    const failStartedAtMs = Date.now();
    upstreamAvailable = false;
    await relayConfig.relayStateEngine.reconcileDock({ reason: "scenario_source_refresh_fails" });
    const staleWait = await waitForStreamCondition({
      streamProbe,
      timeoutMs: options.dockCollectionTimeoutMs,
      predicate: (snapshot) => snapshot?.freshness?.status === "stale",
    });
    const failLag = scenarioLagSummary({
      transition: "source-refresh-fails",
      startedAtMs: failStartedAtMs,
      acknowledgedAtMs: failStartedAtMs,
      observedAtMs: staleWait.observedAtMs,
      maxStreamLagMs: options.maxStreamLagMs,
    });
    if (!staleWait.ok) {
      findings.push({
        code: "scenario_source_refresh_stale_not_seen",
        severity: "error",
        message: "source refresh failure did not become explicit stale freshness through the Dock client stream",
      });
    } else if (failLag.exceeded) {
      findings.push({
        code: "scenario_source_refresh_stale_lag_exceeded",
        severity: "error",
        message: "source refresh stale state appeared after the client-visible lag budget",
        observedLagMs: failLag.observedLagMs,
        maxStreamLagMs: options.maxStreamLagMs,
      });
    }
    const staleSnapshot = streamProbe.snapshot();
    if (!dockSnapshotHasThread(staleSnapshot, cachedThreadID)) {
      findings.push({
        code: "scenario_source_refresh_stale_dropped_cached_row",
        severity: "error",
        message: "stale source refresh dropped the cached row instead of serving explicit stale cached state",
        threadID: cachedThreadID,
      });
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

    const recoverStartedAtMs = Date.now();
    upstreamAvailable = true;
    sourceRows = [
      fixtureThread(recoveredThreadID, "Recovered row after source outage", 200),
    ];
    await relayConfig.relayStateEngine.reconcileDock({ reason: "scenario_source_refresh_recovers" });
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
      findings.push({
        code: "scenario_source_refresh_recovery_not_seen",
        severity: "error",
        message: "source refresh recovery did not reconcile stale rows to the recovered source row through the Dock client stream",
        staleThreadID: cachedThreadID,
        recoveredThreadID,
      });
    } else if (recoverLag.exceeded) {
      findings.push({
        code: "scenario_source_refresh_recovery_lag_exceeded",
        severity: "error",
        message: "source refresh recovery appeared after the client-visible lag budget",
        observedLagMs: recoverLag.observedLagMs,
        maxStreamLagMs: options.maxStreamLagMs,
      });
    }
    const recoveredDock = await collectDockClientPathSnapshot(fixtureOptions, routeEvents);
    const recoveredComparison = compareDockStates(streamProbe.snapshot(), recoveredDock);
    findings.push(...scenarioComparisonFindings({ phase: "source-refresh-recovers", comparison: recoveredComparison }));
    transitions.push({
      name: "source-refresh-recovers",
      kind: "source-refresh-recovers",
      iteration: 1,
      route: "dock/update",
      wait: recoveredWait,
      lag: recoverLag,
      freshDock: sanitizeDockSnapshotForReport(recoveredDock),
      streamComparison: recoveredComparison,
    });

    return {
      id: "source-refresh",
      ok: !findings.some((finding) => finding.severity === "error" || finding.severity === "warning"),
      startedAt: new Date(startedAtMs).toISOString(),
      endedAt: new Date().toISOString(),
      actuator: {
        type: "controlled app-server source fixture through real relay Dock routes",
        routes: ["dock/subscribe", "dock/update"],
        clientExercised: true,
        note: "The upstream source failure/recovery is controlled by the fixture; proof only counts what appears through real relay Dock client routes.",
      },
      target: {
        sourceHostID: host.id,
        cachedThreadID,
        recoveredThreadID,
      },
      transitions,
      stream: {
        notificationCount: streamProbe.notifications.length,
        resyncCount: streamProbe.resyncs.length,
        finalState: sanitizeDockSnapshotForReport(streamProbe.snapshot()),
      },
      clientPathEvidence: summarizeClientPathEvents([...streamProbe.routeEvents, ...routeEvents]),
      findings,
    };
  } finally {
    await streamProbe.close();
    await relay.close();
    await closeWebSocketServer(historyServer);
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

function reportConfig(options) {
  return {
    mode: options.mode,
    relayUrl: sanitizeURLForReport(options.relayUrl),
    codexHome: options.codexHome,
    sqliteHome: options.sqliteHome,
    limit: options.limit,
    clientPathOnly: options.clientPathOnly,
    forceDockResync: options.forceDockResync,
    turnSortDirection: options.turnSortDirection,
    turnItemsView: options.turnItemsView,
    scenario: options.scenario,
    scenarioThreadID: options.scenarioThreadID,
    scenarioHoldMs: options.scenarioHoldMs,
    scenarioRepetitions: options.scenarioRepetitions,
    durationMs: options.durationMs,
    sampleIntervalMs: options.sampleIntervalMs,
    settleMs: options.settleMs,
    dockCollectionTimeoutMs: options.dockCollectionTimeoutMs,
    streamCompareAttempts: options.streamCompareAttempts,
    streamCompareDelayMs: options.streamCompareDelayMs,
    maxStreamLagMs: options.maxStreamLagMs,
    detail: options.detail,
    detailLimit: options.detailLimit,
    detailObserveMs: options.detailObserveMs,
    detailLive: options.detailLive,
    detailBufferInitialLive: options.detailBufferInitialLive,
    requestTimeoutMs: options.requestTimeoutMs,
  };
}

function summarizeSamples(samples, streamProbe) {
  const findings = samples.flatMap((sample) => sample.findings || []);
  const counts = findingCounts(findings);
  const okSamples = samples.filter(sampleOK).length;
  const detailProbeCount = samples.reduce((count, sample) => count + Number(sample.detail?.targetCount || 0), 0);
  const detailBufferedInitialLiveEvents = samples.reduce((count, sample) => (
    count + (sample.detail?.probes || []).reduce((probeCount, probe) => (
      probeCount + Number(probe.liveObservation?.bufferedInitialLiveEventCount || 0)
    ), 0)
  ), 0);
  const clientPathOK = samples.every((sample) => sample.clientPath?.ok !== false);
  const streamLagMeasurements = samples.flatMap((sample) => [
    sample.stream?.convergence,
    sample.stream?.convergenceAfterResync,
  ]).filter((entry) => entry && Number.isFinite(Number(entry.observedLagMs)));
  const maxObservedStreamLagMs = streamLagMeasurements.length > 0
    ? Math.max(...streamLagMeasurements.map((entry) => Number(entry.observedLagMs)))
    : null;
  const routeCounts = {};
  const sampleClientPathEvents = samples.flatMap((sample) => sample.clientPathEvidence?.events || []);
  const allClientPathEvents = streamProbe
    ? [...streamProbe.routeEvents, ...sampleClientPathEvents]
    : sampleClientPathEvents;
  for (const event of allClientPathEvents) {
    if (!event.countedAsClientPath) {
      continue;
    }
    routeCounts[event.route] = (routeCounts[event.route] || 0) + 1;
  }
  return {
    ok: counts.error === 0 && counts.warning === 0,
    sampleCount: samples.length,
    okSamples,
    failedSamples: samples.length - okSamples,
    clientPathOK,
    clientRequiredOracleOK: null,
    clientRequiredOracleSampleCount: 0,
    errors: counts.error,
    warnings: counts.warning,
    info: counts.info,
    streamNotificationCount: streamProbe?.notifications?.length ?? null,
    streamResyncCount: streamProbe?.resyncs?.length ?? null,
    detailProbeCount,
    detailBufferedInitialLiveEvents,
    clientPathRoutesExercised: Object.keys(routeCounts).sort(),
    clientPathRouteCounts: routeCounts,
    parityFailures: 0,
    clientRequiredParityFailures: 0,
    oracleOnlyParitySamples: 0,
    longLivedStreamMismatches: findings.filter((finding) => finding.code?.startsWith("dock_stream_")).length,
    streamLagFailures: findings.filter((finding) => finding.code === "dock_stream_lag_exceeded").length,
    maxObservedStreamLagMs,
    detailFailures: findings.filter((finding) => finding.code?.startsWith("detail_")).length,
  };
}

async function buildScenarioReport(options) {
  const startedAtMs = Date.now();
  const scenarios = [];
  if (options.scenario === "archive-toggle" || options.scenario === "all") {
    scenarios.push(await runArchiveToggleScenario(options));
  }
  if (options.scenario === "detail-reconnect" || options.scenario === "all") {
    scenarios.push(await runDetailReconnectScenario(options));
  }
  if (options.scenario === "resync-gap" || options.scenario === "all") {
    scenarios.push(await runResyncGapScenario(options));
  }
  if (options.scenario === "live-lease-expiry" || options.scenario === "all") {
    scenarios.push(await runLiveLeaseExpiryScenario(options));
  }
  if (options.scenario === "multi-host-isolation" || options.scenario === "all") {
    scenarios.push(await runMultiHostIsolationScenario(options));
  }
  if (options.scenario === "rename-title" || options.scenario === "all") {
    scenarios.push(await runRenameTitleScenario(options));
  }
  if (options.scenario === "server-request" || options.scenario === "all") {
    scenarios.push(await runServerRequestScenario(options));
  }
  if (options.scenario === "source-refresh" || options.scenario === "all") {
    scenarios.push(await runSourceRefreshScenario(options));
  }
  if (options.scenario === "spawn-edge" || options.scenario === "all") {
    scenarios.push(await runSpawnEdgeScenario(options));
  }
  if (options.scenario === "thread-activity" || options.scenario === "all") {
    scenarios.push(await runThreadActivityScenario(options));
  }
  const unsupportedScenarioFindings = unsupportedScenarioFindingsFor(options);
  const scenarioFindings = [
    ...scenarios.flatMap((scenario) => scenario.findings || []),
    ...unsupportedScenarioFindings,
  ];
  const scenarioHasFailure = scenarioFindings
    .some((finding) => finding.severity === "error" || finding.severity === "warning");
  const observationDeadlineMs = options.durationMsExplicit
    ? startedAtMs + options.durationMs
    : null;
  const samples = [];
  let sampleIndex = 0;
  const observationStreamProbe = new DockStreamProbe(options);
  await observationStreamProbe.open();
  await observationStreamProbe.waitForComplete(options.dockCollectionTimeoutMs);
  try {
    do {
      const sample = await buildSample({ options, sampleIndex, streamProbe: observationStreamProbe });
      const firstSample = sampleIndex === 0;
      const findings = firstSample
        ? [...(sample.findings || []), ...scenarioFindings]
        : [...(sample.findings || [])];
      samples.push({
        ...sample,
        ok: sample.ok && !(firstSample && scenarioHasFailure),
        ...(firstSample ? {
          scenarios: scenarios.map((scenario) => ({
            id: scenario.id,
            ok: scenario.ok,
            target: scenario.target || null,
            transitions: scenario.transitions || [],
            findings: scenario.findings || [],
          })),
        } : {}),
        findings,
        findingCounts: findingCounts(findings),
      });
      sampleIndex += 1;
      if (observationDeadlineMs === null || Date.now() >= observationDeadlineMs) {
        break;
      }
      await sleep(Math.min(options.sampleIntervalMs, Math.max(0, observationDeadlineMs - Date.now())));
    } while (Date.now() <= observationDeadlineMs);
  } finally {
    await observationStreamProbe.close();
  }
  const summary = summarizeSamples(samples, observationStreamProbe);
  const scenarioRouteEvents = scenarios.flatMap((scenario) => scenario.clientPathEvidence?.events || []);
  const clientPathEvidence = summarizeClientPathEvents([
    ...scenarioRouteEvents,
    ...observationStreamProbe.routeEvents,
    ...samples.flatMap((sample) => sample.clientPathEvidence?.events || []),
  ]);
  const scenarioFailures = scenarioFindings
    .filter((finding) => finding.severity === "error" || finding.severity === "warning");
  return {
    schemaVersion: 1,
    mode: options.mode,
    startedAt: new Date(startedAtMs).toISOString(),
    endedAt: new Date().toISOString(),
    relayUrl: sanitizeURLForReport(options.relayUrl),
    codexHome: options.codexHome,
    sqliteHome: options.sqliteHome,
    config: reportConfig(options),
    scenarios,
    samples,
    summary: {
      ...summary,
      clientPathRoutesExercised: clientPathEvidence.routes,
      clientPathRouteCounts: clientPathEvidence.routeCounts,
      scenario: options.scenario,
      scenarioCount: scenarios.length,
      scenarioOK: scenarios.every((scenario) => scenario.ok) && scenarioFailures.length === 0,
      scenarioFailures: scenarioFailures.length,
      implementedScenarios: scenarios.map((scenario) => scenario.id),
      unimplementedRequiredScenarios: unsupportedScenarioFindings.map((finding) => finding.scenarioID),
    },
    stream: {
      notificationCount: observationStreamProbe.notifications.length,
      resyncCount: observationStreamProbe.resyncs.length,
      closed: observationStreamProbe.closed,
      finalState: sanitizeDockSnapshotForReport(observationStreamProbe.snapshot()),
    },
    clientPathEvidence,
    oracleEvidence: null,
    failures: samples.flatMap((entry) => entry.findings || [])
      .filter((finding) => finding.severity === "error" || finding.severity === "warning"),
    unsupportedFacts: [],
  };
}

async function buildSyncAuditReport(options) {
  const finalize = (report) => finalizeProofReport({
    kind: "codex-dock-relay-sync-audit-report",
    ...report,
  });
  if (options.mode === "soak") {
    return finalize(await buildSoakReport(options));
  }
  if (options.mode === "scenario") {
    return finalize(await buildScenarioReport(options));
  }
  return finalize(await buildOneShotReport(options));
}

function markdownSummary(report) {
  const lines = [];
  lines.push("# Codex Dock Relay Sync Audit");
  lines.push("");
  lines.push(`Mode: \`${report.mode}\``);
  lines.push(`Relay: \`${report.relayUrl}\``);
  lines.push(`Started: \`${report.startedAt}\``);
  lines.push(`Ended: \`${report.endedAt}\``);
  lines.push("");
  lines.push("## Summary");
  lines.push("");
  lines.push(`- OK: ${report.summary.ok ? "true" : "false"}`);
  lines.push(`- Client-path OK: ${report.summary.clientPathOK ? "true" : "false"}`);
  lines.push(`- Samples: ${report.summary.sampleCount}`);
  lines.push(`- Errors: ${report.summary.errors}`);
  lines.push(`- Warnings: ${report.summary.warnings}`);
  lines.push(`- Long-lived stream mismatches: ${report.summary.longLivedStreamMismatches}`);
  lines.push(`- Stream lag budget: ${report.config?.maxStreamLagMs ?? "unknown"} ms`);
  lines.push(`- Max observed stream lag: ${report.summary.maxObservedStreamLagMs === null ? "not observed" : `${report.summary.maxObservedStreamLagMs} ms`}`);
  lines.push(`- Stream lag failures: ${report.summary.streamLagFailures}`);
  lines.push(`- Detail probes: ${report.summary.detailProbeCount}`);
  lines.push(`- Detail buffered initial live events: ${report.summary.detailBufferedInitialLiveEvents}`);
  lines.push(`- Client-path routes: ${report.summary.clientPathRoutesExercised.join(", ") || "none"}`);
  if (report.mode === "scenario") {
    lines.push(`- Scenario set: ${report.summary.scenario || "unknown"}`);
    lines.push(`- Scenario OK: ${report.summary.scenarioOK ? "true" : "false"}`);
    lines.push(`- Implemented scenarios: ${(report.summary.implementedScenarios || []).join(", ") || "none"}`);
    lines.push(`- Unimplemented required scenarios: ${(report.summary.unimplementedRequiredScenarios || []).join(", ") || "none"}`);
  }
  lines.push("");
  lines.push("Client-path proof counts only relay routes the client exercises.");
  lines.push("");
  lines.push("## Failures");
  lines.push("");
  if (!report.failures.length) {
    lines.push("- None.");
  } else {
    for (const finding of report.failures.slice(0, 50)) {
      lines.push(`- \`${finding.code || "unknown"}\`: ${finding.message || "failure"}`);
    }
    if (report.failures.length > 50) {
      lines.push(`- ${report.failures.length - 50} more failures omitted from summary.`);
    }
  }
  lines.push("");
  lines.push("## Unsupported Or Outside Current Contract");
  lines.push("");
  if (!report.unsupportedFacts.length) {
    lines.push("- None.");
  } else {
    for (const item of report.unsupportedFacts) {
      lines.push(`- ${item}`);
    }
  }
  lines.push("");
  return `${lines.join("\n")}\n`;
}

function writeReportFiles(report, options) {
  assertProofReport(report);
  if (options.jsonOut) {
    fs.mkdirSync(path.dirname(options.jsonOut), { recursive: true });
    fs.writeFileSync(options.jsonOut, `${JSON.stringify(report, null, 2)}\n`, "utf8");
  }
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
  const report = await buildSyncAuditReport(options);
  writeReportFiles(report, options);
  const stdoutReport = options.summaryOnly ? {
    ok: report.summary.ok,
    mode: report.mode,
    startedAt: report.startedAt,
    endedAt: report.endedAt,
    relayUrl: report.relayUrl,
    summary: report.summary,
    reportPath: options.jsonOut || null,
    summaryPath: options.summaryOut || null,
    clientPathEvidence: {
      routes: report.clientPathEvidence?.routes || [],
      routeCounts: report.clientPathEvidence?.routeCounts || {},
      note: report.clientPathEvidence?.note || null,
    },
    oracleEvidence: report.oracleEvidence || null,
    failures: report.failures.slice(0, 20),
    unsupportedFacts: report.unsupportedFacts,
  } : report;
  process.stdout.write(`${JSON.stringify(stdoutReport, null, 2)}\n`);
  if (options.failOnDiff && !report.summary.ok) {
    process.exitCode = 1;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.error(`relay-sync-audit failed: ${error.message || error}`);
    process.exit(1);
  });
}

export {
  DockStreamProbe,
  applyDockPayload,
  buildSyncAuditReport,
  cardID,
  compareDockStates,
  compareDockThreadCard,
  collectDockClientPathSnapshot,
  dockStateFromPayload,
  emptyDockStreamState,
  evaluateStreamConvergenceLag,
  normalizeForComparison,
  parseArgs,
  sanitizeDockSnapshotForReport,
  selectDetailTargets,
  selectScenarioArchiveTarget,
  selectScenarioDetailTarget,
  selectScenarioRenameTarget,
  scenarioLagSummary,
  scenarioRequirementImplemented,
  scenarioTransitionName,
  summarizeClientPathEvents,
  summarizeDetailLiveObservation,
  waitForStreamThreadPresence,
};

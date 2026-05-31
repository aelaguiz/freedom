#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

import {
  DEFAULT_RELAY_WS,
  THREAD_LIST_MAX_LIMIT,
} from "./dock-relay-constants.mjs";
import { JsonRpcWebSocketClient } from "./dock-relay-json-rpc-client.mjs";
import {
  ALL_SOURCE_KINDS_SCOPE,
  EXPLICIT_SOURCE_KINDS,
} from "./dock-relay-state-snapshot.mjs";
import { initializeClient } from "./dock-relay-thread-data.mjs";
import {
  normalizedThreadSourceForFidelity,
  sourceReport,
  textFingerprint,
} from "./dock-relay-thread-fidelity.mjs";

const DEFAULT_INTERACTIVE_CUSTOM_SOURCES = new Set(["atlas", "chatgpt"]);
const TIMESTAMP_TOLERANCE_SECONDS = 2;
const DEFAULT_MISSING_READ_PROBE_LIMIT = 25;
const DEFAULT_REQUEST_TIMEOUT_MS = 120_000;
const ROLLOUT_SESSION_META_MAX_BYTES = 16 * 1024 * 1024;
const ROLLOUT_SESSION_META_CHUNK_BYTES = 64 * 1024;
const TURN_SORT_DIRECTIONS = new Set(["asc", "desc"]);
const TURN_ITEMS_VIEWS = new Set(["notLoaded", "summary", "full"]);
const OUTPUT_SCHEMA_EVIDENCE_KEYS = new Set([
  "outputSchema",
  "output_schema",
  "finalOutputJsonSchema",
  "final_output_json_schema",
  "outputSchemaJson",
  "output_schema_json",
]);

const SQLITE_THREAD_COLUMNS = Object.freeze([
  "id",
  "rollout_path",
  "created_at",
  "updated_at",
  "created_at_ms",
  "updated_at_ms",
  "source",
  "thread_source",
  "agent_nickname",
  "agent_role",
  "agent_path",
  "model_provider",
  "model",
  "reasoning_effort",
  "cwd",
  "cli_version",
  "title",
  "preview",
  "sandbox_policy",
  "approval_mode",
  "tokens_used",
  "first_user_message",
  "has_user_event",
  "archived",
  "archived_at",
  "git_sha",
  "git_branch",
  "git_origin_url",
  "memory_mode",
]);

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

function usage() {
  return [
    "Usage: node scripts/dock-relay-state-parity.mjs [options]",
    "",
    "Options:",
    "  --relay-url <ws-url>       Relay WebSocket URL. Defaults to CODEX_DOCK_RELAY_WS or ws://127.0.0.1:4510.",
    "  --codex-home <path>        Codex home. Defaults to CODEX_HOME or ~/.codex.",
    "  --sqlite-home <path>       SQLite home. Defaults to CODEX_SQLITE_HOME or codex home.",
    "  --limit <n>                App-server page size, capped at 250. Defaults to 250.",
    "  --include-thread-reads     Include app-server/routed thread/read surfaces in the relay snapshot.",
    "  --include-loaded           Include relay thread/loaded/list state in the relay snapshot.",
    "  --include-goals            Include app-server thread/goal/get state in the relay snapshot.",
    "  --include-turns            Include app-server thread/turns/list state in the relay snapshot.",
    "  --exhaustive               Include reads, loaded state, goals, turns, and full turn item availability.",
    "  --turn-sort-direction <asc|desc>  Turn order to request. Defaults to desc, matching app-server default.",
    "  --turn-items-view <notLoaded|summary|full>  Turn item detail to request. Defaults to notLoaded.",
    "  --request-timeout-ms <n>  JSON-RPC timeout for heavy verifier calls. Defaults to 120000.",
    "  --no-dock-subscribe        Do not verify the app-facing dock/subscribe session stream.",
    "  --no-missing-read-probes   Do not call thread/read for SQLite rows missing from thread/list.",
    "  --no-missing-search-probes Do not call thread/search for SQLite rows missing from thread/list.",
    "  --missing-read-probe-limit <n>  Max missing IDs to probe with thread/read. Defaults to 25.",
    "  --json-out <path>          Write the sanitized JSON report to a file.",
    "  --summary-only             Print compact stdout summary instead of the full report.",
    "  --fail-on-diff            Exit 1 when warning/error findings are present.",
    "  --help                    Show this help text.",
  ].join("\n");
}

function parseArgs(argv, env = process.env, cwd = process.cwd()) {
  const options = {
    relayUrl: env.CODEX_DOCK_RELAY_WS || DEFAULT_RELAY_WS,
    codexHome: env.CODEX_HOME || path.join(os.homedir(), ".codex"),
    sqliteHome: env.CODEX_SQLITE_HOME || null,
    limit: THREAD_LIST_MAX_LIMIT,
    includeThreadReads: false,
    includeLoaded: false,
    includeGoals: false,
    includeTurns: false,
    exhaustive: false,
    turnSortDirection: "desc",
    turnItemsView: "notLoaded",
    turnItemsViewExplicit: false,
    requestTimeoutMs: DEFAULT_REQUEST_TIMEOUT_MS,
    includeDockSubscribe: true,
    probeMissingDirectReads: true,
    probeMissingSearches: true,
    missingReadProbeLimit: DEFAULT_MISSING_READ_PROBE_LIMIT,
    jsonOut: null,
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
    } else if (arg === "--include-thread-reads") {
      options.includeThreadReads = true;
    } else if (arg === "--include-loaded") {
      options.includeLoaded = true;
    } else if (arg === "--include-goals") {
      options.includeGoals = true;
    } else if (arg === "--include-turns") {
      options.includeTurns = true;
    } else if (arg === "--exhaustive") {
      options.exhaustive = true;
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
    } else if (arg === "--request-timeout-ms") {
      options.requestTimeoutMs = parsePositiveInteger(readValue(index, arg), "--request-timeout-ms");
      index += 1;
    } else if (arg.startsWith("--request-timeout-ms=")) {
      options.requestTimeoutMs = parsePositiveInteger(arg.slice("--request-timeout-ms=".length), "--request-timeout-ms");
    } else if (arg === "--no-dock-subscribe") {
      options.includeDockSubscribe = false;
    } else if (arg === "--no-missing-read-probes") {
      options.probeMissingDirectReads = false;
    } else if (arg === "--no-missing-search-probes") {
      options.probeMissingSearches = false;
    } else if (arg === "--missing-read-probe-limit") {
      options.missingReadProbeLimit = parsePositiveInteger(readValue(index, arg), "--missing-read-probe-limit");
      index += 1;
    } else if (arg.startsWith("--missing-read-probe-limit=")) {
      options.missingReadProbeLimit = parsePositiveInteger(arg.slice("--missing-read-probe-limit=".length), "--missing-read-probe-limit");
    } else if (arg === "--json-out") {
      options.jsonOut = readValue(index, arg);
      index += 1;
    } else if (arg.startsWith("--json-out=")) {
      options.jsonOut = arg.slice("--json-out=".length);
    } else if (arg === "--summary-only") {
      options.summaryOnly = true;
    } else if (arg === "--fail-on-diff") {
      options.failOnDiff = true;
    } else {
      throw new Error(`unknown option: ${arg}`);
    }
  }

  options.limit = Math.min(options.limit, THREAD_LIST_MAX_LIMIT);
  options.missingReadProbeLimit = Math.min(options.missingReadProbeLimit, THREAD_LIST_MAX_LIMIT);
  if (options.exhaustive) {
    options.includeThreadReads = true;
    options.includeLoaded = true;
    options.includeGoals = true;
    options.includeTurns = true;
    options.includeDockSubscribe = true;
    if (!options.turnItemsViewExplicit) {
      options.turnItemsView = "full";
    }
  }
  if (!TURN_SORT_DIRECTIONS.has(options.turnSortDirection)) {
    throw new Error("--turn-sort-direction must be asc or desc");
  }
  if (!TURN_ITEMS_VIEWS.has(options.turnItemsView)) {
    throw new Error("--turn-items-view must be notLoaded, summary, or full");
  }
  options.codexHome = resolveUserPath(options.codexHome, cwd);
  options.sqliteHome = resolveUserPath(options.sqliteHome || options.codexHome, cwd);
  options.jsonOut = options.jsonOut ? resolveUserPath(options.jsonOut, cwd) : null;
  delete options.turnItemsViewExplicit;
  return options;
}

function sqliteLiteral(value) {
  return `'${String(value).replace(/'/g, "''")}'`;
}

function sqliteIdent(value) {
  if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(value)) {
    throw new Error(`unsafe sqlite identifier: ${value}`);
  }
  return `"${value}"`;
}

function runSQLiteJSON(dbPath, sql) {
  if (!fs.existsSync(dbPath)) {
    return { ok: false, missing: true, rows: [], error: `missing sqlite db: ${dbPath}` };
  }
  const result = spawnSync("sqlite3", ["-readonly", "-json", dbPath, sql], {
    encoding: "utf8",
    maxBuffer: 100 * 1024 * 1024,
  });
  if (result.error) {
    const unavailable = result.error.code === "ENOENT";
    return {
      ok: false,
      missing: false,
      unavailable,
      rows: [],
      error: unavailable ? "sqlite3 command not found" : result.error.message,
    };
  }
  if (result.status !== 0) {
    return {
      ok: false,
      missing: false,
      rows: [],
      error: (result.stderr || result.stdout || `sqlite3 exited ${result.status}`).trim(),
    };
  }
  const stdout = result.stdout.trim();
  if (!stdout) {
    return { ok: true, rows: [] };
  }
  try {
    return { ok: true, rows: JSON.parse(stdout) };
  } catch (error) {
    return { ok: false, missing: false, rows: [], error: `invalid sqlite JSON: ${error.message}` };
  }
}

function readTableColumns(dbPath, table) {
  const result = runSQLiteJSON(dbPath, `PRAGMA table_info(${sqliteIdent(table)});`);
  return {
    ok: result.ok,
    error: result.error || null,
    columns: result.ok ? result.rows.map((row) => row.name).filter(Boolean) : [],
  };
}

function readSQLiteThreads(sqliteHome) {
  const dbPath = path.join(sqliteHome, "state_5.sqlite");
  const table = readTableColumns(dbPath, "threads");
  if (!table.ok) {
    return {
      ok: false,
      dbPath,
      rows: [],
      columns: table.columns,
      error: table.error,
    };
  }
  const columns = new Set(table.columns);
  const selected = SQLITE_THREAD_COLUMNS.filter((column) => columns.has(column));
  if (!selected.includes("id")) {
    return {
      ok: false,
      dbPath,
      rows: [],
      columns: table.columns,
      error: "threads table is missing id column",
    };
  }
  const sql = [
    `SELECT ${selected.map(sqliteIdent).join(", ")}`,
    "FROM threads",
    "ORDER BY COALESCE(updated_at_ms, updated_at * 1000, created_at_ms, created_at * 1000, 0) DESC, id DESC;",
  ].join(" ");
  const result = runSQLiteJSON(dbPath, sql);
  return {
    ok: result.ok,
    dbPath,
    rows: result.rows || [],
    columns: table.columns,
    selectedColumns: selected,
    error: result.ok ? null : result.error,
  };
}

function readGoalSummary(sqliteHome) {
  const dbPath = path.join(sqliteHome, "goals_1.sqlite");
  const table = readTableColumns(dbPath, "thread_goals");
  if (!table.ok) {
    return {
      ok: false,
      dbPath,
      count: null,
      rows: [],
      columns: table.columns,
      error: table.error,
    };
  }
  const result = runSQLiteJSON(dbPath, [
    "SELECT thread_id, goal_id, objective, status, token_budget, tokens_used,",
    "time_used_seconds, created_at_ms, updated_at_ms",
    "FROM thread_goals",
    "ORDER BY updated_at_ms DESC, thread_id DESC;",
  ].join(" "));
  return {
    ok: result.ok,
    dbPath,
    count: result.ok ? (result.rows || []).length : null,
    rows: result.rows || [],
    columns: table.columns,
    error: result.ok ? null : result.error,
  };
}

function readSQLiteSpawnEdges(sqliteHome) {
  const dbPath = path.join(sqliteHome, "state_5.sqlite");
  const table = readTableColumns(dbPath, "thread_spawn_edges");
  if (!table.ok) {
    return {
      ok: false,
      dbPath,
      rows: [],
      columns: table.columns,
      error: table.error,
    };
  }
  const required = ["parent_thread_id", "child_thread_id", "status"];
  const missing = required.filter((column) => !table.columns.includes(column));
  if (missing.length > 0) {
    return {
      ok: false,
      dbPath,
      rows: [],
      columns: table.columns,
      error: `thread_spawn_edges table is missing columns: ${missing.join(", ")}`,
    };
  }
  const result = runSQLiteJSON(dbPath, [
    "SELECT parent_thread_id, child_thread_id, status",
    "FROM thread_spawn_edges",
    "ORDER BY parent_thread_id, child_thread_id;",
  ].join(" "));
  return {
    ok: result.ok,
    dbPath,
    rows: result.rows || [],
    columns: table.columns,
    error: result.ok ? null : result.error,
  };
}

function readFirstLineFromFile(filePath, maxBytes = ROLLOUT_SESSION_META_MAX_BYTES) {
  const fd = fs.openSync(filePath, "r");
  const chunks = [];
  let bytesReadTotal = 0;
  try {
    while (bytesReadTotal < maxBytes) {
      const buffer = Buffer.alloc(Math.min(ROLLOUT_SESSION_META_CHUNK_BYTES, maxBytes - bytesReadTotal));
      const bytesRead = fs.readSync(fd, buffer, 0, buffer.length, bytesReadTotal);
      if (bytesRead === 0) {
        break;
      }
      const chunk = buffer.subarray(0, bytesRead);
      const newline = chunk.indexOf(0x0a);
      if (newline >= 0) {
        chunks.push(chunk.subarray(0, newline));
        return Buffer.concat(chunks).toString("utf8");
      }
      chunks.push(chunk);
      bytesReadTotal += bytesRead;
    }
  } finally {
    fs.closeSync(fd);
  }
  if (bytesReadTotal >= maxBytes) {
    throw new Error(`first line exceeds ${maxBytes} bytes`);
  }
  return Buffer.concat(chunks).toString("utf8");
}

function normalizeRolloutSessionMetaLine(parsed) {
  if (!parsed || typeof parsed !== "object") {
    return null;
  }
  const payload = parsed.type === "session_meta" && parsed.payload && typeof parsed.payload === "object"
    ? parsed.payload
    : parsed.meta && typeof parsed.meta === "object"
      ? parsed.meta
      : parsed;
  if (!payload || typeof payload !== "object") {
    return null;
  }
  const git = payload.git && typeof payload.git === "object"
    ? payload.git
    : parsed.git && typeof parsed.git === "object"
      ? parsed.git
      : null;
  return {
    id: payload.id || null,
    forkedFromId: payload.forked_from_id || payload.forkedFromId || null,
    timestamp: payload.timestamp || null,
    cwd: payload.cwd || null,
    source: payload.source ?? null,
    threadSource: payload.thread_source || payload.threadSource || null,
    originator: payload.originator || null,
    cliVersion: payload.cli_version || payload.cliVersion || null,
    modelProvider: payload.model_provider || payload.modelProvider || null,
    agentNickname: payload.agent_nickname || payload.agentNickname || null,
    agentRole: payload.agent_role || payload.agentRole || payload.agent_type || null,
    agentPath: payload.agent_path || payload.agentPath || null,
    memoryMode: payload.memory_mode || payload.memoryMode || null,
    gitInfo: git ? {
      sha: git.sha || git.commit_hash || null,
      branch: git.branch || null,
      originUrl: git.origin_url || git.originUrl || null,
    } : null,
  };
}

function readRolloutSessionMetaFromPath(filePath) {
  if (!filePath) {
    return { ok: false, path: null, error: "missing rollout path" };
  }
  try {
    const stats = fs.statSync(filePath);
    const firstLine = readFirstLineFromFile(filePath);
    if (!firstLine.trim()) {
      return { ok: false, path: filePath, error: "empty rollout file" };
    }
    const parsed = JSON.parse(firstLine);
    const meta = normalizeRolloutSessionMetaLine(parsed);
    if (!meta || !meta.id) {
      return { ok: false, path: filePath, error: "first line is not session_meta" };
    }
    return {
      ok: true,
      path: filePath,
      modifiedAtMs: Math.floor(stats.mtimeMs),
      meta,
    };
  } catch (error) {
    return { ok: false, path: filePath, error: error?.message || String(error) };
  }
}

function readRolloutSessionMetas(rows) {
  const byThreadID = new Map();
  const errors = [];
  for (const row of rows || []) {
    if (!row?.id || byThreadID.has(row.id)) {
      continue;
    }
    const result = readRolloutSessionMetaFromPath(row.rollout_path);
    byThreadID.set(row.id, result);
    if (!result.ok) {
      errors.push({
        threadID: row.id,
        path: row.rollout_path || null,
        error: result.error,
      });
    }
  }
  return { byThreadID, errors };
}

function summarizeRolloutSessionMetas(readResult) {
  const values = [...(readResult.byThreadID?.values?.() || [])];
  return {
    attempted: values.length,
    found: values.filter((entry) => entry.ok).length,
    missingOrInvalid: values.filter((entry) => !entry.ok).length,
    sampleErrors: (readResult.errors || []).slice(0, 10),
  };
}

function timestampSeconds(value) {
  if (value === null || value === undefined || value === "") {
    return null;
  }
  if (typeof value === "string" && Number.isNaN(Number(value))) {
    const parsed = Date.parse(value);
    return Number.isFinite(parsed) ? Math.floor(parsed / 1000) : null;
  }
  const number = Number(value);
  if (!Number.isFinite(number)) {
    return null;
  }
  return number > 100_000_000_000 ? Math.floor(number / 1000) : Math.floor(number);
}

function sqliteArchived(row) {
  if (row?.archived === null || row?.archived === undefined) {
    return false;
  }
  return Number(row.archived) === 1;
}

function sqliteThreadListableByAppServer(row) {
  // Current Codex thread/list filters out rows whose preview is empty. The
  // relay cannot discover those rows through app-server list pagination.
  return Boolean(row?.id) && typeof row.preview === "string" && row.preview.length > 0;
}

function sourceKindKey(source) {
  if (!source || !source.kind) {
    return "unknown";
  }
  if (source.kind === "custom") {
    return `custom:${source.name || "unknown"}`;
  }
  if (source.kind === "subAgent") {
    return `subAgent:${source.variant || "unknown"}`;
  }
  return source.kind;
}

function parseMaybeJSONValue(value) {
  if (typeof value !== "string") {
    return value;
  }
  const trimmed = value.trim();
  if (!trimmed) {
    return value;
  }
  try {
    return JSON.parse(trimmed);
  } catch {
    return value;
  }
}

function firstObjectValue(object, keys) {
  if (!object || typeof object !== "object") {
    return null;
  }
  for (const key of keys) {
    if (Object.hasOwn(object, key)) {
      return object[key];
    }
  }
  return null;
}

function threadSpawnPayloadFromSource(source) {
  const parsed = parseMaybeJSONValue(source);
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    return null;
  }
  const subAgent = firstObjectValue(parsed, ["subagent", "subAgent"]);
  if (subAgent && typeof subAgent === "object" && !Array.isArray(subAgent)) {
    return firstObjectValue(subAgent, ["thread_spawn", "threadSpawn"]);
  }
  return firstObjectValue(parsed, ["thread_spawn", "threadSpawn"]);
}

function threadSpawnParentIDFromSource(source) {
  const payload = threadSpawnPayloadFromSource(source);
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
    return null;
  }
  const parentID = firstObjectValue(payload, ["parent_thread_id", "parentThreadId"]);
  return nonEmpty(parentID);
}

function expectedSourceScopeNamesForSQLiteThread(row, availableSourceScopes) {
  const source = normalizedThreadSourceForFidelity(row);
  const expected = [];
  for (const scopeName of availableSourceScopes) {
    let matches = false;
    switch (scopeName) {
      case "interactiveDefault":
        matches = source.kind === "cli"
          || source.kind === "vscode"
          || (
            source.kind === "custom"
            && DEFAULT_INTERACTIVE_CUSTOM_SOURCES.has(source.name)
          );
        break;
      case ALL_SOURCE_KINDS_SCOPE:
        matches = source.kind === "cli"
          || source.kind === "vscode"
          || source.kind === "exec"
          || source.kind === "appServer"
          || source.kind === "subAgent"
          || source.kind === "unknown";
        break;
      case "cli":
        matches = source.kind === "cli";
        break;
      case "vscode":
        matches = source.kind === "vscode";
        break;
      case "exec":
        matches = source.kind === "exec";
        break;
      case "appServer":
        matches = source.kind === "appServer";
        break;
      case "subAgent":
        matches = source.kind === "subAgent";
        break;
      case "subAgentReview":
        matches = source.kind === "subAgent" && source.variant === "review";
        break;
      case "subAgentCompact":
        matches = source.kind === "subAgent" && source.variant === "compact";
        break;
      case "subAgentThreadSpawn":
        matches = source.kind === "subAgent" && source.variant === "threadSpawn";
        break;
      case "subAgentOther":
        matches = source.kind === "subAgent" && source.variant === "other";
        break;
      case "unknown":
        matches = source.kind === "unknown";
        break;
      default:
        matches = false;
        break;
    }
    if (matches) {
      expected.push(scopeName);
    }
  }
  return expected;
}

function expectedScopeNamesForSQLiteThread(row, snapshot) {
  const availableSourceScopes = [...new Set((snapshot.scopes || []).map((scope) => scope.sourceScope))];
  const archive = sqliteArchived(row) ? "archived" : "active";
  return expectedSourceScopeNamesForSQLiteThread(row, availableSourceScopes)
    .map((sourceScope) => `${archive}:${sourceScope}`);
}

function sanitizeStatus(status) {
  if (!status || typeof status !== "object") {
    return status || null;
  }
  return {
    type: status.type || null,
    activeFlags: Array.isArray(status.activeFlags) ? [...status.activeFlags] : [],
  };
}

function sanitizeSQLiteThread(row) {
  if (!row) {
    return null;
  }
  return {
    id: row.id || null,
    archived: sqliteArchived(row),
    appServerListable: sqliteThreadListableByAppServer(row),
    hasUserEvent: row.has_user_event === undefined ? null : Number(row.has_user_event) === 1,
    source: sourceReport(row.source, row.thread_source),
    sourceKind: sourceKindKey(normalizedThreadSourceForFidelity(row)),
    threadSource: row.thread_source || null,
    rolloutPath: row.rollout_path || null,
    cwd: row.cwd || null,
    modelProvider: row.model_provider || null,
    model: row.model || null,
    reasoningEffort: row.reasoning_effort || null,
    createdAt: row.created_at ?? null,
    updatedAt: row.updated_at ?? null,
    createdAtMs: row.created_at_ms ?? null,
    updatedAtMs: row.updated_at_ms ?? null,
    cliVersion: row.cli_version || null,
    agentNickname: row.agent_nickname || null,
    agentRole: row.agent_role || null,
    agentPath: row.agent_path || null,
    gitInfo: {
      sha: row.git_sha || null,
      branch: row.git_branch || null,
      originUrl: row.git_origin_url || null,
    },
    sandboxPolicy: row.sandbox_policy || null,
    approvalMode: row.approval_mode || null,
    tokensUsed: row.tokens_used ?? null,
    memoryMode: row.memory_mode || null,
    title: textFingerprint(row.title),
    preview: textFingerprint(row.preview),
    firstUserMessage: textFingerprint(row.first_user_message),
  };
}

function sanitizeRelayThread(thread) {
  if (!thread) {
    return null;
  }
  return {
    id: thread.id || null,
    sessionId: thread.sessionId || null,
    forkedFromId: thread.forkedFromId || null,
    ephemeral: Boolean(thread.ephemeral),
    modelProvider: thread.modelProvider || null,
    createdAt: thread.createdAt ?? null,
    updatedAt: thread.updatedAt ?? null,
    status: sanitizeStatus(thread.status),
    path: thread.path || null,
    cwd: thread.cwd || null,
    cliVersion: thread.cliVersion || null,
    source: sourceReport(thread.source, thread.threadSource),
    sourceKind: sourceKindKey(normalizedThreadSourceForFidelity({
      source: thread.source,
      threadSource: thread.threadSource,
    })),
    threadSource: thread.threadSource || null,
    agentNickname: thread.agentNickname || null,
    agentRole: thread.agentRole || null,
    agentPath: thread.agentPath || null,
    gitInfo: thread.gitInfo || null,
    name: textFingerprint(thread.name),
    preview: textFingerprint(thread.preview),
    turnsCount: Array.isArray(thread.turns) ? thread.turns.length : null,
  };
}

function sanitizeRelayGoal(goal) {
  if (!goal || typeof goal !== "object") {
    return null;
  }
  return {
    threadID: goal.threadId || goal.thread_id || null,
    objective: textFingerprint(goal.objective),
    status: goal.status || null,
    tokenBudget: goal.tokenBudget ?? goal.token_budget ?? null,
    tokensUsed: goal.tokensUsed ?? goal.tokens_used ?? null,
    timeUsedSeconds: goal.timeUsedSeconds ?? goal.time_used_seconds ?? null,
    createdAt: goal.createdAt ?? goal.created_at ?? null,
    updatedAt: goal.updatedAt ?? goal.updated_at ?? null,
  };
}

function sanitizeDockThreadCard(card) {
  if (!card || typeof card !== "object") {
    return null;
  }
  return {
    id: card.id || null,
    logicalHostID: card.logicalHostID || null,
    threadID: card.threadID || null,
    backendSessionID: card.backendSessionID || null,
    status: card.status || null,
    lane: card.lane || null,
    sourceKind: card.sourceKind || null,
    activityAt: card.activityAt ?? null,
    activityAtMs: card.activityAtMs ?? null,
    title: textFingerprint(card.title),
    displaySummary: textFingerprint(card.displaySummary),
  };
}

function sanitizeSQLiteSpawnEdge(edge) {
  if (!edge || typeof edge !== "object") {
    return null;
  }
  return {
    parentThreadID: edge.parent_thread_id || null,
    childThreadID: edge.child_thread_id || null,
    status: edge.status || null,
  };
}

function sanitizeSQLiteGoal(row) {
  if (!row || typeof row !== "object") {
    return null;
  }
  return {
    threadID: row.thread_id || null,
    goalIDPresent: Boolean(row.goal_id),
    objective: textFingerprint(row.objective),
    status: row.status || null,
    tokenBudget: row.token_budget ?? null,
    tokensUsed: row.tokens_used ?? null,
    timeUsedSeconds: row.time_used_seconds ?? null,
    createdAtMs: row.created_at_ms ?? null,
    updatedAtMs: row.updated_at_ms ?? null,
  };
}

function sanitizeRelayAppearance(appearance, thread = null) {
  return {
    scope: appearance?.scope || null,
    archive: appearance?.archive || null,
    archived: appearance?.archived ?? null,
    sourceScope: appearance?.sourceScope || null,
    ordinal: appearance?.ordinal ?? null,
    pageIndex: appearance?.pageIndex ?? null,
    rowIndex: appearance?.rowIndex ?? null,
    thread: sanitizeRelayThread(thread),
  };
}

function missingSearchTermsForSQLiteRow(row) {
  const terms = [];
  const seen = new Set();
  function add(kind, value) {
    const term = nonEmpty(value);
    if (!term || seen.has(term)) {
      return;
    }
    seen.add(term);
    terms.push({
      kind,
      value: term,
      fingerprint: textFingerprint(term),
    });
  }

  add("threadID", row?.id);
  add("cwdBasename", row?.cwd ? path.basename(row.cwd) : null);
  add("gitBranch", row?.git_branch);
  add("gitShaPrefix", typeof row?.git_sha === "string" ? row.git_sha.slice(0, 12) : null);
  return terms;
}

function sanitizeSearchProbe(probe) {
  if (!probe || typeof probe !== "object") {
    return null;
  }
  return {
    threadID: probe.threadID || null,
    sourceScope: probe.sourceScope || null,
    searchTermKind: probe.searchTermKind || null,
    searchTerm: probe.searchTerm || { present: false },
    ok: Boolean(probe.ok),
    complete: probe.complete ?? null,
    pageCount: probe.pageCount ?? null,
    resultCount: probe.resultCount ?? null,
    resultThreadIDs: Array.isArray(probe.resultThreadIDs) ? probe.resultThreadIDs.slice(0, 25) : [],
    includesMissing: Boolean(probe.includesMissing),
    error: probe.error || null,
  };
}

function addFinding(findings, severity, threadID, surface, field, message, values = {}) {
  findings.push({
    severity,
    threadID: threadID || null,
    surface,
    field,
    message,
    ...values,
  });
}

function compareExact(findings, severity, threadID, surface, field, relayValue, sqliteValue, message) {
  if (relayValue === null || relayValue === undefined || sqliteValue === null || sqliteValue === undefined) {
    return;
  }
  if (String(relayValue) !== String(sqliteValue)) {
    addFinding(findings, severity, threadID, surface, field, message, {
      relay: relayValue,
      sqlite: sqliteValue,
    });
  }
}

function compareResolvedPath(findings, severity, threadID, surface, field, relayValue, sqliteValue, message) {
  if (!relayValue || !sqliteValue) {
    return;
  }
  if (path.resolve(relayValue) !== path.resolve(sqliteValue)) {
    addFinding(findings, severity, threadID, surface, field, message, {
      relay: relayValue,
      sqlite: sqliteValue,
    });
  }
}

function compareTimestamp(findings, threadID, surface, field, relayValue, sqliteValue, message) {
  const relaySeconds = timestampSeconds(relayValue);
  const sqliteSeconds = timestampSeconds(sqliteValue);
  if (relaySeconds === null || sqliteSeconds === null) {
    return;
  }
  if (Math.abs(relaySeconds - sqliteSeconds) > TIMESTAMP_TOLERANCE_SECONDS) {
    addFinding(findings, "warning", threadID, surface, field, message, {
      relay: relaySeconds,
      sqlite: sqliteSeconds,
      deltaSeconds: relaySeconds - sqliteSeconds,
    });
  }
}

function valuesMatch(field, lhs, rhs) {
  if (lhs === null || lhs === undefined || rhs === null || rhs === undefined) {
    return true;
  }
  if (field === "cwd" || field === "path" || field === "agentPath") {
    return path.resolve(String(lhs)) === path.resolve(String(rhs));
  }
  return String(lhs) === String(rhs);
}

function summaryValuesMatch(field, lhs, rhs) {
  if (lhs === null || lhs === undefined || rhs === null || rhs === undefined) {
    return false;
  }
  if (field === "cwd" || field === "path" || field === "agentPath") {
    return path.resolve(String(lhs)) === path.resolve(String(rhs));
  }
  if (field === "createdAt" || field === "updatedAt") {
    const lhsSeconds = timestampSeconds(lhs);
    const rhsSeconds = timestampSeconds(rhs);
    return lhsSeconds !== null
      && rhsSeconds !== null
      && Math.abs(lhsSeconds - rhsSeconds) <= TIMESTAMP_TOLERANCE_SECONDS;
  }
  if (typeof lhs === "object" || typeof rhs === "object") {
    return JSON.stringify(lhs) === JSON.stringify(rhs);
  }
  return String(lhs) === String(rhs);
}

function incrementCount(record, key, amount = 1) {
  record[key] = (record[key] || 0) + amount;
}

function isStorageMetadataDisagreement(finding) {
  return finding.surface === "codex.storage"
    && finding.message === "SQLite thread metadata differs from rollout session_meta; relay row findings show which value each app-server surface returned";
}

function summarizeStorageDisagreementAlignment(findings) {
  const summary = {
    total: 0,
    relayMatchesSQLite: 0,
    relayMatchesRollout: 0,
    relayMatchesBoth: 0,
    relayMatchesNeither: 0,
    byField: {},
  };
  for (const finding of findings) {
    if (!isStorageMetadataDisagreement(finding)) {
      continue;
    }
    summary.total += 1;
    const field = finding.field || "unknown";
    if (!summary.byField[field]) {
      summary.byField[field] = {
        total: 0,
        relayMatchesSQLite: 0,
        relayMatchesRollout: 0,
        relayMatchesBoth: 0,
        relayMatchesNeither: 0,
      };
    }
    const bucket = summary.byField[field];
    bucket.total += 1;
    const matchesSQLite = summaryValuesMatch(field, finding.relay, finding.sqlite);
    const matchesRollout = summaryValuesMatch(field, finding.relay, finding.rolloutSessionMeta);
    if (matchesSQLite && matchesRollout) {
      incrementCount(summary, "relayMatchesBoth");
      incrementCount(bucket, "relayMatchesBoth");
    } else if (matchesSQLite) {
      incrementCount(summary, "relayMatchesSQLite");
      incrementCount(bucket, "relayMatchesSQLite");
    } else if (matchesRollout) {
      incrementCount(summary, "relayMatchesRollout");
      incrementCount(bucket, "relayMatchesRollout");
    } else {
      incrementCount(summary, "relayMatchesNeither");
      incrementCount(bucket, "relayMatchesNeither");
    }
  }
  summary.byField = Object.fromEntries(
    Object.entries(summary.byField).sort(([left], [right]) => left.localeCompare(right)),
  );
  return summary;
}

function summarizeFieldsForFindings(findings, predicate) {
  const byField = {};
  for (const finding of findings) {
    if (!predicate(finding)) {
      continue;
    }
    incrementCount(byField, finding.field || "unknown");
  }
  return Object.fromEntries(
    Object.entries(byField).sort((left, right) => (
      right[1] - left[1] || left[0].localeCompare(right[0])
    )),
  );
}

function addStorageDisagreement(findings, context, threadID, field, relayValue, sqliteValue, rolloutValue) {
  const key = `${threadID}:${field}`;
  if (context.storageDisagreementKeys.has(key)) {
    return;
  }
  context.storageDisagreementKeys.add(key);
  addFinding(findings, "warning", threadID, "codex.storage", field, "SQLite thread metadata differs from rollout session_meta; relay row findings show which value each app-server surface returned", {
    relay: relayValue,
    sqlite: sqliteValue,
    rolloutSessionMeta: rolloutValue,
  });
}

function compareRelayFieldToCanonical(findings, context, threadID, scope, field, severity, relayValue, sqliteValue, rolloutValue) {
  if (rolloutValue !== null && rolloutValue !== undefined) {
    if (!valuesMatch(field, relayValue, rolloutValue)) {
      addFinding(findings, severity, threadID, scope, field, `relay ${field} differs from rollout session_meta ${field}`, {
        relay: relayValue,
        rolloutSessionMeta: rolloutValue,
        sqlite: sqliteValue ?? null,
      });
    }
    if (!valuesMatch(field, sqliteValue, rolloutValue)) {
      addStorageDisagreement(findings, context, threadID, field, relayValue, sqliteValue, rolloutValue);
    }
    return;
  }
  compareExact(findings, severity, threadID, scope, field, relayValue, sqliteValue, `relay ${field} differs from SQLite ${field}`);
}

function compareRelaySourceToCanonical(findings, context, threadID, scope, relayThread, sqliteRow, rolloutMeta) {
  const source = normalizedThreadSourceForFidelity({
    source: relayThread?.source,
    threadSource: relayThread?.threadSource,
  });
  const sqliteSource = normalizedThreadSourceForFidelity(sqliteRow);
  const rolloutSource = rolloutMeta ? normalizedThreadSourceForFidelity({
    source: rolloutMeta.source,
    threadSource: rolloutMeta.threadSource,
  }) : null;

  if (rolloutSource) {
    if (JSON.stringify(source) !== JSON.stringify(rolloutSource)) {
      addFinding(findings, "warning", threadID, scope, "source", "relay source classification differs from rollout session_meta source classification", {
        relay: sourceReport(relayThread?.source, relayThread?.threadSource),
        rolloutSessionMeta: sourceReport(rolloutMeta.source, rolloutMeta.threadSource),
        sqlite: sourceReport(sqliteRow?.source, sqliteRow?.thread_source),
      });
    }
    if (JSON.stringify(sqliteSource) !== JSON.stringify(rolloutSource)) {
      addStorageDisagreement(findings, context, threadID, "source", sourceReport(relayThread?.source, relayThread?.threadSource), sourceReport(sqliteRow?.source, sqliteRow?.thread_source), sourceReport(rolloutMeta.source, rolloutMeta.threadSource));
    }
    return;
  }

  if (JSON.stringify(source) !== JSON.stringify(sqliteSource)) {
    addFinding(findings, "warning", threadID, scope, "source", "relay source classification differs from SQLite source classification", {
      relay: sourceReport(relayThread?.source, relayThread?.threadSource),
      sqlite: sourceReport(sqliteRow?.source, sqliteRow?.thread_source),
    });
  }
}

function compareRelayTimestampToCanonical(findings, context, threadID, scope, field, relayValue, sqliteValue, rolloutValue, rolloutLabel = "rollout session_meta timestamp") {
  if (rolloutValue !== null && rolloutValue !== undefined) {
    const relaySeconds = timestampSeconds(relayValue);
    const rolloutSeconds = timestampSeconds(rolloutValue);
    if (relaySeconds !== null && rolloutSeconds !== null && Math.abs(relaySeconds - rolloutSeconds) > TIMESTAMP_TOLERANCE_SECONDS) {
      addFinding(findings, "warning", threadID, scope, field, `relay ${field} differs from ${rolloutLabel}`, {
        relay: relaySeconds,
        rollout: rolloutSeconds,
        sqlite: timestampSeconds(sqliteValue),
        deltaSeconds: relaySeconds - rolloutSeconds,
      });
    }
    const sqliteSeconds = timestampSeconds(sqliteValue);
    if (sqliteSeconds !== null && rolloutSeconds !== null && Math.abs(sqliteSeconds - rolloutSeconds) > TIMESTAMP_TOLERANCE_SECONDS) {
      addStorageDisagreement(findings, context, threadID, field, relaySeconds, sqliteSeconds, rolloutSeconds);
    }
    return;
  }
  compareTimestamp(findings, threadID, scope, field, relayValue, sqliteValue, `relay ${field} differs from SQLite ${field}`);
}

function compareRelayRowToSQLite(findings, context, threadID, relayThread, sqliteRow, scope, rolloutMetaResult, options = {}) {
  const compareUpdatedAtField = options.compareUpdatedAt !== false;
  const rolloutMeta = rolloutMetaResult?.ok ? rolloutMetaResult.meta : null;
  const source = normalizedThreadSourceForFidelity({
    source: relayThread?.source,
    threadSource: relayThread?.threadSource,
  });

  compareExact(findings, "error", threadID, scope, "id", relayThread?.id, sqliteRow?.id, "relay list row ID differs from SQLite thread ID");
  compareResolvedPath(findings, "error", threadID, scope, "path", relayThread?.path, sqliteRow?.rollout_path, "relay rollout path differs from SQLite rollout_path");
  compareRelayFieldToCanonical(findings, context, threadID, scope, "cwd", "warning", relayThread?.cwd, sqliteRow?.cwd, rolloutMeta?.cwd);
  compareRelayFieldToCanonical(findings, context, threadID, scope, "modelProvider", "warning", relayThread?.modelProvider, sqliteRow?.model_provider, rolloutMeta?.modelProvider);
  compareRelayFieldToCanonical(findings, context, threadID, scope, "cliVersion", "warning", relayThread?.cliVersion, sqliteRow?.cli_version, rolloutMeta?.cliVersion);
  compareRelayFieldToCanonical(findings, context, threadID, scope, "agentNickname", "warning", relayThread?.agentNickname, sqliteRow?.agent_nickname, rolloutMeta?.agentNickname);
  compareRelayFieldToCanonical(findings, context, threadID, scope, "agentRole", "warning", relayThread?.agentRole, sqliteRow?.agent_role, rolloutMeta?.agentRole);
  compareRelayFieldToCanonical(findings, context, threadID, scope, "agentPath", "warning", relayThread?.agentPath, sqliteRow?.agent_path, rolloutMeta?.agentPath);
  compareRelayFieldToCanonical(findings, context, threadID, scope, "git.branch", "warning", relayThread?.gitInfo?.branch, sqliteRow?.git_branch, rolloutMeta?.gitInfo?.branch);
  compareRelayFieldToCanonical(findings, context, threadID, scope, "git.sha", "warning", relayThread?.gitInfo?.sha, sqliteRow?.git_sha, rolloutMeta?.gitInfo?.sha);
  compareRelayFieldToCanonical(findings, context, threadID, scope, "git.originUrl", "warning", relayThread?.gitInfo?.originUrl, sqliteRow?.git_origin_url, rolloutMeta?.gitInfo?.originUrl);
  compareRelayTimestampToCanonical(findings, context, threadID, scope, "createdAt", relayThread?.createdAt, sqliteRow?.created_at_ms ?? sqliteRow?.created_at, rolloutMeta?.timestamp);
  if (compareUpdatedAtField) {
    compareRelayTimestampToCanonical(
      findings,
      context,
      threadID,
      scope,
      "updatedAt",
      relayThread?.updatedAt,
      sqliteRow?.updated_at_ms ?? sqliteRow?.updated_at,
      rolloutMetaResult?.modifiedAtMs,
      "rollout file modified time",
    );
  }
  compareRelaySourceToCanonical(findings, context, threadID, scope, relayThread, sqliteRow, rolloutMeta);
  compareRelayFieldToCanonical(findings, context, threadID, scope, "threadSource", "warning", relayThread?.threadSource, sqliteRow?.thread_source, rolloutMeta?.threadSource);

  if (rolloutMeta?.id && relayThread?.id && rolloutMeta.id !== relayThread.id) {
    addFinding(findings, "error", threadID, scope, "session_meta.id", "relay thread ID differs from rollout session_meta id", {
      relay: relayThread.id,
      rolloutSessionMeta: rolloutMeta.id,
    });
  }
  if (source.kind === "subAgent" && !relayThread?.agentNickname && !relayThread?.agentRole && !relayThread?.agentPath) {
    addFinding(findings, "warning", threadID, scope, "agent", "relay classifies thread as sub-agent but has no agent nickname, role, or path");
  }
}

function duplicateValues(values) {
  const seen = new Set();
  const duplicates = new Set();
  for (const value of values) {
    if (!value) {
      continue;
    }
    if (seen.has(value)) {
      duplicates.add(value);
    }
    seen.add(value);
  }
  return [...duplicates].sort();
}

function indexRelaySnapshot(snapshot) {
  const threadsByID = new Map();
  const listRowsByID = new Map();
  const scopeRowsByName = new Map();
  const findings = [];

  const canonicalIDs = (snapshot.threads || []).map((entry) => entry.threadID).filter(Boolean);
  for (const threadID of duplicateValues(canonicalIDs)) {
    addFinding(findings, "error", threadID, "relay.state_snapshot", "threads", "relay canonical thread index contains a duplicate thread ID");
  }
  for (const entry of snapshot.threads || []) {
    if (entry?.threadID) {
      threadsByID.set(entry.threadID, entry);
    }
  }

  for (const scope of snapshot.scopes || []) {
    const scopeRows = [];
    const scopeIDs = [];
    for (const row of scope.rows || []) {
      const threadID = row.thread?.id;
      if (!threadID) {
        addFinding(findings, "error", null, scope.name, "row.thread.id", "relay scope row is missing a thread ID", {
          ordinal: row.ordinal ?? null,
        });
        continue;
      }
      scopeIDs.push(threadID);
      scopeRows.push(row);
      if (!listRowsByID.has(threadID)) {
        listRowsByID.set(threadID, []);
      }
      listRowsByID.get(threadID).push({
        scope: scope.name,
        archive: scope.archive,
        archived: scope.archived,
        sourceScope: scope.sourceScope,
        ordinal: row.ordinal,
        pageIndex: row.pageIndex,
        rowIndex: row.rowIndex,
        thread: row.thread,
      });
    }
    scopeRowsByName.set(scope.name, scopeRows);
    for (const threadID of duplicateValues(scopeIDs)) {
      addFinding(findings, "error", threadID, scope.name, "threadIDsInCodexOrder", "relay scope contains the same thread more than once");
    }
    const explicitIDs = Array.isArray(scope.threadIDsInCodexOrder) ? scope.threadIDsInCodexOrder : [];
    if (JSON.stringify(explicitIDs) !== JSON.stringify(scopeIDs)) {
      addFinding(findings, "error", null, scope.name, "threadIDsInCodexOrder", "relay scope order list differs from scope rows order");
    }
  }

  return {
    threadsByID,
    listRowsByID,
    scopeRowsByName,
    findings,
  };
}

function sqliteIDSet(readResult) {
  return new Set((readResult.rows || []).map((row) => row.id).filter(Boolean));
}

function sqliteStableIDs(before, after) {
  return sqliteThreadIDChanges(before, after).stable;
}

function sqliteThreadIDChanges(before, after) {
  const beforeIDs = sqliteIDSet(before);
  const afterIDs = sqliteIDSet(after);
  const added = [...afterIDs].filter((id) => !beforeIDs.has(id)).sort();
  const removed = [...beforeIDs].filter((id) => !afterIDs.has(id)).sort();
  return {
    stable: added.length === 0 && removed.length === 0,
    added,
    removed,
    addedSet: new Set(added),
    removedSet: new Set(removed),
  };
}

function goalRowsComparable(goalSummary) {
  return (goalSummary.rows || []).map((row) => ({
    threadID: row.thread_id,
    goalID: row.goal_id,
    objective: textFingerprint(row.objective)?.sha256 || null,
    status: row.status,
    tokenBudget: row.token_budget,
    tokensUsed: row.tokens_used,
    timeUsedSeconds: row.time_used_seconds,
    createdAtMs: row.created_at_ms,
    updatedAtMs: row.updated_at_ms,
  })).sort((left, right) => String(left.threadID).localeCompare(String(right.threadID)));
}

function goalRowsChangeCounts(before, after) {
  if (!before?.ok || !after?.ok) {
    return {
      stable: false,
      added: null,
      removed: null,
      changed: null,
    };
  }
  const beforeByID = new Map(goalRowsComparable(before).map((row) => [row.threadID, row]));
  const afterByID = new Map(goalRowsComparable(after).map((row) => [row.threadID, row]));
  let added = 0;
  let removed = 0;
  let changed = 0;
  for (const [threadID, afterRow] of afterByID.entries()) {
    const beforeRow = beforeByID.get(threadID);
    if (!beforeRow) {
      added += 1;
    } else if (JSON.stringify(beforeRow) !== JSON.stringify(afterRow)) {
      changed += 1;
    }
  }
  for (const threadID of beforeByID.keys()) {
    if (!afterByID.has(threadID)) {
      removed += 1;
    }
  }
  return {
    stable: added === 0 && removed === 0 && changed === 0,
    added,
    removed,
    changed,
  };
}

function summarizeSQLiteRows(rows) {
  const byArchive = { active: 0, archived: 0 };
  const bySourceKind = {};
  let withoutUserEvent = 0;
  let appServerListable = 0;
  let appServerNotListable = 0;
  for (const row of rows) {
    if (sqliteArchived(row)) {
      byArchive.archived += 1;
    } else {
      byArchive.active += 1;
    }
    if (row.has_user_event !== undefined && Number(row.has_user_event) !== 1) {
      withoutUserEvent += 1;
    }
    if (sqliteThreadListableByAppServer(row)) {
      appServerListable += 1;
    } else {
      appServerNotListable += 1;
    }
    const sourceKind = sourceKindKey(normalizedThreadSourceForFidelity(row));
    bySourceKind[sourceKind] = (bySourceKind[sourceKind] || 0) + 1;
  }
  return {
    count: rows.length,
    appServerListable,
    appServerNotListable,
    byArchive,
    bySourceKind: Object.fromEntries(Object.entries(bySourceKind).sort(([lhs], [rhs]) => lhs.localeCompare(rhs))),
    withoutUserEvent,
  };
}

function summarizeRelaySnapshot(snapshot) {
  return {
    kind: snapshot.kind || null,
    generatedAt: snapshot.generatedAt || null,
    source: snapshot.source || null,
    surfaceMeanings: snapshot.surfaceMeanings || null,
    complete: Boolean(snapshot.complete),
    scopeCount: snapshot.scopeCount ?? (snapshot.scopes || []).length,
    threadCount: snapshot.threadCount ?? (snapshot.threads || []).length,
    surfaceConflicts: summarizeSurfaceConflicts(snapshot),
    canonicalProjection: summarizeCanonicalProjection(snapshot),
    turnCoverage: summarizeTurnCoverage(snapshot),
    loaded: {
      included: snapshot.loaded !== undefined,
      complete: snapshot.loaded?.complete ?? null,
      threadCount: Array.isArray(snapshot.loaded?.threadIDs) ? snapshot.loaded.threadIDs.length : null,
      error: snapshot.loaded?.error || null,
    },
    scopes: (snapshot.scopes || []).map((scope) => ({
      name: scope.name,
      complete: Boolean(scope.complete),
      rowCount: scope.rowCount ?? (scope.rows || []).length,
      pages: Array.isArray(scope.pages) ? scope.pages.length : 0,
      error: scope.error || null,
      first: scope.threadIDsInCodexOrder?.[0] || null,
      last: scope.threadIDsInCodexOrder?.at(-1) || null,
    })),
  };
}

function summarizeSurfaceConflicts(snapshot) {
  const byField = {};
  let threadsCompared = 0;
  let threadsWithConflicts = 0;
  let fieldConflicts = 0;
  for (const entry of snapshot.threads || []) {
    if (!entry?.surfaceSummary) {
      continue;
    }
    threadsCompared += 1;
    if (!entry.surfaceSummary.hasConflicts) {
      continue;
    }
    threadsWithConflicts += 1;
    for (const field of entry.surfaceSummary.conflictingFields || []) {
      byField[field] = (byField[field] || 0) + 1;
      fieldConflicts += 1;
    }
  }
  return {
    included: threadsCompared > 0,
    threadsCompared,
    threadsWithConflicts,
    fieldConflicts,
    byField: Object.fromEntries(Object.entries(byField).sort(([lhs], [rhs]) => lhs.localeCompare(rhs))),
  };
}

function summarizeCanonicalProjection(snapshot) {
  let threadsCompared = 0;
  let threadsWithProjection = 0;
  let threadsWithCanonicalConflicts = 0;
  let projectedFields = 0;
  let conflictingProjectedFields = 0;
  const byField = {};
  const sourceCounts = {};
  let priority = null;

  for (const entry of snapshot.threads || []) {
    if (!entry?.surfaceSummary) {
      continue;
    }
    threadsCompared += 1;
    const projection = entry.surfaceSummary.canonicalProjection;
    if (!projection) {
      continue;
    }
    threadsWithProjection += 1;
    if (!priority && Array.isArray(projection.priority)) {
      priority = [...projection.priority];
    }
    const fields = projection.fields || {};
    let threadHasConflict = false;
    for (const [field, fieldProjection] of Object.entries(fields)) {
      projectedFields += 1;
      const source = fieldProjection?.source?.kind
        ? `${fieldProjection.source.kind}${fieldProjection.source.scope ? `:${fieldProjection.source.scope}` : ""}`
        : "unknown";
      sourceCounts[source] = (sourceCounts[source] || 0) + 1;
      if (fieldProjection?.hasConflict) {
        threadHasConflict = true;
        conflictingProjectedFields += 1;
        byField[field] = (byField[field] || 0) + 1;
      }
    }
    if (threadHasConflict) {
      threadsWithCanonicalConflicts += 1;
    }
  }

  return {
    included: threadsCompared > 0,
    threadsCompared,
    threadsWithProjection,
    missingProjectionThreads: threadsCompared - threadsWithProjection,
    threadsWithCanonicalConflicts,
    projectedFields,
    conflictingProjectedFields,
    priority,
    sourceCounts: Object.fromEntries(Object.entries(sourceCounts).sort(([lhs], [rhs]) => lhs.localeCompare(rhs))),
    conflictFields: Object.fromEntries(Object.entries(byField).sort(([lhs], [rhs]) => lhs.localeCompare(rhs))),
  };
}

function turnStatusKey(turn) {
  if (typeof turn?.status === "string") {
    return turn.status;
  }
  if (typeof turn?.status?.type === "string") {
    return turn.status.type;
  }
  return "unknown";
}

function itemTypeKey(item) {
  if (typeof item?.type === "string" && item.type.length > 0) {
    return item.type;
  }
  return "unknown";
}

function hasUserMessageItem(turn) {
  const items = Array.isArray(turn?.items) ? turn.items : [];
  return items.some((item) => itemTypeKey(item) === "userMessage" || itemTypeKey(item) === "user_message");
}

function hasOutputSchemaEvidenceKey(value) {
  if (value === null || value === undefined || Array.isArray(value) || typeof value !== "object") {
    return false;
  }
  return Object.keys(value).some((key) => OUTPUT_SCHEMA_EVIDENCE_KEYS.has(key));
}

function chronologicalTurnRows(turnRows, sortDirection) {
  if (sortDirection === "desc") {
    return [...turnRows].reverse();
  }
  return turnRows;
}

function summarizeTurnCoverage(snapshot) {
  const statusCounts = {};
  const itemsViewCounts = {};
  const requestedSortDirection = snapshot.turnRequest?.sortDirection || "desc";
  const requestedItemsView = snapshot.turnRequest?.itemsView || "notLoaded";
  let threadsChecked = 0;
  let completeThreads = 0;
  let incompleteThreads = 0;
  let threadsWithTurns = 0;
  let threadsWithoutTurns = 0;
  let totalTurns = 0;
  let totalItems = 0;
  let totalPages = 0;
  let turnsWithItems = 0;
  let duplicateTurnIDThreads = 0;
  let duplicateTurnIDs = 0;
  let ordinalMismatches = 0;
  let threadsWithAnyUserMessageItem = 0;
  let threadsWithoutUserMessageItem = 0;
  let threadsWithOldestTurnUserMessage = 0;
  let threadsWithOldestTurnNoUserMessage = 0;
  let threadsWithOutputSchemaEvidence = 0;
  let outputSchemaEvidenceTurns = 0;
  let outputSchemaEvidenceItems = 0;
  const itemTypeCounts = {};

  for (const entry of snapshot.threads || []) {
    if (!entry || entry.turns === null || entry.turns === undefined) {
      continue;
    }
    threadsChecked += 1;
    const turns = entry.turns;
    if (turns.complete) {
      completeThreads += 1;
    } else {
      incompleteThreads += 1;
    }
    totalPages += Array.isArray(turns.pages) ? turns.pages.length : 0;
    const turnRows = Array.isArray(turns.turnsInCodexOrder) ? turns.turnsInCodexOrder : [];
    if (turnRows.length > 0) {
      threadsWithTurns += 1;
    } else {
      threadsWithoutTurns += 1;
    }
    totalTurns += turnRows.length;
    const turnIDs = [];
    let threadHasUserMessage = false;
    let threadHasOutputSchemaEvidence = false;
    const rowsInChronologicalOrder = chronologicalTurnRows(turnRows, requestedSortDirection);
    const oldestTurn = rowsInChronologicalOrder[0]?.turn || null;
    if (oldestTurn) {
      if (hasUserMessageItem(oldestTurn)) {
        threadsWithOldestTurnUserMessage += 1;
      } else {
        threadsWithOldestTurnNoUserMessage += 1;
      }
    }
    for (let index = 0; index < turnRows.length; index += 1) {
      const row = turnRows[index];
      if (row.ordinal !== index) {
        ordinalMismatches += 1;
      }
      const turn = row.turn || {};
      if (turn.id) {
        turnIDs.push(turn.id);
      }
      const status = turnStatusKey(turn);
      statusCounts[status] = (statusCounts[status] || 0) + 1;
      const itemsView = turn.itemsView || turn.items_view || "unknown";
      itemsViewCounts[itemsView] = (itemsViewCounts[itemsView] || 0) + 1;
      const items = Array.isArray(turn.items) ? turn.items : [];
      if (items.length > 0) {
        turnsWithItems += 1;
      }
      totalItems += items.length;
      if (hasUserMessageItem(turn)) {
        threadHasUserMessage = true;
      }
      let turnHasOutputSchemaEvidence = hasOutputSchemaEvidenceKey(turn);
      for (const item of items) {
        const type = itemTypeKey(item);
        itemTypeCounts[type] = (itemTypeCounts[type] || 0) + 1;
        if (hasOutputSchemaEvidenceKey(item)) {
          turnHasOutputSchemaEvidence = true;
          outputSchemaEvidenceItems += 1;
        }
      }
      if (turnHasOutputSchemaEvidence) {
        threadHasOutputSchemaEvidence = true;
        outputSchemaEvidenceTurns += 1;
      }
    }
    if (threadHasUserMessage) {
      threadsWithAnyUserMessageItem += 1;
    } else {
      threadsWithoutUserMessageItem += 1;
    }
    if (threadHasOutputSchemaEvidence) {
      threadsWithOutputSchemaEvidence += 1;
    }
    const duplicates = duplicateValues(turnIDs);
    if (duplicates.length > 0) {
      duplicateTurnIDThreads += 1;
      duplicateTurnIDs += duplicates.length;
    }
  }

  return {
    included: threadsChecked > 0,
    source: "thread/turns/list",
    requestedSortDirection,
    requestedItemsView,
    preservedInReturnedPageOrder: true,
    threadsChecked,
    completeThreads,
    incompleteThreads,
    threadsWithTurns,
    threadsWithoutTurns,
    totalTurns,
    totalItems,
    turnsWithItems,
    totalPages,
    duplicateTurnIDThreads,
    duplicateTurnIDs,
    ordinalMismatches,
    statusCounts: Object.fromEntries(Object.entries(statusCounts).sort(([lhs], [rhs]) => lhs.localeCompare(rhs))),
    itemsViewCounts: Object.fromEntries(Object.entries(itemsViewCounts).sort(([lhs], [rhs]) => lhs.localeCompare(rhs))),
    itemTypeCounts: Object.fromEntries(Object.entries(itemTypeCounts).sort(([lhs], [rhs]) => lhs.localeCompare(rhs))),
    startShape: {
      source: "thread/turns/list turn items",
      requestedItemsView,
      requestedSortDirection,
      oldestTurnInference: requestedSortDirection === "desc"
        ? "oldest turn is the last returned row"
        : "oldest turn is the first returned row",
      threadsWithAnyUserMessageItem,
      threadsWithoutUserMessageItem,
      threadsWithOldestTurnUserMessage,
      threadsWithOldestTurnNoUserMessage,
      threadsWithoutTurns,
    },
    outputSchemaEvidence: {
      source: "thread/turns/list top-level turn/item field-name scan",
      evidenceKeys: [...OUTPUT_SCHEMA_EVIDENCE_KEYS].sort(),
      requestedItemsView,
      threadsWithEvidence: threadsWithOutputSchemaEvidence,
      turnsWithEvidence: outputSchemaEvidenceTurns,
      itemsWithEvidence: outputSchemaEvidenceItems,
      historicalStateObserved: outputSchemaEvidenceItems > 0 || outputSchemaEvidenceTurns > 0,
    },
  };
}

function compareRelayTurnCoverage(findings, snapshot) {
  const summary = summarizeTurnCoverage(snapshot);
  if (!summary.included) {
    return summary;
  }
  if (summary.incompleteThreads > 0) {
    addFinding(findings, "error", null, "relay.turns", "complete", "at least one thread/turns/list drain was incomplete", {
      incompleteThreads: summary.incompleteThreads,
    });
  }
  if (summary.duplicateTurnIDThreads > 0) {
    addFinding(findings, "error", null, "relay.turns", "turn.id", "at least one thread/turns/list result contains duplicate turn IDs inside a thread", {
      duplicateTurnIDThreads: summary.duplicateTurnIDThreads,
      duplicateTurnIDs: summary.duplicateTurnIDs,
    });
  }
  if (summary.ordinalMismatches > 0) {
    addFinding(findings, "error", null, "relay.turns", "ordinal", "relay turn ordinal order does not match returned page order", {
      ordinalMismatches: summary.ordinalMismatches,
    });
  }
  return summary;
}

function compareScopeMembership(findings, snapshot, sqliteRow, relayRows) {
  const threadID = sqliteRow.id;
  const expected = new Set(expectedScopeNamesForSQLiteThread(sqliteRow, snapshot));
  const actual = new Set(relayRows.map((row) => row.scope));
  for (const scopeName of expected) {
    if (!actual.has(scopeName)) {
      addFinding(findings, "error", threadID, "relay.state_snapshot", "scope_membership", "SQLite thread is missing from expected relay scope", {
        expectedScope: scopeName,
        sqlite: sanitizeSQLiteThread(sqliteRow),
      });
    }
  }
  for (const scopeName of actual) {
    if (!expected.has(scopeName)) {
      addFinding(findings, "error", threadID, "relay.state_snapshot", "scope_membership", "relay thread appears in a scope not expected from SQLite source/archive state", {
        actualScope: scopeName,
        expectedScopes: [...expected].sort(),
        sqlite: sanitizeSQLiteThread(sqliteRow),
      });
    }
  }
}

function normalizedDockStatusFromThreadStatus(status) {
  if (status?.type === "active") {
    const flags = new Set(status.activeFlags || []);
    if (flags.has("waitingOnApproval")) {
      return "needsApproval";
    }
    if (flags.has("waitingOnUserInput")) {
      return "needsInput";
    }
    return "running";
  }
  switch (status?.type) {
    case "idle":
      return "idle";
    case "systemError":
      return "error";
    case "notLoaded":
      return "dormant";
    default:
      return "unknown";
  }
}

function statusEvidenceForRelayEntry(entry) {
  if (entry?.routedRead?.thread?.status) {
    return {
      source: "routed thread/read",
      status: entry.routedRead.thread.status,
    };
  }
  if (entry?.historyRead?.thread?.status) {
    return {
      source: "history thread/read",
      status: entry.historyRead.thread.status,
    };
  }
  const listStatus = entry?.listRows?.find((row) => row?.thread?.status)?.thread?.status;
  if (listStatus) {
    return {
      source: "thread/list",
      status: listStatus,
    };
  }
  return {
    source: null,
    status: null,
  };
}

function compareLoadedConsistency(findings, snapshot, relayIndex) {
  if (!snapshot.loaded || snapshot.loaded.complete === false) {
    return;
  }
  const loadedIDs = new Set(snapshot.loaded.threadIDs || []);
  for (const [threadID, entry] of relayIndex.threadsByID.entries()) {
    const evidence = statusEvidenceForRelayEntry(entry);
    const statusType = evidence.status?.type || null;
    const listStatuses = (relayIndex.listRowsByID.get(threadID) || [])
      .map((row) => row.thread?.status?.type)
      .filter(Boolean);
    const loaded = loadedIDs.has(threadID);
    if (loaded && statusType === "notLoaded") {
      addFinding(findings, "warning", threadID, "relay.loaded", "status", "thread/loaded/list includes this thread but the best relay status evidence reports notLoaded", {
        statusSource: evidence.source,
        listStatuses: [...new Set(listStatuses)].sort(),
      });
    } else if (!loaded && statusType && statusType !== "notLoaded") {
      addFinding(findings, "warning", threadID, "relay.loaded", "status", "best relay status evidence reports live/non-notLoaded status but thread/loaded/list did not include this thread", {
        statusSource: evidence.source,
        status: statusType,
        listStatuses: [...new Set(listStatuses)].sort(),
      });
    }
  }
}

const RELAY_LIST_CONSISTENCY_FIELDS = Object.freeze([
  "cwd",
  "modelProvider",
  "cliVersion",
  "source",
  "threadSource",
  "agentNickname",
  "agentRole",
  "agentPath",
  "git.branch",
  "git.sha",
  "git.originUrl",
  "status.type",
  "createdAt",
  "updatedAt",
]);

function relayThreadFieldValue(thread, field) {
  switch (field) {
    case "source":
      return sourceReport(thread?.source, thread?.threadSource);
    case "git.branch":
      return thread?.gitInfo?.branch ?? null;
    case "git.sha":
      return thread?.gitInfo?.sha ?? null;
    case "git.originUrl":
      return thread?.gitInfo?.originUrl ?? null;
    case "status.type":
      return thread?.status?.type ?? null;
    default:
      return thread?.[field] ?? null;
  }
}

function canonicalFieldKey(field, value) {
  if (value === null || value === undefined) {
    return null;
  }
  if (field === "cwd" || field === "agentPath") {
    return path.resolve(String(value));
  }
  return JSON.stringify(value);
}

function compareRelayListRowConsistency(findings, relayRowsByID) {
  for (const [threadID, rows] of relayRowsByID.entries()) {
    if (rows.length <= 1) {
      continue;
    }
    for (const field of RELAY_LIST_CONSISTENCY_FIELDS) {
      const valuesByKey = new Map();
      for (const row of rows) {
        const value = relayThreadFieldValue(row.thread, field);
        const key = canonicalFieldKey(field, value);
        if (!key) {
          continue;
        }
        if (!valuesByKey.has(key)) {
          valuesByKey.set(key, []);
        }
        valuesByKey.get(key).push({
          scope: row.scope,
          value,
        });
      }
      if (valuesByKey.size > 1) {
        addFinding(findings, "warning", threadID, "relay.list_rows", field, "same thread has different values across app-server thread/list scopes", {
          values: [...valuesByKey.values()].flat(),
        });
      }
    }
  }
}

function compareRelayThreadPair(findings, threadID, leftSurface, leftThread, rightSurface, rightThread) {
  if (!leftThread || !rightThread) {
    return;
  }
  for (const field of RELAY_LIST_CONSISTENCY_FIELDS) {
    const leftValue = relayThreadFieldValue(leftThread, field);
    const rightValue = relayThreadFieldValue(rightThread, field);
    if (!valuesMatch(field, leftValue, rightValue)) {
      addFinding(findings, "warning", threadID, "relay.thread_read_pair", field, "history thread/read and routed thread/read returned different metadata", {
        [leftSurface]: leftValue,
        [rightSurface]: rightValue,
      });
    }
  }
}

function compareSpawnEdges(findings, snapshot, relayRowsByID, sqliteRowsByID, spawnEdges) {
  if (!spawnEdges?.ok) {
    addFinding(findings, "warning", null, "codex.storage", "thread_spawn_edges", "SQLite thread_spawn_edges could not be read", {
      error: spawnEdges?.error || null,
    });
    return {
      included: false,
      sqliteSpawnEdgeCount: null,
      sqliteSpawnEdgesWithChildThreadRow: null,
      sqliteSpawnEdgesWithRelayChild: null,
      missingRelayChildForSpawnEdge: null,
      parentMismatches: null,
      relaySourceParentsWithoutEdge: null,
      storageSourceParentMismatches: null,
    };
  }

  const edges = spawnEdges.rows || [];
  const edgesByChild = new Map();
  for (const edge of edges) {
    if (!edge.child_thread_id) {
      continue;
    }
    edgesByChild.set(edge.child_thread_id, edge);
  }

  let edgesWithChildThreadRow = 0;
  let edgesWithRelayChild = 0;
  let missingRelayChildForSpawnEdge = 0;
  let parentMismatches = 0;
  let storageSourceParentMismatches = 0;
  const parentMismatchKeys = new Set();

  for (const edge of edges) {
    const childID = edge.child_thread_id;
    const parentID = edge.parent_thread_id;
    if (!childID || !parentID) {
      continue;
    }
    const sqliteChild = sqliteRowsByID.get(childID);
    const relayRows = relayRowsByID.get(childID) || [];
    if (sqliteChild) {
      edgesWithChildThreadRow += 1;
      const sqliteSourceParent = threadSpawnParentIDFromSource(sqliteChild.source);
      if (sqliteSourceParent && sqliteSourceParent !== parentID) {
        storageSourceParentMismatches += 1;
        addFinding(findings, "warning", childID, "codex.storage", "thread_spawn_edges", "SQLite child source parent differs from thread_spawn_edges parent", {
          sqliteSourceParent,
          edge: sanitizeSQLiteSpawnEdge(edge),
        });
      }
    } else {
      addFinding(findings, "info", childID, "codex.storage", "thread_spawn_edges", "spawn edge child thread ID is absent from state_5.sqlite threads", {
        edge: sanitizeSQLiteSpawnEdge(edge),
      });
    }
    if (relayRows.length === 0) {
      if (sqliteChild && sqliteThreadListableByAppServer(sqliteChild)) {
        missingRelayChildForSpawnEdge += 1;
        addFinding(findings, "warning", childID, "relay.spawn_edges", "childThreadID", "spawn edge child thread is listable in SQLite but absent from relay app-server snapshot", {
          edge: sanitizeSQLiteSpawnEdge(edge),
        });
      }
      continue;
    }
    edgesWithRelayChild += 1;
    for (const relayRow of relayRows) {
      const relaySourceParent = threadSpawnParentIDFromSource(relayRow.thread?.source);
      const relaySource = normalizedThreadSourceForFidelity({
        source: relayRow.thread?.source,
        threadSource: relayRow.thread?.threadSource,
      });
      if (!relaySourceParent && relaySource.kind === "subAgent" && relaySource.variant === "threadSpawn") {
        addFinding(findings, "warning", childID, relayRow.scope, "source.parentThreadID", "relay source marks thread as spawned but does not expose parent thread ID", {
          edge: sanitizeSQLiteSpawnEdge(edge),
        });
        continue;
      }
      if (relaySourceParent && relaySourceParent !== parentID) {
        const key = `${childID}:${relayRow.scope}:${relaySourceParent}:${parentID}`;
        if (!parentMismatchKeys.has(key)) {
          parentMismatchKeys.add(key);
          parentMismatches += 1;
        }
        addFinding(findings, "error", childID, relayRow.scope, "source.parentThreadID", "relay spawned parent differs from SQLite thread_spawn_edges parent", {
          relayParentThreadID: relaySourceParent,
          edge: sanitizeSQLiteSpawnEdge(edge),
        });
      }
    }
  }

  let relaySourceParentsWithoutEdge = 0;
  for (const [threadID, relayRows] of relayRowsByID.entries()) {
    if (edgesByChild.has(threadID)) {
      continue;
    }
    const relayParents = [...new Set(relayRows.map((row) => threadSpawnParentIDFromSource(row.thread?.source)).filter(Boolean))];
    for (const relayParentThreadID of relayParents) {
      relaySourceParentsWithoutEdge += 1;
      addFinding(findings, "warning", threadID, "relay.spawn_edges", "source.parentThreadID", "relay source encodes a spawned parent, but SQLite thread_spawn_edges has no child edge for this thread", {
        relayParentThreadID,
      });
    }
  }

  return {
    included: true,
    sqliteSpawnEdgeCount: edges.length,
    sqliteSpawnEdgesWithChildThreadRow: edgesWithChildThreadRow,
    sqliteSpawnEdgesWithRelayChild: edgesWithRelayChild,
    missingRelayChildForSpawnEdge,
    parentMismatches,
    relaySourceParentsWithoutEdge,
    storageSourceParentMismatches,
  };
}

function laneCountsForThreadCards(cards) {
  const counts = {};
  for (const card of cards || []) {
    const lane = card?.lane || "unknown";
    counts[lane] = (counts[lane] || 0) + 1;
  }
  return Object.fromEntries(Object.entries(counts).sort(([lhs], [rhs]) => lhs.localeCompare(rhs)));
}

function firstOrderMismatch(expectedIDs, actualIDs) {
  const maxLength = Math.max(expectedIDs.length, actualIDs.length);
  for (let index = 0; index < maxLength; index += 1) {
    const expectedThreadID = expectedIDs[index] || null;
    const actualThreadID = actualIDs[index] || null;
    if (expectedThreadID !== actualThreadID) {
      return {
        index,
        expectedThreadID,
        actualThreadID,
      };
    }
  }
  return null;
}

function orderMismatchCount(expectedIDs, actualIDs) {
  const maxLength = Math.max(expectedIDs.length, actualIDs.length);
  let mismatches = 0;
  for (let index = 0; index < maxLength; index += 1) {
    if ((expectedIDs[index] || null) !== (actualIDs[index] || null)) {
      mismatches += 1;
    }
  }
  return mismatches;
}

function dockCardActivityAtByThreadID(cards) {
  const byID = new Map();
  for (const card of cards || []) {
    if (card?.threadID) {
      byID.set(card.threadID, card.activityAtMs ?? card.activityAt ?? null);
    }
  }
  return byID;
}

function snapshotUpdatedAtByThreadID(scope) {
  const byID = new Map();
  for (const row of scope?.rows || []) {
    const threadID = row?.thread?.id;
    if (threadID) {
      byID.set(threadID, row.thread.updatedAt ?? null);
    }
  }
  return byID;
}

function dockOrderMismatchMovement(expectedIDs, actualIDs, snapshotUpdatedAt, dockUpdatedAt) {
  let stableMismatches = 0;
  let movementMismatches = 0;
  let firstStableMismatch = null;
  let firstMovementMismatch = null;
  const maxLength = Math.max(expectedIDs.length, actualIDs.length);

  for (let index = 0; index < maxLength; index += 1) {
    const expectedThreadID = expectedIDs[index] || null;
    const actualThreadID = actualIDs[index] || null;
    if (expectedThreadID === actualThreadID) {
      continue;
    }
    const compared = { index, expectedThreadID, actualThreadID };
    const involved = [expectedThreadID, actualThreadID].filter(Boolean);
    const moved = involved.some((threadID) => (
      timestampSeconds(snapshotUpdatedAt.get(threadID)) !== timestampSeconds(dockUpdatedAt.get(threadID))
    ));
    if (moved) {
      movementMismatches += 1;
      firstMovementMismatch = firstMovementMismatch || compared;
    } else {
      stableMismatches += 1;
      firstStableMismatch = firstStableMismatch || compared;
    }
  }

  return {
    stableMismatches,
    movementMismatches,
    firstStableMismatch,
    firstMovementMismatch,
  };
}

function compareDockCodexOrder(findings, snapshot, cards, expectedIDs, auditMovement = { addedThreadIDs: new Set() }) {
  const orderScope = (snapshot?.scopes || []).find((scope) => scope?.name === "active:allSourceKinds");
  if (!orderScope || !Array.isArray(orderScope.threadIDsInCodexOrder)) {
    return {
      compared: false,
      comparableThreadCount: null,
      mismatches: null,
      stableMismatches: null,
      mismatchesDueToFreshnessMovement: null,
      firstMismatch: null,
      firstStableMismatch: null,
      firstMovementMismatch: null,
    };
  }

  const dockIDs = cards.map((card) => card.threadID).filter(Boolean);
  const dockIDSet = new Set(dockIDs);
  const codexOrderSet = new Set(orderScope.threadIDsInCodexOrder);
  const comparableIDs = new Set([...expectedIDs].filter((threadID) => (
    dockIDSet.has(threadID)
      && codexOrderSet.has(threadID)
      && !auditMovement.addedThreadIDs?.has(threadID)
  )));
  const expectedOrderIDs = orderScope.threadIDsInCodexOrder.filter((threadID) => comparableIDs.has(threadID));
  const actualOrderIDs = dockIDs.filter((threadID) => comparableIDs.has(threadID));
  const firstMismatch = firstOrderMismatch(expectedOrderIDs, actualOrderIDs);
  const mismatches = orderMismatchCount(expectedOrderIDs, actualOrderIDs);
  const movement = dockOrderMismatchMovement(
    expectedOrderIDs,
    actualOrderIDs,
    snapshotUpdatedAtByThreadID(orderScope),
    dockCardActivityAtByThreadID(cards),
  );

  if (movement.firstStableMismatch) {
    addFinding(findings, "error", movement.firstStableMismatch.actualThreadID || movement.firstStableMismatch.expectedThreadID, "dock.subscribe", "threadIDOrder", "dock/subscribe order differs from app-server active:allSourceKinds thread/list order", {
      index: movement.firstStableMismatch.index,
      expectedThreadID: movement.firstStableMismatch.expectedThreadID,
      actualThreadID: movement.firstStableMismatch.actualThreadID,
      comparableThreadCount: expectedOrderIDs.length,
      stableMismatches: movement.stableMismatches,
    });
  } else if (movement.firstMovementMismatch) {
    addFinding(findings, "info", movement.firstMovementMismatch.actualThreadID || movement.firstMovementMismatch.expectedThreadID, "dock.subscribe", "threadIDOrder", "dock/subscribe order comparison moved because compared row timestamps changed during the audit", {
      index: movement.firstMovementMismatch.index,
      expectedThreadID: movement.firstMovementMismatch.expectedThreadID,
      actualThreadID: movement.firstMovementMismatch.actualThreadID,
      comparableThreadCount: expectedOrderIDs.length,
      mismatchesDueToFreshnessMovement: movement.movementMismatches,
    });
  }

  return {
    compared: true,
    comparableThreadCount: expectedOrderIDs.length,
    mismatches,
    stableMismatches: movement.stableMismatches,
    mismatchesDueToFreshnessMovement: movement.movementMismatches,
    firstMismatch,
    firstStableMismatch: movement.firstStableMismatch,
    firstMovementMismatch: movement.firstMovementMismatch,
  };
}

function compareDockLiveStatuses(findings, snapshot, cards) {
  if (!snapshot?.loaded || snapshot.loaded.complete === false) {
    return {
      compared: false,
      loadedThreadCount: null,
      loadedDockCardsCompared: null,
      loadedDockStatusMismatches: null,
      staleLiveDockCards: null,
      firstLoadedDockStatusMismatch: null,
    };
  }

  const loadedIDs = new Set(snapshot.loaded.threadIDs || []);
  const entriesByID = new Map((snapshot.threads || []).map((entry) => [entry.threadID, entry]));
  let loadedDockCardsCompared = 0;
  let loadedDockStatusMismatches = 0;
  let staleLiveDockCards = 0;
  let firstLoadedDockStatusMismatch = null;

  for (const card of cards) {
    if (!card?.threadID || !loadedIDs.has(card.threadID)) {
      continue;
    }
    loadedDockCardsCompared += 1;
    const evidence = statusEvidenceForRelayEntry(entriesByID.get(card.threadID));
    const expected = normalizedDockStatusFromThreadStatus(evidence.status);
    const actual = card.status || "unknown";
    if (actual === "dormant" || actual === "unknown") {
      staleLiveDockCards += 1;
    }
    if (expected !== "unknown" && actual !== expected) {
      loadedDockStatusMismatches += 1;
      firstLoadedDockStatusMismatch = firstLoadedDockStatusMismatch || {
        threadID: card.threadID,
        expected,
        actual,
        statusSource: evidence.source,
      };
    }
  }

  if (firstLoadedDockStatusMismatch) {
    addFinding(findings, "error", firstLoadedDockStatusMismatch.threadID, "dock.subscribe", "status", "dock/subscribe status differs from loaded app-server thread status", firstLoadedDockStatusMismatch);
  } else if (staleLiveDockCards > 0) {
    addFinding(findings, "error", null, "dock.subscribe", "status", "dock/subscribe marked loaded app-server cards as dormant or unknown", {
      staleLiveDockCards,
      loadedDockCardsCompared,
    });
  }

  return {
    compared: true,
    loadedThreadCount: loadedIDs.size,
    loadedDockCardsCompared,
    loadedDockStatusMismatches,
    staleLiveDockCards,
    firstLoadedDockStatusMismatch,
  };
}

function compareDockSubscribe(findings, dockSnapshot, sqliteRows, auditMovement = { addedThreadIDs: new Set() }, snapshot = null) {
  if (!dockSnapshot) {
    return {
      included: false,
      cardCount: null,
      expectedActiveListableCount: null,
      expectedWindowCount: null,
      window: null,
      archivedThreadCount: null,
      duplicateCardIDs: null,
      duplicateThreadIDs: null,
      missingActiveListableFromDock: null,
      missingActiveListableFromDockDueToAuditMovement: null,
      extraDockCards: null,
      codexOrderCompared: null,
      codexOrderComparableThreads: null,
      codexOrderMismatches: null,
      codexOrderStableMismatches: null,
      codexOrderMismatchesDueToFreshnessMovement: null,
      codexOrderFirstMismatch: null,
      codexOrderFirstStableMismatch: null,
      codexOrderFirstMovementMismatch: null,
      loadedStatusCompared: null,
      loadedThreadCount: null,
      loadedDockCardsCompared: null,
      loadedDockStatusMismatches: null,
      staleLiveDockCards: null,
      firstLoadedDockStatusMismatch: null,
      lanes: null,
    };
  }

  const cards = Array.isArray(dockSnapshot.cards) ? dockSnapshot.cards : [];
  const window = dockSnapshot.window && typeof dockSnapshot.window === "object"
    ? {
      offset: Number.isFinite(Number(dockSnapshot.window.offset)) ? Number(dockSnapshot.window.offset) : 0,
      limit: Number.isFinite(Number(dockSnapshot.window.limit)) ? Number(dockSnapshot.window.limit) : cards.length,
      rowCount: Number.isFinite(Number(dockSnapshot.window.rowCount)) ? Number(dockSnapshot.window.rowCount) : cards.length,
    }
    : null;
  const sqliteRowsByID = new Map((sqliteRows || []).map((row) => [row.id, row]));
  const dockIDs = cards.map((card) => card.threadID).filter(Boolean);
  const dockIDSet = new Set(dockIDs);
  const duplicateCardIDs = duplicateValues(cards.map((card) => card.id).filter(Boolean));
  const duplicateThreadIDs = duplicateValues(dockIDs);
  for (const id of duplicateCardIDs) {
    addFinding(findings, "error", null, "dock.subscribe", "id", "dock/subscribe returned duplicate card IDs", { id });
  }
  for (const threadID of duplicateThreadIDs) {
    addFinding(findings, "error", threadID, "dock.subscribe", "threadID", "dock/subscribe returned the same thread more than once");
  }

  const dockReachableSourceScopes = ["interactiveDefault", ...EXPLICIT_SOURCE_KINDS];
  const expectedRows = (sqliteRows || []).filter((row) => (
    !sqliteArchived(row)
      && sqliteThreadListableByAppServer(row)
      && expectedSourceScopeNamesForSQLiteThread(row, dockReachableSourceScopes).length > 0
  ));
  const expectedIDs = new Set(expectedRows.map((row) => row.id).filter(Boolean));
  const orderScope = (snapshot?.scopes || []).find((scope) => scope?.name === "active:allSourceKinds");
  const expectedOrderedIDs = Array.isArray(orderScope?.threadIDsInCodexOrder)
    ? orderScope.threadIDsInCodexOrder.filter((threadID) => expectedIDs.has(threadID))
    : expectedRows.map((row) => row.id).filter(Boolean);
  const windowOffset = window?.offset ?? 0;
  const windowRowCount = window?.rowCount ?? expectedOrderedIDs.length;
  const expectedWindowIDs = expectedOrderedIDs.slice(windowOffset, windowOffset + windowRowCount);
  const expectedWindowIDSet = new Set(expectedWindowIDs);
  const allMissing = expectedWindowIDs.filter((threadID) => !dockIDSet.has(threadID)).sort();
  const missingDueToAuditMovement = allMissing.filter((threadID) => auditMovement.addedThreadIDs?.has(threadID));
  const missing = allMissing.filter((threadID) => !auditMovement.addedThreadIDs?.has(threadID));
  const extra = cards.filter((card) => !expectedIDs.has(card.threadID));
  const archived = cards.filter((card) => {
    const row = sqliteRowsByID.get(card.threadID);
    return row && sqliteArchived(row);
  });

  for (const threadID of missing) {
    addFinding(findings, "error", threadID, "dock.subscribe", "threadID", "dock/subscribe returned window is missing an active app-server-listable thread", {
      window,
      sqlite: sanitizeSQLiteThread(sqliteRowsByID.get(threadID)),
    });
  }
  for (const threadID of missingDueToAuditMovement) {
    addFinding(findings, "info", threadID, "dock.subscribe", "threadID", "active app-server-listable thread appeared in SQLite after the dock snapshot window was captured", {
      window,
      sqlite: sanitizeSQLiteThread(sqliteRowsByID.get(threadID)),
    });
  }
  for (const card of archived) {
    addFinding(findings, "error", card.threadID, "dock.subscribe", "archived", "dock/subscribe returned a Codex-archived thread", {
      dock: sanitizeDockThreadCard(card),
      sqlite: sanitizeSQLiteThread(sqliteRowsByID.get(card.threadID)),
    });
  }
  for (const card of extra) {
    addFinding(findings, "warning", card.threadID || null, "dock.subscribe", "threadID", "dock/subscribe returned a card outside the expected active app-server-listable SQLite set", {
      dock: sanitizeDockThreadCard(card),
      sqlite: sanitizeSQLiteThread(sqliteRowsByID.get(card.threadID)),
    });
  }

  const codexOrder = compareDockCodexOrder(findings, snapshot, cards, expectedWindowIDSet, auditMovement);
  const liveStatuses = compareDockLiveStatuses(findings, snapshot, cards);

  return {
    included: true,
    cardCount: cards.length,
    expectedActiveListableCount: expectedIDs.size,
    expectedWindowCount: expectedWindowIDs.length,
    window: window ? {
      ...window,
      totalRows: Number.isFinite(Number(dockSnapshot.totalRows)) ? Number(dockSnapshot.totalRows) : expectedIDs.size,
    } : null,
    archivedThreadCount: archived.length,
    duplicateCardIDs: duplicateCardIDs.length,
    duplicateThreadIDs: duplicateThreadIDs.length,
    missingActiveListableFromDock: missing.length,
    missingActiveListableFromDockDueToAuditMovement: missingDueToAuditMovement.length,
    extraDockCards: extra.length,
    codexOrderCompared: codexOrder.compared,
    codexOrderComparableThreads: codexOrder.comparableThreadCount,
    codexOrderMismatches: codexOrder.mismatches,
    codexOrderStableMismatches: codexOrder.stableMismatches,
    codexOrderMismatchesDueToFreshnessMovement: codexOrder.mismatchesDueToFreshnessMovement,
    codexOrderFirstMismatch: codexOrder.firstMismatch,
    codexOrderFirstStableMismatch: codexOrder.firstStableMismatch,
    codexOrderFirstMovementMismatch: codexOrder.firstMovementMismatch,
    loadedStatusCompared: liveStatuses.compared,
    loadedThreadCount: liveStatuses.loadedThreadCount,
    loadedDockCardsCompared: liveStatuses.loadedDockCardsCompared,
    loadedDockStatusMismatches: liveStatuses.loadedDockStatusMismatches,
    staleLiveDockCards: liveStatuses.staleLiveDockCards,
    firstLoadedDockStatusMismatch: liveStatuses.firstLoadedDockStatusMismatch,
    lanes: laneCountsForThreadCards(cards),
  };
}

function compareRelayReadDetails(findings, context, relayIndex, sqliteRowsByID, rolloutSessionMetaByID) {
  for (const [threadID, entry] of relayIndex.threadsByID.entries()) {
    const sqliteRow = sqliteRowsByID.get(threadID);
    if (!sqliteRow) {
      continue;
    }
    const rolloutMetaResult = rolloutSessionMetaByID.get(threadID);
    const historyThread = entry.historyRead?.thread || null;
    const routedThread = entry.routedRead?.thread || null;
    if (historyThread) {
      compareRelayRowToSQLite(
        findings,
        context,
        threadID,
        historyThread,
        sqliteRow,
        "relay.history_read",
        rolloutMetaResult,
        { compareUpdatedAt: false },
      );
    }
    if (routedThread) {
      compareRelayRowToSQLite(
        findings,
        context,
        threadID,
        routedThread,
        sqliteRow,
        "relay.routed_read",
        rolloutMetaResult,
        { compareUpdatedAt: false },
      );
    }
    compareRelayThreadPair(findings, threadID, "historyRead", historyThread, "routedRead", routedThread);
  }
}

function statusFromSQLiteGoalStatus(value) {
  switch (value) {
    case "usage_limited":
      return "usageLimited";
    case "budget_limited":
      return "budgetLimited";
    default:
      return value || null;
  }
}

function compareGoalTimestamp(findings, threadID, field, relayValue, sqliteMs) {
  const relaySeconds = timestampSeconds(relayValue);
  const sqliteSeconds = timestampSeconds(sqliteMs);
  if (relaySeconds === null || sqliteSeconds === null) {
    return;
  }
  if (Math.abs(relaySeconds - sqliteSeconds) > TIMESTAMP_TOLERANCE_SECONDS) {
    addFinding(findings, "warning", threadID, "relay.thread_goal", field, `relay goal ${field} differs from SQLite goal ${field}`, {
      relay: relaySeconds,
      sqlite: sqliteSeconds,
      deltaSeconds: relaySeconds - sqliteSeconds,
    });
  }
}

function compareRelayGoals(findings, snapshot, goalSummary, sqliteRowsByID) {
  if (!snapshot.threads?.some((entry) => entry.goalRead !== null && entry.goalRead !== undefined)) {
    return {
      included: false,
      relayGoalCount: null,
      sqliteGoalCount: goalSummary.count ?? null,
      sqliteGoalsWithThreadRow: null,
      sqliteGoalsWithoutThreadRow: null,
      missingFromRelay: null,
      missingFromRelayWithThreadRow: null,
      extraInRelay: null,
      goalReadErrors: null,
      appServerDoesNotExposeGoalID: null,
    };
  }

  const sqliteGoalsByThreadID = new Map((goalSummary.rows || []).map((row) => [row.thread_id, row]));
  const relayGoalsByThreadID = new Map();
  let goalReadErrors = 0;
  for (const entry of snapshot.threads || []) {
    const goal = entry.goalRead?.goal || null;
    if (goal) {
      relayGoalsByThreadID.set(entry.threadID, goal);
    }
    if ((entry.errors || []).some((error) => error.source === "history thread/goal/get")) {
      goalReadErrors += 1;
    }
  }

  const relayIDs = new Set(relayGoalsByThreadID.keys());
  const sqliteIDs = new Set(sqliteGoalsByThreadID.keys());
  const missing = [...sqliteIDs].filter((threadID) => !relayIDs.has(threadID)).sort();
  const sqliteGoalsWithoutThreadRow = [...sqliteIDs].filter((threadID) => !sqliteRowsByID.has(threadID)).sort();
  const sqliteGoalsWithThreadRow = [...sqliteIDs].filter((threadID) => sqliteRowsByID.has(threadID)).sort();
  const missingWithThreadRow = missing.filter((threadID) => sqliteRowsByID.has(threadID));
  const missingWithoutThreadRow = missing.filter((threadID) => !sqliteRowsByID.has(threadID));
  const extra = [...relayIDs].filter((threadID) => !sqliteIDs.has(threadID)).sort();

  for (const threadID of missingWithThreadRow) {
    addFinding(findings, "warning", threadID, "relay.thread_goal", "threadID", "SQLite goal is missing from app-server thread/goal/get state", {
      sqlite: sanitizeSQLiteGoal(sqliteGoalsByThreadID.get(threadID)),
    });
  }
  for (const threadID of missingWithoutThreadRow) {
    addFinding(findings, "info", threadID, "codex.storage", "goal.threadID", "SQLite goal row points at a thread ID absent from state_5.sqlite threads", {
      sqlite: sanitizeSQLiteGoal(sqliteGoalsByThreadID.get(threadID)),
    });
  }
  for (const threadID of extra) {
    addFinding(findings, "warning", threadID, "relay.thread_goal", "threadID", "app-server thread/goal/get returned a goal not present in SQLite goal rows", {
      relay: sanitizeRelayGoal(relayGoalsByThreadID.get(threadID)),
    });
  }

  for (const [threadID, relayGoal] of relayGoalsByThreadID.entries()) {
    const sqliteGoal = sqliteGoalsByThreadID.get(threadID);
    if (!sqliteGoal) {
      continue;
    }
    compareExact(findings, "warning", threadID, "relay.thread_goal", "threadID", relayGoal.threadId ?? relayGoal.thread_id, sqliteGoal.thread_id, "relay goal threadID differs from SQLite goal thread_id");
    compareExact(findings, "warning", threadID, "relay.thread_goal", "objective", textFingerprint(relayGoal.objective)?.sha256, textFingerprint(sqliteGoal.objective)?.sha256, "relay goal objective fingerprint differs from SQLite goal objective fingerprint");
    compareExact(findings, "warning", threadID, "relay.thread_goal", "status", relayGoal.status, statusFromSQLiteGoalStatus(sqliteGoal.status), "relay goal status differs from SQLite goal status");
    compareExact(findings, "warning", threadID, "relay.thread_goal", "tokenBudget", relayGoal.tokenBudget ?? relayGoal.token_budget, sqliteGoal.token_budget, "relay goal tokenBudget differs from SQLite goal token_budget");
    compareExact(findings, "warning", threadID, "relay.thread_goal", "tokensUsed", relayGoal.tokensUsed ?? relayGoal.tokens_used, sqliteGoal.tokens_used, "relay goal tokensUsed differs from SQLite goal tokens_used");
    compareExact(findings, "warning", threadID, "relay.thread_goal", "timeUsedSeconds", relayGoal.timeUsedSeconds ?? relayGoal.time_used_seconds, sqliteGoal.time_used_seconds, "relay goal timeUsedSeconds differs from SQLite goal time_used_seconds");
    compareGoalTimestamp(findings, threadID, "createdAt", relayGoal.createdAt ?? relayGoal.created_at, sqliteGoal.created_at_ms);
    compareGoalTimestamp(findings, threadID, "updatedAt", relayGoal.updatedAt ?? relayGoal.updated_at, sqliteGoal.updated_at_ms);
  }

  return {
    included: true,
    relayGoalCount: relayGoalsByThreadID.size,
    sqliteGoalCount: sqliteGoalsByThreadID.size,
    sqliteGoalsWithThreadRow: sqliteGoalsWithThreadRow.length,
    sqliteGoalsWithoutThreadRow: sqliteGoalsWithoutThreadRow.length,
    missingFromRelay: missing.length,
    missingFromRelayWithThreadRow: missingWithThreadRow.length,
    extraInRelay: extra.length,
    goalReadErrors,
    appServerDoesNotExposeGoalID: sqliteGoalsByThreadID.size > 0,
  };
}

function buildBlindSpots(options, snapshot, sqliteAfter, goalSummary, reportSummary) {
  const blindSpots = [];
  if (!options.includeThreadReads) {
    blindSpots.push("This run did not include app-server thread/read or routed thread/read detail for every thread.");
  }
  if (!options.includeLoaded) {
    blindSpots.push("This run did not include thread/loaded/list, so live-vs-not-loaded state was not proven here.");
  }
  if (snapshot.loaded?.complete === false) {
    blindSpots.push("thread/loaded/list was included but incomplete, so loaded/live state is only partial.");
  }
  if (reportSummary.sqliteStableGoalsDuringAudit === false) {
    blindSpots.push("SQLite goal rows changed during the audit, so goal counter/status comparisons are not an atomic point-in-time proof.");
  }
  if ((goalSummary.count || 0) > 0 && !reportSummary.goalParity?.included) {
    blindSpots.push("Codex goals exist in goals_1.sqlite, but this run did not include relay app-server thread/goal/get goal reads.");
  }
  if (reportSummary.goalParity?.included && reportSummary.goalParity?.appServerDoesNotExposeGoalID) {
    blindSpots.push("App-server thread/goal/get exposes goal state but not SQLite goal_id, so goal_id parity is not possible through the app-server.");
  }
  if (reportSummary.goalParity?.included && (reportSummary.goalParity.sqliteGoalsWithoutThreadRow || 0) > 0) {
    blindSpots.push("Some SQLite goal rows point at thread IDs absent from state_5.sqlite threads; app-server exposes goals by known thread ID, not as a standalone goal list.");
  }
  if (reportSummary.goalParity?.included && (
    (reportSummary.goalParity.missingFromRelayWithThreadRow || 0) > 0
      || reportSummary.goalParity.extraInRelay > 0
      || reportSummary.goalParity.goalReadErrors > 0
  )) {
    blindSpots.push("Goal parity was included, but app-server thread/goal/get did not exactly match SQLite goals for current state_5.sqlite thread rows.");
  }
  if ((reportSummary.missingListableFromRelay || 0) > 0) {
    blindSpots.push("At least one stable app-server-listable SQLite thread is missing from relay/state/snapshot thread/list scopes.");
  }
  if ((reportSummary.missingFromRelay || 0) > 0) {
    blindSpots.push("At least one stable SQLite thread is not discoverable through relay/state/snapshot thread/list scopes.");
  }
  if (!options.probeMissingSearches && (reportSummary.missingFromRelay || 0) > 0) {
    blindSpots.push("This run did not include relay thread/search probes for SQLite rows missing from thread/list discovery.");
  }
  if ((reportSummary.searchProbeRows || 0) > 0) {
    blindSpots.push("thread/search is term-bound; it can prove whether known safe terms find a missing thread, but it is not a global thread enumeration surface.");
  }
  if ((reportSummary.missingSearchNotDiscoverable || 0) > 0) {
    blindSpots.push("At least one missing SQLite thread was not found by relay thread/search safe-term probes.");
  }
  if (!reportSummary.dockParity?.included) {
    blindSpots.push("This run did not verify the app-facing dock/subscribe card stream.");
  }
  if (reportSummary.dockParity?.included && (
    reportSummary.dockParity.missingActiveListableFromDock > 0
      || reportSummary.dockParity.archivedThreadCount > 0
      || reportSummary.dockParity.extraDockCards > 0
  )) {
    blindSpots.push("dock/subscribe returned window did not exactly match the active app-server-listable SQLite thread window.");
  }
  if (reportSummary.dockParity?.included && reportSummary.dockParity.codexOrderCompared === false) {
    blindSpots.push("dock/subscribe order was not compared against app-server active:allSourceKinds thread/list order.");
  }
  if (reportSummary.dockParity?.included && (reportSummary.dockParity.codexOrderStableMismatches || 0) > 0) {
    blindSpots.push("dock/subscribe returned the right active card set, but not in the same order as app-server active:allSourceKinds thread/list.");
  }
  if (reportSummary.dockParity?.included && (reportSummary.dockParity.codexOrderMismatchesDueToFreshnessMovement || 0) > 0) {
    blindSpots.push("dock/subscribe order comparison saw app-server row timestamp movement during the audit; stable order mismatches are counted separately.");
  }
  if (reportSummary.dockParity?.included && reportSummary.dockParity.loadedStatusCompared === false) {
    blindSpots.push("dock/subscribe live status was not compared against thread/loaded/list.");
  }
  if (reportSummary.dockParity?.included && (reportSummary.dockParity.loadedDockStatusMismatches || 0) > 0) {
    blindSpots.push("dock/subscribe returned a status that disagreed with loaded app-server thread status.");
  }
  if (reportSummary.dockParity?.included && (reportSummary.dockParity.staleLiveDockCards || 0) > 0) {
    blindSpots.push("dock/subscribe marked at least one loaded app-server card as dormant or unknown.");
  }
  if (!reportSummary.turnParity?.included) {
    blindSpots.push("This run did not verify thread/turns/list order or completeness.");
  }
  if (reportSummary.turnParity?.included && reportSummary.turnParity.requestedItemsView !== "full") {
    blindSpots.push("Prompt-start and output-schema evidence require full thread/turns/list items; this run did not request itemsView=full.");
  }
  if (reportSummary.turnParity?.included && reportSummary.turnParity.requestedItemsView === "full") {
    blindSpots.push("App-server historical responses do not expose thread/start sessionStartSource; prompt-start shape can only be inferred from returned userMessage items.");
  }
  if (
    reportSummary.turnParity?.included
      && reportSummary.turnParity.requestedItemsView === "full"
      && reportSummary.turnParity.outputSchemaEvidence?.historicalStateObserved === false
  ) {
    blindSpots.push("Full thread/turns/list items exposed no output-schema field-name evidence; current app-server history surfaces do not identify historical JSON/output-schema turns.");
  }
  if (reportSummary.turnParity?.included && (
    (reportSummary.turnParity.incompleteThreads || 0) > 0
      || (reportSummary.turnParity.duplicateTurnIDThreads || 0) > 0
      || (reportSummary.turnParity.ordinalMismatches || 0) > 0
  )) {
    blindSpots.push("thread/turns/list was included, but turn coverage or returned order was incomplete.");
  }
  if (!reportSummary.spawnParity?.included) {
    blindSpots.push("Spawn parent/child parity was not included because SQLite thread_spawn_edges could not be read.");
  }
  if (reportSummary.spawnParity?.included && (
    (reportSummary.spawnParity.parentMismatches || 0) > 0
      || (reportSummary.spawnParity.relaySourceParentsWithoutEdge || 0) > 0
      || (reportSummary.spawnParity.storageSourceParentMismatches || 0) > 0
  )) {
    blindSpots.push("Spawn parent/child parity found relationship disagreements between relay source metadata and SQLite thread_spawn_edges.");
  }
  if (reportSummary.appServerNotListable > 0) {
    blindSpots.push("Some SQLite threads are outside the app-server thread/list enumeration contract.");
  }
  if (!reportSummary.sqliteStableIDsDuringAudit) {
    blindSpots.push("SQLite thread IDs changed during the audit, so this was not an atomic point-in-time comparison.");
  }
  if ((reportSummary.storageDisagreements || 0) > 0) {
    blindSpots.push("Some SQLite metadata differs from rollout session_meta; those are storage disagreements that still need a Codex meaning decision.");
  }
  if (reportSummary.relayCanonicalProjection?.included && (reportSummary.relayCanonicalProjection.missingProjectionThreads || 0) > 0) {
    blindSpots.push("Some app-server thread surfaces were compared without a relay canonical projection.");
  }
  if ((reportSummary.listRowInconsistencies || 0) > 0) {
    if (reportSummary.relayCanonicalProjection?.included) {
      blindSpots.push("Some app-server thread/list scopes return different metadata for the same thread; the relay canonical projection records the winning app-server surface for each compared field.");
    } else {
      blindSpots.push("Some app-server thread/list scopes return different metadata for the same thread; relay clients need canonical detail from thread/read or an explicit conflict state.");
    }
  }
  if ((reportSummary.readDetailDisagreements || 0) > 0) {
    blindSpots.push("Some app-server thread/read details still disagree with rollout session_meta, SQLite, or each other.");
  }
  if ((sqliteAfter.rows || []).some((row) => expectedSourceScopeNamesForSQLiteThread(row, ["interactiveDefault", ...EXPLICIT_SOURCE_KINDS]).length === 0)) {
    blindSpots.push("Some SQLite source values do not map to any current app-server source scope.");
  }
  return blindSpots;
}

function summarizeCompletionBoundary(reportSummary) {
  const appServerChecks = {
    relaySnapshotComplete: reportSummary.relayComplete === true,
    appServerListableThreadsOneToOne:
      reportSummary.sqliteStableIDsDuringAudit === true
      && reportSummary.missingListableFromRelay === 0
      && reportSummary.extraInRelay === 0,
    dockActiveRowsExact:
      reportSummary.dockParity?.included === true
      && reportSummary.dockParity.archivedThreadCount === 0
      && reportSummary.dockParity.duplicateCardIDs === 0
      && reportSummary.dockParity.duplicateThreadIDs === 0
      && reportSummary.dockParity.missingActiveListableFromDock === 0
      && reportSummary.dockParity.extraDockCards === 0,
    dockOrderExact:
      reportSummary.dockParity?.included === true
      && reportSummary.dockParity.codexOrderCompared === true
      && reportSummary.dockParity.codexOrderStableMismatches === 0,
    dockLoadedStatusExact:
      reportSummary.dockParity?.included === true
      && reportSummary.dockParity.loadedStatusCompared === true
      && reportSummary.dockParity.loadedDockStatusMismatches === 0
      && reportSummary.dockParity.staleLiveDockCards === 0,
    canonicalAppServerProjectionComplete:
      reportSummary.relayCanonicalProjection?.included === true
      && reportSummary.relayCanonicalProjection.missingProjectionThreads === 0,
    turnHistoryComplete:
      reportSummary.turnParity?.included === true
      && reportSummary.turnParity.requestedItemsView === "full"
      && reportSummary.turnParity.incompleteThreads === 0
      && reportSummary.turnParity.duplicateTurnIDThreads === 0
      && reportSummary.turnParity.ordinalMismatches === 0,
    currentThreadGoalsExact:
      reportSummary.goalParity?.included === true
      && reportSummary.goalParity.missingFromRelayWithThreadRow === 0
      && reportSummary.goalParity.extraInRelay === 0
      && reportSummary.goalParity.goalReadErrors === 0,
    spawnEdgesExact:
      reportSummary.spawnParity?.included === true
      && reportSummary.spawnParity.missingRelayChildForSpawnEdge === 0
      && reportSummary.spawnParity.parentMismatches === 0
      && reportSummary.spawnParity.relaySourceParentsWithoutEdge === 0
      && reportSummary.spawnParity.storageSourceParentMismatches === 0,
  };
  const failedAppServerChecks = Object.entries(appServerChecks)
    .filter(([, passed]) => !passed)
    .map(([name]) => name);
  const outsideAppServerSupport = [
    "global enumeration of previewless direct-readable threads",
    "SQLite goal_id through thread/goal/get",
    "standalone enumeration of orphan goal rows",
    "one shared transaction/snapshot ID across thread/list, thread/read, thread/turns/list, and thread/goal/get",
    "historical thread/start.sessionStartSource",
    "historical turn/start.output_schema",
    "thread/turns/items/list until Codex stops returning method_not_found",
  ];
  const movingState = [];
  if (reportSummary.sqliteStableGoalsDuringAudit === false) {
    movingState.push("SQLite goal rows changed during this audit; app-server provides no shared snapshot ID to make cross-surface goal proof atomic.");
  }
  if (reportSummary.sqliteStableIDsDuringAudit === false) {
    movingState.push("SQLite thread IDs changed during this audit.");
  }

  return {
    appServerExposedParityComplete: failedAppServerChecks.length === 0,
    appServerChecks,
    failedAppServerChecks,
    movingState,
    outsideAppServerSupport,
    storageMeaningConflicts: {
      storageDisagreements: reportSummary.storageDisagreements || 0,
      listRowInconsistencies: reportSummary.listRowInconsistencies || 0,
      readDetailDisagreements: reportSummary.readDetailDisagreements || 0,
    },
  };
}

async function requestRelayStateSnapshot(options) {
  const client = new JsonRpcWebSocketClient(options.relayUrl, {
    requestTimeoutMs: options.requestTimeoutMs,
  });
  await initializeClient(client);
  try {
    return await client.request("relay/state/snapshot", {
      includeArchived: true,
      includeThreadReads: options.includeThreadReads,
      includeTurns: options.includeTurns,
      turnSortDirection: options.turnSortDirection,
      turnItemsView: options.turnItemsView,
      includeLoaded: options.includeLoaded,
      includeGoals: options.includeGoals,
      limit: options.limit,
    });
  } finally {
    await client.close();
  }
}

async function requestDockSubscribeSnapshot(options) {
  if (!options.includeDockSubscribe) {
    return null;
  }
  const client = new JsonRpcWebSocketClient(options.relayUrl, {
    requestTimeoutMs: options.requestTimeoutMs,
  });
  await initializeClient(client);
  try {
    return await client.request("dock/subscribe", {});
  } finally {
    await client.close();
  }
}

async function probeMissingDirectReads(options, missingRows) {
  if (!options.probeMissingDirectReads || missingRows.length === 0) {
    return [];
  }
  const client = new JsonRpcWebSocketClient(options.relayUrl, {
    requestTimeoutMs: options.requestTimeoutMs,
  });
  await initializeClient(client);
  const probes = [];
  try {
    for (const row of missingRows.slice(0, options.missingReadProbeLimit)) {
      try {
        const response = await client.request("thread/read", {
          threadId: row.id,
          includeTurns: false,
        });
        probes.push({
          threadID: row.id,
          ok: true,
          thread: sanitizeRelayThread(response?.thread),
        });
      } catch (error) {
        probes.push({
          threadID: row.id,
          ok: false,
          error: error?.message || String(error),
        });
      }
    }
  } finally {
    await client.close();
  }
  return probes;
}

function searchProbeSourceScopes() {
  return [
    {
      name: "interactiveDefault",
      sourceKinds: null,
    },
    {
      name: ALL_SOURCE_KINDS_SCOPE,
      sourceKinds: [...EXPLICIT_SOURCE_KINDS],
    },
  ];
}

async function probeMissingThreadSearches(options, missingRows) {
  if (!options.probeMissingSearches || missingRows.length === 0) {
    return [];
  }
  const client = new JsonRpcWebSocketClient(options.relayUrl, {
    requestTimeoutMs: options.requestTimeoutMs,
  });
  await initializeClient(client);
  const probes = [];
  try {
    for (const row of missingRows.slice(0, options.missingReadProbeLimit)) {
      for (const term of missingSearchTermsForSQLiteRow(row)) {
        for (const scope of searchProbeSourceScopes()) {
          try {
            const resultThreadIDs = [];
            const seenCursors = new Set();
            let cursor = null;
            let complete = true;
            let pageCount = 0;
            while (true) {
              const request = {
                archived: sqliteArchived(row),
                limit: options.limit,
                searchTerm: term.value,
                sortKey: "updated_at",
                sortDirection: "desc",
              };
              if (cursor) {
                request.cursor = cursor;
              }
              if (Array.isArray(scope.sourceKinds)) {
                request.sourceKinds = scope.sourceKinds;
              }
              const response = await client.request("thread/search", request);
              pageCount += 1;
              const pageThreadIDs = (Array.isArray(response?.data) ? response.data : [])
                .map((result) => result?.thread?.id || result?.id || null)
                .filter(Boolean);
              resultThreadIDs.push(...pageThreadIDs);
              const nextCursor = response?.nextCursor || null;
              if (!nextCursor) {
                break;
              }
              if (seenCursors.has(nextCursor)) {
                complete = false;
                break;
              }
              seenCursors.add(nextCursor);
              cursor = nextCursor;
            }
            probes.push({
              threadID: row.id,
              sourceScope: scope.name,
              searchTermKind: term.kind,
              searchTerm: term.fingerprint,
              ok: true,
              complete,
              pageCount,
              resultCount: resultThreadIDs.length,
              resultThreadIDs,
              includesMissing: resultThreadIDs.includes(row.id),
            });
          } catch (error) {
            probes.push({
              threadID: row.id,
              sourceScope: scope.name,
              searchTermKind: term.kind,
              searchTerm: term.fingerprint,
              ok: false,
              complete: false,
              pageCount: null,
              resultCount: null,
              resultThreadIDs: [],
              includesMissing: false,
              error: error?.message || String(error),
            });
          }
        }
      }
    }
  } finally {
    await client.close();
  }
  return probes;
}

function compareRelaySnapshotToSQLite(snapshot, sqliteBefore, sqliteAfter, goalSummary, directReadProbes, options, rolloutSessionMetaByID = new Map(), spawnEdges = { ok: true, rows: [] }, dockSnapshot = null, searchProbes = []) {
  const relayIndex = indexRelaySnapshot(snapshot);
  const findings = [...relayIndex.findings];
  const threadIDChanges = sqliteThreadIDChanges(sqliteBefore, sqliteAfter);
  const comparisonContext = {
    storageDisagreementKeys: new Set(),
  };

  if (!snapshot.complete) {
    addFinding(findings, "error", null, "relay.state_snapshot", "complete", "relay/state/snapshot reported incomplete state", {
      complete: false,
    });
  }
  for (const scope of snapshot.scopes || []) {
    if (!scope.complete) {
      addFinding(findings, "error", null, scope.name, "complete", "relay scope reported incomplete state", {
        error: scope.error || null,
      });
    }
  }

  const sqliteRows = sqliteAfter.rows || [];
  const sqliteRowsByID = new Map(sqliteRows.map((row) => [row.id, row]));
  const sqliteIDs = new Set(sqliteRowsByID.keys());
  const relayIDs = new Set(relayIndex.threadsByID.keys());
  const missingRows = sqliteRows.filter((row) => !relayIDs.has(row.id));
  const missingRowsDueToAuditMovement = missingRows.filter((row) => threadIDChanges.addedSet.has(row.id));
  const stableMissingRows = missingRows.filter((row) => !threadIDChanges.addedSet.has(row.id));
  const missingListableRows = stableMissingRows.filter(sqliteThreadListableByAppServer);
  const missingListableRowsDueToAuditMovement = missingRowsDueToAuditMovement.filter(sqliteThreadListableByAppServer);
  const missingNotListableRows = stableMissingRows.filter((row) => !sqliteThreadListableByAppServer(row));
  const appServerNotListableRows = sqliteRows.filter((row) => !sqliteThreadListableByAppServer(row));
  const allExtraThreadIDs = [...relayIDs].filter((threadID) => !sqliteIDs.has(threadID)).sort();
  const extraThreadIDsDueToAuditMovement = allExtraThreadIDs.filter((threadID) => threadIDChanges.removedSet.has(threadID));
  const extraThreadIDs = allExtraThreadIDs.filter((threadID) => !threadIDChanges.removedSet.has(threadID));

  for (const row of missingListableRows) {
    addFinding(findings, "error", row.id, "relay.state_snapshot", "thread_id", "SQLite thread is missing from the relay app-server snapshot", {
      sqlite: sanitizeSQLiteThread(row),
    });
  }
  for (const row of missingNotListableRows) {
    addFinding(findings, "info", row.id, "app_server.thread_list", "thread_id", "SQLite thread is outside the app-server thread/list enumeration contract", {
      sqlite: sanitizeSQLiteThread(row),
    });
  }
  for (const row of missingListableRowsDueToAuditMovement) {
    addFinding(findings, "info", row.id, "relay.state_snapshot", "thread_id", "SQLite thread appeared after the relay app-server snapshot was captured", {
      sqlite: sanitizeSQLiteThread(row),
    });
  }
  for (const threadID of extraThreadIDs) {
    const relayEntry = relayIndex.threadsByID.get(threadID);
    addFinding(findings, "error", threadID, "relay.state_snapshot", "thread_id", "relay app-server snapshot contains a thread not present in SQLite threads", {
      appearances: (relayEntry?.appearances || []).map((appearance) => sanitizeRelayAppearance(appearance)),
    });
  }
  for (const threadID of extraThreadIDsDueToAuditMovement) {
    const relayEntry = relayIndex.threadsByID.get(threadID);
    addFinding(findings, "info", threadID, "relay.state_snapshot", "thread_id", "SQLite thread disappeared after the relay app-server snapshot was captured", {
      appearances: (relayEntry?.appearances || []).map((appearance) => sanitizeRelayAppearance(appearance)),
    });
  }

  for (const row of sqliteRows) {
    const relayRows = relayIndex.listRowsByID.get(row.id) || [];
    if (relayRows.length === 0) {
      continue;
    }
    compareScopeMembership(findings, snapshot, row, relayRows);
    for (const relayRow of relayRows) {
      const actualArchived = Boolean(relayRow.archived);
      if (actualArchived !== sqliteArchived(row)) {
        addFinding(findings, "error", row.id, relayRow.scope, "archived", "relay scope archive state differs from SQLite archived flag", {
          relay: actualArchived,
          sqlite: sqliteArchived(row),
        });
      }
      compareRelayRowToSQLite(
        findings,
        comparisonContext,
        row.id,
        relayRow.thread,
        row,
        relayRow.scope,
        rolloutSessionMetaByID.get(row.id),
      );
    }
  }

  compareLoadedConsistency(findings, snapshot, relayIndex);
  compareRelayListRowConsistency(findings, relayIndex.listRowsByID);
  compareRelayReadDetails(findings, comparisonContext, relayIndex, sqliteRowsByID, rolloutSessionMetaByID);
  const goalParity = compareRelayGoals(findings, snapshot, goalSummary, sqliteRowsByID);
  const spawnParity = compareSpawnEdges(findings, snapshot, relayIndex.listRowsByID, sqliteRowsByID, spawnEdges);
  const dockParity = compareDockSubscribe(findings, dockSnapshot, sqliteRows, {
    addedThreadIDs: threadIDChanges.addedSet,
  }, snapshot);
  const turnParity = compareRelayTurnCoverage(findings, snapshot);
  const appServerSurfaceConflicts = summarizeSurfaceConflicts(snapshot);
  const relayCanonicalProjection = summarizeCanonicalProjection(snapshot);

  for (const probe of directReadProbes) {
    const sqliteRow = sqliteRowsByID.get(probe.threadID);
    const listable = sqliteRow ? sqliteThreadListableByAppServer(sqliteRow) : true;
    const addedDuringAudit = threadIDChanges.addedSet.has(probe.threadID);
    if (probe.ok) {
      addFinding(findings, addedDuringAudit ? "info" : (listable ? "warning" : "info"), probe.threadID, "relay.thread_read", "discoverability", addedDuringAudit
        ? "thread is directly readable by ID, but appeared after the relay app-server snapshot was captured"
        : (listable
          ? "missing SQLite thread is directly readable by ID but absent from relay thread/list discovery"
          : "thread is directly readable by ID, but app-server thread/list does not enumerate this SQLite row"), {
        directRead: probe.thread,
      });
    } else {
      addFinding(findings, addedDuringAudit ? "warning" : (listable ? "error" : "warning"), probe.threadID, "relay.thread_read", "discoverability", addedDuringAudit
        ? "thread appeared after the relay app-server snapshot was captured and direct thread/read failed"
        : (listable
          ? "missing SQLite thread is absent from relay thread/list discovery and direct thread/read failed"
          : "thread is outside app-server thread/list enumeration and direct thread/read failed"), {
        error: probe.error,
      });
    }
  }

  const searchProbesByThreadID = new Map();
  for (const probe of searchProbes || []) {
    if (!probe?.threadID) {
      continue;
    }
    if (!searchProbesByThreadID.has(probe.threadID)) {
      searchProbesByThreadID.set(probe.threadID, []);
    }
    searchProbesByThreadID.get(probe.threadID).push(probe);
  }
  for (const [threadID, probes] of searchProbesByThreadID.entries()) {
    const sqliteRow = sqliteRowsByID.get(threadID);
    const listable = sqliteRow ? sqliteThreadListableByAppServer(sqliteRow) : true;
    const addedDuringAudit = threadIDChanges.addedSet.has(threadID);
    const sanitizedProbes = probes.map(sanitizeSearchProbe);
    const successful = probes.some((probe) => probe.ok);
    const complete = probes.every((probe) => probe.ok && probe.complete !== false);
    const includesMissing = probes.some((probe) => probe.ok && probe.includesMissing);
    if (includesMissing) {
      addFinding(findings, addedDuringAudit ? "info" : (listable ? "warning" : "info"), threadID, "relay.thread_search", "discoverability", addedDuringAudit
        ? "thread appeared after the relay app-server snapshot was captured but is discoverable by thread/search"
        : (listable
          ? "missing SQLite thread is discoverable by thread/search but absent from relay thread/list discovery"
          : "thread is outside app-server thread/list enumeration but is discoverable by thread/search with a known safe term"), {
        probes: sanitizedProbes,
      });
    } else if (successful) {
      addFinding(findings, "info", threadID, "relay.thread_search", "discoverability", complete
        ? "missing SQLite thread was not found by relay thread/search safe-term probes"
        : "missing SQLite thread was not found by relay thread/search safe-term probes before search pagination became incomplete", {
        probes: sanitizedProbes,
      });
    } else {
      addFinding(findings, listable && !addedDuringAudit ? "warning" : "info", threadID, "relay.thread_search", "discoverability", "relay thread/search probes failed for missing SQLite thread", {
        probes: sanitizedProbes,
      });
    }
  }

  const severityCounts = findings.reduce((counts, finding) => {
    counts[finding.severity] = (counts[finding.severity] || 0) + 1;
    return counts;
  }, {});
  const listRowInconsistencies = findings.filter((finding) => finding.surface === "relay.list_rows").length;
  const readDetailDisagreements = findings.filter((finding) => (
    finding.surface === "relay.history_read"
      || finding.surface === "relay.routed_read"
      || finding.surface === "relay.thread_read_pair"
  )).length;
  const storageDisagreementAlignment = summarizeStorageDisagreementAlignment(findings);
  const listRowInconsistencyFields = summarizeFieldsForFindings(
    findings,
    (finding) => finding.surface === "relay.list_rows",
  );
  const readDetailDisagreementFields = summarizeFieldsForFindings(
    findings,
    (finding) => finding.surface === "relay.history_read"
      || finding.surface === "relay.routed_read"
      || finding.surface === "relay.thread_read_pair",
  );
  const summary = {
    ok: (severityCounts.error || 0) === 0 && (severityCounts.warning || 0) === 0,
    relayComplete: Boolean(snapshot.complete),
    relayThreadCount: relayIDs.size,
    sqliteThreadCount: sqliteIDs.size,
    sqliteAppServerListableThreadCount: sqliteRows.length - appServerNotListableRows.length,
    appServerNotListable: appServerNotListableRows.length,
    missingFromRelay: stableMissingRows.length,
    missingFromRelayDueToAuditMovement: missingRowsDueToAuditMovement.length,
    missingListableFromRelay: missingListableRows.length,
    missingListableFromRelayDueToAuditMovement: missingListableRowsDueToAuditMovement.length,
    extraInRelay: extraThreadIDs.length,
    extraInRelayDueToAuditMovement: extraThreadIDsDueToAuditMovement.length,
    sqliteStableIDsDuringAudit: threadIDChanges.stable,
    sqliteThreadRowsAddedDuringAudit: threadIDChanges.added.length,
    sqliteThreadRowsRemovedDuringAudit: threadIDChanges.removed.length,
    directReadProbes: directReadProbes.length,
    searchProbeAttempts: (searchProbes || []).length,
    searchProbeRows: searchProbesByThreadID.size,
    missingSearchDiscoverable: [...searchProbesByThreadID.entries()].filter(([, probes]) => probes.some((probe) => probe.ok && probe.includesMissing)).length,
    missingSearchNotDiscoverable: [...searchProbesByThreadID.entries()].filter(([, probes]) => !probes.some((probe) => probe.ok && probe.includesMissing)).length,
    missingListableSearchDiscoverable: [...searchProbesByThreadID.entries()].filter(([threadID, probes]) => (
      sqliteThreadListableByAppServer(sqliteRowsByID.get(threadID))
        && probes.some((probe) => probe.ok && probe.includesMissing)
    )).length,
    storageDisagreements: comparisonContext.storageDisagreementKeys.size,
    storageDisagreementAlignment,
    listRowInconsistencies,
    listRowInconsistencyFields,
    readDetailDisagreements,
    readDetailDisagreementFields,
    appServerSurfaceConflicts,
    relayCanonicalProjection,
    turnParity,
    goalParity,
    spawnParity,
    dockParity,
    findings: findings.length,
    errors: severityCounts.error || 0,
    warnings: severityCounts.warning || 0,
    info: severityCounts.info || 0,
  };

  return {
    summary,
    findings,
    missingThreads: missingRows.map((row) => ({
      ...sanitizeSQLiteThread(row),
      auditMovement: threadIDChanges.addedSet.has(row.id) ? "addedDuringAudit" : "stable",
    })),
    extraThreadIDs: allExtraThreadIDs,
  };
}

async function buildReport(options) {
  const sqliteBefore = readSQLiteThreads(options.sqliteHome);
  const goalSummaryBefore = readGoalSummary(options.sqliteHome);
  const snapshot = await requestRelayStateSnapshot(options);
  const dockSnapshot = await requestDockSubscribeSnapshot(options);
  const sqliteAfter = readSQLiteThreads(options.sqliteHome);
  const goalSummaryAfter = readGoalSummary(options.sqliteHome);
  const spawnEdgesAfter = readSQLiteSpawnEdges(options.sqliteHome);

  if (!sqliteBefore.ok) {
    throw new Error(`failed to read SQLite before snapshot: ${sqliteBefore.error}`);
  }
  if (!sqliteAfter.ok) {
    throw new Error(`failed to read SQLite after snapshot: ${sqliteAfter.error}`);
  }
  const rolloutSessionMeta = readRolloutSessionMetas(sqliteAfter.rows || []);

  const preliminaryRelayIDs = new Set((snapshot.threads || []).map((entry) => entry.threadID).filter(Boolean));
  const missingRows = (sqliteAfter.rows || []).filter((row) => !preliminaryRelayIDs.has(row.id));
  const directReadProbes = await probeMissingDirectReads(options, missingRows);
  const searchProbes = await probeMissingThreadSearches(options, missingRows);
  const comparison = compareRelaySnapshotToSQLite(
    snapshot,
    sqliteBefore,
    sqliteAfter,
    goalSummaryAfter,
    directReadProbes,
    options,
    rolloutSessionMeta.byThreadID,
    spawnEdgesAfter,
    dockSnapshot,
    searchProbes,
  );

  const goalChanges = goalRowsChangeCounts(goalSummaryBefore, goalSummaryAfter);
  const reportSummary = {
    ...comparison.summary,
    sqliteStableGoalsDuringAudit: goalChanges.stable,
    sqliteGoalRowsChangedDuringAudit: goalChanges.changed,
    sqliteGoalRowsAddedDuringAudit: goalChanges.added,
    sqliteGoalRowsRemovedDuringAudit: goalChanges.removed,
  };
  reportSummary.completionBoundary = summarizeCompletionBoundary(reportSummary);
  const report = {
    ok: reportSummary.ok,
    generatedAt: new Date().toISOString(),
    config: {
      relayUrl: sanitizeURLForReport(options.relayUrl),
      codexHome: options.codexHome,
      sqliteHome: options.sqliteHome,
      stateDbPath: sqliteAfter.dbPath,
      goalsDbPath: goalSummaryAfter.dbPath,
      limit: options.limit,
      includeThreadReads: options.includeThreadReads,
      includeLoaded: options.includeLoaded,
      includeGoals: options.includeGoals,
      includeTurns: options.includeTurns,
      exhaustive: options.exhaustive,
      turnSortDirection: options.turnSortDirection,
      turnItemsView: options.turnItemsView,
      requestTimeoutMs: options.requestTimeoutMs,
      includeDockSubscribe: options.includeDockSubscribe,
      probeMissingDirectReads: options.probeMissingDirectReads,
      probeMissingSearches: options.probeMissingSearches,
      missingReadProbeLimit: options.missingReadProbeLimit,
    },
    relay: summarizeRelaySnapshot(snapshot),
    dock: dockSnapshot ? {
      kind: dockSnapshot.kind || null,
      schemaVersion: dockSnapshot.schemaVersion ?? null,
      view: dockSnapshot.view || null,
      complete: dockSnapshot.complete ?? null,
      totalRows: dockSnapshot.totalRows ?? null,
      window: dockSnapshot.window || null,
      cardCount: Array.isArray(dockSnapshot.cards) ? dockSnapshot.cards.length : null,
      lanes: laneCountsForThreadCards(dockSnapshot.cards || []),
      freshness: dockSnapshot.freshness || null,
    } : null,
    sqlite: {
      before: summarizeSQLiteRows(sqliteBefore.rows),
      after: summarizeSQLiteRows(sqliteAfter.rows),
      selectedColumns: sqliteAfter.selectedColumns || [],
      goals: {
        available: goalSummaryAfter.ok,
        count: goalSummaryAfter.count,
        beforeCount: goalSummaryBefore.count,
        afterCount: goalSummaryAfter.count,
        stableDuringAudit: reportSummary.sqliteStableGoalsDuringAudit,
        changedDuringAudit: goalChanges.changed,
        addedDuringAudit: goalChanges.added,
        removedDuringAudit: goalChanges.removed,
        error: goalSummaryAfter.error || null,
      },
      spawnEdges: {
        available: spawnEdgesAfter.ok,
        count: spawnEdgesAfter.ok ? (spawnEdgesAfter.rows || []).length : null,
        error: spawnEdgesAfter.error || null,
      },
    },
    disk: {
      rolloutSessionMeta: summarizeRolloutSessionMetas(rolloutSessionMeta),
    },
    summary: reportSummary,
    blindSpots: buildBlindSpots(options, snapshot, sqliteAfter, goalSummaryAfter, reportSummary),
    missingThreads: comparison.missingThreads,
    extraThreadIDs: comparison.extraThreadIDs,
    directReadProbes,
    searchProbes: searchProbes.map(sanitizeSearchProbe),
    findings: comparison.findings,
  };
  return report;
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    console.log(usage());
    return;
  }
  const report = await buildReport(options);
  if (options.jsonOut) {
    fs.mkdirSync(path.dirname(options.jsonOut), { recursive: true });
    fs.writeFileSync(options.jsonOut, `${JSON.stringify(report, null, 2)}\n`, "utf8");
  }
  const stdoutReport = options.summaryOnly ? {
    ok: report.ok,
    generatedAt: report.generatedAt,
    reportPath: options.jsonOut || null,
    relayUrl: report.config.relayUrl,
    relay: {
      complete: report.relay.complete,
      threadCount: report.relay.threadCount,
      scopeCount: report.relay.scopeCount,
      nonEmptyScopes: report.relay.scopes.filter((scope) => scope.rowCount > 0),
    },
    sqlite: report.sqlite.after,
    disk: report.disk,
    goals: report.sqlite.goals,
    summary: report.summary,
    blindSpots: report.blindSpots,
    missingThreads: report.missingThreads,
    directReadProbes: report.directReadProbes,
    searchProbes: report.searchProbes,
  } : report;
  process.stdout.write(`${JSON.stringify(stdoutReport, null, 2)}\n`);
  const warningOrErrorCount = report.summary.errors + report.summary.warnings;
  if (options.failOnDiff && warningOrErrorCount > 0) {
    process.exitCode = 1;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.error(`relay-state-parity failed: ${error.message || error}`);
    process.exit(1);
  });
}

export {
  buildReport,
  compareRelaySnapshotToSQLite,
  expectedScopeNamesForSQLiteThread,
  expectedSourceScopeNamesForSQLiteThread,
  goalRowsChangeCounts,
  parseArgs,
  readSQLiteSpawnEdges,
  readSQLiteThreads,
  sanitizeRelayThread,
  sanitizeSQLiteThread,
  threadSpawnParentIDFromSource,
};

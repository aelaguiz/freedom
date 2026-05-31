#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

import {
  DEFAULT_RELAY_WS,
  RELAY_STATE_TEXT_FIELD_MAX_CHARS,
  RELAY_STATE_TITLE_MAX_CHARS,
  THREAD_LIST_MAX_LIMIT,
} from "./dock-relay-constants.mjs";
import { JsonRpcWebSocketClient } from "./dock-relay-json-rpc-client.mjs";
import { initializeClient } from "./dock-relay-thread-data.mjs";

const DEFAULT_LIMIT = 50;
const TIMESTAMP_TOLERANCE_SECONDS = 2;

const AGENT_SOURCE_KINDS = Object.freeze([
  "exec",
  "appServer",
  "subAgentReview",
  "subAgentCompact",
  "subAgentThreadSpawn",
  "subAgentOther",
  "unknown",
]);

function nonEmpty(value) {
  if (typeof value !== "string") {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function boundedText(value, maxChars) {
  const text = nonEmpty(value);
  if (!text) {
    return null;
  }
  return text.length > maxChars ? text.slice(0, maxChars) : text;
}

function firstBoundedText(values, maxChars) {
  for (const value of values) {
    const text = boundedText(value, maxChars);
    if (text) {
      return text;
    }
  }
  return null;
}

function normalizeString(value) {
  return String(value || "").trim();
}

function normalizeSourceName(value) {
  return normalizeString(value).toLowerCase();
}

function canonicalSourceName(value) {
  return normalizeSourceName(value).replace(/[^a-z0-9]/g, "");
}

function sha256Short(value) {
  return crypto.createHash("sha256").update(String(value)).digest("hex").slice(0, 12);
}

function textFingerprint(value) {
  if (typeof value !== "string") {
    return { present: false };
  }
  if (value.trim().length === 0) {
    return { present: false, chars: value.length, bytes: Buffer.byteLength(value, "utf8") };
  }
  return {
    present: true,
    chars: [...value].length,
    bytes: Buffer.byteLength(value, "utf8"),
    sha256: sha256Short(value),
  };
}

function fingerprintsMatch(lhs, rhs) {
  const left = textFingerprint(lhs);
  const right = textFingerprint(rhs);
  if (!left.present && !right.present) {
    return true;
  }
  return left.present === right.present
    && left.bytes === right.bytes
    && left.sha256 === right.sha256;
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

function splitThreadIDs(value) {
  return String(value || "")
    .split(",")
    .map((piece) => piece.trim())
    .filter(Boolean)
    .map((piece) => (piece.includes("::") ? piece.split("::").at(-1) : piece));
}

function usage() {
  return [
    "Usage: node scripts/dock-relay-thread-fidelity.mjs [options]",
    "",
    "Options:",
    "  --relay-url <ws-url>       Relay WebSocket URL. Defaults to CODEX_DOCK_RELAY_WS or ws://127.0.0.1:4510.",
    "  --codex-home <path>        Codex home. Defaults to CODEX_HOME or ~/.codex.",
    "  --sqlite-home <path>       SQLite home. Defaults to CODEX_SQLITE_HOME or codex home.",
    "  --limit <n>                Relay page size, capped at 250. Defaults to 50.",
    "  --max-threads <n>          Maximum collected threads to cross-check. Defaults to --limit.",
    "  --thread-id <id[,id]>      Only check specific thread IDs. May be repeated.",
    "  --include-archived         Also collect archived relay thread/list rows.",
    "  --json-out <path>          Write the sanitized JSON report to a file.",
    "  --summary-only             Print a compact stdout summary instead of the full report.",
    "  --fail-on-diff            Exit 1 when warning/error findings are present.",
    "  --help                    Show this help text.",
  ].join("\n");
}

function parseArgs(argv, env = process.env, cwd = process.cwd()) {
  const options = {
    relayUrl: env.CODEX_DOCK_RELAY_WS || DEFAULT_RELAY_WS,
    codexHome: env.CODEX_HOME || path.join(os.homedir(), ".codex"),
    sqliteHome: env.CODEX_SQLITE_HOME || null,
    limit: DEFAULT_LIMIT,
    maxThreads: null,
    threadIDs: [],
    includeArchived: false,
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
    } else if (arg === "--max-threads") {
      options.maxThreads = parsePositiveInteger(readValue(index, arg), "--max-threads");
      index += 1;
    } else if (arg.startsWith("--max-threads=")) {
      options.maxThreads = parsePositiveInteger(arg.slice("--max-threads=".length), "--max-threads");
    } else if (arg === "--thread-id") {
      options.threadIDs.push(...splitThreadIDs(readValue(index, arg)));
      index += 1;
    } else if (arg.startsWith("--thread-id=")) {
      options.threadIDs.push(...splitThreadIDs(arg.slice("--thread-id=".length)));
    } else if (arg === "--include-archived") {
      options.includeArchived = true;
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
  options.maxThreads = Math.min(options.maxThreads || options.limit, THREAD_LIST_MAX_LIMIT);
  options.threadIDs = [...new Set(options.threadIDs)];
  options.codexHome = resolveUserPath(options.codexHome, cwd);
  options.sqliteHome = resolveUserPath(options.sqliteHome || options.codexHome, cwd);
  options.jsonOut = options.jsonOut ? resolveUserPath(options.jsonOut, cwd) : null;
  return options;
}

function parseMaybeJSON(value) {
  if (typeof value !== "string") {
    return value;
  }
  const trimmed = value.trim();
  if (!trimmed.startsWith("{") && !trimmed.startsWith("[")) {
    return value;
  }
  try {
    return JSON.parse(trimmed);
  } catch {
    return value;
  }
}

function normalizedSubAgentVariant(value) {
  if (typeof value === "string") {
    switch (canonicalSourceName(value)) {
      case "review":
      case "subagentreview":
        return "review";
      case "compact":
      case "subagentcompact":
        return "compact";
      case "threadspawn":
      case "subagentthreadspawn":
      case "spawn":
        return "threadSpawn";
      case "other":
      case "subagentother":
        return "other";
      case "memoryconsolidation":
        return "memoryConsolidation";
      default:
        return "unknown";
    }
  }
  if (value && typeof value === "object") {
    if (Object.hasOwn(value, "thread_spawn") || Object.hasOwn(value, "threadSpawn")) {
      return "threadSpawn";
    }
    if (Object.hasOwn(value, "review")) {
      return "review";
    }
    if (Object.hasOwn(value, "compact")) {
      return "compact";
    }
    if (Object.hasOwn(value, "other")) {
      return "other";
    }
  }
  return "unknown";
}

function signalFromString(value) {
  const normalized = canonicalSourceName(value);
  switch (normalized) {
    case "cli":
      return { family: "human", kind: "cli" };
    case "vscode":
      return { family: "human", kind: "vscode" };
    case "exec":
      return { family: "automation", kind: "exec" };
    case "appserver":
    case "mcp":
      return { family: "automation", kind: "appServer" };
    case "atlas":
    case "chatgpt":
      return { family: "human", kind: "custom", name: normalizeSourceName(value) };
    case "subagent":
      return { family: "automation", kind: "subAgent", variant: "unknown" };
    case "subagentreview":
      return { family: "automation", kind: "subAgent", variant: "review" };
    case "subagentcompact":
      return { family: "automation", kind: "subAgent", variant: "compact" };
    case "subagentthreadspawn":
      return { family: "automation", kind: "subAgent", variant: "threadSpawn" };
    case "subagentother":
      return { family: "automation", kind: "subAgent", variant: "other" };
    case "internal":
    case "memoryconsolidation":
      return { family: "internal", kind: "internal" };
    case "unknown":
      return { family: "unknown", kind: "unknown" };
    default:
      return { family: "unknown", kind: "unknown" };
  }
}

function signalFromSubAgent(value) {
  if (Array.isArray(value)) {
    return value.flatMap(signalFromSubAgent);
  }
  if (typeof value === "string" && normalizedSubAgentVariant(value) === "memoryConsolidation") {
    return [{ family: "internal", kind: "internal" }];
  }
  if (
    value
    && typeof value === "object"
    && (
      Object.hasOwn(value, "memory_consolidation")
      || Object.hasOwn(value, "memoryConsolidation")
      || Object.hasOwn(value, "internal")
    )
  ) {
    return [{ family: "internal", kind: "internal" }];
  }
  return [{
    family: "automation",
    kind: "subAgent",
    variant: normalizedSubAgentVariant(value),
  }];
}

function signalsFromSourceObject(source) {
  const signals = [];
  for (const key of ["type", "kind", "sourceKind", "source_kind", "subtype", "custom"]) {
    if (typeof source[key] === "string") {
      signals.push(signalFromString(source[key]));
    }
  }
  if (source.source !== undefined) {
    signals.push(...signalsFromSourceValue(source.source));
  }
  for (const key of Object.keys(source)) {
    switch (canonicalSourceName(key)) {
      case "cli":
      case "vscode":
      case "exec":
      case "appserver":
      case "mcp":
      case "unknown":
      case "subagentreview":
      case "subagentcompact":
      case "subagentthreadspawn":
      case "subagentother":
        signals.push(signalFromString(key));
        break;
      case "subagent":
        signals.push(...signalFromSubAgent(source[key]));
        break;
      case "internal":
      case "memory":
      case "memoryconsolidation":
        signals.push({ family: "internal", kind: "internal" });
        break;
      default:
        break;
    }
  }
  return signals;
}

function signalsFromSourceValue(source) {
  const parsed = parseMaybeJSON(source);
  if (typeof parsed === "string") {
    return [signalFromString(parsed)];
  }
  if (Array.isArray(parsed)) {
    return parsed.flatMap(signalsFromSourceValue);
  }
  if (parsed && typeof parsed === "object") {
    return signalsFromSourceObject(parsed);
  }
  return [];
}

function uniqueSignals(signals) {
  const seen = new Set();
  const result = [];
  for (const signal of signals) {
    const key = JSON.stringify(signal);
    if (!seen.has(key)) {
      seen.add(key);
      result.push(signal);
    }
  }
  return result;
}

function sourceFromSignals(signals) {
  const unique = uniqueSignals(signals);
  if (unique.length === 0) {
    return { kind: "unknown" };
  }
  if (unique.some((signal) => signal.family === "unknown")) {
    return { kind: "unknown" };
  }
  if (unique.some((signal) => signal.family === "internal")) {
    return { kind: "internal" };
  }

  const families = new Set(unique.map((signal) => signal.family));
  if (families.size !== 1) {
    return { kind: "unknown" };
  }
  const kinds = new Set(unique.map((signal) => (
    signal.kind === "custom"
      ? `custom:${signal.name}`
      : signal.kind === "subAgent"
        ? `subAgent:${signal.variant}`
        : signal.kind
  )));
  if (kinds.size !== 1) {
    return { kind: "unknown" };
  }

  const signal = unique[0];
  if (signal.kind === "custom") {
    return { kind: "custom", name: signal.name };
  }
  if (signal.kind === "subAgent") {
    return { kind: "subAgent", variant: signal.variant };
  }
  return { kind: signal.kind };
}

function normalizedThreadSourceForFidelity(row) {
  const threadSource = row?.threadSource ?? row?.thread_source;
  if (canonicalSourceName(threadSource) === "memoryconsolidation") {
    return { kind: "internal" };
  }
  return sourceFromSignals(signalsFromSourceValue(row?.source));
}

function sourceReport(value, threadSource = null) {
  const parsed = parseMaybeJSON(value);
  const report = {
    normalized: normalizedThreadSourceForFidelity({ source: parsed, threadSource }),
  };
  const cleanedThreadSource = nonEmpty(threadSource);
  if (cleanedThreadSource) {
    report.threadSource = cleanedThreadSource;
  }
  if (typeof parsed === "string") {
    report.value = parsed;
  } else if (parsed && typeof parsed === "object") {
    report.kind = Array.isArray(parsed) ? "array" : "object";
    report.keys = Array.isArray(parsed) ? [] : Object.keys(parsed).sort();
    report.sha256 = sha256Short(JSON.stringify(parsed));
  } else {
    report.value = null;
  }
  return report;
}

function expectedDockLaneForSource(source) {
  switch (source?.kind) {
    case "cli":
    case "vscode":
    case "custom":
      return { lane: "human", sourceKind: "human" };
    case "exec":
    case "appServer":
    case "subAgent":
    case "unknown":
      return { lane: "agent", sourceKind: "automation" };
    case "internal":
      return { lane: "internal", sourceKind: "internal" };
    default:
      return { lane: "agent", sourceKind: "automation" };
  }
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
    maxBuffer: 10 * 1024 * 1024,
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

class CodexStorageReader {
  constructor({ codexHome, sqliteHome }) {
    this.codexHome = codexHome;
    this.sqliteHome = sqliteHome;
    this.stateDbPath = path.join(sqliteHome, "state_5.sqlite");
    this.goalsDbPath = path.join(sqliteHome, "goals_1.sqlite");
    this.columnsByTable = new Map();
  }

  tableColumns(dbPath, table) {
    const key = `${dbPath}:${table}`;
    if (this.columnsByTable.has(key)) {
      return this.columnsByTable.get(key);
    }
    const result = runSQLiteJSON(dbPath, `PRAGMA table_info(${sqliteIdent(table)});`);
    const columns = result.ok ? new Set(result.rows.map((row) => row.name)) : new Set();
    this.columnsByTable.set(key, { result, columns });
    return this.columnsByTable.get(key);
  }

  tableExists(dbPath, table) {
    return this.tableColumns(dbPath, table).columns.size > 0;
  }

  selectRows(dbPath, table, wantedColumns, whereSQL = "", suffixSQL = "") {
    const { result, columns } = this.tableColumns(dbPath, table);
    if (!result.ok) {
      return { ok: false, rows: [], error: result.error, missing: result.missing, unavailable: result.unavailable };
    }
    if (columns.size === 0) {
      return { ok: false, rows: [], error: `missing table: ${table}` };
    }
    const selected = wantedColumns.filter((column) => columns.has(column));
    if (selected.length === 0) {
      return { ok: false, rows: [], error: `no requested columns exist in ${table}` };
    }
    const sql = [
      `SELECT ${selected.map(sqliteIdent).join(", ")}`,
      `FROM ${sqliteIdent(table)}`,
      whereSQL,
      suffixSQL,
    ].filter(Boolean).join(" ");
    return runSQLiteJSON(dbPath, `${sql};`);
  }

  stateThread(threadID) {
    return this.selectRows(
      this.stateDbPath,
      "threads",
      [
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
        "archived",
        "archived_at",
        "git_sha",
        "git_branch",
        "git_origin_url",
        "memory_mode",
      ],
      `WHERE "id" = ${sqliteLiteral(threadID)}`,
      "LIMIT 1",
    );
  }

  spawnEdges(threadID) {
    if (!this.tableExists(this.stateDbPath, "thread_spawn_edges")) {
      return { ok: false, rows: [], error: "missing table: thread_spawn_edges" };
    }
    const sql = [
      "SELECT parent_thread_id, child_thread_id, status",
      "FROM thread_spawn_edges",
      `WHERE parent_thread_id = ${sqliteLiteral(threadID)} OR child_thread_id = ${sqliteLiteral(threadID)}`,
      "ORDER BY parent_thread_id, child_thread_id;",
    ].join(" ");
    return runSQLiteJSON(this.stateDbPath, sql);
  }

  dynamicToolCount(threadID) {
    if (!this.tableExists(this.stateDbPath, "thread_dynamic_tools")) {
      return { ok: false, count: null, error: "missing table: thread_dynamic_tools" };
    }
    const sql = `SELECT COUNT(*) AS count FROM thread_dynamic_tools WHERE thread_id = ${sqliteLiteral(threadID)};`;
    const result = runSQLiteJSON(this.stateDbPath, sql);
    return {
      ok: result.ok,
      count: Number(result.rows?.[0]?.count ?? 0),
      error: result.error,
    };
  }

  backfillState() {
    if (!this.tableExists(this.stateDbPath, "backfill_state")) {
      return { ok: false, row: null, error: "missing table: backfill_state" };
    }
    const result = runSQLiteJSON(this.stateDbPath, "SELECT id, status, last_watermark, last_success_at, updated_at FROM backfill_state WHERE id = 1;");
    return { ok: result.ok, row: result.rows?.[0] || null, error: result.error };
  }

  goal(threadID) {
    return this.selectRows(
      this.goalsDbPath,
      "thread_goals",
      [
        "thread_id",
        "goal_id",
        "objective",
        "status",
        "token_budget",
        "tokens_used",
        "time_used_seconds",
        "created_at_ms",
        "updated_at_ms",
      ],
      `WHERE "thread_id" = ${sqliteLiteral(threadID)}`,
      "LIMIT 1",
    );
  }
}

function collectText(value, depth = 0) {
  if (depth > 6 || value === null || value === undefined) {
    return [];
  }
  if (typeof value === "string") {
    return [value];
  }
  if (Array.isArray(value)) {
    return value.flatMap((item) => collectText(item, depth + 1));
  }
  if (typeof value === "object") {
    const pieces = [];
    for (const key of ["text", "message", "content", "input_text"]) {
      if (value[key] !== undefined) {
        pieces.push(...collectText(value[key], depth + 1));
      }
    }
    return pieces;
  }
  return [];
}

function extractUserMessage(payload) {
  const type = canonicalSourceName(payload?.type || payload?.kind || payload?.event_type);
  if (type && type !== "usermessage" && type !== "userinput") {
    return null;
  }
  const role = canonicalSourceName(payload?.role || payload?.author?.role);
  if (role && role !== "user") {
    return null;
  }
  const pieces = collectText(payload?.message ?? payload?.text ?? payload?.content ?? payload?.input);
  const joined = pieces.map((piece) => piece.trim()).filter(Boolean).join("\n");
  return nonEmpty(joined);
}

function objectHasKey(value, wantedKey, depth = 0) {
  if (depth > 8 || !value || typeof value !== "object") {
    return false;
  }
  if (Object.hasOwn(value, wantedKey)) {
    return true;
  }
  if (Array.isArray(value)) {
    return value.some((item) => objectHasKey(item, wantedKey, depth + 1));
  }
  return Object.values(value).some((item) => objectHasKey(item, wantedKey, depth + 1));
}

function readRolloutSummary(rolloutPath) {
  const summary = {
    path: rolloutPath,
    exists: Boolean(rolloutPath && fs.existsSync(rolloutPath)),
    lineCount: 0,
    parseErrors: 0,
    typeCounts: {},
    sessionMetaPayload: null,
    firstUserMessage: null,
    latestTokenCount: null,
    latestTurnContextKeys: [],
    jsonModeSchemaPersisted: false,
    firstLineTimestamp: null,
    lastLineTimestamp: null,
  };
  if (!summary.exists) {
    return summary;
  }

  const text = fs.readFileSync(rolloutPath, "utf8");
  for (const line of text.split(/\r?\n/)) {
    if (line.trim().length === 0) {
      continue;
    }
    summary.lineCount += 1;
    let item;
    try {
      item = JSON.parse(line);
    } catch {
      summary.parseErrors += 1;
      continue;
    }
    const type = item?.type || "unknown";
    summary.typeCounts[type] = (summary.typeCounts[type] || 0) + 1;
    if (item?.timestamp && !summary.firstLineTimestamp) {
      summary.firstLineTimestamp = item.timestamp;
    }
    if (item?.timestamp) {
      summary.lastLineTimestamp = item.timestamp;
    }

    if (type === "session_meta" && !summary.sessionMetaPayload) {
      summary.sessionMetaPayload = item.payload || null;
    } else if (type === "turn_context") {
      const payload = item.payload || {};
      summary.latestTurnContextKeys = Object.keys(payload).sort();
      summary.jsonModeSchemaPersisted = summary.jsonModeSchemaPersisted
        || objectHasKey(payload, "final_output_json_schema")
        || objectHasKey(payload, "output_schema");
    } else if (type === "event_msg") {
      const payload = item.payload || {};
      if (!summary.firstUserMessage) {
        summary.firstUserMessage = extractUserMessage(payload);
      }
      const eventType = canonicalSourceName(payload?.type || payload?.kind);
      if (eventType === "tokencount" || eventType === "tokencountupdate") {
        summary.latestTokenCount = payload.totalTokenCount
          ?? payload.total_tokens
          ?? payload.tokens_used
          ?? summary.latestTokenCount;
      }
    }
  }
  return summary;
}

function walkForRolloutCandidates(root, threadID, candidates = []) {
  if (!root || !fs.existsSync(root)) {
    return candidates;
  }
  const suffix = `-${threadID}.jsonl`;
  const entries = fs.readdirSync(root, { withFileTypes: true });
  for (const entry of entries) {
    const fullPath = path.join(root, entry.name);
    if (entry.isDirectory()) {
      walkForRolloutCandidates(fullPath, threadID, candidates);
    } else if (entry.isFile() && entry.name.startsWith("rollout-") && entry.name.endsWith(suffix)) {
      candidates.push(fullPath);
    }
  }
  return candidates;
}

function findRolloutPath(codexHome, threadID, stateRow) {
  const candidates = [];
  if (stateRow?.rollout_path) {
    candidates.push(stateRow.rollout_path);
  }
  candidates.push(...walkForRolloutCandidates(path.join(codexHome, "sessions"), threadID));
  candidates.push(...walkForRolloutCandidates(path.join(codexHome, "archived_sessions"), threadID));
  const unique = [...new Set(candidates.filter(Boolean))];
  const existing = unique.find((candidate) => fs.existsSync(candidate));
  return {
    path: existing || unique[0] || null,
    candidates: unique,
  };
}

function readSessionIndexName(codexHome, threadID) {
  const indexPath = path.join(codexHome, "session_index.jsonl");
  if (!fs.existsSync(indexPath)) {
    return { path: indexPath, present: false, name: null, updatedAt: null, parseErrors: 0 };
  }
  let latest = null;
  let parseErrors = 0;
  const text = fs.readFileSync(indexPath, "utf8");
  for (const line of text.split(/\r?\n/)) {
    if (line.trim().length === 0) {
      continue;
    }
    try {
      const item = JSON.parse(line);
      if (item?.id === threadID) {
        latest = item;
      }
    } catch {
      parseErrors += 1;
    }
  }
  return {
    path: indexPath,
    present: Boolean(latest),
    name: latest?.thread_name || null,
    updatedAt: latest?.updated_at || null,
    parseErrors,
  };
}

function gitInfoFromMeta(meta) {
  const git = meta?.git || {};
  return {
    sha: nonEmpty(git.sha) || nonEmpty(git.commit_hash) || nonEmpty(git.commitHash),
    branch: nonEmpty(git.branch),
    originUrl: nonEmpty(git.origin_url) || nonEmpty(git.originUrl),
  };
}

function firstPresent(...values) {
  for (const value of values) {
    if (value !== undefined && value !== null && value !== "") {
      return value;
    }
  }
  return null;
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

function storageComparable(storage) {
  const row = storage.stateRow || {};
  const meta = storage.rollout?.sessionMetaPayload || {};
  const metaGit = gitInfoFromMeta(meta);
  const source = firstPresent(row.source, meta.source);
  const threadSource = firstPresent(row.thread_source, meta.thread_source);
  const rolloutPath = storage.rollout?.path || row.rollout_path || null;
  return {
    id: firstPresent(row.id, meta.id),
    rolloutPath,
    createdAtSeconds: timestampSeconds(firstPresent(row.created_at_ms, row.created_at, meta.timestamp)),
    updatedAtSeconds: timestampSeconds(firstPresent(row.updated_at_ms, row.updated_at, storage.rollout?.lastLineTimestamp)),
    source,
    sourceNormalized: normalizedThreadSourceForFidelity({ source, threadSource }),
    threadSource,
    agentNickname: firstPresent(row.agent_nickname, meta.agent_nickname),
    agentRole: firstPresent(row.agent_role, meta.agent_role),
    agentPath: firstPresent(row.agent_path, meta.agent_path),
    modelProvider: firstPresent(row.model_provider, meta.model_provider),
    cliVersion: firstPresent(row.cli_version, meta.cli_version),
    cwd: firstPresent(row.cwd, meta.cwd),
    forkedFromId: firstPresent(meta.forked_from_id, meta.forkedFromId),
    title: firstPresent(row.title, storage.sessionIndex?.name),
    preview: firstPresent(row.preview, row.first_user_message, storage.rollout?.firstUserMessage),
    firstUserMessage: firstPresent(row.first_user_message, storage.rollout?.firstUserMessage),
    archived: row.archived === undefined ? archiveStateFromPath(rolloutPath) : Number(row.archived) === 1,
    gitInfo: {
      sha: firstPresent(row.git_sha, metaGit.sha),
      branch: firstPresent(row.git_branch, metaGit.branch),
      originUrl: firstPresent(row.git_origin_url, metaGit.originUrl),
    },
  };
}

function archiveStateFromPath(rolloutPath) {
  if (!rolloutPath) {
    return null;
  }
  return rolloutPath.split(path.sep).includes("archived_sessions");
}

function normalizedStatus(thread) {
  const status = thread?.status;
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

function titleForThread(thread) {
  return firstBoundedText([
    thread?.name,
    thread?.preview,
    thread?.cwd?.split("/").filter(Boolean).at(-1),
  ], RELAY_STATE_TITLE_MAX_CHARS)
    || (nonEmpty(thread?.id) ? `Thread ${thread.id.slice(0, 8)}` : "Thread");
}

function displaySummaryForThreadCard(thread) {
  return firstBoundedText([
    thread?.displaySummary,
    thread?.latestSummary,
    thread?.summary,
    thread?.preview,
  ], RELAY_STATE_TEXT_FIELD_MAX_CHARS) || titleForThread(thread);
}

function repositoryForThread(thread) {
  const originURL = nonEmpty(thread?.gitInfo?.originUrl);
  if (originURL) {
    const pieces = originURL.split(/[/:]/).filter(Boolean);
    const last = pieces.at(-1);
    if (last) {
      return last.endsWith(".git") ? last.slice(0, -4) : last;
    }
  }
  return nonEmpty(thread?.cwd?.split("/").filter(Boolean).at(-1));
}

function addFinding(findings, severity, threadID, surface, field, message, values = {}) {
  findings.push({
    severity,
    threadID,
    surface,
    field,
    message,
    ...values,
  });
}

function compareExact(findings, severity, threadID, surface, field, relayValue, storageValue, message) {
  if (relayValue === null || relayValue === undefined || storageValue === null || storageValue === undefined) {
    return;
  }
  if (String(relayValue) !== String(storageValue)) {
    addFinding(findings, severity, threadID, surface, field, message, {
      relay: relayValue,
      storage: storageValue,
    });
  }
}

function compareRequiredExact(
  findings,
  severity,
  threadID,
  surface,
  field,
  actualValue,
  expectedValue,
  message,
) {
  if (expectedValue === null || expectedValue === undefined) {
    return;
  }
  if (actualValue === null || actualValue === undefined || String(actualValue) !== String(expectedValue)) {
    addFinding(findings, severity, threadID, surface, field, message, {
      actual: actualValue ?? null,
      expected: expectedValue,
    });
  }
}

function compareTimestamp(findings, threadID, surface, field, relayValue, storageValue, message) {
  const relaySeconds = timestampSeconds(relayValue);
  const storageSeconds = timestampSeconds(storageValue);
  if (relaySeconds === null || storageSeconds === null) {
    return;
  }
  if (Math.abs(relaySeconds - storageSeconds) > TIMESTAMP_TOLERANCE_SECONDS) {
    addFinding(findings, "warning", threadID, surface, field, message, {
      relay: relaySeconds,
      storage: storageSeconds,
      deltaSeconds: relaySeconds - storageSeconds,
    });
  }
}

function compareText(findings, threadID, surface, field, relayText, storageText, message) {
  if (!nonEmpty(relayText) || !nonEmpty(storageText)) {
    return;
  }
  if (!fingerprintsMatch(relayText, storageText)) {
    addFinding(findings, "warning", threadID, surface, field, message, {
      relay: textFingerprint(relayText),
      storage: textFingerprint(storageText),
    });
  }
}

function compareRelayThreadToStorage(threadID, relayThread, storage, loadedThreadIDs = new Set()) {
  const findings = [];
  const comparable = storageComparable(storage);
  const hasStorage = Boolean(storage.stateRow || storage.rollout?.sessionMetaPayload);

  if (!relayThread) {
    addFinding(findings, "error", threadID, "relay.thread_read", "thread", "relay thread/read did not return this thread");
    return findings;
  }

  if (!hasStorage && !relayThread.ephemeral) {
    addFinding(findings, "error", threadID, "storage", "durable_record", "non-ephemeral relay thread has no state DB row or rollout file");
  }
  if (!hasStorage && relayThread.ephemeral) {
    addFinding(findings, "info", threadID, "storage", "ephemeral", "ephemeral relay thread is expected to be absent from disk/SQLite");
  }

  compareExact(findings, "error", threadID, "relay.thread_read", "id", relayThread.id, comparable.id, "relay thread ID differs from storage ID");
  compareExact(findings, "error", threadID, "relay.thread_read", "cwd", relayThread.cwd, comparable.cwd, "relay cwd differs from storage cwd");
  compareExact(findings, "error", threadID, "relay.thread_read", "modelProvider", relayThread.modelProvider, comparable.modelProvider, "relay modelProvider differs from storage model provider");
  compareExact(findings, "warning", threadID, "relay.thread_read", "cliVersion", relayThread.cliVersion, comparable.cliVersion, "relay cliVersion differs from storage cli_version");
  compareExact(findings, "error", threadID, "relay.thread_read", "forkedFromId", relayThread.forkedFromId, comparable.forkedFromId, "relay fork parent differs from rollout session_meta fork parent");
  compareExact(findings, "warning", threadID, "relay.thread_read", "agentNickname", relayThread.agentNickname, comparable.agentNickname, "relay agent nickname differs from storage");
  compareExact(findings, "warning", threadID, "relay.thread_read", "agentRole", relayThread.agentRole, comparable.agentRole, "relay agent role differs from storage");
  compareExact(findings, "error", threadID, "relay.thread_read", "agentPath", relayThread.agentPath, comparable.agentPath, "relay agent path differs from storage");
  compareExact(findings, "error", threadID, "relay.thread_read", "git.branch", relayThread.gitInfo?.branch, comparable.gitInfo.branch, "relay git branch differs from storage");
  compareExact(findings, "warning", threadID, "relay.thread_read", "git.sha", relayThread.gitInfo?.sha, comparable.gitInfo.sha, "relay git SHA differs from storage");
  compareExact(findings, "warning", threadID, "relay.thread_read", "git.originUrl", relayThread.gitInfo?.originUrl, comparable.gitInfo.originUrl, "relay git origin URL differs from storage");
  compareTimestamp(findings, threadID, "relay.thread_read", "createdAt", relayThread.createdAt, comparable.createdAtSeconds, "relay createdAt differs from storage created time");
  compareTimestamp(findings, threadID, "relay.thread_read", "updatedAt", relayThread.updatedAt, comparable.updatedAtSeconds, "relay updatedAt differs from storage updated time");
  compareText(findings, threadID, "relay.thread_read", "preview", relayThread.preview, comparable.preview, "relay preview differs from storage preview");
  compareText(findings, threadID, "relay.thread_read", "name", relayThread.name, comparable.title, "relay name differs from storage title/session index");

  if (relayThread.path && comparable.rolloutPath && path.resolve(relayThread.path) !== path.resolve(comparable.rolloutPath)) {
    addFinding(findings, "error", threadID, "relay.thread_read", "path", "relay rollout path differs from storage rollout path", {
      relay: relayThread.path,
      storage: comparable.rolloutPath,
    });
  }

  const relaySource = normalizedThreadSourceForFidelity({
    source: relayThread.source,
    threadSource: relayThread.threadSource,
  });
  if (JSON.stringify(relaySource) !== JSON.stringify(comparable.sourceNormalized)) {
    addFinding(findings, "error", threadID, "relay.thread_read", "source", "relay source classification differs from storage source classification", {
      relay: sourceReport(relayThread.source, relayThread.threadSource),
      storage: sourceReport(comparable.source, comparable.threadSource),
    });
  }
  compareExact(findings, "error", threadID, "relay.thread_read", "threadSource", relayThread.threadSource, comparable.threadSource, "relay threadSource differs from storage thread_source");

  const isLoaded = loadedThreadIDs.has(threadID);
  if (isLoaded && relayThread.status?.type === "notLoaded") {
    addFinding(findings, "error", threadID, "relay.loaded", "status", "thread/loaded/list includes the thread but thread/read reports notLoaded");
  } else if (!isLoaded && relayThread.status?.type && relayThread.status.type !== "notLoaded") {
    addFinding(findings, "warning", threadID, "relay.loaded", "status", "thread/read reports a live status but thread/loaded/list did not include the thread", {
      status: relayThread.status.type,
    });
  } else {
    addFinding(findings, "info", threadID, "relay.loaded", "status", isLoaded ? "relay reports this thread as loaded/live" : "relay reports this thread as stored/not loaded");
  }

  return findings;
}

function compareDockThreadCardToRelay(threadID, dockCard, relayThread, storage) {
  const findings = [];
  if (!dockCard) {
    return findings;
  }

  if (dockCard.threadID !== threadID) {
    addFinding(findings, "error", threadID, "dock.snapshot", "threadID", "dock card threadID differs from expected thread ID", {
      relay: dockCard.threadID,
      storage: threadID,
    });
  }
  if (dockCard.logicalHostID && dockCard.id !== `${dockCard.logicalHostID}::${dockCard.threadID}`) {
    addFinding(findings, "error", threadID, "dock.snapshot", "id", "dock card id is not logicalHostID::threadID", {
      relay: dockCard.id,
      expected: `${dockCard.logicalHostID}::${dockCard.threadID}`,
    });
  }

  if (relayThread) {
    const expectedBackendID = nonEmpty(relayThread.sessionId) || relayThread.id;
    compareRequiredExact(findings, "error", threadID, "dock.snapshot", "backendSessionID", dockCard.backendSessionID, expectedBackendID, "dock backendSessionID differs from relay thread session ID");
    compareRequiredExact(findings, "error", threadID, "dock.snapshot", "workingDirectory", dockCard.workingDirectory, nonEmpty(relayThread.cwd) || nonEmpty(relayThread.path), "dock workingDirectory differs from relay thread cwd/path");
    compareRequiredExact(findings, "error", threadID, "dock.snapshot", "branch", dockCard.branch, relayThread.gitInfo?.branch, "dock branch differs from relay thread git branch");
    compareRequiredExact(findings, "warning", threadID, "dock.snapshot", "repository", dockCard.repository, repositoryForThread(relayThread), "dock repository differs from relay-derived repository");
    compareRequiredExact(findings, "error", threadID, "dock.snapshot", "status", dockCard.status, normalizedStatus(relayThread), "dock status differs from relay thread status");
    if (relayThread.activityAt !== null && relayThread.activityAt !== undefined) {
      compareTimestamp(findings, threadID, "dock.snapshot", "activityAt", dockCard.activityAtMs ?? dockCard.activityAt, relayThread.activityAt, "dock activityAt differs from relay thread activity");
    }
    compareText(findings, threadID, "dock.snapshot", "title", dockCard.title, titleForThread(relayThread), "dock title differs from relay-derived title");
    compareText(findings, threadID, "dock.snapshot", "displaySummary", dockCard.displaySummary, displaySummaryForThreadCard(relayThread), "dock displaySummary differs from relay-derived summary");
  }

  const comparable = storageComparable(storage);
  const expected = expectedDockLaneForSource(comparable.sourceNormalized);
  if (expected.lane === "internal") {
    addFinding(findings, "error", threadID, "dock.snapshot", "lane", "internal storage thread appeared in the dock card snapshot");
  } else {
    compareRequiredExact(findings, "error", threadID, "dock.snapshot", "lane", dockCard.lane, expected.lane, "dock lane differs from storage source classification");
    compareRequiredExact(findings, "error", threadID, "dock.snapshot", "sourceKind", dockCard.sourceKind, expected.sourceKind, "dock sourceKind differs from storage source classification");
  }
  compareRequiredExact(findings, "error", threadID, "dock.snapshot", "workingDirectory", dockCard.workingDirectory, comparable.cwd, "dock workingDirectory differs from storage cwd");
  compareRequiredExact(findings, "error", threadID, "dock.snapshot", "branch", dockCard.branch, comparable.gitInfo.branch, "dock branch differs from storage git branch");
  return findings;
}

function sanitizeThreadStatus(status) {
  if (!status || typeof status !== "object") {
    return status || null;
  }
  return {
    type: status.type || null,
    activeFlags: Array.isArray(status.activeFlags) ? [...status.activeFlags] : [],
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
    status: sanitizeThreadStatus(thread.status),
    path: thread.path || null,
    cwd: thread.cwd || null,
    cliVersion: thread.cliVersion || null,
    source: sourceReport(thread.source, thread.threadSource),
    threadSource: thread.threadSource || null,
    agentNickname: thread.agentNickname || null,
    agentRole: thread.agentRole || null,
    agentPath: thread.agentPath || null,
    gitInfo: thread.gitInfo || null,
    name: textFingerprint(thread.name),
    preview: textFingerprint(thread.preview),
    latestSummary: textFingerprint(thread.latestSummary),
    turnCount: Array.isArray(thread.turns) ? thread.turns.length : null,
  };
}

function sanitizeDockThreadCard(card) {
  if (!card) {
    return null;
  }
  return {
    id: card.id || null,
    logicalHostID: card.logicalHostID || null,
    threadID: card.threadID || null,
    backendSessionID: card.backendSessionID || null,
    title: textFingerprint(card.title),
    status: card.status || null,
    lane: card.lane || null,
    sourceKind: card.sourceKind || null,
    repository: card.repository || null,
    workingDirectory: card.workingDirectory || null,
    branch: card.branch || null,
    activityAt: card.activityAt ?? null,
    activityAtMs: card.activityAtMs ?? null,
    displaySummary: textFingerprint(card.displaySummary),
  };
}

function sanitizeStorage(storage) {
  const state = storage.stateRow;
  const rollout = storage.rollout;
  const sessionIndex = storage.sessionIndex;
  const goal = storage.goalRow;
  return {
    stateDb: {
      present: Boolean(state),
      row: state ? {
        id: state.id || null,
        rolloutPath: state.rollout_path || null,
        createdAt: state.created_at ?? null,
        updatedAt: state.updated_at ?? null,
        createdAtMs: state.created_at_ms ?? null,
        updatedAtMs: state.updated_at_ms ?? null,
        source: sourceReport(state.source, state.thread_source),
        threadSource: state.thread_source || null,
        agentNickname: state.agent_nickname || null,
        agentRole: state.agent_role || null,
        agentPath: state.agent_path || null,
        modelProvider: state.model_provider || null,
        model: state.model || null,
        reasoningEffort: state.reasoning_effort || null,
        cwd: state.cwd || null,
        cliVersion: state.cli_version || null,
        title: textFingerprint(state.title),
        preview: textFingerprint(state.preview),
        sandboxPolicy: state.sandbox_policy || null,
        approvalMode: state.approval_mode || null,
        tokensUsed: state.tokens_used ?? null,
        firstUserMessage: textFingerprint(state.first_user_message),
        archived: state.archived === undefined ? null : Number(state.archived) === 1,
        archivedAt: state.archived_at ?? null,
        gitSha: state.git_sha || null,
        gitBranch: state.git_branch || null,
        gitOriginUrl: state.git_origin_url || null,
        memoryMode: state.memory_mode || null,
      } : null,
      error: storage.stateError || null,
    },
    rollout: rollout ? {
      path: rollout.path || null,
      exists: Boolean(rollout.exists),
      lineCount: rollout.lineCount || 0,
      parseErrors: rollout.parseErrors || 0,
      typeCounts: rollout.typeCounts || {},
      sessionMeta: rollout.sessionMetaPayload ? {
        id: rollout.sessionMetaPayload.id || null,
        forkedFromId: rollout.sessionMetaPayload.forked_from_id || rollout.sessionMetaPayload.forkedFromId || null,
        timestamp: rollout.sessionMetaPayload.timestamp || null,
        cwd: rollout.sessionMetaPayload.cwd || null,
        cliVersion: rollout.sessionMetaPayload.cli_version || null,
        source: sourceReport(rollout.sessionMetaPayload.source, rollout.sessionMetaPayload.thread_source),
        threadSource: rollout.sessionMetaPayload.thread_source || null,
        agentNickname: rollout.sessionMetaPayload.agent_nickname || null,
        agentRole: rollout.sessionMetaPayload.agent_role || null,
        agentPath: rollout.sessionMetaPayload.agent_path || null,
        modelProvider: rollout.sessionMetaPayload.model_provider || null,
        gitInfo: gitInfoFromMeta(rollout.sessionMetaPayload),
      } : null,
      firstUserMessage: textFingerprint(rollout.firstUserMessage),
      latestTokenCount: rollout.latestTokenCount ?? null,
      latestTurnContextKeys: rollout.latestTurnContextKeys || [],
      jsonModeSchemaPersisted: Boolean(rollout.jsonModeSchemaPersisted),
      firstLineTimestamp: rollout.firstLineTimestamp || null,
      lastLineTimestamp: rollout.lastLineTimestamp || null,
    } : null,
    sessionIndex: sessionIndex ? {
      path: sessionIndex.path,
      present: sessionIndex.present,
      name: textFingerprint(sessionIndex.name),
      updatedAt: sessionIndex.updatedAt,
      parseErrors: sessionIndex.parseErrors,
    } : null,
    spawnEdges: storage.spawnEdges || [],
    dynamicToolCount: storage.dynamicToolCount ?? null,
    goal: goal ? {
      threadID: goal.thread_id || null,
      goalID: goal.goal_id || null,
      objective: textFingerprint(goal.objective),
      status: goal.status || null,
      tokenBudget: goal.token_budget ?? null,
      tokensUsed: goal.tokens_used ?? null,
      timeUsedSeconds: goal.time_used_seconds ?? null,
      createdAtMs: goal.created_at_ms ?? null,
      updatedAtMs: goal.updated_at_ms ?? null,
    } : null,
    goalError: storage.goalError || null,
  };
}

function readStorageForThread(reader, threadID) {
  const stateResult = reader.stateThread(threadID);
  const stateRow = stateResult.ok ? stateResult.rows[0] || null : null;
  const rolloutPath = findRolloutPath(reader.codexHome, threadID, stateRow);
  const rollout = readRolloutSummary(rolloutPath.path);
  const sessionIndex = readSessionIndexName(reader.codexHome, threadID);
  const spawnResult = reader.spawnEdges(threadID);
  const toolResult = reader.dynamicToolCount(threadID);
  const goalResult = reader.goal(threadID);
  return {
    stateRow,
    stateError: stateResult.ok ? null : stateResult.error,
    rollout,
    rolloutCandidates: rolloutPath.candidates,
    sessionIndex,
    spawnEdges: spawnResult.ok ? spawnResult.rows : [],
    spawnError: spawnResult.ok ? null : spawnResult.error,
    dynamicToolCount: toolResult.ok ? toolResult.count : null,
    dynamicToolError: toolResult.ok ? null : toolResult.error,
    goalRow: goalResult.ok ? goalResult.rows[0] || null : null,
    goalError: goalResult.ok ? null : goalResult.error,
  };
}

async function requestMaybe(client, method, params, label, errors) {
  try {
    return await client.request(method, params);
  } catch (error) {
    errors.push({
      label,
      method,
      error: error.message || String(error),
    });
    return null;
  }
}

async function readRelaySurfaces(options) {
  const errors = [];
  const client = new JsonRpcWebSocketClient(options.relayUrl);
  await initializeClient(client);
  try {
    const dockSnapshot = await requestMaybe(client, "dock/subscribe", undefined, "dock snapshot", errors);
    const loadedList = await requestMaybe(client, "thread/loaded/list", { limit: THREAD_LIST_MAX_LIMIT }, "loaded list", errors);
    const baseParams = {
      limit: options.limit,
      sortKey: "updated_at",
      sortDirection: "desc",
      modelProviders: [],
      archived: false,
    };
    const listRequests = [
      ["interactiveActive", baseParams],
      ["automationActive", { ...baseParams, sourceKinds: AGENT_SOURCE_KINDS }],
    ];
    if (options.includeArchived) {
      listRequests.push(["interactiveArchived", { ...baseParams, archived: true }]);
      listRequests.push(["automationArchived", { ...baseParams, archived: true, sourceKinds: AGENT_SOURCE_KINDS }]);
    }
    const lists = {};
    for (const [label, params] of listRequests) {
      lists[label] = await requestMaybe(client, "thread/list", params, label, errors);
    }

    const ids = [];
    const pushID = (id) => {
      if (id && !ids.includes(id)) {
        ids.push(id);
      }
    };
    for (const id of options.threadIDs) {
      pushID(id);
    }
    for (const card of dockSnapshot?.cards || []) {
      pushID(card.threadID);
    }
    for (const list of Object.values(lists)) {
      for (const row of list?.data || []) {
        pushID(row.id);
      }
    }
    for (const id of loadedList?.data || []) {
      pushID(id);
    }
    const selectedIDs = options.threadIDs.length > 0 ? ids : ids.slice(0, options.maxThreads);
    const threadReads = {};
    for (const threadID of selectedIDs) {
      const response = await requestMaybe(client, "thread/read", { threadId: threadID, includeTurns: false }, `thread ${threadID}`, errors);
      threadReads[threadID] = response?.thread || null;
    }

    return {
      dockSnapshot,
      loadedThreadIDs: new Set((loadedList?.data || []).filter(Boolean)),
      loadedList,
      lists,
      threadReads,
      selectedThreadIDs: selectedIDs,
      errors,
    };
  } finally {
    await client.close();
  }
}

function buildThreadReport(threadID, relay, storage) {
  const dockCard = (relay.dockSnapshot?.cards || []).find((card) => card.threadID === threadID) || null;
  const relayThread = relay.threadReads[threadID] || null;
  const findings = [
    ...compareRelayThreadToStorage(threadID, relayThread, storage, relay.loadedThreadIDs),
    ...compareDockThreadCardToRelay(threadID, dockCard, relayThread, storage),
  ];

  if (storage.rollout?.path && storage.stateRow?.rollout_path && path.resolve(storage.rollout.path) !== path.resolve(storage.stateRow.rollout_path)) {
    addFinding(findings, "warning", threadID, "storage", "rollout_path", "state DB rollout_path differs from rollout file found on disk", {
      stateDb: storage.stateRow.rollout_path,
      disk: storage.rollout.path,
    });
  }
  if (storage.stateRow && storage.rollout?.sessionMetaPayload) {
    const comparable = storageComparable(storage);
    compareExact(findings, "error", threadID, "storage", "cwd", storage.stateRow.cwd, storage.rollout.sessionMetaPayload.cwd, "state DB cwd differs from rollout session_meta cwd");
    compareExact(findings, "warning", threadID, "storage", "cliVersion", storage.stateRow.cli_version, storage.rollout.sessionMetaPayload.cli_version, "state DB cli_version differs from rollout session_meta cli_version");
    compareExact(findings, "error", threadID, "storage", "modelProvider", storage.stateRow.model_provider, storage.rollout.sessionMetaPayload.model_provider, "state DB model provider differs from rollout session_meta model provider");
    compareText(findings, threadID, "storage", "firstUserMessage", storage.stateRow.first_user_message, storage.rollout.firstUserMessage, "state DB first_user_message differs from rollout first user message");
    const pathArchived = archiveStateFromPath(storage.rollout.path);
    if (pathArchived !== null && comparable.archived !== null && pathArchived !== comparable.archived) {
      addFinding(findings, "error", threadID, "storage", "archived", "state DB archived flag differs from rollout path collection", {
        stateDb: comparable.archived,
        diskPathArchived: pathArchived,
      });
    }
  }
  if (storage.rollout?.parseErrors > 0) {
    addFinding(findings, "warning", threadID, "storage.rollout", "parseErrors", "rollout JSONL has parse errors", {
      parseErrors: storage.rollout.parseErrors,
    });
  }
  if (storage.goalRow) {
    addFinding(findings, "info", threadID, "storage.goals", "goal", "goals_1.sqlite has a current goal row for this thread", {
      status: storage.goalRow.status,
      tokenBudget: storage.goalRow.token_budget ?? null,
    });
  }
  if (storage.rollout && !storage.rollout.jsonModeSchemaPersisted) {
    addFinding(findings, "info", threadID, "storage.rollout", "jsonMode", "rollout did not persist normal turn JSON-output schema proof");
  }

  return {
    threadID,
    relay: {
      dockCard: sanitizeDockThreadCard(dockCard),
      threadRead: sanitizeRelayThread(relayThread),
      loaded: relay.loadedThreadIDs.has(threadID),
    },
    storage: sanitizeStorage(storage),
    findings,
  };
}

async function buildReport(options) {
  const relay = await readRelaySurfaces(options);
  const reader = new CodexStorageReader(options);
  const backfill = reader.backfillState();
  const threads = [];
  for (const threadID of relay.selectedThreadIDs) {
    const storage = readStorageForThread(reader, threadID);
    threads.push(buildThreadReport(threadID, relay, storage));
  }

  const relayErrors = relay.errors.map((error) => ({
    severity: "error",
    threadID: null,
    surface: "relay",
    field: error.method,
    message: `${error.label} request failed`,
    error: error.error,
  }));
  const findings = [
    ...relayErrors,
    ...threads.flatMap((thread) => thread.findings),
  ];
  const severityCounts = findings.reduce((counts, finding) => {
    counts[finding.severity] = (counts[finding.severity] || 0) + 1;
    return counts;
  }, {});
  const warningOrErrorCount = (severityCounts.error || 0) + (severityCounts.warning || 0);
  return {
    ok: warningOrErrorCount === 0,
    generatedAt: new Date().toISOString(),
    config: {
      relayUrl: sanitizeURLForReport(options.relayUrl),
      codexHome: options.codexHome,
      sqliteHome: options.sqliteHome,
      stateDbPath: reader.stateDbPath,
      goalsDbPath: reader.goalsDbPath,
      limit: options.limit,
      maxThreads: options.maxThreads,
      includeArchived: options.includeArchived,
      explicitThreadIDs: options.threadIDs,
    },
    relay: {
      dockSnapshot: relay.dockSnapshot ? {
        kind: relay.dockSnapshot.kind || null,
        seq: relay.dockSnapshot.seq ?? null,
        asOf: relay.dockSnapshot.asOf || null,
        hostCount: Array.isArray(relay.dockSnapshot.hosts) ? relay.dockSnapshot.hosts.length : 0,
        cardCount: Array.isArray(relay.dockSnapshot.cards) ? relay.dockSnapshot.cards.length : 0,
        freshness: relay.dockSnapshot.freshness || null,
      } : null,
      loadedThreadCount: relay.loadedThreadIDs.size,
      listCounts: Object.fromEntries(Object.entries(relay.lists).map(([label, result]) => [
        label,
        {
          rows: result?.data?.length || 0,
          nextCursor: result?.nextCursor || null,
          liveOverlay: result?.liveOverlay || null,
        },
      ])),
      selectedThreadIDs: relay.selectedThreadIDs,
      errors: relay.errors,
    },
    storage: {
      stateDbAvailable: fs.existsSync(reader.stateDbPath),
      goalsDbAvailable: fs.existsSync(reader.goalsDbPath),
      backfillState: backfill.ok ? backfill.row : null,
      backfillError: backfill.ok ? null : backfill.error,
    },
    summary: {
      checkedThreads: threads.length,
      findings: findings.length,
      errors: severityCounts.error || 0,
      warnings: severityCounts.warning || 0,
      info: severityCounts.info || 0,
    },
    findings,
    threads,
  };
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
    codexHome: report.config.codexHome,
    sqliteHome: report.config.sqliteHome,
    relay: {
      dockCardCount: report.relay.dockSnapshot?.cardCount ?? null,
      loadedThreadCount: report.relay.loadedThreadCount,
      relayErrors: report.relay.errors.length,
    },
    storage: {
      stateDbAvailable: report.storage.stateDbAvailable,
      goalsDbAvailable: report.storage.goalsDbAvailable,
      backfillStatus: report.storage.backfillState?.status || null,
    },
    summary: report.summary,
  } : report;
  process.stdout.write(`${JSON.stringify(stdoutReport, null, 2)}\n`);
  const warningOrErrorCount = report.summary.errors + report.summary.warnings;
  if (options.failOnDiff && warningOrErrorCount > 0) {
    process.exitCode = 1;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.error(`relay-thread-fidelity failed: ${error.message || error}`);
    process.exit(1);
  });
}

export {
  buildReport,
  compareDockThreadCardToRelay,
  compareRelayThreadToStorage,
  expectedDockLaneForSource,
  normalizedStatus,
  normalizedThreadSourceForFidelity,
  parseArgs,
  sourceReport,
  storageComparable,
  textFingerprint,
};

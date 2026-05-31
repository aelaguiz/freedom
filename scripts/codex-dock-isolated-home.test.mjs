import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import {
  createIsolatedHome,
  parseArgs,
} from "./codex-dock-isolated-home.mjs";

function hasSqlite() {
  return spawnSync("sqlite3", ["--version"], { encoding: "utf8" }).status === 0;
}

function tempDir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), "codex-dock-isolated-home-test-"));
}

function runSqlite(dbPath, sql) {
  const result = spawnSync("sqlite3", [dbPath], {
    input: sql,
    encoding: "utf8",
  });
  if (result.status !== 0) {
    throw new Error(result.stderr || result.stdout);
  }
  return result.stdout;
}

function sqliteJSON(dbPath, sql) {
  const result = spawnSync("sqlite3", ["-json", dbPath, sql], { encoding: "utf8" });
  if (result.status !== 0) {
    throw new Error(result.stderr || result.stdout);
  }
  return result.stdout.trim() ? JSON.parse(result.stdout) : [];
}

function writeSourceHome(root) {
  const sourceHome = path.join(root, "source-home");
  fs.mkdirSync(path.join(sourceHome, "sessions", "2026", "05", "31"), { recursive: true });
  fs.mkdirSync(path.join(sourceHome, "archived_sessions"), { recursive: true });
  const rolloutA = path.join(sourceHome, "sessions", "2026", "05", "31", "rollout-a.jsonl");
  const rolloutB = path.join(sourceHome, "sessions", "2026", "05", "31", "rollout-b.jsonl");
  const archivedRolloutC = path.join(sourceHome, "archived_sessions", "rollout-c.jsonl");
  fs.writeFileSync(rolloutA, "{\"type\":\"session_meta\",\"payload\":{\"id\":\"thread-a\"}}\n");
  fs.writeFileSync(rolloutB, "{\"type\":\"session_meta\",\"payload\":{\"id\":\"thread-b\"}}\n");
  fs.writeFileSync(archivedRolloutC, "{\"type\":\"session_meta\",\"payload\":{\"id\":\"thread-c\"}}\n");

  runSqlite(path.join(sourceHome, "state_5.sqlite"), `
CREATE TABLE threads (
  id TEXT PRIMARY KEY,
  rollout_path TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  source TEXT NOT NULL,
  model_provider TEXT NOT NULL,
  cwd TEXT NOT NULL,
  title TEXT NOT NULL,
  sandbox_policy TEXT NOT NULL,
  approval_mode TEXT NOT NULL,
  tokens_used INTEGER NOT NULL DEFAULT 0,
  has_user_event INTEGER NOT NULL DEFAULT 0,
  archived INTEGER NOT NULL DEFAULT 0,
  archived_at INTEGER,
  git_sha TEXT,
  git_branch TEXT,
  git_origin_url TEXT,
  cli_version TEXT NOT NULL DEFAULT '',
  first_user_message TEXT NOT NULL DEFAULT '',
  agent_nickname TEXT,
  agent_role TEXT,
  memory_mode TEXT NOT NULL DEFAULT 'enabled',
  model TEXT,
  reasoning_effort TEXT,
  agent_path TEXT,
  created_at_ms INTEGER,
  updated_at_ms INTEGER,
  thread_source TEXT,
  preview TEXT NOT NULL DEFAULT ''
);
CREATE TABLE thread_dynamic_tools (
  thread_id TEXT NOT NULL,
  position INTEGER NOT NULL,
  name TEXT NOT NULL,
  description TEXT NOT NULL,
  input_schema TEXT NOT NULL,
  defer_loading INTEGER NOT NULL DEFAULT 0,
  namespace TEXT,
  PRIMARY KEY(thread_id, position)
);
CREATE TABLE thread_spawn_edges (
  parent_thread_id TEXT NOT NULL,
  child_thread_id TEXT NOT NULL PRIMARY KEY,
  status TEXT NOT NULL
);
CREATE TABLE remote_control_enrollments (
  websocket_url TEXT NOT NULL,
  account_id TEXT NOT NULL,
  app_server_client_name TEXT NOT NULL,
  server_id TEXT NOT NULL,
  environment_id TEXT NOT NULL,
  server_name TEXT NOT NULL,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (websocket_url, account_id, app_server_client_name)
);
CREATE TABLE agent_jobs (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  status TEXT NOT NULL,
  instruction TEXT NOT NULL,
  output_schema_json TEXT,
  input_headers_json TEXT NOT NULL,
  input_csv_path TEXT NOT NULL,
  output_csv_path TEXT NOT NULL,
  auto_export INTEGER NOT NULL DEFAULT 1,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  started_at INTEGER,
  completed_at INTEGER,
  last_error TEXT,
  max_runtime_seconds INTEGER
);
CREATE TABLE agent_job_items (
  job_id TEXT NOT NULL,
  item_id TEXT NOT NULL,
  row_index INTEGER NOT NULL,
  source_id TEXT,
  row_json TEXT NOT NULL,
  status TEXT NOT NULL,
  assigned_thread_id TEXT,
  attempt_count INTEGER NOT NULL DEFAULT 0,
  result_json TEXT,
  last_error TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  completed_at INTEGER,
  reported_at INTEGER,
  PRIMARY KEY (job_id, item_id)
);
INSERT INTO threads (id, rollout_path, created_at, updated_at, source, model_provider, cwd, title, sandbox_policy, approval_mode, archived, created_at_ms, updated_at_ms, preview)
VALUES
  ('thread-a', '${rolloutA.replaceAll("'", "''")}', 1, 2, 'exec', 'openai', '/tmp', 'Thread A', 'workspace-write', 'never', 0, 1000, 2000, 'Thread A preview'),
  ('thread-b', '${rolloutB.replaceAll("'", "''")}', 1, 3, 'exec', 'openai', '/tmp', 'Thread B', 'workspace-write', 'never', 0, 1000, 3000, 'Thread B preview'),
  ('thread-c', '${archivedRolloutC.replaceAll("'", "''")}', 1, 4, 'exec', 'openai', '/tmp', 'Thread C', 'workspace-write', 'never', 0, 1000, 4000, 'Thread C preview');
INSERT INTO thread_dynamic_tools (thread_id, position, name, description, input_schema) VALUES ('thread-a', 0, 'tool-a', 'Tool A', '{}'), ('thread-b', 0, 'tool-b', 'Tool B', '{}'), ('thread-c', 0, 'tool-c', 'Tool C', '{}');
INSERT INTO agent_jobs (id, name, status, instruction, input_headers_json, input_csv_path, output_csv_path, created_at, updated_at) VALUES ('job-a', 'Job A', 'pending', 'instruction', '{}', '/tmp/in.csv', '/tmp/out.csv', 1, 1);
`);

  runSqlite(path.join(sourceHome, "goals_1.sqlite"), `
CREATE TABLE thread_goals (
  thread_id TEXT PRIMARY KEY NOT NULL,
  goal_id TEXT NOT NULL,
  objective TEXT NOT NULL,
  status TEXT NOT NULL,
  token_budget INTEGER,
  tokens_used INTEGER NOT NULL DEFAULT 0,
  time_used_seconds INTEGER NOT NULL DEFAULT 0,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
);
INSERT INTO thread_goals (thread_id, goal_id, objective, status, created_at_ms, updated_at_ms)
VALUES ('thread-a', 'goal-a', 'Objective A', 'active', 1, 1),
       ('thread-b', 'goal-b', 'Objective B', 'active', 1, 1),
       ('thread-c', 'goal-c', 'Objective C', 'active', 1, 1);
`);
  return { sourceHome, rolloutA, rolloutB };
}

test("parseArgs resolves create paths and defaults source home from environment", () => {
  const options = parseArgs([
    "create",
    "--output-home", "out-home",
    "--thread-id", "thread-a",
    "--thread-count", "2",
    "--json-out", "meta.json",
  ], { CODEX_HOME: "/tmp/source-home" });

  assert.equal(options.sourceHome, "/tmp/source-home");
  assert.equal(options.outputHome.endsWith("out-home"), true);
  assert.equal(options.threadID, "thread-a");
  assert.equal(options.threadCount, 2);
  assert.equal(options.jsonOut.endsWith("meta.json"), true);
});

test("createIsolatedHome clones one active thread and rewrites rollout path", { skip: !hasSqlite() }, () => {
  const root = tempDir();
  const { sourceHome, rolloutA } = writeSourceHome(root);
  const outputHome = path.join(root, "isolated-home");
  const jsonOut = path.join(root, "metadata.json");

  const metadata = createIsolatedHome({
    sourceHome,
    outputHome,
    threadID: "thread-a",
    maxRolloutBytes: 100_000,
    jsonOut,
    force: false,
  });

  assert.equal(metadata.threadID, "thread-a");
  assert.deepEqual(metadata.threadIDs, ["thread-a"]);
  assert.equal(metadata.threadCount, 1);
  assert.equal(metadata.sourceRolloutPath, rolloutA);
  assert.equal(metadata.rolloutPath.startsWith(outputHome), true);
  assert.equal(fs.existsSync(metadata.rolloutPath), true);
  assert.equal(metadata.threads.length, 1);
  assert.equal(fs.existsSync(jsonOut), true);

  const rows = sqliteJSON(path.join(outputHome, "state_5.sqlite"), "SELECT id, archived, rollout_path FROM threads ORDER BY id;");
  assert.deepEqual(rows, [
    {
      id: "thread-a",
      archived: 0,
      rollout_path: metadata.rolloutPath,
    },
  ]);
  const tools = sqliteJSON(path.join(outputHome, "state_5.sqlite"), "SELECT thread_id, name FROM thread_dynamic_tools;");
  assert.deepEqual(tools, [{ thread_id: "thread-a", name: "tool-a" }]);
  const jobs = sqliteJSON(path.join(outputHome, "state_5.sqlite"), "SELECT id FROM agent_jobs;");
  assert.deepEqual(jobs, []);
  const goals = sqliteJSON(path.join(outputHome, "goals_1.sqlite"), "SELECT thread_id, goal_id FROM thread_goals;");
  assert.deepEqual(goals, [{ thread_id: "thread-a", goal_id: "goal-a" }]);
});

test("createIsolatedHome can clone multiple active threads for full-list UI proof", { skip: !hasSqlite() }, () => {
  const root = tempDir();
  writeSourceHome(root);
  const sourceHome = path.join(root, "source-home");
  const outputHome = path.join(root, "isolated-home");

  const metadata = createIsolatedHome({
    sourceHome,
    outputHome,
    threadID: null,
    threadCount: 2,
    maxRolloutBytes: 100_000,
    jsonOut: null,
    force: false,
  });

  assert.equal(metadata.threadCount, 2);
  assert.deepEqual(metadata.threadIDs, ["thread-b", "thread-a"]);
  assert.equal(metadata.threadID, "thread-b");
  assert.equal(metadata.threads.length, 2);
  assert.equal(metadata.threads.every((thread) => fs.existsSync(thread.rolloutPath)), true);

  const rows = sqliteJSON(path.join(outputHome, "state_5.sqlite"), "SELECT id, archived, rollout_path FROM threads ORDER BY updated_at_ms DESC;");
  assert.deepEqual(rows.map((row) => row.id), ["thread-b", "thread-a"]);
  assert.equal(rows.every((row) => row.archived === 0), true);
  assert.equal(rows.every((row) => row.rollout_path.startsWith(outputHome)), true);

  const tools = sqliteJSON(path.join(outputHome, "state_5.sqlite"), "SELECT thread_id, name FROM thread_dynamic_tools ORDER BY thread_id;");
  assert.deepEqual(tools, [
    { thread_id: "thread-a", name: "tool-a" },
    { thread_id: "thread-b", name: "tool-b" },
  ]);
  const goals = sqliteJSON(path.join(outputHome, "goals_1.sqlite"), "SELECT thread_id, goal_id FROM thread_goals ORDER BY thread_id;");
  assert.deepEqual(goals, [
    { thread_id: "thread-a", goal_id: "goal-a" },
    { thread_id: "thread-b", goal_id: "goal-b" },
  ]);
});

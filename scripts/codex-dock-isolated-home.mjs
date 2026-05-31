#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

function usage() {
  return [
    "Usage: node scripts/codex-dock-isolated-home.mjs create --output-home <path> [options]",
    "",
    "Options:",
    "  --source-home <path>        Source Codex home. Defaults to CODEX_HOME or ~/.codex.",
    "  --thread-id <id>           Clone a specific active thread.",
    "  --thread-count <n>         Number of active threads to clone. Defaults to 1.",
    "  --max-rollout-bytes <n>    Maximum rollout JSONL size to clone. Defaults to 3000000.",
    "  --json-out <path>          Write metadata JSON.",
    "  --force                    Remove output home first if it already exists.",
  ].join("\n");
}

function readValue(args, index, name) {
  const value = args[index + 1];
  if (!value || value.startsWith("--")) {
    throw new Error(`${name} requires a value`);
  }
  return value;
}

function parseArgs(argv = process.argv.slice(2), env = process.env) {
  const [command, ...rest] = argv;
  if (command !== "create") {
    throw new Error(usage());
  }
  const options = {
    sourceHome: env.CODEX_HOME || path.join(os.homedir(), ".codex"),
    outputHome: null,
    threadID: null,
    threadCount: 1,
    maxRolloutBytes: 3_000_000,
    jsonOut: null,
    force: false,
  };
  for (let index = 0; index < rest.length; index += 1) {
    const arg = rest[index];
    if (arg === "--source-home") {
      options.sourceHome = readValue(rest, index, arg);
      index += 1;
    } else if (arg.startsWith("--source-home=")) {
      options.sourceHome = arg.slice("--source-home=".length);
    } else if (arg === "--output-home") {
      options.outputHome = readValue(rest, index, arg);
      index += 1;
    } else if (arg.startsWith("--output-home=")) {
      options.outputHome = arg.slice("--output-home=".length);
    } else if (arg === "--thread-id") {
      options.threadID = readValue(rest, index, arg);
      index += 1;
    } else if (arg.startsWith("--thread-id=")) {
      options.threadID = arg.slice("--thread-id=".length);
    } else if (arg === "--thread-count") {
      options.threadCount = Number(readValue(rest, index, arg));
      index += 1;
    } else if (arg.startsWith("--thread-count=")) {
      options.threadCount = Number(arg.slice("--thread-count=".length));
    } else if (arg === "--max-rollout-bytes") {
      options.maxRolloutBytes = Number(readValue(rest, index, arg));
      index += 1;
    } else if (arg.startsWith("--max-rollout-bytes=")) {
      options.maxRolloutBytes = Number(arg.slice("--max-rollout-bytes=".length));
    } else if (arg === "--json-out") {
      options.jsonOut = readValue(rest, index, arg);
      index += 1;
    } else if (arg.startsWith("--json-out=")) {
      options.jsonOut = arg.slice("--json-out=".length);
    } else if (arg === "--force") {
      options.force = true;
    } else if (arg === "--help" || arg === "-h") {
      console.log(usage());
      process.exit(0);
    } else {
      throw new Error(`unknown option: ${arg}`);
    }
  }
  if (!options.outputHome) {
    throw new Error("--output-home is required");
  }
  if (!Number.isFinite(options.maxRolloutBytes) || options.maxRolloutBytes <= 0) {
    throw new Error("--max-rollout-bytes must be a positive number");
  }
  if (!Number.isInteger(options.threadCount) || options.threadCount <= 0) {
    throw new Error("--thread-count must be a positive integer");
  }
  return {
    ...options,
    sourceHome: path.resolve(options.sourceHome),
    outputHome: path.resolve(options.outputHome),
    jsonOut: options.jsonOut ? path.resolve(options.jsonOut) : null,
  };
}

function runSqlite(args, { input = null } = {}) {
  try {
    return execFileSync("sqlite3", args, {
      input,
      encoding: "utf8",
      stdio: ["pipe", "pipe", "pipe"],
    });
  } catch (error) {
    const stderr = error.stderr ? String(error.stderr).trim() : "";
    throw new Error(stderr || error.message);
  }
}

function sqliteJSON(dbPath, sql) {
  const output = runSqlite(["-json", dbPath, sql]);
  return output.trim() ? JSON.parse(output) : [];
}

function quoteSQL(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function ensureInsideHome(home, filePath) {
  const resolvedHome = path.resolve(home);
  const resolvedFile = path.resolve(filePath);
  const relative = path.relative(resolvedHome, resolvedFile);
  if (relative.startsWith("..") || path.isAbsolute(relative)) {
    throw new Error(`rollout path is outside source home: ${filePath}`);
  }
  return relative;
}

function isActiveSessionRolloutRelative(relative) {
  return relative.split(path.sep)[0] === "sessions";
}

function selectThread(options) {
  return selectThreads({ ...options, threadCount: 1 })[0];
}

function selectThreads(options) {
  const threadCount = options.threadCount ?? 1;
  const stateDb = path.join(options.sourceHome, "state_5.sqlite");
  if (!fs.existsSync(stateDb)) {
    throw new Error(`missing source state database: ${stateDb}`);
  }
  const selected = [];
  function addCandidates(where, limit) {
    if (selected.length >= threadCount) {
      return;
    }
    const selectedIDs = new Set(selected.map((thread) => thread.id));
    const candidates = sqliteJSON(
      stateDb,
      `SELECT id, rollout_path AS rolloutPath, archived, COALESCE(updated_at_ms, updated_at * 1000) AS updatedAtMs FROM threads WHERE ${where} ORDER BY updatedAtMs DESC LIMIT ${Number(limit)};`,
    );
    for (const candidate of candidates) {
      if (selected.length >= threadCount) {
        return;
      }
      if (selectedIDs.has(candidate.id) || candidate.archived === 1) {
        continue;
      }
      if (!candidate.id || !candidate.rolloutPath || !fs.existsSync(candidate.rolloutPath)) {
        continue;
      }
      const relative = ensureInsideHome(options.sourceHome, candidate.rolloutPath);
      if (!isActiveSessionRolloutRelative(relative)) {
        continue;
      }
      const size = fs.statSync(candidate.rolloutPath).size;
      if (size <= options.maxRolloutBytes) {
        selected.push({ ...candidate, rolloutBytes: size });
        selectedIDs.add(candidate.id);
      }
    }
  }

  if (options.threadID) {
    addCandidates(`id = ${quoteSQL(options.threadID)}`, 1);
  }
  addCandidates(
    "archived = 0 AND rollout_path IS NOT NULL AND rollout_path <> '' AND preview <> ''",
    Math.max(200, threadCount * 10),
  );
  if (selected.length < threadCount) {
    throw new Error(options.threadID
      ? `could not clone ${threadCount} active threads including requested thread ${options.threadID}`
      : `could not find ${threadCount} active threads with existing rollouts under ${options.maxRolloutBytes} bytes`);
  }
  return selected;
}

function backupSqlite(sourceDb, outputDb) {
  if (!fs.existsSync(sourceDb)) {
    return false;
  }
  fs.mkdirSync(path.dirname(outputDb), { recursive: true });
  runSqlite([sourceDb, `.backup ${quoteSQL(outputDb)}`]);
  return true;
}

function cloneRollout({ sourceHome, outputHome, sourceRollout }) {
  const relative = ensureInsideHome(sourceHome, sourceRollout);
  const outputRollout = path.join(outputHome, relative);
  fs.mkdirSync(path.dirname(outputRollout), { recursive: true });
  fs.copyFileSync(sourceRollout, outputRollout);
  return { relative, outputRollout };
}

function sqlInList(values) {
  return values.map(quoteSQL).join(", ");
}

function pruneState({ outputHome, rollouts }) {
  const stateDb = path.join(outputHome, "state_5.sqlite");
  const threadIDs = rollouts.map((rollout) => rollout.threadID);
  const updateSQL = rollouts.map((rollout) => `
UPDATE threads
SET archived = 0,
    archived_at = NULL,
    rollout_path = ${quoteSQL(rollout.outputRollout)}
WHERE id = ${quoteSQL(rollout.threadID)};
`).join("\n");
  const sql = `
PRAGMA foreign_keys = OFF;
DELETE FROM thread_dynamic_tools WHERE thread_id NOT IN (${sqlInList(threadIDs)});
DELETE FROM thread_spawn_edges WHERE parent_thread_id NOT IN (${sqlInList(threadIDs)}) OR child_thread_id NOT IN (${sqlInList(threadIDs)});
DELETE FROM agent_job_items;
DELETE FROM agent_jobs;
DELETE FROM remote_control_enrollments;
DELETE FROM threads WHERE id NOT IN (${sqlInList(threadIDs)});
${updateSQL}
VACUUM;
`;
  runSqlite([stateDb], { input: sql });
}

function pruneGoals({ outputHome, threadIDs }) {
  const goalsDb = path.join(outputHome, "goals_1.sqlite");
  if (!fs.existsSync(goalsDb)) {
    return;
  }
  runSqlite([goalsDb], {
    input: `DELETE FROM thread_goals WHERE thread_id NOT IN (${sqlInList(threadIDs)});\nVACUUM;\n`,
  });
}

function createIsolatedHome(options) {
  const selectedThreads = selectThreads(options);
  if (fs.existsSync(options.outputHome)) {
    if (!options.force) {
      throw new Error(`output home already exists: ${options.outputHome}`);
    }
    fs.rmSync(options.outputHome, { recursive: true, force: true });
  }
  fs.mkdirSync(options.outputHome, { recursive: true });

  const stateCopied = backupSqlite(
    path.join(options.sourceHome, "state_5.sqlite"),
    path.join(options.outputHome, "state_5.sqlite"),
  );
  if (!stateCopied) {
    throw new Error("source state_5.sqlite was not copied");
  }
  backupSqlite(
    path.join(options.sourceHome, "goals_1.sqlite"),
    path.join(options.outputHome, "goals_1.sqlite"),
  );
  const rollouts = selectedThreads.map((selected) => ({
    threadID: selected.id,
    selected,
    ...cloneRollout({
      sourceHome: options.sourceHome,
      outputHome: options.outputHome,
      sourceRollout: selected.rolloutPath,
    }),
  }));
  pruneState({
    outputHome: options.outputHome,
    rollouts,
  });
  pruneGoals({ outputHome: options.outputHome, threadIDs: rollouts.map((rollout) => rollout.threadID) });

  const metadata = {
    version: 1,
    generatedAt: new Date().toISOString(),
    sourceHome: options.sourceHome,
    outputHome: options.outputHome,
    threadID: selectedThreads[0].id,
    threadIDs: selectedThreads.map((thread) => thread.id),
    threadCount: selectedThreads.length,
    sourceRolloutPath: selectedThreads[0].rolloutPath,
    rolloutPath: rollouts[0].outputRollout,
    rolloutRelativePath: rollouts[0].relative,
    rolloutBytes: selectedThreads[0].rolloutBytes,
    threads: rollouts.map((rollout) => ({
      threadID: rollout.threadID,
      sourceRolloutPath: rollout.selected.rolloutPath,
      rolloutPath: rollout.outputRollout,
      rolloutRelativePath: rollout.relative,
      rolloutBytes: rollout.selected.rolloutBytes,
    })),
    stateDbPath: path.join(options.outputHome, "state_5.sqlite"),
    goalsDbPath: fs.existsSync(path.join(options.outputHome, "goals_1.sqlite"))
      ? path.join(options.outputHome, "goals_1.sqlite")
      : null,
  };
  if (options.jsonOut) {
    fs.mkdirSync(path.dirname(options.jsonOut), { recursive: true });
    fs.writeFileSync(options.jsonOut, `${JSON.stringify(metadata, null, 2)}\n`);
  }
  return metadata;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  try {
    const metadata = createIsolatedHome(parseArgs());
    console.log(JSON.stringify(metadata));
  } catch (error) {
    console.error(error?.message || String(error));
    process.exit(1);
  }
}

export {
  createIsolatedHome,
  parseArgs,
  selectThread,
  selectThreads,
};

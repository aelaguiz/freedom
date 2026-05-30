import assert from "node:assert/strict";
import test from "node:test";

import {
  compareDockSessionToRelay,
  compareRelayThreadToStorage,
  expectedDockLaneForSource,
  normalizedStatus,
  normalizedThreadSourceForFidelity,
  parseArgs,
  sourceReport,
  textFingerprint,
} from "./dock-relay-thread-fidelity.mjs";

test("thread fidelity text fingerprints do not expose prompt text", () => {
  const fingerprint = textFingerprint("private user prompt");

  assert.equal(fingerprint.present, true);
  assert.equal(fingerprint.bytes, Buffer.byteLength("private user prompt", "utf8"));
  assert.equal(fingerprint.sha256.length, 12);
  assert.equal(JSON.stringify(fingerprint).includes("private user prompt"), false);
});

test("thread fidelity source classification matches dock relay source families", () => {
  assert.deepEqual(
    normalizedThreadSourceForFidelity({ source: "cli" }),
    { kind: "cli" },
  );
  assert.deepEqual(
    normalizedThreadSourceForFidelity({ source: "mcp" }),
    { kind: "appServer" },
  );
  assert.deepEqual(
    normalizedThreadSourceForFidelity({ source: "exec" }),
    { kind: "exec" },
  );
  assert.deepEqual(
    normalizedThreadSourceForFidelity({ source: { subagent: { thread_spawn: { parent_thread_id: "parent" } } } }),
    { kind: "subAgent", variant: "threadSpawn" },
  );
  assert.deepEqual(
    expectedDockLaneForSource({ kind: "unknown" }),
    { lane: "agent", sourceKind: "automation" },
  );
});

test("source report summarizes structured source without dumping raw JSON", () => {
  const report = sourceReport({
    subagent: {
      thread_spawn: {
        parent_thread_id: "parent-thread",
        instruction: "private task text",
      },
    },
  });

  assert.deepEqual(report.normalized, { kind: "subAgent", variant: "threadSpawn" });
  assert.deepEqual(report.keys, ["subagent"]);
  assert.equal(report.sha256.length, 12);
  assert.equal(JSON.stringify(report).includes("private task text"), false);
});

test("relay-to-storage comparison detects source and fork mismatches", () => {
  const storage = {
    stateRow: {
      id: "thread-1",
      rollout_path: "/tmp/rollout-thread-1.jsonl",
      source: "cli",
      thread_source: "user",
      cwd: "/repo",
      model_provider: "openai",
      cli_version: "1.0.0",
      updated_at: 1_780_000_100,
      created_at: 1_780_000_000,
    },
    rollout: {
      path: "/tmp/rollout-thread-1.jsonl",
      exists: true,
      sessionMetaPayload: {
        id: "thread-1",
        cwd: "/repo",
        model_provider: "openai",
        cli_version: "1.0.0",
        source: "cli",
        thread_source: "user",
        forked_from_id: "parent-thread",
      },
      firstUserMessage: null,
    },
    sessionIndex: null,
  };
  const relayThread = {
    id: "thread-1",
    cwd: "/other-repo",
    modelProvider: "openai",
    cliVersion: "1.0.0",
    source: "exec",
    threadSource: "subagent",
    forkedFromId: "other-parent",
    status: { type: "notLoaded" },
  };

  const findings = compareRelayThreadToStorage("thread-1", relayThread, storage, new Set());

  assert.ok(findings.some((finding) => finding.field === "cwd" && finding.severity === "error"));
  assert.ok(findings.some((finding) => finding.field === "source" && finding.severity === "error"));
  assert.ok(findings.some((finding) => finding.field === "forkedFromId" && finding.severity === "error"));
  assert.equal(JSON.stringify(findings).includes("private"), false);
});

test("dock snapshot comparison checks client-visible row fields", () => {
  const storage = {
    stateRow: {
      id: "thread-1",
      rollout_path: "/tmp/rollout-thread-1.jsonl",
      source: "cli",
      thread_source: "user",
      cwd: "/repo",
      model_provider: "openai",
      cli_version: "1.0.0",
      updated_at: 1_780_000_100,
      created_at: 1_780_000_000,
      git_branch: "main",
    },
    rollout: {
      path: "/tmp/rollout-thread-1.jsonl",
      exists: true,
      sessionMetaPayload: {
        id: "thread-1",
        cwd: "/repo",
        source: "cli",
        thread_source: "user",
      },
    },
    sessionIndex: null,
  };
  const relayThread = {
    id: "thread-1",
    sessionId: "session-1",
    cwd: "/repo",
    preview: "private title",
    latestSummary: "private summary",
    updatedAt: 1_780_000_100,
    status: { type: "idle" },
    source: "cli",
    threadSource: "user",
    gitInfo: {
      branch: "main",
      originUrl: "git@github.com:aelaguiz/codex-client.git",
    },
  };
  const dockSession = {
    id: "host::thread-1",
    hostID: "host",
    threadID: "thread-1",
    backendSessionID: "session-1",
    title: "private title",
    status: "running",
    lane: "agent",
    repository: "wrong",
    workingDirectory: "/repo",
    branch: "main",
    updatedAt: 1_780_000_100,
    summary: "private summary",
    source: { kind: "automation" },
  };

  const findings = compareDockSessionToRelay("thread-1", dockSession, relayThread, storage);

  assert.equal(normalizedStatus(relayThread), "idle");
  assert.ok(findings.some((finding) => finding.field === "status" && finding.severity === "error"));
  assert.ok(findings.some((finding) => finding.field === "lane" && finding.severity === "error"));
  assert.ok(findings.some((finding) => finding.field === "source.kind" && finding.severity === "error"));
  assert.equal(JSON.stringify(findings).includes("private title"), false);
  assert.equal(JSON.stringify(findings).includes("private summary"), false);
});

test("parseArgs expands dock IDs and clamps relay page size", () => {
  const parsed = parseArgs(
    [
      "--limit",
      "999",
      "--max-threads=3",
      "--thread-id",
      "host::thread-1,thread-2",
      "--include-archived",
    ],
    {
      CODEX_DOCK_RELAY_WS: "ws://relay.example:4510",
      CODEX_HOME: "~/custom-codex",
    },
    "/tmp",
  );

  assert.equal(parsed.limit, 250);
  assert.equal(parsed.maxThreads, 3);
  assert.deepEqual(parsed.threadIDs, ["thread-1", "thread-2"]);
  assert.equal(parsed.includeArchived, true);
});

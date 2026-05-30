import assert from "node:assert/strict";
import test from "node:test";

import {
  compareRelaySnapshotToSQLite,
  expectedScopeNamesForSQLiteThread,
  expectedSourceScopeNamesForSQLiteThread,
  goalRowsChangeCounts,
  parseArgs,
  sanitizeSQLiteThread,
  threadSpawnParentIDFromSource,
} from "./dock-relay-state-parity.mjs";

test("state parity maps SQLite source values to expected app-server scopes", () => {
  const scopes = [
    "interactiveDefault",
    "allSourceKinds",
    "cli",
    "vscode",
    "exec",
    "appServer",
    "subAgent",
    "subAgentReview",
    "subAgentCompact",
    "subAgentThreadSpawn",
    "subAgentOther",
    "unknown",
  ];

  assert.deepEqual(
    expectedSourceScopeNamesForSQLiteThread({ source: "cli", thread_source: "user" }, scopes),
    ["interactiveDefault", "allSourceKinds", "cli"],
  );
  assert.deepEqual(
    expectedSourceScopeNamesForSQLiteThread({
      source: JSON.stringify({
        subagent: {
          thread_spawn: {
            parent_thread_id: "parent",
            instruction: "private task text",
          },
        },
      }),
      thread_source: "subagent",
    }, scopes),
    ["allSourceKinds", "subAgent", "subAgentThreadSpawn"],
  );
  assert.deepEqual(
    expectedSourceScopeNamesForSQLiteThread({ source: "unknown", thread_source: "memory_consolidation" }, scopes),
    [],
  );
});

test("state parity reports SQLite rows missing from relay without exposing prompt text", () => {
  const snapshot = {
    complete: true,
    scopes: [
      {
        name: "active:interactiveDefault",
        sourceScope: "interactiveDefault",
        complete: true,
        rows: [
          {
            ordinal: 0,
            thread: {
              id: "thread-present",
              source: "cli",
              threadSource: "user",
              cwd: "/repo",
              path: "/tmp/rollout-thread-present.jsonl",
              modelProvider: "openai",
              status: { type: "notLoaded" },
              preview: "private visible text",
            },
          },
        ],
        threadIDsInCodexOrder: ["thread-present"],
      },
      {
        name: "active:cli",
        sourceScope: "cli",
        complete: true,
        rows: [
          {
            ordinal: 0,
            thread: {
              id: "thread-present",
              source: "cli",
              threadSource: "user",
              cwd: "/repo",
              path: "/tmp/rollout-thread-present.jsonl",
              modelProvider: "openai",
              status: { type: "notLoaded" },
              preview: "private visible text",
            },
          },
        ],
        threadIDsInCodexOrder: ["thread-present"],
      },
    ],
    threads: [
      {
        threadID: "thread-present",
        appearances: [
          { scope: "active:interactiveDefault", archive: "active", archived: false, sourceScope: "interactiveDefault" },
          { scope: "active:cli", archive: "active", archived: false, sourceScope: "cli" },
        ],
      },
    ],
    loaded: { complete: true, threadIDs: [] },
  };
  const sqliteBefore = {
    ok: true,
    rows: [
      {
        id: "thread-present",
        source: "cli",
        thread_source: "user",
        archived: 0,
        cwd: "/repo",
        rollout_path: "/tmp/rollout-thread-present.jsonl",
        model_provider: "openai",
        preview: "private visible text",
      },
      {
        id: "thread-missing",
        source: "cli",
        thread_source: "user",
        archived: 0,
        cwd: "/repo",
        rollout_path: "/tmp/rollout-thread-missing.jsonl",
        model_provider: "openai",
        title: "private missing title",
        preview: "private missing preview",
        first_user_message: "private missing prompt",
      },
    ],
  };
  const sqliteAfter = sqliteBefore;

  const report = compareRelaySnapshotToSQLite(
    snapshot,
    sqliteBefore,
    sqliteAfter,
    { ok: true, count: 0 },
    [],
    { includeThreadReads: false, includeLoaded: true },
  );

  assert.equal(report.summary.missingFromRelay, 1);
  assert.ok(report.findings.some((finding) => finding.threadID === "thread-missing" && finding.severity === "error"));
  const serialized = JSON.stringify(report);
  assert.equal(serialized.includes("private missing title"), false);
  assert.equal(serialized.includes("private missing preview"), false);
  assert.equal(serialized.includes("private missing prompt"), false);
  assert.equal(serialized.includes("private visible text"), false);
});

test("state parity marks previewless SQLite rows as outside current app-server list discovery", () => {
  const snapshot = {
    complete: true,
    scopes: [
      {
        name: "active:interactiveDefault",
        sourceScope: "interactiveDefault",
        complete: true,
        rows: [],
        threadIDsInCodexOrder: [],
      },
      {
        name: "active:allSourceKinds",
        sourceScope: "allSourceKinds",
        complete: true,
        rows: [],
        threadIDsInCodexOrder: [],
      },
      {
        name: "active:cli",
        sourceScope: "cli",
        complete: true,
        rows: [],
        threadIDsInCodexOrder: [],
      },
    ],
    threads: [],
    loaded: { complete: true, threadIDs: [] },
  };
  const sqlite = {
    ok: true,
    rows: [
      {
        id: "previewless-thread",
        source: "cli",
        thread_source: "user",
        archived: 0,
        preview: "",
        title: "private title",
        first_user_message: "",
      },
    ],
  };

  const report = compareRelaySnapshotToSQLite(
    snapshot,
    sqlite,
    sqlite,
    { ok: true, count: 0 },
    [{ threadID: "previewless-thread", ok: true, thread: { id: "previewless-thread", source: "cli" } }],
    { includeThreadReads: false, includeLoaded: true },
  );

  assert.equal(report.summary.missingFromRelay, 1);
  assert.equal(report.summary.missingListableFromRelay, 0);
  assert.equal(report.summary.errors, 0);
  assert.equal(report.summary.warnings, 0);
  assert.equal(report.summary.info, 2);
  assert.equal(JSON.stringify(report).includes("private title"), false);
});

test("state parity records thread/search probes without storing search terms or snippets", () => {
  const snapshot = {
    complete: true,
    scopes: [
      {
        name: "active:interactiveDefault",
        sourceScope: "interactiveDefault",
        complete: true,
        rows: [],
        threadIDsInCodexOrder: [],
      },
      {
        name: "active:allSourceKinds",
        sourceScope: "allSourceKinds",
        complete: true,
        rows: [],
        threadIDsInCodexOrder: [],
      },
    ],
    threads: [],
    loaded: { complete: true, threadIDs: [] },
  };
  const sqlite = {
    ok: true,
    rows: [
      {
        id: "previewless-thread",
        source: "cli",
        thread_source: "user",
        archived: 0,
        preview: "",
        cwd: "/private/repo/secret-project",
      },
    ],
  };

  const report = compareRelaySnapshotToSQLite(
    snapshot,
    sqlite,
    sqlite,
    { ok: true, count: 0 },
    [],
    { includeThreadReads: false, includeLoaded: true, probeMissingSearches: true },
    new Map(),
    { ok: true, rows: [] },
    null,
    [
      {
        threadID: "previewless-thread",
        sourceScope: "allSourceKinds",
        searchTermKind: "cwdBasename",
        searchTerm: { present: true, chars: 14, bytes: 14, sha256: "termhash" },
        rawSearchTerm: "private-query-term",
        ok: true,
        complete: true,
        pageCount: 1,
        resultCount: 1,
        resultThreadIDs: ["previewless-thread"],
        includesMissing: true,
        snippet: "private snippet should not be copied",
      },
    ],
  );

  assert.equal(report.summary.searchProbeAttempts, 1);
  assert.equal(report.summary.searchProbeRows, 1);
  assert.equal(report.summary.missingSearchDiscoverable, 1);
  assert.ok(report.findings.some((finding) => finding.surface === "relay.thread_search" && finding.threadID === "previewless-thread"));
  const serialized = JSON.stringify(report);
  assert.equal(serialized.includes("private-query-term"), false);
  assert.equal(serialized.includes("private snippet"), false);
});

test("state parity treats SQLite versus rollout session_meta drift as storage disagreement", () => {
  const snapshot = {
    complete: true,
    scopes: [
      {
        name: "active:cli",
        sourceScope: "cli",
        complete: true,
        rows: [
          {
            ordinal: 0,
            thread: {
              id: "thread-1",
              source: "cli",
              threadSource: "user",
              cwd: "/repo/from-session-meta",
              path: "/tmp/rollout-thread-1.jsonl",
              modelProvider: "openai",
              cliVersion: "1.2.3",
              status: { type: "notLoaded" },
              preview: "private visible text",
            },
          },
        ],
        threadIDsInCodexOrder: ["thread-1"],
      },
    ],
    threads: [
      {
        threadID: "thread-1",
        appearances: [
          { scope: "active:cli", archive: "active", archived: false, sourceScope: "cli" },
        ],
      },
    ],
    loaded: { complete: true, threadIDs: [] },
  };
  const sqlite = {
    ok: true,
    rows: [
      {
        id: "thread-1",
        source: "cli",
        thread_source: "user",
        archived: 0,
        cwd: "/repo/from-sqlite",
        rollout_path: "/tmp/rollout-thread-1.jsonl",
        model_provider: "openai",
        cli_version: "1.2.3",
        preview: "private visible text",
      },
    ],
  };
  const rolloutSessionMetaByID = new Map([
    ["thread-1", {
      ok: true,
      path: "/tmp/rollout-thread-1.jsonl",
      meta: {
        id: "thread-1",
        cwd: "/repo/from-session-meta",
        source: "cli",
        threadSource: "user",
        modelProvider: "openai",
        cliVersion: "1.2.3",
      },
    }],
  ]);

  const report = compareRelaySnapshotToSQLite(
    snapshot,
    sqlite,
    sqlite,
    { ok: true, count: 0 },
    [],
    { includeThreadReads: false, includeLoaded: true },
    rolloutSessionMetaByID,
  );

  assert.equal(report.summary.errors, 0);
  assert.equal(report.summary.storageDisagreements, 1);
  assert.equal(report.summary.storageDisagreementAlignment.total, 1);
  assert.equal(report.summary.storageDisagreementAlignment.relayMatchesRollout, 1);
  assert.deepEqual(report.summary.storageDisagreementAlignment.byField.cwd, {
    total: 1,
    relayMatchesSQLite: 0,
    relayMatchesRollout: 1,
    relayMatchesBoth: 0,
    relayMatchesNeither: 0,
  });
  assert.ok(report.findings.some((finding) => (
    finding.severity === "warning"
      && finding.surface === "codex.storage"
      && finding.field === "cwd"
      && finding.threadID === "thread-1"
  )));
  assert.equal(report.findings.some((finding) => finding.message === "relay cwd differs from SQLite cwd"), false);
});

test("state parity reports divergent relay list metadata for the same thread", () => {
  const snapshot = {
    complete: true,
    scopes: [
      {
        name: "active:interactiveDefault",
        sourceScope: "interactiveDefault",
        complete: true,
        rows: [
          {
            ordinal: 0,
            thread: {
              id: "thread-1",
              source: "cli",
              threadSource: "user",
              cwd: "/repo/a",
              path: "/tmp/rollout-thread-1.jsonl",
              modelProvider: "openai",
              status: { type: "notLoaded" },
              preview: "private visible text",
            },
          },
        ],
        threadIDsInCodexOrder: ["thread-1"],
      },
      {
        name: "active:cli",
        sourceScope: "cli",
        complete: true,
        rows: [
          {
            ordinal: 0,
            thread: {
              id: "thread-1",
              source: "cli",
              threadSource: "user",
              cwd: "/repo/b",
              path: "/tmp/rollout-thread-1.jsonl",
              modelProvider: "openai",
              status: { type: "notLoaded" },
              preview: "private visible text",
            },
          },
        ],
        threadIDsInCodexOrder: ["thread-1"],
      },
    ],
    threads: [
      {
        threadID: "thread-1",
        appearances: [
          { scope: "active:interactiveDefault", archive: "active", archived: false, sourceScope: "interactiveDefault" },
          { scope: "active:cli", archive: "active", archived: false, sourceScope: "cli" },
        ],
        surfaceSummary: {
          hasConflicts: true,
          conflictingFields: ["cwd"],
          canonicalProjection: {
            priority: [
              "routed thread/read",
              "history thread/read",
              "thread/list:allSourceKinds",
              "thread/list:interactiveDefault",
              "thread/list",
            ],
            fields: {
              cwd: {
                value: "/repo/a",
                source: { kind: "thread/list", scope: "active:interactiveDefault" },
                valueCount: 2,
                hasConflict: true,
              },
              updatedAt: {
                value: 1,
                source: { kind: "thread/list", scope: "active:interactiveDefault" },
                valueCount: 1,
                hasConflict: false,
              },
            },
          },
        },
      },
    ],
    loaded: { complete: true, threadIDs: [] },
  };
  const sqlite = {
    ok: true,
    rows: [
      {
        id: "thread-1",
        source: "cli",
        thread_source: "user",
        archived: 0,
        cwd: "/repo/a",
        rollout_path: "/tmp/rollout-thread-1.jsonl",
        model_provider: "openai",
        preview: "private visible text",
      },
    ],
  };

  const report = compareRelaySnapshotToSQLite(
    snapshot,
    sqlite,
    sqlite,
    { ok: true, count: 0 },
    [],
    { includeThreadReads: false, includeLoaded: true },
  );

  assert.equal(report.summary.listRowInconsistencies, 1);
  assert.deepEqual(report.summary.listRowInconsistencyFields, { cwd: 1 });
  assert.equal(report.summary.relayCanonicalProjection.included, true);
  assert.equal(report.summary.relayCanonicalProjection.threadsWithProjection, 1);
  assert.equal(report.summary.relayCanonicalProjection.threadsWithCanonicalConflicts, 1);
  assert.deepEqual(report.summary.relayCanonicalProjection.conflictFields, { cwd: 1 });
  assert.ok(report.findings.some((finding) => (
    finding.surface === "relay.list_rows"
      && finding.field === "cwd"
      && finding.threadID === "thread-1"
  )));
});

test("state parity checks included thread/read detail against rollout metadata", () => {
  const snapshot = {
    complete: true,
    scopes: [
      {
        name: "active:cli",
        sourceScope: "cli",
        complete: true,
        rows: [
          {
            ordinal: 0,
            thread: {
              id: "thread-1",
              source: "cli",
              threadSource: "user",
              cwd: "/repo/from-list",
              path: "/tmp/rollout-thread-1.jsonl",
              modelProvider: "openai",
              status: { type: "notLoaded" },
              preview: "private visible text",
            },
          },
        ],
        threadIDsInCodexOrder: ["thread-1"],
      },
    ],
    threads: [
      {
        threadID: "thread-1",
        appearances: [
          { scope: "active:cli", archive: "active", archived: false, sourceScope: "cli" },
        ],
        historyRead: {
          thread: {
            id: "thread-1",
            source: "cli",
            threadSource: "user",
            cwd: "/repo/from-read",
            path: "/tmp/rollout-thread-1.jsonl",
            modelProvider: "openai",
            status: { type: "notLoaded" },
          },
        },
        routedRead: {
          thread: {
            id: "thread-1",
            source: "cli",
            threadSource: "user",
            cwd: "/repo/from-read",
            path: "/tmp/rollout-thread-1.jsonl",
            modelProvider: "openai",
            status: { type: "notLoaded" },
          },
        },
      },
    ],
    loaded: { complete: true, threadIDs: [] },
  };
  const sqlite = {
    ok: true,
    rows: [
      {
        id: "thread-1",
        source: "cli",
        thread_source: "user",
        archived: 0,
        cwd: "/repo/from-list",
        rollout_path: "/tmp/rollout-thread-1.jsonl",
        model_provider: "openai",
        preview: "private visible text",
      },
    ],
  };
  const rolloutSessionMetaByID = new Map([
    ["thread-1", {
      ok: true,
      path: "/tmp/rollout-thread-1.jsonl",
      meta: {
        id: "thread-1",
        cwd: "/repo/from-read",
        source: "cli",
        threadSource: "user",
        modelProvider: "openai",
      },
    }],
  ]);

  const report = compareRelaySnapshotToSQLite(
    snapshot,
    sqlite,
    sqlite,
    { ok: true, count: 0 },
    [],
    { includeThreadReads: true, includeLoaded: true },
    rolloutSessionMetaByID,
  );

  assert.equal(report.summary.readDetailDisagreements, 0);
  assert.deepEqual(report.summary.readDetailDisagreementFields, {});
  assert.ok(report.findings.some((finding) => (
    finding.surface === "active:cli"
      && finding.field === "cwd"
      && finding.message === "relay cwd differs from rollout session_meta cwd"
  )));
  assert.equal(report.findings.some((finding) => finding.surface === "relay.history_read" && finding.field === "cwd"), false);
});

test("state parity checks included thread goal state without exposing objective text", () => {
  const snapshot = {
    complete: true,
    scopes: [
      {
        name: "active:cli",
        sourceScope: "cli",
        complete: true,
        rows: [
          {
            ordinal: 0,
            thread: {
              id: "thread-with-goal",
              source: "cli",
              threadSource: "user",
              cwd: "/repo",
              path: "/tmp/rollout-thread-with-goal.jsonl",
              modelProvider: "openai",
              status: { type: "notLoaded" },
              preview: "private visible text",
            },
          },
        ],
        threadIDsInCodexOrder: ["thread-with-goal"],
      },
    ],
    threads: [
      {
        threadID: "thread-with-goal",
        appearances: [
          { scope: "active:cli", archive: "active", archived: false, sourceScope: "cli" },
        ],
        goalRead: {
          goal: {
            threadId: "thread-with-goal",
            objective: "private goal objective",
            status: "active",
            tokenBudget: 100,
            tokensUsed: 7,
            timeUsedSeconds: 9,
            createdAt: 1770000000,
            updatedAt: 1770000001,
          },
        },
      },
    ],
    loaded: { complete: true, threadIDs: [] },
  };
  const sqlite = {
    ok: true,
    rows: [
      {
        id: "thread-with-goal",
        source: "cli",
        thread_source: "user",
        archived: 0,
        cwd: "/repo",
        rollout_path: "/tmp/rollout-thread-with-goal.jsonl",
        model_provider: "openai",
        preview: "private visible text",
      },
    ],
  };

  const report = compareRelaySnapshotToSQLite(
    snapshot,
    sqlite,
    sqlite,
    {
      ok: true,
      count: 1,
      rows: [
        {
          thread_id: "thread-with-goal",
          goal_id: "private-goal-id",
          objective: "private goal objective",
          status: "active",
          token_budget: 100,
          tokens_used: 7,
          time_used_seconds: 9,
          created_at_ms: 1770000000000,
          updated_at_ms: 1770000001000,
        },
        {
          thread_id: "orphan-goal-thread",
          goal_id: "private-orphan-goal-id",
          objective: "private orphan goal objective",
          status: "complete",
          token_budget: null,
          tokens_used: 11,
          time_used_seconds: 12,
          created_at_ms: 1770000000000,
          updated_at_ms: 1770000001000,
        },
      ],
    },
    [],
    { includeThreadReads: false, includeLoaded: true, includeGoals: true },
  );

  assert.equal(report.summary.goalParity.included, true);
  assert.equal(report.summary.goalParity.relayGoalCount, 1);
  assert.equal(report.summary.goalParity.sqliteGoalCount, 2);
  assert.equal(report.summary.goalParity.sqliteGoalsWithThreadRow, 1);
  assert.equal(report.summary.goalParity.sqliteGoalsWithoutThreadRow, 1);
  assert.equal(report.summary.goalParity.missingFromRelay, 1);
  assert.equal(report.summary.goalParity.missingFromRelayWithThreadRow, 0);
  assert.equal(report.summary.goalParity.extraInRelay, 0);
  assert.equal(report.summary.goalParity.appServerDoesNotExposeGoalID, true);
  assert.equal(report.findings.some((finding) => finding.surface === "relay.thread_goal"), false);
  assert.ok(report.findings.some((finding) => (
    finding.threadID === "orphan-goal-thread"
      && finding.surface === "codex.storage"
      && finding.field === "goal.threadID"
      && finding.severity === "info"
  )));
  assert.equal(JSON.stringify(report).includes("private goal objective"), false);
  assert.equal(JSON.stringify(report).includes("private orphan goal objective"), false);
  assert.equal(JSON.stringify(report).includes("private-goal-id"), false);
  assert.equal(JSON.stringify(report).includes("private-orphan-goal-id"), false);
});

test("state parity counts goal rows that changed during an audit", () => {
  const before = {
    ok: true,
    rows: [
      {
        thread_id: "changed-thread",
        goal_id: "private-changed-goal-id",
        objective: "private changed objective",
        status: "active",
        token_budget: 100,
        tokens_used: 1,
        time_used_seconds: 2,
        created_at_ms: 1770000000000,
        updated_at_ms: 1770000001000,
      },
      {
        thread_id: "removed-thread",
        goal_id: "private-removed-goal-id",
        objective: "private removed objective",
        status: "active",
        token_budget: null,
        tokens_used: 3,
        time_used_seconds: 4,
        created_at_ms: 1770000000000,
        updated_at_ms: 1770000001000,
      },
    ],
  };
  const after = {
    ok: true,
    rows: [
      {
        thread_id: "changed-thread",
        goal_id: "private-changed-goal-id",
        objective: "private changed objective",
        status: "active",
        token_budget: 100,
        tokens_used: 2,
        time_used_seconds: 2,
        created_at_ms: 1770000000000,
        updated_at_ms: 1770000002000,
      },
      {
        thread_id: "added-thread",
        goal_id: "private-added-goal-id",
        objective: "private added objective",
        status: "complete",
        token_budget: null,
        tokens_used: 5,
        time_used_seconds: 6,
        created_at_ms: 1770000000000,
        updated_at_ms: 1770000001000,
      },
    ],
  };

  assert.deepEqual(goalRowsChangeCounts(before, after), {
    stable: false,
    added: 1,
    removed: 1,
    changed: 1,
  });
});

test("state parity compares spawned parent edge with relay source parent", () => {
  const source = {
    subAgent: {
      threadSpawn: {
        parentThreadId: "parent-thread",
        agentNickname: "private nickname",
      },
    },
  };
  const snapshot = {
    complete: true,
    scopes: [
      {
        name: "active:subAgentThreadSpawn",
        archive: "active",
        archived: false,
        sourceScope: "subAgentThreadSpawn",
        complete: true,
        rows: [
          {
            ordinal: 0,
            thread: {
              id: "child-thread",
              source,
              threadSource: "subagent",
              cwd: "/repo",
              path: "/tmp/child.jsonl",
              modelProvider: "openai",
              status: { type: "notLoaded" },
              preview: "private child prompt",
            },
          },
        ],
        threadIDsInCodexOrder: ["child-thread"],
      },
    ],
    threads: [
      {
        threadID: "child-thread",
        appearances: [
          { scope: "active:subAgentThreadSpawn", archive: "active", archived: false, sourceScope: "subAgentThreadSpawn" },
        ],
      },
    ],
    loaded: { complete: true, threadIDs: [] },
  };
  const sqlite = {
    ok: true,
    rows: [
      {
        id: "child-thread",
        source: JSON.stringify({
          subagent: {
            thread_spawn: {
              parent_thread_id: "parent-thread",
              agent_nickname: "private nickname",
            },
          },
        }),
        thread_source: "subagent",
        archived: 0,
        cwd: "/repo",
        rollout_path: "/tmp/child.jsonl",
        model_provider: "openai",
        preview: "private child prompt",
      },
    ],
  };

  const report = compareRelaySnapshotToSQLite(
    snapshot,
    sqlite,
    sqlite,
    { ok: true, count: 0, rows: [] },
    [],
    { includeThreadReads: false, includeLoaded: true },
    new Map(),
    {
      ok: true,
      rows: [
        {
          parent_thread_id: "parent-thread",
          child_thread_id: "child-thread",
          status: "open",
        },
      ],
    },
  );

  assert.equal(threadSpawnParentIDFromSource(source), "parent-thread");
  assert.equal(report.summary.spawnParity.included, true);
  assert.equal(report.summary.spawnParity.sqliteSpawnEdgeCount, 1);
  assert.equal(report.summary.spawnParity.sqliteSpawnEdgesWithRelayChild, 1);
  assert.equal(report.summary.spawnParity.parentMismatches, 0);
  assert.equal(report.summary.spawnParity.relaySourceParentsWithoutEdge, 0);
  assert.equal(report.findings.some((finding) => finding.surface === "relay.spawn_edges"), false);
  assert.equal(JSON.stringify(report).includes("private child prompt"), false);
  assert.equal(JSON.stringify(report).includes("private nickname"), false);
});

test("state parity reports spawned parent mismatch without leaking prompt text", () => {
  const snapshot = {
    complete: true,
    scopes: [
      {
        name: "active:subAgentThreadSpawn",
        archive: "active",
        archived: false,
        sourceScope: "subAgentThreadSpawn",
        complete: true,
        rows: [
          {
            ordinal: 0,
            thread: {
              id: "child-thread",
              source: {
                subAgent: {
                  threadSpawn: {
                    parentThreadId: "wrong-parent",
                  },
                },
              },
              threadSource: "subagent",
              cwd: "/repo",
              path: "/tmp/child.jsonl",
              modelProvider: "openai",
              status: { type: "notLoaded" },
              preview: "private child prompt",
            },
          },
        ],
        threadIDsInCodexOrder: ["child-thread"],
      },
    ],
    threads: [
      {
        threadID: "child-thread",
        appearances: [
          { scope: "active:subAgentThreadSpawn", archive: "active", archived: false, sourceScope: "subAgentThreadSpawn" },
        ],
      },
    ],
    loaded: { complete: true, threadIDs: [] },
  };
  const sqlite = {
    ok: true,
    rows: [
      {
        id: "child-thread",
        source: JSON.stringify({
          subagent: {
            thread_spawn: {
              parent_thread_id: "parent-thread",
            },
          },
        }),
        thread_source: "subagent",
        archived: 0,
        cwd: "/repo",
        rollout_path: "/tmp/child.jsonl",
        model_provider: "openai",
        preview: "private child prompt",
      },
    ],
  };

  const report = compareRelaySnapshotToSQLite(
    snapshot,
    sqlite,
    sqlite,
    { ok: true, count: 0, rows: [] },
    [],
    { includeThreadReads: false, includeLoaded: true },
    new Map(),
    {
      ok: true,
      rows: [
        {
          parent_thread_id: "parent-thread",
          child_thread_id: "child-thread",
          status: "open",
        },
      ],
    },
  );

  assert.equal(report.summary.spawnParity.parentMismatches, 1);
  assert.ok(report.findings.some((finding) => (
    finding.threadID === "child-thread"
      && finding.surface === "active:subAgentThreadSpawn"
      && finding.field === "source.parentThreadID"
      && finding.severity === "error"
  )));
  assert.equal(JSON.stringify(report).includes("private child prompt"), false);
});

test("state parity reports dock/subscribe missing active listable rows", () => {
  const snapshot = {
    complete: true,
    scopes: [
      {
        name: "active:cli",
        archive: "active",
        archived: false,
        sourceScope: "cli",
        complete: true,
        rows: [
          {
            ordinal: 0,
            thread: {
              id: "visible-thread",
              source: "cli",
              threadSource: "user",
              cwd: "/repo",
              path: "/tmp/visible.jsonl",
              modelProvider: "openai",
              status: { type: "notLoaded" },
              preview: "private prompt",
            },
          },
        ],
        threadIDsInCodexOrder: ["visible-thread"],
      },
    ],
    threads: [
      {
        threadID: "visible-thread",
        appearances: [
          { scope: "active:cli", archive: "active", archived: false, sourceScope: "cli" },
        ],
      },
    ],
    loaded: { complete: true, threadIDs: [] },
  };
  const sqlite = {
    ok: true,
    rows: [
      {
        id: "visible-thread",
        source: "cli",
        thread_source: "user",
        archived: 0,
        cwd: "/repo",
        rollout_path: "/tmp/visible.jsonl",
        model_provider: "openai",
        preview: "private prompt",
      },
    ],
  };

  const report = compareRelaySnapshotToSQLite(
    snapshot,
    sqlite,
    sqlite,
    { ok: true, count: 0, rows: [] },
    [],
    { includeThreadReads: false, includeLoaded: true },
    new Map(),
    { ok: true, rows: [] },
    { kind: "snapshot", sessions: [] },
  );

  assert.equal(report.summary.dockParity.included, true);
  assert.equal(report.summary.dockParity.sessionCount, 0);
  assert.equal(report.summary.dockParity.expectedActiveListableCount, 1);
  assert.equal(report.summary.dockParity.missingActiveListableFromDock, 1);
  assert.ok(report.findings.some((finding) => (
    finding.threadID === "visible-thread"
      && finding.surface === "dock.subscribe"
      && finding.field === "threadID"
      && finding.severity === "error"
  )));
  assert.equal(JSON.stringify(report).includes("private prompt"), false);
});

test("state parity compares dock/subscribe status against loaded app-server state", () => {
  const liveThread = {
    id: "live-thread",
    createdAt: 10,
    updatedAt: 100,
    source: "cli",
    threadSource: "user",
    cwd: "/repo",
    path: "/tmp/live.jsonl",
    modelProvider: "openai",
    status: { type: "notLoaded" },
    preview: "private live prompt",
  };
  const snapshot = {
    complete: true,
    scopes: [
      {
        name: "active:allSourceKinds",
        archive: "active",
        archived: false,
        sourceScope: "allSourceKinds",
        complete: true,
        rows: [
          { ordinal: 0, thread: liveThread },
        ],
        threadIDsInCodexOrder: ["live-thread"],
      },
    ],
    threads: [
      {
        threadID: "live-thread",
        appearances: [
          { scope: "active:allSourceKinds", archive: "active", archived: false, sourceScope: "allSourceKinds" },
        ],
        routedRead: {
          thread: {
            ...liveThread,
            status: { type: "active", activeFlags: ["waitingOnUserInput"] },
          },
        },
      },
    ],
    loaded: { complete: true, threadIDs: ["live-thread"] },
  };
  const sqlite = {
    ok: true,
    rows: [
      {
        id: "live-thread",
        source: "cli",
        thread_source: "user",
        archived: 0,
        cwd: "/repo",
        rollout_path: "/tmp/live.jsonl",
        model_provider: "openai",
        preview: "private live prompt",
        created_at: 10,
        updated_at: 100,
      },
    ],
  };

  const report = compareRelaySnapshotToSQLite(
    snapshot,
    sqlite,
    sqlite,
    { ok: true, count: 0, rows: [] },
    [],
    { includeThreadReads: true, includeLoaded: true },
    new Map(),
    { ok: true, rows: [] },
    {
      kind: "snapshot",
      sessions: [
        { id: "host::live-thread", threadID: "live-thread", lane: "human", updatedAt: 100, status: "dormant" },
      ],
    },
  );

  assert.equal(report.summary.dockParity.loadedStatusCompared, true);
  assert.equal(report.summary.dockParity.loadedThreadCount, 1);
  assert.equal(report.summary.dockParity.loadedDockSessionsCompared, 1);
  assert.equal(report.summary.dockParity.loadedDockStatusMismatches, 1);
  assert.equal(report.summary.dockParity.staleLiveDockSessions, 1);
  assert.deepEqual(report.summary.dockParity.firstLoadedDockStatusMismatch, {
    threadID: "live-thread",
    expected: "needsInput",
    actual: "dormant",
    statusSource: "routed thread/read",
  });
  assert.ok(report.findings.some((finding) => (
    finding.threadID === "live-thread"
      && finding.surface === "dock.subscribe"
      && finding.field === "status"
      && finding.severity === "error"
  )));
  assert.equal(report.findings.some((finding) => finding.surface === "relay.loaded"), false);
  assert.equal(JSON.stringify(report).includes("private live prompt"), false);
});

test("state parity checks dock/subscribe order against app-server combined Codex order", () => {
  const newerThread = {
    id: "newer-thread",
    createdAt: 20,
    updatedAt: 200,
    source: "cli",
    threadSource: "user",
    cwd: "/repo",
    path: "/tmp/newer.jsonl",
    modelProvider: "openai",
    status: { type: "notLoaded" },
    preview: "private newer prompt",
  };
  const olderThread = {
    id: "older-thread",
    createdAt: 10,
    updatedAt: 100,
    source: "cli",
    threadSource: "user",
    cwd: "/repo",
    path: "/tmp/older.jsonl",
    modelProvider: "openai",
    status: { type: "notLoaded" },
    preview: "private older prompt",
  };
  const snapshot = {
    complete: true,
    scopes: [
      {
        name: "active:allSourceKinds",
        archive: "active",
        archived: false,
        sourceScope: "allSourceKinds",
        complete: true,
        rows: [
          { ordinal: 0, pageIndex: 0, rowIndex: 0, thread: newerThread },
          { ordinal: 1, pageIndex: 0, rowIndex: 1, thread: olderThread },
        ],
        threadIDsInCodexOrder: ["newer-thread", "older-thread"],
      },
    ],
    threads: [
      {
        threadID: "newer-thread",
        appearances: [
          { scope: "active:allSourceKinds", archive: "active", archived: false, sourceScope: "allSourceKinds" },
        ],
      },
      {
        threadID: "older-thread",
        appearances: [
          { scope: "active:allSourceKinds", archive: "active", archived: false, sourceScope: "allSourceKinds" },
        ],
      },
    ],
    loaded: { complete: true, threadIDs: [] },
  };
  const sqlite = {
    ok: true,
    rows: [
      {
        id: "newer-thread",
        source: "cli",
        thread_source: "user",
        archived: 0,
        cwd: "/repo",
        rollout_path: "/tmp/newer.jsonl",
        model_provider: "openai",
        preview: "private newer prompt",
        created_at: 20,
        updated_at: 200,
      },
      {
        id: "older-thread",
        source: "cli",
        thread_source: "user",
        archived: 0,
        cwd: "/repo",
        rollout_path: "/tmp/older.jsonl",
        model_provider: "openai",
        preview: "private older prompt",
        created_at: 10,
        updated_at: 100,
      },
    ],
  };

  const report = compareRelaySnapshotToSQLite(
    snapshot,
    sqlite,
    sqlite,
    { ok: true, count: 0, rows: [] },
    [],
    { includeThreadReads: false, includeLoaded: true },
    new Map(),
    { ok: true, rows: [] },
    {
      kind: "snapshot",
      sessions: [
        { id: "host::older-thread", threadID: "older-thread", lane: "human", updatedAt: 100 },
        { id: "host::newer-thread", threadID: "newer-thread", lane: "human", updatedAt: 200 },
      ],
    },
  );

  assert.equal(report.summary.dockParity.codexOrderCompared, true);
  assert.equal(report.summary.dockParity.codexOrderComparableThreads, 2);
  assert.equal(report.summary.dockParity.codexOrderMismatches, 2);
  assert.equal(report.summary.dockParity.codexOrderStableMismatches, 2);
  assert.equal(report.summary.dockParity.codexOrderMismatchesDueToFreshnessMovement, 0);
  assert.deepEqual(report.summary.dockParity.codexOrderFirstMismatch, {
    index: 0,
    expectedThreadID: "newer-thread",
    actualThreadID: "older-thread",
  });
  assert.deepEqual(report.summary.dockParity.codexOrderFirstStableMismatch, {
    index: 0,
    expectedThreadID: "newer-thread",
    actualThreadID: "older-thread",
  });
  assert.ok(report.findings.some((finding) => (
    finding.surface === "dock.subscribe"
      && finding.field === "threadIDOrder"
      && finding.severity === "error"
  )));
  assert.equal(JSON.stringify(report).includes("private newer prompt"), false);
  assert.equal(JSON.stringify(report).includes("private older prompt"), false);
});

test("state parity classifies dock/subscribe order changes caused by live timestamp movement", () => {
  const snapshot = {
    complete: true,
    scopes: [
      {
        name: "active:allSourceKinds",
        archive: "active",
        archived: false,
        sourceScope: "allSourceKinds",
        complete: true,
        rows: [
          {
            ordinal: 0,
            thread: {
              id: "newer-thread",
              updatedAt: 200,
              source: "cli",
              threadSource: "user",
              cwd: "/repo",
              path: "/tmp/newer.jsonl",
              modelProvider: "openai",
              status: { type: "notLoaded" },
              preview: "private newer prompt",
            },
          },
          {
            ordinal: 1,
            thread: {
              id: "older-thread",
              updatedAt: 100,
              source: "cli",
              threadSource: "user",
              cwd: "/repo",
              path: "/tmp/older.jsonl",
              modelProvider: "openai",
              status: { type: "notLoaded" },
              preview: "private older prompt",
            },
          },
        ],
        threadIDsInCodexOrder: ["newer-thread", "older-thread"],
      },
    ],
    threads: [
      { threadID: "newer-thread" },
      { threadID: "older-thread" },
    ],
    loaded: { complete: true, threadIDs: [] },
  };
  const sqlite = {
    ok: true,
    rows: [
      {
        id: "newer-thread",
        source: "cli",
        thread_source: "user",
        archived: 0,
        cwd: "/repo",
        rollout_path: "/tmp/newer.jsonl",
        model_provider: "openai",
        preview: "private newer prompt",
        updated_at: 200,
      },
      {
        id: "older-thread",
        source: "cli",
        thread_source: "user",
        archived: 0,
        cwd: "/repo",
        rollout_path: "/tmp/older.jsonl",
        model_provider: "openai",
        preview: "private older prompt",
        updated_at: 100,
      },
    ],
  };

  const report = compareRelaySnapshotToSQLite(
    snapshot,
    sqlite,
    sqlite,
    { ok: true, count: 0, rows: [] },
    [],
    { includeThreadReads: false, includeLoaded: true },
    new Map(),
    { ok: true, rows: [] },
    {
      kind: "snapshot",
      sessions: [
        { id: "host::older-thread", threadID: "older-thread", lane: "human", updatedAt: 250 },
        { id: "host::newer-thread", threadID: "newer-thread", lane: "human", updatedAt: 200 },
      ],
    },
  );

  assert.equal(report.summary.dockParity.codexOrderMismatches, 2);
  assert.equal(report.summary.dockParity.codexOrderStableMismatches, 0);
  assert.equal(report.summary.dockParity.codexOrderMismatchesDueToFreshnessMovement, 2);
  assert.ok(report.findings.some((finding) => (
    finding.surface === "dock.subscribe"
      && finding.field === "threadIDOrder"
      && finding.severity === "info"
  )));
  assert.equal(report.findings.some((finding) => (
    finding.surface === "dock.subscribe"
      && finding.field === "threadIDOrder"
      && finding.severity === "error"
  )), false);
  assert.equal(JSON.stringify(report).includes("private newer prompt"), false);
  assert.equal(JSON.stringify(report).includes("private older prompt"), false);
});

test("state parity marks threads added during audit as movement instead of relay misses", () => {
  const snapshot = {
    complete: true,
    scopes: [
      {
        name: "active:vscode",
        archive: "active",
        archived: false,
        sourceScope: "vscode",
        complete: true,
        rows: [],
        threadIDsInCodexOrder: [],
      },
    ],
    threads: [],
    loaded: { complete: true, threadIDs: [] },
  };
  const sqliteBefore = { ok: true, rows: [] };
  const sqliteAfter = {
    ok: true,
    rows: [
      {
        id: "new-thread",
        source: "vscode",
        thread_source: "user",
        archived: 0,
        cwd: "/repo",
        rollout_path: "/tmp/new.jsonl",
        model_provider: "openai",
        preview: "private prompt",
      },
    ],
  };

  const report = compareRelaySnapshotToSQLite(
    snapshot,
    sqliteBefore,
    sqliteAfter,
    { ok: true, count: 0, rows: [] },
    [{ threadID: "new-thread", ok: true, thread: { id: "new-thread", source: "vscode" } }],
    { includeThreadReads: false, includeLoaded: true },
    new Map(),
    { ok: true, rows: [] },
    { kind: "snapshot", sessions: [] },
  );

  assert.equal(report.summary.sqliteStableIDsDuringAudit, false);
  assert.equal(report.summary.sqliteThreadRowsAddedDuringAudit, 1);
  assert.equal(report.summary.missingFromRelay, 0);
  assert.equal(report.summary.missingListableFromRelay, 0);
  assert.equal(report.summary.missingFromRelayDueToAuditMovement, 1);
  assert.equal(report.summary.missingListableFromRelayDueToAuditMovement, 1);
  assert.equal(report.summary.dockParity.missingActiveListableFromDock, 0);
  assert.equal(report.summary.dockParity.missingActiveListableFromDockDueToAuditMovement, 1);
  assert.equal(report.summary.errors, 0);
  assert.equal(JSON.stringify(report).includes("private prompt"), false);
});

test("state parity summarizes turn coverage without exposing turn item text", () => {
  const snapshot = {
    complete: true,
    turnRequest: {
      included: true,
      sortDirection: "desc",
      itemsView: "full",
    },
    scopes: [
      {
        name: "active:cli",
        archive: "active",
        archived: false,
        sourceScope: "cli",
        complete: true,
        rows: [
          {
            ordinal: 0,
            thread: {
              id: "visible-thread",
              source: "cli",
              threadSource: "user",
              cwd: "/repo",
              path: "/tmp/visible.jsonl",
              modelProvider: "openai",
              status: { type: "notLoaded" },
            },
          },
        ],
        threadIDsInCodexOrder: ["visible-thread"],
      },
    ],
    threads: [
      {
        threadID: "visible-thread",
        appearances: [
          { scope: "active:cli", archive: "active", archived: false, sourceScope: "cli" },
        ],
        surfaceSummary: {
          hasConflicts: false,
          conflictingFields: [],
        },
        turns: {
          complete: true,
          pages: [{ cursor: null, nextCursor: null, rowCount: 2 }],
          turnsInCodexOrder: [
            {
              ordinal: 0,
              pageIndex: 0,
              rowIndex: 0,
              turn: {
                id: "turn-newer",
                status: "completed",
                itemsView: "full",
                items: [{ type: "agentMessage", text: "private response text" }],
              },
            },
            {
              ordinal: 1,
              pageIndex: 0,
              rowIndex: 1,
              turn: {
                id: "turn-older",
                status: "interrupted",
                itemsView: "full",
                items: [
                  {
                    type: "userMessage",
                    text: "private turn text",
                    finalOutputJsonSchema: {
                      description: "private schema text",
                    },
                  },
                ],
              },
            },
          ],
        },
      },
    ],
    loaded: { complete: true, threadIDs: [] },
  };
  const sqlite = {
    ok: true,
    rows: [
      {
        id: "visible-thread",
        source: "cli",
        thread_source: "user",
        archived: 0,
        cwd: "/repo",
        rollout_path: "/tmp/visible.jsonl",
        model_provider: "openai",
        preview: "private prompt",
      },
    ],
  };

  const report = compareRelaySnapshotToSQLite(
    snapshot,
    sqlite,
    sqlite,
    { ok: true, count: 0, rows: [] },
    [],
    { includeThreadReads: false, includeLoaded: true, includeTurns: true },
  );

  assert.equal(report.summary.turnParity.included, true);
  assert.equal(report.summary.turnParity.threadsChecked, 1);
  assert.equal(report.summary.turnParity.totalTurns, 2);
  assert.equal(report.summary.turnParity.totalItems, 2);
  assert.equal(report.summary.turnParity.turnsWithItems, 2);
  assert.equal(report.summary.turnParity.requestedSortDirection, "desc");
  assert.equal(report.summary.turnParity.requestedItemsView, "full");
  assert.deepEqual(report.summary.turnParity.statusCounts, {
    completed: 1,
    interrupted: 1,
  });
  assert.deepEqual(report.summary.turnParity.itemTypeCounts, {
    agentMessage: 1,
    userMessage: 1,
  });
  assert.deepEqual(report.summary.turnParity.startShape, {
    source: "thread/turns/list turn items",
    requestedItemsView: "full",
    requestedSortDirection: "desc",
    oldestTurnInference: "oldest turn is the last returned row",
    threadsWithAnyUserMessageItem: 1,
    threadsWithoutUserMessageItem: 0,
    threadsWithOldestTurnUserMessage: 1,
    threadsWithOldestTurnNoUserMessage: 0,
    threadsWithoutTurns: 0,
  });
  assert.equal(report.summary.turnParity.outputSchemaEvidence.threadsWithEvidence, 1);
  assert.equal(report.summary.turnParity.outputSchemaEvidence.turnsWithEvidence, 1);
  assert.equal(report.summary.turnParity.outputSchemaEvidence.itemsWithEvidence, 1);
  assert.equal(report.summary.turnParity.outputSchemaEvidence.historicalStateObserved, true);
  assert.equal(JSON.stringify(report).includes("private turn text"), false);
  assert.equal(JSON.stringify(report).includes("private response text"), false);
  assert.equal(JSON.stringify(report).includes("private schema text"), false);
  assert.equal(JSON.stringify(report).includes("private prompt"), false);
});

test("state parity expected scopes include archive side", () => {
  const snapshot = {
    scopes: [
      { name: "active:interactiveDefault", sourceScope: "interactiveDefault" },
      { name: "archived:interactiveDefault", sourceScope: "interactiveDefault" },
      { name: "active:cli", sourceScope: "cli" },
      { name: "archived:cli", sourceScope: "cli" },
    ],
  };

  assert.deepEqual(
    expectedScopeNamesForSQLiteThread({ source: "cli", thread_source: "user", archived: 1 }, snapshot),
    ["archived:interactiveDefault", "archived:cli"],
  );
});

test("state parity parseArgs expands paths and clamps page limits", () => {
  const parsed = parseArgs(
    [
      "--relay-url",
      "ws://relay.example:4510",
      "--limit=999",
      "--include-thread-reads",
      "--include-loaded",
      "--include-goals",
      "--include-turns",
      "--turn-sort-direction",
      "asc",
      "--turn-items-view=notLoaded",
      "--request-timeout-ms=600000",
      "--missing-read-probe-limit",
      "999",
      "--json-out",
      "reports/state-parity.json",
    ],
    {
      CODEX_HOME: "~/custom-codex",
    },
    "/tmp/codex-client",
  );

  assert.equal(parsed.relayUrl, "ws://relay.example:4510");
  assert.equal(parsed.limit, 250);
  assert.equal(parsed.missingReadProbeLimit, 250);
  assert.equal(parsed.includeThreadReads, true);
  assert.equal(parsed.includeLoaded, true);
  assert.equal(parsed.includeGoals, true);
  assert.equal(parsed.includeTurns, true);
  assert.equal(parsed.turnSortDirection, "asc");
  assert.equal(parsed.turnItemsView, "notLoaded");
  assert.equal(parsed.requestTimeoutMs, 600000);
  assert.equal(parsed.includeDockSubscribe, true);
  assert.equal(parsed.probeMissingSearches, true);
  assert.equal(parsed.codexHome.endsWith("/custom-codex"), true);
  assert.equal(parsed.jsonOut, "/tmp/codex-client/reports/state-parity.json");
});

test("state parity parseArgs can skip dock/subscribe verification", () => {
  const parsed = parseArgs(["--no-dock-subscribe", "--no-missing-search-probes"], {}, "/tmp/codex-client");

  assert.equal(parsed.includeDockSubscribe, false);
  assert.equal(parsed.probeMissingSearches, false);
});

test("state parity parseArgs exhaustive includes all app-server surfaces", () => {
  const parsed = parseArgs(["--exhaustive"], {}, "/tmp/codex-client");

  assert.equal(parsed.exhaustive, true);
  assert.equal(parsed.includeThreadReads, true);
  assert.equal(parsed.includeLoaded, true);
  assert.equal(parsed.includeGoals, true);
  assert.equal(parsed.includeTurns, true);
  assert.equal(parsed.includeDockSubscribe, true);
  assert.equal(parsed.turnItemsView, "full");
});

test("state parity parseArgs exhaustive keeps explicit turn items view", () => {
  const parsed = parseArgs(["--exhaustive", "--turn-items-view=notLoaded"], {}, "/tmp/codex-client");

  assert.equal(parsed.exhaustive, true);
  assert.equal(parsed.includeTurns, true);
  assert.equal(parsed.turnItemsView, "notLoaded");
});

test("state parity sanitizes SQLite text fields as fingerprints", () => {
  const sanitized = sanitizeSQLiteThread({
    id: "thread-1",
    source: "cli",
    thread_source: "user",
    title: "private title",
    preview: "private preview",
    first_user_message: "private prompt",
  });

  assert.equal(sanitized.title.present, true);
  assert.equal(sanitized.preview.present, true);
  assert.equal(sanitized.firstUserMessage.present, true);
  assert.equal(JSON.stringify(sanitized).includes("private title"), false);
  assert.equal(JSON.stringify(sanitized).includes("private preview"), false);
  assert.equal(JSON.stringify(sanitized).includes("private prompt"), false);
});

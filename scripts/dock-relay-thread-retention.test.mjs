import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import { RELAY_THREAD_RETENTION_WINDOW_MS } from "./dock-relay-constants.mjs";
import {
  archiveThread,
  canonicalizeThreadRows,
  drainThreadListRows,
  listThreadTurns,
  readSessionIndexHumanStartedSupplements,
  setThreadName,
} from "./dock-relay-thread-data.mjs";
import { RelayStateEngine } from "./dock-relay-state-engine.mjs";
import { normalizeThread } from "./dock-relay-state-views.mjs";
import {
  THREAD_RETENTION_REJECTION_REASON,
  cheapThreadActivityMs,
  filterThreadsByRetention,
  retentionBypassThreadIDsFromLive,
  threadRetentionCutoffMs,
  threadRetentionDecision,
  threadRetentionRejectedError,
  threadRetentionWindowMs,
} from "./dock-relay-thread-retention.mjs";
import { RelayUserMessageCommandEngine } from "./dock-relay-user-message-command.mjs";

const NOW_MS = Date.parse("2026-06-06T12:00:00.000Z");
const CUTOFF_MS = NOW_MS - RELAY_THREAD_RETENTION_WINDOW_MS;
const VERY_OLD_MS = Date.parse("2000-01-01T00:00:00.000Z");

function humanThread(id, updatedAtMs) {
  return {
    id,
    sessionId: `${id}-session`,
    preview: id,
    createdAt: updatedAtMs / 1000,
    updatedAt: updatedAtMs / 1000,
    source: "cli",
    status: { type: "idle" },
    cwd: "/tmp/codex-client",
    gitInfo: { branch: "main" },
  };
}

function fakeRelayConfig(handler, extra = {}) {
  return {
    hostId: "home",
    hostName: "Home",
    relayStateDatabasePath: ":memory:",
    logger: { info() {}, warn() {}, error() {}, debug() {} },
    appServerRegistry: {
      async ensureReady() {},
      historyEndpoint() {
        return { url: "ws://history", bearerToken: null };
      },
      isHistoryEndpoint() {
        return true;
      },
      routeForThreadMethod() {
        return {
          source: "history",
          endpoint: { url: "ws://history", bearerToken: null },
        };
      },
      liveEndpoints() {
        return [];
      },
      recordLiveRows() {},
    },
    registryHistoryClient: {
      request: handler,
    },
    sessionRouter: {
      async rowForThread() {
        return null;
      },
    },
    ...extra,
  };
}

test("thread retention uses the production 48 hour window by default", () => {
  assert.equal(threadRetentionWindowMs({}), 48 * 60 * 60 * 1000);
  assert.equal(threadRetentionCutoffMs({}, { nowMs: NOW_MS }), CUTOFF_MS);
});

test("thread retention accepts recent cheap activity and rejects old activity", () => {
  const recent = {
    id: "recent-thread",
    updatedAt: (CUTOFF_MS + 1_000) / 1000,
  };
  const old = {
    id: "old-thread",
    updatedAt: (CUTOFF_MS - 1_000) / 1000,
  };

  assert.equal(threadRetentionDecision(recent, { cutoffMs: CUTOFF_MS }).retained, true);
  const oldDecision = threadRetentionDecision(old, { cutoffMs: CUTOFF_MS });
  assert.equal(oldDecision.retained, false);
  assert.equal(oldDecision.reason, THREAD_RETENTION_REJECTION_REASON);
});

test("thread retention treats missing or invalid timestamps as old", () => {
  for (const row of [
    { id: "missing" },
    { id: "invalid", updatedAt: "not a timestamp" },
    { id: "zero", updatedAtMs: 0 },
  ]) {
    const decision = threadRetentionDecision(row, { cutoffMs: CUTOFF_MS });
    assert.equal(decision.retained, false, row.id);
    assert.equal(decision.reason, THREAD_RETENTION_REJECTION_REASON);
  }
});

test("thread retention uses the same activity timestamp fields as card projection", () => {
  const row = {
    id: "activity-thread",
    createdAt: "2026-06-01T00:00:00.000Z",
    activityAt: "2026-06-06T10:00:00.000Z",
  };

  assert.equal(cheapThreadActivityMs(row), Date.parse("2026-06-06T10:00:00.000Z"));
  assert.equal(threadRetentionDecision(row, { cutoffMs: CUTOFF_MS }).retained, true);
});

test("thread retention keeps explicit live bypass thread ids even when cheap activity is old", () => {
  const oldLive = {
    id: "live-thread",
    updatedAt: (CUTOFF_MS - 1_000_000) / 1000,
  };

  const decision = threadRetentionDecision(oldLive, {
    bypassThreadIDs: new Set(["live-thread"]),
    cutoffMs: CUTOFF_MS,
  });

  assert.equal(decision.retained, true);
  assert.equal(decision.reason, "live_bypass");
});

test("retention bypass ids include live rows and hidden live rollup targets", () => {
  const ids = retentionBypassThreadIDsFromLive(
    [{ id: "live-root" }],
    [{ id: "hidden-child", dockRelayRollupTargetThreadID: "parent-thread" }],
  );

  assert.deepEqual([...ids].sort(), ["live-root", "parent-thread"]);
});

test("thread retention filter reports retained rows and rejection counts", () => {
  const recent = { id: "recent", updatedAtMs: CUTOFF_MS + 1 };
  const old = { id: "old", updatedAtMs: CUTOFF_MS - 1 };

  const result = filterThreadsByRetention([recent, old], { cutoffMs: CUTOFF_MS });

  assert.deepEqual(result.retainedRows.map((row) => row.id), ["recent"]);
  assert.equal(result.retentionRejectedRows, 1);
  assert.deepEqual(result.rejectedCounts, {
    [THREAD_RETENTION_REJECTION_REASON]: 1,
  });
});

test("thread retention rejection error uses the human-filter JSON-RPC error shape", () => {
  const decision = threadRetentionDecision({ id: "old", updatedAtMs: 1 }, { cutoffMs: CUTOFF_MS });
  const error = threadRetentionRejectedError("old", decision);

  assert.equal(error.code, -32043);
  assert.deepEqual(error.data, {
    threadId: "old",
    reason: THREAD_RETENTION_REJECTION_REASON,
    activityAtMs: 1000,
    cutoffMs: CUTOFF_MS,
  });
});

test("drainThreadListRows stops updated_at desc pagination at the retention boundary", async () => {
  const requests = [];
  const config = fakeRelayConfig(async (method, params = {}) => {
    requests.push({ method, params });
    assert.equal(method, "thread/list");
    if (!params.cursor) {
      return {
        data: [
          humanThread("recent", CUTOFF_MS + 1_000),
          humanThread("old", CUTOFF_MS - 1_000),
        ],
        nextCursor: "page-2",
      };
    }
    return {
      data: [humanThread("should-not-fetch", CUTOFF_MS + 2_000)],
      nextCursor: null,
    };
  });

  const scope = await drainThreadListRows(config, {
    limit: 2,
    sortKey: "updated_at",
    sortDirection: "desc",
  }, {
    cutoffMs: CUTOFF_MS,
  });

  assert.equal(scope.complete, true);
  assert.equal(scope.retentionBoundaryHit, true);
  assert.equal(scope.retentionRejectedRows, 1);
  assert.deepEqual(scope.rows.map((row) => row.thread.id), ["recent"]);
  assert.deepEqual(requests.map((request) => request.params.cursor || null), [null]);
});

test("session-index supplements reject old candidates before thread/read", async () => {
  const root = mkdtempSync(join(tmpdir(), "codex-dock-retention-index-"));
  try {
    writeFileSync(join(root, "session_index.jsonl"), [
      JSON.stringify({
        id: "recent",
        thread_name: "Recent",
        updated_at: new Date(CUTOFF_MS + 1_000).toISOString(),
      }),
      JSON.stringify({
        id: "old",
        thread_name: "Old",
        updated_at: new Date(CUTOFF_MS - 1_000).toISOString(),
      }),
      "",
    ].join("\n"));

    const readThreadIDs = [];
    const result = await readSessionIndexHumanStartedSupplements({
      codexHome: root,
      logger: { info() {}, warn() {}, error() {}, debug() {} },
    }, [], {
      cutoffMs: CUTOFF_MS,
      readThread: async (threadId) => {
        readThreadIDs.push(threadId);
        return { thread: humanThread(threadId, CUTOFF_MS + 1_000) };
      },
    });

    assert.deepEqual(readThreadIDs, ["recent"]);
    assert.deepEqual(result.acceptedRows.map((row) => row.id), ["recent"]);
    assert.equal(result.retentionRejectedRows, 1);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("old direct routes reject before thread turns or archive mutation requests", async () => {
  const requests = [];
  const config = fakeRelayConfig(async (method, params = {}) => {
    requests.push({ method, params });
    if (method === "thread/read") {
      return { thread: humanThread(params.threadId, VERY_OLD_MS) };
    }
    if (method === "thread/turns/list" || method === "thread/archive") {
      throw new Error(`${method} should not be called for old retained-out thread`);
    }
    throw new Error(`unexpected method ${method}`);
  });

  await assert.rejects(
    () => listThreadTurns(config, { threadId: "old", limit: 10 }),
    (error) => error.code === -32043
      && error.data?.reason === THREAD_RETENTION_REJECTION_REASON,
  );
  await assert.rejects(
    () => archiveThread(config, { threadId: "old" }),
    (error) => error.code === -32043
      && error.data?.reason === THREAD_RETENTION_REJECTION_REASON,
  );

  assert.deepEqual(requests.map((request) => request.method), ["thread/read", "thread/read"]);
});

test("activity proof uses retained list row when route thread/read has stale activity", async () => {
  const requests = [];
  const retainedActivityMs = Date.now() - RELAY_THREAD_RETENTION_WINDOW_MS + 60_000;
  const recentListRow = humanThread("recent-proof", retainedActivityMs);
  const staleReadRow = humanThread("recent-proof", VERY_OLD_MS);
  const config = fakeRelayConfig(async (method, params = {}) => {
    requests.push({ method, params });
    if (method === "thread/read") {
      return { thread: staleReadRow };
    }
    if (method === "thread/turns/list") {
      return { data: [], nextCursor: null };
    }
    throw new Error(`unexpected method ${method}`);
  });

  const proof = await canonicalizeThreadRows(config, [recentListRow], {
    route: "retention-activity-proof-test",
  });

  assert.equal(proof.complete, true);
  assert.equal(proof.validationFailures, 0);
  assert.equal(proof.rows[0].activityProofStatus, "proven");
  assert.equal(proof.rows[0].activityAtMs, retainedActivityMs);
  assert.deepEqual(requests.map((request) => request.method), ["thread/read", "thread/turns/list"]);
});

test("visible retained Dock card allows rename when route thread/read has stale activity", async () => {
  const requests = [];
  const retainedActivityMs = Date.now() - RELAY_THREAD_RETENTION_WINDOW_MS + 60_000;
  const retainedThread = humanThread("visible-retained", retainedActivityMs);
  const staleReadRow = humanThread("visible-retained", VERY_OLD_MS);
  const host = { id: "home", displayName: "Home", endpoint: null };
  const appFacingCard = normalizeThread({
    ...retainedThread,
    activityAtMs: retainedActivityMs,
    activityAt: new Date(retainedActivityMs).toISOString(),
    freshness: "fresh",
    completeness: "complete",
  }, host, "human", {
    archiveState: "active",
    freshness: "fresh",
    completeness: "complete",
  });
  const config = fakeRelayConfig(async (method, params = {}) => {
    requests.push({ method, params });
    if (method === "thread/read") {
      return { thread: staleReadRow };
    }
    if (method === "thread/name/set") {
      return { ok: true };
    }
    throw new Error(`unexpected method ${method}`);
  }, {
    relayStateEngine: {
      cardForThread(threadId) {
        return threadId === "visible-retained" ? appFacingCard : null;
      },
    },
  });

  const result = await setThreadName(config, {
    threadId: "visible-retained",
    name: "Renamed visible retained thread",
  });

  assert.deepEqual(result, { ok: true });
  assert.deepEqual(requests.map((request) => request.method), ["thread/read", "thread/name/set"]);
});

test("old active-looking Dock card does not bypass retention without live evidence", async () => {
  const requests = [];
  const oldActiveThread = {
    ...humanThread("old-active-card", VERY_OLD_MS),
    status: { type: "active", activeFlags: [] },
  };
  const host = { id: "home", displayName: "Home", endpoint: null };
  const appFacingCard = normalizeThread({
    ...oldActiveThread,
    activityAtMs: VERY_OLD_MS,
    activityAt: new Date(VERY_OLD_MS).toISOString(),
    freshness: "fresh",
    completeness: "complete",
  }, host, "human", {
    archiveState: "active",
    freshness: "fresh",
    completeness: "complete",
  });
  const config = fakeRelayConfig(async (method, params = {}) => {
    requests.push({ method, params });
    if (method === "thread/read") {
      return { thread: oldActiveThread };
    }
    if (method === "thread/name/set") {
      throw new Error("thread/name/set should not be called for stale active-looking card");
    }
    throw new Error(`unexpected method ${method}`);
  }, {
    relayStateEngine: {
      cardForThread(threadId) {
        return threadId === "old-active-card" ? appFacingCard : null;
      },
    },
  });

  await assert.rejects(
    () => setThreadName(config, {
      threadId: "old-active-card",
      name: "Should not rename stale active-looking thread",
    }),
    (error) => error.code === -32043
      && error.data?.reason === THREAD_RETENTION_REJECTION_REASON,
  );

  assert.deepEqual(requests.map((request) => request.method), ["thread/read"]);
});

test("old thread/message/send rejects before outbound message persistence", async () => {
  const requests = [];
  const config = fakeRelayConfig(async (method, params = {}) => {
    requests.push({ method, params });
    if (method === "thread/read") {
      return { thread: humanThread(params.threadId, VERY_OLD_MS) };
    }
    if (method === "turn/start") {
      throw new Error("turn/start should not be called for old retained-out thread");
    }
    throw new Error(`unexpected method ${method}`);
  });
  const engine = new RelayUserMessageCommandEngine(config);
  try {
    await assert.rejects(
      () => engine.send({
        threadId: "old",
        clientUserMessageId: "dock-msg:old",
        input: [{ type: "text", text: "Should not send", text_elements: [] }],
      }),
      (error) => error.code === -32043
        && error.data?.reason === THREAD_RETENTION_REJECTION_REASON,
    );
    assert.deepEqual(requests.map((request) => request.method), ["thread/read"]);
    assert.equal(engine.store.messageForClientID("home", "old", "dock-msg:old"), null);
  } finally {
    engine.stateStore.close();
  }
});

test("complete Dock reconcile deletes old cards without expensive old-row reads", async () => {
  const oldThread = humanThread("old-card", VERY_OLD_MS);
  const requests = [];
  const config = fakeRelayConfig(async (method, params = {}) => {
    requests.push({ method, params });
    if (method === "thread/list") {
      return {
        data: [oldThread],
        nextCursor: null,
      };
    }
    throw new Error(`${method} should not be called for old retained-out thread`);
  });
  const engine = new RelayStateEngine(config);
  try {
    const host = { id: "home", displayName: "Home", endpoint: null };
    const card = normalizeThread({
      ...oldThread,
      activityAtMs: VERY_OLD_MS,
      activityAt: new Date(VERY_OLD_MS).toISOString(),
      freshness: "fresh",
      completeness: "complete",
    }, host, "human", {
      archiveState: "active",
      freshness: "fresh",
      completeness: "complete",
    });
    engine.store.applyDockReconciliation({
      host,
      cards: [card],
      scopes: [{
        name: "active:interactiveDefault",
        archived: false,
        sourceScope: "interactiveDefault",
        complete: true,
        error: null,
      }],
      complete: true,
      error: null,
      previousCards: [],
    });
    assert.equal(engine.store.listDockCards({ hostID: "home" }).totalRows, 1);

    await engine.reconcileDock({ reason: "retention-delete-test" });

    assert.equal(engine.store.listDockCards({ hostID: "home" }).totalRows, 0);
    assert.deepEqual(requests.map((request) => request.method), ["thread/list"]);
  } finally {
    await engine.close();
  }
});

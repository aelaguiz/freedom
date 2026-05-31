import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { WebSocketServer } from "ws";

import {
  RELAY_STATE_TEXT_FIELD_MAX_CHARS,
  RELAY_STATE_TITLE_MAX_CHARS,
} from "./dock-relay-constants.mjs";
import {
  attentionFlagsForServerRequest,
  buildBonjourAdvertisementArgs,
  isPhoneRequestAuthorized,
  mergeActiveFlags,
  preferThread,
  sanitizeRelayFields,
  startServer,
  statusPriority,
  threadMatchesSourceKinds,
} from "./dock-relay.mjs";
import { createRelayLogger } from "./dock-relay-logger.mjs";
import { SessionRouter, liveOverlayForSnapshot } from "./dock-relay-live-status-cache.mjs";
import {
  classifyThreadOrigin,
  filterHumanBaseThreads,
  isHumanBaseThread,
  threadSpawnParentIDFromSource,
} from "./dock-relay-human-thread-filter.mjs";
import { RelayStateEngine } from "./dock-relay-state-engine.mjs";
import { RelayStateStore } from "./dock-relay-state-store.mjs";
import {
  estimateJSONBytes,
  normalizeThread,
  normalizedStatus,
} from "./dock-relay-state-views.mjs";
import { ThreadSummaryCache } from "./dock-relay-thread-summary-cache.mjs";
import {
  clampThreadListParams,
  disabledLiveOverlay,
  liveStatusCacheForConfig,
} from "./dock-relay-thread-data.mjs";

import {
  closeWebSocketServer,
  jsonRpcRequest,
  onceListening,
  openWebSocket,
  sleepMs,
  waitForRelayMessage,
} from "./dock-relay-test-helpers.mjs";

test("relay logger redacts credentials and payload fields", () => {
  const lines = [];
  const logger = createRelayLogger({
    stream: {
      write(line) {
        lines.push(line);
      },
    },
    clock: () => new Date("2026-05-28T00:00:00.000Z"),
  });

  logger.info("relay.redaction_test", {
    authorization: "Bearer sk-test-secret-token",
    openAIAPIKey: "sk-test-secret-token",
    base64Audio: Buffer.from("raw audio bytes").toString("base64"),
    transcript: "private transcript",
    endpointUrl: "ws://user:pass@127.0.0.1:4510/path?token=secret#frag",
    params: {
      prompt: "private prompt",
    },
  });

  assert.equal(lines.length, 1);
  const parsed = JSON.parse(lines[0]);
  assert.equal(parsed.timestamp, "2026-05-28T00:00:00.000Z");
  assert.equal(parsed.level, "info");
  assert.equal(parsed.fields.authorization, "<redacted>");
  assert.equal(parsed.fields.openAIAPIKey, "<redacted>");
  assert.equal(parsed.fields.base64Audio, "<redacted>");
  assert.equal(parsed.fields.transcript, "<redacted>");
  assert.equal(parsed.fields.params, "<redacted-payload>");
  assert.equal(parsed.fields.endpointUrl, "ws://127.0.0.1:4510/path");

  const text = lines.join("\n");
  assert.equal(text.includes("sk-test-secret-token"), false);
  assert.equal(text.includes("raw audio bytes"), false);
  assert.equal(text.includes("private transcript"), false);
  assert.equal(text.includes("private prompt"), false);
  assert.equal(text.includes("user:pass"), false);
});

test("attention flags are derived from real app-server request methods", () => {
  assert.deepEqual(
    attentionFlagsForServerRequest({
      method: "item/commandExecution/requestApproval",
    }),
    ["waitingOnApproval"],
  );
  assert.deepEqual(
    attentionFlagsForServerRequest({
      method: "item/tool/requestUserInput",
    }),
    ["waitingOnUserInput"],
  );
  assert.deepEqual(
    attentionFlagsForServerRequest({
      method: "mcpServer/elicitation/request",
    }),
    ["waitingOnUserInput"],
  );
  assert.deepEqual(
    attentionFlagsForServerRequest({
      method: "thread/status/changed",
    }),
    [],
  );
});

test("mergeActiveFlags preserves existing active flags", () => {
  const row = {
    id: "thread-1",
    status: {
      type: "active",
      activeFlags: ["waitingOnApproval"],
    },
  };

  assert.deepEqual(
    mergeActiveFlags(row, ["waitingOnUserInput"]),
    {
      id: "thread-1",
      status: {
        type: "active",
        activeFlags: ["waitingOnApproval", "waitingOnUserInput"],
      },
    },
  );
});

test("active attention outranks plain active when deduping live rows", () => {
  const plain = {
    id: "thread-1",
    updatedAt: 10,
    status: {
      type: "active",
      activeFlags: [],
    },
  };
  const needsAttention = {
    id: "thread-1",
    updatedAt: 9,
    status: {
      type: "active",
      activeFlags: ["waitingOnUserInput"],
    },
  };

  assert.equal(statusPriority(needsAttention), 0);
  assert.equal(preferThread(plain, needsAttention), needsAttention);
});

test("dock stream status normalization has product-facing names", () => {
  assert.equal(normalizedStatus({ status: { type: "notLoaded" } }), "dormant");
  assert.equal(normalizedStatus({ status: { type: "idle" } }), "idle");
  assert.equal(normalizedStatus({ status: { type: "systemError" } }), "error");
  assert.equal(normalizedStatus({ status: { type: "active", activeFlags: [] } }), "running");
  assert.equal(
    normalizedStatus({
      status: {
        type: "active",
        activeFlags: ["waitingOnUserInput"],
      },
    }),
    "needsInput",
  );
  assert.equal(
    normalizedStatus({
      status: {
        type: "active",
        activeFlags: ["waitingOnApproval", "waitingOnUserInput"],
      },
    }),
    "needsApproval",
  );
});

test("relay state projection bounds oversized thread card text fields", () => {
  const host = { id: "home", displayName: "Home", endpoint: "home.fairy-salmon.ts.net:4510" };
  const session = normalizeThread({
    id: "thread-large-preview",
    preview: "p".repeat(RELAY_STATE_TEXT_FIELD_MAX_CHARS + 1_000),
    latestSummary: "s".repeat(RELAY_STATE_TEXT_FIELD_MAX_CHARS + 1_000),
    displaySummary: "m".repeat(RELAY_STATE_TEXT_FIELD_MAX_CHARS + 1_000),
    updatedAt: 10,
    source: "cli",
    status: { type: "notLoaded" },
  }, host, "human");

  assert.equal(session.title.length, RELAY_STATE_TITLE_MAX_CHARS);
  assert.equal(session.displaySummary.length, RELAY_STATE_TEXT_FIELD_MAX_CHARS);
});

test("relay state store emits Dock changes and keeps rows when a scope goes stale", () => {
  const host = { id: "Amir-M5", displayName: "Amir M5", endpoint: "amir-m5.local:4510" };
  const store = new RelayStateStore({ relayStateDatabasePath: ":memory:" });
  const session = normalizeThread({
    id: "thread-1",
    sessionId: "session-1",
    preview: "Build Dock",
    updatedAt: 10,
    source: "cli",
    status: { type: "active", activeFlags: [] },
  }, host, "human");
  try {
    const update = store.applyDockReconciliation({
      host,
      cards: [session],
      scopes: [{ name: "active:dock", archived: false, sourceScope: "dock", complete: true }],
      complete: true,
    });
    assert.equal(update.seq, 1);
    assert.deepEqual(update.upsertCards.map((row) => row.threadID), ["thread-1"]);
    assert.deepEqual(store.listDockCards({ hostID: host.id }).cards.map((row) => row.threadID), ["thread-1"]);
    const change = store.db.prepare("SELECT payload_json FROM changes WHERE seq = ?").get(update.seq);
    assert.deepEqual(JSON.parse(change.payload_json), {
      upsertCount: 1,
      deleteCount: 0,
      complete: true,
    });

    store.markScopeStale(host.id, "active:dock", new Error("upstream unavailable"));
    assert.equal(store.freshnessForHost(host.id).status, "stale");
    assert.match(store.freshnessForHost(host.id).lastError, /upstream unavailable/);
    assert.deepEqual(store.listDockCards({ hostID: host.id }).cards.map((row) => row.threadID), ["thread-1"]);
  } finally {
    store.close();
  }
});

test("relay state store publishes client-projected status changes from live leases", () => {
  const host = { id: "Amir-M5", displayName: "Amir M5", endpoint: "amir-m5.local:4510" };
  const store = new RelayStateStore({ relayStateDatabasePath: ":memory:" });
  const session = normalizeThread({
    id: "thread-1",
    sessionId: "session-1",
    preview: "Build Dock",
    updatedAt: 10,
    source: "cli",
    status: { type: "notLoaded" },
  }, host, "human");
  try {
    store.applyDockReconciliation({
      host,
      cards: [session],
      scopes: [{ name: "active:dock", archived: false, sourceScope: "dock", complete: true }],
      complete: true,
    });
    const previousVisible = store.listDockCards({ hostID: host.id }).cards;
    assert.equal(previousVisible[0].status, "dormant");

    store.upsertLiveLease(host.id, {
      threadID: "thread-1",
      backendSessionID: "session-1",
      status: "dormant",
      expiresAtMs: Date.now() - 1_000,
    });
    const update = store.applyDockReconciliation({
      host,
      cards: [session],
      scopes: [{ name: "active:dock", archived: false, sourceScope: "dock", complete: true }],
      complete: true,
      previousCards: previousVisible,
    });
    assert.deepEqual(update.upsertCards.map((row) => row.status), ["unknown"]);
    assert.equal(store.listDockCards({ hostID: host.id }).cards[0].status, "unknown");

    const steadyUpdate = store.applyDockReconciliation({
      host,
      cards: [session],
      scopes: [{ name: "active:dock", archived: false, sourceScope: "dock", complete: true }],
      complete: true,
    });
    assert.deepEqual(steadyUpdate.upsertCards, []);
  } finally {
    store.close();
  }
});

test("relay state store publishes live lease expiry even after fresh snapshots project it expired", async () => {
  const host = { id: "Amir-M5", displayName: "Amir M5", endpoint: "amir-m5.local:4510" };
  const store = new RelayStateStore({ relayStateDatabasePath: ":memory:" });
  const session = normalizeThread({
    id: "thread-1",
    sessionId: "session-1",
    preview: "Build Dock",
    updatedAt: 10,
    source: "cli",
    status: { type: "notLoaded" },
  }, host, "human");
  const scope = { name: "active:dock", archived: false, sourceScope: "dock", complete: true };
  try {
    store.applyDockReconciliation({
      host,
      cards: [session],
      scopes: [scope],
      complete: true,
    });
    store.upsertLiveLease(host.id, {
      threadID: "thread-1",
      backendSessionID: "session-1",
      status: "running",
      expiresAtMs: Date.now() + 20,
    });
    assert.equal(store.listDockCards({ hostID: host.id }).cards[0].status, "running");
    await sleepMs(40);

    const previousAtReconcileStart = store.listDockCards({ hostID: host.id }).cards;
    assert.equal(previousAtReconcileStart[0].status, "unknown");
    const expiryUpdate = store.applyDockReconciliation({
      host,
      cards: [session],
      scopes: [scope],
      complete: true,
      previousCards: previousAtReconcileStart,
    });
    assert.deepEqual(expiryUpdate.upsertCards.map((row) => row.status), ["unknown"]);

    const steadyUpdate = store.applyDockReconciliation({
      host,
      cards: [session],
      scopes: [scope],
      complete: true,
    });
    assert.deepEqual(steadyUpdate.upsertCards, []);
  } finally {
    store.close();
  }
});

test("relay state store removes archived Dock rows through state mutation", () => {
  const host = { id: "Amir-M5", displayName: "Amir M5", endpoint: "amir-m5.local:4510" };
  const store = new RelayStateStore({ relayStateDatabasePath: ":memory:" });
  const session = normalizeThread({
    id: "thread-1",
    preview: "Build Dock",
    updatedAt: 10,
    source: "cli",
    status: { type: "notLoaded" },
  }, host, "human");
  try {
    store.applyDockReconciliation({
      host,
      cards: [session],
      scopes: [{ name: "active:dock", archived: false, sourceScope: "dock", complete: true }],
      complete: true,
    });
    store.applyArchiveMutation({ hostID: host.id, threadID: "thread-1", archived: true });
    assert.deepEqual(store.listDockCards({ hostID: host.id }).cards, []);
    assert.deepEqual(store.listArchiveCards({ hostID: host.id }).cards.map((row) => row.threadID), ["thread-1"]);
  } finally {
    store.close();
  }
});

test("relay state archive mutation projects live leases into unarchive deltas", () => {
  const host = { id: "Amir-M5", displayName: "Amir M5", endpoint: "amir-m5.local:4510" };
  const store = new RelayStateStore({ relayStateDatabasePath: ":memory:" });
  const session = normalizeThread({
    id: "thread-1",
    preview: "Build Dock",
    updatedAt: 10,
    source: "cli",
    status: { type: "notLoaded" },
  }, host, "human");
  try {
    store.applyDockReconciliation({
      host,
      cards: [session],
      scopes: [{ name: "active:dock", archived: false, sourceScope: "dock", complete: true }],
      complete: true,
    });
    store.upsertLiveLease(host.id, {
      threadID: "thread-1",
      backendSessionID: "session-1",
      status: "running",
      expiresAtMs: Date.now() + 5_000,
    });
    store.applyArchiveMutation({ hostID: host.id, threadID: "thread-1", archived: true });
    const restored = store.applyArchiveMutation({ hostID: host.id, threadID: "thread-1", archived: false });

    assert.equal(restored.dockUpsertCards[0].status, "running");
    assert.equal(store.listDockCards({ hostID: host.id }).cards[0].status, "running");
  } finally {
    store.close();
  }
});

test("relay state store does not immediately resurrect locally archived rows from stale active reconciliation", () => {
  const host = { id: "Amir-M5", displayName: "Amir M5", endpoint: "amir-m5.local:4510" };
  const store = new RelayStateStore({ relayStateDatabasePath: ":memory:" });
  const session = normalizeThread({
    id: "thread-1",
    preview: "Build Dock",
    updatedAt: 10,
    source: "cli",
    status: { type: "notLoaded" },
  }, host, "human");
  try {
    store.applyDockReconciliation({
      host,
      cards: [session],
      scopes: [{ name: "active:dock", archived: false, sourceScope: "dock", complete: true }],
      complete: true,
    });
    store.applyArchiveMutation({ hostID: host.id, threadID: "thread-1", archived: true });
    const staleActiveList = store.applyDockReconciliation({
      host,
      cards: [session],
      scopes: [{ name: "active:dock", archived: false, sourceScope: "dock", complete: true }],
      complete: true,
    });
    assert.deepEqual(staleActiveList.upsertCards, []);
    assert.deepEqual(store.listDockCards({ hostID: host.id }).cards, []);
    assert.deepEqual(store.listArchiveCards({ hostID: host.id }).cards.map((row) => row.threadID), ["thread-1"]);
  } finally {
    store.close();
  }
});

test("relay state snapshot windows oversized Dock results explicitly", async () => {
  const host = { id: "Amir-M5", displayName: "Amir M5", endpoint: "amir-m5.local:4510" };
  const engine = new RelayStateEngine({
    hostId: host.id,
    hostName: host.displayName,
    hostEndpoint: host.endpoint,
    relayStateDatabasePath: ":memory:",
  });
  try {
    const cards = Array.from({ length: 4 }, (_, index) => normalizeThread({
      id: `thread-${index + 1}`,
      preview: `Window row ${index + 1}`,
      latestSummary: "x".repeat(400),
      updatedAt: 100 - index,
      source: "cli",
      status: { type: "notLoaded" },
    }, host, "human"));
    engine.store.applyDockReconciliation({
      host,
      cards,
      scopes: [{ name: "active:dock", archived: false, sourceScope: "dock", complete: true }],
      complete: true,
    });

    const snapshot = engine.snapshotDock({ softLimitBytes: 1_200 });

    assert.equal(snapshot.kind, "snapshot");
    assert.equal(snapshot.view, "dock");
    assert.equal(snapshot.complete, false);
    assert.equal(snapshot.totalRows, 4);
    assert.ok(snapshot.window.rowCount < snapshot.totalRows);
    assert.equal(snapshot.window.nextOffset, snapshot.window.rowCount);
    assert.equal(snapshot.cards.length, snapshot.window.rowCount);
  } finally {
    await engine.close();
  }
});

test("relay state streams remaining Dock windows after a partial snapshot", async () => {
  const host = { id: "Amir-M5", displayName: "Amir M5", endpoint: "amir-m5.local:4510" };
  const engine = new RelayStateEngine({
    hostId: host.id,
    hostName: host.displayName,
    hostEndpoint: host.endpoint,
    relayStateDatabasePath: ":memory:",
    relayStateSnapshotSoftLimitBytes: 1_200,
  });
  try {
    const cards = Array.from({ length: 4 }, (_, index) => normalizeThread({
      id: `thread-${index + 1}`,
      preview: `Window row ${index + 1}`,
      latestSummary: "x".repeat(400),
      updatedAt: 100 - index,
      source: "cli",
      status: { type: "notLoaded" },
    }, host, "human"));
    engine.store.applyDockReconciliation({
      host,
      cards,
      scopes: [{ name: "active:dock", archived: false, sourceScope: "dock", complete: true }],
      complete: true,
    });

    const notifications = [];
    const response = await engine.subscribeDock({
      session: {},
      downstreamWs: {},
      sendJson: (_ws, message) => notifications.push(message),
    });
    await sleepMs(50);

    assert.equal(response.kind, "snapshot");
    assert.equal(response.complete, false);
    assert.ok(response.window.nextOffset > 0);
    const catchupUpdates = () => notifications
      .filter((message) => message.method === "dock/update")
      .map((message) => message.params)
      .filter((update) => (
      update.baseSeq === response.seq
      && update.seq === response.seq
      && Number(update.window?.offset || 0) > 0
    ));
    const deadline = Date.now() + 1_000;
    while (Date.now() < deadline && catchupUpdates().at(-1)?.complete !== true) {
      await sleepMs(10);
    }
    const updates = catchupUpdates();
    assert.ok(updates.length >= 1);
    assert.equal(updates.at(-1).complete, true);
    const receivedThreadIDs = new Set([
      ...response.cards.map((row) => row.threadID),
      ...updates.flatMap((update) => update.upsertCards.map((row) => row.threadID)),
    ]);
    assert.deepEqual([...receivedThreadIDs].sort(), ["thread-1", "thread-2", "thread-3", "thread-4"]);
  } finally {
    await engine.close();
  }
});

test("relay state restarts Dock window catchup when store seq changes mid-catchup", async () => {
  const host = { id: "Amir-M5", displayName: "Amir M5", endpoint: "amir-m5.local:4510" };
  const engine = new RelayStateEngine({
    hostId: host.id,
    hostName: host.displayName,
    hostEndpoint: host.endpoint,
    relayStateDatabasePath: ":memory:",
    relayStateSnapshotSoftLimitBytes: 1_200,
  });
  try {
    const cards = Array.from({ length: 6 }, (_, index) => normalizeThread({
      id: `thread-${index + 1}`,
      preview: `Window row ${index + 1}`,
      latestSummary: "x".repeat(400),
      updatedAt: 100 - index,
      source: "cli",
      status: { type: "notLoaded" },
    }, host, "human"));
    engine.store.applyDockReconciliation({
      host,
      cards,
      scopes: [{ name: "active:dock", archived: false, sourceScope: "dock", complete: true }],
      complete: true,
    });

    const notifications = [];
    let advancedSeq = false;
    const response = await engine.subscribeDock({
      session: {},
      downstreamWs: {},
      sendJson: (_ws, message) => {
        notifications.push(message);
        const update = message?.params;
        if (!advancedSeq && update?.kind === "delta" && Number(update.window?.offset || 0) > 0) {
          advancedSeq = true;
          const changedCards = [
            normalizeThread({
              id: "thread-new",
              preview: "New row while catchup is in flight",
              latestSummary: "x".repeat(400),
              updatedAt: 200,
              source: "cli",
              status: { type: "notLoaded" },
            }, host, "human"),
            ...cards,
          ];
          engine.store.applyDockReconciliation({
            host,
            cards: changedCards,
            scopes: [{ name: "active:dock", archived: false, sourceScope: "dock", complete: true }],
            complete: true,
            previousCards: cards,
          });
        }
      },
    });
    assert.equal(response.kind, "snapshot");
    assert.equal(response.complete, false);
    let updates = [];
    let restartedSnapshot = null;
    let restartedCatchupUpdates = [];
    for (let attempt = 0; attempt < 100; attempt += 1) {
      updates = notifications
        .filter((message) => message.method === "dock/update")
        .map((message) => message.params);
      restartedSnapshot = updates.find((update) => (
        update.kind === "snapshot"
        && Number(update.seq) > Number(response.seq)
      ));
      restartedCatchupUpdates = restartedSnapshot
        ? updates.filter((update) => (
          update.kind === "delta"
          && update.baseSeq === restartedSnapshot.seq
          && update.seq === restartedSnapshot.seq
          && Number(update.window?.offset || 0) > 0
        ))
        : [];
      if (restartedCatchupUpdates.at(-1)?.complete === true) {
        break;
      }
      await sleepMs(10);
    }
    assert.equal(advancedSeq, true);
    assert.ok(restartedSnapshot);
    assert.ok(restartedCatchupUpdates.length >= 1);
    assert.equal(restartedCatchupUpdates.at(-1).complete, true);
    const receivedThreadIDs = new Set([
      ...restartedSnapshot.cards.map((row) => row.threadID),
      ...restartedCatchupUpdates.flatMap((update) => update.upsertCards.map((row) => row.threadID)),
    ]);
    assert.deepEqual([...receivedThreadIDs].sort(), ["thread-new", ...cards.map((card) => card.threadID)].sort());
  } finally {
    await engine.close();
  }
});

test("dock/subscribe does not refresh already fresh relay state just to serve cached rows", async () => {
  const host = { id: "Amir-M5", displayName: "Amir M5", endpoint: "amir-m5.local:4510" };
  const engine = new RelayStateEngine({
    hostId: host.id,
    hostName: host.displayName,
    hostEndpoint: host.endpoint,
    relayStateDatabasePath: ":memory:",
  });
  let scheduledReconciliations = 0;
  engine.reconciler.schedule = () => {
    scheduledReconciliations += 1;
    return Promise.resolve(null);
  };
  try {
    const session = normalizeThread({
      id: "thread-1",
      preview: "Fresh cached row",
      updatedAt: 100,
      source: "cli",
      status: { type: "notLoaded" },
    }, host, "human");
    engine.store.applyDockReconciliation({
      host,
      cards: [session],
      scopes: [
        { name: "active:allSourceKinds", archived: false, sourceScope: "allSourceKinds", complete: true },
        { name: "active:interactiveDefault", archived: false, sourceScope: "interactiveDefault", complete: true },
      ],
      complete: true,
    });

    const response = await engine.subscribeDock({
      session: {},
      downstreamWs: {},
      sendJson: () => {},
    });
    await sleepMs(20);

    assert.equal(response.complete, true);
    assert.equal(response.cards.length, 1);
    assert.equal(scheduledReconciliations, 0);
  } finally {
    await engine.close();
  }
});

test("relay state JSON size estimator fails closed for unserializable payloads", () => {
  const circular = {};
  circular.self = circular;
  assert.equal(estimateJSONBytes(circular), Number.POSITIVE_INFINITY);
});

test("thread/list params clamp to Codex's 250 row page cap", () => {
  assert.deepEqual(clampThreadListParams({ limit: 500 }), { limit: 250 });
  assert.deepEqual(clampThreadListParams({ limit: 0, cursor: "abc" }), {
    limit: 250,
    cursor: "abc",
  });
  assert.deepEqual(clampThreadListParams({ limit: 37, archived: true }), {
    limit: 37,
    archived: true,
  });
});

test("thread summary cache keeps the last useful summary while a row version warms", () => {
  const cache = new ThreadSummaryCache({
    readThreadTurns: async () => ({ data: [] }),
  });
  cache.remember("thread-1", {
    version: "10",
    summary: "Latest known useful update",
    activityAt: 9,
    checkedAtMs: 1,
  });

  const decorated = cache.decorateRows([
    {
      id: "thread-1",
      preview: "Original opening prompt",
      updatedAt: 20,
    },
  ]);

  assert.equal(decorated[0].latestSummary, "Latest known useful update");
  assert.equal(decorated[0].displaySummary, "Latest known useful update");
  assert.equal(decorated[0].activityAt, 9);
});

test("phase 2 live overlay is explicit degraded metadata", () => {
  assert.deepEqual(disabledLiveOverlay(), {
    ok: false,
    state: "disabled",
    ageMs: null,
  });
});

test("phase 3 live overlay reports partial live discovery failure", () => {
  const now = Date.now();
  const overlay = liveOverlayForSnapshot({
    ok: true,
    checkedAtMs: now,
    endpoints: [{ url: "ws://127.0.0.1:4511" }],
    failedEndpoints: 1,
    rows: [],
  });

  assert.equal(overlay.ok, false);
  assert.equal(overlay.state, "degraded");
  assert.equal(overlay.endpoints, 1);
  assert.equal(overlay.failedEndpoints, 1);
});

test("live status default refresh cadence stays below stale threshold", () => {
  const cache = liveStatusCacheForConfig({
    historyUrl: "ws://127.0.0.1:4500",
  });

  assert.equal(cache.refreshIntervalMs < cache.maxAgeMs, true);
  assert.equal(cache.refreshIntervalMs, 2_500);
  assert.equal(cache.maxAgeMs, 5_000);
});

test("default thread/list sourceKinds keeps only interactive live sources", () => {
  const cases = [
    ["cli", { source: "cli" }, true],
    ["vscode", { source: "vscode" }, true],
    ["atlas custom", { source: { custom: "atlas" } }, true],
    ["chatgpt custom", { source: { custom: "chatgpt" } }, true],
    ["atlas legacy string", { source: "atlas" }, true],
    ["exec", { source: "exec" }, false],
    ["appServer", { source: "appServer" }, false],
    ["appServer object", { source: { appServer: {} } }, false],
    ["mcp alias", { source: "mcp" }, false],
    ["mcp object", { source: { mcp: {} } }, false],
    ["subAgent", { source: { subAgent: "review" } }, false],
    ["unknown", { source: "unknown" }, false],
    ["missing source", {}, false],
  ];

  for (const [name, row, expected] of cases) {
    assert.equal(threadMatchesSourceKinds(row), expected, name);
    assert.equal(threadMatchesSourceKinds(row, []), expected, `${name} empty sourceKinds`);
  }
});

test("explicit agent sourceKinds include live automation and unknown rows", () => {
  const agentKinds = [
    "exec",
    "appServer",
    "subAgentReview",
    "subAgentCompact",
    "subAgentThreadSpawn",
    "subAgentOther",
    "unknown",
  ];

  assert.equal(threadMatchesSourceKinds({ source: "exec" }, agentKinds), true);
  assert.equal(threadMatchesSourceKinds({ source: { exec: {} } }, agentKinds), true);
  assert.equal(threadMatchesSourceKinds({ source: "appServer" }, agentKinds), true);
  assert.equal(threadMatchesSourceKinds({ source: { appServer: {} } }, agentKinds), true);
  assert.equal(threadMatchesSourceKinds({ source: "mcp" }, agentKinds), true);
  assert.equal(threadMatchesSourceKinds({ source: { mcp: {} } }, agentKinds), true);
  assert.equal(threadMatchesSourceKinds({ source: { subAgent: "review" } }, agentKinds), true);
  assert.equal(threadMatchesSourceKinds({ source: "subAgentReview" }, agentKinds), true);
  assert.equal(threadMatchesSourceKinds({ source: { sourceKind: "subAgentCompact" } }, agentKinds), true);
  assert.equal(threadMatchesSourceKinds({ source: { subAgent: "memory_consolidation" } }, agentKinds), false);
  assert.equal(threadMatchesSourceKinds({ source: "unknown" }, agentKinds), true);
  assert.equal(threadMatchesSourceKinds({}, agentKinds), true);
  assert.equal(threadMatchesSourceKinds({ source: "cli" }, agentKinds), false);
  assert.equal(threadMatchesSourceKinds({ source: { custom: "atlas" } }, agentKinds), false);
});

test("contradictory live source metadata maps to unknown", () => {
  const familyConflict = {
    source: {
      cli: {},
      subAgent: "review",
    },
  };
  const variantConflict = {
    source: {
      subAgent: ["review", "compact"],
    },
  };

  assert.equal(threadMatchesSourceKinds(familyConflict), false);
  assert.equal(threadMatchesSourceKinds(familyConflict, ["subAgent"]), false);
  assert.equal(threadMatchesSourceKinds(familyConflict, ["unknown"]), true);

  assert.equal(threadMatchesSourceKinds(variantConflict), false);
  assert.equal(threadMatchesSourceKinds(variantConflict, ["subAgentReview"]), false);
  assert.equal(threadMatchesSourceKinds(variantConflict, ["subAgentCompact"]), false);
  assert.equal(threadMatchesSourceKinds(variantConflict, ["unknown"]), true);
});

test("internal memory live source metadata stays out of filtered scopes", () => {
  const row = { source: "unknown", threadSource: "memory_consolidation" };
  const snakeCaseRow = { source: "unknown", thread_source: "memory_consolidation" };
  const sourceStringRow = { source: "memory_consolidation" };
  const subAgentRow = { source: { subAgent: "memory_consolidation" } };

  assert.equal(threadMatchesSourceKinds(row), false);
  assert.equal(threadMatchesSourceKinds(row, ["subAgent"]), false);
  assert.equal(threadMatchesSourceKinds(row, ["unknown"]), false);
  assert.equal(threadMatchesSourceKinds(snakeCaseRow, ["unknown"]), false);
  assert.equal(threadMatchesSourceKinds(sourceStringRow, ["unknown"]), false);
  assert.equal(threadMatchesSourceKinds(subAgentRow, ["subAgent"]), false);
  assert.equal(threadMatchesSourceKinds(subAgentRow, ["unknown"]), false);
});

test("subAgent sourceKinds match broad and specific live variants", () => {
  const review = { source: { subAgent: "review" } };
  const compact = { source: { subAgent: "compact" } };
  const threadSpawn = {
    source: {
      subAgent: {
        thread_spawn: {
          parent_thread_id: "parent-thread",
          depth: 1,
        },
      },
    },
  };
  const other = { source: { subAgent: { other: "custom-agent" } } };

  assert.equal(threadMatchesSourceKinds(review, ["subAgent"]), true);
  assert.equal(threadMatchesSourceKinds(threadSpawn, ["subAgent"]), true);

  assert.equal(threadMatchesSourceKinds(review, ["subAgentReview"]), true);
  assert.equal(threadMatchesSourceKinds(review, ["subAgentCompact"]), false);
  assert.equal(threadMatchesSourceKinds(compact, ["subAgentCompact"]), true);
  assert.equal(threadMatchesSourceKinds(threadSpawn, ["subAgentThreadSpawn"]), true);
  assert.equal(threadMatchesSourceKinds(other, ["subAgentOther"]), true);
});

test("human thread classifier accepts only user-started base threads", () => {
  const cases = [
    ["cli", { source: "cli" }, true, "human_cli"],
    ["vscode", { source: "vscode" }, true, "human_vscode"],
    ["atlas custom", { source: { custom: "atlas" } }, true, "human_custom_atlas"],
    ["chatgpt custom", { source: "chatgpt" }, true, "human_custom_chatgpt"],
    ["exec", { source: "exec" }, false, "exec"],
    ["appServer", { source: "appServer" }, false, "app_server"],
    ["mcp alias", { source: "mcp" }, false, "mcp"],
    ["subAgent review", { source: { subAgent: "review" } }, false, "sub_agent"],
    ["memory consolidation", { source: "memory_consolidation" }, false, "memory_internal"],
    ["missing source", {}, false, "missing_source"],
    ["forked human", { source: "cli", forkedFromId: "parent-thread" }, false, "forked"],
    [
      "thread spawn",
      { source: { subAgent: { thread_spawn: { parent_thread_id: "parent-thread" } } } },
      false,
      "not_base_level",
    ],
    ["contradictory", { source: { cli: {}, subAgent: "review" } }, false, "contradictory_source"],
  ];

  for (const [name, row, allowed, reason] of cases) {
    const classification = classifyThreadOrigin(row);
    assert.equal(classification.allowed, allowed, name);
    assert.equal(classification.reason, reason, name);
    assert.equal(isHumanBaseThread(row), allowed, name);
  }
  assert.equal(
    threadSpawnParentIDFromSource({ subAgent: { threadSpawn: { parentThreadId: "parent-thread" } } }),
    "parent-thread",
  );
});

test("human thread filtering reports rejected reason counts", () => {
  const { acceptedRows, rejectedCounts } = filterHumanBaseThreads([
    { id: "human", source: "cli" },
    { id: "agent", source: "exec" },
    { id: "spawn", source: { subAgent: { thread_spawn: { parent_thread_id: "parent" } } } },
    { id: "missing" },
  ]);

  assert.deepEqual(acceptedRows.map((row) => row.id), ["human"]);
  assert.deepEqual(rejectedCounts, {
    exec: 1,
    missing_source: 1,
    not_base_level: 1,
  });
});

test("session routing ignores non-human live rows defensively", async () => {
  const historyEndpoint = { label: "history", url: "ws://history.example" };
  const humanEndpoint = { label: "human-live", url: "ws://human.example" };
  const execEndpoint = { label: "exec-live", url: "ws://exec.example" };
  const router = new SessionRouter({
    historyEndpoint,
    liveStatusCache: {
      async snapshotForRouting() {
        return {
          rows: [
            { id: "exec-live-thread", source: "exec", dockRelaySource: execEndpoint },
            { id: "human-live-thread", source: "cli", dockRelaySource: humanEndpoint },
          ],
        };
      },
    },
  });

  assert.equal(await router.rowForThread("exec-live-thread"), null);
  assert.deepEqual(await router.endpointForThread("exec-live-thread"), historyEndpoint);
  assert.deepEqual(await router.rowForThread("human-live-thread"), {
    id: "human-live-thread",
    source: "cli",
    dockRelaySource: humanEndpoint,
  });
  assert.deepEqual(await router.loadedThreadIDs(), ["human-live-thread"]);
});

test("relay source marker is never returned to clients", () => {
  assert.deepEqual(
    sanitizeRelayFields({
      id: "thread-1",
      dockRelaySource: { url: "ws://127.0.0.1:4555" },
    }),
    { id: "thread-1" },
  );
});

test("phone auth none permits local phone connections without a bearer token", () => {
  assert.equal(
    isPhoneRequestAuthorized({ headers: {} }, { phoneAuth: "none" }),
    true,
  );
  assert.equal(
    isPhoneRequestAuthorized(
      { headers: { authorization: "Bearer wrong" } },
      { phoneAuth: "bearer", relayBearerToken: "right" },
    ),
    false,
  );
  assert.equal(
    isPhoneRequestAuthorized(
      { headers: { authorization: "Bearer right" } },
      { phoneAuth: "bearer", relayBearerToken: "right" },
    ),
    true,
  );
});

test("Bonjour advertisement contains only non-secret relay metadata", () => {
  const args = buildBonjourAdvertisementArgs({
    bonjourName: "Codex Dock Test",
    hostId: "Amir-M5",
    phoneAuth: "none",
    port: 4510,
    version: "0.1.0",
  });

  assert.deepEqual(args.slice(0, 5), [
    "-R",
    "Codex Dock Test",
    "_codexdock._tcp",
    "local",
    "4510",
  ]);
  assert.ok(args.includes("version=0.1.0"));
  assert.ok(args.includes("relay-id=Amir-M5"));
  assert.equal(args.includes("auth=none"), false);
  assert.equal(args.includes("scheme=ws"), false);
  assert.equal(args.some((value) => /token|secret|key/i.test(value)), false);
});

test("relay rejects legacy raw audio/transcribe after realtime cutover", async () => {
  const relay = startServer({
    listenHost: "127.0.0.1",
    port: 0,
    phoneAuth: "none",
    historyUrl: "ws://127.0.0.1:1",
    historyBearerToken: "history-token",
    advertiseBonjour: false,
  });
  await relay.listening;
  const ws = await openWebSocket(`ws://127.0.0.1:${relay.server.address().port}`);

  try {
    const response = await jsonRpcRequest(ws, "audio/transcribe", {
      mimeType: "audio/mp4",
      base64Audio: Buffer.from("legacy audio").toString("base64"),
    });

    assert.equal(response.result, undefined);
    assert.equal(response.error.code, -32601);
    assert.match(response.error.message, /unsupported method: audio\/transcribe/);
  } finally {
    ws.close();
    await relay.close();
  }
});

test("relay keeps the raw history app-server token on the Mac side", async () => {
  let observedAuthorization = null;
  const historyServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await onceListening(historyServer);
  historyServer.on("connection", (ws, request) => {
    observedAuthorization = request.headers.authorization;
    ws.on("message", (data) => {
      const message = JSON.parse(data.toString());
      if (message.method === "initialize") {
        ws.send(JSON.stringify({
          id: message.id,
          result: {
            userAgent: "codex-test",
            codexHome: "/tmp/codex",
            platformFamily: "unix",
            platformOs: "macos",
          },
        }));
      } else if (message.method === "thread/list") {
        ws.send(JSON.stringify({
          id: message.id,
          result: {
            data: [],
            nextCursor: null,
            backwardsCursor: null,
          },
        }));
      }
    });
  });

  const relay = startServer({
    listenHost: "127.0.0.1",
    port: 0,
    phoneAuth: "none",
    historyUrl: `ws://127.0.0.1:${historyServer.address().port}`,
    historyBearerToken: "history-token",
    advertiseBonjour: false,
  });
  await relay.listening;
  const ws = await openWebSocket(`ws://127.0.0.1:${relay.server.address().port}`);

  try {
    const response = await jsonRpcRequest(ws, "thread/list", { archived: true });
    assert.deepEqual(response.result.data, []);
    assert.equal(observedAuthorization, "Bearer history-token");
  } finally {
    ws.close();
    await relay.close();
    await closeWebSocketServer(historyServer);
  }
});

test("thread/search forwards app-server search params and strips relay-only thread fields", async () => {
  let observedAuthorization = null;
  const observedSearchParams = [];
  const historyServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await onceListening(historyServer);
  historyServer.on("connection", (ws, request) => {
    observedAuthorization = request.headers.authorization;
    ws.on("message", (data) => {
      const message = JSON.parse(data.toString());
      if (message.method === "initialize") {
        ws.send(JSON.stringify({
          id: message.id,
          result: {
            userAgent: "codex-test",
            codexHome: "/tmp/codex",
            platformFamily: "unix",
            platformOs: "macos",
          },
        }));
      } else if (message.method === "thread/search") {
        observedSearchParams.push(message.params || {});
        ws.send(JSON.stringify({
          id: message.id,
          result: {
            data: [
              {
                thread: {
                  id: "thread-1",
                  preview: "Search result",
                  updatedAt: 100,
                  status: { type: "notLoaded" },
                  source: "cli",
                  dockRelaySource: { bearerToken: "must-not-leak" },
                },
                snippets: [{ field: "preview", text: "Search result" }],
              },
            ],
            nextCursor: "next-page",
            backwardsCursor: null,
          },
        }));
      }
    });
  });

  const relay = startServer({
    listenHost: "127.0.0.1",
    port: 0,
    phoneAuth: "none",
    historyUrl: `ws://127.0.0.1:${historyServer.address().port}`,
    historyBearerToken: "history-token",
    advertiseBonjour: false,
  });
  await relay.listening;
  const ws = await openWebSocket(`ws://127.0.0.1:${relay.server.address().port}`);

  try {
    const response = await jsonRpcRequest(ws, "thread/search", {
      archived: false,
      limit: 999,
      searchTerm: "thread-1",
      sourceKinds: ["cli", "exec"],
      sortKey: "updated_at",
      sortDirection: "desc",
    });

    assert.equal(response.error, undefined);
    assert.equal(observedAuthorization, "Bearer history-token");
    assert.deepEqual(observedSearchParams, [
      {
        archived: false,
        limit: 250,
        searchTerm: "thread-1",
        sortKey: "updated_at",
        sortDirection: "desc",
      },
    ]);
    assert.equal(response.result.nextCursor, "next-page");
    assert.deepEqual(response.result.data.map((row) => row.thread.id), ["thread-1"]);
    assert.deepEqual(response.result.data[0].snippets, [{ field: "preview", text: "Search result" }]);
    assert.equal(response.result.data[0].thread.dockRelaySource, undefined);
    assert.equal(JSON.stringify(response.result).includes("must-not-leak"), false);
  } finally {
    ws.close();
    await relay.close();
    await closeWebSocketServer(historyServer);
  }
});

test("thread/goal/get forwards app-server goal reads through the relay", async () => {
  let observedAuthorization = null;
  const observedGoalParams = [];
  const historyServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await onceListening(historyServer);
  historyServer.on("connection", (ws, request) => {
    observedAuthorization = request.headers.authorization;
    ws.on("message", (data) => {
      const message = JSON.parse(data.toString());
      if (message.method === "initialize") {
        ws.send(JSON.stringify({
          id: message.id,
          result: {
            userAgent: "codex-test",
            codexHome: "/tmp/codex",
            platformFamily: "unix",
            platformOs: "macos",
          },
        }));
      } else if (message.method === "thread/goal/get") {
        observedGoalParams.push(message.params || {});
        ws.send(JSON.stringify({
          id: message.id,
          result: {
            goal: {
              threadId: "thread-1",
              objective: "Reach parity",
              status: "in_progress",
              tokenBudget: null,
              tokensUsed: 12,
              timeUsedSeconds: 34,
              createdAt: 1000,
              updatedAt: 2000,
            },
          },
        }));
      } else if (message.method === "thread/read") {
        ws.send(JSON.stringify({
          id: message.id,
          result: {
            thread: {
              id: message.params?.threadId,
              preview: "Goal owner",
              updatedAt: 100,
              source: "cli",
              status: { type: "notLoaded" },
            },
          },
        }));
      }
    });
  });

  const relay = startServer({
    listenHost: "127.0.0.1",
    port: 0,
    phoneAuth: "none",
    historyUrl: `ws://127.0.0.1:${historyServer.address().port}`,
    historyBearerToken: "history-token",
    advertiseBonjour: false,
  });
  await relay.listening;
  const ws = await openWebSocket(`ws://127.0.0.1:${relay.server.address().port}`);

  try {
    const response = await jsonRpcRequest(ws, "thread/goal/get", {
      threadId: "thread-1",
    });

    assert.equal(response.error, undefined);
    assert.equal(observedAuthorization, "Bearer history-token");
    assert.deepEqual(observedGoalParams, [{ threadId: "thread-1" }]);
    assert.deepEqual(response.result, {
      goal: {
        threadId: "thread-1",
        objective: "Reach parity",
        status: "in_progress",
        tokenBudget: null,
        tokensUsed: 12,
        timeUsedSeconds: 34,
        createdAt: 1000,
        updatedAt: 2000,
      },
    });
  } finally {
    ws.close();
    await relay.close();
    await closeWebSocketServer(historyServer);
  }
});

test("dock/subscribe returns a normalized relay-owned session snapshot", async () => {
  let observedAuthorization = null;
  const observedThreadListParams = [];
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "codex-dock-relay-test-"));
  const historyServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await onceListening(historyServer);
  historyServer.on("connection", (ws, request) => {
    observedAuthorization = request.headers.authorization;
    ws.on("message", (data) => {
      const message = JSON.parse(data.toString());
      if (message.method === "initialize") {
        ws.send(JSON.stringify({
          id: message.id,
          result: {
            userAgent: "codex-test",
            codexHome: "/tmp/codex",
            platformFamily: "unix",
            platformOs: "macos",
          },
        }));
      } else if (message.method === "thread/list") {
        observedThreadListParams.push(message.params || {});
        ws.send(JSON.stringify({
          id: message.id,
          result: {
            data: [
              {
                id: "history-thread",
                sessionId: "history-session",
                preview: "History thread",
                latestSummary: "Stored history row",
                displaySummary: "Stored history message",
                activityAt: 1_780_000_090,
                updatedAt: 1_780_000_100,
                status: {
                  type: "notLoaded",
                },
                cwd: "/Users/aelaguiz/workspace/codex-client",
                gitInfo: {
                  branch: "main",
                  originUrl: "codex-client",
                },
                source: "cli",
              },
              {
                id: "agent-thread",
                sessionId: "agent-session",
                preview: "Agent thread",
                updatedAt: 1_780_000_200,
                status: {
                  type: "active",
                  activeFlags: ["waitingOnApproval"],
                },
                cwd: "/Users/aelaguiz/workspace/codex-client",
                gitInfo: {
                  branch: "feature/relay-table",
                  originUrl: "codex-client",
                },
                source: "exec",
                dockRelaySource: {
                  bearerToken: "must-not-leak",
                },
              },
            ],
            nextCursor: null,
            backwardsCursor: null,
          },
        }));
      } else if (message.method === "thread/loaded/list") {
        ws.send(JSON.stringify({
          id: message.id,
          result: { data: [], nextCursor: null },
        }));
      }
    });
  });

  const relay = startServer({
    listenHost: "127.0.0.1",
    port: 0,
    phoneAuth: "none",
    historyUrl: `ws://127.0.0.1:${historyServer.address().port}`,
    historyBearerToken: "history-token",
    hostId: "Amir-M5",
    hostName: "Amir M5",
    hostEndpoint: "amir-m5.fairy-salmon.ts.net:4510",
    advertiseBonjour: false,
    relayStateDatabasePath: path.join(tempDir, "relay-state.sqlite"),
  });
  await relay.listening;
  const ws = await openWebSocket(`ws://127.0.0.1:${relay.server.address().port}`);

  try {
    const response = await jsonRpcRequest(ws, "dock/subscribe");

    assert.equal(response.error, undefined);
    assert.equal(response.result.kind, "snapshot");
    assert.equal(response.result.view, "dock");
    assert.deepEqual(response.result.cards, []);
    assert.equal(observedThreadListParams.length, 0);

    const update = await waitForRelayMessage(ws, (message) => message.method === "dock/update");
    const params = update.params;
    assert.equal(observedAuthorization, "Bearer history-token");
    assert.equal(observedThreadListParams.length, 1);
    assert.deepEqual(observedThreadListParams.map((params) => params.archived), [false]);
    assert.ok(observedThreadListParams.every((params) => params.includePreviewless === undefined));
    assert.ok(observedThreadListParams.every((params) => params.sourceKinds === undefined));
    assert.equal(params.kind, "delta");
    assert.equal(params.view, "dock");
    assert.equal(params.complete, true);
    assert.equal(params.totalRows, 1);
    assert.deepEqual(params.window, {
      offset: 0,
      limit: 1,
      rowCount: 1,
      nextOffset: null,
    });
    assert.equal(typeof params.stateGeneration, "number");
    assert.equal(params.upsertHosts[0].id, "Amir-M5");
    assert.equal(params.upsertHosts[0].logicalHostID, "Amir-M5");
    assert.equal(params.upsertHosts[0].endpoint, "amir-m5.fairy-salmon.ts.net:4510");
    assert.ok(params.upsertCards.every((row) => row.id === `${row.logicalHostID}::${row.threadID}`));
    assert.deepEqual(
      params.upsertCards.map((row) => [row.threadID, row.status, row.lane, row.sourceKind]),
      [
        ["history-thread", "dormant", "human", "human"],
      ],
    );
    const historySession = params.upsertCards.find((row) => row.threadID === "history-thread");
    assert.equal(historySession.displaySummary, "Stored history message");
    assert.equal(historySession.activityAtMs, 1_780_000_090_000);
    assert.equal(JSON.stringify(params).includes("notLoaded"), false);
    assert.equal(JSON.stringify(params).includes("must-not-leak"), false);
  } finally {
    ws.close();
    await relay.close();
    await closeWebSocketServer(historyServer);
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
});

test("dock/subscribe overlays live status without changing stored Codex order", async () => {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "codex-dock-relay-test-"));
  const liveServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await onceListening(liveServer);
  const liveUrl = `ws://127.0.0.1:${liveServer.address().port}`;
  const historyServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await onceListening(historyServer);

  liveServer.on("connection", (ws) => {
    ws.on("message", (data) => {
      const message = JSON.parse(data.toString());
      if (message.method === "initialize") {
        ws.send(JSON.stringify({
          id: message.id,
          result: {
            userAgent: "live-test",
            codexHome: "/tmp/codex",
            platformFamily: "unix",
            platformOs: "macos",
          },
        }));
      } else if (message.method === "thread/loaded/list") {
        ws.send(JSON.stringify({
          id: message.id,
          result: { data: ["live-thread"], nextCursor: null },
        }));
      } else if (message.method === "thread/read") {
        ws.send(JSON.stringify({
          id: message.id,
          result: {
            thread: {
              id: "live-thread",
              sessionId: "live-session",
              preview: "Live preview should not replace stored summary",
              updatedAt: 10,
              source: "cli",
              status: {
                type: "active",
                activeFlags: ["waitingOnUserInput"],
              },
            },
          },
        }));
      }
    });
  });

  historyServer.on("connection", (ws) => {
    ws.on("message", (data) => {
      const message = JSON.parse(data.toString());
      if (message.method === "initialize") {
        ws.send(JSON.stringify({
          id: message.id,
          result: {
            userAgent: "history-test",
            codexHome: "/tmp/codex",
            platformFamily: "unix",
            platformOs: "macos",
          },
        }));
      } else if (message.method === "thread/list") {
        ws.send(JSON.stringify({
          id: message.id,
          result: {
            data: [
              {
                id: "live-thread",
                sessionId: "stored-session",
                preview: "Stored summary",
                latestSummary: "Stored summary",
                displaySummary: "Stored message",
                activityAt: 250,
                updatedAt: 300,
                source: "cli",
                status: { type: "notLoaded" },
              },
              {
                id: "stored-thread",
                sessionId: "stored-only-session",
                preview: "Stored only",
                updatedAt: 200,
                source: "cli",
                status: { type: "notLoaded" },
              },
            ],
            nextCursor: null,
            backwardsCursor: null,
          },
        }));
      } else if (message.method === "thread/loaded/list") {
        ws.send(JSON.stringify({
          id: message.id,
          result: { data: [], nextCursor: null },
        }));
      }
    });
  });

  await sleepMs(20);
  const relay = startServer({
    listenHost: "127.0.0.1",
    port: 0,
    phoneAuth: "none",
    historyUrl: `ws://127.0.0.1:${historyServer.address().port}`,
    historyBearerToken: "history-token",
    liveEndpoints: [{ label: "live-test", url: liveUrl }],
    hostId: "Amir-M5",
    advertiseBonjour: false,
    relayStateDatabasePath: path.join(tempDir, "relay-state.sqlite"),
    threadSummaryCache: {
      decorateRows: (rows) => rows,
      warmRows: () => {},
    },
  });
  await relay.listening;
  const ws = await openWebSocket(`ws://127.0.0.1:${relay.server.address().port}`);

  try {
    const response = await jsonRpcRequest(ws, "dock/subscribe");
    assert.equal(response.error, undefined);
    assert.deepEqual(response.result.cards, []);
    const update = await waitForRelayMessage(ws, (message) => message.method === "dock/update");
    const cards = update.params.upsertCards;
    assert.deepEqual(cards.map((card) => card.threadID), [
      "live-thread",
      "stored-thread",
    ]);
    const liveSession = cards.find((card) => card.threadID === "live-thread");
    assert.equal(liveSession.status, "needsInput");
    assert.equal(liveSession.backendSessionID, "live-session");
    assert.equal(liveSession.activityAtMs, 250_000);
    assert.equal(liveSession.displaySummary, "Stored message");
    assert.equal(cards.find((card) => card.threadID === "stored-thread").status, "dormant");
  } finally {
    ws.close();
    await relay.close();
    await closeWebSocketServer(liveServer);
    await closeWebSocketServer(historyServer);
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
});

test("dock/subscribe drains only human-started base thread pages", async () => {
  const observedThreadListParams = [];
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "codex-dock-relay-test-"));
  const historyServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await onceListening(historyServer);
  historyServer.on("connection", (ws) => {
    ws.on("message", (data) => {
      const message = JSON.parse(data.toString());
      if (message.method === "initialize") {
        ws.send(JSON.stringify({
          id: message.id,
          result: {
            userAgent: "codex-test",
            codexHome: "/tmp/codex",
            platformFamily: "unix",
            platformOs: "macos",
          },
        }));
      } else if (message.method === "thread/list") {
        const params = message.params || {};
        observedThreadListParams.push(params);
        const cursor = params.cursor || null;
        let data = [];
        let nextCursor = null;
        if (cursor === null) {
          data = [
            { id: "human-page-1", preview: "Human page 1", updatedAt: 40, status: { type: "notLoaded" }, source: "cli" },
            { id: "agent-page-1", preview: "Agent page 1", updatedAt: 20, status: { type: "notLoaded" }, source: "exec" },
          ];
          nextCursor = "human-page-2";
        } else if (cursor === "human-page-2") {
          data = [
            { id: "human-page-2", preview: "Human page 2", updatedAt: 30, status: { type: "notLoaded" }, source: "cli" },
            { id: "agent-page-2", preview: "Agent page 2", updatedAt: 10, status: { type: "notLoaded" }, source: "exec" },
          ];
        }
        ws.send(JSON.stringify({
          id: message.id,
          result: {
            data,
            nextCursor,
            backwardsCursor: null,
          },
        }));
      } else if (message.method === "thread/loaded/list") {
        ws.send(JSON.stringify({
          id: message.id,
          result: { data: [], nextCursor: null },
        }));
      }
    });
  });

  const relay = startServer({
    listenHost: "127.0.0.1",
    port: 0,
    phoneAuth: "none",
    historyUrl: `ws://127.0.0.1:${historyServer.address().port}`,
    historyBearerToken: "history-token",
    hostId: "Amir-M5",
    advertiseBonjour: false,
    relayStateDatabasePath: path.join(tempDir, "relay-state.sqlite"),
  });
  await relay.listening;
  const ws = await openWebSocket(`ws://127.0.0.1:${relay.server.address().port}`);

  try {
    const response = await jsonRpcRequest(ws, "dock/subscribe");

    assert.equal(response.error, undefined);
    assert.deepEqual(response.result.cards, []);
    const update = await waitForRelayMessage(ws, (message) => message.method === "dock/update");
    assert.deepEqual(
      update.params.upsertCards.map((row) => row.threadID),
      ["human-page-1", "human-page-2"],
    );
    assert.equal(observedThreadListParams.length, 2);
    assert.ok(observedThreadListParams.every((params) => params.archived === false));
    assert.ok(observedThreadListParams.every((params) => params.includePreviewless === undefined));
    assert.ok(observedThreadListParams.some((params) => !params.sourceKinds && !params.cursor));
    assert.ok(observedThreadListParams.some((params) => !params.sourceKinds && params.cursor === "human-page-2"));
    assert.ok(observedThreadListParams.every((params) => params.sourceKinds === undefined));
  } finally {
    ws.close();
    await relay.close();
    await closeWebSocketServer(historyServer);
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
});

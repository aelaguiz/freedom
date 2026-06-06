import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import test from "node:test";

import { RELAY_STATE_SCHEMA_VERSION } from "./dock-relay-constants.mjs";
import { RelayOutboundUserMessageStore } from "./dock-relay-outbound-user-message-store.mjs";
import { RelayStateStore } from "./dock-relay-state-store.mjs";
import { threadCardDisplayOrderKey } from "./dock-relay-projection-engine.mjs";

function testThreadCard({
  hostID = "home",
  threadID = "thread-1",
  view = "dock",
  title = "Thread 1",
  status = "idle",
  activityAtMs = Date.parse("2026-06-05T00:00:00.000Z"),
} = {}) {
  const projectionID = `host:${hostID}/thread:${threadID}/row:threadCard`;
  return {
    id: projectionID,
    schemaVersion: 1,
    identityVersion: 1,
    projectionEngineVersion: 1,
    sourceHostID: hostID,
    view,
    projectionID,
    sourceRef: `host:${hostID}/thread:${threadID}`,
    rowRole: "threadCard",
    displayOrderKey: threadCardDisplayOrderKey({ activityAtMs, status, projectionID }),
    logicalHostID: hostID,
    threadID,
    backendSessionID: threadID,
    hostDisplayName: "Home",
    hostEndpoint: null,
    activityAt: new Date(activityAtMs).toISOString(),
    activityAtMs,
    displaySummary: title,
    title,
    status,
    sourceKind: "human",
    lane: "human",
    relationship: "root",
    forkedFromID: null,
    archiveState: view === "archive" ? "archived" : "active",
    freshness: "fresh",
    completeness: "complete",
    repository: "repo",
    workingDirectory: "/repo",
    branch: "main",
    summarySource: "title",
    activityProofStatus: "proven",
    activityProofSource: "test",
    activityProofCheckedAt: "2026-06-05T00:00:00.000Z",
  };
}

test("relay state store exposes per-view stream sequence cursors", () => {
  const store = new RelayStateStore({
    hostId: "home",
    relayStateDatabasePath: ":memory:",
  });
  try {
    const initialGlobalSeq = store.currentSeq();
    const initialDockSeq = store.currentSeqForView("dock");
    const initialArchiveSeq = store.currentSeqForView("archive");
    const dockFirst = store.recordChange({
      view: "dock",
      hostID: "home",
      changeType: "fixture-dock-first",
    });
    const archiveOnly = store.recordChange({
      view: "archive",
      hostID: "home",
      changeType: "fixture-archive-only",
    });

    assert.equal(dockFirst, initialDockSeq + 1);
    assert.equal(archiveOnly, initialArchiveSeq + 1);
    assert.equal(store.currentSeq(), initialGlobalSeq + 2);
    assert.equal(store.currentSeqForView("dock"), dockFirst);
    assert.equal(store.currentSeqForView("archive"), archiveOnly);

    const dockBaseSeq = store.currentSeqForView("dock");
    const dockSecond = store.recordChange({
      view: "dock",
      hostID: "home",
      changeType: "fixture-dock-second",
    });

    assert.equal(dockBaseSeq, dockFirst);
    assert.equal(dockSecond, dockFirst + 1);
    assert.equal(store.currentSeq(), initialGlobalSeq + 3);
    assert.equal(store.currentSeqForView("dock"), dockSecond);
    assert.equal(store.currentSeqForView("archive"), archiveOnly);
  } finally {
    store.close();
  }
});

test("relay state store migrates existing global-only changes to per-view sequence cursors", () => {
  const root = mkdtempSync(join(tmpdir(), "codex-dock-state-store-"));
  const dbPath = join(root, "relay-state.sqlite");
  const db = new DatabaseSync(dbPath);
  try {
    db.exec(`
      CREATE TABLE schema_migrations (
        version INTEGER PRIMARY KEY,
        applied_at TEXT NOT NULL
      );
      INSERT INTO schema_migrations (version, applied_at)
      VALUES (${RELAY_STATE_SCHEMA_VERSION}, '2026-06-05T00:00:00.000Z');

      CREATE TABLE changes (
        seq INTEGER PRIMARY KEY AUTOINCREMENT,
        view TEXT NOT NULL,
        host_id TEXT,
        thread_id TEXT,
        change_type TEXT NOT NULL,
        payload_json TEXT,
        created_at TEXT NOT NULL
      );
      INSERT INTO changes (view, host_id, thread_id, change_type, payload_json, created_at)
      VALUES
        ('dock', 'home', 'dock-1', 'old-dock-1', NULL, '2026-06-05T00:00:00.000Z'),
        ('archive', 'home', 'archive-1', 'old-archive-1', NULL, '2026-06-05T00:00:01.000Z'),
        ('dock', 'home', 'dock-2', 'old-dock-2', NULL, '2026-06-05T00:00:02.000Z');
    `);
    db.close();

    const store = new RelayStateStore({
      hostId: "home",
      relayStateDatabasePath: dbPath,
    });
    try {
      const changes = store.db.prepare(`
        SELECT seq, view, view_seq AS viewSeq
        FROM changes
        ORDER BY seq ASC
      `).all().map((row) => ({
        seq: row.seq,
        view: row.view,
        viewSeq: row.viewSeq,
      }));
      assert.deepEqual(
        changes,
        [
          { seq: 1, view: "dock", viewSeq: 1 },
          { seq: 2, view: "archive", viewSeq: 1 },
          { seq: 3, view: "dock", viewSeq: 2 },
        ],
      );
      assert.equal(store.currentSeq(), 3);
      assert.equal(store.currentSeqForView("dock"), 2);
      assert.equal(store.currentSeqForView("archive"), 1);
    } finally {
      store.close();
    }
  } finally {
    try {
      db.close();
    } catch {
      // Already closed by the migration path above.
    }
    rmSync(root, { recursive: true, force: true });
  }
});

test("relay state store clears derived cache when projection contract fingerprint changes", () => {
  const store = new RelayStateStore({
    hostId: "home",
    relayStateDatabasePath: ":memory:",
  });
  try {
    store.db.prepare(`
      INSERT OR REPLACE INTO hosts (host_id, display_name, endpoint, updated_at)
      VALUES ('home', 'Home', 'ws://home:4510', '2026-06-01T00:00:00.000Z')
    `).run();
    store.db.prepare(`
      INSERT INTO threads (
        host_id, thread_id, dock_id, status, archive_state, completeness,
        activity_proof_status, active_scope_present, archived_scope_present,
        freshness_status, updated_at
      ) VALUES (
        'home', 'thread-1', 'host:home/thread:thread-1/row:threadCard', 'idle',
        'active', 'complete', 'complete', 1, 0, 'fresh',
        '2026-06-01T00:00:00.000Z'
      )
    `).run();
    store.db.prepare(`
      UPDATE projection_cache_contract
      SET fingerprint = 'stale-projection-contract'
      WHERE contract_id = 'derived-projection-cache'
    `).run();

    assert.equal(store.db.prepare("SELECT COUNT(*) AS count FROM threads").get().count, 1);
    store.migrate();

    assert.equal(store.db.prepare("SELECT COUNT(*) AS count FROM threads").get().count, 0);
    const reset = store.db.prepare(`
      SELECT payload_json AS payload
      FROM changes
      WHERE change_type = 'projection-cache-schema-reset'
      ORDER BY seq DESC
      LIMIT 1
    `).get();
    assert.match(reset.payload, /stale-projection-contract/u);
  } finally {
    store.close();
  }
});

test("relay state store does not create projection changes for repeated fresh empty dock reconciles", () => {
  const store = new RelayStateStore({
    hostId: "home",
    relayStateDatabasePath: ":memory:",
  });
  const host = { id: "home", displayName: "Home", endpoint: null };
  try {
    const first = store.applyDockReconciliation({
      host,
      cards: [],
      scopes: [{
        name: "active:interactiveDefault",
        archived: false,
        sourceScope: "interactiveDefault",
        complete: true,
        error: null,
      }],
      complete: true,
    });
    assert.equal(first.changed, true);
    assert.equal(store.freshnessForHost("home", { archived: false }).status, "fresh");

    const second = store.applyDockReconciliation({
      host,
      cards: [],
      scopes: [{
        name: "active:interactiveDefault",
        archived: false,
        sourceScope: "interactiveDefault",
        complete: true,
        error: null,
      }],
      complete: true,
    });

    assert.equal(second.changed, false);
    assert.equal(second.seq, first.seq);
    assert.equal(store.currentSeqForView("dock"), first.seq);
  } finally {
    store.close();
  }
});

test("relay state store does not create projection changes for repeated fresh empty archive reconciles", () => {
  const store = new RelayStateStore({
    hostId: "home",
    relayStateDatabasePath: ":memory:",
  });
  const host = { id: "home", displayName: "Home", endpoint: null };
  try {
    const first = store.applyArchiveReconciliation({
      host,
      cards: [],
      complete: true,
      error: null,
    });
    assert.equal(first.changed, true);
    assert.equal(store.freshnessForHost("home", { archived: true }).status, "fresh");

    const second = store.applyArchiveReconciliation({
      host,
      cards: [],
      complete: true,
      error: null,
    });

    assert.equal(second.changed, false);
    assert.equal(second.seq, first.seq);
    assert.equal(store.currentSeqForView("archive"), first.seq);
  } finally {
    store.close();
  }
});

test("targeted card upsert publishes deletion when a card moves views", () => {
  const store = new RelayStateStore({
    hostId: "home",
    relayStateDatabasePath: ":memory:",
  });
  const host = { id: "home", displayName: "Home", endpoint: null };
  try {
    const archivedCard = testThreadCard({
      view: "archive",
      title: "Archived Thread",
    });
    const archiveInitial = store.applyArchiveReconciliation({
      host,
      cards: [archivedCard],
      complete: true,
      error: null,
    });
    assert.equal(archiveInitial.changed, true);
    assert.equal(store.listArchiveCards({ hostID: "home" }).totalRows, 1);
    assert.equal(store.listDockCards({ hostID: "home" }).totalRows, 0);

    const activeCard = testThreadCard({
      view: "dock",
      title: "Active Thread",
      activityAtMs: Date.parse("2026-06-05T00:00:01.000Z"),
    });
    const result = store.applyTargetedCardUpsert({
      host,
      card: activeCard,
      reason: "targeted-unarchive-read",
    });

    assert.equal(result.changed, true);
    assert.equal(result.view, "dock");
    assert.equal(result.rows[0]?.title, "Active Thread");
    assert.equal(result.removedFrom?.changed, true);
    assert.equal(result.removedFrom?.view, "archive");
    assert.deepEqual(result.removedFrom?.projectionIDs, [archivedCard.projectionID]);
    assert.equal(store.listArchiveCards({ hostID: "home" }).totalRows, 0);
    assert.equal(store.listDockCards({ hostID: "home" }).totalRows, 1);
  } finally {
    store.close();
  }
});

test("targeted card patch does not revive a removed scoped card", () => {
  const store = new RelayStateStore({
    hostId: "home",
    relayStateDatabasePath: ":memory:",
  });
  const host = { id: "home", displayName: "Home", endpoint: null };
  try {
    const card = testThreadCard({
      title: "Visible Thread",
    });
    const initial = store.applyDockReconciliation({
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
    });
    assert.equal(initial.changed, true);
    assert.equal(store.listDockCards({ hostID: "home" }).totalRows, 1);

    const removed = store.applyTargetedCardRemoval({
      host,
      threadID: card.threadID,
      reason: "thread/closed",
    });
    assert.equal(removed.changed, true);
    assert.deepEqual(removed.projectionIDs, [card.projectionID]);
    assert.equal(store.listDockCards({ hostID: "home" }).totalRows, 0);

    const patch = store.applyThreadCardPatch({
      host,
      threadID: card.threadID,
      patch: { title: "Resurrected Thread" },
      reason: "thread/name/updated",
    });
    assert.equal(patch.missing, true);
    assert.equal(patch.hidden, true);
    assert.equal(patch.changed, false);
    assert.equal(store.listDockCards({ hostID: "home" }).totalRows, 0);
  } finally {
    store.close();
  }
});

test("relay state store keeps outbound user-message commands outside derived projection resets", () => {
  const store = new RelayStateStore({
    hostId: "home",
    relayStateDatabasePath: ":memory:",
  });
  const outboundMessages = new RelayOutboundUserMessageStore(store.db);
  try {
    const inserted = outboundMessages.upsertAccepted({
      hostID: "home",
      threadID: "thread-1",
      clientUserMessageID: "dock-msg:1",
      inputJSON: JSON.stringify([{ text: "hello" }]),
      inputHash: "hash-1",
      at: "2026-06-04T00:00:00.000Z",
    });
    assert.equal(inserted.status, "inserted");
    assert.equal(inserted.row.state, "acceptedByRelay");

    const existing = outboundMessages.upsertAccepted({
      hostID: "home",
      threadID: "thread-1",
      clientUserMessageID: "dock-msg:1",
      inputJSON: JSON.stringify([{ text: "hello" }]),
      inputHash: "hash-1",
      at: "2026-06-04T00:00:01.000Z",
    });
    assert.equal(existing.status, "existing");

    const collision = outboundMessages.upsertAccepted({
      hostID: "home",
      threadID: "thread-1",
      clientUserMessageID: "dock-msg:1",
      inputJSON: JSON.stringify([{ text: "different" }]),
      inputHash: "hash-2",
      at: "2026-06-04T00:00:02.000Z",
    });
    assert.equal(collision.status, "collision");

    const submitted = outboundMessages.markSubmitted({
      hostID: "home",
      threadID: "thread-1",
      clientUserMessageID: "dock-msg:1",
      upstreamEndpointUrl: "ws://home:4500",
      upstreamMethod: "turn/start",
      codexTurnID: "turn-1",
      at: "2026-06-04T00:00:03.000Z",
    });
    assert.equal(submitted.state, "submittedUpstream");
    assert.equal(submitted.codexTurnID, "turn-1");

    store.resetDerivedProjectionCache(4);
    const afterReset = outboundMessages.messageForClientID("home", "thread-1", "dock-msg:1");
    assert.equal(afterReset.state, "submittedUpstream");
    assert.equal(afterReset.upstreamMethod, "turn/start");

    const canonical = outboundMessages.markCanonicalObserved({
      hostID: "home",
      threadID: "thread-1",
      clientUserMessageID: "dock-msg:1",
      codexTurnID: "turn-1",
      codexItemID: "item-1",
      at: "2026-06-04T00:00:04.000Z",
    });
    assert.equal(canonical.state, "canonicalObserved");
    assert.equal(canonical.codexItemID, "item-1");
  } finally {
    store.close();
  }
});

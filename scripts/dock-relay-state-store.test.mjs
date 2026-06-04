import assert from "node:assert/strict";
import test from "node:test";

import { RelayOutboundUserMessageStore } from "./dock-relay-outbound-user-message-store.mjs";
import { RelayStateStore } from "./dock-relay-state-store.mjs";

test("relay state store exposes per-view stream sequence cursors", () => {
  const store = new RelayStateStore({
    hostId: "home",
    relayStateDatabasePath: ":memory:",
  });
  try {
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

    assert.equal(store.currentSeq(), archiveOnly);
    assert.equal(store.currentSeqForView("dock"), dockFirst);
    assert.equal(store.currentSeqForView("archive"), archiveOnly);

    const dockBaseSeq = store.currentSeqForView("dock");
    const dockSecond = store.recordChange({
      view: "dock",
      hostID: "home",
      changeType: "fixture-dock-second",
    });

    assert.equal(dockBaseSeq, dockFirst);
    assert.equal(dockSecond, archiveOnly + 1);
    assert.equal(store.currentSeqForView("dock"), dockSecond);
  } finally {
    store.close();
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

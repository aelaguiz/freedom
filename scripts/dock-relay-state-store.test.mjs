import assert from "node:assert/strict";
import test from "node:test";

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

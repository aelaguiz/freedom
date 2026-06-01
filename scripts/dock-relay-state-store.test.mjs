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

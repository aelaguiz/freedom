import assert from "node:assert/strict";
import test from "node:test";

import {
  ThreadDetailLedger,
  eventFromRequest,
  eventsFromNotification,
  eventsFromThread,
} from "./dock-relay-thread-detail-ledger.mjs";

function historyThread() {
  return {
    id: "thread-1",
    turns: [{
      id: "turn-1",
      startedAt: 1_800_000_000,
      completedAt: 1_800_000_010,
      items: [{
        id: "item-user-1",
        type: "userMessage",
        content: [{ text: "hello" }],
      }, {
        id: "item-agent-1",
        type: "agentMessage",
        text: "hi",
      }],
    }],
  };
}

function fileChangeItem() {
  return {
    id: "item-file-1",
    type: "fileChange",
    status: "completed",
    changes: [{
      path: "CodexDock/AppServer/ThreadDetailDTO.swift",
      kind: {
        type: "update",
        move_path: null,
      },
      diff: "@@ -1,3 +1,4 @@\n import Foundation\n-old line\n+new line\n+added line\n context\n",
    }],
  };
}

function fileChangeThread() {
  return {
    id: "thread-1",
    turns: [{
      id: "turn-1",
      startedAt: 1_800_000_000,
      completedAt: 1_800_000_010,
      items: [fileChangeItem()],
    }],
  };
}

test("thread detail ledger gives history and live item notifications the same user-message event id", () => {
  const historyEvent = eventsFromThread(historyThread(), { sourceHostID: "home" })
    .find((event) => event.payload.renderKind === "userMessage");
  const liveEvent = eventsFromNotification({
    method: "item/completed",
    params: {
      threadId: "thread-1",
      turnId: "turn-1",
      itemId: "item-user-1",
      completedAtMs: 1_800_000_001_000,
      item: {
        type: "userMessage",
        content: [{ text: "hello" }],
      },
    },
  }, { sourceHostID: "home", nowMs: 1_800_000_001_000 }).find((event) => event.payload.renderKind === "userMessage");

  assert.equal(liveEvent.projectionID, historyEvent.projectionID);
  assert.equal(liveEvent.payload.itemID, "item-user-1");
});

test("thread detail projection rows carry the shared projection envelope", () => {
  const rows = [
    ...eventsFromThread(historyThread(), { sourceHostID: "home" }),
    eventFromRequest({
      id: "request-1",
      method: "item/commandExecution/requestApproval",
      params: {
        threadId: "thread-1",
        turnId: "turn-1",
        itemId: "item-command-1",
        command: ["echo", "hi"],
      },
    }, 1_800_000_005_000, { sourceHostID: "home" }),
  ];

  assert.ok(rows.length > 0);
  for (const row of rows) {
    assert.equal(row.schemaVersion, 1);
    assert.equal(row.identityVersion, 1);
    assert.equal(row.projectionEngineVersion, 1);
    assert.equal(row.sourceHostID, "home");
    assert.equal(row.view, "thread.detail");
    assert.equal(row.threadID, "thread-1");
    assert.ok(row.projectionID.startsWith("host:home/thread:thread-1/"));
    assert.ok(row.sourceRef.startsWith("host:home/thread:thread-1"));
    assert.ok(row.rowRole);
    assert.ok(row.displayOrderKey);
  }
});

test("thread detail ledger upserts live user message and canonical history into one row", () => {
  const ledger = new ThreadDetailLedger({ sourceHostID: "home", threadID: "thread-1" });
  const live = eventsFromNotification({
    method: "item/completed",
    params: {
      threadId: "thread-1",
      turnId: "turn-1",
      itemId: "item-user-1",
      item: {
        type: "userMessage",
        content: [{ text: "hello" }],
      },
    },
  }, { sourceHostID: "home", nowMs: 1_800_000_001_000 })[0];

  ledger.upsertRow(live);
  ledger.replaceFromThread(historyThread());

  const userRows = ledger.snapshot().rows.filter((event) => event.payload.renderKind === "userMessage");
  assert.equal(userRows.length, 1);
  assert.equal(userRows[0].payload.body, "hello");
});

test("thread detail resync merge preserves live rows while history lags", () => {
  const ledger = new ThreadDetailLedger({ sourceHostID: "home", threadID: "thread-1" });
  ledger.replaceFromThread(historyThread());

  const update = ledger.applyNotification({
    method: "item/agentMessage/delta",
    params: {
      threadId: "thread-1",
      turnId: "turn-live",
      itemId: "agent-live",
      delta: "new live work",
    },
  }, { nowMs: 1_800_000_020_000 });
  assert.equal(update.scope, "thread");

  ledger.mergeFromThread(historyThread());

  const snapshot = ledger.snapshot();
  assert.deepEqual(
    snapshot.rows.map((row) => row.projectionID),
    [
      "host:home/thread:thread-1/turn:turn-live/item:agent-live/row:agentMessage",
      "host:home/thread:thread-1/turn:turn-1/item:item-agent-1/row:agentMessage",
      "host:home/thread:thread-1/turn:turn-1/item:item-user-1/row:userMessage",
    ]
  );
});

test("thread detail ledger rows carry the full projection envelope", () => {
  const ledger = new ThreadDetailLedger({ sourceHostID: "home", threadID: "thread-1" });
  ledger.replaceFromThread(historyThread());

  const snapshot = ledger.snapshot();
  assert.equal(snapshot.schemaVersion, 1);
  assert.equal(snapshot.identityVersion, 1);
  assert.equal(snapshot.projectionEngineVersion, 1);
  for (const row of snapshot.rows) {
    assert.equal(row.schemaVersion, snapshot.schemaVersion);
    assert.equal(row.identityVersion, snapshot.identityVersion);
    assert.equal(row.projectionEngineVersion, snapshot.projectionEngineVersion);
    assert.equal(row.sourceHostID, snapshot.sourceHostID);
    assert.equal(row.view, "thread.detail");
    assert.equal(row.threadID, snapshot.threadID);
    assert.match(row.projectionID, /^host:home\/thread:thread-1\//);
    assert.match(row.sourceRef, /^host:home\/thread:thread-1\//);
    assert.equal(typeof row.rowRole, "string");
    assert.notEqual(row.rowRole, "");
    assert.equal(typeof row.displayOrderKey, "string");
    assert.notEqual(row.displayOrderKey, "");
  }
});

test("thread detail ledger uses one event id for streaming agent delta and completed item", () => {
  const ledger = new ThreadDetailLedger({ sourceHostID: "home", threadID: "thread-1" });
  const first = ledger.applyNotification({
    method: "item/agentMessage/delta",
    params: {
      threadId: "thread-1",
      turnId: "turn-1",
      itemId: "item-agent-1",
      delta: "he",
    },
  }, { nowMs: 1_800_000_002_000 });
  const second = ledger.applyNotification({
    method: "item/agentMessage/delta",
    params: {
      threadId: "thread-1",
      turnId: "turn-1",
      itemId: "item-agent-1",
      delta: "llo",
    },
  }, { nowMs: 1_800_000_003_000 });
  const completed = ledger.applyNotification({
    method: "item/completed",
    params: {
      threadId: "thread-1",
      turnId: "turn-1",
      itemId: "item-agent-1",
      completedAtMs: 1_800_000_004_000,
      item: {
        type: "agentMessage",
        text: "hello",
      },
    },
  }, { nowMs: 1_800_000_004_000 });

  assert.equal(first.rows[0].projectionID, second.rows[0].projectionID);
  assert.equal(second.rows[0].payload.body, "hello");
  assert.equal(completed.rows[0].projectionID, first.rows[0].projectionID);
  assert.equal(ledger.snapshot().rows.filter((event) => event.payload.renderKind === "agentMessage").length, 1);
  assert.equal(ledger.snapshot().rows[0].payload.body, "hello");
});

test("thread detail ledger does not invent item identities when live items lack stable ids", () => {
  const rows = eventsFromNotification({
    method: "item/completed",
    params: {
      threadId: "thread-1",
      item: {
        type: "userMessage",
        content: [{ text: "hello" }],
      },
    },
  }, { sourceHostID: "home", nowMs: 1_800_000_004_000 });

  assert.equal(rows.length, 1);
  assert.equal(rows[0].rowRole, "unknown");
  assert.equal(rows[0].payload.renderKind, "unknown");
  assert.equal(rows[0].payload.diagnostic.code, "turnID_missing");
  assert.match(rows[0].projectionID, /^host:home\/thread:thread-1\/diagnostic:/u);
  assert.doesNotMatch(rows[0].projectionID, /turn:unknown|item:/u);
});

test("thread detail item-backed request uses the item row id and request id stays response-only", () => {
  const event = eventFromRequest({
    id: "request-1",
    method: "item/commandExecution/requestApproval",
    params: {
      threadId: "thread-1",
      turnId: "turn-1",
      itemId: "item-command-1",
      command: ["echo", "hi"],
    },
  }, 1_800_000_005_000, { sourceHostID: "home" });

  assert.equal(event.projectionID, "host:home/thread:thread-1/turn:turn-1/item:item-command-1/row:command");
  assert.equal(event.sourceRef, "host:home/thread:thread-1/turn:turn-1/item:item-command-1");
  assert.equal(event.rowRole, "command");
  assert.equal(event.payload.renderKind, "command");
  assert.equal(event.payload.request.requestID, "request-1");
  assert.equal(event.payload.request.method, "item/commandExecution/requestApproval");
  assert.equal(event.payload.body, "echo hi");
});

test("thread detail projects file-change items with structured diff payload", () => {
  const event = eventsFromThread(fileChangeThread(), { sourceHostID: "home" })[0];

  assert.equal(event.projectionID, "host:home/thread:thread-1/turn:turn-1/item:item-file-1/row:fileChange");
  assert.equal(event.rowRole, "fileChange");
  assert.equal(event.payload.renderKind, "request");
  assert.equal(event.payload.body, "1 file changed, +2 -1");
  assert.equal(event.payload.fileChange.version, 1);
  assert.equal(event.payload.fileChange.status, "completed");
  assert.equal(event.payload.fileChange.approvalRequired, false);
  assert.deepEqual(event.payload.fileChange.summary, {
    fileCount: 1,
    additions: 2,
    deletions: 1,
    truncated: false,
  });
  assert.equal(event.payload.fileChange.changes[0].path, "CodexDock/AppServer/ThreadDetailDTO.swift");
  assert.equal(event.payload.fileChange.changes[0].kind, "update");
  assert.equal(event.payload.fileChange.changes[0].diffAvailability, "available");
});

test("thread detail file-change projection normalizes add delete move and limited diffs", () => {
  const event = eventsFromThread({
    id: "thread-1",
    turns: [{
      id: "turn-1",
      startedAt: 1_800_000_000,
      completedAt: 1_800_000_010,
      items: [{
        id: "item-file-2",
        type: "fileChange",
        status: "completed",
        changes: [{
          path: "CodexDock/NewModel.swift",
          kind: "add",
          content: "let one = 1\nlet two = 2\n",
        }, {
          path: "CodexDock/OldModel.swift",
          kind: "delete",
          content: "let old = 1\nlet stale = 2\n",
        }, {
          path: "CodexDock/RenamedModel.swift",
          kind: {
            type: "move",
            move_path: "CodexDock/OriginalModel.swift",
          },
          diff: "@@ -1,1 +1,1 @@\n-oldName\n+newName\n",
        }, {
          path: "CodexDock/Generated/Large.swift",
          kind: "update",
          diffAvailability: "truncated",
          diff: "@@ -1,1 +1,1 @@\n-oldGenerated\n+newGenerated\n",
        }],
      }],
    }],
  }, { sourceHostID: "home" })[0];

  assert.equal(event.payload.body, "4 files changed, +4 -4");
  assert.deepEqual(event.payload.fileChange.summary, {
    fileCount: 4,
    additions: 4,
    deletions: 4,
    truncated: true,
  });
  assert.deepEqual(
    event.payload.fileChange.changes.map((change) => ({
      path: change.path,
      oldPath: change.oldPath,
      kind: change.kind,
      additions: change.additions,
      deletions: change.deletions,
      diffAvailability: change.diffAvailability,
      truncated: change.truncated,
    })),
    [{
      path: "CodexDock/NewModel.swift",
      oldPath: null,
      kind: "add",
      additions: 2,
      deletions: 0,
      diffAvailability: "available",
      truncated: false,
    }, {
      path: "CodexDock/OldModel.swift",
      oldPath: null,
      kind: "delete",
      additions: 0,
      deletions: 2,
      diffAvailability: "available",
      truncated: false,
    }, {
      path: "CodexDock/RenamedModel.swift",
      oldPath: "CodexDock/OriginalModel.swift",
      kind: "move",
      additions: 1,
      deletions: 1,
      diffAvailability: "available",
      truncated: false,
    }, {
      path: "CodexDock/Generated/Large.swift",
      oldPath: null,
      kind: "update",
      additions: 1,
      deletions: 1,
      diffAvailability: "tooLarge",
      truncated: true,
    }]
  );
  assert.equal(event.payload.fileChange.changes[3].unavailableReason, "tooLarge");
});

test("thread detail file-change approval carries unavailable payload when no diff is attached", () => {
  const event = eventFromRequest({
    id: "request-file-1",
    method: "item/fileChange/requestApproval",
    params: {
      threadId: "thread-1",
      turnId: "turn-1",
      itemId: "item-file-1",
      reason: "Approve file change",
    },
  }, 1_800_000_005_000, { sourceHostID: "home" });

  assert.equal(event.projectionID, "host:home/thread:thread-1/turn:turn-1/item:item-file-1/row:fileChange");
  assert.equal(event.rowRole, "fileChange");
  assert.equal(event.payload.request.requestID, "request-file-1");
  assert.equal(event.payload.body, "Diff unavailable on phone.");
  assert.equal(event.payload.fileChange.status, "pending");
  assert.equal(event.payload.fileChange.approvalRequired, true);
  assert.equal(event.payload.fileChange.summary.fileCount, 0);
  assert.deepEqual(event.payload.fileChange.changes, []);
  assert.equal(event.payload.fileChange.unavailableReason, "missingDiff");
});

test("thread detail unsupported request methods stay standalone request rows", () => {
  const event = eventFromRequest({
    id: "request-1",
    method: "item/tool/requestUserInput",
    params: {
      threadId: "thread-1",
      turnId: "turn-1",
      itemId: "item-tool-1",
      message: "Pick one",
    },
  }, 1_800_000_005_000, { sourceHostID: "home" });

  assert.equal(event.projectionID, "host:home/thread:thread-1/turn:turn-1/item:item-tool-1/request:request-1/row:request");
  assert.equal(event.rowRole, "request");
  assert.equal(event.payload.renderKind, "request");
  assert.equal(event.payload.request.requestID, "request-1");
});

test("thread detail ledger merges item-backed request state into the canonical item row", () => {
  const ledger = new ThreadDetailLedger({ sourceHostID: "home", threadID: "thread-1" });
  const requestUpdate = ledger.applyRequest({
    id: "request-1",
    method: "item/commandExecution/requestApproval",
    params: {
      threadId: "thread-1",
      turnId: "turn-1",
      itemId: "item-command-1",
      command: ["echo", "hi"],
    },
  }, { nowMs: 1_800_000_005_000 });
  const itemUpdate = ledger.applyNotification({
    method: "item/completed",
    params: {
      threadId: "thread-1",
      turnId: "turn-1",
      itemId: "item-command-1",
      item: {
        type: "commandExecution",
        command: ["echo", "hi"],
      },
    },
  }, { nowMs: 1_800_000_006_000 });

  assert.equal(requestUpdate.rows[0].projectionID, itemUpdate.rows[0].projectionID);
  const commandRows = ledger.snapshot().rows.filter((event) => event.rowRole === "command");
  assert.equal(commandRows.length, 1);
  assert.equal(commandRows[0].projectionID, "host:home/thread:thread-1/turn:turn-1/item:item-command-1/row:command");
  assert.equal(commandRows[0].payload.request.requestID, "request-1");
  assert.equal(commandRows[0].payload.visibility, "request");
});

test("thread detail ledger preserves file-change payload when approval arrives after item", () => {
  const ledger = new ThreadDetailLedger({ sourceHostID: "home", threadID: "thread-1" });
  ledger.replaceFromThread(fileChangeThread());
  const requestUpdate = ledger.applyRequest({
    id: "request-file-1",
    method: "item/fileChange/requestApproval",
    params: {
      threadId: "thread-1",
      turnId: "turn-1",
      itemId: "item-file-1",
      reason: "Approve file change",
    },
  }, { nowMs: 1_800_000_005_000 });

  const row = requestUpdate.rows[0];
  assert.equal(row.projectionID, "host:home/thread:thread-1/turn:turn-1/item:item-file-1/row:fileChange");
  assert.equal(row.payload.request.requestID, "request-file-1");
  assert.equal(row.payload.fileChange.approvalRequired, true);
  assert.equal(row.payload.fileChange.status, "pending");
  assert.equal(row.payload.fileChange.summary.fileCount, 1);
  assert.equal(row.payload.fileChange.changes[0].diffAvailability, "available");
  assert.equal(row.payload.body, "Review 1 file before approving, +2 -1");
});

test("thread detail ledger preserves request state when file-change item arrives after approval", () => {
  const ledger = new ThreadDetailLedger({ sourceHostID: "home", threadID: "thread-1" });
  const requestUpdate = ledger.applyRequest({
    id: "request-file-1",
    method: "item/fileChange/requestApproval",
    params: {
      threadId: "thread-1",
      turnId: "turn-1",
      itemId: "item-file-1",
      reason: "Approve file change",
    },
  }, { nowMs: 1_800_000_005_000 });
  const itemUpdate = ledger.applyNotification({
    method: "item/completed",
    params: {
      threadId: "thread-1",
      turnId: "turn-1",
      itemId: "item-file-1",
      item: {
        ...fileChangeItem(),
        id: undefined,
      },
    },
  }, { nowMs: 1_800_000_006_000 });

  assert.equal(requestUpdate.rows[0].projectionID, itemUpdate.rows[0].projectionID);
  const fileChangeRows = ledger.snapshot().rows.filter((event) => event.rowRole === "fileChange");
  assert.equal(fileChangeRows.length, 1);
  assert.equal(fileChangeRows[0].payload.request.requestID, "request-file-1");
  assert.equal(fileChangeRows[0].payload.visibility, "request");
  assert.equal(fileChangeRows[0].payload.fileChange.approvalRequired, true);
  assert.equal(fileChangeRows[0].payload.fileChange.summary.fileCount, 1);
  assert.equal(fileChangeRows[0].payload.fileChange.changes[0].path, "CodexDock/AppServer/ThreadDetailDTO.swift");
  assert.equal(fileChangeRows[0].payload.body, "Review 1 file before approving, +2 -1");
});

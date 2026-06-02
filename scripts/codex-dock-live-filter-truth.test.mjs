import assert from "node:assert/strict";
import test from "node:test";

import { filterCountsFromProjectionRows, summarizeSamples } from "./codex-dock-live-filter-truth.mjs";

function row({
  projectionID,
  displayOrderKey,
  kind,
  visibility,
  itemType = kind,
  turnID = "turn-1",
  itemID = "item-1",
}) {
  return {
    projectionID,
    sourceHostID: "host",
    displayOrderKey,
    renderKind: kind,
    visibility,
    itemType,
    turnID,
    itemID,
  };
}

test("live filter truth counts projection command rows without inventing whitespace-only output", () => {
  const counts = filterCountsFromProjectionRows([
    row({
      projectionID: "host:host/thread:thread-a/turn:turn-1/item:command-1/row:command",
      displayOrderKey: "001",
      kind: "command",
      visibility: "tooling",
      itemType: "commandExecution",
      itemID: "command-1",
    }),
  ], 240);

  assert.equal(counts.visibleCounts.all, 1);
  assert.equal(counts.visibleCounts.command, 1);
  assert.equal(counts.visibleCounts.output, 0);
});

test("live filter truth counts relay-emitted command output projection rows", () => {
  const counts = filterCountsFromProjectionRows([
    row({
      projectionID: "host:host/thread:thread-a/turn:turn-1/item:command-1/row:command",
      displayOrderKey: "001",
      kind: "command",
      visibility: "tooling",
      itemType: "commandExecution",
      itemID: "command-1",
    }),
    row({
      projectionID: "host:host/thread:thread-a/turn:turn-1/item:command-1/row:commandOutput",
      displayOrderKey: "002",
      kind: "output",
      visibility: "tooling",
      itemType: "commandExecution",
      itemID: "command-1",
    }),
  ], 240);

  assert.equal(counts.visibleCounts.all, 2);
  assert.equal(counts.visibleCounts.command, 1);
  assert.equal(counts.visibleCounts.output, 1);
});

test("live filter truth exposes visible projection ids in Thread Detail render order", () => {
  const counts = filterCountsFromProjectionRows([
    row({
      projectionID: "host:host/thread:thread-a/turn:new-turn/item:old-agent/row:agentMessage",
      displayOrderKey: "002",
      kind: "agentMessage",
      visibility: "message",
      itemID: "old-agent",
      turnID: "new-turn",
    }),
    row({
      projectionID: "host:host/thread:thread-a/turn:new-turn/item:new-agent/row:agentMessage",
      displayOrderKey: "001",
      kind: "agentMessage",
      visibility: "message",
      itemID: "new-agent",
      turnID: "new-turn",
    }),
    row({
      projectionID: "host:host/thread:thread-a/turn:older-turn/item:older-user/row:userMessage",
      displayOrderKey: "003",
      kind: "userMessage",
      visibility: "message",
      itemID: "older-user",
      turnID: "older-turn",
    }),
  ], 240);

  assert.deepEqual(counts.visibleProjectionIDs.messages.slice(0, 3), [
    "host:host/thread:thread-a/turn:new-turn/item:new-agent/row:agentMessage",
    "host:host/thread:thread-a/turn:new-turn/item:old-agent/row:agentMessage",
    "host:host/thread:thread-a/turn:older-turn/item:older-user/row:userMessage",
  ]);
});

test("live filter truth caps visible projection ids with the same visible window as counts", () => {
  const counts = filterCountsFromProjectionRows([
    row({
      projectionID: "host:host/thread:thread-a/turn:turn-1/item:item-1/row:agentMessage",
      displayOrderKey: "003",
      kind: "agentMessage",
      visibility: "message",
      itemID: "item-1",
    }),
    row({
      projectionID: "host:host/thread:thread-a/turn:turn-1/item:item-2/row:agentMessage",
      displayOrderKey: "002",
      kind: "agentMessage",
      visibility: "message",
      itemID: "item-2",
    }),
    row({
      projectionID: "host:host/thread:thread-a/turn:turn-1/item:item-3/row:agentMessage",
      displayOrderKey: "001",
      kind: "agentMessage",
      visibility: "message",
      itemID: "item-3",
    }),
  ], 2);

  assert.equal(counts.visibleCounts.messages, 2);
  assert.deepEqual(counts.visibleProjectionIDs.messages, [
    "host:host/thread:thread-a/turn:turn-1/item:item-3/row:agentMessage",
    "host:host/thread:thread-a/turn:turn-1/item:item-2/row:agentMessage",
  ]);
});

test("live filter truth summary treats capped visible projection id changes as movement", () => {
  const summary = summarizeSamples([
    {
      sampledAt: "2026-06-01T13:00:00.000Z",
      finishedAt: "2026-06-01T13:00:00.100Z",
      dock: { targetCard: { activityAt: "2026-06-01T13:00:00.000Z" } },
      turns: {
        visibleCounts: { messages: 240 },
        visibleProjectionIDs: { messages: ["host:host/thread:thread-a/turn:turn-a/item:item-a/row:agentMessage", "host:host/thread:thread-a/turn:turn-old/item:item-old/row:agentMessage"] },
      },
    },
    {
      sampledAt: "2026-06-01T13:00:01.000Z",
      finishedAt: "2026-06-01T13:00:01.100Z",
      dock: { targetCard: { activityAt: "2026-06-01T13:00:00.000Z" } },
      turns: {
        visibleCounts: { messages: 240 },
        visibleProjectionIDs: { messages: ["host:host/thread:thread-a/turn:turn-b/item:item-b/row:agentMessage", "host:host/thread:thread-a/turn:turn-a/item:item-a/row:agentMessage"] },
      },
    },
  ]);

  assert.equal(summary.moving, true);
  assert.equal(summary.filters.messages.changed, true);
  assert.deepEqual(summary.filters.messages.visibleProjectionIDHeadUnique, ["host:host/thread:thread-a/turn:turn-a/item:item-a/row:agentMessage", "host:host/thread:thread-a/turn:turn-b/item:item-b/row:agentMessage"]);
});

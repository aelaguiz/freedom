import assert from "node:assert/strict";
import test from "node:test";

import { filterCountsFromTurns, summarizeSamples } from "./codex-dock-live-filter-truth.mjs";

test("live filter truth ignores whitespace-only command output like Swift", () => {
  const turn = {
    id: "turn-1",
    items: [
      {
        id: "command-1",
        type: "commandExecution",
        command: "true",
        aggregatedOutput: "\n",
      },
    ],
  };

  const counts = filterCountsFromTurns([turn], 240);

  assert.equal(counts.visibleCounts.all, 1);
  assert.equal(counts.visibleCounts.command, 1);
  assert.equal(counts.visibleCounts.output, 0);
});

test("live filter truth counts non-empty command output like Swift", () => {
  const turn = {
    id: "turn-1",
    items: [
      {
        id: "command-1",
        type: "commandExecution",
        command: "echo ok",
        aggregatedOutput: "ok\n",
      },
    ],
  };

  const counts = filterCountsFromTurns([turn], 240);

  assert.equal(counts.visibleCounts.all, 2);
  assert.equal(counts.visibleCounts.command, 1);
  assert.equal(counts.visibleCounts.output, 1);
});

test("live filter truth exposes visible event ids in Thread Detail render order", () => {
  const turns = [
    {
      id: "new-turn",
      startedAt: 100,
      completedAt: 110,
      items: [
        { id: "old-agent", type: "agentMessage", text: "old" },
        { id: "new-agent", type: "agentMessage", text: "new" },
      ],
    },
    {
      id: "older-turn",
      startedAt: 90,
      completedAt: 95,
      items: [
        { id: "older-user", type: "userMessage", content: [{ text: "older" }] },
      ],
    },
  ];

  const counts = filterCountsFromTurns(turns, 240);

  assert.deepEqual(counts.visibleEventIDs.messages.slice(0, 3), [
    "new-turn-new-agent-agent",
    "new-turn-old-agent-agent",
    "older-turn-older-user-user",
  ]);
});

test("live filter truth caps visible event ids with the same visible window as counts", () => {
  const turn = {
    id: "turn-1",
    startedAt: 100,
    completedAt: 110,
    items: [
      { id: "item-1", type: "agentMessage", text: "one" },
      { id: "item-2", type: "agentMessage", text: "two" },
      { id: "item-3", type: "agentMessage", text: "three" },
    ],
  };

  const counts = filterCountsFromTurns([turn], 2);

  assert.equal(counts.visibleCounts.messages, 2);
  assert.deepEqual(counts.visibleEventIDs.messages, [
    "turn-1-item-3-agent",
    "turn-1-item-2-agent",
  ]);
});

test("live filter truth summary treats capped visible event id changes as movement", () => {
  const summary = summarizeSamples([
    {
      sampledAt: "2026-06-01T13:00:00.000Z",
      finishedAt: "2026-06-01T13:00:00.100Z",
      dock: { targetCard: { activityAt: "2026-06-01T13:00:00.000Z" } },
      turns: {
        visibleCounts: { messages: 240 },
        visibleEventIDs: { messages: ["event-a", "event-old"] },
      },
    },
    {
      sampledAt: "2026-06-01T13:00:01.000Z",
      finishedAt: "2026-06-01T13:00:01.100Z",
      dock: { targetCard: { activityAt: "2026-06-01T13:00:00.000Z" } },
      turns: {
        visibleCounts: { messages: 240 },
        visibleEventIDs: { messages: ["event-b", "event-a"] },
      },
    },
  ]);

  assert.equal(summary.moving, true);
  assert.equal(summary.filters.messages.changed, true);
  assert.deepEqual(summary.filters.messages.visibleEventIDHeadUnique, ["event-a", "event-b"]);
});

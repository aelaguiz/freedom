import assert from "node:assert/strict";
import test from "node:test";

import {
  latestMeaningfulMessageFromTurns,
  latestMeaningfulSummaryFromTurns,
} from "./dock-relay-thread-summary.mjs";

test("latestMeaningfulMessageFromTurns prefers newest user or agent message", () => {
  const message = latestMeaningfulMessageFromTurns([
    {
      id: "old-turn",
      startedAt: "2026-06-05T12:00:00.000Z",
      items: [{ type: "userMessage", text: "Old prompt" }],
    },
    {
      id: "new-turn",
      startedAt: "2026-06-05T12:01:00.000Z",
      items: [{ type: "agentMessage", text: "Newest answer" }],
    },
  ]);

  assert.equal(message?.text, "Newest answer");
  assert.equal(message?.role, "agent");
  assert.equal(message?.timestampMs, Date.parse("2026-06-05T12:01:00.000Z"));
  assert.equal(
    message?.timestampSeconds,
    Math.floor(Date.parse("2026-06-05T12:01:00.000Z") / 1000),
  );
});

test("latestMeaningfulMessageFromTurns ignores non-message items and reads array content", () => {
  const message = latestMeaningfulMessageFromTurns([
    {
      id: "mixed-turn",
      startedAt: "2026-06-05T12:00:00.000Z",
      items: [
        { type: "toolResult", text: "not card text" },
        {
          type: "agentMessage",
          content: [{ text: "Visible" }, { content: "summary" }],
        },
      ],
    },
  ]);

  assert.equal(message?.text, "Visible\nsummary");
  assert.equal(latestMeaningfulSummaryFromTurns([]), null);
});

test("latestMeaningfulMessageFromTurns is deterministic without timestamps", () => {
  const message = latestMeaningfulMessageFromTurns([
    {
      id: "untimed-turn",
      items: [
        { type: "userMessage", text: "First" },
        { type: "agentMessage", text: "Second" },
      ],
    },
  ]);

  assert.equal(message?.text, "Second");
  assert.equal(message?.timestampMs, 0);
  assert.equal(message?.timestampSeconds, 0);
});

function parseTimestampMs(value) {
  if (value === null || value === undefined) {
    return null;
  }
  if (typeof value === "number" && Number.isFinite(value)) {
    return value < 10_000_000_000 ? value * 1000 : value;
  }
  if (typeof value === "string" && value.length > 0) {
    const parsed = Date.parse(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function nonEmptyText(value) {
  if (typeof value !== "string") {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function textFromContent(content) {
  if (typeof content === "string") {
    return content;
  }
  if (!Array.isArray(content)) {
    return "";
  }
  return content
    .map((part) => {
      if (typeof part === "string") {
        return part;
      }
      if (!part || typeof part !== "object") {
        return "";
      }
      return part.text || textFromContent(part.content);
    })
    .filter(Boolean)
    .join("\n");
}

function textFromItem(item) {
  if (!item || typeof item !== "object") {
    return null;
  }
  return nonEmptyText(item.text)
    || nonEmptyText(textFromContent(item.content));
}

function isMessageSummaryCandidate(item) {
  return item?.type === "userMessage" || item?.type === "agentMessage";
}

function roleForItem(item) {
  if (item?.type === "userMessage") {
    return "user";
  }
  if (item?.type === "agentMessage") {
    return "agent";
  }
  return null;
}

function turnMessageTimestampMs(turn, item) {
  return parseTimestampMs(item?.timestampMs)
    ?? parseTimestampMs(item?.timestamp)
    ?? parseTimestampMs(item?.createdAtMs)
    ?? parseTimestampMs(item?.createdAt)
    ?? parseTimestampMs(turn?.activityAtMs)
    ?? parseTimestampMs(turn?.activityAt)
    ?? parseTimestampMs(turn?.updatedAtMs)
    ?? parseTimestampMs(turn?.updatedAt)
    ?? parseTimestampMs(turn?.completedAtMs)
    ?? parseTimestampMs(turn?.completedAt)
    ?? parseTimestampMs(turn?.finishedAtMs)
    ?? parseTimestampMs(turn?.finishedAt)
    ?? parseTimestampMs(turn?.startedAtMs)
    ?? parseTimestampMs(turn?.startedAt)
    ?? parseTimestampMs(turn?.createdAtMs)
    ?? parseTimestampMs(turn?.createdAt)
    ?? 0;
}

function eventPrecedes(lhs, rhs) {
  if (lhs.timestampMs !== rhs.timestampMs) {
    return lhs.timestampMs < rhs.timestampMs;
  }
  if (lhs.pageIndex !== rhs.pageIndex) {
    return lhs.pageIndex < rhs.pageIndex;
  }
  if (lhs.turnIndex !== rhs.turnIndex) {
    return lhs.turnIndex < rhs.turnIndex;
  }
  return lhs.itemIndex < rhs.itemIndex;
}

function latestMeaningfulMessageFromTurns(turns = [], { pageIndex = 0 } = {}) {
  let latest = null;
  turns.forEach((turn, turnIndex) => {
    const items = Array.isArray(turn?.items) ? turn.items : [];
    items.forEach((item, itemIndex) => {
      if (!isMessageSummaryCandidate(item)) {
        return;
      }
      const text = textFromItem(item);
      if (!text) {
        return;
      }
      const timestampMs = turnMessageTimestampMs(turn, item);
      const candidate = {
        text,
        role: roleForItem(item),
        timestampMs,
        timestampSeconds: Math.floor(timestampMs / 1000),
        pageIndex,
        turnIndex,
        itemIndex,
      };
      if (!latest || eventPrecedes(latest, candidate)) {
        latest = candidate;
      }
    });
  });
  return latest;
}

function latestMeaningfulSummaryFromTurns(turns = []) {
  return latestMeaningfulMessageFromTurns(turns)?.text || null;
}

export {
  latestMeaningfulMessageFromTurns,
  latestMeaningfulSummaryFromTurns,
};

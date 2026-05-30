import crypto from "node:crypto";

import { defaultRelayLogger } from "./dock-relay-logger.mjs";

const DEFAULT_SUMMARY_TURN_LIMIT = 10;
const DEFAULT_MAX_ENTRIES = 500;
const DEFAULT_MAX_CONCURRENT = 2;

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

function rowVersion(row) {
  return String(row?.updatedAt ?? row?.createdAt ?? "");
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
      return part.text || part.content || "";
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

function eventPrecedes(lhs, rhs) {
  if (lhs.timestampMs !== rhs.timestampMs) {
    return lhs.timestampMs < rhs.timestampMs;
  }
  if (lhs.turnIndex !== rhs.turnIndex) {
    return lhs.turnIndex < rhs.turnIndex;
  }
  return lhs.itemIndex < rhs.itemIndex;
}

function latestMeaningfulMessageFromTurns(turns = []) {
  let latest = null;
  turns.forEach((turn, turnIndex) => {
    const timestampMs = parseTimestampMs(turn?.startedAt)
      ?? parseTimestampMs(turn?.completedAt)
      ?? 0;
    const items = Array.isArray(turn?.items) ? turn.items : [];
    items.forEach((item, itemIndex) => {
      if (!isMessageSummaryCandidate(item)) {
        return;
      }
      const text = textFromItem(item);
      if (!text) {
        return;
      }
      const candidate = {
        text,
        timestampMs,
        turnIndex,
        itemIndex,
      };
      if (!latest || eventPrecedes(latest, candidate)) {
        latest = candidate;
      }
    });
  });
  if (!latest?.text) {
    return null;
  }
  return {
    text: latest.text,
    timestampSeconds: Math.floor(latest.timestampMs / 1000),
  };
}

function latestMeaningfulSummaryFromTurns(turns = []) {
  return latestMeaningfulMessageFromTurns(turns)?.text || null;
}

class ThreadSummaryCache {
  constructor({
    readThreadTurns,
    logger = defaultRelayLogger,
    turnLimit = DEFAULT_SUMMARY_TURN_LIMIT,
    maxEntries = DEFAULT_MAX_ENTRIES,
    maxConcurrent = DEFAULT_MAX_CONCURRENT,
  }) {
    this.readThreadTurns = readThreadTurns;
    this.logger = logger;
    this.turnLimit = turnLimit;
    this.maxEntries = maxEntries;
    this.maxConcurrent = maxConcurrent;
    this.entries = new Map();
    this.queued = [];
    this.queuedIDs = new Set();
    this.active = 0;
    this.idleResolvers = [];
  }

  decorateRows(rows = []) {
    return rows.map((row) => {
      if (nonEmptyText(row?.messageSummary)) {
        return row;
      }
      const entry = this.entryForRow(row, { allowStale: true });
      if (!entry?.summary) {
        return row;
      }
      return {
        ...row,
        latestSummary: nonEmptyText(row?.latestSummary) || entry.summary,
        messageSummary: entry.summary,
        messageUpdatedAt: entry.messageUpdatedAt ?? null,
      };
    });
  }

  warmRows(rows = []) {
    if (!this.readThreadTurns) {
      return;
    }
    for (const row of rows) {
      if (!row?.id || !this.needsWarm(row)) {
        continue;
      }
      if (this.queuedIDs.has(row.id)) {
        continue;
      }
      this.queuedIDs.add(row.id);
      this.queued.push({
        threadId: row.id,
        version: rowVersion(row),
      });
    }
    this.pump();
  }

  async whenIdle() {
    if (this.active === 0 && this.queued.length === 0) {
      return;
    }
    await new Promise((resolve) => {
      this.idleResolvers.push(resolve);
    });
  }

  entryForRow(row, { allowStale = false } = {}) {
    const entry = this.entries.get(row?.id);
    if (!entry) {
      return null;
    }
    if (entry.version !== rowVersion(row) && !allowStale) {
      return null;
    }
    return entry;
  }

  needsWarm(row) {
    const entry = this.entries.get(row.id);
    return !entry || entry.version !== rowVersion(row);
  }

  pump() {
    while (this.active < this.maxConcurrent && this.queued.length > 0) {
      const task = this.queued.shift();
      this.queuedIDs.delete(task.threadId);
      this.active += 1;
      this.warmOne(task)
        .catch((error) => {
          this.logger.warn("thread_summary.warm_failed", {
            threadIDHash: this.hashForLog(task.threadId),
            error,
          });
        })
        .finally(() => {
          this.active -= 1;
          this.resolveIdleIfNeeded();
          this.pump();
        });
    }
    this.resolveIdleIfNeeded();
  }

  async warmOne(task) {
    const turns = await this.readThreadTurns({
      threadId: task.threadId,
      limit: this.turnLimit,
    });
    const message = latestMeaningfulMessageFromTurns(turns?.data || []);
    this.remember(task.threadId, {
      version: task.version,
      summary: message?.text || null,
      messageUpdatedAt: message?.timestampSeconds ?? null,
      checkedAtMs: Date.now(),
    });
  }

  remember(threadId, entry) {
    this.entries.set(threadId, entry);
    while (this.entries.size > this.maxEntries) {
      const firstKey = this.entries.keys().next().value;
      this.entries.delete(firstKey);
    }
  }

  resolveIdleIfNeeded() {
    if (this.active !== 0 || this.queued.length !== 0) {
      return;
    }
    const resolvers = this.idleResolvers;
    this.idleResolvers = [];
    for (const resolve of resolvers) {
      resolve();
    }
  }

  hashForLog(value) {
    return crypto.createHash("sha256").update(String(value || "")).digest("hex").slice(0, 12);
  }
}

export {
  ThreadSummaryCache,
  latestMeaningfulMessageFromTurns,
  latestMeaningfulSummaryFromTurns,
};

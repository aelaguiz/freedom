import { RELAY_THREAD_RETENTION_WINDOW_MS } from "./dock-relay-constants.mjs";
import { rowActivityAtMs } from "./dock-relay-state-views.mjs";

const THREAD_RETENTION_REJECTION_REASON = "older_than_retention_window";

function nonEmpty(value) {
  if (typeof value !== "string") {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function threadIDFromRow(row) {
  if (typeof row === "string") {
    return nonEmpty(row);
  }
  return nonEmpty(row?.id) || nonEmpty(row?.threadId) || nonEmpty(row?.threadID);
}

function threadRetentionWindowMs(config = {}) {
  const override = config?.threadRetentionWindowMs;
  if (override === null || override === undefined || override === "") {
    return RELAY_THREAD_RETENTION_WINDOW_MS;
  }
  const number = Number(override);
  if (number === Number.POSITIVE_INFINITY) {
    return number;
  }
  return Number.isFinite(number) && number >= 0
    ? Math.trunc(number)
    : RELAY_THREAD_RETENTION_WINDOW_MS;
}

function threadRetentionCutoffMs(config = {}, {
  nowMs = Date.now(),
} = {}) {
  const windowMs = threadRetentionWindowMs(config);
  if (windowMs === Number.POSITIVE_INFINITY) {
    return 0;
  }
  const resolvedNowMs = Number(nowMs);
  const safeNowMs = Number.isFinite(resolvedNowMs) && resolvedNowMs > 0
    ? Math.trunc(resolvedNowMs)
    : Date.now();
  return Math.max(0, safeNowMs - windowMs);
}

function cheapThreadActivityMs(row) {
  return rowActivityAtMs(row);
}

function normalizeBypassThreadIDs(threadIDs = []) {
  if (threadIDs instanceof Set) {
    return threadIDs;
  }
  return new Set((threadIDs || []).map((value) => threadIDFromRow(value)).filter(Boolean));
}

function hasFiniteCutoffMs(value) {
  return value !== null
    && value !== undefined
    && value !== ""
    && Number.isFinite(Number(value));
}

function resolveThreadRetentionCutoffMs(config = {}, {
  cutoffMs = null,
  nowMs = Date.now(),
} = {}) {
  return hasFiniteCutoffMs(cutoffMs)
    ? Math.max(0, Math.trunc(Number(cutoffMs)))
    : threadRetentionCutoffMs(config, { nowMs });
}

function threadRetentionDecision(row, {
  bypassThreadIDs = [],
  config = {},
  cutoffMs = null,
  nowMs = Date.now(),
} = {}) {
  const threadId = threadIDFromRow(row);
  const bypassIDs = normalizeBypassThreadIDs(bypassThreadIDs);
  const activityAtMs = cheapThreadActivityMs(row);
  const resolvedCutoffMs = resolveThreadRetentionCutoffMs(config, { cutoffMs, nowMs });

  if (threadId && bypassIDs.has(threadId)) {
    return {
      retained: true,
      reason: "live_bypass",
      threadId,
      activityAtMs,
      cutoffMs: resolvedCutoffMs,
    };
  }

  if (activityAtMs > 0 && activityAtMs >= resolvedCutoffMs) {
    return {
      retained: true,
      reason: "within_retention_window",
      threadId,
      activityAtMs,
      cutoffMs: resolvedCutoffMs,
    };
  }

  return {
    retained: false,
    reason: THREAD_RETENTION_REJECTION_REASON,
    threadId,
    activityAtMs,
    cutoffMs: resolvedCutoffMs,
  };
}

function isThreadRetainedByAge(row, options = {}) {
  return threadRetentionDecision(row, options).retained;
}

function filterThreadsByRetention(rows = [], options = {}) {
  const retainedRows = [];
  const rejectedRows = [];
  const rejectedCounts = {};
  for (const row of rows || []) {
    const decision = threadRetentionDecision(row, options);
    if (decision.retained) {
      retainedRows.push(row);
      continue;
    }
    rejectedRows.push({ row, decision });
    rejectedCounts[decision.reason] = Number(rejectedCounts[decision.reason] || 0) + 1;
  }
  return {
    retainedRows,
    rejectedRows,
    rejectedCounts,
    retentionRejectedRows: rejectedRows.length,
  };
}

function retentionBypassThreadIDsFromLive(liveRows = [], rollupRows = []) {
  const ids = new Set();
  for (const row of liveRows || []) {
    const id = threadIDFromRow(row);
    if (id) {
      ids.add(id);
    }
  }
  for (const row of rollupRows || []) {
    const targetThreadID = nonEmpty(row?.dockRelayRollupTargetThreadID);
    if (targetThreadID) {
      ids.add(targetThreadID);
    }
  }
  return ids;
}

function threadRetentionRejectedError(threadId, decision = {}) {
  const error = new Error("thread rejected by retention filter");
  error.code = -32043;
  error.data = {
    threadId: threadId || decision.threadId || null,
    reason: THREAD_RETENTION_REJECTION_REASON,
    activityAtMs: Number(decision.activityAtMs || 0),
    cutoffMs: Number(decision.cutoffMs || 0),
  };
  return error;
}

export {
  THREAD_RETENTION_REJECTION_REASON,
  cheapThreadActivityMs,
  filterThreadsByRetention,
  isThreadRetainedByAge,
  retentionBypassThreadIDsFromLive,
  resolveThreadRetentionCutoffMs,
  threadIDFromRow,
  threadRetentionCutoffMs,
  threadRetentionDecision,
  threadRetentionRejectedError,
  threadRetentionWindowMs,
};

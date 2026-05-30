import os from "node:os";

import {
  RELAY_STATE_TEXT_FIELD_MAX_CHARS,
  RELAY_STATE_TITLE_MAX_CHARS,
} from "./dock-relay-constants.mjs";

const DOCK_VIEW = "dock";
const ARCHIVE_VIEW = "archive";

function nonEmpty(value) {
  if (typeof value !== "string") {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function boundedText(value, maxChars = RELAY_STATE_TEXT_FIELD_MAX_CHARS) {
  const text = nonEmpty(value);
  if (!text) {
    return null;
  }
  return text.length > maxChars ? text.slice(0, maxChars) : text;
}

function firstBoundedText(values, maxChars = RELAY_STATE_TEXT_FIELD_MAX_CHARS) {
  for (const value of values) {
    const text = boundedText(value, maxChars);
    if (text) {
      return text;
    }
  }
  return null;
}

function optionalNumber(value) {
  if (value === null || value === undefined || value === "") {
    return null;
  }
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function publicHostFromConfig(config) {
  return {
    id: config.hostId || os.hostname(),
    displayName: config.hostName || config.hostId || os.hostname(),
    endpoint: config.hostEndpoint || null,
  };
}

function laneForScope(scope) {
  return scope === "automation" ? "agent" : "human";
}

function normalizedSourceName(value) {
  return String(value || "").trim().toLowerCase().replace(/[^a-z0-9]/g, "");
}

function sourceNameFromThread(thread) {
  const source = thread?.source;
  if (typeof source === "string") {
    return normalizedSourceName(source);
  }
  if (!source || typeof source !== "object" || Array.isArray(source)) {
    return "";
  }
  for (const key of ["type", "kind", "sourceKind", "source_kind", "source"]) {
    if (typeof source[key] === "string") {
      return normalizedSourceName(source[key]);
    }
  }
  for (const key of Object.keys(source)) {
    const normalized = normalizedSourceName(key);
    if (normalized) {
      return normalized;
    }
  }
  return "";
}

function dockLaneForThread(thread, fallbackLane = "agent") {
  switch (sourceNameFromThread(thread)) {
  case "cli":
  case "vscode":
  case "atlas":
  case "chatgpt":
    return "human";
  default:
    return fallbackLane;
  }
}

function sourceKindFromThread(thread, lane) {
  if (lane === "agent") {
    return "automation";
  }
  if (lane === "human") {
    return "human";
  }
  return "unknown";
}

function kindLabelForThread(thread, lane) {
  return nonEmpty(thread?.sourceKind)
    || nonEmpty(thread?.source)
    || (lane === "agent" ? "Agent" : "Human");
}

function normalizedStatus(thread) {
  const status = thread?.status;
  if (status?.type === "active") {
    const flags = new Set(status.activeFlags || []);
    if (flags.has("waitingOnApproval")) {
      return "needsApproval";
    }
    if (flags.has("waitingOnUserInput")) {
      return "needsInput";
    }
    return "running";
  }
  switch (status?.type) {
  case "idle":
    return "idle";
  case "systemError":
    return "error";
  case "notLoaded":
    return "dormant";
  default:
    return "unknown";
  }
}

function titleForThread(thread) {
  return boundedText(thread?.name, RELAY_STATE_TITLE_MAX_CHARS)
    || boundedText(thread?.preview, RELAY_STATE_TITLE_MAX_CHARS)
    || boundedText(thread?.cwd?.split("/").filter(Boolean).at(-1), RELAY_STATE_TITLE_MAX_CHARS)
    || (nonEmpty(thread?.id) ? `Thread ${thread.id.slice(0, 8)}` : "Thread");
}

function repositoryForThread(thread) {
  const originURL = nonEmpty(thread?.gitInfo?.originUrl);
  if (originURL) {
    const pieces = originURL.split(/[/:]/).filter(Boolean);
    const last = pieces.at(-1);
    if (last) {
      return last.endsWith(".git") ? last.slice(0, -4) : last;
    }
  }
  return nonEmpty(thread?.cwd?.split("/").filter(Boolean).at(-1));
}

function rowTimestamp(thread) {
  return optionalNumber(thread?.updatedAt ?? thread?.createdAt) ?? 0;
}

function statusPriority(thread) {
  const status = thread?.status;
  if (status?.type === "active") {
    const flags = new Set(status.activeFlags || []);
    if (flags.has("waitingOnApproval") || flags.has("waitingOnUserInput")) {
      return 0;
    }
    return 1;
  }
  if (status?.type === "idle") {
    return 2;
  }
  if (status?.type === "systemError") {
    return 3;
  }
  if (status?.type === "notLoaded") {
    return 5;
  }
  return 4;
}

function preferThread(candidate, existing) {
  if (!existing) {
    return candidate;
  }
  const candidatePriority = statusPriority(candidate);
  const existingPriority = statusPriority(existing);
  if (candidatePriority !== existingPriority) {
    return candidatePriority < existingPriority ? candidate : existing;
  }
  return rowTimestamp(candidate) >= rowTimestamp(existing) ? candidate : existing;
}

function sanitizeRelayFields(thread) {
  if (!thread || typeof thread !== "object") {
    return thread;
  }
  const { dockRelaySource, ...clean } = thread;
  return clean;
}

function overlayLiveStatus(storedRow, liveRow) {
  if (!liveRow?.status) {
    return storedRow;
  }
  const cleanLiveRow = sanitizeRelayFields(liveRow);
  return {
    ...storedRow,
    sessionId: nonEmpty(cleanLiveRow.sessionId) || storedRow.sessionId,
    status: cleanLiveRow.status,
  };
}

function orderedDockRows(primaryRows, interactiveRows, liveRows = []) {
  const byThreadID = new Map();
  const liveRowsByID = new Map(liveRows.map((row) => [row?.id, row]).filter(([id]) => id));
  const orderedThreadIDs = [];
  const addRow = (row, lane) => {
    if (!row?.id) {
      return;
    }
    const liveRow = liveRowsByID.get(row.id);
    const rowWithLiveStatus = liveRow ? overlayLiveStatus(row, liveRow) : row;
    const existing = byThreadID.get(row.id);
    if (!existing) {
      orderedThreadIDs.push(row.id);
      byThreadID.set(row.id, { lane, row: rowWithLiveStatus });
      return;
    }
    byThreadID.set(row.id, {
      lane: existing.lane,
      row: preferThread(rowWithLiveStatus, existing.row),
    });
  };

  for (const row of primaryRows) {
    addRow(row, dockLaneForThread(row));
  }
  for (const row of interactiveRows) {
    addRow(row, "human");
  }
  return orderedThreadIDs.map((threadID) => byThreadID.get(threadID)).filter(Boolean);
}

function normalizeThread(thread, host, lane = "human") {
  const threadID = nonEmpty(thread?.id);
  if (!threadID) {
    return null;
  }
  const sessionID = nonEmpty(thread?.sessionId) || threadID;
  const updatedAt = rowTimestamp(thread);
  const sourceKind = sourceKindFromThread(thread, lane);
  return {
    id: `${host.id}::${threadID}`,
    hostID: host.id,
    threadID,
    backendSessionID: sessionID,
    title: titleForThread(thread),
    status: normalizedStatus(thread),
    lane,
    kindLabel: boundedText(kindLabelForThread(thread, lane), RELAY_STATE_TITLE_MAX_CHARS),
    repository: boundedText(repositoryForThread(thread), RELAY_STATE_TITLE_MAX_CHARS),
    workingDirectory: firstBoundedText([thread?.cwd, thread?.path]),
    branch: boundedText(thread?.gitInfo?.branch, RELAY_STATE_TITLE_MAX_CHARS),
    updatedAt,
    summary: firstBoundedText([thread?.latestSummary, thread?.preview]) || titleForThread(thread),
    messageSummary: boundedText(thread?.messageSummary),
    messageUpdatedAt: optionalNumber(thread?.messageUpdatedAt),
    source: {
      kind: sourceKind,
    },
  };
}

function normalizeStoredSession(row) {
  if (!row) {
    return null;
  }
  return {
    id: row.dock_id,
    hostID: row.host_id,
    threadID: row.thread_id,
    backendSessionID: row.backend_session_id,
    title: row.title,
    status: row.status,
    lane: row.lane,
    kindLabel: row.kind_label,
    repository: row.repository,
    workingDirectory: row.working_directory,
    branch: row.branch,
    updatedAt: row.updated_at_ms,
    summary: row.summary,
    messageSummary: row.message_summary,
    messageUpdatedAt: row.message_updated_at_ms,
    source: {
      kind: row.source_kind || "unknown",
    },
  };
}

function applyLeaseToSession(session, lease, nowMs = Date.now()) {
  if (!session || !lease) {
    return session;
  }
  if (lease.expires_at_ms && Number(lease.expires_at_ms) < nowMs) {
    return session.status === "dormant"
      ? { ...session, status: "unknown" }
      : session;
  }
  const status = lease.status || "unknown";
  return {
    ...session,
    backendSessionID: lease.backend_session_id || session.backendSessionID,
    status: status === "waiting" ? "needsInput" : status,
  };
}

function buildWindow({ offset = 0, limit, rowCount, totalRows }) {
  const safeOffset = Math.max(0, Number(offset || 0));
  const safeLimit = Math.max(0, Number(limit || rowCount || 0));
  const end = safeOffset + rowCount;
  return {
    offset: safeOffset,
    limit: safeLimit,
    rowCount,
    nextOffset: end < totalRows ? end : null,
  };
}

function estimateJSONBytes(value) {
  try {
    return Buffer.byteLength(JSON.stringify(value), "utf8");
  } catch {
    return Number.POSITIVE_INFINITY;
  }
}

export {
  ARCHIVE_VIEW,
  DOCK_VIEW,
  applyLeaseToSession,
  buildWindow,
  estimateJSONBytes,
  normalizedStatus,
  normalizeStoredSession,
  normalizeThread,
  orderedDockRows,
  publicHostFromConfig,
};

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

function timestampNumberToMs(number) {
  if (!Number.isFinite(number) || number <= 0) {
    return 0;
  }
  return number > 10_000_000_000 ? Math.trunc(number) : Math.trunc(number * 1000);
}

function publicHostFromConfig(config) {
  const logicalHostID = config.hostId || os.hostname();
  return {
    id: logicalHostID,
    logicalHostID,
    displayName: config.hostName || config.hostId || os.hostname(),
    endpoint: config.hostEndpoint || null,
  };
}

function dockCardID(logicalHostID, threadID) {
  const hostID = nonEmpty(logicalHostID);
  const id = nonEmpty(threadID);
  return hostID && id ? `${hostID}::${id}` : null;
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

function timestampToMs(value) {
  if (typeof value === "string") {
    const trimmed = value.trim();
    if (!trimmed) {
      return 0;
    }
    const number = optionalNumber(trimmed);
    if (number !== null) {
      return timestampNumberToMs(number);
    }
    const parsed = Date.parse(trimmed);
    return Number.isFinite(parsed) ? Math.max(0, Math.trunc(parsed)) : 0;
  }
  const number = optionalNumber(value);
  return number === null ? 0 : timestampNumberToMs(number);
}

function timestampToISO(value) {
  const ms = timestampToMs(value);
  if (!Number.isFinite(ms) || ms <= 0) {
    return new Date(0).toISOString();
  }
  return new Date(ms).toISOString();
}

function activityOrderKey(activityAtMs, threadID) {
  const inverted = Number.MAX_SAFE_INTEGER - Math.max(0, Number(activityAtMs || 0));
  return `${String(Math.max(0, inverted)).padStart(16, "0")}:${threadID}`;
}

function archiveOrderKey(activityAtMs, threadID) {
  return activityOrderKey(activityAtMs, threadID);
}

function displaySummaryForThread(thread) {
  return firstBoundedText([
    thread?.displaySummary,
    thread?.latestSummary,
    thread?.summary,
    thread?.preview,
  ]) || titleForThread(thread);
}

function summarySourceForThread(thread) {
  if (boundedText(thread?.summarySource)) {
    return boundedText(thread.summarySource, RELAY_STATE_TITLE_MAX_CHARS);
  }
  if (boundedText(thread?.displaySummary)) {
    return "assistant_label";
  }
  if (boundedText(thread?.latestSummary)) {
    return "latest_summary";
  }
  if (boundedText(thread?.summary)) {
    return "summary";
  }
  if (boundedText(thread?.preview)) {
    return "preview";
  }
  return "title";
}

function forkParentIDForThread(thread) {
  return nonEmpty(thread?.forkedFromId) || nonEmpty(thread?.forked_from_id);
}

function relationshipForThread(thread) {
  return forkParentIDForThread(thread) ? "forked" : "root";
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
  for (const row of liveRows) {
    addRow(row, "human");
  }
  return orderedThreadIDs.map((threadID) => byThreadID.get(threadID)).filter(Boolean);
}

function normalizeThread(thread, host, lane = "human", options = {}) {
  const threadID = nonEmpty(thread?.id);
  if (!threadID) {
    return null;
  }
  const sessionID = nonEmpty(thread?.sessionId) || threadID;
  const activityAtMs = timestampToMs(thread?.activityAtMs ?? thread?.activityAt ?? rowTimestamp(thread));
  const sourceKind = sourceKindFromThread(thread, lane);
  const forkedFromID = forkParentIDForThread(thread);
  const orderKey = options.orderKey || activityOrderKey(activityAtMs, threadID);
  // Canonical card facts must already be folded before this point; this
  // function formats relay-owned facts and never rebuilds order from list index.
  return {
    id: dockCardID(host.logicalHostID || host.id, threadID),
    logicalHostID: host.logicalHostID || host.id,
    threadID,
    backendSessionID: sessionID,
    hostDisplayName: host.displayName || host.id,
    hostEndpoint: host.endpoint || null,
    orderKey,
    activityAt: timestampToISO(activityAtMs),
    activityAtMs,
    displaySummary: displaySummaryForThread(thread),
    title: titleForThread(thread),
    status: normalizedStatus(thread),
    sourceKind,
    lane,
    relationship: options.relationship || relationshipForThread(thread),
    forkedFromID,
    archiveState: options.archiveState || "active",
    freshness: options.freshness || thread?.freshness || "fresh",
    completeness: options.completeness || thread?.completeness || "complete",
    repository: boundedText(repositoryForThread(thread), RELAY_STATE_TITLE_MAX_CHARS),
    workingDirectory: firstBoundedText([thread?.cwd, thread?.path]),
    branch: boundedText(thread?.gitInfo?.branch, RELAY_STATE_TITLE_MAX_CHARS),
    summarySource: summarySourceForThread(thread),
  };
}

function normalizeStoredCard(row) {
  if (!row) {
    return null;
  }
  const activityAtMs = Number(row.activity_at_ms || row.updated_at_ms || 0);
  return {
    id: row.dock_id || dockCardID(row.logical_host_id || row.host_id, row.thread_id),
    logicalHostID: row.logical_host_id || row.host_id,
    threadID: row.thread_id,
    backendSessionID: row.backend_session_id,
    hostDisplayName: row.host_display_name || row.host_id,
    hostEndpoint: row.host_endpoint || null,
    orderKey: row.order_key || activityOrderKey(activityAtMs, row.thread_id),
    activityAt: row.activity_at || timestampToISO(activityAtMs),
    activityAtMs,
    displaySummary: row.display_summary || row.summary || row.title || "No summary",
    title: row.title,
    status: row.status,
    sourceKind: row.source_kind || "unknown",
    lane: row.lane,
    relationship: row.relationship || "root",
    forkedFromID: row.forked_from_id || null,
    archiveState: row.archive_state || "unknown",
    freshness: row.freshness_status || "unknown",
    completeness: row.completeness || "unknown",
    repository: row.repository,
    workingDirectory: row.working_directory,
    branch: row.branch,
    summarySource: row.summary_source || null,
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
  activityOrderKey,
  archiveOrderKey,
  buildWindow,
  dockCardID,
  estimateJSONBytes,
  normalizedStatus,
  normalizeStoredCard,
  normalizeThread,
  orderedDockRows,
  publicHostFromConfig,
  timestampToISO,
  timestampToMs,
};

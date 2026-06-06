import os from "node:os";

import {
  RELAY_STATE_TEXT_FIELD_MAX_CHARS,
  RELAY_STATE_TITLE_MAX_CHARS,
} from "./dock-relay-constants.mjs";
import {
  PROJECTION_ENGINE_VERSION,
  PROJECTION_IDENTITY_VERSION,
  PROJECTION_SCHEMA_VERSION,
  projectionIDForThreadCard,
  sourceRefForThreadCard,
  threadCardDisplayOrderKey,
} from "./dock-relay-projection-engine.mjs";

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

const ACTIVE_PUBLIC_STATUS_PRIORITY = new Map([
  ["needsApproval", 0],
  ["needsInput", 1],
  ["running", 2],
]);

function activePublicStatus(value) {
  const status = typeof value === "string" ? value : normalizedStatus(value);
  return ACTIVE_PUBLIC_STATUS_PRIORITY.has(status) ? status : null;
}

function activePublicStatusPriority(status) {
  return ACTIVE_PUBLIC_STATUS_PRIORITY.get(status) ?? Number.POSITIVE_INFINITY;
}

function publicStatusToThreadStatus(status) {
  switch (status) {
  case "needsApproval":
    return { type: "active", activeFlags: ["waitingOnApproval"] };
  case "needsInput":
    return { type: "active", activeFlags: ["waitingOnUserInput"] };
  case "running":
    return { type: "active", activeFlags: [] };
  default:
    return null;
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

function rowActivityAtMs(thread) {
  return timestampToMs(
    thread?.activityAtMs
      ?? thread?.activityAt
      ?? thread?.updatedAtMs
      ?? thread?.updatedAt
      ?? thread?.createdAtMs
      ?? thread?.createdAt
      ?? rowTimestamp(thread)
  );
}

function relayRowCarriesActivitySignal(row) {
  return row?.dockRelayActivitySource !== "private-owner-presence"
    && row?.dockRelayRollupSource !== "private-owner-presence"
    && row?.activityProofStatus !== "status_only";
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

function preferHiddenActivityRollup(candidate, existing) {
  if (!candidate) {
    return existing || null;
  }
  if (!existing) {
    return candidate;
  }
  const candidateStatus = activePublicStatus(candidate);
  const existingStatus = activePublicStatus(existing);
  const candidatePriority = activePublicStatusPriority(candidateStatus);
  const existingPriority = activePublicStatusPriority(existingStatus);
  if (candidatePriority !== existingPriority) {
    return candidatePriority < existingPriority ? candidate : existing;
  }
  return rowActivityAtMs(candidate) >= rowActivityAtMs(existing) ? candidate : existing;
}

function hiddenActivityRollupsByTargetThreadID(rollupRows = []) {
  const byTargetThreadID = new Map();
  for (const row of rollupRows || []) {
    const targetThreadID = nonEmpty(row?.dockRelayRollupTargetThreadID);
    if (!targetThreadID || !activePublicStatus(row)) {
      continue;
    }
    byTargetThreadID.set(
      targetThreadID,
      preferHiddenActivityRollup(row, byTargetThreadID.get(targetThreadID)),
    );
  }
  return byTargetThreadID;
}

function strongerPublicStatus(currentStatus, rollupStatus) {
  if (!rollupStatus) {
    return currentStatus;
  }
  const currentActive = activePublicStatus(currentStatus);
  if (!currentActive) {
    return rollupStatus;
  }
  return activePublicStatusPriority(rollupStatus) < activePublicStatusPriority(currentActive)
    ? rollupStatus
    : currentActive;
}

function overlayHiddenActivityRollup(storedRow, rollupRow) {
  const rollupStatus = activePublicStatus(rollupRow);
  if (!rollupStatus) {
    return storedRow;
  }
  const publicStatus = strongerPublicStatus(normalizedStatus(storedRow), rollupStatus);
  const status = publicStatusToThreadStatus(publicStatus) || storedRow.status;
  const activityAtMs = relayRowCarriesActivitySignal(rollupRow)
    ? Math.max(rowActivityAtMs(storedRow), rowActivityAtMs(rollupRow))
    : rowActivityAtMs(storedRow);
  return {
    ...storedRow,
    activityAt: timestampToISO(activityAtMs),
    activityAtMs,
    status,
  };
}

function overlayHiddenActivityRollupOnCard(card, rollupRow) {
  const rollupStatus = activePublicStatus(rollupRow);
  if (!rollupStatus) {
    return card;
  }
  const publicStatus = strongerPublicStatus(card?.status, rollupStatus);
  const activityAtMs = relayRowCarriesActivitySignal(rollupRow)
    ? Math.max(Number(card?.activityAtMs || 0), rowActivityAtMs(rollupRow))
    : Number(card?.activityAtMs || 0);
  return {
    ...card,
    activityAt: timestampToISO(activityAtMs),
    activityAtMs,
    status: publicStatus,
    displayOrderKey: threadCardDisplayOrderKey({
      activityAtMs,
      status: publicStatus,
      projectionID: card.projectionID,
    }),
  };
}

function applyHiddenActivityRollupsToCards(cards = [], rollupRows = []) {
  if (!Array.isArray(cards) || cards.length === 0 || !Array.isArray(rollupRows) || rollupRows.length === 0) {
    return cards;
  }
  const rollupsByTargetThreadID = hiddenActivityRollupsByTargetThreadID(rollupRows);
  if (rollupsByTargetThreadID.size === 0) {
    return cards;
  }
  return cards
    .map((card) => overlayHiddenActivityRollupOnCard(card, rollupsByTargetThreadID.get(card.threadID)))
    .sort((left, right) => String(left.displayOrderKey).localeCompare(String(right.displayOrderKey)));
}

function orderedDockRows(primaryRows, interactiveRows, liveRows = [], rollupRows = []) {
  const byThreadID = new Map();
  const liveRowsByID = new Map(liveRows.map((row) => [row?.id, row]).filter(([id]) => id));
  const rollupsByTargetThreadID = hiddenActivityRollupsByTargetThreadID(rollupRows);
  const orderedThreadIDs = [];
  const addRow = (row, lane) => {
    if (!row?.id) {
      return;
    }
    const liveRow = liveRowsByID.get(row.id);
    const rowWithLiveStatus = liveRow ? overlayLiveStatus(row, liveRow) : row;
    const rollupRow = rollupsByTargetThreadID.get(row.id);
    const rowWithRollupStatus = rollupRow
      ? overlayHiddenActivityRollup(rowWithLiveStatus, rollupRow)
      : rowWithLiveStatus;
    const existing = byThreadID.get(row.id);
    if (!existing) {
      orderedThreadIDs.push(row.id);
      byThreadID.set(row.id, { lane, row: rowWithRollupStatus });
      return;
    }
    byThreadID.set(row.id, {
      lane: existing.lane,
      row: preferThread(rowWithRollupStatus, existing.row),
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
  const sourceHostID = host.id;
  const status = normalizedStatus(thread);
  const projectionID = projectionIDForThreadCard({ sourceHostID, threadID });
  const sourceRef = sourceRefForThreadCard({ sourceHostID, threadID });
  const displayOrderKey = threadCardDisplayOrderKey({ activityAtMs, status, projectionID });
  // Canonical card facts must already be folded before this point; this
  // function formats relay-owned facts and never rebuilds order from list index.
  return {
    id: projectionID,
    schemaVersion: PROJECTION_SCHEMA_VERSION,
    identityVersion: PROJECTION_IDENTITY_VERSION,
    projectionEngineVersion: PROJECTION_ENGINE_VERSION,
    sourceHostID,
    view: options.archiveState === "archived" ? ARCHIVE_VIEW : DOCK_VIEW,
    projectionID,
    sourceRef,
    rowRole: "threadCard",
    displayOrderKey,
    logicalHostID: sourceHostID,
    threadID,
    backendSessionID: sessionID,
    hostDisplayName: host.displayName || host.id,
    hostEndpoint: host.endpoint || null,
    activityAt: timestampToISO(activityAtMs),
    activityAtMs,
    displaySummary: displaySummaryForThread(thread),
    title: titleForThread(thread),
    status,
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
  if (typeof row.raw_json !== "string" || !row.raw_json.trim()) {
    return null;
  }
  let rawCard;
  try {
    rawCard = JSON.parse(row.raw_json);
  } catch {
    return null;
  }
  if (!storedCardHasProjectionEnvelope(rawCard, row)) {
    return null;
  }
  return {
    ...rawCard,
    id: rawCard.projectionID,
    archiveState: row.archive_state || "unknown",
    freshness: row.freshness_status || "unknown",
    completeness: row.completeness || "unknown",
  };
}

function storedCardHasProjectionEnvelope(rawCard, row) {
  return rawCard
    && rawCard.schemaVersion === PROJECTION_SCHEMA_VERSION
    && rawCard.identityVersion === PROJECTION_IDENTITY_VERSION
    && rawCard.projectionEngineVersion === PROJECTION_ENGINE_VERSION
    && rawCard.sourceHostID === row.host_id
    && rawCard.logicalHostID === rawCard.sourceHostID
    && rawCard.threadID === row.thread_id
    && rawCard.id === rawCard.projectionID
    && rawCard.rowRole === "threadCard"
    && typeof rawCard.view === "string"
    && typeof rawCard.projectionID === "string"
    && rawCard.projectionID.trim()
    && typeof rawCard.sourceRef === "string"
    && rawCard.sourceRef.trim()
    && typeof rawCard.displayOrderKey === "string"
    && rawCard.displayOrderKey.trim();
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
  applyHiddenActivityRollupsToCards,
  buildWindow,
  dockCardID,
  estimateJSONBytes,
  normalizedStatus,
  normalizeStoredCard,
  normalizeThread,
  orderedDockRows,
  publicHostFromConfig,
  relayRowCarriesActivitySignal,
  rowActivityAtMs,
  timestampToISO,
  timestampToMs,
};

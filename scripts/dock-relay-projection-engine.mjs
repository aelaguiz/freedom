import crypto from "node:crypto";

const PROJECTION_SCHEMA_VERSION = 1;
const PROJECTION_IDENTITY_VERSION = 1;
const PROJECTION_ENGINE_VERSION = 1;

const THREAD_DETAIL_VIEW = "thread.detail";
const THREAD_DETAIL_ORDER = "displayOrderKeyAscending";
const THREAD_DETAIL_DEFAULT_VIEW_PARAMS = Object.freeze({
  visibility: "all",
  rowRoles: null,
  search: "",
  includeDiagnostics: true,
  sort: THREAD_DETAIL_ORDER,
});
const THREAD_DETAIL_DEFAULT_VIEW_PARAMS_KEY = `sha256:${crypto
  .createHash("sha256")
  .update(stableStringify(THREAD_DETAIL_DEFAULT_VIEW_PARAMS))
  .digest("hex")}`;

const MAX_SORT_MS = 9_999_999_999_999_999;
const MAX_ORDER = 9_999_999_999;

function stableStringify(value) {
  if (Array.isArray(value)) {
    return `[${value.map(stableStringify).join(",")}]`;
  }
  if (value && typeof value === "object") {
    return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${stableStringify(value[key])}`).join(",")}}`;
  }
  return JSON.stringify(value);
}

function shortHash(value, length = 12) {
  return crypto.createHash("sha256").update(String(value ?? "")).digest("hex").slice(0, length);
}

function safeSegment(value) {
  const bytes = Buffer.from(String(value ?? "missing"), "utf8");
  let output = "";
  for (const byte of bytes) {
    const isAlphaNumeric =
      (byte >= 0x30 && byte <= 0x39)
      || (byte >= 0x41 && byte <= 0x5a)
      || (byte >= 0x61 && byte <= 0x7a);
    if (isAlphaNumeric || byte === 0x2d || byte === 0x2e || byte === 0x5f) {
      output += String.fromCharCode(byte);
    } else {
      output += `%${byte.toString(16).toUpperCase().padStart(2, "0")}`;
    }
  }
  return output;
}

function segment(label, value) {
  return `${label}:${safeSegment(value)}`;
}

function hostSegment(sourceHostID) {
  return segment("host", sourceHostID);
}

function threadSegment(threadID) {
  return segment("thread", threadID);
}

function padOrder(value) {
  const number = Math.max(0, Math.min(MAX_ORDER, Math.trunc(Number(value) || 0)));
  return String(number).padStart(10, "0");
}

function invertedOrder(value) {
  if (value === null || value === undefined) {
    return MAX_ORDER;
  }
  return MAX_ORDER - Math.max(0, Math.min(MAX_ORDER, Math.trunc(Number(value) || 0)));
}

function threadDetailDisplayOrderKey({
  activityAtMs,
  turnOrder,
  itemOrder,
  rowOrder,
  projectionID,
}) {
  const ms = Math.max(0, Math.min(MAX_SORT_MS, Math.trunc(Number(activityAtMs) || 0)));
  return [
    String(MAX_SORT_MS - ms).padStart(16, "0"),
    padOrder(turnOrder ?? MAX_ORDER),
    padOrder(invertedOrder(itemOrder)),
    padOrder(invertedOrder(rowOrder)),
    safeSegment(projectionID),
  ].join("|");
}

function sourceRefForThreadItem({ sourceHostID, threadID, turnID, itemID }) {
  return [
    hostSegment(sourceHostID),
    threadSegment(threadID),
    segment("turn", turnID),
    segment("item", itemID),
  ].join("/");
}

function projectionIDForThreadItem({ sourceHostID, threadID, turnID, itemID, rowRole }) {
  return `${sourceRefForThreadItem({ sourceHostID, threadID, turnID, itemID })}/${segment("row", rowRole)}`;
}

function sourceRefForThreadRequest({ sourceHostID, threadID, turnID = null, itemID = null, requestID }) {
  const base = [hostSegment(sourceHostID), threadSegment(threadID)];
  if (turnID && itemID) {
    base.push(segment("turn", turnID), segment("item", itemID));
  }
  base.push(segment("request", requestID));
  return base.join("/");
}

function projectionIDForThreadRequest({ sourceHostID, threadID, turnID = null, itemID = null, requestID }) {
  return `${sourceRefForThreadRequest({ sourceHostID, threadID, turnID, itemID, requestID })}/${segment("row", "request")}`;
}

function sourceRefForThreadSystem({ sourceHostID, threadID, systemKind }) {
  return [
    hostSegment(sourceHostID),
    threadSegment(threadID),
    segment("system", systemKind),
  ].join("/");
}

function projectionIDForThreadSystem({ sourceHostID, threadID, systemKind }) {
  return `${sourceRefForThreadSystem({ sourceHostID, threadID, systemKind })}/${segment("row", "system")}`;
}

function sourceRefForThreadDiagnostic({ sourceHostID, threadID, diagnosticID }) {
  return [
    hostSegment(sourceHostID),
    threadSegment(threadID),
    segment("diagnostic", diagnosticID),
  ].join("/");
}

function projectionIDForThreadDiagnostic({ sourceHostID, threadID, diagnosticID }) {
  return `${sourceRefForThreadDiagnostic({ sourceHostID, threadID, diagnosticID })}/${segment("row", "unknown")}`;
}

function sourceRefForThreadCard({ sourceHostID, threadID }) {
  return [
    hostSegment(sourceHostID),
    threadSegment(threadID),
  ].join("/");
}

function projectionIDForThreadCard({ sourceHostID, threadID }) {
  return `${sourceRefForThreadCard({ sourceHostID, threadID })}/${segment("row", "threadCard")}`;
}

function cardStatusPriority(status) {
  switch (status) {
    case "needsInput":
    case "needsApproval":
      return 0;
    case "running":
      return 1;
    case "idle":
      return 2;
    case "error":
      return 3;
    case "unknown":
      return 4;
    case "dormant":
      return 5;
    default:
      return 4;
  }
}

function threadCardDisplayOrderKey({
  activityAtMs,
  status,
  projectionID,
}) {
  const ms = Math.max(0, Math.min(MAX_SORT_MS, Math.trunc(Number(activityAtMs) || 0)));
  return [
    String(MAX_SORT_MS - ms).padStart(16, "0"),
    String(cardStatusPriority(status)).padStart(4, "0"),
    safeSegment(projectionID),
  ].join("|");
}

export {
  PROJECTION_ENGINE_VERSION,
  PROJECTION_IDENTITY_VERSION,
  PROJECTION_SCHEMA_VERSION,
  THREAD_DETAIL_DEFAULT_VIEW_PARAMS,
  THREAD_DETAIL_DEFAULT_VIEW_PARAMS_KEY,
  THREAD_DETAIL_ORDER,
  THREAD_DETAIL_VIEW,
  cardStatusPriority,
  hostSegment,
  projectionIDForThreadCard,
  projectionIDForThreadDiagnostic,
  projectionIDForThreadItem,
  projectionIDForThreadRequest,
  projectionIDForThreadSystem,
  safeSegment,
  segment,
  shortHash,
  sourceRefForThreadCard,
  sourceRefForThreadDiagnostic,
  sourceRefForThreadItem,
  sourceRefForThreadRequest,
  sourceRefForThreadSystem,
  stableStringify,
  threadCardDisplayOrderKey,
  threadDetailDisplayOrderKey,
  threadSegment,
};

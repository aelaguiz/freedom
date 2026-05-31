import {
  canonicalSourceName,
  normalizedThreadSource,
  signalsFromSourceValue,
} from "./dock-relay-source-filter.mjs";

const HUMAN_CUSTOM_SOURCES = new Set(["atlas", "chatgpt"]);

function nonEmpty(value) {
  if (typeof value !== "string") {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function firstObjectValue(object, keys) {
  if (!object || typeof object !== "object") {
    return null;
  }
  for (const key of keys) {
    if (Object.hasOwn(object, key)) {
      return object[key];
    }
  }
  return null;
}

function parseMaybeJSONValue(value) {
  if (typeof value !== "string") {
    return value;
  }
  const trimmed = value.trim();
  if (!trimmed) {
    return value;
  }
  if (!trimmed.startsWith("{") && !trimmed.startsWith("[")) {
    return value;
  }
  try {
    return JSON.parse(trimmed);
  } catch {
    return value;
  }
}

function threadSpawnPayloadFromSource(source) {
  const parsed = parseMaybeJSONValue(source);
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    return null;
  }
  const subAgent = firstObjectValue(parsed, ["subagent", "subAgent"]);
  if (subAgent && typeof subAgent === "object" && !Array.isArray(subAgent)) {
    return firstObjectValue(subAgent, ["thread_spawn", "threadSpawn"]);
  }
  return firstObjectValue(parsed, ["thread_spawn", "threadSpawn"]);
}

function threadSpawnParentIDFromSource(source) {
  const payload = threadSpawnPayloadFromSource(source);
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
    return null;
  }
  const parentID = firstObjectValue(payload, ["parent_thread_id", "parentThreadId"]);
  return nonEmpty(parentID);
}

function forkParentIDFromRow(row) {
  return nonEmpty(row?.forkedFromId) || nonEmpty(row?.forked_from_id);
}

function threadRelationship(row) {
  const spawnParentID = threadSpawnParentIDFromSource(row?.source);
  if (spawnParentID) {
    return {
      relationship: "spawned",
      parentThreadID: spawnParentID,
      forkedFromID: forkParentIDFromRow(row),
    };
  }
  const forkedFromID = forkParentIDFromRow(row);
  if (forkedFromID) {
    return {
      relationship: "forked",
      parentThreadID: null,
      forkedFromID,
    };
  }
  return {
    relationship: "root",
    parentThreadID: null,
    forkedFromID: null,
  };
}

function sourceIsMissing(row) {
  return row?.source === undefined || row?.source === null || row?.source === "";
}

function hasRawSourceName(value, target) {
  const parsed = parseMaybeJSONValue(value);
  if (typeof parsed === "string") {
    return canonicalSourceName(parsed) === target;
  }
  if (Array.isArray(parsed)) {
    return parsed.some((entry) => hasRawSourceName(entry, target));
  }
  if (!parsed || typeof parsed !== "object") {
    return false;
  }
  for (const key of ["type", "kind", "sourceKind", "source_kind", "subtype", "custom"]) {
    if (typeof parsed[key] === "string" && canonicalSourceName(parsed[key]) === target) {
      return true;
    }
  }
  if (parsed.source !== undefined && hasRawSourceName(parsed.source, target)) {
    return true;
  }
  return Object.keys(parsed).some((key) => canonicalSourceName(key) === target);
}

function sourceHasContradictorySignals(row) {
  const signals = signalsFromSourceValue(row?.source);
  if (signals.length <= 1) {
    return false;
  }
  if (signals.some((signal) => signal.family === "unknown")) {
    return false;
  }
  const families = new Set(signals.map((signal) => signal.family));
  if (families.size > 1) {
    return true;
  }
  const kinds = new Set(signals.map((signal) => (
    signal.kind === "custom"
      ? `custom:${signal.name}`
      : signal.kind === "subAgent"
        ? `subAgent:${signal.variant}`
        : signal.kind
  )));
  return kinds.size > 1;
}

function rejected(reason, sourceKind = "unknown", row = null) {
  const relationship = threadRelationship(row);
  return {
    allowed: false,
    category: "rejected",
    reason,
    sourceKind,
    relationship: relationship.relationship,
    parentThreadID: relationship.parentThreadID,
    forkedFromID: relationship.forkedFromID,
  };
}

function accepted(reason, row) {
  const relationship = threadRelationship(row);
  return {
    allowed: true,
    category: "human_started",
    reason,
    sourceKind: "human",
    relationship: relationship.relationship,
    parentThreadID: relationship.parentThreadID,
    forkedFromID: relationship.forkedFromID,
  };
}

function classifyThreadOrigin(row) {
  if (threadSpawnParentIDFromSource(row?.source)) {
    return rejected("not_base_level", "automation", row);
  }

  const threadSource = canonicalSourceName(row?.threadSource ?? row?.thread_source);
  if (threadSource === "subagent") {
    return rejected("sub_agent", "automation", row);
  }
  if (threadSource === "memoryconsolidation") {
    return rejected("memory_internal", "internal", row);
  }
  if (sourceIsMissing(row)) {
    return rejected("missing_source", "unknown", row);
  }

  const source = normalizedThreadSource(row);
  switch (source.kind) {
  case "cli":
    return accepted("human_cli", row);
  case "vscode":
    return accepted("human_vscode", row);
  case "custom":
    if (HUMAN_CUSTOM_SOURCES.has(source.name)) {
      return accepted(`human_custom_${source.name}`, row);
    }
    return rejected("unknown", "unknown", row);
  case "exec":
    return rejected("exec", "automation", row);
  case "appServer":
    return rejected(hasRawSourceName(row?.source, "mcp") ? "mcp" : "app_server", "automation", row);
  case "subAgent":
    return rejected(
      source.variant === "threadSpawn" ? "sub_agent_thread_spawn" : "sub_agent",
      "automation",
      row,
    );
  case "internal":
    return rejected("memory_internal", "internal", row);
  case "unknown":
  default:
    return rejected(sourceHasContradictorySignals(row) ? "contradictory_source" : "unknown", "unknown", row);
  }
}

function isHumanStartedThread(row) {
  return classifyThreadOrigin(row).allowed;
}

function filterHumanStartedThreads(rows = []) {
  const acceptedRows = [];
  const rejectedCounts = {};
  for (const row of rows) {
    const classification = classifyThreadOrigin(row);
    if (classification.allowed) {
      acceptedRows.push(row);
      continue;
    }
    rejectedCounts[classification.reason] = Number(rejectedCounts[classification.reason] || 0) + 1;
  }
  return { acceptedRows, rejectedCounts };
}

function humanThreadRejectedError(threadId, reason) {
  const error = new Error("thread rejected by human-only filter");
  error.code = -32043;
  error.data = {
    threadId: threadId || null,
    reason: reason || "unknown",
  };
  return error;
}

function assertHumanStartedThread(row) {
  const classification = classifyThreadOrigin(row);
  if (!classification.allowed) {
    throw humanThreadRejectedError(row?.id || row?.threadId || row?.threadID, classification.reason);
  }
  return row;
}

function isHumanAppFacingCard(card) {
  return card?.lane === "human" && card?.sourceKind === "human";
}

export {
  assertHumanStartedThread,
  classifyThreadOrigin,
  filterHumanStartedThreads,
  forkParentIDFromRow,
  humanThreadRejectedError,
  isHumanAppFacingCard,
  isHumanStartedThread,
  threadRelationship,
  threadSpawnParentIDFromSource,
};

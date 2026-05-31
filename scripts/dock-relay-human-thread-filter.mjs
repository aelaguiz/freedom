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

function hasForkParent(row) {
  return Boolean(nonEmpty(row?.forkedFromId) || nonEmpty(row?.forked_from_id));
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

function rejected(reason, sourceKind = "unknown") {
  return {
    allowed: false,
    category: "rejected",
    reason,
    sourceKind,
  };
}

function accepted(reason) {
  return {
    allowed: true,
    category: "human_base",
    reason,
    sourceKind: "human",
  };
}

function classifyThreadOrigin(row) {
  if (hasForkParent(row)) {
    return rejected("forked");
  }
  if (threadSpawnParentIDFromSource(row?.source)) {
    return rejected("not_base_level", "automation");
  }

  const threadSource = canonicalSourceName(row?.threadSource ?? row?.thread_source);
  if (threadSource === "subagent") {
    return rejected("sub_agent", "automation");
  }
  if (threadSource === "memoryconsolidation") {
    return rejected("memory_internal", "internal");
  }
  if (sourceIsMissing(row)) {
    return rejected("missing_source");
  }

  const source = normalizedThreadSource(row);
  switch (source.kind) {
  case "cli":
    return accepted("human_cli");
  case "vscode":
    return accepted("human_vscode");
  case "custom":
    if (HUMAN_CUSTOM_SOURCES.has(source.name)) {
      return accepted(`human_custom_${source.name}`);
    }
    return rejected("unknown");
  case "exec":
    return rejected("exec", "automation");
  case "appServer":
    return rejected(hasRawSourceName(row?.source, "mcp") ? "mcp" : "app_server", "automation");
  case "subAgent":
    return rejected(
      source.variant === "threadSpawn" ? "sub_agent_thread_spawn" : "sub_agent",
      "automation",
    );
  case "internal":
    return rejected("memory_internal", "internal");
  case "unknown":
  default:
    return rejected(sourceHasContradictorySignals(row) ? "contradictory_source" : "unknown");
  }
}

function isHumanBaseThread(row) {
  return classifyThreadOrigin(row).allowed;
}

function filterHumanBaseThreads(rows = []) {
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

function assertHumanBaseThread(row) {
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
  assertHumanBaseThread,
  classifyThreadOrigin,
  filterHumanBaseThreads,
  humanThreadRejectedError,
  isHumanAppFacingCard,
  isHumanBaseThread,
  threadSpawnParentIDFromSource,
};

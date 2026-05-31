const DEFAULT_INTERACTIVE_CUSTOM_SOURCES = new Set(["atlas", "chatgpt"]);

function normalizeString(value) {
  return String(value || "").trim();
}

function normalizeSourceName(value) {
  return normalizeString(value).toLowerCase();
}

function canonicalSourceName(value) {
  return normalizeSourceName(value).replace(/[^a-z0-9]/g, "");
}

function normalizedSubAgentVariant(value) {
  if (typeof value === "string") {
    switch (canonicalSourceName(value)) {
      case "review":
      case "subagentreview":
        return "review";
      case "compact":
      case "subagentcompact":
        return "compact";
      case "threadspawn":
      case "subagentthreadspawn":
      case "spawn":
        return "threadSpawn";
      case "other":
      case "subagentother":
        return "other";
      case "memoryconsolidation":
        return "memoryConsolidation";
      default:
        return "unknown";
    }
  }
  if (value && typeof value === "object") {
    if (Object.hasOwn(value, "thread_spawn") || Object.hasOwn(value, "threadSpawn")) {
      return "threadSpawn";
    }
    if (Object.hasOwn(value, "other")) {
      return "other";
    }
  }
  return "unknown";
}

function signalFromString(value) {
  const normalized = canonicalSourceName(value);
  switch (normalized) {
    case "cli":
      return { family: "human", kind: "cli" };
    case "vscode":
      return { family: "human", kind: "vscode" };
    case "exec":
      return { family: "automation", kind: "exec" };
    case "appserver":
    case "mcp":
      return { family: "automation", kind: "appServer" };
    case "atlas":
    case "chatgpt":
      return { family: "human", kind: "custom", name: normalizeSourceName(value) };
    case "subagent":
      return { family: "automation", kind: "subAgent", variant: "unknown" };
    case "subagentreview":
      return { family: "automation", kind: "subAgent", variant: "review" };
    case "subagentcompact":
      return { family: "automation", kind: "subAgent", variant: "compact" };
    case "subagentthreadspawn":
      return { family: "automation", kind: "subAgent", variant: "threadSpawn" };
    case "subagentother":
      return { family: "automation", kind: "subAgent", variant: "other" };
    case "internal":
    case "memoryconsolidation":
      return { family: "internal", kind: "internal" };
    case "unknown":
      return { family: "unknown", kind: "unknown" };
    default:
      return { family: "unknown", kind: "unknown" };
  }
}

function signalFromSubAgent(value) {
  if (Array.isArray(value)) {
    return value.flatMap(signalFromSubAgent);
  }
  if (typeof value === "string" && normalizedSubAgentVariant(value) === "memoryConsolidation") {
    return [{ family: "internal", kind: "internal" }];
  }
  if (
    value
    && typeof value === "object"
    && (
      Object.hasOwn(value, "memory_consolidation")
      || Object.hasOwn(value, "memoryConsolidation")
      || Object.hasOwn(value, "internal")
    )
  ) {
    return [{ family: "internal", kind: "internal" }];
  }
  return [{
    family: "automation",
    kind: "subAgent",
    variant: normalizedSubAgentVariant(value),
  }];
}

function signalKey(signal) {
  return JSON.stringify(signal);
}

function uniqueSignals(signals) {
  const seen = new Set();
  const result = [];
  for (const signal of signals) {
    const key = signalKey(signal);
    if (!seen.has(key)) {
      seen.add(key);
      result.push(signal);
    }
  }
  return result;
}

function sourceFromSignals(signals) {
  const unique = uniqueSignals(signals);
  if (unique.length === 0) {
    return { kind: "unknown" };
  }
  if (unique.some((signal) => signal.family === "unknown")) {
    return { kind: "unknown" };
  }
  if (unique.some((signal) => signal.family === "internal")) {
    return { kind: "internal" };
  }

  const families = new Set(unique.map((signal) => signal.family));
  if (families.size !== 1) {
    return { kind: "unknown" };
  }
  const kinds = new Set(unique.map((signal) => (
    signal.kind === "custom"
      ? `custom:${signal.name}`
      : signal.kind === "subAgent"
        ? `subAgent:${signal.variant}`
        : signal.kind
  )));
  if (kinds.size !== 1) {
    return { kind: "unknown" };
  }

  const signal = unique[0];
  if (signal.kind === "custom") {
    return { kind: "custom", name: signal.name };
  }
  if (signal.kind === "subAgent") {
    return { kind: "subAgent", variant: signal.variant };
  }
  return { kind: signal.kind };
}

function signalsFromSourceObject(source) {
  const signals = [];
  for (const key of ["type", "kind", "sourceKind", "source_kind", "subtype", "custom"]) {
    if (typeof source[key] === "string") {
      signals.push(signalFromString(source[key]));
    }
  }
  if (source.source !== undefined) {
    signals.push(...signalsFromSourceValue(source.source));
  }
  for (const key of Object.keys(source)) {
    switch (canonicalSourceName(key)) {
      case "cli":
      case "vscode":
      case "exec":
      case "appserver":
      case "mcp":
      case "unknown":
      case "subagentreview":
      case "subagentcompact":
      case "subagentthreadspawn":
      case "subagentother":
        signals.push(signalFromString(key));
        break;
      case "subagent":
        signals.push(...signalFromSubAgent(source[key]));
        break;
      case "internal":
      case "memory":
      case "memoryconsolidation":
        signals.push({ family: "internal", kind: "internal" });
        break;
      default:
        break;
    }
  }
  return signals;
}

function signalsFromSourceValue(source) {
  if (typeof source === "string") {
    return [signalFromString(source)];
  }
  if (Array.isArray(source)) {
    return source.flatMap(signalsFromSourceValue);
  }
  if (source && typeof source === "object") {
    return signalsFromSourceObject(source);
  }
  return [];
}

function isInternalThreadSource(row) {
  const threadSource = row?.threadSource ?? row?.thread_source;
  switch (canonicalSourceName(threadSource)) {
    case "memoryconsolidation":
      return true;
    default:
      return false;
  }
}

function normalizedThreadSource(row) {
  if (isInternalThreadSource(row)) {
    return { kind: "internal" };
  }
  return sourceFromSignals(signalsFromSourceValue(row?.source));
}

function matchesDefaultInteractiveSource(row) {
  const source = normalizedThreadSource(row);
  return source.kind === "cli"
    || source.kind === "vscode"
    || (
      source.kind === "custom"
      && DEFAULT_INTERACTIVE_CUSTOM_SOURCES.has(source.name)
    );
}

function threadMatchesSingleSourceKind(row, sourceKind) {
  const source = normalizedThreadSource(row);
  switch (sourceKind) {
    case "cli":
      return source.kind === "cli";
    case "vscode":
      return source.kind === "vscode";
    case "exec":
      return source.kind === "exec";
    case "appServer":
      return source.kind === "appServer";
    case "subAgent":
      return source.kind === "subAgent";
    case "subAgentReview":
      return source.kind === "subAgent" && source.variant === "review";
    case "subAgentCompact":
      return source.kind === "subAgent" && source.variant === "compact";
    case "subAgentThreadSpawn":
      return source.kind === "subAgent" && source.variant === "threadSpawn";
    case "subAgentOther":
      return source.kind === "subAgent" && source.variant === "other";
    case "unknown":
      return source.kind === "unknown";
    default:
      return false;
  }
}

function threadMatchesSourceKinds(row, sourceKinds) {
  if (!Array.isArray(sourceKinds) || sourceKinds.length === 0) {
    return matchesDefaultInteractiveSource(row);
  }
  return sourceKinds.some((sourceKind) => threadMatchesSingleSourceKind(row, sourceKind));
}

export {
  canonicalSourceName,
  normalizedThreadSource,
  signalsFromSourceValue,
  threadMatchesSourceKinds,
};

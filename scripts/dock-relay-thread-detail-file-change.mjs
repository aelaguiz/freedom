function firstNonEmpty(...values) {
  for (const value of values) {
    if (typeof value !== "string") {
      continue;
    }
    const trimmed = value.trim();
    if (trimmed.length > 0) {
      return trimmed;
    }
  }
  return null;
}

function nonEmptyPreservingWhitespace(value) {
  if (typeof value !== "string") {
    return null;
  }
  return value.trim().length > 0 ? value : null;
}

function numberValue(value) {
  return Number.isFinite(Number(value)) ? Number(value) : null;
}

function rowFileChange(row) {
  return row?.payload?.fileChange || null;
}

function normalizeFileChangeKind(change) {
  const rawKind = typeof change?.kind === "string"
    ? change.kind
    : firstNonEmpty(change?.kind?.type, change?.type, change?.changeType);
  switch ((rawKind || "").toLowerCase()) {
    case "add":
    case "added":
    case "create":
    case "created":
      return "add";
    case "delete":
    case "deleted":
    case "remove":
    case "removed":
      return "delete";
    case "move":
    case "moved":
    case "rename":
    case "renamed":
      return "move";
    case "modify":
    case "modified":
    case "update":
    case "updated":
      return "update";
    default:
      return "unknown";
  }
}

function countChangedLines(diff, kind) {
  if (typeof diff !== "string" || diff.length === 0) {
    return { additions: 0, deletions: 0 };
  }
  const lines = diff.split(/\r?\n/u);
  let additions = 0;
  let deletions = 0;
  for (const line of lines) {
    if (line.startsWith("+++") || line.startsWith("---") || line.startsWith("@@")) {
      continue;
    }
    if (line.startsWith("+")) {
      additions += 1;
    } else if (line.startsWith("-")) {
      deletions += 1;
    }
  }
  if (additions === 0 && deletions === 0 && !diff.includes("@@")) {
    const contentLines = lines.filter((line, index) => index < lines.length - 1 || line.length > 0).length;
    if (kind === "add") {
      additions = contentLines;
    } else if (kind === "delete") {
      deletions = contentLines;
    }
  }
  return { additions, deletions };
}

function normalizeDiffAvailability(change, diff) {
  const explicit = firstNonEmpty(
    change?.diffAvailability,
    change?.availability,
    change?.status?.diffAvailability,
  );
  switch ((explicit || "").toLowerCase()) {
    case "available":
    case "text":
      return "available";
    case "binary":
      return "binary";
    case "generated":
      return "generated";
    case "toolarge":
    case "too_large":
    case "too-large":
    case "truncated":
      return "tooLarge";
    case "missing":
      return "missing";
    case "unsupported":
      return "unsupported";
    case "unknown":
      return "unknown";
    default:
      break;
  }
  if (change?.binary === true || change?.isBinary === true) {
    return "binary";
  }
  if (change?.generated === true || change?.isGenerated === true) {
    return "generated";
  }
  if (change?.truncated === true || change?.diffTruncated === true || change?.tooLarge === true) {
    return "tooLarge";
  }
  return diff ? "available" : "missing";
}

function normalizeFileChangeEntry(change) {
  const kind = normalizeFileChangeKind(change);
  const diff = nonEmptyPreservingWhitespace(change?.diff)
    ?? nonEmptyPreservingWhitespace(change?.patch)
    ?? nonEmptyPreservingWhitespace(change?.unifiedDiff)
    ?? nonEmptyPreservingWhitespace(change?.content);
  const counts = countChangedLines(diff, kind);
  const explicitAdditions = numberValue(change?.additions);
  const explicitDeletions = numberValue(change?.deletions);
  const diffAvailability = normalizeDiffAvailability(change, diff);
  const unavailableReason = firstNonEmpty(change?.unavailableReason, change?.reason)
    || (diffAvailability === "available" ? null : diffAvailability);
  const entry = {
    path: firstNonEmpty(change?.path, change?.newPath, change?.targetPath, change?.filePath) || "Unknown file",
    oldPath: firstNonEmpty(change?.oldPath, change?.previousPath, change?.sourcePath, change?.kind?.move_path, change?.kind?.movePath),
    kind,
    additions: explicitAdditions ?? counts.additions,
    deletions: explicitDeletions ?? counts.deletions,
    diffAvailability,
    diff: diff || null,
    truncated: Boolean(change?.truncated === true || change?.diffTruncated === true || diffAvailability === "tooLarge"),
  };
  if (unavailableReason) {
    entry.unavailableReason = unavailableReason;
  }
  return entry;
}

function normalizeFileChangeStatus(source, approvalRequired) {
  const rawStatus = typeof source?.status === "string"
    ? source.status
    : firstNonEmpty(source?.status?.type, source?.state, source?.phase);
  switch ((rawStatus || "").toLowerCase()) {
    case "completed":
    case "complete":
    case "done":
      return approvalRequired ? "pending" : "completed";
    case "pending":
    case "waiting":
    case "waitingonapproval":
    case "waiting_on_approval":
      return "pending";
    case "applied":
      return "applied";
    case "declined":
    case "rejected":
      return "declined";
    case "failed":
    case "error":
      return "failed";
    default:
      return approvalRequired ? "pending" : "unknown";
  }
}

function normalizeFileChangePayload(source, {
  approvalRequired = false,
  unavailableReason = null,
} = {}) {
  const changesSource = source?.fileChange || source || {};
  const rawChanges = Array.isArray(changesSource.changes)
    ? changesSource.changes
    : (Array.isArray(changesSource.files) ? changesSource.files : []);
  const changes = rawChanges
    .filter((change) => change && typeof change === "object")
    .map((change) => normalizeFileChangeEntry(change));
  const summary = changes.reduce((memo, change) => ({
    fileCount: memo.fileCount + 1,
    additions: memo.additions + change.additions,
    deletions: memo.deletions + change.deletions,
    truncated: memo.truncated || change.truncated,
  }), {
    fileCount: 0,
    additions: 0,
    deletions: 0,
    truncated: false,
  });
  const rowReason = firstNonEmpty(
    unavailableReason,
    changesSource.unavailableReason,
    changesSource.reason,
    changes.length === 0 ? "missingDiff" : null,
  );
  const payload = {
    version: 1,
    status: normalizeFileChangeStatus(changesSource, approvalRequired),
    approvalRequired: Boolean(approvalRequired),
    summary,
    changes,
  };
  if (rowReason) {
    payload.unavailableReason = rowReason;
  }
  return payload;
}

function fileChangeDisplayBody(fileChange) {
  if (!fileChange) {
    return "File changes are available on desktop.";
  }
  const fileCount = Number(fileChange.summary?.fileCount || fileChange.changes?.length || 0);
  const additions = Number(fileChange.summary?.additions || 0);
  const deletions = Number(fileChange.summary?.deletions || 0);
  if (fileCount <= 0) {
    return "Diff unavailable on phone.";
  }
  const fileLabel = fileCount === 1 ? "file" : "files";
  if (fileChange.approvalRequired) {
    return `Review ${fileCount} ${fileLabel} before approving, +${additions} -${deletions}`;
  }
  return `${fileCount} ${fileLabel} changed, +${additions} -${deletions}`;
}

export {
  fileChangeDisplayBody,
  normalizeFileChangePayload,
  rowFileChange,
};

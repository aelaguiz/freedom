import { THREAD_LIST_MAX_LIMIT } from "./dock-relay-constants.mjs";
import {
  aggregateLoadedList,
  aggregateThreadRead,
  listThreadTurns,
  readHistoryThread,
  readHistoryThreadGoal,
  readHistoryThreadList,
} from "./dock-relay-thread-data.mjs";

const STATE_SNAPSHOT_SCHEMA_VERSION = 1;
const DEFAULT_SORT_KEY = "updated_at";
const DEFAULT_SORT_DIRECTION = "desc";
const THREAD_SURFACE_FIELDS = Object.freeze([
  ["id", ["id"]],
  ["createdAt", ["createdAt"]],
  ["updatedAt", ["updatedAt"]],
  ["cwd", ["cwd"]],
  ["path", ["path"]],
  ["modelProvider", ["modelProvider"]],
  ["model", ["model"]],
  ["cliVersion", ["cliVersion"]],
  ["source", ["source"]],
  ["threadSource", ["threadSource"]],
  ["status.type", ["status", "type"]],
  ["git.sha", ["gitInfo", "sha"]],
  ["git.branch", ["gitInfo", "branch"]],
  ["git.originUrl", ["gitInfo", "originUrl"]],
  ["agentNickname", ["agentNickname"]],
  ["agentRole", ["agentRole"]],
  ["agentPath", ["agentPath"]],
]);
const CANONICAL_SURFACE_PRIORITY = Object.freeze([
  "routed thread/read",
  "history thread/read",
  "thread/list:allSourceKinds",
  "thread/list:interactiveDefault",
  "thread/list",
]);

const EXPLICIT_SOURCE_KINDS = Object.freeze([
  "cli",
  "vscode",
  "exec",
  "appServer",
  "subAgent",
  "subAgentReview",
  "subAgentCompact",
  "subAgentThreadSpawn",
  "subAgentOther",
  "unknown",
]);
const ALL_SOURCE_KINDS_SCOPE = "allSourceKinds";

function parseLimit(value, fallback = THREAD_LIST_MAX_LIMIT) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return fallback;
  }
  return Math.min(THREAD_LIST_MAX_LIMIT, Math.floor(parsed));
}

function sourceScopes(params = {}) {
  if (Array.isArray(params.sourceScopes) && params.sourceScopes.length > 0) {
    return params.sourceScopes.map((scope) => {
      if (scope === "interactiveDefault") {
        return {
          name: "interactiveDefault",
          sourceKinds: null,
          meaning: "app-server default interactive source scope",
        };
      }
      if (scope === ALL_SOURCE_KINDS_SCOPE) {
        return {
          name: ALL_SOURCE_KINDS_SCOPE,
          sourceKinds: [...EXPLICIT_SOURCE_KINDS],
          meaning: "app-server explicit sourceKinds union preserving combined Codex order",
        };
      }
      return {
        name: String(scope),
        sourceKinds: [String(scope)],
        meaning: `app-server explicit sourceKinds ${String(scope)}`,
      };
    });
  }
  return [
    {
      name: "interactiveDefault",
      sourceKinds: null,
      meaning: "app-server default interactive source scope",
    },
    {
      name: ALL_SOURCE_KINDS_SCOPE,
      sourceKinds: [...EXPLICIT_SOURCE_KINDS],
      meaning: "app-server explicit sourceKinds union preserving combined Codex order",
    },
    ...EXPLICIT_SOURCE_KINDS.map((sourceKind) => ({
      name: sourceKind,
      sourceKinds: [sourceKind],
      meaning: `app-server explicit sourceKinds ${sourceKind}`,
    })),
  ];
}

function archiveScopes(params = {}) {
  if (params.includeArchived === false) {
    return [{ name: "active", archived: false }];
  }
  if (params.onlyArchived === true) {
    return [{ name: "archived", archived: true }];
  }
  return [
    { name: "active", archived: false },
    { name: "archived", archived: true },
  ];
}

function baseThreadListParams(params, archived, sourceScope, cursor) {
  const request = {
    limit: parseLimit(params.limit),
    sortKey: params.sortKey || DEFAULT_SORT_KEY,
    sortDirection: params.sortDirection || DEFAULT_SORT_DIRECTION,
    modelProviders: Array.isArray(params.modelProviders) ? params.modelProviders : [],
    archived,
  };
  if (cursor) {
    request.cursor = cursor;
  }
  if (Array.isArray(sourceScope.sourceKinds)) {
    request.sourceKinds = sourceScope.sourceKinds;
  }
  if (params.cwd !== undefined) {
    request.cwd = params.cwd;
  }
  if (params.searchTerm !== undefined) {
    request.searchTerm = params.searchTerm;
  }
  if (params.useStateDbOnly !== undefined) {
    request.useStateDbOnly = params.useStateDbOnly;
  }
  return request;
}

async function drainThreadListScope(config, params, archiveScope, sourceScope) {
  const pages = [];
  const rows = [];
  const seenCursors = new Set();
  let cursor = null;
  let complete = true;
  let error = null;
  let ordinal = 0;

  try {
    while (true) {
      const request = baseThreadListParams(params, archiveScope.archived, sourceScope, cursor);
      const response = await readHistoryThreadList(config, request);
      const data = Array.isArray(response?.data) ? response.data : [];
      const page = {
        cursor,
        nextCursor: response?.nextCursor || null,
        backwardsCursor: response?.backwardsCursor || null,
        rowCount: data.length,
      };
      pages.push(page);
      for (let index = 0; index < data.length; index += 1) {
        rows.push({
          ordinal,
          pageIndex: pages.length - 1,
          rowIndex: index,
          thread: data[index],
        });
        ordinal += 1;
      }
      const nextCursor = response?.nextCursor || null;
      if (!nextCursor) {
        break;
      }
      if (seenCursors.has(nextCursor)) {
        complete = false;
        error = `repeated thread/list cursor ${nextCursor}`;
        break;
      }
      seenCursors.add(nextCursor);
      cursor = nextCursor;
    }
  } catch (caught) {
    complete = false;
    error = caught?.message || String(caught);
  }

  return {
    name: `${archiveScope.name}:${sourceScope.name}`,
    archive: archiveScope.name,
    archived: archiveScope.archived,
    sourceScope: sourceScope.name,
    sourceKinds: sourceScope.sourceKinds,
    meaning: sourceScope.meaning,
    complete,
    error,
    pages,
    rowCount: rows.length,
    threadIDsInCodexOrder: rows.map((row) => row.thread?.id).filter(Boolean),
    rows,
  };
}

function ensureThreadEntry(threadsByID, threadID) {
  if (!threadsByID.has(threadID)) {
    threadsByID.set(threadID, {
      threadID,
      appearances: [],
      listRows: [],
      historyRead: null,
      routedRead: null,
      goalRead: null,
      turns: null,
      surfaceSummary: null,
      errors: [],
    });
  }
  return threadsByID.get(threadID);
}

function attachScopeRows(threadsByID, scope) {
  for (const row of scope.rows) {
    const threadID = row.thread?.id;
    if (!threadID) {
      continue;
    }
    const entry = ensureThreadEntry(threadsByID, threadID);
    entry.appearances.push({
      scope: scope.name,
      archive: scope.archive,
      archived: scope.archived,
      sourceScope: scope.sourceScope,
      ordinal: row.ordinal,
      pageIndex: row.pageIndex,
      rowIndex: row.rowIndex,
    });
    entry.listRows.push({
      scope: scope.name,
      thread: row.thread,
    });
  }
}

function valueAtPath(value, path) {
  let current = value;
  for (const part of path) {
    if (current === null || current === undefined) {
      return undefined;
    }
    current = current[part];
  }
  return current;
}

function stableValueKey(value) {
  if (value === undefined) {
    return "undefined";
  }
  if (value === null) {
    return "null";
  }
  if (Array.isArray(value)) {
    return `[${value.map(stableValueKey).join(",")}]`;
  }
  if (typeof value === "object") {
    return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${stableValueKey(value[key])}`).join(",")}}`;
  }
  return `${typeof value}:${String(value)}`;
}

function cloneComparableValue(value) {
  if (value === undefined) {
    return null;
  }
  if (value === null || typeof value !== "object") {
    return value ?? null;
  }
  return JSON.parse(JSON.stringify(value));
}

function addSurfaceValue(valuesByField, field, value, surface) {
  if (value === undefined) {
    return;
  }
  if (!valuesByField.has(field)) {
    valuesByField.set(field, new Map());
  }
  const byValue = valuesByField.get(field);
  const valueKey = stableValueKey(value);
  if (!byValue.has(valueKey)) {
    byValue.set(valueKey, {
      value: cloneComparableValue(value),
      surfaces: [],
    });
  }
  byValue.get(valueKey).surfaces.push(surface);
}

function surfaceRank(surface) {
  if (surface?.kind === "routed thread/read") {
    return 0;
  }
  if (surface?.kind === "history thread/read") {
    return 1;
  }
  if (surface?.kind === "thread/list" && surface?.scope?.endsWith(`:${ALL_SOURCE_KINDS_SCOPE}`)) {
    return 2;
  }
  if (surface?.kind === "thread/list" && surface?.scope?.endsWith(":interactiveDefault")) {
    return 3;
  }
  if (surface?.kind === "thread/list") {
    return 4;
  }
  return 5;
}

function compareSurfacePriority(left, right) {
  const rankDiff = surfaceRank(left) - surfaceRank(right);
  if (rankDiff !== 0) {
    return rankDiff;
  }
  const leftKey = `${left?.kind || ""}:${left?.scope || ""}`;
  const rightKey = `${right?.kind || ""}:${right?.scope || ""}`;
  return leftKey.localeCompare(rightKey);
}

function canonicalSurfaceForValue(valueEntry) {
  return [...(valueEntry?.surfaces || [])].sort(compareSurfacePriority)[0] || null;
}

function canonicalFieldProjection(valuesByField) {
  const fields = {};
  for (const [field, byValue] of valuesByField.entries()) {
    const candidates = [...byValue.values()].map((entry) => ({
      value: entry.value,
      source: canonicalSurfaceForValue(entry),
      valueCount: byValue.size,
      hasConflict: byValue.size > 1,
    }));
    candidates.sort((left, right) => compareSurfacePriority(left.source, right.source));
    fields[field] = candidates[0];
  }
  return {
    meaning: "deterministic relay app-server projection; each field records the winning app-server surface and does not use disk or SQLite",
    priority: [...CANONICAL_SURFACE_PRIORITY],
    fields,
    conflictFields: Object.entries(fields)
      .filter(([, projection]) => projection.hasConflict)
      .map(([field]) => field)
      .sort((left, right) => left.localeCompare(right)),
  };
}

function threadSurfaceSummary(entry) {
  const valuesByField = new Map();
  for (const row of entry.listRows || []) {
    for (const [field, path] of THREAD_SURFACE_FIELDS) {
      addSurfaceValue(valuesByField, field, valueAtPath(row.thread, path), {
        kind: "thread/list",
        scope: row.scope,
      });
    }
  }
  for (const [kind, read] of [
    ["history thread/read", entry.historyRead],
    ["routed thread/read", entry.routedRead],
  ]) {
    if (!read?.thread) {
      continue;
    }
    for (const [field, path] of THREAD_SURFACE_FIELDS) {
      addSurfaceValue(valuesByField, field, valueAtPath(read.thread, path), { kind });
    }
  }

  const fieldConflicts = [];
  for (const [field, byValue] of valuesByField.entries()) {
    if (byValue.size <= 1) {
      continue;
    }
    fieldConflicts.push({
      field,
      values: [...byValue.values()],
    });
  }
  fieldConflicts.sort((left, right) => left.field.localeCompare(right.field));

  return {
    meaning: "comparison of app-server-provided list/read surfaces only; no disk or SQLite data is used",
    canonicalProjection: canonicalFieldProjection(valuesByField),
    comparedFields: THREAD_SURFACE_FIELDS.map(([field]) => field),
    surfaceCounts: {
      listRows: entry.listRows?.length || 0,
      historyRead: entry.historyRead?.thread ? 1 : 0,
      routedRead: entry.routedRead?.thread ? 1 : 0,
    },
    hasConflicts: fieldConflicts.length > 0,
    conflictingFields: fieldConflicts.map((conflict) => conflict.field),
    fieldConflicts,
  };
}

function attachSurfaceSummaries(threads) {
  for (const entry of threads) {
    entry.surfaceSummary = threadSurfaceSummary(entry);
  }
}

async function readThreadDetails(config, params, threads) {
  const includeThreadReads = params.includeThreadReads !== false;
  const includeTurns = params.includeTurns === true;
  if (!includeThreadReads && !includeTurns) {
    return;
  }
  for (const entry of threads) {
    if (includeThreadReads) {
      try {
        entry.historyRead = await readHistoryThread(config, {
          threadId: entry.threadID,
          includeTurns: false,
        });
      } catch (error) {
        entry.errors.push({
          source: "history thread/read",
          message: error?.message || String(error),
        });
      }
      try {
        entry.routedRead = await aggregateThreadRead(config, {
          threadId: entry.threadID,
          includeTurns: false,
        });
      } catch (error) {
        entry.errors.push({
          source: "routed thread/read",
          message: error?.message || String(error),
        });
      }
    }
    if (includeTurns) {
      entry.turns = await drainThreadTurns(config, entry.threadID, params);
    }
  }
}

async function readThreadGoals(config, params, threads) {
  if (params.includeGoals !== true) {
    return;
  }
  for (const entry of threads) {
    try {
      entry.goalRead = await readHistoryThreadGoal(config, {
        threadId: entry.threadID,
      });
    } catch (error) {
      entry.errors.push({
        source: "history thread/goal/get",
        message: error?.message || String(error),
      });
    }
  }
}

async function drainThreadTurns(config, threadID, params = {}) {
  const pages = [];
  const turns = [];
  const seenCursors = new Set();
  let cursor = null;
  let complete = true;
  let error = null;
  let ordinal = 0;

  try {
    while (true) {
      const request = {
        threadId: threadID,
        limit: parseLimit(params.turnLimit || params.limit),
        sortDirection: params.turnSortDirection || "desc",
        itemsView: params.turnItemsView || "notLoaded",
      };
      if (cursor) {
        request.cursor = cursor;
      }
      const response = await listThreadTurns(config, request);
      const data = Array.isArray(response?.data) ? response.data : [];
      pages.push({
        cursor,
        nextCursor: response?.nextCursor || null,
        backwardsCursor: response?.backwardsCursor || null,
        rowCount: data.length,
      });
      for (let index = 0; index < data.length; index += 1) {
        turns.push({
          ordinal,
          pageIndex: pages.length - 1,
          rowIndex: index,
          turn: data[index],
        });
        ordinal += 1;
      }
      const nextCursor = response?.nextCursor || null;
      if (!nextCursor) {
        break;
      }
      if (seenCursors.has(nextCursor)) {
        complete = false;
        error = `repeated thread/turns/list cursor ${nextCursor}`;
        break;
      }
      seenCursors.add(nextCursor);
      cursor = nextCursor;
    }
  } catch (caught) {
    complete = false;
    error = caught?.message || String(caught);
  }

  return {
    complete,
    error,
    pages,
    turnCount: turns.length,
    turnsInCodexOrder: turns,
  };
}

function snapshotCompleteness(scopes, loaded, threads) {
  return scopes.every((scope) => scope.complete)
    && loaded.complete
    && threads.every((thread) => thread.errors.length === 0 && (!thread.turns || thread.turns.complete));
}

async function buildRelayStateSnapshot(config, params = {}) {
  const scopes = [];
  const threadsByID = new Map();
  for (const archiveScope of archiveScopes(params)) {
    for (const sourceScope of sourceScopes(params)) {
      const scope = await drainThreadListScope(config, params, archiveScope, sourceScope);
      scopes.push(scope);
      attachScopeRows(threadsByID, scope);
    }
  }

  const threads = [...threadsByID.values()].sort((lhs, rhs) => lhs.threadID.localeCompare(rhs.threadID));
  await readThreadDetails(config, params, threads);
  await readThreadGoals(config, params, threads);
  attachSurfaceSummaries(threads);

  let loaded = {
    complete: true,
    error: null,
    threadIDs: [],
  };
  if (params.includeLoaded !== false) {
    try {
      const response = await aggregateLoadedList(config, { limit: THREAD_LIST_MAX_LIMIT });
      loaded = {
        complete: !response.nextCursor,
        error: response.nextCursor ? "loaded thread list exceeded relay page cap" : null,
        threadIDs: response.data || [],
        nextCursor: response.nextCursor || null,
      };
    } catch (error) {
      loaded = {
        complete: false,
        error: error?.message || String(error),
        threadIDs: [],
      };
    }
  }

  return {
    schemaVersion: STATE_SNAPSHOT_SCHEMA_VERSION,
    kind: "relayStateSnapshot",
    generatedAt: new Date().toISOString(),
    source: "app-server-only",
    surfaceMeanings: {
      "thread/list": "app-server list row scoped by archived/source filters; order is preserved within each scope only",
      "history thread/read": "raw configured history app-server thread/read result for a known thread ID",
      "routed thread/read": "relay-routed thread/read result; live owners may return live status/detail, otherwise history app-server is used",
      "thread/search": "app-server term-bound search for known text; forwarded by relay but not used as a global enumeration source",
      "thread/turns/list": "app-server turn pages for a known thread ID, preserved in returned page order; full items expose userMessage evidence for prompt-shape inference but not a formal thread-start source",
      "thread/goal/get": "app-server current goal lookup for a known thread ID; this is not a standalone goal list",
      canonicalProjection: "relay-owned deterministic projection across app-server surfaces; field values prefer routed thread/read, then history thread/read, then app-server list rows in combined/default/list order",
    },
    order: {
      sortKey: params.sortKey || DEFAULT_SORT_KEY,
      sortDirection: params.sortDirection || DEFAULT_SORT_DIRECTION,
      preservedWithinEachScope: true,
    },
    turnRequest: {
      included: params.includeTurns === true,
      sortDirection: params.turnSortDirection || "desc",
      itemsView: params.turnItemsView || "notLoaded",
    },
    complete: snapshotCompleteness(scopes, loaded, threads),
    scopeCount: scopes.length,
    threadCount: threads.length,
    scopes,
    loaded,
    threads,
  };
}

export {
  ALL_SOURCE_KINDS_SCOPE,
  buildRelayStateSnapshot,
  drainThreadTurns,
  drainThreadListScope,
  EXPLICIT_SOURCE_KINDS,
};

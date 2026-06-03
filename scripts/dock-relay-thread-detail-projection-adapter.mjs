import crypto from "node:crypto";

import {
  PROJECTION_ENGINE_VERSION as THREAD_DETAIL_PROJECTION_ENGINE_VERSION,
  PROJECTION_IDENTITY_VERSION as THREAD_DETAIL_IDENTITY_VERSION,
  PROJECTION_SCHEMA_VERSION as THREAD_DETAIL_SCHEMA_VERSION,
  THREAD_DETAIL_DEFAULT_VIEW_PARAMS_KEY,
  THREAD_DETAIL_ORDER,
  THREAD_DETAIL_VIEW,
  projectionIDForThreadDiagnostic as projectionIDForDiagnostic,
  projectionIDForThreadItem as projectionIDForItem,
  projectionIDForThreadRequest as projectionIDForRequest,
  projectionIDForThreadSystem as projectionIDForSystem,
  shortHash,
  sourceRefForThreadDiagnostic as sourceRefForDiagnostic,
  sourceRefForThreadItem as sourceRefForItem,
  sourceRefForThreadRequest as sourceRefForRequest,
  sourceRefForThreadSystem as sourceRefForSystem,
  stableStringify,
  threadDetailDisplayOrderKey as displayOrderKey,
} from "./dock-relay-projection-engine.mjs";

const THREAD_DETAIL_UPDATE_METHOD = "thread/detail/update";

function nonEmptyString(value) {
  if (typeof value !== "string") {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

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

function timestampMs(value, { unit = "auto" } = {}) {
  const number = numberValue(value);
  if (number === null) {
    return null;
  }
  if (unit === "seconds") {
    return Math.trunc(number * 1000);
  }
  if (unit === "milliseconds") {
    return Math.trunc(number);
  }
  return number < 10_000_000_000 ? Math.trunc(number * 1000) : Math.trunc(number);
}

function firstTimestampMs(...candidates) {
  for (const candidate of candidates) {
    const value = timestampMs(candidate.value, { unit: candidate.unit || "auto" });
    if (value !== null) {
      return value;
    }
  }
  return null;
}

function isoFromMs(ms) {
  if (!Number.isFinite(Number(ms)) || Number(ms) <= 0) {
    return null;
  }
  return new Date(Number(ms)).toISOString();
}

function freshness(sourceWatermark = null) {
  return {
    state: "fresh",
    asOf: new Date().toISOString(),
    sourceWatermark,
  };
}

function resolveIdentity(label, candidates) {
  const values = candidates
    .map((candidate) => nonEmptyString(candidate?.value))
    .filter(Boolean);
  const unique = [...new Set(values)];
  if (unique.length === 0) {
    return { value: null, error: `${label}_missing`, candidates: [] };
  }
  if (unique.length > 1) {
    return { value: null, error: `${label}_conflict`, candidates: unique };
  }
  return { value: unique[0], error: null, candidates: unique };
}

function textList(value) {
  if (typeof value === "string") {
    return firstNonEmpty(value);
  }
  if (Array.isArray(value)) {
    return firstNonEmpty(...value.map((item) => {
      if (typeof item === "string") {
        return item;
      }
      return item?.text;
    }));
  }
  if (value && typeof value === "object") {
    return firstNonEmpty(value.text);
  }
  return null;
}

function userInputText(value) {
  if (typeof value === "string") {
    return firstNonEmpty(value);
  }
  if (!Array.isArray(value)) {
    return null;
  }
  return firstNonEmpty(value.map((item) => (
    typeof item === "string" ? item : item?.text
  )).filter(Boolean).join("\n"));
}

function commandText(value) {
  if (typeof value === "string") {
    return firstNonEmpty(value);
  }
  if (Array.isArray(value)) {
    return firstNonEmpty(value.filter((part) => typeof part === "string").join(" "));
  }
  if (value && typeof value === "object") {
    return firstNonEmpty(value.command, value.cmd, value.text);
  }
  return null;
}

function itemActivityMs(type, {
  defaultMs,
  turnStartedAtMs,
  turnCompletedAtMs,
}) {
  switch (type) {
    case "userMessage":
      return turnStartedAtMs ?? defaultMs;
    case "agentMessage":
    case "plan":
    case "reasoning":
    case "commandExecution":
    case "fileChange":
    case "mcpToolCall":
    case "dynamicToolCall":
      return turnCompletedAtMs ?? turnStartedAtMs ?? defaultMs;
    default:
      return defaultMs;
  }
}

function lifecycleActivityMs(method, params, nowMs) {
  switch (method) {
    case "item/started":
      return timestampMs(params?.startedAtMs, { unit: "milliseconds" }) ?? nowMs;
    case "item/completed":
      return timestampMs(params?.completedAtMs, { unit: "milliseconds" })
        ?? timestampMs(params?.startedAtMs, { unit: "milliseconds" })
        ?? nowMs;
    default:
      return nowMs;
  }
}

function diagnosticHash({
  sourceHostID,
  threadID,
  rawKind,
  turnID,
  itemID,
  requestID,
  errorCode,
}) {
  return shortHash(stableStringify({
    identityVersion: THREAD_DETAIL_IDENTITY_VERSION,
    sourceHostID,
    threadID,
    rawKind,
    turnID,
    itemID,
    requestID,
    errorCode,
  }), 16);
}

function diagnosticEvent({
  sourceHostID,
  threadID,
  rawKind,
  turnID = null,
  itemID = null,
  requestID = null,
  errorCode,
  activityAtMs = Date.now(),
}) {
  const hash = diagnosticHash({
    sourceHostID,
    threadID,
    rawKind,
    turnID,
    itemID,
    requestID,
    errorCode,
  });
  const sourceRef = sourceRefForDiagnostic({ sourceHostID, threadID, diagnosticID: hash });
  const projectionID = projectionIDForDiagnostic({ sourceHostID, threadID, diagnosticID: hash });
  return makeProjectionRow({
    sourceHostID,
    threadID,
    projectionID,
    sourceRef,
    itemType: rawKind,
    rowRole: "unknown",
    visibility: "unknown",
    renderKind: "unknown",
    title: "Projection diagnostic",
    body: `Projection identity issue: ${errorCode}`,
    eventTimeMs: activityAtMs,
    activityAtMs,
    renderState: "diagnostic",
    diagnostic: {
      code: errorCode,
      rawKind,
      turnID,
      itemID,
      requestID,
    },
  });
}

function makeProjectionRow({
  sourceHostID,
  threadID,
  projectionID,
  sourceRef,
  itemType = null,
  rowRole,
  visibility,
  renderKind,
  title,
  body,
  eventTimeMs = null,
  activityAtMs = null,
  turnID = null,
  itemID = null,
  turnOrder = null,
  itemOrder = null,
  rowOrder = 0,
  renderState = "settled",
  requestID = null,
  request = null,
  diagnostic = null,
  revision = 1,
  sourceWatermark = null,
}) {
  const resolvedActivityMs = activityAtMs ?? eventTimeMs ?? Date.now();
  const resolvedEventMs = eventTimeMs ?? resolvedActivityMs;
  return {
    schemaVersion: THREAD_DETAIL_SCHEMA_VERSION,
    identityVersion: THREAD_DETAIL_IDENTITY_VERSION,
    projectionEngineVersion: THREAD_DETAIL_PROJECTION_ENGINE_VERSION,
    sourceHostID,
    view: THREAD_DETAIL_VIEW,
    threadID,
    projectionID,
    sourceRef,
    rowRole,
    displayOrderKey: displayOrderKey({
      activityAtMs: resolvedActivityMs,
      turnOrder,
      itemOrder,
      rowOrder,
      projectionID,
    }),
    revision,
    freshness: freshness(sourceWatermark),
    payload: {
      turnID,
      itemID,
      itemType,
      visibility,
      renderKind,
      title,
      body,
      eventTime: isoFromMs(resolvedEventMs),
      activityTime: isoFromMs(resolvedActivityMs),
      turnOrder,
      itemOrder,
      rowOrder,
      renderState,
      requestID,
      request,
      diagnostic,
    },
  };
}

function rowPayload(row) {
  return row?.payload || {};
}

function rowRequestID(row) {
  return rowPayload(row).requestID;
}

function rowRequest(row) {
  return rowPayload(row).request;
}

function rowRenderState(row) {
  return rowPayload(row).renderState;
}

function rowRenderKind(row) {
  return rowPayload(row).renderKind;
}

function rowBody(row) {
  return rowPayload(row).body;
}

function rowSpecsForItem(item) {
  const type = item?.type || "unknown";
  switch (type) {
    case "userMessage":
      return [{
        rowRole: "userMessage",
        renderKind: "userMessage",
        visibility: "message",
        title: "User message",
        body: userInputText(item.content) || "User input",
        rowOrder: 0,
      }];
    case "agentMessage":
      return [{
        rowRole: "agentMessage",
        renderKind: "agentMessage",
        visibility: "message",
        title: "Agent message",
        body: firstNonEmpty(item.text, "Agent message") || "Agent message",
        rowOrder: 0,
      }];
    case "plan":
      return [{
        rowRole: "plan",
        renderKind: "agentMessage",
        visibility: "thinking",
        title: "Plan",
        body: firstNonEmpty(item.text, "Plan update") || "Plan update",
        rowOrder: 0,
      }];
    case "reasoning":
      return [{
        rowRole: "reasoning",
        renderKind: "agentMessage",
        visibility: "thinking",
        title: "Reasoning",
        body: textList(item.summary) || textList(item.content) || "Reasoning",
        rowOrder: 0,
      }];
    case "commandExecution":
    {
      const rows = [{
        rowRole: "command",
        renderKind: "command",
        visibility: "tooling",
        title: "Command",
        body: commandText(item.command) || "Command",
        rowOrder: 0,
      }];
      const output = firstNonEmpty(item.aggregatedOutput);
      if (output) {
        rows.push({
          rowRole: "commandOutput",
          renderKind: "output",
          visibility: "tooling",
          title: "Command output",
          body: output,
          rowOrder: 1,
        });
      }
      return rows;
    }
    case "fileChange":
      return [{
        rowRole: "fileChange",
        renderKind: "request",
        visibility: "request",
        title: "File change",
        body: "File changes are available on desktop.",
        rowOrder: 0,
      }];
    case "mcpToolCall":
    case "dynamicToolCall":
      return [{
        rowRole: "toolCall",
        renderKind: "command",
        visibility: "tooling",
        title: "Tool call",
        body: item.tool || item.namespace || "Tool call",
        rowOrder: 0,
      }];
    default:
      return [{
        rowRole: "unknown",
        renderKind: "unknown",
        visibility: "unknown",
        title: "Unsupported event",
        body: `Unsupported event type: ${type}`,
        rowOrder: 0,
      }];
  }
}

function eventsFromItem(item, {
  sourceHostID,
  threadID,
  turn = {},
  liveParams = null,
  defaultMs = null,
  turnStartedAtMs = null,
  turnCompletedAtMs = null,
  turnOrder = null,
  itemOrder = null,
  renderState = "settled",
}) {
  const rawKind = item?.type || "unknown";
  const turnID = resolveIdentity("turnID", liveParams
    ? [
      { value: liveParams.turnId },
      { value: liveParams.turnID },
      { value: liveParams.turn?.id },
      { value: item?.turnId },
      { value: item?.turnID },
    ]
    : [
      { value: turn?.id },
      { value: turn?.turnId },
      { value: turn?.turnID },
    ]);
  const itemID = resolveIdentity("itemID", liveParams
    ? [
      { value: liveParams.itemId },
      { value: liveParams.itemID },
      { value: item?.id },
    ]
    : [
      { value: item?.id },
    ]);
  const activityAtMs = itemActivityMs(rawKind, {
    defaultMs,
    turnStartedAtMs,
    turnCompletedAtMs,
  }) ?? Date.now();

  if (!item || typeof item !== "object") {
    return [diagnosticEvent({
      sourceHostID,
      threadID,
      rawKind: "nonObjectItem",
      errorCode: "item_shape_invalid",
      activityAtMs,
    })];
  }

  if (turnID.error || itemID.error) {
    return [diagnosticEvent({
      sourceHostID,
      threadID,
      rawKind,
      turnID: turnID.value,
      itemID: itemID.value,
      errorCode: turnID.error || itemID.error,
      activityAtMs,
    })];
  }

  const sourceRef = sourceRefForItem({
    sourceHostID,
    threadID,
    turnID: turnID.value,
    itemID: itemID.value,
  });
  return rowSpecsForItem(item).map((spec) => makeProjectionRow({
    sourceHostID,
    threadID,
    projectionID: projectionIDForItem({
      sourceHostID,
      threadID,
      turnID: turnID.value,
      itemID: itemID.value,
      rowRole: spec.rowRole,
    }),
    sourceRef,
    itemType: rawKind,
    rowRole: spec.rowRole,
    visibility: spec.visibility,
    renderKind: spec.renderKind,
    title: spec.title,
    body: spec.body,
    eventTimeMs: activityAtMs,
    activityAtMs,
    turnID: turnID.value,
    itemID: itemID.value,
    turnOrder,
    itemOrder,
    rowOrder: spec.rowOrder,
    renderState,
  }));
}

function eventsFromTurn(turn, {
  sourceHostID,
  threadID,
  turnOrder,
}) {
  if (!turn || typeof turn !== "object") {
    return [];
  }
  const turnStartedAtMs = firstTimestampMs(
    { value: turn.startedAtMs, unit: "milliseconds" },
    { value: turn.startedAt, unit: "seconds" },
    { value: turn.createdAtMs, unit: "milliseconds" },
    { value: turn.createdAt, unit: "auto" },
  );
  const turnCompletedAtMs = firstTimestampMs(
    { value: turn.completedAtMs, unit: "milliseconds" },
    { value: turn.completedAt, unit: "seconds" },
    { value: turn.finishedAtMs, unit: "milliseconds" },
    { value: turn.finishedAt, unit: "auto" },
    { value: turn.updatedAtMs, unit: "milliseconds" },
    { value: turn.updatedAt, unit: "auto" },
  );
  const defaultMs = turnStartedAtMs ?? turnCompletedAtMs;
  const items = Array.isArray(turn.items) ? turn.items : [];
  return items.flatMap((item, itemOrder) => eventsFromItem(item, {
    sourceHostID,
    threadID,
    turn,
    defaultMs,
    turnStartedAtMs,
    turnCompletedAtMs,
    turnOrder,
    itemOrder,
    renderState: "settled",
  }));
}

function activeTurnIDFromThread(thread) {
  const turns = Array.isArray(thread?.turns) ? thread.turns : [];
  for (const turn of turns) {
    if (turn?.status === "inProgress" && turn?.id) {
      return turn.id;
    }
  }
  return null;
}

function eventsFromThread(thread, {
  sourceHostID,
  threadID = thread?.id,
} = {}) {
  const turns = Array.isArray(thread?.turns) ? thread.turns : [];
  return turns.flatMap((turn, turnOrder) => eventsFromTurn(turn, {
    sourceHostID,
    threadID,
    turnOrder,
  }));
}

function deltaMethodSpec(method) {
  switch (method) {
    case "item/agentMessage/delta":
      return {
        rowRole: "agentMessage",
        renderKind: "agentMessage",
        visibility: "message",
        title: "Agent update",
        key: "delta",
      };
    case "item/plan/delta":
      return {
        rowRole: "plan",
        renderKind: "agentMessage",
        visibility: "thinking",
        title: "Plan update",
        key: "delta",
      };
    case "item/reasoning/summaryTextDelta":
    case "item/reasoning/textDelta":
      return {
        rowRole: "reasoning",
        renderKind: "agentMessage",
        visibility: "thinking",
        title: "Reasoning update",
        key: "delta",
      };
    case "item/commandExecution/outputDelta":
      return {
        rowRole: "commandOutput",
        renderKind: "output",
        visibility: "tooling",
        title: "Command output",
        key: "delta",
      };
    default:
      return null;
  }
}

function deltaEventFromNotification(message, {
  sourceHostID,
  threadID,
  nowMs,
}) {
  const params = message?.params || {};
  const spec = deltaMethodSpec(message?.method);
  if (!spec) {
    return null;
  }
  const body = nonEmptyPreservingWhitespace(params[spec.key] ?? params.text ?? params.summary);
  if (!body) {
    return null;
  }
  const turnID = resolveIdentity("turnID", [
    { value: params.turnId },
    { value: params.turnID },
  ]);
  const itemID = resolveIdentity("itemID", [
    { value: params.itemId },
    { value: params.itemID },
  ]);
  if (turnID.error || itemID.error) {
    return diagnosticEvent({
      sourceHostID,
      threadID,
      rawKind: message?.method || "delta",
      turnID: turnID.value,
      itemID: itemID.value,
      errorCode: turnID.error || itemID.error,
      activityAtMs: nowMs,
    });
  }
  const sourceRef = sourceRefForItem({
    sourceHostID,
    threadID,
    turnID: turnID.value,
    itemID: itemID.value,
  });
  return makeProjectionRow({
    sourceHostID,
    threadID,
    projectionID: projectionIDForItem({
      sourceHostID,
      threadID,
      turnID: turnID.value,
      itemID: itemID.value,
      rowRole: spec.rowRole,
    }),
    sourceRef,
    itemType: message?.method,
    rowRole: spec.rowRole,
    visibility: spec.visibility,
    renderKind: spec.renderKind,
    title: spec.title,
    body,
    eventTimeMs: nowMs,
    activityAtMs: nowMs,
    turnID: turnID.value,
    itemID: itemID.value,
    renderState: "streaming",
  });
}

function threadIDFromParams(params) {
  return nonEmptyString(params?.threadId) || nonEmptyString(params?.threadID) || null;
}

function eventsFromNotification(message, {
  sourceHostID,
  threadID,
  nowMs = Date.now(),
} = {}) {
  const params = message?.params || {};
  const resolvedThreadID = threadID || threadIDFromParams(params);
  if (!resolvedThreadID) {
    return [];
  }

  const delta = deltaEventFromNotification(message, {
    sourceHostID,
    threadID: resolvedThreadID,
    nowMs,
  });
  if (delta) {
    return [delta];
  }

  switch (message?.method) {
    case "item/started":
    case "item/completed":
      if (!params.item) {
        return [diagnosticEvent({
          sourceHostID,
          threadID: resolvedThreadID,
          rawKind: message.method,
          errorCode: "item_missing",
          activityAtMs: nowMs,
        })];
      }
      return eventsFromItem(params.item, {
        sourceHostID,
        threadID: resolvedThreadID,
        liveParams: params,
        defaultMs: lifecycleActivityMs(message.method, params, nowMs),
        renderState: message.method === "item/completed" ? "settled" : "live",
      });
    case "thread/status/changed":
    {
      const status = params.status?.type || "updated";
      const systemKind = "threadStatusChanged";
      const sourceRef = sourceRefForSystem({ sourceHostID, threadID: resolvedThreadID, systemKind });
      return [makeProjectionRow({
        sourceHostID,
        threadID: resolvedThreadID,
        projectionID: projectionIDForSystem({ sourceHostID, threadID: resolvedThreadID, systemKind }),
        sourceRef,
        itemType: message.method,
        rowRole: "system",
        visibility: "system",
        renderKind: "system",
        title: "Thread status",
        body: status,
        eventTimeMs: nowMs,
        activityAtMs: nowMs,
        renderState: "live",
      })];
    }
    case "thread/closed":
    {
      const systemKind = "threadClosed";
      const sourceRef = sourceRefForSystem({ sourceHostID, threadID: resolvedThreadID, systemKind });
      return [makeProjectionRow({
        sourceHostID,
        threadID: resolvedThreadID,
        projectionID: projectionIDForSystem({ sourceHostID, threadID: resolvedThreadID, systemKind }),
        sourceRef,
        itemType: message.method,
        rowRole: "system",
        visibility: "system",
        renderKind: "system",
        title: "Thread closed",
        body: "The app-server closed this thread.",
        eventTimeMs: nowMs,
        activityAtMs: nowMs,
        renderState: "live",
      })];
    }
    default:
      return [];
  }
}

function requestTitle(method) {
  switch (method) {
    case "item/commandExecution/requestApproval":
      return "Command approval";
    case "item/fileChange/requestApproval":
      return "File change approval";
    case "item/tool/requestUserInput":
      return "Input requested";
    case "item/permissions/requestApproval":
      return "Permission approval";
    default:
      return "Needs desktop";
  }
}

function requestBody(method, params = {}) {
  return firstNonEmpty(
    commandText(params.command),
    params.reason,
    params.message,
    method,
  ) || method;
}

function itemBackedRequestProjection(method) {
  switch (method) {
    case "item/commandExecution/requestApproval":
      return {
        rowRole: "command",
        visibility: "request",
        renderKind: "command",
      };
    case "item/fileChange/requestApproval":
      return {
        rowRole: "fileChange",
        visibility: "request",
        renderKind: "request",
      };
    default:
      return null;
  }
}

function eventFromRequest(message, nowMs = Date.now(), {
  sourceHostID,
  threadID: fallbackThreadID = null,
} = {}) {
  const params = message?.params || {};
  const threadID = threadIDFromParams(params) || fallbackThreadID;
  if (!threadID || message?.id === undefined || !message?.method) {
    return null;
  }
  const requestID = String(message.id);
  const turnID = resolveIdentity("turnID", [
    { value: params.turnId },
    { value: params.turnID },
  ]);
  const itemID = resolveIdentity("itemID", [
    { value: params.itemId },
    { value: params.itemID },
  ]);
  const requestedAtMs = timestampMs(params.startedAtMs, { unit: "milliseconds" }) ?? nowMs;
  if (turnID.error === "turnID_conflict" || itemID.error === "itemID_conflict") {
    return diagnosticEvent({
      sourceHostID,
      threadID,
      rawKind: message.method,
      turnID: turnID.value,
      itemID: itemID.value,
      requestID,
      errorCode: turnID.error || itemID.error,
      activityAtMs: requestedAtMs,
    });
  }
  const itemBackedProjection = itemBackedRequestProjection(message.method);
  const hasStableItemIdentity = Boolean(itemBackedProjection && turnID.value && itemID.value && !turnID.error && !itemID.error);
  const projectionID = hasStableItemIdentity
    ? projectionIDForItem({
        sourceHostID,
        threadID,
        turnID: turnID.value,
        itemID: itemID.value,
        rowRole: itemBackedProjection.rowRole,
      })
    : projectionIDForRequest({
        sourceHostID,
        threadID,
        turnID: turnID.value,
        itemID: itemID.value,
        requestID,
      });
  const sourceRef = hasStableItemIdentity
    ? sourceRefForItem({
        sourceHostID,
        threadID,
        turnID: turnID.value,
        itemID: itemID.value,
      })
    : sourceRefForRequest({
        sourceHostID,
        threadID,
        turnID: turnID.value,
        itemID: itemID.value,
        requestID,
      });
  const rowRole = hasStableItemIdentity ? itemBackedProjection.rowRole : "request";
  const visibility = hasStableItemIdentity ? itemBackedProjection.visibility : "request";
  const renderKind = hasStableItemIdentity ? itemBackedProjection.renderKind : "request";
  return makeProjectionRow({
    sourceHostID,
    threadID,
    projectionID,
    sourceRef,
    itemType: message.method,
    rowRole,
    visibility,
    renderKind,
    title: requestTitle(message.method),
    body: requestBody(message.method, params),
    eventTimeMs: requestedAtMs,
    activityAtMs: requestedAtMs,
    turnID: turnID.value,
    itemID: itemID.value,
    renderState: "live",
    requestID,
    request: {
      requestID: message.id,
      method: message.method,
      params: message.params || null,
      status: "pending",
    },
  });
}

function makeSnapshot({
  sourceHostID,
  threadID,
  epoch,
  seq,
  generation = 1,
  rows,
  activeTurnID = null,
  source = "thread/detail",
}) {
  return {
    schemaVersion: THREAD_DETAIL_SCHEMA_VERSION,
    identityVersion: THREAD_DETAIL_IDENTITY_VERSION,
    projectionEngineVersion: THREAD_DETAIL_PROJECTION_ENGINE_VERSION,
    sourceHostID,
    view: THREAD_DETAIL_VIEW,
    threadID,
    epoch,
    seq,
    generation,
    snapshotID: `${epoch}:${seq}`,
    scope: "thread",
    viewParamsKey: THREAD_DETAIL_DEFAULT_VIEW_PARAMS_KEY,
    complete: true,
    order: THREAD_DETAIL_ORDER,
    freshness: freshness(source),
    activeTurnID,
    rows: [...rows].sort((left, right) => String(left.displayOrderKey).localeCompare(String(right.displayOrderKey))),
  };
}

export {
  THREAD_DETAIL_DEFAULT_VIEW_PARAMS_KEY,
  THREAD_DETAIL_IDENTITY_VERSION,
  THREAD_DETAIL_ORDER,
  THREAD_DETAIL_PROJECTION_ENGINE_VERSION,
  THREAD_DETAIL_SCHEMA_VERSION,
  THREAD_DETAIL_UPDATE_METHOD,
  THREAD_DETAIL_VIEW,
  activeTurnIDFromThread,
  eventFromRequest,
  eventsFromNotification,
  eventsFromThread,
  freshness,
  makeSnapshot,
  nonEmptyString,
  rowBody,
  rowPayload,
  rowRenderKind,
  rowRenderState,
  rowRequest,
  rowRequestID,
};

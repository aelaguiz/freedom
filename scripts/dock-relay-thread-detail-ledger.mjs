import crypto from "node:crypto";

import {
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
} from "./dock-relay-thread-detail-projection-adapter.mjs";

class ThreadDetailLedger {
  constructor({ sourceHostID, threadID, epoch = crypto.randomUUID(), seq = 0 } = {}) {
    if (!nonEmptyString(sourceHostID)) {
      throw new Error("ThreadDetailLedger requires sourceHostID");
    }
    this.sourceHostID = nonEmptyString(sourceHostID);
    this.threadID = threadID || null;
    this.epoch = epoch;
    this.seq = seq;
    this.generation = 1;
    this.rowsByProjectionID = new Map();
    this.requestProjectionIDByRequestID = new Map();
    this.activeTurnID = null;
  }

  replaceFromThread(thread, source = "thread/detail/read") {
    const threadID = thread?.id || this.threadID;
    this.threadID = threadID;
    this.rowsByProjectionID = new Map();
    this.requestProjectionIDByRequestID = new Map();
    this.activeTurnID = activeTurnIDFromThread(thread);
    for (const row of eventsFromThread(thread, {
      sourceHostID: this.sourceHostID,
      threadID,
    })) {
      this.upsertRow(row);
    }
    this.seq += 1;
    return this.snapshot(source);
  }

  snapshot(source = "thread/detail") {
    return makeSnapshot({
      sourceHostID: this.sourceHostID,
      threadID: this.threadID,
      epoch: this.epoch,
      seq: this.seq,
      generation: this.generation,
      rows: this.rowsByProjectionID.values(),
      activeTurnID: this.activeTurnID,
      source,
    });
  }

  applyNotification(message, { nowMs = Date.now() } = {}) {
    if (message?.method === "turn/started") {
      const turnID = message?.params?.turn?.id || message?.params?.turnId || message?.params?.turnID || null;
      if (turnID) {
        this.activeTurnID = turnID;
      }
    }
    if (message?.method === "turn/completed") {
      const turnID = message?.params?.turn?.id || message?.params?.turnId || message?.params?.turnID || null;
      if (turnID && turnID === this.activeTurnID) {
        this.activeTurnID = null;
      }
    }
    if (message?.method === "serverRequest/resolved") {
      const requestID = String(message?.params?.requestId ?? "");
      const projectionID = this.requestProjectionIDByRequestID.get(requestID);
      if (!projectionID) {
        return null;
      }
      const existing = this.rowsByProjectionID.get(projectionID);
      if (!rowRequest(existing)) {
        return null;
      }
      const row = this.upsertRow({
        ...existing,
        payload: {
          ...rowPayload(existing),
          request: {
            ...rowRequest(existing),
            status: "resolved",
          },
          renderState: "settled",
        },
      });
      this.seq += 1;
      return this.update({
        kind: "upsert",
        rows: [row],
      });
    }

    const rows = eventsFromNotification(message, {
      sourceHostID: this.sourceHostID,
      threadID: this.threadID,
      nowMs,
    });
    if (rows.length === 0) {
      return null;
    }
    const upsertedRows = rows.map((row) => this.upsertRow(row));
    this.seq += 1;
    return this.update({
      kind: "upsert",
      rows: upsertedRows,
      liveState: message?.method === "thread/closed" ? "closed" : undefined,
    });
  }

  applyRequest(message, { nowMs = Date.now() } = {}) {
    const row = eventFromRequest(message, nowMs, {
      sourceHostID: this.sourceHostID,
      threadID: this.threadID,
    });
    if (!row || row.threadID !== this.threadID) {
      return null;
    }
    const upserted = this.upsertRow(row);
    const requestID = rowRequestID(row);
    if (requestID !== null && requestID !== undefined) {
      this.requestProjectionIDByRequestID.set(String(requestID), row.projectionID);
    }
    this.seq += 1;
    return this.update({ kind: "upsert", rows: [upserted] });
  }

  upsertRow(row) {
    const existing = this.rowsByProjectionID.get(row.projectionID);
    let next = {
      ...row,
      revision: (existing?.revision || 0) + 1,
    };
    const existingRequest = rowRequest(existing);
    if (existingRequest && !rowRequest(next)) {
      const keepRequestVisible = existingRequest.status !== "resolved";
      next = {
        ...next,
        payload: {
          ...rowPayload(next),
          requestID: rowRequestID(existing),
          request: existingRequest,
          visibility: keepRequestVisible ? "request" : rowPayload(next).visibility,
          renderState: keepRequestVisible ? "live" : rowPayload(next).renderState,
        },
      };
    }
    if (rowRenderState(existing) === "streaming"
      && rowRenderState(row) === "streaming"
      && rowRenderKind(existing) === rowRenderKind(row)) {
      next = {
        ...next,
        payload: {
          ...rowPayload(next),
          body: `${rowBody(existing) || ""}${rowBody(row) || ""}`,
        },
      };
    }
    this.rowsByProjectionID.set(next.projectionID, next);
    const requestID = rowRequestID(next);
    if (requestID !== null && requestID !== undefined) {
      this.requestProjectionIDByRequestID.set(String(requestID), next.projectionID);
    }
    return next;
  }

  update({
    kind,
    rows = [],
    projectionIDs = [],
    snapshot = null,
    reason = null,
    liveState = undefined,
  } = {}) {
    return {
      kind,
      schemaVersion: THREAD_DETAIL_SCHEMA_VERSION,
      identityVersion: THREAD_DETAIL_IDENTITY_VERSION,
      projectionEngineVersion: THREAD_DETAIL_PROJECTION_ENGINE_VERSION,
      sourceHostID: this.sourceHostID,
      view: THREAD_DETAIL_VIEW,
      threadID: this.threadID,
      epoch: this.epoch,
      seq: this.seq,
      generation: this.generation,
      viewParamsKey: THREAD_DETAIL_DEFAULT_VIEW_PARAMS_KEY,
      order: THREAD_DETAIL_ORDER,
      activeTurnID: this.activeTurnID,
      freshness: freshness(kind),
      rows: [...rows].sort((left, right) => String(left.displayOrderKey).localeCompare(String(right.displayOrderKey))),
      projectionIDs,
      snapshot,
      reason,
      ...(liveState ? { liveState } : {}),
    };
  }
}

function createThreadDetailLedgerFromThread(thread, {
  sourceHostID,
  threadID = thread?.id,
} = {}) {
  const ledger = new ThreadDetailLedger({ sourceHostID, threadID });
  ledger.replaceFromThread({ ...thread, id: threadID });
  return ledger;
}

export {
  THREAD_DETAIL_DEFAULT_VIEW_PARAMS_KEY,
  THREAD_DETAIL_IDENTITY_VERSION,
  THREAD_DETAIL_ORDER,
  THREAD_DETAIL_PROJECTION_ENGINE_VERSION,
  THREAD_DETAIL_SCHEMA_VERSION,
  THREAD_DETAIL_UPDATE_METHOD,
  THREAD_DETAIL_VIEW,
  ThreadDetailLedger,
  createThreadDetailLedgerFromThread,
  eventFromRequest,
  eventsFromNotification,
  eventsFromThread,
};

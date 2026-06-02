import crypto from "node:crypto";

import {
  RELAY_STATE_DOCK_WINDOW_SIZE,
  RELAY_STATE_HEARTBEAT_INTERVAL_MS,
  RELAY_STATE_SNAPSHOT_SOFT_LIMIT_BYTES,
  RELAY_STATE_STREAM_SCHEMA_VERSION,
  RELAY_STATE_UPDATE_SOFT_LIMIT_BYTES,
} from "./dock-relay-constants.mjs";
import {
  buildWindow,
  estimateJSONBytes,
} from "./dock-relay-state-views.mjs";

const DOCK_SUBSCRIBE_METHOD = "dock/subscribe";
const DOCK_RESYNC_METHOD = "dock/resync";
const DOCK_UPDATE_METHOD = "dock/update";
const ARCHIVE_SUBSCRIBE_METHOD = "archive/subscribe";
const ARCHIVE_RESYNC_METHOD = "archive/resync";
const ARCHIVE_UPDATE_METHOD = "archive/update";

function currentSeqForView(store, view) {
  return typeof store.currentSeqForView === "function"
    ? store.currentSeqForView(view)
    : store.currentSeq();
}

function sequenceFields(store, hub, view) {
  const seq = currentSeqForView(store, view);
  return {
    schemaVersion: RELAY_STATE_STREAM_SCHEMA_VERSION,
    identityVersion: 1,
    projectionEngineVersion: 1,
    epoch: hub.epoch,
    seq,
  };
}

function cardDeltaClearlyTooLarge(delta) {
  const changedRows = Number(delta.rows?.length || 0)
    + Number(delta.projectionIDs?.length || 0);
  return changedRows > RELAY_STATE_DOCK_WINDOW_SIZE;
}

class StateSubscriptionHub {
  constructor({
    store,
    snapshotForView,
    heartbeatForView = null,
    logger = null,
    heartbeatIntervalMs = RELAY_STATE_HEARTBEAT_INTERVAL_MS,
    snapshotSoftLimitBytes = RELAY_STATE_SNAPSHOT_SOFT_LIMIT_BYTES,
    updateSoftLimitBytes = RELAY_STATE_UPDATE_SOFT_LIMIT_BYTES,
  }) {
    this.store = store;
    this.snapshotForView = snapshotForView;
    this.heartbeatForView = heartbeatForView;
    this.logger = logger;
    this.heartbeatIntervalMs = heartbeatIntervalMs;
    this.snapshotSoftLimitBytes = snapshotSoftLimitBytes;
    this.updateSoftLimitBytes = updateSoftLimitBytes;
    this.subscribers = new Set();
    this.epoch = crypto.randomUUID();
    this.heartbeatTimer = null;
  }

  subscribe(view, listener) {
    const subscriber = {
      id: crypto.randomUUID(),
      view,
      listener,
    };
    this.subscribers.add(subscriber);
    this.ensureHeartbeatTimer();
    return () => {
      this.subscribers.delete(subscriber);
      this.stopHeartbeatTimerIfIdle();
    };
  }

  async snapshot(viewName, options = {}) {
    return this.snapshotForView(viewName, {
      ...options,
      epoch: this.epoch,
      softLimitBytes: this.snapshotSoftLimitBytes,
    });
  }

  cardDelta({
    view,
    seq,
    sourceHostID,
    freshness,
    rows = [],
    projectionIDs = [],
    totalRows,
    complete = undefined,
    window = undefined,
  }) {
    const resolvedSourceHostID = sourceHostID || "unknown";
    const kind = rows.length > 0 ? "upsert" : (projectionIDs.length > 0 ? "delete" : "heartbeat");
    const effectiveWindow = window || (
      complete !== undefined && Number.isFinite(Number(totalRows))
        ? buildWindow({
            offset: 0,
            limit: totalRows,
            rowCount: totalRows,
            totalRows,
          })
        : undefined
    );
    return {
      kind,
      ...sequenceFields(this.store, this, view),
      seq,
      sourceHostID: resolvedSourceHostID,
      view,
      scope: "view",
      viewParamsKey: `${view}:${resolvedSourceHostID}`,
      order: "displayOrderKeyAscending",
      complete,
      totalRows,
      window: effectiveWindow,
      freshness,
      rows,
      projectionIDs,
    };
  }

  async publishDelta(delta) {
    const payloadBytes = cardDeltaClearlyTooLarge(delta)
      ? Number.POSITIVE_INFINITY
      : estimateJSONBytes(delta);
    const update = payloadBytes > this.updateSoftLimitBytes
      ? await this.snapshot(delta.view)
      : delta;
    for (const subscriber of this.subscribers) {
      if (subscriber.view !== update.view) {
        continue;
      }
      try {
        subscriber.listener(update);
      } catch (error) {
        this.logger?.warn?.("state.subscriber_failed", { error });
      }
    }
  }

  ensureHeartbeatTimer() {
    if (this.heartbeatTimer || this.heartbeatIntervalMs <= 0) {
      return;
    }
    this.heartbeatTimer = setInterval(() => {
      this.publishHeartbeats();
    }, this.heartbeatIntervalMs);
    this.heartbeatTimer.unref?.();
  }

  stopHeartbeatTimerIfIdle() {
    if (this.subscribers.size > 0 || !this.heartbeatTimer) {
      return;
    }
    clearInterval(this.heartbeatTimer);
    this.heartbeatTimer = null;
  }

  publishHeartbeats() {
    if (this.subscribers.size === 0) {
      this.stopHeartbeatTimerIfIdle();
      return;
    }
    const views = new Set([...this.subscribers].map((subscriber) => subscriber.view));
    for (const view of views) {
      const heartbeat = this.heartbeat(view);
      for (const subscriber of this.subscribers) {
        if (subscriber.view !== view) {
          continue;
        }
        try {
          subscriber.listener(heartbeat);
        } catch (error) {
          this.logger?.warn?.("state.subscriber_failed", { error });
        }
      }
    }
  }

  heartbeat(view) {
    if (this.heartbeatForView) {
      return this.heartbeatForView(view, { epoch: this.epoch });
    }
    return {
      kind: "heartbeat",
      ...sequenceFields(this.store, this, view),
      sourceHostID: "unknown",
      view,
      scope: "view",
      viewParamsKey: `${view}:unknown`,
      order: "displayOrderKeyAscending",
      freshness: { status: "unknown" },
    };
  }
}

export {
  ARCHIVE_RESYNC_METHOD,
  ARCHIVE_SUBSCRIBE_METHOD,
  ARCHIVE_UPDATE_METHOD,
  DOCK_RESYNC_METHOD,
  DOCK_SUBSCRIBE_METHOD,
  DOCK_UPDATE_METHOD,
  StateSubscriptionHub,
};

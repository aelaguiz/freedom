import crypto from "node:crypto";

import {
  RELAY_STATE_DOCK_WINDOW_SIZE,
  RELAY_STATE_HEARTBEAT_INTERVAL_MS,
  RELAY_STATE_SNAPSHOT_SOFT_LIMIT_BYTES,
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
    schemaVersion: 2,
    epoch: hub.epoch,
    seq,
    stateGeneration: seq,
  };
}

function cardDeltaClearlyTooLarge(delta) {
  const changedRows = Number(delta.upsertCards?.length || 0)
    + Number(delta.deleteCardIDs?.length || 0)
    + Number(delta.upsertHosts?.length || 0);
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
    baseSeq,
    seq,
    freshness,
    upsertHosts = undefined,
    upsertCards = [],
    deleteCardIDs = [],
    totalRows,
    complete = undefined,
    window = undefined,
  }) {
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
      kind: "delta",
      ...sequenceFields(this.store, this, view),
      baseSeq,
      seq,
      stateGeneration: seq,
      view,
      complete,
      totalRows,
      window: effectiveWindow,
      freshness,
      upsertHosts,
      upsertCards,
      deleteCardIDs,
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
      baseSeq: null,
      view,
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

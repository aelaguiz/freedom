import crypto from "node:crypto";

import {
  RELAY_STATE_DOCK_WINDOW_SIZE,
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

function sequenceFields(store, view) {
  return {
    schemaVersion: 2,
    epoch: view.epoch,
    seq: store.currentSeq(),
    stateGeneration: store.currentSeq(),
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
    logger = null,
    snapshotSoftLimitBytes = RELAY_STATE_SNAPSHOT_SOFT_LIMIT_BYTES,
    updateSoftLimitBytes = RELAY_STATE_UPDATE_SOFT_LIMIT_BYTES,
  }) {
    this.store = store;
    this.snapshotForView = snapshotForView;
    this.logger = logger;
    this.snapshotSoftLimitBytes = snapshotSoftLimitBytes;
    this.updateSoftLimitBytes = updateSoftLimitBytes;
    this.subscribers = new Set();
    this.epoch = crypto.randomUUID();
  }

  subscribe(view, listener) {
    const subscriber = {
      id: crypto.randomUUID(),
      view,
      listener,
    };
    this.subscribers.add(subscriber);
    return () => {
      this.subscribers.delete(subscriber);
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
      ...sequenceFields(this.store, this),
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

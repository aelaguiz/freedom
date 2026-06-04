class NotificationIngestor {
  constructor({
    store,
    hostId,
    scheduleReconciliation,
    logger = null,
  }) {
    this.store = store;
    this.hostId = hostId;
    this.scheduleReconciliation = scheduleReconciliation;
    this.logger = logger;
  }

  ingestArchiveMutation({ threadId, archived }) {
    if (!threadId) {
      return null;
    }
    // Archive commands are inputs to the canonical projection. They must not
    // write card order or freshness directly because that recreates a second
    // card-truth path beside dock/* and archive/* streams.
    return {
      threadId,
      archived,
      reason: archived ? "thread/archive" : "thread/unarchive",
    };
  }

  ingestThreadNameUpdated(message) {
    if (message?.method !== "thread/name/updated") {
      return null;
    }
    const threadId = message?.params?.threadId;
    if (typeof threadId !== "string" || threadId.trim().length === 0) {
      return null;
    }
    return {
      threadId,
      reason: "thread/name/updated",
    };
  }

  ingestThreadStatusChanged(message) {
    if (message?.method !== "thread/status/changed") {
      return null;
    }
    const threadId = message?.params?.threadId || message?.params?.threadID;
    if (typeof threadId !== "string" || threadId.trim().length === 0) {
      return null;
    }
    return {
      threadId,
      reason: "thread/status/changed",
    };
  }

  markScopeStale(scopeName, error) {
    this.store.markScopeStale(this.hostId, scopeName, error);
    this.scheduleReconciliation?.({
      reason: "scope-stale",
      immediate: false,
    });
  }

  ingestLiveDisconnect(error = null) {
    this.logger?.warn?.("state.live_disconnect_marked_stale", { error });
    this.markScopeStale("live-leases", error || new Error("live endpoint disconnected"));
  }
}

export {
  NotificationIngestor,
};

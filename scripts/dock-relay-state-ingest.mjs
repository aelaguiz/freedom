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
    const result = this.store.applyArchiveMutation({
      hostID: this.hostId,
      threadID: threadId,
      archived,
    });
    this.scheduleReconciliation?.({
      reason: archived ? "thread/archive" : "thread/unarchive",
      immediate: false,
    });
    return result;
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

import {
  RELAY_STATE_DOCK_WINDOW_SIZE,
  RELAY_STATE_RECONCILE_DEBOUNCE_MS,
  RELAY_STATE_RECONCILE_INTERVAL_MS,
  RELAY_STATE_SNAPSHOT_SOFT_LIMIT_BYTES,
  RELAY_STATE_UPDATE_SOFT_LIMIT_BYTES,
  THREAD_LIST_MAX_LIMIT,
} from "./dock-relay-constants.mjs";
import { NotificationIngestor } from "./dock-relay-state-ingest.mjs";
import { relayStateStoreForConfig } from "./dock-relay-state-store.mjs";
import { StateSubscriptionHub } from "./dock-relay-state-subscriptions.mjs";
import {
  DOCK_VIEW,
  ARCHIVE_VIEW,
  buildWindow,
  dockOrderKey,
  estimateJSONBytes,
  normalizeThread,
  normalizedStatus,
  orderedDockRows,
  publicHostFromConfig,
} from "./dock-relay-state-views.mjs";
import {
  drainThreadListScope,
} from "./dock-relay-state-snapshot.mjs";
import { isHumanStartedThread } from "./dock-relay-human-thread-filter.mjs";
import {
  aggregateThreadList,
  collectLiveRows,
  configuredLiveEndpointsForConfig,
  enrichHumanStartedRows,
  mergeHumanStartedRowsWithSupplements,
  readSessionIndexHumanStartedSupplements,
} from "./dock-relay-thread-data.mjs";

function nowISOString() {
  return new Date().toISOString();
}

function sleep(ms) {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

const ACTIVE_DEFAULT_SCOPE = {
  name: "interactiveDefault",
  sourceKinds: null,
  meaning: "app-server default interactive source scope",
};

const ACTIVE_ARCHIVE_SCOPE = {
  name: "active",
  archived: false,
};

function appFacingHumanStartedVisibility() {
  return {
    mode: "app_facing_human_started_threads_only",
    includeRejectedThreads: false,
    rejectedThreadsRequireDiagnosticSnapshotOptIn: true,
  };
}

function liveLeaseFromRow(row, endpoint, maxAgeMs) {
  const threadID = row?.id;
  if (!threadID) {
    return null;
  }
  const status = normalizedStatus(row);
  const validationAtMs = Date.now();
  return {
    threadID,
    endpointLabel: endpoint?.label || endpoint?.url || null,
    endpointUrl: endpoint?.url || null,
    backendSessionID: row?.sessionId || threadID,
    status,
    waitingState: status === "needsApproval" || status === "needsInput" ? status : null,
    commandCapability: false,
    validationAtMs,
    expiresAtMs: validationAtMs + maxAgeMs,
  };
}

class StateReconciler {
  constructor({
    engine,
    intervalMs = RELAY_STATE_RECONCILE_INTERVAL_MS,
    debounceMs = RELAY_STATE_RECONCILE_DEBOUNCE_MS,
  }) {
    this.engine = engine;
    this.intervalMs = intervalMs;
    this.debounceMs = debounceMs;
    this.timer = null;
    this.debounceTimer = null;
    this.inFlight = null;
  }

  start() {
    if (this.timer) {
      return;
    }
    this.schedule({ reason: "boot", immediate: false });
    this.timer = setInterval(() => {
      this.schedule({ reason: "periodic", immediate: false });
    }, this.intervalMs);
    this.timer.unref?.();
  }

  async stop() {
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }
    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer);
      this.debounceTimer = null;
    }
    if (this.inFlight) {
      await this.inFlight.catch(() => null);
    }
  }

  schedule({ reason, immediate = false } = {}) {
    if (immediate) {
      if (this.debounceTimer) {
        clearTimeout(this.debounceTimer);
        this.debounceTimer = null;
      }
      return this.run(reason || "manual");
    }
    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer);
    }
    this.debounceTimer = setTimeout(() => {
      this.debounceTimer = null;
      this.run(reason || "debounced").catch((error) => {
        this.engine.logger?.warn?.("state.reconcile_failed", { reason, error });
      });
    }, this.debounceMs);
    this.debounceTimer.unref?.();
    return Promise.resolve(null);
  }

  async run(reason = "manual") {
    if (this.inFlight) {
      return this.inFlight;
    }
    this.inFlight = this.engine.reconcileDock({ reason }).finally(() => {
      this.inFlight = null;
    });
    return this.inFlight;
  }
}

class RelayStateEngine {
  constructor(config, options = {}) {
    this.config = config;
    this.logger = config.logger;
    this.store = options.store || relayStateStoreForConfig(config);
    this.reconciler = new StateReconciler({
      engine: this,
      intervalMs: config.relayStateReconcileIntervalMs || RELAY_STATE_RECONCILE_INTERVAL_MS,
      debounceMs: config.relayStateReconcileDebounceMs || RELAY_STATE_RECONCILE_DEBOUNCE_MS,
    });
    this.subscriptions = new StateSubscriptionHub({
      store: this.store,
      snapshotForView: (view, params) => this.snapshotForView(view, params),
      logger: this.logger,
      snapshotSoftLimitBytes: config.relayStateSnapshotSoftLimitBytes
        || RELAY_STATE_SNAPSHOT_SOFT_LIMIT_BYTES,
    });
    this.ingestor = new NotificationIngestor({
      store: this.store,
      hostId: config.hostId,
      scheduleReconciliation: (request) => this.scheduleReconciliation(request),
      logger: this.logger,
    });
    this.liveLeaseExpiryTimer = null;
    this.started = false;
  }

  start() {
    if (this.started) {
      return;
    }
    this.started = true;
    this.reconciler.start();
  }

  async close() {
    if (this.liveLeaseExpiryTimer) {
      clearTimeout(this.liveLeaseExpiryTimer);
      this.liveLeaseExpiryTimer = null;
    }
    await this.reconciler.stop();
    this.store.close();
  }

  scheduleReconciliation(request = {}) {
    return this.reconciler.schedule(request);
  }

  scheduleLiveLeaseExpiryReconciliation(hostID) {
    if (this.liveLeaseExpiryTimer) {
      clearTimeout(this.liveLeaseExpiryTimer);
      this.liveLeaseExpiryTimer = null;
    }
    const expiresAtMs = this.store.nextUnpublishedLiveLeaseExpiryMs(hostID);
    if (!expiresAtMs) {
      return;
    }
    const delayMs = Math.max(0, expiresAtMs - Date.now() + 1);
    this.liveLeaseExpiryTimer = setTimeout(() => {
      this.liveLeaseExpiryTimer = null;
      this.reconciler.schedule({ reason: "live-lease-expiry", immediate: true }).catch((error) => {
        this.logger?.warn?.("state.reconcile_failed", {
          reason: "live-lease-expiry",
          error,
        });
      });
    }, delayMs);
    this.liveLeaseExpiryTimer.unref?.();
  }

  shouldReconcileAfterResponse() {
    const host = publicHostFromConfig(this.config);
    const counts = this.store.stateCounts();
    const freshness = this.store.freshnessForHost(host.id);
    const totalRows = this.store.listDockCards({ hostID: host.id, offset: 0, limit: 0 }).totalRows;
    return Number(totalRows || 0) === 0
      || Number(counts.incomplete || 0) > 0
      || freshness.status !== "fresh";
  }

  scheduleReconciliationAfterResponse(reason, { force = false } = {}) {
    if (!force && !this.shouldReconcileAfterResponse()) {
      this.logger?.debug?.("state.reconcile_skipped", {
        reason,
        freshness: "fresh",
      });
      return;
    }
    const timer = setImmediate(() => {
      this.reconciler.schedule({ reason, immediate: true }).catch((error) => {
        this.logger?.warn?.("state.reconcile_failed", { reason, error });
      });
    });
    timer.unref?.();
  }

  async reconcileDock({ reason = "manual" } = {}) {
    const host = publicHostFromConfig(this.config);
    try {
      const baseParams = {
        archived: false,
        limit: THREAD_LIST_MAX_LIMIT,
        sortKey: "updated_at",
        sortDirection: "desc",
        modelProviders: [],
      };
      const previousDockCards = this.store.listDockCards({ hostID: host.id }).cards;
      const [liveRows, defaultScope] = await Promise.all([
        this.refreshLiveLeases(),
        drainThreadListScope(this.config, baseParams, ACTIVE_ARCHIVE_SCOPE, ACTIVE_DEFAULT_SCOPE),
      ]);
      const interactiveRows = defaultScope.rows.map((row) => row.thread).filter(Boolean);
      const { acceptedRows, rejectedCounts, validationFailures } = await enrichHumanStartedRows(
        this.config,
        interactiveRows,
        { route: "dock_reconcile" },
      );
      const supplements = await readSessionIndexHumanStartedSupplements(this.config, acceptedRows, {
        route: "dock_reconcile",
        params: baseParams,
        limit: baseParams.limit,
      });
      for (const [rejectedReason, count] of Object.entries(supplements.rejectedCounts)) {
        rejectedCounts[rejectedReason] = Number(rejectedCounts[rejectedReason] || 0) + Number(count || 0);
      }
      const appRows = mergeHumanStartedRowsWithSupplements(acceptedRows, supplements.acceptedRows);
      const orderedRows = orderedDockRows([], appRows, liveRows);
      const cards = orderedRows
        .map(({ row, lane }, index) => normalizeThread(row, host, lane, {
          archiveState: "active",
          orderKey: dockOrderKey(index, row?.id || ""),
        }))
        .filter(Boolean);
      const totalValidationFailures = validationFailures + supplements.validationFailures;
      const complete = defaultScope.complete && totalValidationFailures === 0;
      const reconciliationScope = complete
        ? defaultScope
        : {
          ...defaultScope,
          complete: false,
          error: defaultScope.error || "human-started thread validation failed",
        };
      const cleanup = this.store.deleteRejectedThreadCards(host.id);
      const leaseCleanup = this.store.deleteRejectedLiveLeases(host.id);
      const result = this.store.applyDockReconciliation({
        host,
        cards,
        scopes: [reconciliationScope],
        complete,
        error: reconciliationScope.error || null,
        previousCards: previousDockCards,
      });
      const freshness = this.store.freshnessForHost(host.id);
      const totalRows = this.store.listDockCards({ hostID: host.id }).totalRows;
      const deltaCarriesEveryRow = complete
        && Number(result.deleteCardIDs?.length || 0) === 0
        && Number(result.upsertCards?.length || 0) === Number(totalRows || 0);
      await this.subscriptions.publishDelta(this.subscriptions.cardDelta({
        view: DOCK_VIEW,
        baseSeq: Math.max(0, Number(result.seq) - 1),
        seq: result.seq,
        freshness,
        upsertHosts: [host],
        upsertCards: result.upsertCards,
        deleteCardIDs: result.deleteCardIDs,
        totalRows,
        complete: deltaCarriesEveryRow ? true : undefined,
      }));
      if (complete) {
        this.logger?.info?.("state.reconcile_succeeded", {
          reason,
          hostId: host.id,
          rows: cards.length,
          rejectedCounts,
          validationFailures: totalValidationFailures,
          supplementedRows: supplements.acceptedRows.length,
          deletedRejectedCards: cleanup.deleted,
          deletedRejectedLiveLeases: leaseCleanup.deleted,
          seq: result.seq,
        });
      } else {
        this.logger?.warn?.("state.reconcile_incomplete", {
          reason,
          hostId: host.id,
          rows: cards.length,
          seq: result.seq,
          rejectedCounts,
          validationFailures: totalValidationFailures,
          supplementedRows: supplements.acceptedRows.length,
          deletedRejectedCards: cleanup.deleted,
          deletedRejectedLiveLeases: leaseCleanup.deleted,
          error: reconciliationScope.error || null,
        });
      }
      this.scheduleLiveLeaseExpiryReconciliation(host.id);
      return result;
    } catch (error) {
      this.store.upsertHost(host);
      this.store.markScopeStale(host.id, "active:interactiveDefault", error);
      const seq = this.store.currentSeq();
      const totalRows = this.store.listDockCards({ hostID: host.id }).totalRows;
      await this.subscriptions.publishDelta(this.subscriptions.cardDelta({
        view: DOCK_VIEW,
        baseSeq: Math.max(0, seq - 1),
        seq,
        freshness: this.store.freshnessForHost(host.id),
        totalRows,
        complete: false,
      }));
      this.logger?.warn?.("state.reconcile_failed", {
        reason,
        hostId: host.id,
        error,
      });
      this.scheduleLiveLeaseExpiryReconciliation(host.id);
      return { seq, upsertCards: [], deleteCardIDs: [], error };
    }
  }

  async reconcileArchive({ reason = "manual" } = {}) {
    const host = publicHostFromConfig(this.config);
    try {
      const baseParams = {
        archived: true,
        limit: THREAD_LIST_MAX_LIMIT,
        sortKey: "updated_at",
        sortDirection: "desc",
        modelProviders: [],
      };
      const previousArchiveCards = this.store.listArchiveCards({ hostID: host.id }).cards;
      const history = await aggregateThreadList(this.config, baseParams);
      const rows = Array.isArray(history?.data) ? history.data : [];
      const cards = rows
        .map((row) => normalizeThread(row, host, "human", {
          archiveState: "archived",
        }))
        .filter(Boolean);
      const result = this.store.applyArchiveReconciliation({
        host,
        cards,
        complete: true,
        previousCards: previousArchiveCards,
      });
      const freshness = this.store.freshnessForHost(host.id);
      const totalRows = this.store.listArchiveCards({ hostID: host.id }).totalRows;
      await this.subscriptions.publishDelta(this.subscriptions.cardDelta({
        view: ARCHIVE_VIEW,
        baseSeq: Math.max(0, Number(result.seq) - 1),
        seq: result.seq,
        freshness,
        upsertHosts: [host],
        upsertCards: result.upsertCards,
        deleteCardIDs: result.deleteCardIDs,
        totalRows,
        complete: true,
      }));
      this.logger?.info?.("state.archive_reconcile_succeeded", {
        reason,
        hostId: host.id,
        rows: cards.length,
        seq: result.seq,
      });
      return result;
    } catch (error) {
      this.store.upsertHost(host);
      this.store.markScopeStale(host.id, "archived:interactiveDefault", error);
      const seq = this.store.currentSeq();
      const totalRows = this.store.listArchiveCards({ hostID: host.id }).totalRows;
      await this.subscriptions.publishDelta(this.subscriptions.cardDelta({
        view: ARCHIVE_VIEW,
        baseSeq: Math.max(0, seq - 1),
        seq,
        freshness: this.store.freshnessForHost(host.id),
        totalRows,
        complete: false,
      }));
      this.logger?.warn?.("state.archive_reconcile_failed", {
        reason,
        hostId: host.id,
        error,
      });
      return { seq, upsertCards: [], deleteCardIDs: [], error };
    }
  }

  async refreshLiveLeases() {
    const host = publicHostFromConfig(this.config);
    const endpoints = configuredLiveEndpointsForConfig(this.config, { includeHistory: true });
    const live = await collectLiveRows({
      logger: this.logger,
      pool: this.config.upstreamPool || null,
      endpoints,
      excludeURLs: [],
    });
    const endpointsByUrl = new Map(endpoints.map((endpoint) => [endpoint.url, endpoint]));
    const acceptedRows = [];
    for (const row of live.rows || []) {
      if (!isHumanStartedThread(row)) {
        continue;
      }
      const endpoint = endpointsByUrl.get(row?.dockRelaySource?.url) || row?.dockRelaySource || null;
      const lease = liveLeaseFromRow(
        row,
        endpoint,
        this.config.liveStatusMaxAgeMs || 5_000,
      );
      if (lease) {
        this.store.upsertLiveLease(host.id, lease);
        acceptedRows.push(row);
      }
    }
    this.store.deleteRejectedLiveLeases(host.id);
    return acceptedRows;
  }

  snapshotForView(view, {
    epoch,
    offset = 0,
    limit = RELAY_STATE_DOCK_WINDOW_SIZE,
    softLimitBytes = RELAY_STATE_SNAPSHOT_SOFT_LIMIT_BYTES,
  } = {}) {
    if (view === ARCHIVE_VIEW) {
      return this.snapshotArchive({ epoch, offset, limit, softLimitBytes });
    }
    return this.snapshotDock({ epoch, offset, limit, softLimitBytes });
  }

  snapshotDock({
    epoch = this.subscriptions.epoch,
    offset = 0,
    limit = RELAY_STATE_DOCK_WINDOW_SIZE,
    softLimitBytes = RELAY_STATE_SNAPSHOT_SOFT_LIMIT_BYTES,
  } = {}) {
    const host = publicHostFromConfig(this.config);
    const totalRows = this.store.listDockCards({ hostID: host.id, offset: 0, limit: 0 }).totalRows;
    if (totalRows === 0) {
      return this.makeSnapshot({
        view: DOCK_VIEW,
        epoch,
        complete: true,
        totalRows: 0,
        window: buildWindow({ offset: 0, limit: 0, rowCount: 0, totalRows: 0 }),
        cards: [],
        freshness: this.store.freshnessForHost(host.id),
      });
    }

    let windowLimit = Math.max(1, Math.min(Number(limit || 1), totalRows));
    let bounded = this.store.listDockCards({ hostID: host.id, offset, limit: windowLimit });
    let window = buildWindow({
      offset,
      limit: windowLimit,
      rowCount: bounded.cards.length,
      totalRows: bounded.totalRows,
    });
    let snapshot = this.makeSnapshot({
      view: DOCK_VIEW,
      epoch,
      complete: offset + bounded.cards.length >= bounded.totalRows,
      totalRows: bounded.totalRows,
      window,
      cards: bounded.cards,
      freshness: this.store.freshnessForHost(host.id),
    });

    while (estimateJSONBytes(snapshot) > softLimitBytes && windowLimit > 1) {
      windowLimit = Math.max(1, Math.floor(windowLimit / 2));
      bounded = this.store.listDockCards({ hostID: host.id, offset, limit: windowLimit });
      window = buildWindow({
        offset,
        limit: windowLimit,
        rowCount: bounded.cards.length,
        totalRows: bounded.totalRows,
      });
      snapshot = this.makeSnapshot({
        view: DOCK_VIEW,
        epoch,
        complete: offset + bounded.cards.length >= bounded.totalRows,
        totalRows: bounded.totalRows,
        window,
        cards: bounded.cards,
        freshness: this.store.freshnessForHost(host.id),
      });
    }

    return this.makeSnapshot({
      view: DOCK_VIEW,
      epoch,
      complete: offset + bounded.cards.length >= bounded.totalRows,
      totalRows: bounded.totalRows,
      window,
      cards: bounded.cards,
      freshness: this.store.freshnessForHost(host.id),
    });
  }

  snapshotArchive({
    epoch = this.subscriptions.epoch,
    offset = 0,
    limit = RELAY_STATE_DOCK_WINDOW_SIZE,
  } = {}) {
    const host = publicHostFromConfig(this.config);
    const result = this.store.listArchiveCards({ hostID: host.id, offset, limit });
    return this.makeSnapshot({
      view: ARCHIVE_VIEW,
      epoch,
      complete: offset + result.cards.length >= result.totalRows,
      totalRows: result.totalRows,
      window: buildWindow({
        offset,
        limit,
        rowCount: result.cards.length,
        totalRows: result.totalRows,
      }),
      cards: result.cards,
      freshness: this.store.freshnessForHost(host.id),
    });
  }

  makeSnapshot({
    view,
    epoch,
    complete,
    totalRows,
    window,
    cards,
    freshness,
  }) {
    return {
      kind: "snapshot",
      schemaVersion: 2,
      epoch,
      baseSeq: null,
      seq: this.store.currentSeq(),
      stateGeneration: this.store.currentSeq(),
      view,
      complete,
      totalRows,
      window,
      asOf: nowISOString(),
      visibility: appFacingHumanStartedVisibility(),
      freshness,
      hosts: this.store.hostRows(),
      cards,
    };
  }

  async subscribeDock({ session, downstreamWs, sendJson }) {
    return this.subscribeCardView({
      view: DOCK_VIEW,
      updateMethod: "dock/update",
      subscribeReason: "dock/subscribe",
      updateReason: "dock/update",
      unsubscribeKey: "dockUnsubscribe",
      session,
      downstreamWs,
      sendJson,
      after: () => this.scheduleReconciliationAfterResponse("dock/subscribe"),
    });
  }

  async subscribeArchive({ session, downstreamWs, sendJson }) {
    return this.subscribeCardView({
      view: ARCHIVE_VIEW,
      updateMethod: "archive/update",
      subscribeReason: "archive/subscribe",
      updateReason: "archive/update",
      unsubscribeKey: "archiveUnsubscribe",
      session,
      downstreamWs,
      sendJson,
      after: () => this.scheduleArchiveReconciliationAfterResponse("archive/subscribe"),
    });
  }

  async subscribeCardView({
    view,
    updateMethod,
    subscribeReason,
    updateReason,
    unsubscribeKey,
    session,
    downstreamWs,
    sendJson,
    after = null,
  }) {
    session[unsubscribeKey]?.();
    session[unsubscribeKey] = null;
    let subscriptionReady = false;
    const bufferedUpdates = [];
    const sendUpdate = (update, { scheduleCatchup = true } = {}) => {
      sendJson(downstreamWs, {
        jsonrpc: "2.0",
        method: updateMethod,
        params: update,
      });
      if (scheduleCatchup) {
        this.scheduleCardWindowCatchupAfterResponse(update, sendUpdate, updateReason);
      }
    };
    session[unsubscribeKey] = this.subscriptions.subscribe(view, (update) => {
      if (!subscriptionReady) {
        bufferedUpdates.push(update);
        return;
      }
      sendUpdate(update);
    });

    const snapshot = await this.subscriptions.snapshot(view);
    subscriptionReady = true;
    let catchupTarget = snapshot;
    for (const update of bufferedUpdates) {
      if (update.epoch === snapshot.epoch && Number(update.seq || 0) > Number(snapshot.seq || 0)) {
        sendUpdate(update);
        catchupTarget = update.kind === "snapshot" ? update : null;
      }
    }
    bufferedUpdates.length = 0;
    this.scheduleCardWindowCatchupAfterResponse(catchupTarget, sendUpdate, subscribeReason, { after });
    return snapshot;
  }

  async resyncDock({ downstreamWs = null, sendJson = null } = {}) {
    return this.resyncCardView({
      view: DOCK_VIEW,
      updateMethod: "dock/update",
      resyncReason: "dock/resync",
      updateReason: "dock/update",
      downstreamWs,
      sendJson,
      after: () => this.scheduleReconciliationAfterResponse("dock/resync"),
      otherwise: () => this.scheduleReconciliationAfterResponse("dock/resync"),
    });
  }

  async resyncArchive({ downstreamWs = null, sendJson = null } = {}) {
    return this.resyncCardView({
      view: ARCHIVE_VIEW,
      updateMethod: "archive/update",
      resyncReason: "archive/resync",
      updateReason: "archive/update",
      downstreamWs,
      sendJson,
      after: () => this.scheduleArchiveReconciliationAfterResponse("archive/resync"),
      otherwise: () => this.scheduleArchiveReconciliationAfterResponse("archive/resync"),
    });
  }

  scheduleArchiveReconciliationAfterResponse(reason) {
    const timer = setImmediate(() => {
      this.reconcileArchive({ reason }).catch((error) => {
        this.logger?.warn?.("state.archive_reconcile_failed", { reason, error });
      });
    });
    timer.unref?.();
  }

  async resyncCardView({
    view,
    updateMethod,
    resyncReason,
    updateReason,
    downstreamWs = null,
    sendJson = null,
    after = null,
    otherwise = null,
  } = {}) {
    const snapshot = await this.subscriptions.snapshot(view);
    if (downstreamWs && sendJson) {
      const sendUpdate = (update, { scheduleCatchup = true } = {}) => {
        sendJson(downstreamWs, {
          jsonrpc: "2.0",
          method: updateMethod,
          params: update,
        });
        if (scheduleCatchup) {
          this.scheduleCardWindowCatchupAfterResponse(update, sendUpdate, updateReason);
        }
      };
      this.scheduleCardWindowCatchupAfterResponse(snapshot, sendUpdate, resyncReason, { after });
    } else {
      otherwise?.();
    }
    return snapshot;
  }

  scheduleCardWindowCatchupAfterResponse(snapshot, sendUpdate, reason, { after = null } = {}) {
    if (!this.needsCardWindowCatchup(snapshot)) {
      after?.();
      return;
    }
    const timer = setImmediate(() => {
      this.sendCardWindowCatchup({ snapshot, sendUpdate, reason })
        .catch((error) => {
          this.logger?.warn?.("state.catchup_failed", { reason, error });
        })
        .finally(() => {
          after?.();
        });
    });
    timer.unref?.();
  }

  needsCardWindowCatchup(snapshot) {
    return snapshot?.kind === "snapshot"
      && (snapshot.view === DOCK_VIEW || snapshot.view === ARCHIVE_VIEW)
      && snapshot.complete === false
      && Number.isInteger(snapshot.window?.nextOffset);
  }

  async sendCardWindowCatchup({ snapshot, sendUpdate, reason }) {
    const host = publicHostFromConfig(this.config);
    const baseSeq = Number(snapshot.seq || 0);
    let nextOffset = Number(snapshot.window?.nextOffset || 0);
    const preferredLimit = Math.max(1, Number(snapshot.window?.limit || RELAY_STATE_DOCK_WINDOW_SIZE));
    while (Number.isInteger(nextOffset)) {
      if (this.store.currentSeq() !== baseSeq) {
        const restartSnapshot = await this.subscriptions.snapshot(snapshot.view);
        this.logger?.info?.("state.catchup_abandoned", {
          reason,
          hostId: host.id,
          baseSeq,
          currentSeq: this.store.currentSeq(),
          restartedSeq: restartSnapshot?.seq ?? null,
        });
        sendUpdate(restartSnapshot, { scheduleCatchup: false });
        await this.sendCardWindowCatchup({ snapshot: restartSnapshot, sendUpdate, reason });
        return;
      }
      let limit = preferredLimit;
      let delta = this.makeCardWindowDelta({
        host,
        snapshot,
        offset: nextOffset,
        limit,
      });
      while (estimateJSONBytes(delta) > RELAY_STATE_UPDATE_SOFT_LIMIT_BYTES && limit > 1) {
        limit = Math.max(1, Math.floor(limit / 2));
        delta = this.makeCardWindowDelta({
          host,
          snapshot,
          offset: nextOffset,
          limit,
        });
      }
      sendUpdate(delta);
      if (delta.complete === true || !Number.isInteger(delta.window?.nextOffset)) {
        return;
      }
      if (Number(delta.window.rowCount || 0) <= 0) {
        this.logger?.warn?.("state.catchup_empty_window", {
          reason,
          hostId: host.id,
          offset: nextOffset,
          totalRows: delta.totalRows,
        });
        return;
      }
      nextOffset = delta.window.nextOffset;
      await sleep(0);
    }
  }

  makeCardWindowDelta({ host, snapshot, offset, limit }) {
    const bounded = snapshot.view === ARCHIVE_VIEW
      ? this.store.listArchiveCards({ hostID: host.id, offset, limit })
      : this.store.listDockCards({ hostID: host.id, offset, limit });
    const complete = offset + bounded.cards.length >= bounded.totalRows;
    return this.subscriptions.cardDelta({
      view: snapshot.view,
      baseSeq: snapshot.seq,
      seq: snapshot.seq,
      freshness: snapshot.freshness || this.store.freshnessForHost(host.id),
      upsertCards: bounded.cards,
      deleteCardIDs: [],
      totalRows: bounded.totalRows,
      complete,
      window: buildWindow({
        offset,
        limit,
        rowCount: bounded.cards.length,
        totalRows: bounded.totalRows,
      }),
    });
  }

  async handleArchiveMutation({ threadId, archived }) {
    const result = this.ingestor.ingestArchiveMutation({ threadId, archived });
    if (!result) {
      return;
    }
    const host = publicHostFromConfig(this.config);
    const dockTotalRows = this.store.listDockCards({ hostID: host.id }).totalRows;
    await this.subscriptions.publishDelta(this.subscriptions.cardDelta({
      view: DOCK_VIEW,
      baseSeq: Math.max(0, Number(result.seq) - 1),
      seq: result.seq,
      freshness: this.store.freshnessForHost(host.id),
      upsertCards: result.dockUpsertCards || [],
      deleteCardIDs: result.dockDeleteCardIDs || [],
      totalRows: dockTotalRows,
      complete: true,
    }));
    const archiveTotalRows = this.store.listArchiveCards({ hostID: host.id }).totalRows;
    await this.subscriptions.publishDelta(this.subscriptions.cardDelta({
      view: ARCHIVE_VIEW,
      baseSeq: Math.max(0, Number(result.seq) - 1),
      seq: result.seq,
      freshness: this.store.freshnessForHost(host.id),
      upsertCards: result.archiveUpsertCards || [],
      deleteCardIDs: result.archiveDeleteCardIDs || [],
      totalRows: archiveTotalRows,
      complete: true,
    }));
  }

  stateSnapshot() {
    return {
      ok: true,
      schema: "codexdock.relayState.v1",
      visibility: appFacingHumanStartedVisibility(),
      db: this.store.dbHealth(),
      counts: this.store.stateCounts(),
      syncScopes: this.store.syncScopes(),
    };
  }

  explainThread(threadID) {
    const host = publicHostFromConfig(this.config);
    return this.store.explainThread({ hostID: host.id, threadID });
  }
}

function relayStateEngineForConfig(config) {
  if (!config.relayStateEngine) {
    config.relayStateEngine = new RelayStateEngine(config);
  }
  return config.relayStateEngine;
}

export {
  RelayStateEngine,
  StateReconciler,
  relayStateEngineForConfig,
  sleep,
};

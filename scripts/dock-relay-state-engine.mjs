import {
  RELAY_STATE_DOCK_WINDOW_SIZE,
  RELAY_STATE_RECONCILE_DEBOUNCE_MS,
  RELAY_STATE_RECONCILE_INTERVAL_MS,
  RELAY_STATE_SNAPSHOT_SOFT_LIMIT_BYTES,
  RELAY_STATE_STREAM_SCHEMA_VERSION,
  RELAY_STATE_TARGETED_DIRTY_DEBOUNCE_MS,
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
  estimateJSONBytes,
  normalizeThread,
  normalizedStatus,
  orderedDockRows,
  publicHostFromConfig,
} from "./dock-relay-state-views.mjs";
import { isHumanStartedThread } from "./dock-relay-human-thread-filter.mjs";
import {
  canonicalizeThreadRows,
  collectLiveRows,
  drainThreadListRows,
  enrichHumanStartedRows,
  mergeHumanStartedRowsWithSupplements,
  mergePrivateLiveRows,
  readCanonicalThreadForProjection,
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

const ACTIVE_LIVE_SCOPE = {
  name: "active:liveLoadedSessions",
  archived: false,
  sourceScope: "liveLoadedSessions",
};

function firstScopeError(scopes, fallback) {
  const scope = scopes.find((candidate) => candidate?.complete === false && candidate?.error);
  return scope?.error || fallback;
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

function threadIDFromNotification(message) {
  return message?.params?.threadId
    || message?.params?.threadID
    || message?.params?.thread_id
    || message?.params?.thread?.id
    || null;
}

function threadNameFromNotification(message) {
  return typeof message?.params?.threadName === "string"
    ? message.params.threadName
    : (typeof message?.params?.thread_name === "string"
      ? message.params.thread_name
      : (typeof message?.params?.name === "string" ? message.params.name : null));
}

function threadStatusFromNotification(message) {
  return message?.params?.status || null;
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
    this.inFlight = this.engine.reconcileAll({ reason }).finally(() => {
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
      heartbeatForView: (view, params) => this.heartbeatForView(view, params),
      logger: this.logger,
      heartbeatIntervalMs: config.relayStateHeartbeatIntervalMs,
      snapshotSoftLimitBytes: config.relayStateSnapshotSoftLimitBytes
        || RELAY_STATE_SNAPSHOT_SOFT_LIMIT_BYTES,
    });
    this.ingestor = new NotificationIngestor({
      store: this.store,
      hostId: config.hostId,
      scheduleReconciliation: (request) => this.scheduleReconciliation(request),
      logger: this.logger,
    });
    this.mutationReconcileChain = Promise.resolve(null);
    this.liveLeaseExpiryTimer = null;
    this.threadDirtyTimers = new Map();
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
    for (const timer of this.threadDirtyTimers.values()) {
      clearTimeout(timer);
    }
    this.threadDirtyTimers.clear();
    await this.reconciler.stop();
    await this.mutationReconcileChain.catch(() => null);
    this.store.close();
  }

  scheduleReconciliation(request = {}) {
    return this.reconciler.schedule(request);
  }

  async refreshLiveStatusCacheForSnapshot(reason) {
    if (typeof this.config.liveStatusCache?.snapshotForRouting !== "function") {
      return null;
    }
    try {
      return await this.config.liveStatusCache.snapshotForRouting();
    } catch (error) {
      this.logger?.warn?.("state.live_status_snapshot_refresh_failed", {
        reason,
        error,
      });
      return null;
    }
  }

  async refreshDockProjectionForSnapshot(reason) {
    const liveSnapshot = await this.refreshLiveStatusCacheForSnapshot(reason);
    if (!liveSnapshot?.ok) {
      return liveSnapshot;
    }
    const hasLiveEndpointEvidence = Number(liveSnapshot.endpoints?.length || 0) > 0
      || Number(liveSnapshot.rows?.length || 0) > 0
      || Number(liveSnapshot.rollupRows?.length || 0) > 0
      || Number(liveSnapshot.failedEndpoints || 0) > 0
      || Number(liveSnapshot.failedThreadReads || 0) > 0;
    if (!hasLiveEndpointEvidence) {
      return liveSnapshot;
    }
    return this.reconcileDock({ reason: `${reason}:pre_snapshot` });
  }

  cardForThread(threadID, { visibleOnly = true } = {}) {
    const host = publicHostFromConfig(this.config);
    return this.store.cardForThread({ hostID: host.id, threadID, visibleOnly });
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

  shouldReconcileAfterResponse({ archived = false } = {}) {
    const host = publicHostFromConfig(this.config);
    const freshness = this.store.freshnessForHost(host.id, { archived });
    return freshness.status !== "fresh";
  }

  scheduleReconciliationAfterResponse(reason, { force = false, archived = false } = {}) {
    if (!force && !this.shouldReconcileAfterResponse({ archived })) {
      this.logger?.debug?.("state.reconcile_skipped", {
        reason,
        archived,
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

  async publishTargetedCardResult(result, {
    view = result?.view,
    reason = "targeted-card-update",
  } = {}) {
    if (result?.removedFrom?.changed) {
      await this.publishTargetedCardResult(result.removedFrom, {
        view: result.removedFrom.view,
        reason,
      });
    }
    if (!result?.changed || !view) {
      return;
    }
    const host = publicHostFromConfig(this.config);
    const archived = view === ARCHIVE_VIEW;
    const freshness = this.store.freshnessForHost(host.id, { archived });
    const totalRows = archived
      ? this.store.listArchiveCards({ hostID: host.id, offset: 0, limit: 0 }).totalRows
      : this.store.listDockCards({ hostID: host.id, offset: 0, limit: 0 }).totalRows;
    await this.subscriptions.publishDelta(this.subscriptions.cardDelta({
      view,
      seq: result.seq,
      sourceHostID: host.id,
      freshness,
      rows: result.rows || [],
      projectionIDs: result.projectionIDs || [],
      totalRows,
      complete: result.complete === true ? true : undefined,
      reason,
    }));
    this.logger?.info?.("state.targeted_projection_delta_emitted", {
      reason,
      hostId: host.id,
      view,
      seq: result.seq,
      upsertCount: Number(result.rows?.length || 0),
      deleteCount: Number(result.projectionIDs?.length || 0),
    });
  }

  async publishTargetedArchiveMove(results, reason) {
    await this.publishTargetedCardResult(results?.dock, { view: DOCK_VIEW, reason });
    await this.publishTargetedCardResult(results?.archive, { view: ARCHIVE_VIEW, reason });
  }

  async patchThreadCard({ threadId, patch, reason }) {
    const host = publicHostFromConfig(this.config);
    const result = this.store.applyThreadCardPatch({
      host,
      threadID: threadId,
      patch,
      reason,
    });
    if (!result?.hidden) {
      await this.publishTargetedCardResult(result, { view: result.view, reason });
    }
    return result;
  }

  async projectThreadCard({ threadId, reason, archived = false, eventThread = null } = {}) {
    const host = publicHostFromConfig(this.config);
    let row = eventThread;
    let canonical = null;
    if (row?.id) {
      canonical = await canonicalizeThreadRows(this.config, [row], { route: reason });
      row = canonical.rows[0] || null;
    } else {
      canonical = await readCanonicalThreadForProjection(this.config, threadId, { route: reason });
      row = canonical.row;
    }
    if (!row?.id) {
      throw new Error("targeted projection could not resolve thread row");
    }
    const card = normalizeThread(row, host, "human", {
      archiveState: archived ? "archived" : "active",
      freshness: row.freshness,
      completeness: row.completeness,
    });
    const result = this.store.applyTargetedCardUpsert({
      host,
      card,
      reason,
    });
    await this.publishTargetedCardResult(result, { view: result.view, reason });
    return result;
  }

  async updateThreadCardFromEvent({ threadId, reason, patch = null, archived = null, eventThread = null } = {}) {
    if (!threadId) {
      return null;
    }
    if (patch && Object.keys(patch).length > 0) {
      const patched = await this.patchThreadCard({ threadId, patch, reason });
      if (!patched?.missing) {
        return {
          reason,
          path: patched.changed ? "direct_patch" : "direct_patch_noop",
          [patched.view === ARCHIVE_VIEW ? "archive" : "dock"]: patched,
        };
      }
      if (patched.hidden) {
        return {
          reason,
          path: "hidden_card_ignored",
        };
      }
    }
    const existing = this.cardForThread(threadId);
    if (!existing && !eventThread && this.cardForThread(threadId, { visibleOnly: false })) {
      return {
        reason,
        path: "hidden_card_ignored",
      };
    }
    const targetArchived = archived !== null && archived !== undefined
      ? Boolean(archived)
      : existing?.archiveState === "archived";
    const projected = await this.projectThreadCard({
      threadId,
      reason,
      archived: targetArchived,
      eventThread,
    });
    return {
      reason,
      path: "targeted_read",
      [projected.view === ARCHIVE_VIEW ? "archive" : "dock"]: projected,
    };
  }

  queueThreadDirtyUpdate({ threadId, reason }) {
    if (!threadId) {
      return null;
    }
    const key = threadId;
    const existingTimer = this.threadDirtyTimers.get(key);
    if (existingTimer) {
      clearTimeout(existingTimer);
    }
    const timer = setTimeout(() => {
      this.threadDirtyTimers.delete(key);
      this.queueMutationReconciliation(() => this.updateThreadCardFromEvent({
        threadId,
        reason,
      })).catch((error) => {
        this.logger?.warn?.("state.thread_dirty_targeted_update_failed", {
          reason,
          error,
        });
      });
    }, this.config.relayStateTargetedDirtyDebounceMs || RELAY_STATE_TARGETED_DIRTY_DEBOUNCE_MS);
    timer.unref?.();
    this.threadDirtyTimers.set(key, timer);
    return {
      reason,
      threadId,
      queued: true,
    };
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
      const [liveProof, defaultScope] = await Promise.all([
        this.refreshLiveLeases(),
        drainThreadListRows(this.config, baseParams, {
          name: `${ACTIVE_ARCHIVE_SCOPE.name}:${ACTIVE_DEFAULT_SCOPE.name}`,
          sourceScope: ACTIVE_DEFAULT_SCOPE.name,
        }),
      ]);
      const liveRows = liveProof.rows;
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
      const orderedRows = orderedDockRows([], appRows, liveRows, liveProof.rollupRows);
      // Card order is derived only after every row has proven activity from
      // thread/read plus thread/turns/list. Raw thread/list order is input data,
      // not a client-visible ordering contract.
      const canonical = await canonicalizeThreadRows(
        this.config,
        orderedRows.map(({ row }) => row).filter(Boolean),
        { route: "dock_reconcile" },
      );
      const canonicalByID = new Map(canonical.rows.map((row) => [row.id, row]));
      const cards = orderedRows
        .map(({ row, lane }) => canonicalByID.get(row?.id) ? normalizeThread(canonicalByID.get(row.id), host, lane, {
          archiveState: "active",
          freshness: canonicalByID.get(row.id).freshness,
          completeness: canonicalByID.get(row.id).completeness,
        }) : null)
        .filter(Boolean);
      const totalValidationFailures = validationFailures + canonical.validationFailures;
      const complete = defaultScope.complete
        && liveProof.scope.complete
        && totalValidationFailures === 0
        && canonical.complete;
      const reconciliationScope = complete
        ? defaultScope
        : {
          ...defaultScope,
          complete: defaultScope.complete,
          error: defaultScope.complete ? null : (defaultScope.error || "human-started thread validation failed"),
        };
      const proofScopes = [
        reconciliationScope,
        liveProof.scope,
      ];
      const cleanup = this.store.deleteRejectedThreadCards(host.id);
      const leaseCleanup = this.store.deleteRejectedLiveLeases(host.id);
      const result = this.store.applyDockReconciliation({
        host,
        cards,
        scopes: proofScopes,
        complete,
        error: firstScopeError(proofScopes, canonical.complete ? null : "card activity proof incomplete"),
        explicitRejectedThreadIDs: liveProof.rejectedThreadIDs,
        previousCards: previousDockCards,
      });
      const failureReason = firstScopeError(proofScopes, canonical.complete ? null : "card activity proof incomplete");
      const freshness = this.store.freshnessForHost(host.id, { archived: false });
      const totalRows = this.store.listDockCards({ hostID: host.id }).totalRows;
      const truthComplete = freshness.status === "fresh"
        && this.store.cardTruthCompleteForHost(host.id, { archived: false });
      // A delta that includes every current row is a complete client view even
      // when it also deletes stale rows from the previous view.
      const deltaCarriesEveryRow = complete
        && truthComplete
        && Number(result.rows?.length || 0) === Number(totalRows || 0);
      if (result.changed) {
        await this.subscriptions.publishDelta(this.subscriptions.cardDelta({
          view: DOCK_VIEW,
          seq: result.seq,
          sourceHostID: host.id,
          freshness,
          rows: result.rows,
          projectionIDs: result.projectionIDs,
          totalRows,
          complete: deltaCarriesEveryRow ? true : undefined,
        }));
      }
      if (complete) {
        this.logger?.info?.("state.reconcile_succeeded", {
          reason,
          hostId: host.id,
          rows: cards.length,
          rejectedCounts,
          validationFailures: totalValidationFailures,
          supplementValidationFailures: supplements.validationFailures,
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
          supplementValidationFailures: supplements.validationFailures,
          supplementedRows: supplements.acceptedRows.length,
          deletedRejectedCards: cleanup.deleted,
          deletedRejectedLiveLeases: leaseCleanup.deleted,
          error: failureReason,
        });
      }
      this.scheduleLiveLeaseExpiryReconciliation(host.id);
      return result;
    } catch (error) {
      this.store.upsertHost(host);
      const change = this.store.markScopeStale(host.id, "active:interactiveDefault", error);
      const seq = change.seq;
      const totalRows = this.store.listDockCards({ hostID: host.id }).totalRows;
      await this.subscriptions.publishDelta(this.subscriptions.cardDelta({
        view: DOCK_VIEW,
        seq,
        sourceHostID: host.id,
        freshness: this.store.freshnessForHost(host.id, { archived: false }),
        totalRows,
        complete: false,
      }));
      this.logger?.warn?.("state.reconcile_failed", {
        reason,
        hostId: host.id,
        error,
      });
      this.scheduleLiveLeaseExpiryReconciliation(host.id);
      return { seq, rows: [], projectionIDs: [], error };
    }
  }

  async reconcileAll({ reason = "manual" } = {}) {
    const [dock, archive] = await Promise.all([
      this.reconcileDock({ reason }),
      this.reconcileArchive({ reason }),
    ]);
    return { dock, archive };
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
      const defaultScope = await drainThreadListRows(this.config, baseParams, {
        name: "archived:interactiveDefault",
        sourceScope: "interactiveDefault",
      });
      const interactiveRows = defaultScope.rows.map((row) => row.thread).filter(Boolean);
      const { acceptedRows, rejectedCounts, validationFailures } = await enrichHumanStartedRows(
        this.config,
        interactiveRows,
        { route: "archive_reconcile" },
      );
      const supplements = await readSessionIndexHumanStartedSupplements(this.config, acceptedRows, {
        route: "archive_reconcile",
        params: baseParams,
        limit: baseParams.limit,
      });
      for (const [rejectedReason, count] of Object.entries(supplements.rejectedCounts)) {
        rejectedCounts[rejectedReason] = Number(rejectedCounts[rejectedReason] || 0) + Number(count || 0);
      }
      const rows = mergeHumanStartedRowsWithSupplements(acceptedRows, supplements.acceptedRows);
      const canonical = await canonicalizeThreadRows(this.config, rows, { route: "archive_reconcile" });
      const cards = canonical.rows
        .map((row) => normalizeThread(row, host, "human", {
          archiveState: "archived",
          freshness: row.freshness,
          completeness: row.completeness,
        }))
        .filter(Boolean);
      const totalValidationFailures = validationFailures + canonical.validationFailures;
      const complete = defaultScope.complete && totalValidationFailures === 0 && canonical.complete;
      const result = this.store.applyArchiveReconciliation({
        host,
        cards,
        complete,
        error: complete ? null : (defaultScope.error || "archive card activity proof incomplete"),
        previousCards: previousArchiveCards,
      });
      const freshness = this.store.freshnessForHost(host.id, { archived: true });
      const totalRows = this.store.listArchiveCards({ hostID: host.id }).totalRows;
      const truthComplete = freshness.status === "fresh"
        && this.store.cardTruthCompleteForHost(host.id, { archived: true });
      if (result.changed) {
        await this.subscriptions.publishDelta(this.subscriptions.cardDelta({
          view: ARCHIVE_VIEW,
          seq: result.seq,
          sourceHostID: host.id,
          freshness,
          rows: result.rows,
          projectionIDs: result.projectionIDs,
          totalRows,
          complete: complete && truthComplete ? true : false,
        }));
      }
      this.logger?.info?.("state.archive_reconcile_succeeded", {
        reason,
        hostId: host.id,
        rows: cards.length,
        rejectedCounts,
        validationFailures: totalValidationFailures,
        supplementValidationFailures: supplements.validationFailures,
        seq: result.seq,
      });
      return result;
    } catch (error) {
      this.store.upsertHost(host);
      const change = this.store.markScopeStale(host.id, "archived:interactiveDefault", error);
      const seq = change.seq;
      const totalRows = this.store.listArchiveCards({ hostID: host.id }).totalRows;
      await this.subscriptions.publishDelta(this.subscriptions.cardDelta({
        view: ARCHIVE_VIEW,
        seq,
        sourceHostID: host.id,
        freshness: this.store.freshnessForHost(host.id, { archived: true }),
        totalRows,
        complete: false,
      }));
      this.logger?.warn?.("state.archive_reconcile_failed", {
        reason,
        hostId: host.id,
        error,
      });
      return { seq, rows: [], projectionIDs: [], error };
    }
  }

  async refreshLiveLeases() {
    const host = publicHostFromConfig(this.config);
    if (!this.config.appServerRegistry) {
      throw new Error("appServerRegistry is required for state live lease refresh");
    }
    await this.config.appServerRegistry.ensureReady("state_live_leases");
    const endpoints = this.config.appServerRegistry.liveEndpoints();
    const collectedLive = await collectLiveRows({
      logger: this.logger,
      pool: this.config.upstreamPool || null,
      endpoints,
      excludeURLs: [],
      onNotification: this.config.upstreamNotificationHandler || null,
      codexHome: this.config.codexHome || null,
    });
    const live = mergePrivateLiveRows(collectedLive, this.config.appServerRegistry, {
      codexHome: this.config.codexHome || null,
      logger: this.logger,
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
        if (endpoint?.endpointType !== "private") {
          this.config.appServerRegistry?.recordLiveRows(endpoint, [row]);
        }
      }
    }
    this.store.deleteRejectedLiveLeases(host.id);
    const failedEndpoints = Number(live.failedEndpoints || 0);
    const failedThreadReads = Number(live.failedThreadReads || 0);
    const complete = failedEndpoints === 0 && failedThreadReads === 0;
    const error = failedEndpoints > 0
      ? `live loaded session refresh failed for ${failedEndpoints}/${endpoints.length} endpoints`
      : (failedThreadReads > 0 ? `live loaded session thread/read failed for ${failedThreadReads}/${live.totalThreadReads || 0} threads` : null);
    return {
      rows: acceptedRows,
      rollupRows: Array.isArray(live.rollupRows) ? live.rollupRows : [],
      rejectedThreadIDs: Array.isArray(live.privateRejectedThreadIDs)
        ? [...new Set([...(live.rejectedThreadIDs || []), ...live.privateRejectedThreadIDs])]
        : (Array.isArray(live.rejectedThreadIDs) ? live.rejectedThreadIDs : []),
      scope: {
        ...ACTIVE_LIVE_SCOPE,
        complete,
        error,
      },
    };
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

  heartbeatForView(view, {
    epoch = this.subscriptions.epoch,
  } = {}) {
    const host = publicHostFromConfig(this.config);
    const archived = view === ARCHIVE_VIEW;
    const freshness = this.store.freshnessForHost(host.id, { archived });
    const truthComplete = freshness.status === "fresh"
      && this.store.cardTruthCompleteForHost(host.id, { archived });
    const result = archived
      ? this.store.listArchiveCards({ hostID: host.id, offset: 0, limit: 0 })
      : this.store.listDockCards({ hostID: host.id, offset: 0, limit: 0 });
    const seq = this.store.currentSeqForView(view);
    return {
      kind: "heartbeat",
      schemaVersion: RELAY_STATE_STREAM_SCHEMA_VERSION,
      identityVersion: 1,
      projectionEngineVersion: 1,
      sourceHostID: host.id,
      epoch,
      seq,
      generation: this.subscriptions.generation,
      view,
      scope: "view",
      viewParamsKey: `${view}:${host.id}`,
      order: "displayOrderKeyAscending",
      complete: truthComplete,
      totalRows: result.totalRows,
      window: buildWindow({
        offset: 0,
        limit: 0,
        rowCount: 0,
        totalRows: result.totalRows,
      }),
      asOf: nowISOString(),
      freshness,
    };
  }

  snapshotDock({
    epoch = this.subscriptions.epoch,
    offset = 0,
    limit = RELAY_STATE_DOCK_WINDOW_SIZE,
    softLimitBytes = RELAY_STATE_SNAPSHOT_SOFT_LIMIT_BYTES,
  } = {}) {
    const host = publicHostFromConfig(this.config);
    const freshness = this.store.freshnessForHost(host.id, { archived: false });
    const truthComplete = freshness.status === "fresh"
      && this.store.cardTruthCompleteForHost(host.id, { archived: false });
    const totalRows = this.store.listDockCards({ hostID: host.id, offset: 0, limit: 0 }).totalRows;
    if (totalRows === 0) {
      return this.makeSnapshot({
        view: DOCK_VIEW,
        epoch,
        complete: truthComplete,
        totalRows: 0,
        window: buildWindow({ offset: 0, limit: 0, rowCount: 0, totalRows: 0 }),
        cards: [],
        freshness,
      });
    }

    const listDockCards = ({ offset: requestedOffset, limit: requestedLimit }) => {
      // Snapshots must expose only the committed projection. Live status cache
      // is folded into the store by reconciliation/targeted updates; applying
      // it here creates a second truth that subscribers were never sent.
      return this.store.listDockCards({ hostID: host.id, offset: requestedOffset, limit: requestedLimit });
    };

    let windowLimit = Math.max(1, Math.min(Number(limit || 1), totalRows));
    let bounded = listDockCards({ offset, limit: windowLimit });
    let window = buildWindow({
      offset,
      limit: windowLimit,
      rowCount: bounded.cards.length,
      totalRows: bounded.totalRows,
    });
    let snapshot = this.makeSnapshot({
      view: DOCK_VIEW,
      epoch,
      complete: truthComplete && offset + bounded.cards.length >= bounded.totalRows,
      totalRows: bounded.totalRows,
      window,
      cards: bounded.cards,
      freshness,
    });

    while (estimateJSONBytes(snapshot) > softLimitBytes && windowLimit > 1) {
      windowLimit = Math.max(1, Math.floor(windowLimit / 2));
      bounded = listDockCards({ offset, limit: windowLimit });
      window = buildWindow({
        offset,
        limit: windowLimit,
        rowCount: bounded.cards.length,
        totalRows: bounded.totalRows,
      });
      snapshot = this.makeSnapshot({
        view: DOCK_VIEW,
        epoch,
        complete: truthComplete && offset + bounded.cards.length >= bounded.totalRows,
        totalRows: bounded.totalRows,
        window,
        cards: bounded.cards,
        freshness,
      });
    }

    return this.makeSnapshot({
      view: DOCK_VIEW,
      epoch,
      complete: truthComplete && offset + bounded.cards.length >= bounded.totalRows,
      totalRows: bounded.totalRows,
      window,
      cards: bounded.cards,
      freshness,
    });
  }

  snapshotArchive({
    epoch = this.subscriptions.epoch,
    offset = 0,
    limit = RELAY_STATE_DOCK_WINDOW_SIZE,
  } = {}) {
    const host = publicHostFromConfig(this.config);
    const freshness = this.store.freshnessForHost(host.id, { archived: true });
    const truthComplete = freshness.status === "fresh"
      && this.store.cardTruthCompleteForHost(host.id, { archived: true });
    const result = this.store.listArchiveCards({ hostID: host.id, offset, limit });
    return this.makeSnapshot({
      view: ARCHIVE_VIEW,
      epoch,
      complete: truthComplete && offset + result.cards.length >= result.totalRows,
      totalRows: result.totalRows,
      window: buildWindow({
        offset,
        limit,
        rowCount: result.cards.length,
        totalRows: result.totalRows,
      }),
      cards: result.cards,
      freshness,
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
      schemaVersion: RELAY_STATE_STREAM_SCHEMA_VERSION,
      identityVersion: 1,
      projectionEngineVersion: 1,
      sourceHostID: publicHostFromConfig(this.config).id,
      epoch,
      seq: this.store.currentSeqForView(view),
      generation: this.subscriptions.generation,
      view,
      scope: "view",
      viewParamsKey: `${view}:${publicHostFromConfig(this.config).id}`,
      order: "displayOrderKeyAscending",
      complete,
      totalRows,
      window,
      asOf: nowISOString(),
      freshness,
      rows: cards,
    };
  }

  async subscribeDock({ session, downstreamWs, sendJson }) {
    await this.refreshDockProjectionForSnapshot("dock/subscribe");
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
    await this.refreshDockProjectionForSnapshot("dock/resync");
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
    if (!this.shouldReconcileAfterResponse({ archived: true })) {
      this.logger?.debug?.("state.archive_reconcile_skipped", {
        reason,
        archived: true,
        freshness: "fresh",
      });
      return;
    }
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
    const snapshotSeq = Number(snapshot.seq || 0);
    let nextOffset = Number(snapshot.window?.nextOffset || 0);
    const preferredLimit = Math.max(1, Number(snapshot.window?.limit || RELAY_STATE_DOCK_WINDOW_SIZE));
    while (Number.isInteger(nextOffset)) {
      if (this.store.currentSeqForView(snapshot.view) !== snapshotSeq) {
        const restartSnapshot = await this.subscriptions.snapshot(snapshot.view);
        this.logger?.info?.("state.catchup_abandoned", {
          reason,
          hostId: host.id,
          snapshotSeq,
          currentSeq: this.store.currentSeqForView(snapshot.view),
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
    const archived = snapshot.view === ARCHIVE_VIEW;
    const freshness = this.store.freshnessForHost(host.id, { archived });
    const truthComplete = freshness.status === "fresh"
      && this.store.cardTruthCompleteForHost(host.id, { archived });
    const complete = truthComplete && offset + bounded.cards.length >= bounded.totalRows;
    return this.subscriptions.cardDelta({
      kind: "page",
      view: snapshot.view,
      seq: snapshot.seq,
      sourceHostID: host.id,
      freshness,
      rows: bounded.cards,
      projectionIDs: [],
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

  queueMutationReconciliation(operation) {
    const previous = this.mutationReconcileChain.catch(() => null);
    const current = previous.then(operation, operation);
    const cleanup = current.then(
      () => null,
      () => null,
    ).then(() => {
      if (this.mutationReconcileChain === cleanup) {
        this.mutationReconcileChain = Promise.resolve(null);
      }
      return null;
    });
    this.mutationReconcileChain = cleanup;
    return current;
  }

  async reconcileDockAndArchiveAfterMutation({
    reason,
    logEvent,
    failureMessage,
  }) {
    const results = await Promise.allSettled([
      this.reconcileDock({ reason }),
      this.reconcileArchive({ reason }),
    ]);
    for (const [index, result] of results.entries()) {
      if (result.status !== "rejected" && !result.value?.error) {
        continue;
      }
      this.logger?.warn?.(logEvent, {
        reason,
        view: index === 0 ? DOCK_VIEW : ARCHIVE_VIEW,
        error: result.status === "rejected" ? result.reason : result.value.error,
      });
    }
    const failed = results.find((result) => result.status === "rejected" || result.value?.error);
    if (failed) {
      const reason = failed.status === "rejected" ? failed.reason : failed.value.error;
      throw reason instanceof Error ? reason : new Error(String(reason || failureMessage));
    }
    return {
      reason,
      dock: results[0].status === "fulfilled" ? results[0].value : null,
      archive: results[1].status === "fulfilled" ? results[1].value : null,
    };
  }

  async handleArchiveMutation({ threadId, archived }) {
    const mutation = this.ingestor.ingestArchiveMutation({ threadId, archived });
    if (!mutation) {
      return null;
    }
    return this.queueMutationReconciliation(async () => {
      const host = publicHostFromConfig(this.config);
      const move = this.store.applyThreadArchiveMove({
        host,
        threadID: mutation.threadId,
        archived: mutation.archived,
        reason: mutation.reason,
      });
      if (move.missing) {
        if (move.hidden) {
          return {
            reason: mutation.reason,
            path: "hidden_card_ignored",
            dock: move.dock,
            archive: move.archive,
          };
        }
        const projected = await this.projectThreadCard({
          threadId: mutation.threadId,
          reason: mutation.reason,
          archived: mutation.archived,
        });
        return {
          reason: mutation.reason,
          path: "targeted_read",
          [projected.view === ARCHIVE_VIEW ? "archive" : "dock"]: projected,
        };
      }
      await this.publishTargetedArchiveMove(move, mutation.reason);
      return {
        reason: mutation.reason,
        path: "targeted_archive_move",
        dock: move.dock,
        archive: move.archive,
      };
    });
  }

  async handleThreadNameNotification(message) {
    const mutation = this.ingestor.ingestThreadNameUpdated(message);
    if (!mutation) {
      return null;
    }
    const threadName = threadNameFromNotification(message);
    return this.queueMutationReconciliation(async () => {
      const patch = threadName ? { title: threadName } : null;
      return this.updateThreadCardFromEvent({
        threadId: mutation.threadId,
        reason: mutation.reason,
        patch,
      });
    });
  }

  async handleThreadStatusNotification(message) {
    const mutation = this.ingestor.ingestThreadStatusChanged(message);
    if (!mutation) {
      return null;
    }
    const rawStatus = threadStatusFromNotification(message);
    const status = rawStatus ? normalizedStatus({ status: rawStatus }) : null;
    return this.queueMutationReconciliation(async () => this.updateThreadCardFromEvent({
      threadId: mutation.threadId,
      reason: mutation.reason,
      patch: status && status !== "unknown" ? { status } : null,
    }));
  }

  async handleThreadStartedNotification(message) {
    const thread = message?.params?.thread || null;
    const threadId = threadIDFromNotification(message);
    if (message?.method !== "thread/started" || !threadId) {
      return null;
    }
    return this.queueMutationReconciliation(async () => this.updateThreadCardFromEvent({
      threadId,
      reason: "thread/started",
      archived: false,
      eventThread: thread,
    }));
  }

  async handleThreadArchivedNotification(message) {
    const threadId = threadIDFromNotification(message);
    if (message?.method !== "thread/archived" || !threadId) {
      return null;
    }
    return this.handleArchiveMutation({ threadId, archived: true });
  }

  async handleThreadUnarchivedNotification(message) {
    const threadId = threadIDFromNotification(message);
    if (message?.method !== "thread/unarchived" || !threadId) {
      return null;
    }
    return this.handleArchiveMutation({ threadId, archived: false });
  }

  async handleThreadClosedNotification(message) {
    const threadId = threadIDFromNotification(message);
    if (message?.method !== "thread/closed" || !threadId) {
      return null;
    }
    return this.queueMutationReconciliation(async () => {
      const host = publicHostFromConfig(this.config);
      const removed = this.store.applyTargetedCardRemoval({
        host,
        threadID: threadId,
        reason: "thread/closed",
      });
      await this.publishTargetedCardResult(removed, { view: removed.view, reason: "thread/closed" });
      return {
        reason: "thread/closed",
        path: "targeted_remove",
        [removed.view === ARCHIVE_VIEW ? "archive" : "dock"]: removed,
      };
    });
  }

  handleThreadDirtyNotification(message) {
    const method = message?.method;
    if (!["turn/started", "turn/completed", "item/started", "item/completed", "serverRequest/resolved"].includes(method)) {
      return null;
    }
    const threadId = threadIDFromNotification(message);
    if (!threadId) {
      return null;
    }
    return this.queueThreadDirtyUpdate({
      threadId,
      reason: method,
    });
  }

  async handleThreadNameMutation({ threadId, name = null, reason = "thread/name/set" }) {
    if (!threadId) {
      return null;
    }
    return this.queueMutationReconciliation(() => this.updateThreadCardFromEvent({
      threadId,
      reason,
      patch: typeof name === "string" && name.trim().length > 0 ? { title: name } : null,
    }));
  }

  stateHealth() {
    return {
      ok: true,
      schema: "codexdock.relayState.health.v1",
      db: this.store.dbHealth(),
    };
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

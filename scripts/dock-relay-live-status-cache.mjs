import { defaultRelayLogger } from "./dock-relay-logger.mjs";

const DEFAULT_LIVE_STATUS_MAX_AGE_MS = 5_000;
const DEFAULT_LIVE_STATUS_REFRESH_INTERVAL_MS = 2_500;

function liveOverlayForSnapshot(snapshot, maxAgeMs = DEFAULT_LIVE_STATUS_MAX_AGE_MS) {
  const ageMs = snapshot.checkedAtMs ? Date.now() - snapshot.checkedAtMs : null;
  if (snapshot.ok && ageMs !== null && ageMs <= maxAgeMs) {
    if (snapshot.failedEndpoints > 0) {
      return {
        ok: false,
        state: "degraded",
        ageMs,
        endpoints: snapshot.endpoints.length,
        failedEndpoints: snapshot.failedEndpoints,
        rows: snapshot.rows.length,
      };
    }
    return {
      ok: true,
      state: "ready",
      ageMs,
      endpoints: snapshot.endpoints.length,
      failedEndpoints: snapshot.failedEndpoints,
      rows: snapshot.rows.length,
    };
  }
  if (snapshot.ok && ageMs !== null) {
    return {
      ok: false,
      state: "stale",
      ageMs,
    };
  }
  return {
    ok: false,
    state: snapshot.checkedAtMs ? "unavailable" : "disabled",
    ageMs,
  };
}

class LiveStatusCache {
  constructor({
    collectLiveRows,
    logger = defaultRelayLogger,
    statusTracker = null,
    refreshIntervalMs = DEFAULT_LIVE_STATUS_REFRESH_INTERVAL_MS,
    maxAgeMs = DEFAULT_LIVE_STATUS_MAX_AGE_MS,
  }) {
    this.collectLiveRows = collectLiveRows;
    this.logger = logger;
    this.statusTracker = statusTracker;
    this.refreshIntervalMs = refreshIntervalMs;
    this.maxAgeMs = maxAgeMs;
    this.refreshTimer = null;
    this.refreshPromise = null;
    this.state = {
      checkedAt: null,
      checkedAtMs: null,
      ok: false,
      status: "unknown",
      endpoints: [],
      failedEndpoints: 0,
      rows: [],
      error: null,
    };
  }

  start() {
    if (this.refreshTimer || !this.collectLiveRows) {
      return;
    }
    this.refreshTimer = setInterval(() => {
      this.refreshNow().catch((error) => {
        this.logger.warn("live_status.refresh_failed", { error });
      });
    }, this.refreshIntervalMs);
    this.refreshTimer.unref?.();
  }

  stop() {
    if (this.refreshTimer) {
      clearInterval(this.refreshTimer);
      this.refreshTimer = null;
    }
  }

  async refreshNow() {
    if (!this.collectLiveRows) {
      return this.snapshot();
    }
    if (this.refreshPromise) {
      return this.refreshPromise;
    }
    this.refreshPromise = (async () => {
      try {
        const live = await this.collectLiveRows(this.logger);
        this.state = {
          checkedAt: new Date().toISOString(),
          checkedAtMs: Date.now(),
          ok: true,
          status: "up",
          endpoints: live.endpoints || [],
          failedEndpoints: live.failedEndpoints || 0,
          rows: live.rows || [],
          error: null,
        };
        this.statusTracker?.recordLiveDiscovery({
          status: "up",
          ok: true,
          endpoints: this.state.endpoints.length,
          failedEndpoints: this.state.failedEndpoints,
          rows: this.state.rows.length,
        });
        return this.snapshot();
      } catch (error) {
        this.state = {
          checkedAt: new Date().toISOString(),
          checkedAtMs: Date.now(),
          ok: false,
          status: "down",
          endpoints: [],
          failedEndpoints: 1,
          rows: [],
          error,
        };
        this.statusTracker?.recordLiveDiscovery({
          status: "down",
          ok: false,
          error,
        });
        return this.snapshot();
      } finally {
        this.refreshPromise = null;
      }
    })();
    return this.refreshPromise;
  }

  async snapshotForRouting() {
    const snapshot = this.snapshot();
    const ageMs = snapshot.checkedAtMs ? Date.now() - snapshot.checkedAtMs : null;
    if (ageMs === null || ageMs > this.maxAgeMs) {
      return this.refreshNow();
    }
    return snapshot;
  }

  snapshot() {
    return {
      ...this.state,
      rows: [...this.state.rows],
      endpoints: [...this.state.endpoints],
      liveOverlay: liveOverlayForSnapshot(this.state, this.maxAgeMs),
    };
  }

  liveOverlay() {
    return this.snapshot().liveOverlay;
  }
}

class SessionRouter {
  constructor({
    liveStatusCache,
    historyEndpoint,
  }) {
    this.liveStatusCache = liveStatusCache;
    this.historyEndpoint = historyEndpoint;
  }

  async endpointForThread(threadId) {
    const snapshot = await this.liveStatusCache.snapshotForRouting();
    const liveRow = snapshot.rows.find((row) => row.id === threadId);
    return liveRow?.dockRelaySource || this.historyEndpoint;
  }

  async rowForThread(threadId) {
    const snapshot = await this.liveStatusCache.snapshotForRouting();
    return snapshot.rows.find((row) => row.id === threadId) || null;
  }

  async loadedThreadIDs(params = {}) {
    const snapshot = await this.liveStatusCache.snapshotForRouting();
    const ids = snapshot.rows.map((row) => row.id).filter(Boolean);
    return ids;
  }
}

export {
  LiveStatusCache,
  SessionRouter,
  liveOverlayForSnapshot,
};

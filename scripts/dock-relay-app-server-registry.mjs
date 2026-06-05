import fs from "node:fs";

import {
  APP_SERVER_REGISTRY_ENDPOINT_TTL_MS,
  APP_SERVER_REGISTRY_LIVE_ENDPOINT_LIMIT,
  APP_SERVER_REGISTRY_REFRESH_INTERVAL_MS,
  APP_SERVER_REGISTRY_STATUS_ENDPOINT_LIMIT,
  LIVE_LOADED_LIST_LIMIT,
  LIVE_THREAD_READ_CONCURRENCY,
  RELAY_VERSION,
} from "./dock-relay-constants.mjs";
import {
  canonicalEndpointURL,
  daemonSocketPathForCodexHome,
  daemonUnixURLForCodexHome,
  defaultCodexHome,
  defaultProcessListProvider,
  discoverAppServerEndpointsFromProcesses,
  isLoopbackWebSocketURL,
  normalizeAppServerEndpoint,
  sanitizedEndpoint,
  stableID,
  tokenizeCommandLine,
} from "./dock-relay-app-server-discovery.mjs";
import { defaultRelayLogger } from "./dock-relay-logger.mjs";
import { JsonRpcWebSocketClient } from "./dock-relay-json-rpc-client.mjs";
const HISTORY_ROUTE_METHODS = new Set([
  "thread/list",
  "thread/unarchive",
]);
const LIVE_OWNER_PREFERRED_METHODS = new Set([
  "thread/read",
  "thread/turns/list",
  "thread/message/send",
  "thread/resume",
  "turn/start",
  "turn/steer",
  "thread/archive",
  "thread/name/set",
  "thread/detail/subscribe",
  "thread/detail/resync",
]);
const ACTIVE_SESSION_ONLY_METHODS = new Set([
  "turn/interrupt",
  "raw-json-rpc/server-request-response",
]);
const HISTORY_SAFE_PRIVATE_OWNER_METHODS = new Set([
  "thread/read",
  "thread/turns/list",
  "thread/name/set",
]);

class AppServerRegistryRouteError extends Error {
  constructor(message, {
    code = -32020,
    reason = "app_server_registry_route_unavailable",
    method = null,
    threadId = null,
  } = {}) {
    super(message);
    this.name = "AppServerRegistryRouteError";
    this.code = code;
    this.reason = reason;
    this.method = method;
    this.threadId = threadId;
  }
}

function nowISOString(clock) {
  const value = clock();
  return value instanceof Date ? value.toISOString() : new Date(value).toISOString();
}

function nowMs(clock) {
  const value = clock();
  return value instanceof Date ? value.getTime() : Number(value);
}

function statusPriorityForThread(thread) {
  const type = thread?.status?.type;
  if (type === "active" || type === "running") {
    return 0;
  }
  if (type === "idle") {
    return 1;
  }
  if (type === "systemError") {
    return 2;
  }
  if (type === "notLoaded") {
    return 4;
  }
  return 3;
}

function updatedAtMs(thread) {
  const value = thread?.updatedAt ?? thread?.updated_at ?? thread?.lastActivityAt;
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }
  const parsed = Date.parse(String(value || ""));
  return Number.isFinite(parsed) ? parsed : 0;
}

function preferLiveOwner(candidate, existing) {
  if (!existing) {
    return candidate;
  }
  const candidatePriority = statusPriorityForThread(candidate.row);
  const existingPriority = statusPriorityForThread(existing.row);
  if (candidatePriority !== existingPriority) {
    return candidatePriority < existingPriority ? candidate : existing;
  }
  return updatedAtMs(candidate.row) >= updatedAtMs(existing.row) ? candidate : existing;
}

function isAttachableOwnerProbeEndpoint(endpoint) {
  const supportedTransport = endpoint?.transport === "unix"
    || endpoint?.transport === "ws"
    || endpoint?.transport === "wss";
  return Boolean(
    endpoint
    && !endpoint.failure
    && !endpoint.dockOwnedRaw
    && supportedTransport
    && (endpoint.transport === "unix" || endpoint.endpointType === "live")
  );
}

function allSettledInBatches(values, batchSize, mapper) {
  const size = Math.max(1, Math.floor(Number(batchSize) || 1));
  return (async () => {
    const results = [];
    for (let start = 0; start < values.length; start += size) {
      const batch = values.slice(start, start + size);
      results.push(...await Promise.allSettled(batch.map(mapper)));
    }
    return results;
  })();
}

class AppServerRegistry {
  constructor({
    codexHome = defaultCodexHome(),
    daemonSocketPath = null,
    includeDaemonHistory = true,
    fixtureHistoryEndpoints = [],
    fixtureLiveEndpoints = [],
    diagnosticEndpoints = [],
    discoveryProvider = null,
    processListProvider = defaultProcessListProvider,
    clientFactory = null,
    logger = defaultRelayLogger,
    clock = () => new Date(),
    refreshIntervalMs = APP_SERVER_REGISTRY_REFRESH_INTERVAL_MS,
    endpointTtlMs = APP_SERVER_REGISTRY_ENDPOINT_TTL_MS,
  } = {}) {
    this.codexHome = codexHome;
    this.daemonSocketPath = daemonSocketPath || daemonSocketPathForCodexHome(codexHome);
    this.includeDaemonHistory = includeDaemonHistory;
    this.fixtureHistoryEndpoints = fixtureHistoryEndpoints;
    this.fixtureLiveEndpoints = fixtureLiveEndpoints;
    this.diagnosticEndpoints = diagnosticEndpoints;
    this.discoveryProvider = discoveryProvider;
    this.processListProvider = processListProvider;
    this.clientFactory = clientFactory;
    this.logger = logger;
    this.clock = clock;
    this.refreshIntervalMs = refreshIntervalMs;
    this.endpointTtlMs = endpointTtlMs;
    this.refreshTimer = null;
    this.refreshPromise = null;
    this.threadOwnerById = new Map();
    this.privateOwnerByThreadId = new Map();
    this.state = {
      lastRefreshAt: null,
      lastRefreshAtMs: null,
      selectedHistoryEndpoint: null,
      endpoints: [],
      liveEndpoints: [],
      unreachableObserved: [],
      failedEndpoints: [],
      duplicateOwners: [],
      error: null,
    };
  }

  async start() {
    await this.refreshNow("start");
    if (!this.refreshTimer) {
      this.refreshTimer = setInterval(() => {
        this.refreshNow("timer").catch((error) => {
          this.logger.warn("app_server_registry.refresh_failed", { error });
        });
      }, this.refreshIntervalMs);
      this.refreshTimer.unref?.();
    }
  }

  stop() {
    if (this.refreshTimer) {
      clearInterval(this.refreshTimer);
      this.refreshTimer = null;
    }
  }

  async refreshNow(reason = "manual") {
    if (this.refreshPromise) {
      return this.refreshPromise;
    }
    this.refreshPromise = this.refresh(reason).finally(() => {
      this.refreshPromise = null;
    });
    return this.refreshPromise;
  }

  async ensureReady(reason = "ensure_ready") {
    if (!this.state.lastRefreshAt) {
      await this.refreshNow(reason);
    }
    return this.snapshot();
  }

  async refresh(reason) {
    const observedAt = nowISOString(this.clock);
    const observedAtMs = nowMs(this.clock);
    const endpoints = [];
    const observations = [];
    const failedEndpoints = [];
    const privateThreadOwners = [];
    let privateOwnerRefreshReliable = !this.discoveryProvider && !this.processListProvider;

    if (this.includeDaemonHistory) {
      endpoints.push({
        source: "daemon",
        endpointType: "history",
        label: "codex-daemon-history",
        url: "unix://",
        codexHome: this.codexHome,
      });
    }
    endpoints.push(...this.fixtureHistoryEndpoints.map((endpoint) => ({
      ...endpoint,
      source: endpoint.source || "fixture-history",
      endpointType: "history",
    })));
    endpoints.push(...this.fixtureLiveEndpoints.map((endpoint) => ({
      ...endpoint,
      source: endpoint.source || "fixture-live",
      endpointType: "live",
    })));
    observations.push(...this.diagnosticEndpoints);

    try {
      if (this.discoveryProvider) {
        const discovered = await this.discoveryProvider({ codexHome: this.codexHome, reason });
        if (Array.isArray(discovered)) {
          endpoints.push(...discovered);
        } else if (discovered && typeof discovered === "object") {
          endpoints.push(...(discovered.endpoints || []));
          observations.push(...(discovered.observations || []));
          privateThreadOwners.push(...(discovered.privateThreadOwners || []));
        }
        privateOwnerRefreshReliable = true;
      } else if (this.processListProvider) {
        const processList = await this.processListProvider({
          codexHome: this.codexHome,
          logger: this.logger,
          reason,
        });
        const discovered = discoverAppServerEndpointsFromProcesses(processList, {
          codexHome: this.codexHome,
          logger: this.logger,
        });
        endpoints.push(...discovered.endpoints);
        observations.push(...discovered.observations);
        privateThreadOwners.push(...discovered.privateThreadOwners);
        privateOwnerRefreshReliable = true;
      }
    } catch (error) {
      failedEndpoints.push({
        reason: "discovery_failed",
        message: error?.message || String(error),
      });
      this.logger.warn("app_server_registry.discovery_failed", { reason, error });
    }

    const endpointMap = new Map();
    const unreachableObserved = [];
    for (const rawEndpoint of endpoints) {
      const endpoint = normalizeAppServerEndpoint(rawEndpoint, { codexHome: this.codexHome });
      endpoint.discoveredAt = endpoint.discoveredAt || observedAt;
      endpoint.lastSeenAt = observedAt;
      const failure = endpoint.failure || this.failureForEndpoint(endpoint);
      if (failure) {
        endpoint.failure = failure;
        unreachableObserved.push(endpoint);
      }
      const existing = endpointMap.get(endpoint.id);
      endpointMap.set(endpoint.id, existing ? {
        ...existing,
        ...endpoint,
        label: existing.label,
        source: existing.source,
        discoveredAt: existing.discoveredAt || endpoint.discoveredAt,
        lastSeenAt: endpoint.lastSeenAt,
      } : endpoint);
    }
    for (const rawObservation of observations) {
      const endpoint = normalizeAppServerEndpoint(rawObservation, {
        codexHome: this.codexHome,
        source: rawObservation.source || "observation",
        endpointType: rawObservation.endpointType || "private",
      });
      endpoint.discoveredAt = endpoint.discoveredAt || observedAt;
      endpoint.lastSeenAt = observedAt;
      endpoint.failure = endpoint.failure || this.failureForEndpoint(endpoint) || {
        reason: endpoint.transport === "stdio" ? "private_transport" : "unreachable_observed",
        message: endpoint.transport === "stdio"
          ? "stdio app-server transport is private to its parent process"
          : "observed runtime is not attachable",
      };
      unreachableObserved.push(endpoint);
    }

    const endpointList = [...endpointMap.values()];
    const selectedHistoryEndpoint = this.selectHistoryEndpoint(endpointList);
    const liveEndpoints = endpointList
      .filter(isAttachableOwnerProbeEndpoint)
      .slice(0, APP_SERVER_REGISTRY_LIVE_ENDPOINT_LIMIT);

    this.evictExpiredOwners(observedAtMs);
    this.evictExpiredPrivateOwners(observedAtMs);
    if (privateOwnerRefreshReliable) {
      this.replaceProcessPrivateOwners(privateThreadOwners, observedAt, observedAtMs);
    }
    this.state = {
      lastRefreshAt: observedAt,
      lastRefreshAtMs: observedAtMs,
      selectedHistoryEndpoint,
      endpoints: endpointList,
      liveEndpoints,
      unreachableObserved,
      failedEndpoints,
      duplicateOwners: this.state.duplicateOwners || [],
      error: null,
    };
    this.logger.info("app_server_registry.refresh_complete", {
      reason,
      historySelected: Boolean(selectedHistoryEndpoint),
      liveEndpoints: liveEndpoints.length,
      unreachableObserved: unreachableObserved.length,
      failedEndpoints: failedEndpoints.length,
    });
    return this.snapshot();
  }

  failureForEndpoint(endpoint) {
    if (endpoint.transport === "stdio") {
      return {
        reason: "private_transport",
        message: "stdio app-server transport is private to its parent process",
      };
    }
    if (endpoint.transport === "unix") {
      if (!endpoint.socketPath) {
        return {
          reason: "unix_socket_path_missing",
          message: "Unix app-server endpoint is missing a socket path",
        };
      }
      if (!fs.existsSync(endpoint.socketPath)) {
        return {
          reason: "unix_socket_missing",
          message: "Codex daemon Unix app-server socket is missing",
        };
      }
      return null;
    }
    if (endpoint.transport === "ws" || endpoint.transport === "wss") {
      if (!isLoopbackWebSocketURL(endpoint.url)) {
        return {
          reason: "non_loopback_app_server",
          message: "discovered app-server endpoint is not on loopback",
        };
      }
      return null;
    }
    return {
      reason: "unsupported_transport",
      message: `unsupported app-server transport ${endpoint.transport || "unknown"}`,
    };
  }

  selectHistoryEndpoint(endpoints) {
    const candidates = endpoints
      .filter((endpoint) => endpoint.endpointType === "history")
      .filter((endpoint) => !endpoint.failure)
      .filter((endpoint) => !endpoint.dockOwnedRaw);
    candidates.sort((left, right) => {
      const leftScore = left.transport === "unix" ? 0 : 1;
      const rightScore = right.transport === "unix" ? 0 : 1;
      return leftScore - rightScore || left.label.localeCompare(right.label);
    });
    return candidates[0] || null;
  }

  snapshot() {
    const endpointLimit = APP_SERVER_REGISTRY_STATUS_ENDPOINT_LIMIT;
    return {
      lastRefreshAt: this.state.lastRefreshAt,
      history: this.state.selectedHistoryEndpoint ? sanitizedEndpoint(this.state.selectedHistoryEndpoint) : null,
      counts: {
        endpoints: this.state.endpoints.length,
        liveEndpoints: this.state.liveEndpoints.length,
        unreachableObserved: this.state.unreachableObserved.length,
        failedEndpoints: this.state.failedEndpoints.length,
        threadOwners: this.threadOwnerById.size,
        privateOwners: this.privateOwnerByThreadId.size,
      },
      endpoints: this.state.endpoints.slice(0, endpointLimit).map(sanitizedEndpoint),
      liveEndpoints: this.state.liveEndpoints.slice(0, endpointLimit).map(sanitizedEndpoint),
      unreachableObserved: this.state.unreachableObserved.slice(0, endpointLimit).map(sanitizedEndpoint),
      failedEndpoints: [...this.state.failedEndpoints],
      duplicateOwners: [...(this.state.duplicateOwners || [])],
      error: this.state.error,
    };
  }

  historyEndpoint({ required = false } = {}) {
    if (this.state.selectedHistoryEndpoint) {
      return this.state.selectedHistoryEndpoint;
    }
    if (required) {
      throw new AppServerRegistryRouteError("registry has no valid history app-server endpoint", {
        reason: "history_endpoint_unavailable",
      });
    }
    return null;
  }

  isHistoryEndpoint(endpoint) {
    const history = this.state.selectedHistoryEndpoint;
    return Boolean(
      history
      && endpoint
      && (
        endpoint.id === history.id
        || (
          canonicalEndpointURL(endpoint.url) === canonicalEndpointURL(history.url)
          && (endpoint.bearerToken || null) === (history.bearerToken || null)
        )
      )
    );
  }

  liveEndpoints() {
    return [...this.state.liveEndpoints];
  }

  ownerForThread(threadId) {
    return this.threadOwnerById.get(String(threadId || "")) || null;
  }

  recordPrivateOwner(threadId, observation = {}) {
    if (!threadId) {
      return;
    }
    const checkedAt = nowISOString(this.clock);
    const checkedAtMs = nowMs(this.clock);
    this.privateOwnerByThreadId.set(String(threadId), {
      threadId: String(threadId),
      observedAt: checkedAt,
      checkedAt,
      checkedAtMs,
      observation: {
        source: observation.source || "manual",
        transport: observation.transport || "stdio",
        pid: observation.pid ?? null,
        ppid: observation.ppid ?? null,
        ownerKind: observation.ownerKind || null,
      },
    });
  }

  replaceProcessPrivateOwners(owners = [], observedAt = nowISOString(this.clock), checkedAtMs = nowMs(this.clock)) {
    const observedThreadIds = new Set();
    for (const owner of owners) {
      if (!owner?.threadId) {
        continue;
      }
      const threadId = String(owner.threadId);
      observedThreadIds.add(threadId);
      this.privateOwnerByThreadId.set(threadId, {
        threadId,
        observedAt,
        checkedAt: observedAt,
        checkedAtMs,
        observation: {
          source: "process",
          transport: owner.transport || "stdio",
          pid: owner.pid ?? null,
          ppid: owner.ppid ?? null,
          ownerKind: owner.ownerKind || "codex-cli-resume",
        },
      });
    }
    for (const [threadId, owner] of this.privateOwnerByThreadId.entries()) {
      if (owner?.observation?.source === "process" && !observedThreadIds.has(threadId)) {
        this.privateOwnerByThreadId.delete(threadId);
      }
    }
  }

  privateLiveRows() {
    const now = nowMs(this.clock);
    return [...this.privateOwnerByThreadId.values()]
      .filter((owner) => !owner?.checkedAtMs || now - owner.checkedAtMs <= this.endpointTtlMs)
      .map((owner) => ({
        id: owner.threadId,
        sessionId: owner.threadId,
        source: "cli",
        dockRelayActivitySource: "private-owner-presence",
        activityProofStatus: "status_only",
        activityProofSource: "private-owner-presence",
        status: {
          type: "privateUnattachable",
        },
        dockRelaySource: {
          id: stableID(["private", "stdio", owner.threadId]),
          label: `codex-private:${owner.observation?.pid || owner.threadId.slice(0, 8)}`,
          source: owner.observation?.source || "process",
          endpointType: "private",
          transport: owner.observation?.transport || "stdio",
          url: "stdio://",
          pid: owner.observation?.pid ?? null,
          ppid: owner.observation?.ppid ?? null,
          failure: {
            reason: "private_transport",
            message: "stdio app-server transport is private to its parent process",
          },
        },
      }));
  }

  async historyClient() {
    const endpoint = this.historyEndpoint({ required: true });
    return this.initializedClientForEndpoint(endpoint);
  }

  async initializedClientForEndpoint(endpoint) {
    const client = this.clientFactory
      ? await this.clientFactory(endpoint)
      : new JsonRpcWebSocketClient(endpoint.url, {
          bearerToken: endpoint.bearerToken || null,
          logger: this.logger,
        });
    await client.connect();
    await client.request("initialize", {
      clientInfo: {
        name: "codex_dock_relay",
        title: "Codex Dock Relay",
        version: RELAY_VERSION,
      },
      capabilities: {
        experimentalApi: true,
        requestAttestation: false,
      },
    });
    client.notify("initialized");
    return client;
  }

  async collectLiveRows({ endpoints = this.liveEndpoints() } = {}) {
    const selectedEndpoints = endpoints.slice(0, APP_SERVER_REGISTRY_LIVE_ENDPOINT_LIMIT);
    const results = await allSettledInBatches(
      selectedEndpoints,
      Math.max(1, selectedEndpoints.length),
      (endpoint) => this.readLoadedRowsFromEndpoint(endpoint),
    );
    const rows = [];
    let failedEndpoints = 0;
    let totalThreadReads = 0;
    let failedThreadReads = 0;
    for (let index = 0; index < results.length; index += 1) {
      const result = results[index];
      const endpoint = selectedEndpoints[index];
      if (result.status === "rejected") {
        failedEndpoints += 1;
        this.logger.warn("app_server_registry.live_endpoint_failed", {
          endpointUrl: endpoint.url,
          error: result.reason,
        });
        continue;
      }
      rows.push(...result.value.rows);
      totalThreadReads += result.value.totalThreadReads;
      failedThreadReads += result.value.failedThreadReads;
      this.recordLiveRows(endpoint, result.value.rows);
    }
    return {
      endpoints: selectedEndpoints,
      failedEndpoints,
      totalThreadReads,
      failedThreadReads,
      rows,
    };
  }

  async readLoadedRowsFromEndpoint(endpoint) {
    const client = await this.initializedClientForEndpoint(endpoint);
    try {
      const loaded = await client.request("thread/loaded/list", { limit: LIVE_LOADED_LIST_LIMIT });
      const threadIds = Array.isArray(loaded?.data) ? loaded.data.slice(0, LIVE_LOADED_LIST_LIMIT) : [];
      const results = await allSettledInBatches(
        threadIds,
        LIVE_THREAD_READ_CONCURRENCY,
        (threadId) => client.request("thread/read", {
          threadId,
          includeTurns: false,
        }),
      );
      const rows = [];
      let failedThreadReads = 0;
      for (let index = 0; index < results.length; index += 1) {
        const result = results[index];
        if (result.status === "rejected") {
          failedThreadReads += 1;
          this.logger.warn("app_server_registry.thread_read_failed", {
            endpointUrl: endpoint.url,
            threadId: threadIds[index],
            error: result.reason,
          });
          continue;
        }
        const thread = result.value?.thread;
        if (thread?.id) {
          rows.push({
            ...thread,
            dockRelaySource: endpoint,
          });
        }
      }
      return {
        rows,
        totalThreadReads: threadIds.length,
        failedThreadReads,
      };
    } finally {
      await client.close?.({ reason: "registry_live_read_complete" });
    }
  }

  recordLiveRows(endpoint, rows = []) {
    const checkedAt = nowISOString(this.clock);
    const checkedAtMs = nowMs(this.clock);
    for (const row of rows) {
      if (!row?.id) {
        continue;
      }
      const threadId = String(row.id);
      const candidate = {
        threadId,
        endpoint,
        row,
        checkedAt,
        checkedAtMs,
      };
      const existing = this.threadOwnerById.get(threadId);
      const winner = preferLiveOwner(candidate, existing);
      if (existing && winner !== existing && existing.endpoint?.id !== endpoint.id) {
        this.state.duplicateOwners = [
          ...(this.state.duplicateOwners || []),
          {
            threadId,
            previousEndpointId: existing.endpoint?.id || null,
            winnerEndpointId: endpoint.id,
            observedAt: checkedAt,
          },
        ].slice(-50);
      }
      this.threadOwnerById.set(threadId, winner);
    }
  }

  evictExpiredOwners(now = nowMs(this.clock)) {
    for (const [threadId, owner] of this.threadOwnerById.entries()) {
      if (owner?.checkedAtMs && now - owner.checkedAtMs > this.endpointTtlMs) {
        this.threadOwnerById.delete(threadId);
      }
    }
  }

  evictExpiredPrivateOwners(now = nowMs(this.clock)) {
    for (const [threadId, owner] of this.privateOwnerByThreadId.entries()) {
      if (owner?.checkedAtMs && now - owner.checkedAtMs > this.endpointTtlMs) {
        this.privateOwnerByThreadId.delete(threadId);
      }
    }
  }

  routeForThreadMethod(method, threadId, options = {}) {
    if (options.activeSessionEndpoint) {
      return {
        source: "active-session",
        endpoint: options.activeSessionEndpoint,
        method,
        threadId,
      };
    }
    if (ACTIVE_SESSION_ONLY_METHODS.has(method)) {
      throw new AppServerRegistryRouteError(`${method} requires an active session upstream`, {
        reason: "active_session_required",
        method,
        threadId,
      });
    }
    const owner = this.ownerForThread(threadId);
    if (owner && LIVE_OWNER_PREFERRED_METHODS.has(method)) {
      return {
        source: "live-owner",
        endpoint: owner.endpoint,
        method,
        threadId,
      };
    }
    const privateOwner = this.privateOwnerByThreadId.get(String(threadId || ""));
    if (
      privateOwner
      && !owner
      && !(options.allowHistoryForPrivateOwner && HISTORY_SAFE_PRIVATE_OWNER_METHODS.has(method))
    ) {
      throw new AppServerRegistryRouteError(`thread ${threadId} is owned by a private Codex runtime`, {
        reason: "private_owner_unattachable",
        method,
        threadId,
      });
    }
    if (HISTORY_ROUTE_METHODS.has(method) || LIVE_OWNER_PREFERRED_METHODS.has(method)) {
      return {
        source: "history",
        endpoint: this.historyEndpoint({ required: true }),
        method,
        threadId,
      };
    }
    throw new AppServerRegistryRouteError(`no registry route for ${method}`, {
      reason: "unsupported_method",
      method,
      threadId,
    });
  }
}

export {
  AppServerRegistry,
  AppServerRegistryRouteError,
  daemonSocketPathForCodexHome,
  daemonUnixURLForCodexHome,
  discoverAppServerEndpointsFromProcesses,
  normalizeAppServerEndpoint,
  tokenizeCommandLine,
};

import { sanitizeFields } from "./dock-relay-logger.mjs";

function sanitizedField(name, value) {
  return sanitizeFields({ [name]: value })[name];
}

function safeErrorSummary(error, extra = {}) {
  return sanitizeFields({
    ...extra,
    message: error?.message || String(error),
    code: error?.code || null,
  });
}

function projectLiveStatus(liveStatus = null) {
  const overlay = liveStatus?.liveOverlay || null;
  return sanitizeFields({
    checkedAt: liveStatus?.checkedAt || null,
    status: liveStatus?.status || "unknown",
    ok: liveStatus?.ok ?? null,
    ageMs: overlay?.ageMs ?? null,
    overlayState: overlay?.state || null,
    endpoints: Array.isArray(liveStatus?.endpoints) ? liveStatus.endpoints.length : 0,
    failedEndpoints: liveStatus?.failedEndpoints || 0,
    rows: Array.isArray(liveStatus?.rows) ? liveStatus.rows.length : 0,
    error: liveStatus?.error || null,
  });
}

function projectAppServerRegistryStatus(registry = null) {
  if (!registry?.snapshot) {
    return sanitizeFields({
      status: "missing",
      ok: false,
      history: null,
      counts: {
        endpoints: 0,
        liveEndpoints: 0,
        unreachableObserved: 0,
        failedEndpoints: 0,
        threadOwners: 0,
        privateOwners: 0,
      },
      endpoints: [],
      liveEndpoints: [],
      unreachableObserved: [],
      failedEndpoints: [],
      duplicateOwners: [],
    });
  }
  const snapshot = registry.snapshot();
  return sanitizeFields({
    status: snapshot.history ? "ready" : "degraded",
    ok: Boolean(snapshot.history),
    ...snapshot,
  });
}

function createRelayStatusTracker({ clock = () => new Date() } = {}) {
  const startedAt = clock();
  let lastLiveDiscoveryResult = {
    checkedAt: null,
    status: "unknown",
    ok: null,
  };
  let lastUpstreamError = null;
  let lastClientFacingError = null;
  let lastTranscriptionError = null;
  let reconnect = {
    active: false,
    attempts: 0,
    nextRetryAt: null,
  };
  const requests = {
    total: 0,
    succeeded: 0,
    failed: 0,
    byMethod: new Map(),
  };

  function timestamp() {
    const value = clock();
    return value instanceof Date ? value.toISOString() : new Date(value).toISOString();
  }

  function recordLiveDiscovery(result) {
    lastLiveDiscoveryResult = {
      checkedAt: timestamp(),
      ...sanitizeFields(result),
    };
  }

  function recordUpstreamError(error, context = {}) {
    lastUpstreamError = {
      at: timestamp(),
      ...safeErrorSummary(error, context),
    };
  }

  function recordClientFacingError(error, context = {}) {
    lastClientFacingError = {
      at: timestamp(),
      ...safeErrorSummary(error, context),
    };
  }

  function recordTranscriptionError(error, context = {}) {
    lastTranscriptionError = {
      at: timestamp(),
      ...safeErrorSummary(error, context),
    };
  }

  function recordReconnect({ active, attempts, nextRetryAt = null }) {
    reconnect = sanitizeFields({
      active: Boolean(active),
      attempts: Number(attempts || 0),
      nextRetryAt,
    });
  }

  function recordRequest({ method, ok, code = null, durationMs = null }) {
    const key = String(method || "unknown");
    const existing = requests.byMethod.get(key) || {
      method: key,
      total: 0,
      succeeded: 0,
      failed: 0,
      lastCode: null,
      lastDurationMs: null,
      totalDurationMs: 0,
    };
    existing.total += 1;
    existing.lastCode = code;
    existing.lastDurationMs = Number.isFinite(durationMs) ? Math.max(0, Math.floor(durationMs)) : null;
    if (existing.lastDurationMs !== null) {
      existing.totalDurationMs += existing.lastDurationMs;
    }
    if (ok) {
      existing.succeeded += 1;
      requests.succeeded += 1;
    } else {
      existing.failed += 1;
      requests.failed += 1;
    }
    requests.total += 1;
    requests.byMethod.set(key, existing);
  }

  function requestMetrics() {
    const byMethod = [...requests.byMethod.values()]
      .sort((lhs, rhs) => lhs.method.localeCompare(rhs.method))
      .map((entry) => ({
        method: entry.method,
        total: entry.total,
        succeeded: entry.succeeded,
        failed: entry.failed,
        lastCode: entry.lastCode,
        lastDurationMs: entry.lastDurationMs,
        avgDurationMs: entry.total > 0 ? Math.round(entry.totalDurationMs / entry.total) : null,
      }));
    return {
      total: requests.total,
      succeeded: requests.succeeded,
      failed: requests.failed,
      byMethod,
    };
  }

  function uptimeSeconds() {
    const now = clock();
    const nowMs = now instanceof Date ? now.getTime() : new Date(now).getTime();
    const startedMs = startedAt instanceof Date ? startedAt.getTime() : new Date(startedAt).getTime();
    return Math.max(0, Math.floor((nowMs - startedMs) / 1000));
  }

  function snapshot(config, runtime = {}) {
    const endpointHost = (() => {
      try {
        return new URL(config.openAIRealtimeTranscriptionEndpoint).hostname;
      } catch {
        return null;
      }
    })();
    const observability = config.observability?.statusSnapshot?.() || null;
    const snapshot = sanitizeFields({
      ok: true,
      service: "codex-dock-relay",
      version: config.version,
      host: {
        id: config.hostId || null,
        relayInstanceID: config.hostId || null,
        displayName: config.hostName || config.bonjourName || null,
      },
      uptimeSeconds: uptimeSeconds(),
      listen: {
        host: config.listenHost,
        port: config.port,
      },
      appServerRegistry: projectAppServerRegistryStatus(config.appServerRegistry),
      auth: {
        phoneAuth: config.phoneAuth,
        relayCredentialConfigured: Boolean(config.relayBearerToken),
      },
      transcription: {
        enabled: Boolean(config.openAIAPIKey),
        model: config.openAIRealtimeTranscriptionModel || null,
        endpointHost,
        keyPresent: Boolean(config.openAIAPIKey),
        lastError: lastTranscriptionError,
      },
      liveDiscovery: lastLiveDiscoveryResult,
      liveStatus: projectLiveStatus(runtime.liveStatus),
      state: runtime.relayState || null,
      connections: {
        downstreamActive: runtime.downstreamActive || 0,
        upstreamActive: runtime.upstreamActive || 0,
        upstreamPools: Array.isArray(runtime.upstreamPools) ? runtime.upstreamPools : [],
      },
      errors: {
        lastUpstreamError,
        lastClientFacingError,
      },
      reconnect,
    });
    snapshot.routes = observability?.routes || [];
    snapshot.appCriticalFailures = observability?.appCriticalFailures || [];
    return snapshot;
  }

  function metricsSnapshot(config, runtime = {}) {
    const observabilityMetrics = config.observability?.metricsSnapshot?.() || null;
    const snapshot = sanitizeFields({
      ok: true,
      service: "codex-dock-relay",
      version: config.version,
      host: {
        id: config.hostId || null,
        relayInstanceID: config.hostId || null,
        displayName: config.hostName || config.bonjourName || null,
      },
      uptimeSeconds: uptimeSeconds(),
      appServerRegistry: projectAppServerRegistryStatus(config.appServerRegistry),
      liveStatus: projectLiveStatus(runtime.liveStatus),
      state: runtime.relayState?.counts || null,
      connections: {
        downstreamActive: runtime.downstreamActive || 0,
        upstreamActive: runtime.upstreamActive || 0,
        upstreamPools: Array.isArray(runtime.upstreamPools) ? runtime.upstreamPools : [],
      },
      requests: observabilityMetrics?.requests || requestMetrics(),
      reconnect,
    });
    snapshot.routeMetrics = observabilityMetrics?.routes || [];
    return snapshot;
  }

  function debugSessionsSnapshot(config, runtime = {}) {
    const traces = config.observability?.recentTraces?.({ limit: 10 }) || [];
    return sanitizeFields({
      ok: true,
      service: "codex-dock-relay",
      version: config.version,
      host: {
        id: config.hostId || null,
        relayInstanceID: config.hostId || null,
        displayName: config.hostName || config.bonjourName || null,
      },
      liveStatus: projectLiveStatus(runtime.liveStatus),
      state: runtime.relayState || null,
      liveRows: Array.isArray(runtime.liveRows) ? runtime.liveRows : [],
      sessions: Array.isArray(runtime.sessions) ? runtime.sessions : [],
      connections: {
        downstreamActive: runtime.downstreamActive || 0,
        upstreamActive: runtime.upstreamActive || 0,
        upstreamPools: Array.isArray(runtime.upstreamPools) ? runtime.upstreamPools : [],
      },
      errors: {
        lastUpstreamError,
        lastClientFacingError,
      },
      reconnect,
      recentOperationIDs: traces.map((trace) => trace.operationID).filter(Boolean),
    });
  }

  return {
    debugSessionsSnapshot,
    metricsSnapshot,
    recordClientFacingError,
    recordLiveDiscovery,
    recordRequest,
    recordReconnect,
    recordTranscriptionError,
    recordUpstreamError,
    snapshot,
  };
}

function classifyRelayRequestError(method, error) {
  if (error?.code === -32043 && error?.data) {
    return {
      subsystem: "human-filter",
      retryable: false,
      ...error.data,
    };
  }
  if (error?.code === -32001) {
    return {
      subsystem: "upstream-overload",
      retryable: true,
      overload: true,
    };
  }
  if (error?.data?.subsystem) {
    return {
      ...error.data,
      retryable: error.data.retryable ?? error.code !== -32602,
    };
  }
  if (method === "thread/detail/resync"
    || method === "thread/archive" || method === "thread/unarchive" || method === "thread/name/set") {
    return {
      subsystem: "history",
      retryable: true,
    };
  }
  if (method === "thread/detail/subscribe" || method === "turn/start" || method === "turn/steer" || method === "turn/interrupt") {
    return {
      subsystem: "live-upstream",
      retryable: true,
    };
  }
  if (String(method || "").startsWith("audio/transcription/")) {
    return {
      subsystem: "transcription",
      retryable: error?.code !== -32602,
    };
  }
  return undefined;
}

export {
  classifyRelayRequestError,
  createRelayStatusTracker,
  projectAppServerRegistryStatus,
  projectLiveStatus,
  sanitizedField,
};

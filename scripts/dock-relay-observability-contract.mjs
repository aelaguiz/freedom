const ROUTE_STATUS = Object.freeze({
  UNKNOWN: "unknown",
  HEALTHY: "healthy",
  DEGRADED: "degraded",
  FAILED: "failed",
  STALE: "stale",
  PARTIAL: "partial",
  BLOCKED: "blocked",
});

const FAILURE_CATEGORY = Object.freeze({
  NONE: "none",
  DOWNSTREAM: "downstream",
  HISTORY: "history",
  LIVE_UPSTREAM: "live-upstream",
  TRANSCRIPTION: "transcription",
  UPSTREAM_OVERLOAD: "upstream-overload",
  PAYLOAD_SERIALIZATION: "payload.serialization",
  TIMEOUT: "timeout",
  CANCELLED: "cancelled",
  VALIDATION: "validation",
  UNSUPPORTED: "unsupported",
  RELAY: "relay",
});

const PROBE_SAFETY = Object.freeze({
  PROCESS_ONLY: "process-only",
  AUTO_PROBE_SAFE: "auto-probe-safe",
  MANUAL_ONLY: "manual-only",
  PASSIVE_ONLY: "passive-only",
});

const ROUTE_NAMES = Object.freeze({
  readyz: "readyz",
  healthz: "healthz",
  statusz: "statusz",
  metricsz: "metricsz",
  routesz: "routesz",
  syncz: "syncz",
  initialize: "initialize",
  initialized: "initialized",
  threadDetailSubscribe: "thread/detail/subscribe",
  threadDetailResync: "thread/detail/resync",
  threadDetailUpdate: "thread/detail/update",
  threadArchive: "thread/archive",
  threadUnarchive: "thread/unarchive",
  threadNameSet: "thread/name/set",
  dockSubscribe: "dock/subscribe",
  dockUpdate: "dock/update",
  dockResync: "dock/resync",
  archiveSubscribe: "archive/subscribe",
  archiveUpdate: "archive/update",
  archiveResync: "archive/resync",
  turnStart: "turn/start",
  turnSteer: "turn/steer",
  turnInterrupt: "turn/interrupt",
  audioTranscriptionStart: "audio/transcription/start",
  audioTranscriptionAppend: "audio/transcription/append",
  audioTranscriptionCommit: "audio/transcription/commit",
  audioTranscriptionCancel: "audio/transcription/cancel",
  audioTranscriptionDelta: "audio/transcription/delta",
  audioTranscriptionCompleted: "audio/transcription/completed",
  audioTranscriptionFailed: "audio/transcription/failed",
  audioTranscriptionCanceled: "audio/transcription/canceled",
  audioTranscriptionClosed: "audio/transcription/closed",
});

function route({
  name,
  kind,
  probeSafety,
  appCritical = false,
  budgetMs = null,
  payloadPolicy = "summary-only",
  parentRoute = null,
}) {
  return Object.freeze({
    name,
    kind,
    probeSafety,
    appCritical,
    budgetMs,
    payloadPolicy,
    parentRoute,
  });
}

const ROUTE_CONFIGS = Object.freeze({
  [ROUTE_NAMES.readyz]: route({
    name: ROUTE_NAMES.readyz,
    kind: "http",
    probeSafety: PROBE_SAFETY.PROCESS_ONLY,
    payloadPolicy: "process-health",
  }),
  [ROUTE_NAMES.healthz]: route({
    name: ROUTE_NAMES.healthz,
    kind: "http",
    probeSafety: PROBE_SAFETY.PROCESS_ONLY,
    payloadPolicy: "process-config-health",
  }),
  [ROUTE_NAMES.statusz]: route({
    name: ROUTE_NAMES.statusz,
    kind: "http",
    probeSafety: PROBE_SAFETY.AUTO_PROBE_SAFE,
    payloadPolicy: "route-health-summary",
  }),
  [ROUTE_NAMES.metricsz]: route({
    name: ROUTE_NAMES.metricsz,
    kind: "http",
    probeSafety: PROBE_SAFETY.AUTO_PROBE_SAFE,
    payloadPolicy: "metrics-summary",
  }),
  [ROUTE_NAMES.routesz]: route({
    name: ROUTE_NAMES.routesz,
    kind: "http",
    probeSafety: PROBE_SAFETY.AUTO_PROBE_SAFE,
    payloadPolicy: "full-route-health",
  }),
  [ROUTE_NAMES.syncz]: route({
    name: ROUTE_NAMES.syncz,
    kind: "http",
    probeSafety: PROBE_SAFETY.AUTO_PROBE_SAFE,
    payloadPolicy: "process-sync-health",
  }),
  [ROUTE_NAMES.initialize]: route({
    name: ROUTE_NAMES.initialize,
    kind: "json-rpc",
    probeSafety: PROBE_SAFETY.AUTO_PROBE_SAFE,
    appCritical: true,
    budgetMs: 5_000,
  }),
  [ROUTE_NAMES.initialized]: route({
    name: ROUTE_NAMES.initialized,
    kind: "json-rpc-notification",
    probeSafety: PROBE_SAFETY.PASSIVE_ONLY,
    parentRoute: ROUTE_NAMES.initialize,
  }),
  [ROUTE_NAMES.threadDetailSubscribe]: route({
    name: ROUTE_NAMES.threadDetailSubscribe,
    kind: "json-rpc",
    probeSafety: PROBE_SAFETY.PASSIVE_ONLY,
    appCritical: true,
    budgetMs: 15_000,
    payloadPolicy: "thread-detail-projection-summary",
  }),
  [ROUTE_NAMES.threadDetailResync]: route({
    name: ROUTE_NAMES.threadDetailResync,
    kind: "json-rpc",
    probeSafety: PROBE_SAFETY.MANUAL_ONLY,
    appCritical: true,
    budgetMs: 15_000,
    payloadPolicy: "thread-detail-projection-summary",
  }),
  [ROUTE_NAMES.threadDetailUpdate]: route({
    name: ROUTE_NAMES.threadDetailUpdate,
    kind: "json-rpc-notification",
    probeSafety: PROBE_SAFETY.PASSIVE_ONLY,
    appCritical: true,
    parentRoute: ROUTE_NAMES.threadDetailSubscribe,
    payloadPolicy: "thread-detail-projection-summary",
  }),
  [ROUTE_NAMES.threadArchive]: route({
    name: ROUTE_NAMES.threadArchive,
    kind: "json-rpc",
    probeSafety: PROBE_SAFETY.PASSIVE_ONLY,
    appCritical: true,
    budgetMs: 10_000,
  }),
  [ROUTE_NAMES.threadUnarchive]: route({
    name: ROUTE_NAMES.threadUnarchive,
    kind: "json-rpc",
    probeSafety: PROBE_SAFETY.PASSIVE_ONLY,
    appCritical: true,
    budgetMs: 10_000,
  }),
  [ROUTE_NAMES.threadNameSet]: route({
    name: ROUTE_NAMES.threadNameSet,
    kind: "json-rpc",
    probeSafety: PROBE_SAFETY.PASSIVE_ONLY,
    appCritical: true,
    budgetMs: 10_000,
  }),
  [ROUTE_NAMES.dockSubscribe]: route({
    name: ROUTE_NAMES.dockSubscribe,
    kind: "json-rpc",
    probeSafety: PROBE_SAFETY.AUTO_PROBE_SAFE,
    appCritical: true,
    budgetMs: 15_000,
    payloadPolicy: "thread-card-summary",
  }),
  [ROUTE_NAMES.dockUpdate]: route({
    name: ROUTE_NAMES.dockUpdate,
    kind: "json-rpc-notification",
    probeSafety: PROBE_SAFETY.PASSIVE_ONLY,
    appCritical: true,
    parentRoute: ROUTE_NAMES.dockSubscribe,
    payloadPolicy: "thread-card-summary",
  }),
  [ROUTE_NAMES.dockResync]: route({
    name: ROUTE_NAMES.dockResync,
    kind: "json-rpc",
    probeSafety: PROBE_SAFETY.AUTO_PROBE_SAFE,
    appCritical: true,
    budgetMs: 15_000,
    payloadPolicy: "thread-card-summary",
  }),
  [ROUTE_NAMES.archiveSubscribe]: route({
    name: ROUTE_NAMES.archiveSubscribe,
    kind: "json-rpc",
    probeSafety: PROBE_SAFETY.AUTO_PROBE_SAFE,
    appCritical: true,
    budgetMs: 15_000,
    payloadPolicy: "thread-card-summary",
  }),
  [ROUTE_NAMES.archiveUpdate]: route({
    name: ROUTE_NAMES.archiveUpdate,
    kind: "json-rpc-notification",
    probeSafety: PROBE_SAFETY.PASSIVE_ONLY,
    appCritical: true,
    parentRoute: ROUTE_NAMES.archiveSubscribe,
    payloadPolicy: "thread-card-summary",
  }),
  [ROUTE_NAMES.archiveResync]: route({
    name: ROUTE_NAMES.archiveResync,
    kind: "json-rpc",
    probeSafety: PROBE_SAFETY.AUTO_PROBE_SAFE,
    appCritical: true,
    budgetMs: 15_000,
    payloadPolicy: "thread-card-summary",
  }),
  [ROUTE_NAMES.turnStart]: route({
    name: ROUTE_NAMES.turnStart,
    kind: "json-rpc",
    probeSafety: PROBE_SAFETY.PASSIVE_ONLY,
    appCritical: true,
    budgetMs: 30_000,
  }),
  [ROUTE_NAMES.turnSteer]: route({
    name: ROUTE_NAMES.turnSteer,
    kind: "json-rpc",
    probeSafety: PROBE_SAFETY.PASSIVE_ONLY,
    appCritical: true,
    budgetMs: 10_000,
  }),
  [ROUTE_NAMES.turnInterrupt]: route({
    name: ROUTE_NAMES.turnInterrupt,
    kind: "json-rpc",
    probeSafety: PROBE_SAFETY.PASSIVE_ONLY,
    appCritical: true,
    budgetMs: 10_000,
  }),
  [ROUTE_NAMES.audioTranscriptionStart]: route({
    name: ROUTE_NAMES.audioTranscriptionStart,
    kind: "json-rpc",
    probeSafety: PROBE_SAFETY.PASSIVE_ONLY,
    appCritical: true,
    budgetMs: 10_000,
    payloadPolicy: "content-omitted",
  }),
  [ROUTE_NAMES.audioTranscriptionAppend]: route({
    name: ROUTE_NAMES.audioTranscriptionAppend,
    kind: "json-rpc",
    probeSafety: PROBE_SAFETY.PASSIVE_ONLY,
    appCritical: true,
    budgetMs: 10_000,
    payloadPolicy: "content-omitted",
  }),
  [ROUTE_NAMES.audioTranscriptionCommit]: route({
    name: ROUTE_NAMES.audioTranscriptionCommit,
    kind: "json-rpc",
    probeSafety: PROBE_SAFETY.PASSIVE_ONLY,
    appCritical: true,
    budgetMs: 10_000,
    payloadPolicy: "content-omitted",
  }),
  [ROUTE_NAMES.audioTranscriptionCancel]: route({
    name: ROUTE_NAMES.audioTranscriptionCancel,
    kind: "json-rpc",
    probeSafety: PROBE_SAFETY.PASSIVE_ONLY,
    appCritical: true,
    budgetMs: 10_000,
    payloadPolicy: "content-omitted",
  }),
  [ROUTE_NAMES.audioTranscriptionDelta]: route({
    name: ROUTE_NAMES.audioTranscriptionDelta,
    kind: "json-rpc-notification",
    probeSafety: PROBE_SAFETY.PASSIVE_ONLY,
    appCritical: true,
    parentRoute: ROUTE_NAMES.audioTranscriptionStart,
    payloadPolicy: "content-omitted",
  }),
  [ROUTE_NAMES.audioTranscriptionCompleted]: route({
    name: ROUTE_NAMES.audioTranscriptionCompleted,
    kind: "json-rpc-notification",
    probeSafety: PROBE_SAFETY.PASSIVE_ONLY,
    appCritical: true,
    parentRoute: ROUTE_NAMES.audioTranscriptionStart,
    payloadPolicy: "content-omitted",
  }),
  [ROUTE_NAMES.audioTranscriptionFailed]: route({
    name: ROUTE_NAMES.audioTranscriptionFailed,
    kind: "json-rpc-notification",
    probeSafety: PROBE_SAFETY.PASSIVE_ONLY,
    appCritical: true,
    parentRoute: ROUTE_NAMES.audioTranscriptionStart,
    payloadPolicy: "content-omitted",
  }),
  [ROUTE_NAMES.audioTranscriptionCanceled]: route({
    name: ROUTE_NAMES.audioTranscriptionCanceled,
    kind: "json-rpc-notification",
    probeSafety: PROBE_SAFETY.PASSIVE_ONLY,
    appCritical: true,
    parentRoute: ROUTE_NAMES.audioTranscriptionStart,
    payloadPolicy: "content-omitted",
  }),
  [ROUTE_NAMES.audioTranscriptionClosed]: route({
    name: ROUTE_NAMES.audioTranscriptionClosed,
    kind: "json-rpc-notification",
    probeSafety: PROBE_SAFETY.PASSIVE_ONLY,
    appCritical: true,
    parentRoute: ROUTE_NAMES.audioTranscriptionStart,
    payloadPolicy: "content-omitted",
  }),
});

const OBSERVABILITY_CONTRACT = Object.freeze({
  schema: "codexdock.observabilityContract.v1",
  routeStatuses: Object.values(ROUTE_STATUS),
  failureCategories: Object.values(FAILURE_CATEGORY),
  probeSafety: Object.values(PROBE_SAFETY),
  routes: ROUTE_CONFIGS,
});

function routeConfigFor(routeName) {
  const name = String(routeName || "");
  return ROUTE_CONFIGS[name] || route({
    name,
    kind: "json-rpc",
    probeSafety: PROBE_SAFETY.MANUAL_ONLY,
    appCritical: false,
  });
}

function allRouteConfigs() {
  return Object.values(ROUTE_CONFIGS).sort((lhs, rhs) => lhs.name.localeCompare(rhs.name));
}

function autoProbeSafeRoutes() {
  return allRouteConfigs().filter((config) => config.probeSafety === PROBE_SAFETY.AUTO_PROBE_SAFE);
}

function assertAutoProbeRoute(routeName) {
  const config = routeConfigFor(routeName);
  if (config.probeSafety !== PROBE_SAFETY.AUTO_PROBE_SAFE) {
    throw new Error(`${routeName} is ${config.probeSafety}; automatic probes may only call auto-probe-safe routes`);
  }
}

export {
  FAILURE_CATEGORY,
  OBSERVABILITY_CONTRACT,
  PROBE_SAFETY,
  ROUTE_CONFIGS,
  ROUTE_NAMES,
  ROUTE_STATUS,
  allRouteConfigs,
  assertAutoProbeRoute,
  autoProbeSafeRoutes,
  routeConfigFor,
};

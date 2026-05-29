import http from "node:http";
import https from "node:https";

import { sanitizeFields } from "./dock-relay-logger.mjs";

const DEFAULT_HEALTH_TIMEOUT_MS = 500;

function sanitizedField(name, value) {
  return sanitizeFields({ [name]: value })[name];
}

function rawHealthURLForHistoryURL(historyUrl) {
  const url = new URL(historyUrl);
  url.protocol = url.protocol === "wss:" ? "https:" : "http:";
  url.pathname = "/readyz";
  url.search = "";
  url.hash = "";
  url.username = "";
  url.password = "";
  return url.toString();
}

function getJSON(url, timeoutMs = DEFAULT_HEALTH_TIMEOUT_MS) {
  const client = url.startsWith("https:") ? https : http;
  return new Promise((resolve, reject) => {
    const request = client.get(url, { timeout: timeoutMs }, (response) => {
      const chunks = [];
      response.on("data", (chunk) => chunks.push(chunk));
      response.on("end", () => {
        const body = Buffer.concat(chunks).toString("utf8");
        let parsed = null;
        if (body) {
          try {
            parsed = JSON.parse(body);
          } catch {
            parsed = null;
          }
        }
        resolve({
          statusCode: response.statusCode,
          ok: response.statusCode >= 200 && response.statusCode < 300,
          body: parsed,
        });
      });
    });
    request.on("timeout", () => {
      request.destroy(new Error(`timed out after ${timeoutMs}ms`));
    });
    request.on("error", reject);
  });
}

function safeErrorSummary(error, extra = {}) {
  return sanitizeFields({
    ...extra,
    message: error?.message || String(error),
    code: error?.code || null,
  });
}

function createRelayStatusTracker({ clock = () => new Date() } = {}) {
  const startedAt = clock();
  let lastRawAppServerHealth = {
    checkedAt: null,
    status: "unknown",
    ok: null,
  };
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

  function timestamp() {
    const value = clock();
    return value instanceof Date ? value.toISOString() : new Date(value).toISOString();
  }

  function recordRawHealth(result) {
    lastRawAppServerHealth = {
      checkedAt: timestamp(),
      ...sanitizeFields(result),
    };
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

  function snapshot(config, runtime = {}) {
    const now = clock();
    const nowMs = now instanceof Date ? now.getTime() : new Date(now).getTime();
    const startedMs = startedAt instanceof Date ? startedAt.getTime() : new Date(startedAt).getTime();
    const endpointHost = (() => {
      try {
        return new URL(config.openAIRealtimeTranscriptionEndpoint).hostname;
      } catch {
        return null;
      }
    })();
    return sanitizeFields({
      ok: true,
      service: "codex-dock-relay",
      version: config.version,
      host: {
        id: config.hostId || null,
        displayName: config.hostName || config.bonjourName || null,
      },
      uptimeSeconds: Math.max(0, Math.floor((nowMs - startedMs) / 1000)),
      listen: {
        host: config.listenHost,
        port: config.port,
      },
      history: {
        url: config.historyUrl,
        lastHealth: lastRawAppServerHealth,
      },
      auth: {
        phoneAuth: config.phoneAuth,
        relayCredentialConfigured: Boolean(config.relayBearerToken),
        historyCredentialConfigured: Boolean(config.historyBearerToken),
      },
      transcription: {
        enabled: Boolean(config.openAIAPIKey),
        model: config.openAIRealtimeTranscriptionModel || null,
        endpointHost,
        keyPresent: Boolean(config.openAIAPIKey),
        lastError: lastTranscriptionError,
      },
      liveDiscovery: lastLiveDiscoveryResult,
      connections: {
        downstreamActive: runtime.downstreamActive || 0,
        upstreamActive: runtime.upstreamActive || 0,
      },
      errors: {
        lastUpstreamError,
        lastClientFacingError,
      },
      reconnect,
    });
  }

  return {
    recordClientFacingError,
    recordLiveDiscovery,
    recordRawHealth,
    recordReconnect,
    recordTranscriptionError,
    recordUpstreamError,
    snapshot,
  };
}

async function checkRawAppServerHealth(config, tracker) {
  const healthURL = rawHealthURLForHistoryURL(config.historyUrl);
  try {
    const result = await getJSON(healthURL);
    tracker.recordRawHealth({
      status: result.ok ? "up" : "down",
      ok: result.ok,
      statusCode: result.statusCode,
      url: healthURL,
    });
  } catch (error) {
    tracker.recordRawHealth({
      status: "down",
      ok: false,
      url: healthURL,
      error,
    });
  }
}

function classifyRelayRequestError(method, error) {
  if (error?.code === -32001) {
    return {
      subsystem: "upstream-overload",
      retryable: true,
      overload: true,
    };
  }
  if (method === "thread/list" || method === "thread/read" || method === "thread/turns/list"
    || method === "thread/archive" || method === "thread/unarchive") {
    return {
      subsystem: "history",
      retryable: true,
    };
  }
  if (method === "thread/resume" || method === "turn/start" || method === "turn/steer" || method === "turn/interrupt") {
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
  checkRawAppServerHealth,
  classifyRelayRequestError,
  createRelayStatusTracker,
  rawHealthURLForHistoryURL,
  sanitizedField,
};

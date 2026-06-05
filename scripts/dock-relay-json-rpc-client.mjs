import path from "node:path";

import WebSocket from "ws";

import {
  JSON_RPC_MAX_MESSAGE_BYTES,
  UPSTREAM_CLOSE_TIMEOUT_MS,
  UPSTREAM_CONNECT_TIMEOUT_MS,
  UPSTREAM_REQUEST_TIMEOUT_MS,
} from "./dock-relay-constants.mjs";

function unixSocketPathFromURL(value, { basePath = process.cwd() } = {}) {
  const raw = String(value || "");
  if (!raw.startsWith("unix://")) {
    throw new Error(`not a unix app-server URL: ${raw}`);
  }
  let socketPath = raw.slice("unix://".length);
  const queryIndex = socketPath.search(/[?#]/u);
  if (queryIndex >= 0) {
    socketPath = socketPath.slice(0, queryIndex);
  }
  if (!socketPath) {
    throw new Error(`unix app-server URL is missing a socket path: ${raw}`);
  }
  if (!path.isAbsolute(socketPath)) {
    socketPath = path.resolve(basePath, socketPath);
  }
  if (!socketPath || socketPath === "/") {
    throw new Error(`unix app-server URL is missing a socket path: ${raw}`);
  }
  return socketPath;
}

function webSocketURLForEndpoint(value) {
  const raw = typeof value === "object" && value !== null ? value.url : value;
  const url = String(raw || "");
  if (url.startsWith("unix://")) {
    // The `ws` package accepts IPC sockets as `ws+unix:<socketPath>:<requestPath>`.
    return `ws+unix:${unixSocketPathFromURL(url)}:/`;
  }
  return url;
}

function transportForEndpointURL(value) {
  const url = String(value || "");
  const match = url.match(/^([A-Za-z][A-Za-z0-9+.-]*):/u);
  return match ? match[1].toLowerCase() : "unknown";
}

function normalizeJsonRpcWebSocketEndpoint(value) {
  if (typeof value === "object" && value !== null) {
    if (!value.url) {
      throw new Error("JSON-RPC endpoint descriptor is missing url");
    }
    return {
      ...value,
      url: String(value.url),
      transport: value.transport || transportForEndpointURL(value.url),
      webSocketURL: webSocketURLForEndpoint(value.url),
    };
  }
  return {
    url: String(value || ""),
    transport: transportForEndpointURL(value),
    webSocketURL: webSocketURLForEndpoint(value),
  };
}

class JsonRpcUpstreamError extends Error {
  constructor(method, upstreamError) {
    const message = upstreamError?.message || "upstream JSON-RPC error";
    super(`${method}: ${message}`);
    this.name = "JsonRpcUpstreamError";
    this.method = method;
    this.code = Number.isInteger(upstreamError?.code) ? upstreamError.code : -32000;
    this.data = upstreamError?.data;
    this.upstreamError = upstreamError;
  }
}

class JsonRpcWebSocketClient {
  constructor(
    endpoint,
    {
      bearerToken = null,
      timeoutMs = undefined,
      connectTimeoutMs = timeoutMs ?? UPSTREAM_CONNECT_TIMEOUT_MS,
      requestTimeoutMs = timeoutMs ?? UPSTREAM_REQUEST_TIMEOUT_MS,
      onNotification = null,
      onRequest = null,
      onClose = null,
      logger = null,
      perMessageDeflate = false,
    } = {},
    ) {
    const normalizedEndpoint = normalizeJsonRpcWebSocketEndpoint(endpoint);
    this.url = normalizedEndpoint.url;
    this.webSocketURL = normalizedEndpoint.webSocketURL;
    this.transport = normalizedEndpoint.transport;
    this.bearerToken = bearerToken;
    this.connectTimeoutMs = connectTimeoutMs;
    this.requestTimeoutMs = requestTimeoutMs;
    this.onNotification = onNotification;
    this.onRequest = onRequest;
    this.onClose = onClose;
    this.logger = logger;
    this.perMessageDeflate = perMessageDeflate;
    this.nextId = 1;
    this.pending = new Map();
    this.ws = null;
    this.connectPromise = null;
    this.unhealthy = false;
  }

  connect() {
    if (this.ws?.readyState === WebSocket.OPEN) {
      return Promise.resolve();
    }
    if (this.connectPromise) {
      return this.connectPromise;
    }
    const headers = {};
    if (this.bearerToken) {
      headers.Authorization = `Bearer ${this.bearerToken}`;
    }
    const startedAt = Date.now();
    this.logger?.info("upstream.connect_start", {
      url: this.url,
      transport: this.transport,
      bearerConfigured: Boolean(this.bearerToken),
    });
    this.unhealthy = false;
    this.connectPromise = new Promise((resolve, reject) => {
      const ws = new WebSocket(this.webSocketURL, {
        headers,
        maxPayload: JSON_RPC_MAX_MESSAGE_BYTES,
        perMessageDeflate: this.perMessageDeflate,
      });
      const timer = setTimeout(() => {
        this.logger?.warn("upstream.connect_timeout", {
          url: this.url,
          durationMs: Date.now() - startedAt,
        });
        this.unhealthy = true;
        reject(new Error(`timed out connecting to ${this.url}`));
        this.forceCloseWebSocket(ws);
      }, this.connectTimeoutMs);
      ws.on("open", () => {
        clearTimeout(timer);
        this.ws = ws;
        this.logger?.info("upstream.connect_open", {
          url: this.url,
          transport: this.transport,
          durationMs: Date.now() - startedAt,
        });
        resolve();
      });
      ws.on("message", (data) => this.handleMessage(data));
      ws.on("error", (error) => {
        clearTimeout(timer);
        this.unhealthy = true;
        this.rejectAll(error);
        this.logger?.error("upstream.websocket_error", {
          url: this.url,
          error,
        });
        if (!this.ws) {
          reject(error);
        }
      });
      ws.on("close", () => {
        this.rejectAll(new Error(`websocket closed: ${this.url}`));
        if (this.ws === ws) {
          this.ws = null;
        }
        if (this.connectPromise) {
          this.connectPromise = null;
        }
        this.logger?.warn("upstream.websocket_closed", {
          url: this.url,
        });
        this.onClose?.();
      });
    }).finally(() => {
      this.connectPromise = null;
    });
    return this.connectPromise;
  }

  handleMessage(data) {
    let message;
    try {
      message = JSON.parse(data.toString());
    } catch {
      this.logger?.warn("upstream.invalid_json", {
        url: this.url,
        bytes: data?.byteLength,
      });
      return;
    }
    if (message.id !== undefined && this.pending.has(String(message.id))) {
      const pending = this.pending.get(String(message.id));
      this.pending.delete(String(message.id));
      clearTimeout(pending.timer);
      if (message.error) {
        this.logger?.warn("upstream.request_failed", {
          url: this.url,
          method: pending.method,
          durationMs: Date.now() - pending.startedAt,
          code: message.error.code,
        });
        pending.reject(new JsonRpcUpstreamError(pending.method, message.error));
      } else {
        this.logger?.debug("upstream.request_succeeded", {
          url: this.url,
          method: pending.method,
          durationMs: Date.now() - pending.startedAt,
        });
        pending.resolve(message.result);
      }
      return;
    }

    if (message.method && message.id !== undefined) {
      this.onRequest?.(message);
      return;
    }

    if (message.method) {
      this.onNotification?.(message);
    }
  }

  request(method, params = undefined) {
    if (this.unhealthy || !this.ws || this.ws.readyState !== WebSocket.OPEN) {
      this.logger?.warn("upstream.request_rejected", {
        url: this.url,
        method,
        reason: this.unhealthy ? "unhealthy" : "not_connected",
      });
      return Promise.reject(new Error(`not connected: ${this.url}`));
    }
    const id = String(this.nextId);
    this.nextId += 1;
    const payload = { jsonrpc: "2.0", id, method };
    if (params !== undefined) {
      payload.params = params;
    }
    this.ws.send(JSON.stringify(payload));
    const startedAt = Date.now();
    this.logger?.debug("upstream.request_sent", {
      url: this.url,
      method,
      id,
    });
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        this.unhealthy = true;
        this.logger?.warn("upstream.request_timeout", {
          url: this.url,
          method,
          id,
          durationMs: Date.now() - startedAt,
        });
        const error = new Error(`timed out waiting for ${method} from ${this.url}`);
        reject(error);
        this.close({ reason: "request_timeout" }).catch((closeError) => {
          this.logger?.warn("upstream.timeout_close_failed", {
            url: this.url,
            method,
            error: closeError,
          });
        });
      }, this.requestTimeoutMs);
      this.pending.set(id, { method, resolve, reject, timer, startedAt });
    });
  }

  notify(method, params = undefined) {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) {
      return;
    }
    const payload = { jsonrpc: "2.0", method };
    if (params !== undefined) {
      payload.params = params;
    }
    this.ws.send(JSON.stringify(payload));
    this.logger?.debug("upstream.notification_sent", {
      url: this.url,
      method,
    });
  }

  sendRaw(message) {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) {
      return false;
    }
    this.ws.send(typeof message === "string" ? message : JSON.stringify(message));
    return true;
  }

  isOpen() {
    return !this.unhealthy && this.ws?.readyState === WebSocket.OPEN;
  }

  pendingCount() {
    return this.pending.size;
  }

  isUnhealthy() {
    return this.unhealthy;
  }

  forceCloseWebSocket(ws) {
    try {
      if (ws?.readyState === WebSocket.OPEN || ws?.readyState === WebSocket.CONNECTING) {
        ws.close();
      }
      if (ws?.readyState !== WebSocket.CLOSED) {
        ws.terminate();
      }
    } catch {
      // Nothing else can safely happen here; callers already receive the original error.
    }
  }

  close({ forceAfterMs = UPSTREAM_CLOSE_TIMEOUT_MS, reason = "client_close" } = {}) {
    const ws = this.ws;
    this.ws = null;
    this.connectPromise = null;
    if (!ws || ws.readyState === WebSocket.CLOSED) {
      this.rejectAll(new Error(`websocket closed: ${this.url}`));
      return Promise.resolve();
    }
    this.logger?.debug("upstream.close_start", {
      url: this.url,
      reason,
      pending: this.pending.size,
    });
    return new Promise((resolve) => {
      let settled = false;
      const finish = () => {
        if (settled) {
          return;
        }
        settled = true;
        clearTimeout(timer);
        this.rejectAll(new Error(`websocket closed: ${this.url}`));
        resolve();
      };
      const timer = setTimeout(() => {
        this.logger?.warn("upstream.close_forced", {
          url: this.url,
          reason,
          pending: this.pending.size,
        });
        try {
          ws.terminate();
        } finally {
          finish();
        }
      }, forceAfterMs);
      timer.unref?.();
      ws.once("close", finish);
      if (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING) {
        ws.close();
      } else {
        finish();
      }
    });
  }

  rejectAll(error) {
    for (const pending of this.pending.values()) {
      clearTimeout(pending.timer);
      pending.reject(error);
    }
    this.pending.clear();
  }
}

export {
  JsonRpcUpstreamError,
  JsonRpcWebSocketClient,
  normalizeJsonRpcWebSocketEndpoint,
  transportForEndpointURL,
  unixSocketPathFromURL,
  webSocketURLForEndpoint,
};

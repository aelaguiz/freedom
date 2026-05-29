import WebSocket from "ws";

const DEFAULT_TIMEOUT_MS = 5_000;

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
    url,
    {
      bearerToken = null,
      timeoutMs = DEFAULT_TIMEOUT_MS,
      onNotification = null,
      onRequest = null,
      onClose = null,
      logger = null,
    } = {},
  ) {
    this.url = url;
    this.bearerToken = bearerToken;
    this.timeoutMs = timeoutMs;
    this.onNotification = onNotification;
    this.onRequest = onRequest;
    this.onClose = onClose;
    this.logger = logger;
    this.nextId = 1;
    this.pending = new Map();
    this.ws = null;
  }

  connect() {
    if (this.ws) {
      return Promise.resolve();
    }
    const headers = {};
    if (this.bearerToken) {
      headers.Authorization = `Bearer ${this.bearerToken}`;
    }
    const startedAt = Date.now();
    this.logger?.info("upstream.connect_start", {
      url: this.url,
      bearerConfigured: Boolean(this.bearerToken),
    });
    return new Promise((resolve, reject) => {
      const ws = new WebSocket(this.url, { headers });
      const timer = setTimeout(() => {
        this.logger?.warn("upstream.connect_timeout", {
          url: this.url,
          durationMs: Date.now() - startedAt,
        });
        reject(new Error(`timed out connecting to ${this.url}`));
        ws.close();
      }, this.timeoutMs);
      ws.on("open", () => {
        clearTimeout(timer);
        this.ws = ws;
        this.logger?.info("upstream.connect_open", {
          url: this.url,
          durationMs: Date.now() - startedAt,
        });
        resolve();
      });
      ws.on("message", (data) => this.handleMessage(data));
      ws.on("error", (error) => {
        clearTimeout(timer);
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
        this.logger?.warn("upstream.websocket_closed", {
          url: this.url,
        });
        this.onClose?.();
      });
    });
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
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) {
      this.logger?.warn("upstream.request_rejected", {
        url: this.url,
        method,
        reason: "not_connected",
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
        this.logger?.warn("upstream.request_timeout", {
          url: this.url,
          method,
          id,
          durationMs: Date.now() - startedAt,
        });
        reject(new Error(`timed out waiting for ${method} from ${this.url}`));
      }, this.timeoutMs);
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
    return this.ws?.readyState === WebSocket.OPEN;
  }

  close() {
    if (this.ws) {
      this.ws.close();
      this.ws = null;
    }
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
};

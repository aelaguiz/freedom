import crypto from "node:crypto";

import { JsonRpcWebSocketClient } from "./dock-relay-json-rpc-client.mjs";
import { defaultRelayLogger } from "./dock-relay-logger.mjs";

const DEFAULT_MAX_OPEN_PER_LABEL = 4;

function safeUrl(value) {
  try {
    const url = new URL(value);
    url.username = "";
    url.password = "";
    return url.toString();
  } catch {
    return String(value || "");
  }
}

function credentialKeyFor(value) {
  return value ? `bearer:${crypto.createHash("sha256").update(String(value)).digest("hex")}` : "none";
}

class UpstreamConnectionPool {
  constructor({
    logger = defaultRelayLogger,
    defaultMaxOpenPerLabel = DEFAULT_MAX_OPEN_PER_LABEL,
    maxOpenByLabel = {},
  } = {}) {
    this.logger = logger;
    this.defaultMaxOpenPerLabel = defaultMaxOpenPerLabel;
    this.maxOpenByLabel = { ...maxOpenByLabel };
    this.entries = new Map();
  }

  keyFor({ label, url, bearerToken = null }) {
    return `${label}\n${url}\n${credentialKeyFor(bearerToken)}`;
  }

  labelLimit(label) {
    const value = Number(this.maxOpenByLabel[label]);
    if (Number.isFinite(value) && value > 0) {
      return Math.floor(value);
    }
    return this.defaultMaxOpenPerLabel;
  }

  countOpenOrConnecting(label) {
    let count = 0;
    for (const entry of this.entries.values()) {
      if (entry.label === label && !entry.closed) {
        count += 1;
      }
    }
    return count;
  }

  async clientFor({
    label,
    url,
    bearerToken = null,
    timeoutMs = undefined,
    initializer = null,
  }) {
    const key = this.keyFor({ label, url, bearerToken });
    const existing = this.entries.get(key);
    if (
      existing
      && !existing.closed
      && !existing.client.isUnhealthy()
      && (existing.client.isOpen() || existing.opening)
    ) {
      await existing.opening;
      return existing.client;
    }

    if (existing) {
      this.entries.delete(key);
      await existing.client.close({ reason: "pool_replace_unhealthy" });
    }

    const openCount = this.countOpenOrConnecting(label);
    const maxOpen = this.labelLimit(label);
    if (openCount >= maxOpen) {
      const error = new Error(`upstream pool ${label} exhausted: ${openCount}/${maxOpen}`);
      error.code = -32001;
      throw error;
    }

    let entry;
    const client = new JsonRpcWebSocketClient(url, {
      bearerToken,
      timeoutMs,
      logger: this.logger,
      onClose: () => {
        if (entry) {
          entry.closed = true;
          this.entries.delete(key);
        }
      },
    });
    entry = {
      key,
      label,
      url,
      safeUrl: safeUrl(url),
      client,
      closed: false,
      createdAtMs: Date.now(),
      opening: null,
    };
    this.entries.set(key, entry);

    entry.opening = (async () => {
      await client.connect();
      if (initializer) {
        await initializer(client);
      }
      this.logger.info("upstream_pool.client_ready", {
        label,
        url: entry.safeUrl,
        open: this.countOpenOrConnecting(label),
        maxOpen,
      });
    })().catch(async (error) => {
      entry.closed = true;
      this.entries.delete(key);
      await client.close({ reason: "pool_open_failed" });
      throw error;
    });

    await entry.opening;
    return client;
  }

  async request(endpoint, method, params = undefined, options = {}) {
    const label = options.label || endpoint.label || "default";
    const client = await this.clientFor({
      label,
      url: endpoint.url,
      bearerToken: endpoint.bearerToken || null,
      timeoutMs: options.timeoutMs,
      initializer: options.initializer || null,
    });
    try {
      return await client.request(method, params);
    } catch (error) {
      if (client.isUnhealthy() || !client.isOpen()) {
        const key = this.keyFor({
          label,
          url: endpoint.url,
          bearerToken: endpoint.bearerToken || null,
        });
        this.entries.delete(key);
        await client.close({ reason: "pool_request_failed" });
      }
      throw error;
    }
  }

  stats() {
    const byLabel = new Map();
    for (const entry of this.entries.values()) {
      const current = byLabel.get(entry.label) || {
        label: entry.label,
        open: 0,
        pending: 0,
        unhealthy: 0,
        maxOpen: this.labelLimit(entry.label),
        endpoints: [],
      };
      current.open += entry.client.isOpen() ? 1 : 0;
      current.pending += entry.client.pendingCount();
      current.unhealthy += entry.client.isUnhealthy() ? 1 : 0;
      current.endpoints.push({
        url: entry.safeUrl,
        open: entry.client.isOpen(),
        pending: entry.client.pendingCount(),
        unhealthy: entry.client.isUnhealthy(),
      });
      byLabel.set(entry.label, current);
    }
    return [...byLabel.values()].sort((lhs, rhs) => lhs.label.localeCompare(rhs.label));
  }

  async closeAll({ reason = "pool_close" } = {}) {
    const entries = [...this.entries.values()];
    this.entries.clear();
    await Promise.all(entries.map(async (entry) => {
      entry.closed = true;
      await entry.client.close({ reason });
    }));
  }
}

class HistoryClient {
  constructor({
    pool,
    url,
    bearerToken,
    logger = defaultRelayLogger,
    timeoutMs = undefined,
    initializer,
  }) {
    this.pool = pool;
    this.url = url;
    this.bearerToken = bearerToken;
    this.logger = logger;
    this.timeoutMs = timeoutMs;
    this.initializer = initializer;
  }

  request(method, params = undefined) {
    return this.pool.request(
      {
        label: "history",
        url: this.url,
        bearerToken: this.bearerToken,
      },
      method,
      params,
      {
        label: "history",
        timeoutMs: this.timeoutMs,
        initializer: this.initializer,
      },
    );
  }
}

export {
  HistoryClient,
  UpstreamConnectionPool,
};

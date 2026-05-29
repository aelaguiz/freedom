#!/usr/bin/env node

import http from "node:http";
import https from "node:https";
import process from "node:process";

import { DEFAULT_RELAY_WS } from "./dock-relay-constants.mjs";
import { JsonRpcWebSocketClient } from "./dock-relay-json-rpc-client.mjs";
import { initializeClient } from "./dock-relay-thread-data.mjs";

function httpURLForRelayWS(relayUrl) {
  const url = new URL(relayUrl);
  url.protocol = url.protocol === "wss:" ? "https:" : "http:";
  url.pathname = "/statusz";
  url.search = "";
  url.hash = "";
  url.username = "";
  url.password = "";
  return url.toString();
}

function getJSON(url) {
  const client = url.startsWith("https:") ? https : http;
  return new Promise((resolve, reject) => {
    const request = client.get(url, { timeout: 2_000 }, (response) => {
      const chunks = [];
      response.on("data", (chunk) => chunks.push(chunk));
      response.on("end", () => {
        try {
          resolve(JSON.parse(Buffer.concat(chunks).toString("utf8")));
        } catch (error) {
          reject(error);
        }
      });
    });
    request.on("timeout", () => {
      request.destroy(new Error(`timed out reading ${url}`));
    });
    request.on("error", reject);
  });
}

function historyPool(status) {
  return (status?.connections?.upstreamPools || []).find((pool) => pool.label === "history") || {
    open: 0,
    pending: 0,
    unhealthy: 0,
  };
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function waitForHistoryPool(statusUrl, {
  timeoutMs = 10_000,
  intervalMs = 250,
} = {}) {
  const deadline = Date.now() + timeoutMs;
  let latest = historyPool(await getJSON(statusUrl));
  while (latest.pending !== 0 && Date.now() < deadline) {
    await sleep(intervalMs);
    latest = historyPool(await getJSON(statusUrl));
  }
  return latest;
}

async function main() {
  const relayUrl = process.env.CODEX_DOCK_RELAY_WS || DEFAULT_RELAY_WS;
  const iterations = Number(process.env.CODEX_DOCK_LEAK_CHECK_ITERATIONS || 25);
  const drainTimeoutMs = Number(process.env.CODEX_DOCK_LEAK_CHECK_DRAIN_TIMEOUT_MS || 10_000);
  if (!Number.isFinite(iterations) || iterations <= 0) {
    throw new Error("CODEX_DOCK_LEAK_CHECK_ITERATIONS must be positive");
  }
  if (!Number.isFinite(drainTimeoutMs) || drainTimeoutMs <= 0) {
    throw new Error("CODEX_DOCK_LEAK_CHECK_DRAIN_TIMEOUT_MS must be positive");
  }

  const statusUrl = process.env.CODEX_DOCK_RELAY_STATUS_URL || httpURLForRelayWS(relayUrl);
  const client = new JsonRpcWebSocketClient(relayUrl);
  try {
    await initializeClient(client);
    await client.request("thread/list", {
      limit: 1,
      sortKey: "updated_at",
      sortDirection: "desc",
      modelProviders: [],
      archived: false,
    });
    const before = historyPool(await getJSON(statusUrl));
    for (let index = 0; index < iterations; index += 1) {
      await client.request("thread/list", {
        limit: 1,
        sortKey: "updated_at",
        sortDirection: "desc",
        modelProviders: [],
        archived: false,
      });
    }
    const after = await waitForHistoryPool(statusUrl, { timeoutMs: drainTimeoutMs });
    if (after.open !== before.open) {
      throw new Error(`history upstream open sockets changed from ${before.open} to ${after.open}`);
    }
    if (after.pending !== 0) {
      throw new Error(`history upstream pending requests did not drain: ${after.pending}`);
    }
    if (after.unhealthy !== 0) {
      throw new Error(`history upstream unhealthy sockets remain: ${after.unhealthy}`);
    }
    console.log(JSON.stringify({
      ok: true,
      relayUrl,
      statusUrl,
      iterations,
      drainTimeoutMs,
      historyPoolBefore: before,
      historyPoolAfter: after,
    }, null, 2));
  } finally {
    await client.close();
  }
}

main().catch((error) => {
  console.error(`relay-leak-check failed: ${error.message || error}`);
  process.exit(1);
});

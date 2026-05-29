#!/usr/bin/env node

import fs from "node:fs";
import process from "node:process";

import {
  DEFAULT_HISTORY_APP_SERVER_WS,
  DEFAULT_RELAY_WS,
  THREAD_LIST_MAX_LIMIT,
} from "./dock-relay-constants.mjs";
import { JsonRpcWebSocketClient } from "./dock-relay-json-rpc-client.mjs";
import { initializeClient } from "./dock-relay-thread-data.mjs";

function readTokenFile(path) {
  const value = fs.readFileSync(path, "utf8").trim();
  if (!value) {
    throw new Error(`empty history token file: ${path}`);
  }
  return value;
}

async function requestThreadList(url, bearerToken, params) {
  const client = new JsonRpcWebSocketClient(url, { bearerToken });
  try {
    await initializeClient(client);
    return await client.request("thread/list", params);
  } finally {
    await client.close();
  }
}

function topID(response) {
  return response?.data?.[0]?.id || null;
}

async function main() {
  const relayUrl = process.env.CODEX_DOCK_RELAY_WS || DEFAULT_RELAY_WS;
  const historyUrl = process.env.CODEX_DOCK_HISTORY_APP_SERVER_WS || DEFAULT_HISTORY_APP_SERVER_WS;
  const historyTokenFile = process.env.CODEX_DOCK_HISTORY_TOKEN_FILE;
  const limit = Number(process.env.CODEX_DOCK_PROBE_LIMIT || 20);
  if (!historyTokenFile) {
    throw new Error("CODEX_DOCK_HISTORY_TOKEN_FILE is required");
  }
  if (!Number.isFinite(limit) || limit <= 0 || limit > THREAD_LIST_MAX_LIMIT) {
    throw new Error(`CODEX_DOCK_PROBE_LIMIT must be between 1 and ${THREAD_LIST_MAX_LIMIT}`);
  }

  const params = {
    limit: Math.floor(limit),
    sortKey: "updated_at",
    sortDirection: "desc",
    modelProviders: [],
    archived: false,
  };
  const history = await requestThreadList(historyUrl, readTokenFile(historyTokenFile), params);
  const relay = await requestThreadList(relayUrl, null, params);

  if (topID(history) !== topID(relay)) {
    throw new Error(`relay top row ${topID(relay) || "<none>"} did not match history top row ${topID(history) || "<none>"}`);
  }
  if ((history.nextCursor || null) !== (relay.nextCursor || null)) {
    throw new Error(`relay nextCursor ${relay.nextCursor || "<null>"} did not match history nextCursor ${history.nextCursor || "<null>"}`);
  }

  console.log(JSON.stringify({
    ok: true,
    relayUrl,
    historyUrl,
    limit: params.limit,
    topThreadID: topID(relay),
    rowCount: relay.data?.length || 0,
    nextCursor: relay.nextCursor || null,
    liveOverlay: relay.liveOverlay || null,
  }, null, 2));
}

main().catch((error) => {
  console.error(`relay-probe failed: ${error.message || error}`);
  process.exit(1);
});

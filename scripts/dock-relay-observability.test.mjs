import assert from "node:assert/strict";
import http from "node:http";
import test from "node:test";

import {
  ROUTE_CONFIGS,
  ROUTE_NAMES,
  autoProbeSafeRoutes,
} from "./dock-relay-observability-contract.mjs";
import { startServer } from "./dock-relay.mjs";
import {
  jsonRpcRequest,
  openWebSocket,
} from "./dock-relay-test-helpers.mjs";

function httpStatus(url) {
  return new Promise((resolve, reject) => {
    http.get(url, (response) => {
      response.resume();
      response.on("end", () => resolve(response.statusCode));
    }).on("error", reject);
  });
}

async function withRelay(testFn) {
  const config = {
    listenHost: "127.0.0.1",
    port: 0,
    phoneAuth: "none",
    historyBearerToken: "test-token",
    historyUrl: "ws://127.0.0.1:1/",
    liveEndpoints: [],
    advertiseBonjour: false,
    relayStateDatabasePath: ":memory:",
    hostId: "home",
    hostName: "Home",
  };
  const server = startServer(config);
  await server.listening;
  try {
    await testFn({ config, baseURL: `http://127.0.0.1:${config.port}`, wsURL: `ws://127.0.0.1:${config.port}` });
  } finally {
    await server.close();
  }
}

test("observability contract contains only supported app-facing routes", () => {
  assert.equal(ROUTE_NAMES.dockSubscribe, "dock/subscribe");
  assert.equal(ROUTE_NAMES.archiveSubscribe, "archive/subscribe");
  assert.equal(ROUTE_CONFIGS["thread/list"], undefined);
  assert.equal(ROUTE_CONFIGS["thread/search"], undefined);
  assert.equal(ROUTE_CONFIGS["thread/goal/get"], undefined);
  assert.equal(ROUTE_CONFIGS["relay/state/snapshot"], undefined);
  assert.equal(ROUTE_CONFIGS["state/query"], undefined);
  assert.equal(autoProbeSafeRoutes().some((route) => route.name === "thread/list"), false);
});

test("removed JSON-RPC side doors are unsupported", async () => withRelay(async ({ wsURL }) => {
  const ws = await openWebSocket(wsURL);
  try {
    for (const method of [
      "thread/list",
      "thread/search",
      "thread/goal/get",
      "thread/loaded/list",
      "relay/state/snapshot",
      "state/query",
    ]) {
      const response = await jsonRpcRequest(ws, method, {});
      assert.equal(response.error?.code, -32601);
      assert.match(response.error?.message || "", /unsupported method/);
    }
  } finally {
    ws.close();
  }
}));

test("removed HTTP diagnostics do not expose card truth", async () => withRelay(async ({ baseURL }) => {
  for (const path of [
    "/statez",
    "/dbz",
    "/explainz/thread/example",
    "/debugz/sessions",
    "/subscriptionsz",
    "/tracesz/recent",
    "/tracesz/example",
    "/selftestz",
    "/bundlez",
  ]) {
    assert.equal(await httpStatus(`${baseURL}${path}`), 404);
  }
  assert.equal(await httpStatus(`${baseURL}/syncz`), 200);
}));

import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import {
  JsonRpcWebSocketClient,
  unixSocketPathFromURL,
  webSocketURLForEndpoint,
} from "./dock-relay-json-rpc-client.mjs";
import {
  startUnixJsonRpcServer,
} from "./dock-relay-test-helpers.mjs";

test("JsonRpcWebSocketClient adapts Codex unix:// app-server endpoints to ws+unix", async () => {
  let extensionHeader = null;
  const server = await startUnixJsonRpcServer((message) => {
    if (message.method === "initialize") {
      return { id: message.id, result: { userAgent: "unix-test" } };
    }
    if (message.method === "thread/list") {
      return { id: message.id, result: { data: [], nextCursor: null } };
    }
    return null;
  }, {
    onUpgrade: (request) => {
      extensionHeader = request.headers["sec-websocket-extensions"] || null;
    },
  });
  const endpoint = `unix://${server.socketPath}`;
  assert.equal(unixSocketPathFromURL(endpoint), server.socketPath);
  assert.equal(webSocketURLForEndpoint(endpoint), `ws+unix:${server.socketPath}:/`);

  const client = new JsonRpcWebSocketClient(endpoint, { timeoutMs: 1_000 });
  try {
    await client.connect();
    const initialize = await client.request("initialize", {});
    assert.equal(initialize.userAgent, "unix-test");
    const list = await client.request("thread/list", {});
    assert.deepEqual(list, { data: [], nextCursor: null });
    assert.equal(extensionHeader, null);
  } finally {
    await client.close();
    await server.close();
  }
});

test("JsonRpcWebSocketClient resolves relative unix:// paths against a base path", () => {
  const basePath = fs.mkdtempSync(path.join(os.tmpdir(), "codex-dock-jsonrpc-relative-"));
  try {
    const socketPath = path.join(basePath, "relative.sock");
    assert.equal(
      unixSocketPathFromURL("unix://relative.sock", { basePath }),
      socketPath,
    );
    assert.equal(
      webSocketURLForEndpoint(`unix://${socketPath}`),
      `ws+unix:${socketPath}:/`,
    );
  } finally {
    fs.rmSync(basePath, { recursive: true, force: true });
  }
});

test("JsonRpcWebSocketClient rejects bare unix:// URLs without a socket path", () => {
  assert.throws(
    () => unixSocketPathFromURL("unix://"),
    /missing a socket path/u,
  );
});

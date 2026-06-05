import assert from "node:assert/strict";
import fs from "node:fs";
import http from "node:http";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { WebSocketServer } from "ws";

import {
  JsonRpcWebSocketClient,
  unixSocketPathFromURL,
  webSocketURLForEndpoint,
} from "./dock-relay-json-rpc-client.mjs";

async function startUnixJsonRpcServer(handler, { onUpgrade = null } = {}) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "codex-dock-jsonrpc-unix-"));
  const socketPath = path.join(dir, "app-server.sock");
  const httpServer = http.createServer();
  const wss = new WebSocketServer({ noServer: true });
  const clients = new Set();
  httpServer.on("upgrade", (request, socket, head) => {
    onUpgrade?.(request);
    wss.handleUpgrade(request, socket, head, (ws) => {
      clients.add(ws);
      ws.on("close", () => clients.delete(ws));
      ws.on("message", (raw) => {
        const message = JSON.parse(raw.toString());
        const response = handler(message);
        if (response) {
          ws.send(JSON.stringify(response));
        }
      });
    });
  });
  await new Promise((resolve) => {
    httpServer.listen(socketPath, resolve);
  });
  return {
    socketPath,
    close: async () => {
      for (const ws of clients) {
        ws.close();
      }
      await new Promise((resolve, reject) => {
        httpServer.close((error) => {
          if (error) {
            reject(error);
          } else {
            resolve();
          }
        });
      });
      fs.rmSync(dir, { recursive: true, force: true });
    },
  };
}

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

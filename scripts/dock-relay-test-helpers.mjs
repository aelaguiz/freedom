import { spawn } from "node:child_process";
import fs from "node:fs";
import http from "node:http";
import path from "node:path";
import process from "node:process";
import WebSocket, { WebSocketServer } from "ws";

function onceListening(server) {
  if (server.address()) {
    return Promise.resolve();
  }
  return new Promise((resolve) => {
    server.once("listening", resolve);
  });
}

function httpGetJson(url) {
  return new Promise((resolve, reject) => {
    http.get(url, (response) => {
      const chunks = [];
      response.on("data", (chunk) => chunks.push(chunk));
      response.on("end", () => {
        try {
          resolve(JSON.parse(Buffer.concat(chunks).toString("utf8")));
        } catch (error) {
          reject(error);
        }
      });
    }).on("error", reject);
  });
}

function openWebSocket(url, options = undefined) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(url, options);
    ws.once("open", () => resolve(ws));
    ws.once("error", reject);
  });
}

function jsonRpcRequest(ws, method, params = undefined) {
  const id = `${method}-test`;
  const payload = { id, method };
  if (params !== undefined) {
    payload.params = params;
  }
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`timed out waiting for ${method}`)), 1_000);
    ws.on("message", function onMessage(data) {
      const message = JSON.parse(data.toString());
      if (message.id === id) {
        clearTimeout(timer);
        ws.off("message", onMessage);
        resolve(message);
      }
    });
    ws.send(JSON.stringify(payload));
  });
}

function waitForRelayMessage(ws, predicate) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("timed out waiting for relay message")), 1_000);
    ws.on("message", function onMessage(data) {
      const message = JSON.parse(data.toString());
      if (predicate(message)) {
        clearTimeout(timer);
        ws.off("message", onMessage);
        resolve(message);
      }
    });
  });
}

function waitForWebSocketClose(ws) {
  return new Promise((resolve) => {
    if (ws.readyState === WebSocket.CLOSED) {
      resolve({ code: ws.closeCode, reason: ws.closeReason?.toString() || "" });
      return;
    }
    ws.once("close", (code, reason) => {
      resolve({ code, reason: reason.toString() });
    });
  });
}

function closeWebSocketServer(server) {
  return new Promise((resolve, reject) => {
    server.close((error) => {
      if (error) {
        reject(error);
      } else {
        resolve();
      }
    });
  });
}

async function startUnixJsonRpcServer(handler, {
  socketPath = null,
  socketName = "app-server.sock",
  onUpgrade = null,
} = {}) {
  const baseDir = "/tmp/codex-client";
  fs.mkdirSync(baseDir, { recursive: true });
  const dir = socketPath ? null : fs.mkdtempSync(path.join(baseDir, "codex-dock-jsonrpc-unix-"));
  const resolvedSocketPath = socketPath || path.join(dir, socketName);
  fs.rmSync(resolvedSocketPath, { force: true });

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
        const response = handler(message, ws);
        if (response) {
          ws.send(JSON.stringify(response));
        }
      });
    });
  });

  await new Promise((resolve, reject) => {
    const onError = (error) => {
      httpServer.off("listening", onListening);
      reject(error);
    };
    const onListening = () => {
      httpServer.off("error", onError);
      resolve();
    };
    httpServer.once("error", onError);
    httpServer.once("listening", onListening);
    httpServer.listen(resolvedSocketPath);
  });

  return {
    socketPath: resolvedSocketPath,
    url: `unix://${resolvedSocketPath}`,
    close: async () => {
      for (const ws of clients) {
        try {
          ws.close();
        } catch {
          // Test cleanup should not mask the result being asserted.
        }
      }
      await new Promise((resolve) => {
        let finished = false;
        const finish = () => {
          if (finished) {
            return;
          }
          finished = true;
          clearTimeout(forceTimer);
          resolve();
        };
        const forceTimer = setTimeout(() => {
          for (const ws of clients) {
            try {
              ws.terminate();
            } catch {
              // Test cleanup should not mask the result being asserted.
            }
          }
          finish();
        }, 500);
        try {
          httpServer.close(() => finish());
        } catch {
          finish();
        }
      });
      try {
        await new Promise((resolve) => wss.close(() => resolve()));
      } catch {
        // Closing the HTTP server already closed the IPC listener.
      }
      fs.rmSync(resolvedSocketPath, { force: true });
      if (dir) {
        fs.rmSync(dir, { recursive: true, force: true });
      }
    },
  };
}

function appServerRegistryFixtureConfig({
  historyUrl = null,
  historyBearerToken = "test-token",
  liveEndpoints = [],
  codexHome = "/tmp/codex-client-test",
  includeDaemonHistory = false,
} = {}) {
  return {
    codexHome,
    registryIncludeDaemonHistory: includeDaemonHistory,
    registryProcessListProvider: async () => [],
    registryFixtureHistoryEndpoints: historyUrl
      ? [{
          label: "fixture-history",
          url: historyUrl,
          bearerToken: historyBearerToken || null,
        }]
      : [],
    registryFixtureLiveEndpoints: liveEndpoints
      .filter((endpoint) => endpoint?.url)
      .map((endpoint) => ({
        ...endpoint,
        label: endpoint.label || endpoint.url,
        bearerToken: endpoint.bearerToken || historyBearerToken || null,
      })),
  };
}

function spawnLoopbackAppServerMarker(url) {
  return spawn(
    process.execPath,
    [
      "-e",
      "setInterval(() => {}, 1000)",
      "codex",
      "app-server",
      "--listen",
      url,
    ],
    { stdio: "ignore" },
  );
}

function sleepMs(milliseconds) {
  return new Promise((resolve) => {
    setTimeout(resolve, milliseconds);
  });
}

function closeProcess(child) {
  return new Promise((resolve) => {
    if (child.exitCode !== null || child.signalCode !== null) {
      resolve();
      return;
    }
    const timer = setTimeout(resolve, 500);
    child.once("exit", () => {
      clearTimeout(timer);
      resolve();
    });
    child.kill();
  });
}

export {
  appServerRegistryFixtureConfig,
  closeProcess,
  closeWebSocketServer,
  httpGetJson,
  jsonRpcRequest,
  onceListening,
  openWebSocket,
  sleepMs,
  spawnLoopbackAppServerMarker,
  startUnixJsonRpcServer,
  waitForRelayMessage,
  waitForWebSocketClose,
};

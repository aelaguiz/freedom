import { spawn } from "node:child_process";
import http from "node:http";
import process from "node:process";
import WebSocket from "ws";

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
  closeProcess,
  closeWebSocketServer,
  httpGetJson,
  jsonRpcRequest,
  onceListening,
  openWebSocket,
  sleepMs,
  spawnLoopbackAppServerMarker,
  waitForRelayMessage,
  waitForWebSocketClose,
};

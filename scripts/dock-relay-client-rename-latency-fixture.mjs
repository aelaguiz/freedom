#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { WebSocketServer } from "ws";

import { startServer } from "./dock-relay.mjs";
import {
  appServerRegistryFixtureConfig,
  closeWebSocketServer,
  jsonRpcRequest,
  onceListening,
  openWebSocket,
  sleepMs,
} from "./dock-relay-test-helpers.mjs";

const TARGET_THREAD_ID = "client-rename-latency-target";
const STABLE_THREAD_ID = "client-rename-latency-stable";
const HOST_ID = "home";
const HOST_NAME = "Home";
const ORIGINAL_TITLE = "Client rename original title";
const NEW_TITLE = "Client rename optimistic title";
const DEFAULT_SERVER_ACK_DELAY_MS = 1_500;
const DEFAULT_UI_BUDGET_MS = 700;
const DEFAULT_WAIT_TIMEOUT_MS = 120_000;

function usage() {
  return [
    "Usage:",
    "  node scripts/dock-relay-client-rename-latency-fixture.mjs --ready-out <path> --ui-result-in <path> --stop-in <path> --json-out <path> [options]",
    "",
    "Options:",
    "  --summary-out <path>             Write Markdown summary.",
    "  --server-ack-delay-ms <ms>       Delay fake app-server thread/name/set response. Default: 1500.",
    "  --ui-budget-ms <ms>              Max editor-dismiss and optimistic-title UI budget. Default: 700.",
    "  --wait-timeout-ms <ms>           Wait budget for UI result and stream confirmation. Default: 120000.",
    "  --help                          Show this help.",
  ].join("\n");
}

function parseArgs(argv) {
  const options = {
    readyOut: null,
    uiResultIn: null,
    stopIn: null,
    jsonOut: null,
    summaryOut: null,
    serverAckDelayMs: DEFAULT_SERVER_ACK_DELAY_MS,
    uiBudgetMs: DEFAULT_UI_BUDGET_MS,
    waitTimeoutMs: DEFAULT_WAIT_TIMEOUT_MS,
    help: false,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    const next = () => {
      index += 1;
      if (index >= argv.length) {
        throw new Error(`missing value for ${arg}`);
      }
      return argv[index];
    };
    if (arg === "--ready-out") {
      options.readyOut = next();
    } else if (arg === "--ui-result-in") {
      options.uiResultIn = next();
    } else if (arg === "--stop-in") {
      options.stopIn = next();
    } else if (arg === "--json-out") {
      options.jsonOut = next();
    } else if (arg === "--summary-out") {
      options.summaryOut = next();
    } else if (arg === "--server-ack-delay-ms") {
      options.serverAckDelayMs = Number(next());
    } else if (arg === "--ui-budget-ms") {
      options.uiBudgetMs = Number(next());
    } else if (arg === "--wait-timeout-ms") {
      options.waitTimeoutMs = Number(next());
    } else if (arg === "--help" || arg === "-h") {
      options.help = true;
    } else {
      throw new Error(`unknown argument ${arg}`);
    }
  }
  return options;
}

function validateOptions(options) {
  if (options.help) {
    return;
  }
  for (const field of ["readyOut", "uiResultIn", "stopIn", "jsonOut"]) {
    if (!options[field]) {
      throw new Error(`--${field.replace(/[A-Z]/g, (match) => `-${match.toLowerCase()}`)} is required`);
    }
  }
  for (const field of ["serverAckDelayMs", "uiBudgetMs", "waitTimeoutMs"]) {
    if (!Number.isFinite(options[field]) || options[field] < 0) {
      throw new Error(`${field} must be a non-negative number`);
    }
  }
}

function nowMs() {
  return Date.now();
}

function iso(ms = nowMs()) {
  return new Date(ms).toISOString();
}

function writeJSON(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

function writeText(filePath, body) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, body, "utf8");
}

function appServerResponse(id, result) {
  return JSON.stringify({ jsonrpc: "2.0", id, result });
}

function fixtureThread({ id, title, updatedAt }) {
  return {
    id,
    sessionId: `${id}-session`,
    preview: title,
    name: title,
    createdAt: updatedAt - 100,
    updatedAt,
    source: "cli",
    status: { type: "idle" },
    cwd: "/tmp/codex-client",
    gitInfo: { branch: "main" },
  };
}

async function startClientRenameAppServer({ serverAckDelayMs }) {
  const wss = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  const clients = new Set();
  const timers = new Set();
  const rows = {
    [TARGET_THREAD_ID]: fixtureThread({
      id: TARGET_THREAD_ID,
      title: ORIGINAL_TITLE,
      updatedAt: 4_000,
    }),
    [STABLE_THREAD_ID]: fixtureThread({
      id: STABLE_THREAD_ID,
      title: "Client rename stable title",
      updatedAt: 3_000,
    }),
  };
  const renameRequests = [];

  await onceListening(wss);
  const address = wss.address();
  const url = `ws://127.0.0.1:${address.port}`;

  function sendThreadRead(ws, message) {
    const thread = rows[message.params?.threadId];
    if (!thread) {
      ws.send(JSON.stringify({
        jsonrpc: "2.0",
        id: message.id,
        error: { code: -32602, message: "thread not found" },
      }));
      return;
    }
    ws.send(appServerResponse(message.id, { thread: { ...thread, turns: [] } }));
  }

  wss.on("connection", (ws) => {
    clients.add(ws);
    ws.on("close", () => {
      clients.delete(ws);
    });
    ws.on("message", (raw) => {
      const message = JSON.parse(raw.toString());
      if (message.method === "initialize") {
        ws.send(appServerResponse(message.id, {
          userAgent: "client-rename-latency-fixture",
          codexHome: "/tmp/codex-client-rename-latency",
          platformFamily: "unix",
          platformOs: "macos",
        }));
      } else if (message.method === "initialized") {
        return;
      } else if (message.method === "thread/list") {
        ws.send(appServerResponse(message.id, {
          data: [rows[TARGET_THREAD_ID], rows[STABLE_THREAD_ID]],
          nextCursor: null,
        }));
      } else if (message.method === "thread/loaded/list") {
        ws.send(appServerResponse(message.id, { data: [] }));
      } else if (message.method === "thread/read") {
        sendThreadRead(ws, message);
      } else if (message.method === "thread/turns/list") {
        const threadID = message.params?.threadId;
        const startedAt = threadID === TARGET_THREAD_ID ? 4_100 : 3_100;
        ws.send(appServerResponse(message.id, {
          data: [{ id: `${threadID}-turn`, startedAt, items: [] }],
          nextCursor: null,
          backwardsCursor: null,
        }));
      } else if (message.method === "thread/name/set") {
        const thread = rows[message.params?.threadId];
        if (!thread) {
          ws.send(JSON.stringify({
            jsonrpc: "2.0",
            id: message.id,
            error: { code: -32602, message: "thread not found" },
          }));
          return;
        }
        const receivedAtMs = nowMs();
        const request = {
          threadId: message.params.threadId,
          name: message.params.name,
          receivedAt: iso(receivedAtMs),
          receivedAtMs,
          respondedAt: null,
          respondedAtMs: null,
        };
        renameRequests.push(request);
        thread.name = message.params.name;
        thread.preview = message.params.name;
        thread.updatedAt = 10_000;
        const timer = setTimeout(() => {
          timers.delete(timer);
          request.respondedAtMs = nowMs();
          request.respondedAt = iso(request.respondedAtMs);
          ws.send(appServerResponse(message.id, {}));
        }, serverAckDelayMs);
        timers.add(timer);
      }
    });
  });

  return {
    url,
    renameRequests,
    close: async () => {
      for (const timer of timers) {
        clearTimeout(timer);
      }
      for (const ws of clients) {
        ws.close();
      }
      await closeWebSocketServer(wss);
    },
  };
}

function waitForRelayMessage(ws, predicate, timeoutMs) {
  let timer = null;
  let onMessage = null;
  const promise = new Promise((resolve) => {
    timer = setTimeout(() => {
      ws.off("message", onMessage);
      resolve({ ok: false, reason: "timeout", observedAt: null, observedAtMs: null, message: null });
    }, timeoutMs);
    onMessage = (data) => {
      const message = JSON.parse(data.toString());
      if (!predicate(message)) {
        return;
      }
      const observedAtMs = nowMs();
      clearTimeout(timer);
      ws.off("message", onMessage);
      resolve({ ok: true, observedAt: iso(observedAtMs), observedAtMs, message });
    };
    ws.on("message", onMessage);
  });
  return {
    promise,
    cancel: () => {
      if (timer) {
        clearTimeout(timer);
      }
      if (onMessage) {
        ws.off("message", onMessage);
      }
    },
  };
}

async function waitForJSONFile(filePath, timeoutMs) {
  const deadline = nowMs() + timeoutMs;
  while (nowMs() < deadline) {
    if (fs.existsSync(filePath)) {
      return JSON.parse(fs.readFileSync(filePath, "utf8"));
    }
    await sleepMs(100);
  }
  throw new Error(`timed out waiting for UI result: ${filePath}`);
}

async function waitForFile(filePath, timeoutMs) {
  const deadline = nowMs() + timeoutMs;
  while (nowMs() < deadline) {
    if (fs.existsSync(filePath)) {
      return true;
    }
    await sleepMs(100);
  }
  return false;
}

function finding(severity, code, message, details = {}) {
  return { severity, code, message, details };
}

function buildMarkdownSummary(report) {
  const lines = [
    "# Client Rename Latency Proof",
    "",
    `- status: ${report.summary.ok ? "pass" : "fail"}`,
    `- relayUrl: ${report.relayUrl}`,
    `- threadID: ${report.target.threadID}`,
    `- serverAckDelayMS: ${report.config.serverAckDelayMS}`,
    `- uiBudgetMS: ${report.config.uiBudgetMS}`,
    `- sheetDismissMS: ${report.ui?.timings?.sheetDismissMS ?? "missing"}`,
    `- optimisticTitleMS: ${report.ui?.timings?.optimisticTitleMS ?? "missing"}`,
    `- appServerAckMS: ${report.server?.renameRequests?.[0]?.ackMS ?? "missing"}`,
    `- canonicalUpdateObserved: ${report.canonicalUpdate?.ok === true}`,
    "",
  ];
  if (report.findings.length > 0) {
    lines.push("## Findings", "");
    for (const item of report.findings) {
      lines.push(`- ${item.severity}: ${item.code}: ${item.message}`);
    }
  }
  return `${lines.join("\n")}\n`;
}

function evaluateReport({ options, relayUrl, initial, uiResult, canonicalUpdate, appServer }) {
  const findings = [];
  const request = appServer.renameRequests[0] || null;
  const uiTimings = uiResult?.timings || {};
  const sheetDismissMS = Number(uiTimings.sheetDismissMS);
  const optimisticTitleMS = Number(uiTimings.optimisticTitleMS);
  const saveTappedAtMs = Number(uiTimings.saveTappedAtMs);
  const sheetDismissedAtMs = Number(uiTimings.sheetDismissedAtMs);
  const optimisticTitleObservedAtMs = Number(uiTimings.optimisticTitleObservedAtMs);

  if (uiResult?.status !== "pass") {
    findings.push(finding("error", "ui_result_failed", uiResult?.reason || "UI proof did not pass"));
  }
  if (!Number.isFinite(sheetDismissMS) || sheetDismissMS > options.uiBudgetMs) {
    findings.push(finding("error", "sheet_dismiss_slow", "rename editor did not dismiss within the UI budget", {
      sheetDismissMS,
      uiBudgetMS: options.uiBudgetMs,
    }));
  }
  if (!Number.isFinite(optimisticTitleMS) || optimisticTitleMS > options.uiBudgetMs) {
    findings.push(finding("error", "optimistic_title_slow", "optimistic Dock row title did not appear within the UI budget", {
      optimisticTitleMS,
      uiBudgetMS: options.uiBudgetMs,
    }));
  }
  if (!request) {
    findings.push(finding("error", "rename_request_missing", "fake app-server did not receive thread/name/set"));
  } else {
    request.ackMS = request.respondedAtMs === null ? null : request.respondedAtMs - request.receivedAtMs;
    if (request.name !== NEW_TITLE) {
      findings.push(finding("error", "rename_request_wrong_title", "thread/name/set carried the wrong title", {
        expected: NEW_TITLE,
        actual: request.name,
      }));
    }
    if (request.threadId !== TARGET_THREAD_ID) {
      findings.push(finding("error", "rename_request_wrong_thread", "thread/name/set carried the wrong thread id", {
        expected: TARGET_THREAD_ID,
        actual: request.threadId,
      }));
    }
    if (request.ackMS === null || request.ackMS < Math.max(0, options.serverAckDelayMs - 100)) {
      findings.push(finding("error", "server_ack_not_delayed", "fake app-server ACK was not delayed enough to prove optimistic UI", {
        observedAckMS: request.ackMS,
        configuredDelayMS: options.serverAckDelayMs,
      }));
    }
    if (Number.isFinite(sheetDismissedAtMs) && request.respondedAtMs !== null && sheetDismissedAtMs >= request.respondedAtMs) {
      findings.push(finding("error", "sheet_waited_for_server_ack", "rename editor dismissed after the delayed server ACK instead of before it", {
        sheetDismissedAt: iso(sheetDismissedAtMs),
        serverAckAt: request.respondedAt,
      }));
    }
    if (Number.isFinite(optimisticTitleObservedAtMs) && request.respondedAtMs !== null && optimisticTitleObservedAtMs >= request.respondedAtMs) {
      findings.push(finding("error", "optimistic_title_waited_for_server_ack", "optimistic title appeared after the delayed server ACK instead of before it", {
        optimisticTitleObservedAt: iso(optimisticTitleObservedAtMs),
        serverAckAt: request.respondedAt,
      }));
    }
    if (Number.isFinite(saveTappedAtMs) && request.receivedAtMs < saveTappedAtMs) {
      findings.push(finding("warning", "server_request_before_save_timestamp", "fake app-server request timestamp was before the UI save timestamp; clocks or event ordering need inspection", {
        saveTappedAt: iso(saveTappedAtMs),
        requestReceivedAt: request.receivedAt,
      }));
    }
  }
  if (canonicalUpdate?.ok !== true) {
    findings.push(finding("error", "canonical_update_missing", "relay Dock stream did not publish the canonical renamed title"));
  } else if (request?.respondedAtMs !== null && canonicalUpdate.observedAtMs < request.respondedAtMs) {
    findings.push(finding("error", "canonical_update_before_server_ack", "canonical relay update arrived before the delayed app-server ACK", {
      canonicalObservedAt: canonicalUpdate.observedAt,
      serverAckAt: request.respondedAt,
    }));
  }

  const report = {
    schemaVersion: 1,
    kind: "codex-dock-client-rename-latency-proof",
    startedAt: initial.startedAt,
    endedAt: iso(),
    relayUrl,
    config: {
      serverAckDelayMS: options.serverAckDelayMs,
      uiBudgetMS: options.uiBudgetMs,
      waitTimeoutMS: options.waitTimeoutMs,
    },
    summary: {
      ok: !findings.some((item) => item.severity === "error"),
      findingCount: findings.length,
      sheetDismissMS: Number.isFinite(sheetDismissMS) ? sheetDismissMS : null,
      optimisticTitleMS: Number.isFinite(optimisticTitleMS) ? optimisticTitleMS : null,
      serverAckMS: request?.ackMS ?? null,
      canonicalUpdateObserved: canonicalUpdate?.ok === true,
    },
    target: {
      hostID: HOST_ID,
      threadID: TARGET_THREAD_ID,
      originalTitle: ORIGINAL_TITLE,
      newTitle: NEW_TITLE,
    },
    initialDock: initial.dock,
    ui: uiResult,
    server: {
      renameRequests: appServer.renameRequests,
    },
    canonicalUpdate,
    findings,
  };
  return report;
}

async function run(options) {
  const startedAt = iso();
  const appServer = await startClientRenameAppServer({
    serverAckDelayMs: options.serverAckDelayMs,
  });
  const relayConfig = {
    listenHost: "127.0.0.1",
    port: 0,
    phoneAuth: "none",
    ...appServerRegistryFixtureConfig({
      historyUrl: appServer.url,
      historyBearerToken: "test-token",
      codexHome: "/tmp/codex-client-rename-latency",
    }),
    advertiseBonjour: false,
    relayStateDatabasePath: ":memory:",
    hostId: HOST_ID,
    hostName: HOST_NAME,
  };
  const relay = startServer(relayConfig);
  let probeWs = null;
  let canonicalUpdateWait = null;
  await relay.listening;
  const relayUrl = `ws://127.0.0.1:${relayConfig.port}`;
  try {
    await relayConfig.relayStateEngine.reconcileDock({ reason: "client_rename_latency_initial" });
    probeWs = await openWebSocket(relayUrl);
    const initialDock = await jsonRpcRequest(probeWs, "dock/subscribe", { offset: 0, limit: 10 });
    const initialCard = initialDock.result?.rows?.find((card) => card.threadID === TARGET_THREAD_ID);
    if (initialDock.error || initialCard?.title !== ORIGINAL_TITLE) {
      throw new Error(`controlled fixture failed to publish initial title; got ${initialCard?.title || "missing"}`);
    }

    canonicalUpdateWait = waitForRelayMessage(probeWs, (message) => (
      message.method === "dock/update"
      && (message.params?.rows || []).some((card) => (
        card.threadID === TARGET_THREAD_ID && card.title === NEW_TITLE
      ))
    ), options.waitTimeoutMs);

    writeJSON(options.readyOut, {
      ready: true,
      scenario: "client-rename-latency",
      relayUrl,
      hosts: `127.0.0.1:${relayConfig.port}`,
      hostID: HOST_ID,
      hostName: HOST_NAME,
      threadID: TARGET_THREAD_ID,
      originalTitle: ORIGINAL_TITLE,
      newTitle: NEW_TITLE,
      uiResultPath: options.uiResultIn,
      serverAckDelayMS: options.serverAckDelayMs,
      uiBudgetMS: options.uiBudgetMs,
      at: iso(),
    });

    const uiResult = await waitForJSONFile(options.uiResultIn, options.waitTimeoutMs);
    const requestDeadline = nowMs() + options.waitTimeoutMs;
    while (appServer.renameRequests[0] && appServer.renameRequests[0].respondedAtMs === null && nowMs() < requestDeadline) {
      await sleepMs(25);
    }
    const shouldWaitForCanonicalUpdate = uiResult.status === "pass" || appServer.renameRequests.length > 0;
    const canonicalUpdate = shouldWaitForCanonicalUpdate
      ? await canonicalUpdateWait.promise
      : { ok: false, reason: "skipped_after_ui_failure", observedAt: null, observedAtMs: null, message: null };
    if (!shouldWaitForCanonicalUpdate) {
      canonicalUpdateWait.cancel();
    }
    const report = evaluateReport({
      options,
      relayUrl,
      initial: {
        startedAt,
        dock: initialDock.result,
      },
      uiResult,
      canonicalUpdate,
      appServer,
    });
    writeJSON(options.jsonOut, report);
    if (options.summaryOut) {
      writeText(options.summaryOut, buildMarkdownSummary(report));
    }
    await waitForFile(options.stopIn, options.waitTimeoutMs);
    return report;
  } finally {
    canonicalUpdateWait?.cancel();
    if (probeWs) {
      probeWs.close();
    }
    await relay.close().catch(() => null);
    await appServer.close().catch(() => null);
  }
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    console.log(usage());
    return;
  }
  validateOptions(options);
  const report = await run(options);
  process.stdout.write(`${JSON.stringify({
    ok: report.summary.ok,
    relayUrl: report.relayUrl,
    summary: report.summary,
    reportPath: options.jsonOut,
    summaryPath: options.summaryOut || null,
    findings: report.findings,
  }, null, 2)}\n`);
  if (!report.summary.ok) {
    process.exitCode = 1;
  }
}

main().catch((error) => {
  console.error(`client-rename-latency-fixture failed: ${error.message || error}`);
  process.exitCode = 1;
});

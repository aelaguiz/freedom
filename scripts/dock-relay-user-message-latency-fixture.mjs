import fs from "node:fs";
import path from "node:path";
import { randomUUID } from "node:crypto";
import { WebSocketServer } from "ws";

import { startServer } from "./dock-relay.mjs";
import {
  appServerRegistryFixtureConfig,
  closeWebSocketServer,
  onceListening,
} from "./dock-relay-test-helpers.mjs";

function usage() {
  return [
    "Usage:",
    "  node scripts/dock-relay-user-message-latency-fixture.mjs --ready-out <path> --ui-result-in <path> --stop-in <path> --json-out <path> --summary-out <path> [options]",
    "",
    "Options:",
    "  --upstream-ack-delay-ms <ms>  Delay fake upstream turn/start response. Default: 2500",
    "  --ui-budget-ms <ms>           Max composer clear / pending-row budget. Default: 700",
    "  --wait-timeout-ms <ms>        Max wait for UI result/stop. Default: 60000",
  ].join("\n");
}

function parseArgs(argv) {
  const options = {
    upstreamAckDelayMS: 2_500,
    uiBudgetMS: 700,
    waitTimeoutMS: 60_000,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    const next = () => {
      index += 1;
      if (index >= argv.length) {
        throw new Error(`${arg} requires a value`);
      }
      return argv[index];
    };
    switch (arg) {
      case "--ready-out":
        options.readyOut = next();
        break;
      case "--ui-result-in":
        options.uiResultIn = next();
        break;
      case "--stop-in":
        options.stopIn = next();
        break;
      case "--json-out":
        options.jsonOut = next();
        break;
      case "--summary-out":
        options.summaryOut = next();
        break;
      case "--upstream-ack-delay-ms":
        options.upstreamAckDelayMS = Number(next());
        break;
      case "--ui-budget-ms":
        options.uiBudgetMS = Number(next());
        break;
      case "--wait-timeout-ms":
        options.waitTimeoutMS = Number(next());
        break;
      case "--help":
        console.log(usage());
        process.exit(0);
      default:
        throw new Error(`unknown argument: ${arg}`);
    }
  }
  for (const required of ["readyOut", "uiResultIn", "stopIn", "jsonOut", "summaryOut"]) {
    if (!options[required]) {
      throw new Error(`${required} is required`);
    }
  }
  return options;
}

function ensureParent(filePath) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
}

function writeJSON(filePath, value) {
  ensureParent(filePath);
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`);
}

function writeSummary(filePath, report) {
  ensureParent(filePath);
  const lines = [
    "# User Message Latency Proof",
    "",
    `Status: ${report.status}`,
    report.reason ? `Reason: ${report.reason}` : "Reason: none",
    `Host: ${report.hostID}`,
    `Thread: ${report.threadID}`,
    `UI budget: ${report.uiBudgetMS} ms`,
    `Upstream ack delay: ${report.upstreamAckDelayMS} ms`,
    `Turn/start requests: ${report.fixture.turnStartRequests.length}`,
  ];
  if (report.uiResult?.timings) {
    lines.push(
      "",
      "## Timings",
      "",
      `- Composer clear: ${report.uiResult.timings.composerClearMS} ms`,
      `- Pending row: ${report.uiResult.timings.pendingObservedMS} ms`,
      `- Canonical row: ${report.uiResult.timings.canonicalObservedMS} ms`,
    );
  }
  fs.writeFileSync(filePath, `${lines.join("\n")}\n`);
}

function appServerResponse(id, result) {
  return JSON.stringify({ id, result });
}

function nowSeconds() {
  return Math.floor(Date.now() / 1_000);
}

function makeThread({ threadID, title }) {
  return {
    id: threadID,
    sessionId: `${threadID}-session`,
    preview: title,
    name: title,
    createdAt: 1_800_000_000,
    updatedAt: 1_800_000_000,
    source: "cli",
    status: { type: "running" },
    cwd: "/tmp/codex-client",
    gitInfo: { branch: "main" },
  };
}

async function startFixtureAppServer({ threadID, title, messageText, upstreamAckDelayMS }) {
  const wss = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  const clients = new Set();
  const thread = makeThread({ threadID, title });
  const turns = [];
  const turnStartRequests = [];
  await onceListening(wss);
  const address = wss.address();
  const url = `ws://127.0.0.1:${address.port}`;

  wss.on("connection", (ws) => {
    clients.add(ws);
    ws.on("close", () => clients.delete(ws));
    ws.on("message", (raw) => {
      const message = JSON.parse(raw.toString());
      if (message.method === "initialize") {
        ws.send(appServerResponse(message.id, {
          userAgent: "codex-user-message-latency-fixture",
          codexHome: "/tmp/codex-client-user-message-proof",
          platformFamily: "unix",
          platformOs: "macos",
        }));
      } else if (message.method === "thread/list") {
        ws.send(appServerResponse(message.id, {
          data: [thread],
          nextCursor: null,
          backwardsCursor: null,
        }));
      } else if (message.method === "thread/loaded/list") {
        ws.send(appServerResponse(message.id, { data: [threadID] }));
      } else if (message.method === "thread/read" || message.method === "thread/resume") {
        ws.send(appServerResponse(message.id, { thread }));
      } else if (message.method === "thread/turns/list") {
        ws.send(appServerResponse(message.id, {
          data: turns,
          nextCursor: null,
          backwardsCursor: null,
        }));
      } else if (message.method === "turn/start") {
        turnStartRequests.push({
          receivedAt: new Date().toISOString(),
          params: message.params,
        });
        const clientID = message.params?.clientUserMessageId || "missing-client-id";
        const startedAt = nowSeconds();
        turns.splice(0, turns.length, {
          id: "turn-proof",
          startedAt,
          completedAt: startedAt + 1,
          items: [{
            id: "item-user-proof",
            type: "userMessage",
            clientId: clientID,
            content: [{ text: messageText }],
          }],
        });
        thread.updatedAt = startedAt + 1;
        setTimeout(() => {
          if (ws.readyState === 1) {
            ws.send(appServerResponse(message.id, {
              turn: {
                id: "turn-proof",
                status: "inProgress",
              },
            }));
          }
        }, upstreamAckDelayMS);
      }
    });
  });

  return {
    url,
    thread,
    turns,
    turnStartRequests,
    close: async () => {
      for (const ws of clients) {
        ws.close();
      }
      await closeWebSocketServer(wss);
    },
  };
}

function sleep(ms) {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

async function waitForResultOrStop(options) {
  const deadline = Date.now() + options.waitTimeoutMS;
  while (Date.now() < deadline) {
    if (fs.existsSync(options.uiResultIn)) {
      return "ui-result";
    }
    if (fs.existsSync(options.stopIn)) {
      return "stopped";
    }
    await sleep(100);
  }
  return "timeout";
}

function readJSONIfExists(filePath) {
  if (!fs.existsSync(filePath)) {
    return null;
  }
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function statusFrom({ uiResult, fixture }) {
  if (!uiResult) {
    return {
      status: "blocked",
      reason: "UI result was not written.",
    };
  }
  if (uiResult.status !== "pass") {
    return {
      status: uiResult.status || "fail",
      reason: uiResult.reason || "UI proof did not pass.",
    };
  }
  if (fixture.turnStartRequests.length !== 1) {
    return {
      status: "fail",
      reason: `Expected exactly one upstream turn/start request, got ${fixture.turnStartRequests.length}.`,
    };
  }
  const params = fixture.turnStartRequests[0].params || {};
  if (!String(params.clientUserMessageId || "").startsWith("dock-msg:")) {
    return {
      status: "fail",
      reason: "Upstream turn/start did not include a dock-msg clientUserMessageId.",
    };
  }
  return {
    status: "pass",
    reason: null,
  };
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  const proofRunID = `user-message-${Date.now()}-${randomUUID()}`;
  const hostID = "sim-user-message-latency-fixture";
  const threadID = "sim-user-message-latency-thread";
  const title = "User Message Latency Proof";
  const messageText = "UI latency proof";
  const appServer = await startFixtureAppServer({
    threadID,
    title,
    messageText,
    upstreamAckDelayMS: options.upstreamAckDelayMS,
  });
  const relayConfig = {
    listenHost: "127.0.0.1",
    port: 0,
    phoneAuth: "none",
    ...appServerRegistryFixtureConfig({
      historyUrl: appServer.url,
      historyBearerToken: "test-token",
      codexHome: "/tmp/codex-client-user-message-proof",
    }),
    advertiseBonjour: false,
    relayStateDatabasePath: ":memory:",
    hostId: hostID,
    hostName: "User Message Latency Fixture",
  };
  const relay = startServer(relayConfig);
  await relay.listening;
  try {
    await relayConfig.relayStateEngine.reconcileDock({ reason: "user_message_latency_fixture_ready" });
    const ready = {
      proofRunID,
      hosts: `127.0.0.1:${relayConfig.port}`,
      hostID,
      threadID,
      title,
      messageText,
      uiResultPath: options.uiResultIn,
      upstreamAckDelayMS: options.upstreamAckDelayMS,
      uiBudgetMS: options.uiBudgetMS,
    };
    writeJSON(options.readyOut, ready);
    const waitStatus = await waitForResultOrStop(options);
    const uiResult = readJSONIfExists(options.uiResultIn);
    const fixture = {
      waitStatus,
      turnStartRequests: appServer.turnStartRequests,
      turns: appServer.turns,
    };
    const outcome = statusFrom({ uiResult, fixture });
    const report = {
      schemaVersion: 1,
      kind: "codex-dock-user-message-latency-proof",
      proofRunID,
      status: outcome.status,
      reason: outcome.reason,
      generatedAt: new Date().toISOString(),
      hostID,
      threadID,
      title,
      messageText,
      upstreamAckDelayMS: options.upstreamAckDelayMS,
      uiBudgetMS: options.uiBudgetMS,
      relayUrl: `ws://127.0.0.1:${relayConfig.port}`,
      uiResult,
      fixture,
    };
    writeJSON(options.jsonOut, report);
    writeSummary(options.summaryOut, report);
    if (report.status !== "pass") {
      process.exitCode = 1;
    }
  } finally {
    await relay.close().catch(() => null);
    await appServer.close().catch(() => null);
  }
}

main().catch((error) => {
  console.error(`user-message-latency-fixture failed: ${error.message || error}`);
  process.exit(1);
});

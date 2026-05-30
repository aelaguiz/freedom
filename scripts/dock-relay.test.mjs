import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { WebSocketServer } from "ws";

import {
  attentionFlagsForServerRequest,
  buildBonjourAdvertisementArgs,
  isPhoneRequestAuthorized,
  mergeActiveFlags,
  preferThread,
  sanitizeRelayFields,
  startServer,
  statusPriority,
  threadMatchesSourceKinds,
} from "./dock-relay.mjs";
import { createRelayLogger } from "./dock-relay-logger.mjs";
import { liveOverlayForSnapshot } from "./dock-relay-live-status-cache.mjs";
import {
  bufferedDockUpdateIsAfterSnapshot,
  DockSessionAggregator,
  DockSessionTable,
  dockUpdateForSubscriber,
  normalizedStatus,
} from "./dock-relay-session-table.mjs";
import { ThreadSummaryCache } from "./dock-relay-thread-summary-cache.mjs";
import {
  clampThreadListParams,
  disabledLiveOverlay,
  liveStatusCacheForConfig,
} from "./dock-relay-thread-data.mjs";

import {
  closeWebSocketServer,
  jsonRpcRequest,
  onceListening,
  openWebSocket,
} from "./dock-relay-test-helpers.mjs";
import { DOCK_SESSION_SCHEMA_VERSION } from "./dock-relay-constants.mjs";

test("relay logger redacts credentials and payload fields", () => {
  const lines = [];
  const logger = createRelayLogger({
    stream: {
      write(line) {
        lines.push(line);
      },
    },
    clock: () => new Date("2026-05-28T00:00:00.000Z"),
  });

  logger.info("relay.redaction_test", {
    authorization: "Bearer sk-test-secret-token",
    openAIAPIKey: "sk-test-secret-token",
    base64Audio: Buffer.from("raw audio bytes").toString("base64"),
    transcript: "private transcript",
    endpointUrl: "ws://user:pass@127.0.0.1:4510/path?token=secret#frag",
    params: {
      prompt: "private prompt",
    },
  });

  assert.equal(lines.length, 1);
  const parsed = JSON.parse(lines[0]);
  assert.equal(parsed.timestamp, "2026-05-28T00:00:00.000Z");
  assert.equal(parsed.level, "info");
  assert.equal(parsed.fields.authorization, "<redacted>");
  assert.equal(parsed.fields.openAIAPIKey, "<redacted>");
  assert.equal(parsed.fields.base64Audio, "<redacted>");
  assert.equal(parsed.fields.transcript, "<redacted>");
  assert.equal(parsed.fields.params, "<redacted-payload>");
  assert.equal(parsed.fields.endpointUrl, "ws://127.0.0.1:4510/path");

  const text = lines.join("\n");
  assert.equal(text.includes("sk-test-secret-token"), false);
  assert.equal(text.includes("raw audio bytes"), false);
  assert.equal(text.includes("private transcript"), false);
  assert.equal(text.includes("private prompt"), false);
  assert.equal(text.includes("user:pass"), false);
});

test("attention flags are derived from real app-server request methods", () => {
  assert.deepEqual(
    attentionFlagsForServerRequest({
      method: "item/commandExecution/requestApproval",
    }),
    ["waitingOnApproval"],
  );
  assert.deepEqual(
    attentionFlagsForServerRequest({
      method: "item/tool/requestUserInput",
    }),
    ["waitingOnUserInput"],
  );
  assert.deepEqual(
    attentionFlagsForServerRequest({
      method: "mcpServer/elicitation/request",
    }),
    ["waitingOnUserInput"],
  );
  assert.deepEqual(
    attentionFlagsForServerRequest({
      method: "thread/status/changed",
    }),
    [],
  );
});

test("mergeActiveFlags preserves existing active flags", () => {
  const row = {
    id: "thread-1",
    status: {
      type: "active",
      activeFlags: ["waitingOnApproval"],
    },
  };

  assert.deepEqual(
    mergeActiveFlags(row, ["waitingOnUserInput"]),
    {
      id: "thread-1",
      status: {
        type: "active",
        activeFlags: ["waitingOnApproval", "waitingOnUserInput"],
      },
    },
  );
});

test("active attention outranks plain active when deduping live rows", () => {
  const plain = {
    id: "thread-1",
    updatedAt: 10,
    status: {
      type: "active",
      activeFlags: [],
    },
  };
  const needsAttention = {
    id: "thread-1",
    updatedAt: 9,
    status: {
      type: "active",
      activeFlags: ["waitingOnUserInput"],
    },
  };

  assert.equal(statusPriority(needsAttention), 0);
  assert.equal(preferThread(plain, needsAttention), needsAttention);
});

test("dock stream status normalization has product-facing names", () => {
  assert.equal(normalizedStatus({ status: { type: "notLoaded" } }), "dormant");
  assert.equal(normalizedStatus({ status: { type: "idle" } }), "idle");
  assert.equal(normalizedStatus({ status: { type: "systemError" } }), "error");
  assert.equal(normalizedStatus({ status: { type: "active", activeFlags: [] } }), "running");
  assert.equal(
    normalizedStatus({
      status: {
        type: "active",
        activeFlags: ["waitingOnUserInput"],
      },
    }),
    "needsInput",
  );
  assert.equal(
    normalizedStatus({
      status: {
        type: "active",
        activeFlags: ["waitingOnApproval", "waitingOnUserInput"],
      },
    }),
    "needsApproval",
  );
});

test("dock session table emits deltas and keeps last-good rows on refresh failure", () => {
  const host = { id: "Amir-M5", displayName: "Amir M5", endpoint: "amir-m5.local:4510" };
  const table = new DockSessionTable({ hostId: host.id, hostName: host.displayName });
  const session = {
    id: "Amir-M5::thread-1",
    hostID: "Amir-M5",
    threadID: "thread-1",
    backendSessionID: "session-1",
    title: "Build Dock",
    status: "running",
    repository: "codex-client",
    workingDirectory: "/Users/aelaguiz/workspace/codex-client",
    branch: "main",
    updatedAt: 10,
    summary: "Working",
    source: { kind: "human" },
  };

  const firstUpdate = table.applySuccessfulRefresh({
    host,
    sessions: [session],
    asOf: "2026-05-29T10:00:00.000Z",
  });
  assert.equal(firstUpdate.kind, "delta");
  assert.equal(firstUpdate.baseSeq, 0);
  assert.equal(firstUpdate.seq, 1);
  assert.deepEqual(firstUpdate.upsertSessions.map((row) => row.threadID), ["thread-1"]);

  const heartbeat = table.applySuccessfulRefresh({
    host,
    sessions: [session],
    asOf: "2026-05-29T10:00:01.000Z",
  });
  assert.equal(heartbeat.kind, "heartbeat");
  assert.equal(heartbeat.seq, 1);

  const failed = table.applyFailedRefresh(new Error("upstream unavailable"));
  assert.equal(failed.kind, "heartbeat");
  assert.equal(failed.seq, 1);
  assert.equal(failed.freshness.status, "stale");
  assert.match(failed.freshness.lastError, /upstream unavailable/);
  assert.deepEqual(table.snapshot().sessions.map((row) => row.threadID), ["thread-1"]);
});

test("dock session aggregator uses provider boundary and loads persisted rows stale-on-boot", async () => {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "codex-dock-relay-session-table-"));
  const persistedPath = path.join(tempDir, "session-table.json");
  const host = { id: "Amir-M5", displayName: "Amir M5", endpoint: "amir-m5.local:4510" };
  const session = {
    id: "Amir-M5::thread-1",
    hostID: "Amir-M5",
    threadID: "thread-1",
    backendSessionID: "session-1",
    title: "Build Dock",
    status: "running",
    lane: "human",
    kindLabel: "Human",
    repository: "codex-client",
    workingDirectory: "/Users/aelaguiz/workspace/codex-client",
    branch: "main",
    updatedAt: 10,
    summary: "Working",
    source: { kind: "human" },
  };
  const provider = {
    async listSessions() {
      return { host, sessions: [session] };
    },
  };

  try {
    const aggregator = new DockSessionAggregator(
      { hostId: host.id, hostName: host.displayName },
      { provider, persistencePath: persistedPath, refreshIntervalMs: 60_000 },
    );
    await aggregator.refreshNow({ notify: false });
    aggregator.stop();

    const persisted = JSON.parse(fs.readFileSync(persistedPath, "utf8"));
    assert.equal(persisted.schemaVersion, DOCK_SESSION_SCHEMA_VERSION);
    assert.deepEqual(persisted.sessions.map((row) => row.threadID), ["thread-1"]);

    const restarted = new DockSessionAggregator(
      { hostId: host.id, hostName: host.displayName },
      {
        provider: {
          async listSessions() {
            throw new Error("provider offline");
          },
        },
        persistencePath: persistedPath,
        refreshIntervalMs: 60_000,
      },
    );
    assert.equal(restarted.currentSnapshot().freshness.status, "stale");
    assert.deepEqual(restarted.currentSnapshot().sessions.map((row) => row.threadID), ["thread-1"]);

    const snapshot = await restarted.snapshot();
    assert.equal(snapshot.freshness.status, "stale");
    assert.match(snapshot.freshness.lastError, /provider offline/);
    assert.deepEqual(snapshot.sessions.map((row) => row.threadID), ["thread-1"]);
    restarted.stop();
  } finally {
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
});

test("dock session aggregator ignores persisted rows with incompatible schema", () => {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "codex-dock-relay-session-schema-"));
  const persistedPath = path.join(tempDir, "session-table.json");
  try {
    fs.writeFileSync(
      persistedPath,
      JSON.stringify({
        schemaVersion: DOCK_SESSION_SCHEMA_VERSION + 1,
        hosts: [{ id: "old-host" }],
        sessions: [{ id: "old-host::thread-1", threadID: "thread-1" }],
      }),
    );
    const aggregator = new DockSessionAggregator(
      { hostId: "Amir-M5", hostName: "Amir M5" },
      {
        provider: {
          async listSessions() {
            throw new Error("provider offline");
          },
        },
        persistencePath: persistedPath,
        refreshIntervalMs: 60_000,
      },
    );

    const snapshot = aggregator.currentSnapshot();
    assert.equal(snapshot.schemaVersion, DOCK_SESSION_SCHEMA_VERSION);
    assert.equal(snapshot.freshness.status, "unknown");
    assert.deepEqual(snapshot.sessions, []);
    assert.deepEqual(snapshot.hosts.map((host) => host.id), ["Amir-M5"]);
    aggregator.stop();
  } finally {
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
});

test("dock stream coalesces slow subscriber deltas to snapshots", () => {
  const delta = { kind: "delta", seq: 2 };
  const snapshot = { kind: "snapshot", seq: 3 };
  const aggregator = {
    currentSnapshot() {
      return snapshot;
    },
  };

  assert.equal(dockUpdateForSubscriber(aggregator, { bufferedAmount: 0 }, delta), delta);
  assert.equal(
    dockUpdateForSubscriber(aggregator, { bufferedAmount: 2 * 1024 * 1024 }, delta),
    snapshot
  );
});

test("dock subscribe drops buffered updates already covered by snapshot", () => {
  const snapshot = {
    epoch: "epoch-1",
    seq: 10,
  };

  assert.equal(bufferedDockUpdateIsAfterSnapshot(snapshot, {
    kind: "delta",
    epoch: "epoch-1",
    baseSeq: 9,
    seq: 10,
  }), false);
  assert.equal(bufferedDockUpdateIsAfterSnapshot(snapshot, {
    kind: "heartbeat",
    epoch: "epoch-1",
    seq: 10,
  }), false);
  assert.equal(bufferedDockUpdateIsAfterSnapshot(snapshot, {
    kind: "delta",
    epoch: "epoch-1",
    baseSeq: 10,
    seq: 11,
  }), true);
  assert.equal(bufferedDockUpdateIsAfterSnapshot(snapshot, {
    kind: "delta",
    epoch: "older-epoch",
    baseSeq: 10,
    seq: 11,
  }), false);
});

test("thread/list params clamp to Codex's 250 row page cap", () => {
  assert.deepEqual(clampThreadListParams({ limit: 500 }), { limit: 250 });
  assert.deepEqual(clampThreadListParams({ limit: 0, cursor: "abc" }), {
    limit: 250,
    cursor: "abc",
  });
  assert.deepEqual(clampThreadListParams({ limit: 37, archived: true }), {
    limit: 37,
    archived: true,
  });
});

test("thread summary cache keeps the last useful summary while a row version warms", () => {
  const cache = new ThreadSummaryCache({
    readThreadTurns: async () => ({ data: [] }),
  });
  cache.remember("thread-1", {
    version: "10",
    summary: "Latest known useful update",
    checkedAtMs: 1,
  });

  const decorated = cache.decorateRows([
    {
      id: "thread-1",
      preview: "Original opening prompt",
      updatedAt: 20,
    },
  ]);

  assert.equal(decorated[0].latestSummary, "Latest known useful update");
});

test("phase 2 live overlay is explicit degraded metadata", () => {
  assert.deepEqual(disabledLiveOverlay(), {
    ok: false,
    state: "disabled",
    ageMs: null,
  });
});

test("phase 3 live overlay reports partial live discovery failure", () => {
  const now = Date.now();
  const overlay = liveOverlayForSnapshot({
    ok: true,
    checkedAtMs: now,
    endpoints: [{ url: "ws://127.0.0.1:4511" }],
    failedEndpoints: 1,
    rows: [],
  });

  assert.equal(overlay.ok, false);
  assert.equal(overlay.state, "degraded");
  assert.equal(overlay.endpoints, 1);
  assert.equal(overlay.failedEndpoints, 1);
});

test("live status default refresh cadence stays below stale threshold", () => {
  const cache = liveStatusCacheForConfig({
    historyUrl: "ws://127.0.0.1:4500",
  });

  assert.equal(cache.refreshIntervalMs < cache.maxAgeMs, true);
  assert.equal(cache.refreshIntervalMs, 2_500);
  assert.equal(cache.maxAgeMs, 5_000);
});

test("default thread/list sourceKinds keeps only interactive live sources", () => {
  const cases = [
    ["cli", { source: "cli" }, true],
    ["vscode", { source: "vscode" }, true],
    ["atlas custom", { source: { custom: "atlas" } }, true],
    ["chatgpt custom", { source: { custom: "chatgpt" } }, true],
    ["atlas legacy string", { source: "atlas" }, true],
    ["exec", { source: "exec" }, false],
    ["appServer", { source: "appServer" }, false],
    ["appServer object", { source: { appServer: {} } }, false],
    ["mcp alias", { source: "mcp" }, false],
    ["mcp object", { source: { mcp: {} } }, false],
    ["subAgent", { source: { subAgent: "review" } }, false],
    ["unknown", { source: "unknown" }, false],
    ["missing source", {}, false],
  ];

  for (const [name, row, expected] of cases) {
    assert.equal(threadMatchesSourceKinds(row), expected, name);
    assert.equal(threadMatchesSourceKinds(row, []), expected, `${name} empty sourceKinds`);
  }
});

test("explicit agent sourceKinds include live automation and unknown rows", () => {
  const agentKinds = [
    "exec",
    "appServer",
    "subAgentReview",
    "subAgentCompact",
    "subAgentThreadSpawn",
    "subAgentOther",
    "unknown",
  ];

  assert.equal(threadMatchesSourceKinds({ source: "exec" }, agentKinds), true);
  assert.equal(threadMatchesSourceKinds({ source: { exec: {} } }, agentKinds), true);
  assert.equal(threadMatchesSourceKinds({ source: "appServer" }, agentKinds), true);
  assert.equal(threadMatchesSourceKinds({ source: { appServer: {} } }, agentKinds), true);
  assert.equal(threadMatchesSourceKinds({ source: "mcp" }, agentKinds), true);
  assert.equal(threadMatchesSourceKinds({ source: { mcp: {} } }, agentKinds), true);
  assert.equal(threadMatchesSourceKinds({ source: { subAgent: "review" } }, agentKinds), true);
  assert.equal(threadMatchesSourceKinds({ source: "subAgentReview" }, agentKinds), true);
  assert.equal(threadMatchesSourceKinds({ source: { sourceKind: "subAgentCompact" } }, agentKinds), true);
  assert.equal(threadMatchesSourceKinds({ source: { subAgent: "memory_consolidation" } }, agentKinds), false);
  assert.equal(threadMatchesSourceKinds({ source: "unknown" }, agentKinds), true);
  assert.equal(threadMatchesSourceKinds({}, agentKinds), true);
  assert.equal(threadMatchesSourceKinds({ source: "cli" }, agentKinds), false);
  assert.equal(threadMatchesSourceKinds({ source: { custom: "atlas" } }, agentKinds), false);
});

test("contradictory live source metadata maps to unknown", () => {
  const familyConflict = {
    source: {
      cli: {},
      subAgent: "review",
    },
  };
  const variantConflict = {
    source: {
      subAgent: ["review", "compact"],
    },
  };

  assert.equal(threadMatchesSourceKinds(familyConflict), false);
  assert.equal(threadMatchesSourceKinds(familyConflict, ["subAgent"]), false);
  assert.equal(threadMatchesSourceKinds(familyConflict, ["unknown"]), true);

  assert.equal(threadMatchesSourceKinds(variantConflict), false);
  assert.equal(threadMatchesSourceKinds(variantConflict, ["subAgentReview"]), false);
  assert.equal(threadMatchesSourceKinds(variantConflict, ["subAgentCompact"]), false);
  assert.equal(threadMatchesSourceKinds(variantConflict, ["unknown"]), true);
});

test("internal memory live source metadata stays out of filtered scopes", () => {
  const row = { source: "unknown", threadSource: "memory_consolidation" };
  const snakeCaseRow = { source: "unknown", thread_source: "memory_consolidation" };
  const sourceStringRow = { source: "memory_consolidation" };
  const subAgentRow = { source: { subAgent: "memory_consolidation" } };

  assert.equal(threadMatchesSourceKinds(row), false);
  assert.equal(threadMatchesSourceKinds(row, ["subAgent"]), false);
  assert.equal(threadMatchesSourceKinds(row, ["unknown"]), false);
  assert.equal(threadMatchesSourceKinds(snakeCaseRow, ["unknown"]), false);
  assert.equal(threadMatchesSourceKinds(sourceStringRow, ["unknown"]), false);
  assert.equal(threadMatchesSourceKinds(subAgentRow, ["subAgent"]), false);
  assert.equal(threadMatchesSourceKinds(subAgentRow, ["unknown"]), false);
});

test("subAgent sourceKinds match broad and specific live variants", () => {
  const review = { source: { subAgent: "review" } };
  const compact = { source: { subAgent: "compact" } };
  const threadSpawn = {
    source: {
      subAgent: {
        thread_spawn: {
          parent_thread_id: "parent-thread",
          depth: 1,
        },
      },
    },
  };
  const other = { source: { subAgent: { other: "custom-agent" } } };

  assert.equal(threadMatchesSourceKinds(review, ["subAgent"]), true);
  assert.equal(threadMatchesSourceKinds(threadSpawn, ["subAgent"]), true);

  assert.equal(threadMatchesSourceKinds(review, ["subAgentReview"]), true);
  assert.equal(threadMatchesSourceKinds(review, ["subAgentCompact"]), false);
  assert.equal(threadMatchesSourceKinds(compact, ["subAgentCompact"]), true);
  assert.equal(threadMatchesSourceKinds(threadSpawn, ["subAgentThreadSpawn"]), true);
  assert.equal(threadMatchesSourceKinds(other, ["subAgentOther"]), true);
});

test("relay source marker is never returned to clients", () => {
  assert.deepEqual(
    sanitizeRelayFields({
      id: "thread-1",
      dockRelaySource: { url: "ws://127.0.0.1:4555" },
    }),
    { id: "thread-1" },
  );
});

test("phone auth none permits local phone connections without a bearer token", () => {
  assert.equal(
    isPhoneRequestAuthorized({ headers: {} }, { phoneAuth: "none" }),
    true,
  );
  assert.equal(
    isPhoneRequestAuthorized(
      { headers: { authorization: "Bearer wrong" } },
      { phoneAuth: "bearer", relayBearerToken: "right" },
    ),
    false,
  );
  assert.equal(
    isPhoneRequestAuthorized(
      { headers: { authorization: "Bearer right" } },
      { phoneAuth: "bearer", relayBearerToken: "right" },
    ),
    true,
  );
});

test("Bonjour advertisement contains only non-secret relay metadata", () => {
  const args = buildBonjourAdvertisementArgs({
    bonjourName: "Codex Dock Test",
    hostId: "Amir-M5",
    phoneAuth: "none",
    port: 4510,
    version: "0.1.0",
  });

  assert.deepEqual(args.slice(0, 5), [
    "-R",
    "Codex Dock Test",
    "_codexdock._tcp",
    "local",
    "4510",
  ]);
  assert.ok(args.includes("version=0.1.0"));
  assert.ok(args.includes("relay-id=Amir-M5"));
  assert.equal(args.includes("auth=none"), false);
  assert.equal(args.includes("scheme=ws"), false);
  assert.equal(args.some((value) => /token|secret|key/i.test(value)), false);
});

test("relay rejects legacy raw audio/transcribe after realtime cutover", async () => {
  const relay = startServer({
    listenHost: "127.0.0.1",
    port: 0,
    phoneAuth: "none",
    historyUrl: "ws://127.0.0.1:1",
    historyBearerToken: "history-token",
    advertiseBonjour: false,
  });
  await relay.listening;
  const ws = await openWebSocket(`ws://127.0.0.1:${relay.server.address().port}`);

  try {
    const response = await jsonRpcRequest(ws, "audio/transcribe", {
      mimeType: "audio/mp4",
      base64Audio: Buffer.from("legacy audio").toString("base64"),
    });

    assert.equal(response.result, undefined);
    assert.equal(response.error.code, -32601);
    assert.match(response.error.message, /unsupported method: audio\/transcribe/);
  } finally {
    ws.close();
    await relay.close();
  }
});

test("relay keeps the raw history app-server token on the Mac side", async () => {
  let observedAuthorization = null;
  const historyServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await onceListening(historyServer);
  historyServer.on("connection", (ws, request) => {
    observedAuthorization = request.headers.authorization;
    ws.on("message", (data) => {
      const message = JSON.parse(data.toString());
      if (message.method === "initialize") {
        ws.send(JSON.stringify({
          id: message.id,
          result: {
            userAgent: "codex-test",
            codexHome: "/tmp/codex",
            platformFamily: "unix",
            platformOs: "macos",
          },
        }));
      } else if (message.method === "thread/list") {
        ws.send(JSON.stringify({
          id: message.id,
          result: {
            data: [],
            nextCursor: null,
            backwardsCursor: null,
          },
        }));
      }
    });
  });

  const relay = startServer({
    listenHost: "127.0.0.1",
    port: 0,
    phoneAuth: "none",
    historyUrl: `ws://127.0.0.1:${historyServer.address().port}`,
    historyBearerToken: "history-token",
    advertiseBonjour: false,
  });
  await relay.listening;
  const ws = await openWebSocket(`ws://127.0.0.1:${relay.server.address().port}`);

  try {
    const response = await jsonRpcRequest(ws, "thread/list", { archived: true });
    assert.deepEqual(response.result.data, []);
    assert.equal(observedAuthorization, "Bearer history-token");
  } finally {
    ws.close();
    await relay.close();
    await closeWebSocketServer(historyServer);
  }
});

test("dock/subscribe returns a normalized relay-owned session snapshot", async () => {
  let observedAuthorization = null;
  const observedThreadListParams = [];
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "codex-dock-relay-test-"));
  const historyServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await onceListening(historyServer);
  historyServer.on("connection", (ws, request) => {
    observedAuthorization = request.headers.authorization;
    ws.on("message", (data) => {
      const message = JSON.parse(data.toString());
      if (message.method === "initialize") {
        ws.send(JSON.stringify({
          id: message.id,
          result: {
            userAgent: "codex-test",
            codexHome: "/tmp/codex",
            platformFamily: "unix",
            platformOs: "macos",
          },
        }));
      } else if (message.method === "thread/list") {
        observedThreadListParams.push(message.params || {});
        const isAgentRequest = Array.isArray(message.params?.sourceKinds);
        ws.send(JSON.stringify({
          id: message.id,
          result: {
            data: isAgentRequest ? [
              {
                id: "agent-thread",
                sessionId: "agent-session",
                preview: "Agent thread",
                updatedAt: 1_780_000_200,
                status: {
                  type: "active",
                  activeFlags: ["waitingOnApproval"],
                },
                cwd: "/Users/aelaguiz/workspace/codex-client",
                gitInfo: {
                  branch: "feature/relay-table",
                  originUrl: "codex-client",
                },
                source: "exec",
                dockRelaySource: {
                  bearerToken: "must-not-leak",
                },
              },
            ] : [
              {
                id: "history-thread",
                sessionId: "history-session",
                preview: "History thread",
                latestSummary: "Stored history row",
                updatedAt: 1_780_000_100,
                status: {
                  type: "notLoaded",
                },
                cwd: "/Users/aelaguiz/workspace/codex-client",
                gitInfo: {
                  branch: "main",
                  originUrl: "codex-client",
                },
                source: "cli",
              },
            ],
            nextCursor: null,
            backwardsCursor: null,
          },
        }));
      }
    });
  });

  const relay = startServer({
    listenHost: "127.0.0.1",
    port: 0,
    phoneAuth: "none",
    historyUrl: `ws://127.0.0.1:${historyServer.address().port}`,
    historyBearerToken: "history-token",
    hostId: "Amir-M5",
    hostName: "Amir M5",
    advertiseBonjour: false,
    dockSessionPersistencePath: path.join(tempDir, "session-table.json"),
    dockSessionRefreshIntervalMs: 60_000,
  });
  await relay.listening;
  const ws = await openWebSocket(`ws://127.0.0.1:${relay.server.address().port}`);

  try {
    const response = await jsonRpcRequest(ws, "dock/subscribe");

    assert.equal(observedAuthorization, "Bearer history-token");
    assert.equal(observedThreadListParams.length, 2);
    assert.equal(response.error, undefined);
    assert.equal(response.result.kind, "snapshot");
    assert.equal(response.result.hosts[0].id, "Amir-M5");
    assert.deepEqual(
      response.result.sessions.map((row) => [row.threadID, row.status, row.lane, row.kindLabel, row.source.kind]),
      [
        ["agent-thread", "needsApproval", "agent", "exec", "automation"],
        ["history-thread", "dormant", "human", "cli", "human"],
      ],
    );
    assert.equal(JSON.stringify(response.result).includes("notLoaded"), false);
    assert.equal(JSON.stringify(response.result).includes("must-not-leak"), false);
  } finally {
    ws.close();
    await relay.close();
    await closeWebSocketServer(historyServer);
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
});

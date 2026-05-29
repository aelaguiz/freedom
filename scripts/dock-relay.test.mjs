import assert from "node:assert/strict";
import test from "node:test";
import { WebSocketServer } from "ws";

import {
  attentionFlagsForServerRequest,
  buildBonjourAdvertisementArgs,
  isPhoneRequestAuthorized,
  mergeThreadListRows,
  mergeActiveFlags,
  preferThread,
  sanitizeRelayFields,
  shouldCollectLiveRowsForThreadList,
  startServer,
  statusPriority,
  threadMatchesSourceKinds,
} from "./dock-relay.mjs";
import { createRelayLogger } from "./dock-relay-logger.mjs";

import {
  closeWebSocketServer,
  jsonRpcRequest,
  onceListening,
  openWebSocket,
} from "./dock-relay-test-helpers.mjs";

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

test("archived thread/list does not merge live loopback rows", () => {
  assert.equal(shouldCollectLiveRowsForThreadList({ archived: true }), false);
  assert.equal(shouldCollectLiveRowsForThreadList({ archived: false }), true);
  assert.equal(shouldCollectLiveRowsForThreadList({}), true);
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

test("thread/list live merge applies source filtering before sanitizing results", () => {
  const historyRows = [
    { id: "history-human", source: "cli", updatedAt: 10 },
  ];
  const liveRows = [
    {
      id: "live-human",
      source: { custom: "chatgpt" },
      updatedAt: 30,
      dockRelaySource: { url: "ws://127.0.0.1:4555" },
    },
    {
      id: "live-exec",
      source: "exec",
      updatedAt: 40,
      dockRelaySource: { url: "ws://127.0.0.1:4556" },
    },
    {
      id: "live-subagent",
      source: { subAgent: "review" },
      updatedAt: 50,
      dockRelaySource: { url: "ws://127.0.0.1:4557" },
    },
  ];

  const filteredLiveRows = liveRows.filter((row) => threadMatchesSourceKinds(row));
  const data = mergeThreadListRows(historyRows, filteredLiveRows);

  assert.deepEqual(data.map((row) => row.id), ["live-human", "history-human"]);
  assert.equal(Object.hasOwn(data[0], "dockRelaySource"), false);
});

test("thread/list live merge borrows fresher history timestamp for same thread id", () => {
  const historyRows = [
    {
      id: "active-stale-read",
      updatedAt: 300,
      status: { type: "notLoaded" },
    },
    {
      id: "other-live",
      updatedAt: 200,
      status: { type: "notLoaded" },
    },
  ];
  const liveRows = [
    {
      id: "active-stale-read",
      updatedAt: 10,
      source: "cli",
      status: { type: "active", activeFlags: ["waitingOnUserInput"] },
      dockRelaySource: { url: "ws://127.0.0.1:4555" },
    },
    {
      id: "other-live",
      updatedAt: 250,
      source: "cli",
      status: { type: "active", activeFlags: [] },
      dockRelaySource: { url: "ws://127.0.0.1:4556" },
    },
  ];

  const data = mergeThreadListRows(historyRows, liveRows);

  assert.deepEqual(data.map((row) => row.id), ["active-stale-read", "other-live"]);
  assert.equal(data[0].updatedAt, 300);
  assert.deepEqual(data[0].status, {
    type: "active",
    activeFlags: ["waitingOnUserInput"],
  });
  assert.equal(data[0].source, "cli");
  assert.equal(Object.hasOwn(data[0], "dockRelaySource"), false);
});

test("thread/list live merge does not downgrade fresher live timestamp", () => {
  const historyRows = [
    {
      id: "active-fresh-live",
      updatedAt: 10,
      status: { type: "notLoaded" },
    },
  ];
  const liveRows = [
    {
      id: "active-fresh-live",
      updatedAt: 300,
      status: { type: "active", activeFlags: [] },
      dockRelaySource: { url: "ws://127.0.0.1:4555" },
    },
  ];

  const data = mergeThreadListRows(historyRows, liveRows);

  assert.equal(data.length, 1);
  assert.equal(data[0].updatedAt, 300);
  assert.equal(data[0].status.type, "active");
});

test("thread/list duplicate live history row consumes one relay slot under limit", () => {
  const historyRows = [
    {
      id: "duplicate-thread",
      updatedAt: 300,
      status: { type: "notLoaded" },
    },
    {
      id: "history-fill",
      updatedAt: 200,
      status: { type: "idle" },
    },
  ];
  const liveRows = [
    {
      id: "duplicate-thread",
      updatedAt: 10,
      status: { type: "active", activeFlags: [] },
      dockRelaySource: { url: "ws://127.0.0.1:4555" },
    },
  ];

  const data = mergeThreadListRows(historyRows, liveRows, { limit: 2 });

  assert.deepEqual(data.map((row) => row.id), ["duplicate-thread", "history-fill"]);
  assert.equal(data[0].updatedAt, 300);
  assert.equal(data[0].status.type, "active");
});

test("thread/list keeps live rows inside relay limit before filling with history", () => {
  const historyRows = [
    { id: "history-newest", updatedAt: 100, status: { type: "idle" } },
    { id: "history-next", updatedAt: 90, status: { type: "idle" } },
  ];
  const liveRows = [
    {
      id: "live-older",
      updatedAt: 10,
      status: { type: "active", activeFlags: [] },
      dockRelaySource: { url: "ws://127.0.0.1:4555" },
    },
  ];

  const data = mergeThreadListRows(historyRows, liveRows, { limit: 2 });

  assert.deepEqual(data.map((row) => row.id), ["live-older", "history-newest"]);
  assert.equal(Object.hasOwn(data[0], "dockRelaySource"), false);
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

import assert from "node:assert/strict";
import test from "node:test";
import { WebSocketServer } from "ws";

import { startServer } from "./dock-relay.mjs";
import {
  closeWebSocketServer,
  jsonRpcRequest,
  onceListening,
  openWebSocket,
} from "./dock-relay-test-helpers.mjs";

test("relay/state/snapshot drains app-server list pages and preserves Codex order per scope", async () => {
  const observedThreadListParams = [];
  const historyServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await onceListening(historyServer);

  historyServer.on("connection", (ws) => {
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
        const params = message.params || {};
        observedThreadListParams.push(params);
        const scopeName = `${params.archived ? "archived" : "active"}:${params.sourceKinds?.[0] || "interactiveDefault"}`;
        const cursor = params.cursor || null;
        let result;
        if (scopeName === "active:interactiveDefault" && cursor === null) {
          result = {
            data: [
              { id: "thread-a", updatedAt: 30, source: "cli", status: { type: "notLoaded" } },
              { id: "thread-b", updatedAt: 20, source: "vscode", status: { type: "notLoaded" } },
            ],
            nextCursor: "page-2",
            backwardsCursor: null,
          };
        } else if (scopeName === "active:interactiveDefault" && cursor === "page-2") {
          result = {
            data: [
              { id: "thread-c", updatedAt: 10, source: "cli", status: { type: "notLoaded" } },
            ],
            nextCursor: null,
            backwardsCursor: "page-1",
          };
        } else if (scopeName === "archived:exec") {
          result = {
            data: [
              { id: "thread-archived-agent", updatedAt: 5, source: "exec", status: { type: "notLoaded" } },
            ],
            nextCursor: null,
            backwardsCursor: null,
          };
        } else {
          result = { data: [], nextCursor: null, backwardsCursor: null };
        }
        ws.send(JSON.stringify({ id: message.id, result }));
      } else if (message.method === "thread/read") {
        ws.send(JSON.stringify({
          id: message.id,
          result: {
            thread: {
              id: message.params.threadId,
              updatedAt: 1,
              status: { type: "notLoaded" },
            },
          },
        }));
      } else if (message.method === "thread/goal/get") {
        ws.send(JSON.stringify({
          id: message.id,
          result: {
            goal: message.params.threadId === "thread-a" ? {
              threadId: "thread-a",
              objective: "Keep the audit running",
              status: "active",
              tokenBudget: 1000,
              tokensUsed: 12,
              timeUsedSeconds: 3,
              createdAt: 1770000000,
              updatedAt: 1770000001,
            } : null,
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
    const response = await jsonRpcRequest(ws, "relay/state/snapshot", {
      includeArchived: true,
      includeThreadReads: true,
      includeGoals: true,
      includeLoaded: false,
      sourceScopes: ["interactiveDefault", "exec"],
      limit: 2,
    });

    assert.equal(response.error, undefined);
    assert.ok(observedThreadListParams.every((params) => params.includePreviewless === undefined));
    assert.equal(response.result.kind, "relayStateSnapshot");
    assert.equal(response.result.source, "app-server-only");
    assert.equal(response.result.threadCount, 4);

    const activeInteractive = response.result.scopes.find((scope) => scope.name === "active:interactiveDefault");
    assert.deepEqual(activeInteractive.threadIDsInCodexOrder, ["thread-a", "thread-b", "thread-c"]);
    assert.deepEqual(
      activeInteractive.pages.map((page) => [page.cursor, page.nextCursor, page.rowCount]),
      [
        [null, "page-2", 2],
        ["page-2", null, 1],
      ],
    );

    const archivedExec = response.result.scopes.find((scope) => scope.name === "archived:exec");
    assert.deepEqual(archivedExec.threadIDsInCodexOrder, ["thread-archived-agent"]);
    assert.ok(observedThreadListParams.some((params) => params.archived === true && params.sourceKinds?.[0] === "exec"));
    assert.ok(response.result.threads.every((thread) => thread.historyRead?.thread?.id === thread.threadID));
    assert.equal(response.result.threads.find((thread) => thread.threadID === "thread-a").goalRead.goal.status, "active");
    assert.equal(response.result.threads.find((thread) => thread.threadID === "thread-b").goalRead.goal, null);
    assert.equal(response.result.surfaceMeanings["thread/list"], "app-server list row scoped by archived/source filters; order is preserved within each scope only");
    assert.equal(response.result.surfaceMeanings["thread/turns/list"], "app-server turn pages for a known thread ID, preserved in returned page order; full items expose userMessage evidence for prompt-shape inference but not a formal thread-start source");
    const threadA = response.result.threads.find((thread) => thread.threadID === "thread-a");
    assert.equal(threadA.surfaceSummary.meaning, "comparison of app-server-provided list/read surfaces only; no disk or SQLite data is used");
    assert.equal(threadA.surfaceSummary.surfaceCounts.listRows, 1);
    assert.equal(threadA.surfaceSummary.surfaceCounts.historyRead, 1);
    assert.equal(threadA.surfaceSummary.surfaceCounts.routedRead, 1);
    assert.equal(threadA.surfaceSummary.hasConflicts, true);
    assert.ok(threadA.surfaceSummary.conflictingFields.includes("updatedAt"));
    assert.equal(
      response.result.surfaceMeanings.canonicalProjection,
      "relay-owned deterministic projection across app-server surfaces; field values prefer routed thread/read, then history thread/read, then app-server list rows in combined/default/list order",
    );
    assert.equal(
      threadA.surfaceSummary.canonicalProjection.meaning,
      "deterministic relay app-server projection; each field records the winning app-server surface and does not use disk or SQLite",
    );
    assert.deepEqual(threadA.surfaceSummary.canonicalProjection.priority, [
      "routed thread/read",
      "history thread/read",
      "thread/list:allSourceKinds",
      "thread/list:interactiveDefault",
      "thread/list",
    ]);
    assert.equal(threadA.surfaceSummary.canonicalProjection.fields.updatedAt.value, 1);
    assert.deepEqual(threadA.surfaceSummary.canonicalProjection.fields.updatedAt.source, {
      kind: "routed thread/read",
    });
    assert.equal(threadA.surfaceSummary.canonicalProjection.fields.updatedAt.valueCount, 2);
    assert.equal(threadA.surfaceSummary.canonicalProjection.fields.updatedAt.hasConflict, true);
    assert.ok(threadA.surfaceSummary.canonicalProjection.conflictFields.includes("updatedAt"));
    const updatedAtConflict = threadA.surfaceSummary.fieldConflicts.find((conflict) => conflict.field === "updatedAt");
    assert.deepEqual(
      updatedAtConflict.values.map((entry) => [entry.value, entry.surfaces.map((surface) => surface.kind)]),
      [
        [30, ["thread/list"]],
        [1, ["history thread/read", "routed thread/read"]],
      ],
    );
  } finally {
    ws.close();
    await relay.close();
    await closeWebSocketServer(historyServer);
  }
});

test("relay/state/snapshot drains thread turns in app-server order when requested", async () => {
  const observedTurnsListParams = [];
  const historyServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await onceListening(historyServer);

  historyServer.on("connection", (ws) => {
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
            data: message.params?.archived ? [] : [
              { id: "thread-with-turns", updatedAt: 10, source: "cli", status: { type: "notLoaded" } },
            ],
            nextCursor: null,
            backwardsCursor: null,
          },
        }));
      } else if (message.method === "thread/read") {
        ws.send(JSON.stringify({
          id: message.id,
          result: {
            thread: {
              id: message.params.threadId,
              updatedAt: 10,
              status: { type: "notLoaded" },
            },
          },
        }));
      } else if (message.method === "thread/turns/list") {
        observedTurnsListParams.push(message.params || {});
        const cursor = message.params?.cursor || null;
        ws.send(JSON.stringify({
          id: message.id,
          result: cursor ? {
            data: [{ id: "turn-3" }],
            nextCursor: null,
            backwardsCursor: "page-1",
          } : {
            data: [{ id: "turn-1" }, { id: "turn-2" }],
            nextCursor: "page-2",
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
    const response = await jsonRpcRequest(ws, "relay/state/snapshot", {
      includeArchived: false,
      includeTurns: true,
      includeLoaded: false,
      sourceScopes: ["interactiveDefault"],
      limit: 2,
    });

    assert.equal(response.error, undefined);
    assert.deepEqual(response.result.turnRequest, {
      included: true,
      sortDirection: "desc",
      itemsView: "notLoaded",
    });
    const thread = response.result.threads.find((row) => row.threadID === "thread-with-turns");
    assert.deepEqual(
      thread.turns.turnsInCodexOrder.map((turn) => turn.turn.id),
      ["turn-1", "turn-2", "turn-3"],
    );
    assert.equal(thread.turns.complete, true);
    assert.deepEqual(
      observedTurnsListParams.map((params) => [params.sortDirection, params.itemsView, params.limit, params.cursor || null]),
      [
        ["desc", "notLoaded", 2, null],
        ["desc", "notLoaded", 2, "page-2"],
      ],
    );
  } finally {
    ws.close();
    await relay.close();
    await closeWebSocketServer(historyServer);
  }
});

test("relay/state/snapshot default scopes include an all-source combined Codex order", async () => {
  const observedSourceKinds = [];
  const historyServer = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await onceListening(historyServer);

  historyServer.on("connection", (ws) => {
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
        observedSourceKinds.push(message.params?.sourceKinds || null);
        const sourceKinds = message.params?.sourceKinds || [];
        const isAllSourceScope = sourceKinds.includes("cli")
          && sourceKinds.includes("vscode")
          && sourceKinds.includes("subAgentThreadSpawn")
          && sourceKinds.includes("unknown");
        ws.send(JSON.stringify({
          id: message.id,
          result: {
            data: isAllSourceScope && !message.params?.archived ? [
              { id: "thread-combined-1", updatedAt: 30, source: "cli", status: { type: "notLoaded" } },
              { id: "thread-combined-2", updatedAt: 20, source: "exec", status: { type: "notLoaded" } },
            ] : [],
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
    const response = await jsonRpcRequest(ws, "relay/state/snapshot", {
      includeArchived: false,
      includeThreadReads: false,
      includeLoaded: false,
      limit: 2,
    });

    assert.equal(response.error, undefined);
    const allSourceScope = response.result.scopes.find((scope) => scope.name === "active:allSourceKinds");
    assert.deepEqual(allSourceScope.threadIDsInCodexOrder, ["thread-combined-1", "thread-combined-2"]);
    assert.ok(observedSourceKinds.some((sourceKinds) => (
      Array.isArray(sourceKinds)
        && sourceKinds.includes("cli")
        && sourceKinds.includes("vscode")
        && sourceKinds.includes("subAgentThreadSpawn")
        && sourceKinds.includes("unknown")
    )));
  } finally {
    ws.close();
    await relay.close();
    await closeWebSocketServer(historyServer);
  }
});

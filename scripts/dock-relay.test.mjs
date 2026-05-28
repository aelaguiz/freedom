import assert from "node:assert/strict";
import test from "node:test";

import {
  attentionFlagsForServerRequest,
  mergeActiveFlags,
  preferThread,
  sanitizeRelayFields,
  shouldCollectLiveRowsForThreadList,
  statusPriority,
} from "./dock-relay.mjs";

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

test("relay source marker is never returned to clients", () => {
  assert.deepEqual(
    sanitizeRelayFields({
      id: "thread-1",
      dockRelaySource: { url: "ws://127.0.0.1:4555" },
    }),
    { id: "thread-1" },
  );
});

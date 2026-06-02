import assert from "node:assert/strict";
import test from "node:test";

import {
  PROJECTION_ENGINE_VERSION,
  PROJECTION_IDENTITY_VERSION,
  PROJECTION_SCHEMA_VERSION,
  THREAD_DETAIL_DEFAULT_VIEW_PARAMS_KEY,
  projectionIDForThreadCard,
  projectionIDForThreadItem,
  projectionIDForThreadRequest,
  sourceRefForThreadCard,
  sourceRefForThreadItem,
  sourceRefForThreadRequest,
  threadCardDisplayOrderKey,
  threadDetailDisplayOrderKey,
} from "./dock-relay-projection-engine.mjs";

test("projection engine owns shared projection contract versions", () => {
  assert.equal(PROJECTION_SCHEMA_VERSION, 1);
  assert.equal(PROJECTION_IDENTITY_VERSION, 1);
  assert.equal(PROJECTION_ENGINE_VERSION, 1);
  assert.match(THREAD_DETAIL_DEFAULT_VIEW_PARAMS_KEY, /^sha256:[0-9a-f]{64}$/);
});

test("projection engine builds canonical thread item and request identities", () => {
  assert.equal(
    sourceRefForThreadItem({
      sourceHostID: "home",
      threadID: "thread/one",
      turnID: "turn 1",
      itemID: "item:1",
    }),
    "host:home/thread:thread%2Fone/turn:turn%201/item:item%3A1"
  );
  assert.equal(
    projectionIDForThreadItem({
      sourceHostID: "home",
      threadID: "thread/one",
      turnID: "turn 1",
      itemID: "item:1",
      rowRole: "agentMessage",
    }),
    "host:home/thread:thread%2Fone/turn:turn%201/item:item%3A1/row:agentMessage"
  );
  assert.equal(
    sourceRefForThreadRequest({
      sourceHostID: "home",
      threadID: "thread/one",
      turnID: "turn 1",
      itemID: "item:1",
      requestID: "request/1",
    }),
    "host:home/thread:thread%2Fone/turn:turn%201/item:item%3A1/request:request%2F1"
  );
  assert.equal(
    projectionIDForThreadRequest({
      sourceHostID: "home",
      threadID: "thread/one",
      turnID: "turn 1",
      itemID: "item:1",
      requestID: "request/1",
    }),
    "host:home/thread:thread%2Fone/turn:turn%201/item:item%3A1/request:request%2F1/row:request"
  );
});

test("projection engine display order is newest first and ID-tied", () => {
  const newer = threadDetailDisplayOrderKey({
    activityAtMs: 2_000,
    turnOrder: 0,
    itemOrder: 0,
    rowOrder: 0,
    projectionID: "newer",
  });
  const older = threadDetailDisplayOrderKey({
    activityAtMs: 1_000,
    turnOrder: 0,
    itemOrder: 0,
    rowOrder: 0,
    projectionID: "older",
  });

  assert.equal(newer < older, true);
  assert.match(newer, /\|newer$/);
});

test("projection engine builds canonical thread-card identity and order", () => {
  const sourceRef = sourceRefForThreadCard({
    sourceHostID: "home",
    threadID: "thread/one",
  });
  const projectionID = projectionIDForThreadCard({
    sourceHostID: "home",
    threadID: "thread/one",
  });

  assert.equal(sourceRef, "host:home/thread:thread%2Fone");
  assert.equal(projectionID, "host:home/thread:thread%2Fone/row:threadCard");
  assert.equal(
    threadCardDisplayOrderKey({
      activityAtMs: 2_000,
      status: "needsInput",
      projectionID,
    }) < threadCardDisplayOrderKey({
      activityAtMs: 1_000,
      status: "running",
      projectionID,
    }),
    true
  );
});

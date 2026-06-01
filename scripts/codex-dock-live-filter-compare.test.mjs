import assert from "node:assert/strict";
import test from "node:test";

import { compare } from "./codex-dock-live-filter-compare.mjs";

function relaySample(sampledAt, count, finishedAt = sampledAt, eventIDs = []) {
  return {
    sampledAt,
    finishedAt,
    turns: {
      visibleCounts: {
        messages: count,
        all: count,
      },
      visibleEventIDs: {
        messages: eventIDs,
        all: eventIDs,
      },
    },
  };
}

function uiProof(samples) {
  return {
    runs: [
      {
        filter: "all",
        selectedAt: normalizeUISample(samples[0])?.sampledAt ?? null,
        samples: samples.map((sample) => {
          const normalized = normalizeUISample(sample);
          return {
            sampledAt: normalized.sampledAt,
            finishedAt: normalized.finishedAt,
            ...(normalized.messageListCapturedAt ? { messageListCapturedAt: normalized.messageListCapturedAt } : {}),
            screenKind: "thread",
            filter: "all",
            detailRootValue: `loaded; live=Live; events=${normalized.count}`,
            messageListValue: `events=${normalized.count}; filter=all`,
            messageCards: normalized.eventIDs.map((eventID) => messageElement(eventID)),
            sweepMessageCards: normalized.sweepEventIDs.map((eventID) => messageElement(eventID)),
          };
        }),
      },
    ],
  };
}

function normalizeUISample(sample) {
  if (Array.isArray(sample)) {
    const [sampledAt, count] = sample;
    return {
      sampledAt,
      finishedAt: sampledAt,
      messageListCapturedAt: null,
      count,
      eventIDs: [],
      sweepEventIDs: [],
    };
  }
  return {
    sampledAt: sample.sampledAt,
    finishedAt: sample.finishedAt ?? sample.sampledAt,
    messageListCapturedAt: sample.messageListCapturedAt ?? null,
    count: sample.count,
    eventIDs: sample.eventIDs ?? [],
    sweepEventIDs: sample.sweepEventIDs ?? [],
  };
}

function messageElement(eventID) {
  return {
    identifier: `codexdock.session.message.${eventID}`,
    value: `event=${eventID}; kind=agentMessage; visibility=message; live=false`,
  };
}

test("live filter compare accepts bounded convergence instead of exact nearest-sample equality", () => {
  const report = compare(
    {
      summary: { moving: true },
      samples: [
        relaySample("2026-06-01T13:00:00.000Z", 10),
        relaySample("2026-06-01T13:00:02.000Z", 11),
      ],
    },
    uiProof([
      ["2026-06-01T13:00:02.000Z", 10],
      ["2026-06-01T13:00:08.000Z", 11],
    ]),
    { relayTruth: "relay.json", uiProof: "ui.json", maxLagMS: 5000, requireMoving: false },
  );

  assert.equal(report.status, "pass");
  assert.equal(report.summary.ok, true);
  assert.equal(report.runEvaluations[0].expectedEvents, 11);
});

test("live filter compare allows UI to be ahead of settled relay history", () => {
  const report = compare(
    {
      summary: { moving: false },
      samples: [
        relaySample("2026-06-01T13:00:00.000Z", 10),
      ],
    },
    uiProof([
      ["2026-06-01T13:00:08.000Z", 11],
    ]),
    { relayTruth: "relay.json", uiProof: "ui.json", maxLagMS: 5000, requireMoving: false },
  );

  assert.equal(report.status, "pass");
  assert.equal(report.summary.ok, true);
});

test("live filter compare fails when UI remains behind settled relay history past budget", () => {
  const report = compare(
    {
      summary: { moving: true },
      samples: [
        relaySample("2026-06-01T13:00:00.000Z", 10),
        relaySample("2026-06-01T13:00:02.000Z", 12),
      ],
    },
    uiProof([
      ["2026-06-01T13:00:08.000Z", 11],
    ]),
    { relayTruth: "relay.json", uiProof: "ui.json", maxLagMS: 5000, requireMoving: false },
  );

  assert.equal(report.status, "fail");
  assert.equal(report.summary.ok, false);
  assert.equal(report.failures[0].code, "filter_convergence_lag_exceeded");
});

test("live filter compare scores Thread Detail UI at message list capture time", () => {
  const report = compare(
    {
      summary: { moving: true },
      samples: [
        relaySample("2026-06-01T13:00:00.000Z", 10),
        relaySample("2026-06-01T13:00:02.000Z", 11),
        relaySample("2026-06-01T13:01:00.000Z", 12),
      ],
    },
    uiProof([
      {
        sampledAt: "2026-06-01T13:00:07.500Z",
        messageListCapturedAt: "2026-06-01T13:00:08.000Z",
        finishedAt: "2026-06-01T13:02:00.000Z",
        count: 11,
      },
    ]),
    { relayTruth: "relay.json", uiProof: "ui.json", maxLagMS: 5000, requireMoving: false },
  );

  assert.equal(report.status, "pass");
  assert.equal(report.summary.ok, true);
  assert.equal(report.runEvaluations[0].expectedEvents, 11);
});

test("live filter compare does not use unfinished relay reads as settled truth", () => {
  const report = compare(
    {
      summary: { moving: true },
      samples: [
        relaySample("2026-06-01T13:00:00.000Z", 11, "2026-06-01T13:00:00.500Z"),
        relaySample("2026-06-01T13:00:03.000Z", 12, "2026-06-01T13:00:10.000Z"),
      ],
    },
    uiProof([
      {
        sampledAt: "2026-06-01T13:00:05.000Z",
        messageListCapturedAt: "2026-06-01T13:00:05.000Z",
        finishedAt: "2026-06-01T13:00:05.500Z",
        count: 11,
      },
    ]),
    { relayTruth: "relay.json", uiProof: "ui.json", maxLagMS: 1000, requireMoving: false },
  );

  assert.equal(report.status, "pass");
  assert.equal(report.summary.ok, true);
  assert.equal(report.runEvaluations[0].expectedEvents, 11);
});

test("live filter compare treats visible event id changes as UI movement when counts are capped", () => {
  const report = compare(
    {
      summary: { moving: true },
      samples: [
        relaySample("2026-06-01T13:00:00.000Z", 240, "2026-06-01T13:00:00.500Z", ["event-a", "event-old"]),
        relaySample("2026-06-01T13:00:04.000Z", 240, "2026-06-01T13:00:04.500Z", ["event-b", "event-a"]),
      ],
    },
    uiProof([
      {
        sampledAt: "2026-06-01T13:00:03.000Z",
        messageListCapturedAt: "2026-06-01T13:00:03.000Z",
        count: 240,
        eventIDs: ["event-a", "event-old"],
      },
      {
        sampledAt: "2026-06-01T13:00:10.000Z",
        messageListCapturedAt: "2026-06-01T13:00:10.000Z",
        count: 240,
        eventIDs: ["event-b", "event-a"],
        sweepEventIDs: ["event-b", "event-a"],
      },
    ]),
    { relayTruth: "relay.json", uiProof: "ui.json", maxLagMS: 5000, requireMoving: true },
  );

  assert.equal(report.status, "pass");
  assert.equal(report.summary.uiMoving, true);
  assert.equal(report.runEvaluations[0].expectedEventIDHead, "event-b");
});

test("live filter compare does not blame UI when only unsampled relay filters moved", () => {
  const report = compare(
    {
      summary: {
        moving: true,
        filters: {
          all: { changed: false },
          command: { changed: true },
        },
      },
      samples: [
        relaySample("2026-06-01T13:00:00.000Z", 240, "2026-06-01T13:00:00.500Z", ["event-a"]),
        relaySample("2026-06-01T13:00:04.000Z", 240, "2026-06-01T13:00:04.500Z", ["event-a"]),
      ],
    },
    uiProof([
      {
        sampledAt: "2026-06-01T13:00:03.000Z",
        messageListCapturedAt: "2026-06-01T13:00:03.000Z",
        count: 240,
      },
      {
        sampledAt: "2026-06-01T13:00:10.000Z",
        messageListCapturedAt: "2026-06-01T13:00:10.000Z",
        count: 240,
      },
    ]),
    { relayTruth: "relay.json", uiProof: "ui.json", maxLagMS: 5000, requireMoving: true },
  );

  assert.equal(report.status, "fail");
  assert.equal(report.summary.relayMoving, true);
  assert.equal(report.summary.relayMovingInSampledFilters, false);
  assert.deepEqual(report.summary.relayMovingFilters, []);
  assert.equal(report.failures.some((failure) => failure.code === "sampled_filter_movement_not_observed"), true);
  assert.equal(report.failures.some((failure) => failure.code === "moving_updates_not_proven"), false);
});

test("live filter compare fails when sampled relay filter moves but UI stays static", () => {
  const report = compare(
    {
      summary: {
        moving: true,
        filters: {
          all: { changed: true },
        },
      },
      samples: [
        relaySample("2026-06-01T13:00:00.000Z", 10, "2026-06-01T13:00:00.500Z"),
        relaySample("2026-06-01T13:00:04.000Z", 11, "2026-06-01T13:00:04.500Z"),
      ],
    },
    uiProof([
      {
        sampledAt: "2026-06-01T13:00:03.000Z",
        messageListCapturedAt: "2026-06-01T13:00:03.000Z",
        count: 10,
      },
      {
        sampledAt: "2026-06-01T13:00:05.000Z",
        messageListCapturedAt: "2026-06-01T13:00:05.000Z",
        count: 10,
      },
    ]),
    { relayTruth: "relay.json", uiProof: "ui.json", maxLagMS: 5000, requireMoving: true },
  );

  assert.equal(report.status, "fail");
  assert.equal(report.summary.relayMoving, true);
  assert.equal(report.summary.relayMovingInSampledFilters, true);
  assert.deepEqual(report.summary.relayMovingFilters, ["all"]);
  assert.equal(report.summary.uiMoving, false);
  const failure = report.failures.find((candidate) => candidate.code === "moving_updates_not_proven");
  assert.equal(failure?.relayMoving, true);
  assert.equal(failure?.relayMovingInSampledFilters, true);
  assert.equal(failure?.uiMoving, false);
  assert.equal(report.failures.some((candidate) => candidate.code === "sampled_filter_movement_not_observed"), false);
});

test("live filter compare fails when a checkpoint sweep misses the newest settled event", () => {
  const report = compare(
    {
      summary: { moving: true },
      samples: [
        relaySample("2026-06-01T13:00:04.000Z", 240, "2026-06-01T13:00:04.500Z", ["event-b", "event-a"]),
      ],
    },
    uiProof([
      {
        sampledAt: "2026-06-01T13:00:10.000Z",
        messageListCapturedAt: "2026-06-01T13:00:10.000Z",
        count: 240,
        eventIDs: ["event-a"],
        sweepEventIDs: ["event-a"],
      },
    ]),
    { relayTruth: "relay.json", uiProof: "ui.json", maxLagMS: 5000, requireMoving: false },
  );

  assert.equal(report.status, "fail");
  assert.equal(report.failures.some((failure) => failure.code === "filter_newest_event_missing"), true);
});

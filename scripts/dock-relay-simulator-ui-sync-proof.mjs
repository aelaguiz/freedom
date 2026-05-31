#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

import {
  evaluateStreamConvergenceLag,
} from "./dock-relay-sync-audit.mjs";

const DEFAULT_MAX_UI_LAG_MS = 2000;

function usage() {
  return [
    "Usage:",
    "  node scripts/dock-relay-simulator-ui-sync-proof.mjs --relay-report <path> --ui-samples <path> [options]",
    "",
    "Options:",
    "  --json-out <path>        Write JSON report.",
    "  --summary-out <path>     Write Markdown summary.",
    "  --max-ui-lag-ms <ms>     Startup rendered-UI convergence budget. Default: 2000.",
    "  --fail-on-diff          Exit 1 when rendered UI proof fails.",
    "  --help                  Show this help.",
  ].join("\n");
}

function parseArgs(argv) {
  const options = {
    relayReport: null,
    uiSamples: null,
    jsonOut: null,
    summaryOut: null,
    maxUiLagMs: DEFAULT_MAX_UI_LAG_MS,
    failOnDiff: false,
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
    if (arg === "--relay-report") {
      options.relayReport = next();
    } else if (arg === "--ui-samples") {
      options.uiSamples = next();
    } else if (arg === "--json-out") {
      options.jsonOut = next();
    } else if (arg === "--summary-out") {
      options.summaryOut = next();
    } else if (arg === "--max-ui-lag-ms") {
      options.maxUiLagMs = Number(next());
    } else if (arg === "--fail-on-diff") {
      options.failOnDiff = true;
    } else if (arg === "--help" || arg === "-h") {
      options.help = true;
    } else {
      throw new Error(`unknown argument ${arg}`);
    }
  }
  return options;
}

function readJSON(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function readJSONL(filePath) {
  return fs.readFileSync(filePath, "utf8")
    .split(/\r?\n/u)
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line) => JSON.parse(line));
}

function parseSemicolonValue(value) {
  const result = {};
  for (const part of String(value || "").split(";")) {
    const trimmed = part.trim();
    if (!trimmed) {
      continue;
    }
    const equals = trimmed.indexOf("=");
    if (equals === -1) {
      result[trimmed] = true;
      continue;
    }
    result[trimmed.slice(0, equals).trim()] = trimmed.slice(equals + 1).trim();
  }
  return result;
}

function parseRootRowCount(rootValue) {
  const parsed = parseSemicolonValue(rootValue);
  const value = Number(parsed.rows);
  return Number.isFinite(value) ? value : null;
}

function dateMS(value) {
  const parsed = Date.parse(value || 0);
  return Number.isFinite(parsed) ? parsed : null;
}

function sampleTimeMS(sample) {
  const value = Date.parse(sample.finishedAt || sample.sampledAt || sample.startedAt || 0);
  return Number.isFinite(value) ? value : 0;
}

function firstDateMS(...values) {
  for (const value of values) {
    const parsed = dateMS(value);
    if (parsed !== null) {
      return parsed;
    }
  }
  return null;
}

function isoFromMS(value) {
  return Number.isFinite(value) ? new Date(value).toISOString() : null;
}

function elementObservedAtMS(element, fallbackMs) {
  return firstDateMS(element?.capturedAt, element?.observedAt) ?? fallbackMs;
}

function latestObservedAtMS(times, fallbackMs) {
  const finite = times.filter((value) => Number.isFinite(value));
  return finite.length ? Math.max(...finite) : fallbackMs;
}

function earliestObservedAtMS(times) {
  const finite = times.filter((value) => Number.isFinite(value));
  return finite.length ? Math.min(...finite) : null;
}

function relaySampleTimeMS(sample) {
  const value = Date.parse(sample.finishedAt || sample.startedAt || 0);
  return Number.isFinite(value) ? value : 0;
}

function relaySampleAtOrBefore(relaySamples, uiSample) {
  const target = sampleTimeMS(uiSample);
  let selected = null;
  for (const relaySample of relaySamples) {
    const relayTime = relaySampleTimeMS(relaySample);
    if (relayTime <= target) {
      selected = relaySample;
      continue;
    }
    break;
  }
  return selected;
}

function scenarioTransitionTimeMS(transition) {
  return dateMS(transition?.lag?.relaySeenAt || transition?.wait?.observedAt);
}

function scenarioTransitionTruths(relayReport) {
  const truths = [];
  for (const scenario of Array.isArray(relayReport?.scenarios) ? relayReport.scenarios : []) {
    const transitions = Array.isArray(scenario?.transitions) ? scenario.transitions : [];
    for (let index = 0; index < transitions.length; index += 1) {
      const transition = transitions[index];
      const atMs = scenarioTransitionTimeMS(transition);
      if (atMs === null || !transition?.freshDock) {
        continue;
      }
      const nextTransition = transitions.slice(index + 1)
        .map((candidate) => scenarioTransitionTimeMS(candidate))
        .find((candidateMs) => candidateMs !== null && candidateMs >= atMs) ?? null;
      const at = new Date(atMs).toISOString();
      truths.push({
        scenarioID: scenario.id || "unknown",
        transition: transition.name || transition.route || `transition-${index}`,
        route: transition.route || null,
        at,
        atMs,
        untilMs: nextTransition,
        relayLag: transition.lag || null,
        truthSample: {
          sampleIndex: `${scenario.id || "scenario"}:${transition.name || index}`,
          startedAt: at,
          finishedAt: at,
          freshDock: transition.freshDock,
        },
      });
    }
  }
  return truths.sort((left, right) => left.atMs - right.atMs);
}

function detailTransitionTruths(relayReport) {
  const truths = [];
  for (const scenario of Array.isArray(relayReport?.scenarios) ? relayReport.scenarios : []) {
    const transitions = Array.isArray(scenario?.transitions) ? scenario.transitions : [];
    for (let index = 0; index < transitions.length; index += 1) {
      const transition = transitions[index];
      const atMs = scenarioTransitionTimeMS(transition);
      if (atMs === null || !transition?.detailTruth) {
        continue;
      }
      const nextTransition = transitions.slice(index + 1)
        .filter((candidate) => candidate?.detailTruth)
        .map((candidate) => scenarioTransitionTimeMS(candidate))
        .find((candidateMs) => candidateMs !== null && candidateMs >= atMs) ?? null;
      truths.push({
        scenarioID: scenario.id || "unknown",
        transition: transition.name || transition.route || `detail-transition-${index}`,
        route: transition.route || null,
        at: new Date(atMs).toISOString(),
        atMs,
        untilMs: nextTransition,
        relayLag: transition.lag || null,
        truth: transition.detailTruth,
      });
    }
  }
  return truths.sort((left, right) => left.atMs - right.atMs);
}

function relayTruthSamples(relayReport) {
  const regularSamples = (Array.isArray(relayReport.samples) ? relayReport.samples : [])
    .filter((sample) => dateMS(sample?.finishedAt || sample?.startedAt) !== null);
  const transitionSamples = scenarioTransitionTruths(relayReport)
    .map((truth) => truth.truthSample);
  return [...regularSamples, ...transitionSamples]
    .sort((left, right) => relaySampleTimeMS(left) - relaySampleTimeMS(right));
}

function relayOrigin(card) {
  if (card.lane === "human") {
    return "human";
  }
  if (card.lane === "agent") {
    return "automation";
  }
  if (card.sourceKind === "automation") {
    return "automation";
  }
  if (card.sourceKind === "human") {
    return "human";
  }
  return "unknown";
}

function relayCardsByKey(relaySample) {
  const cards = relaySample?.freshDock?.cards || [];
  const byKey = new Map();
  for (const card of cards) {
    byKey.set(`${card.logicalHostID}::${card.threadID}`, card);
  }
  return byKey;
}

function relayHostIDs(relaySample) {
  const ids = new Set();
  for (const host of Array.isArray(relaySample?.freshDock?.hosts) ? relaySample.freshDock.hosts : []) {
    if (host?.id) {
      ids.add(host.id);
    }
  }
  for (const card of Array.isArray(relaySample?.freshDock?.cards) ? relaySample.freshDock.cards : []) {
    if (card?.logicalHostID) {
      ids.add(card.logicalHostID);
    }
  }
  return [...ids].sort();
}

function sampleHostSummaries(sample) {
  return Array.isArray(sample?.hostSummaries) ? sample.hostSummaries : [];
}

function sampleHostSummary(sample, hostID, allowSingleHostFallback = false) {
  const expectedIdentifier = dockHostSummaryIdentifier(hostID);
  const summaries = sampleHostSummaries(sample);
  const exact = summaries.find((summary) => (
    summary?.identifier === expectedIdentifier
    || String(summary?.value || "").startsWith(`${hostID};`)
  )) || null;
  if (exact) {
    return exact;
  }
  return allowSingleHostFallback && summaries.length === 1 ? summaries[0] : null;
}

function hostSummaryText(summary) {
  return `${summary?.value || ""} ${summary?.label || ""}`.toLowerCase();
}

function hostSummaryShowsFreshness(summary, status) {
  const text = hostSummaryText(summary);
  switch (status) {
  case "stale":
    return text.includes("stale") || text.includes("partial");
  case "offline":
    return text.includes("offline");
  case "error":
    return text.includes("error");
  case "refreshing":
    return text.includes("refreshing") || text.includes("checking");
  default:
    return false;
  }
}

function hostSummaryShowsNonFresh(summary) {
  const text = hostSummaryText(summary);
  return text.includes("partial")
    || text.includes("stale")
    || text.includes("offline")
    || text.includes("error")
    || text.includes("refreshing");
}

function addFailure(failures, sample, code, message, detail = {}) {
  failures.push({
    code,
    message,
    sampleIndex: sample?.sampleIndex ?? null,
    sampledAt: sample?.sampledAt ?? null,
    ...detail,
  });
}

function rowFailureCode(source, suffix) {
  return source === "sweep" ? `dock_ui_sweep_${suffix}` : `dock_ui_${suffix}`;
}

function automationSafeSegment(value) {
  let escaped = "";
  for (const byte of Buffer.from(String(value || ""), "utf8")) {
    if (
      (byte >= 48 && byte <= 57)
      || (byte >= 65 && byte <= 90)
      || (byte >= 97 && byte <= 122)
      || byte === 45
      || byte === 46
      || byte === 95
    ) {
      escaped += String.fromCharCode(byte);
    } else {
      escaped += `%${byte.toString(16).toUpperCase().padStart(2, "0")}`;
    }
  }
  return escaped || "_";
}

function requestCardIdentifier(cardID) {
  return `codexdock.session.request.${automationSafeSegment(cardID)}`;
}

function dockHostSummaryIdentifier(hostID) {
  return `codexdock.dock.host.${automationSafeSegment(hostID)}`;
}

function requestStatusIdentifier(cardID) {
  return `${requestCardIdentifier(cardID)}.status`;
}

function messageCardIdentifier(eventID) {
  return `codexdock.session.message.${automationSafeSegment(eventID)}`;
}

function detailElements(detail) {
  return [
    ...(Array.isArray(detail?.messageCards) ? detail.messageCards : []),
    ...(Array.isArray(detail?.requestElements) ? detail.requestElements : []),
  ];
}

function detailElement(detail, identifier) {
  return detailElements(detail).find((element) => element?.identifier === identifier) || null;
}

function detailHasIdentifier(detail, identifier, legacyIDs = []) {
  return legacyIDs.includes(identifier)
    || (Array.isArray(detail?.messageCardIDs) && detail.messageCardIDs.includes(identifier))
    || (Array.isArray(detail?.requestCardIDs) && detail.requestCardIDs.includes(identifier))
    || Boolean(detailElement(detail, identifier));
}

function detailMessageEventCount(detail) {
  const parsed = parseSemicolonValue(detail?.messageListValue || "");
  const count = Number(parsed.events);
  return Number.isFinite(count) ? count : null;
}

function mergeUniqueValues(...sources) {
  return [...new Set(sources.flat().filter(Boolean))];
}

function mergeUniqueElements(...sources) {
  const merged = [];
  const seen = new Set();
  for (const element of sources.flat()) {
    if (!element?.identifier || seen.has(element.identifier)) {
      continue;
    }
    seen.add(element.identifier);
    merged.push(element);
  }
  return merged;
}

function combinedDetailForSample(sample) {
  const detail = sample?.detail || {};
  const sweep = sample?.detailSweep || {};
  return {
    ...detail,
    messageCardIDs: mergeUniqueValues(detail.messageCardIDs || [], sweep.messageCardIDs || []),
    requestCardIDs: mergeUniqueValues(detail.requestCardIDs || [], sweep.requestCardIDs || []),
    messageCards: mergeUniqueElements(detail.messageCards || [], sweep.messageCards || []),
    requestElements: mergeUniqueElements(detail.requestElements || [], sweep.requestElements || []),
  };
}

function detailValueObservedAtMS(sample, key) {
  const detail = sample?.detail || {};
  const fallbackMs = sampleTimeMS(sample);
  const capturedKey = `${key}CapturedAt`;
  return firstDateMS(detail[capturedKey], detail.finishedAt, detail.capturedAt) ?? fallbackMs;
}

function detailCollectionObservedAtMS(sample, collectionName) {
  const detail = sample?.detail || {};
  const fallbackMs = sampleTimeMS(sample);
  if (collectionName === "message") {
    return firstDateMS(detail.messageCardsCapturedAt, detail.finishedAt, detail.capturedAt) ?? fallbackMs;
  }
  if (collectionName === "request") {
    return firstDateMS(detail.requestElementsCapturedAt, detail.finishedAt, detail.capturedAt) ?? fallbackMs;
  }
  return fallbackMs;
}

function detailIdentifierObservedAtMS(sample, identifier) {
  const detail = sample?.detail || {};
  const sweep = sample?.detailSweep || {};
  const detailMessageFallbackMs = detailCollectionObservedAtMS(sample, "message");
  const detailRequestFallbackMs = detailCollectionObservedAtMS(sample, "request");
  const sweepFallbackMs = firstDateMS(sweep.finishedAt, sweep.capturedAt) ?? sampleTimeMS(sample);
  const times = [];

  for (const element of Array.isArray(detail.messageCards) ? detail.messageCards : []) {
    if (element?.identifier === identifier) {
      times.push(elementObservedAtMS(element, detailMessageFallbackMs));
    }
  }
  for (const element of Array.isArray(detail.requestElements) ? detail.requestElements : []) {
    if (element?.identifier === identifier) {
      times.push(elementObservedAtMS(element, detailRequestFallbackMs));
    }
  }
  if (Array.isArray(detail.messageCardIDs) && detail.messageCardIDs.includes(identifier)) {
    times.push(detailMessageFallbackMs);
  }
  if (Array.isArray(detail.requestCardIDs) && detail.requestCardIDs.includes(identifier)) {
    times.push(detailRequestFallbackMs);
  }

  for (const element of Array.isArray(sweep.messageCards) ? sweep.messageCards : []) {
    if (element?.identifier === identifier) {
      times.push(elementObservedAtMS(element, sweepFallbackMs));
    }
  }
  for (const element of Array.isArray(sweep.requestElements) ? sweep.requestElements : []) {
    if (element?.identifier === identifier) {
      times.push(elementObservedAtMS(element, sweepFallbackMs));
    }
  }
  if (Array.isArray(sweep.messageCardIDs) && sweep.messageCardIDs.includes(identifier)) {
    times.push(sweepFallbackMs);
  }
  if (Array.isArray(sweep.requestCardIDs) && sweep.requestCardIDs.includes(identifier)) {
    times.push(sweepFallbackMs);
  }

  return earliestObservedAtMS(times);
}

function detailRequestStatusInfo(sample, detail, cardID) {
  const statusID = requestStatusIdentifier(cardID);
  const statusElement = detailElement(detail, statusID);
  if (statusElement) {
    return {
      status: statusElement.value || statusElement.label || null,
      observedAtMs: detailIdentifierObservedAtMS(sample, statusID),
    };
  }

  const cardIDValue = requestCardIdentifier(cardID);
  const card = detailElement(detail, cardIDValue);
  const parsedCard = parseSemicolonValue(card?.value || "");
  if (parsedCard.status) {
    return {
      status: parsedCard.status,
      observedAtMs: detailIdentifierObservedAtMS(sample, cardIDValue),
    };
  }

  return {
    status: null,
    observedAtMs: null,
  };
}

function detailSweepMessageCardCount(sample) {
  const sweep = sample?.detailSweep || null;
  if (!sweep) {
    return 0;
  }
  return new Set([
    ...(Array.isArray(sweep.messageCardIDs) ? sweep.messageCardIDs : []),
    ...(Array.isArray(sweep.messageCards) ? sweep.messageCards.map((element) => element?.identifier).filter(Boolean) : []),
  ]).size;
}

function evaluateDetailTransitionSample(sample, transition) {
  const failures = [];
  const detail = sample?.detail || null;
  const fallbackObservedAtMs = sampleTimeMS(sample);
  const evidenceTimes = [];
  const addEvidenceTime = (value) => {
    if (Number.isFinite(value)) {
      evidenceTimes.push(value);
    }
  };
  if (!detail) {
    addFailure(
      failures,
      sample,
      "detail_ui_missing_detail",
      "Simulator sample did not expose the target thread detail UI."
    );
    return {
      ok: false,
      failures,
      observedAt: null,
      observedAtMs: null,
    };
  }

  const root = parseSemicolonValue(detail.rootValue);
  const header = parseSemicolonValue(detail.headerValue);
  const truth = transition.truth || {};
  const combinedDetail = combinedDetailForSample(sample);
  const actualHost = root.host || header.host || null;
  const actualThread = root.thread || header.thread || null;
  const expectedDetailHost = truth.detailHostID || truth.logicalHostID || null;
  if (expectedDetailHost && actualHost !== expectedDetailHost) {
    addFailure(
      failures,
      sample,
      "detail_ui_wrong_host",
      "Simulator detail UI is showing the wrong host.",
      {
        expectedHost: expectedDetailHost,
        actualHost,
      }
    );
  } else if (expectedDetailHost) {
    addEvidenceTime(root.host === expectedDetailHost
      ? detailValueObservedAtMS(sample, "root")
      : detailValueObservedAtMS(sample, "header"));
  }
  if (truth.threadID && actualThread !== truth.threadID) {
    addFailure(
      failures,
      sample,
      "detail_ui_wrong_thread",
      "Simulator detail UI is showing the wrong thread.",
      {
        expectedThread: truth.threadID,
        actualThread,
      }
    );
  } else if (truth.threadID) {
    addEvidenceTime(root.thread === truth.threadID
      ? detailValueObservedAtMS(sample, "root")
      : detailValueObservedAtMS(sample, "header"));
  }

  const expectedEventCount = Number(truth.expectedMessageEventCount);
  if (Number.isFinite(expectedEventCount)) {
    const actualEventCount = detailMessageEventCount(detail);
    if (actualEventCount !== expectedEventCount) {
      addFailure(
        failures,
        sample,
        "detail_ui_message_event_count_mismatch",
        "Simulator detail UI rendered the wrong number of opened-thread events.",
        {
          expectedEventCount,
          actualEventCount,
        }
      );
    } else {
      addEvidenceTime(detailValueObservedAtMS(sample, "messageList"));
    }
  }

  for (const eventID of Array.isArray(truth.expectedMessageEventIDs) ? truth.expectedMessageEventIDs : []) {
    const expectedMessageCard = messageCardIdentifier(eventID);
    if (!detailHasIdentifier(combinedDetail, expectedMessageCard, combinedDetail.messageCardIDs || [])) {
      addFailure(
        failures,
        sample,
        "detail_ui_message_card_missing",
        "Simulator detail UI did not display an expected opened-thread event row.",
        {
          eventID,
          expectedMessageCard,
        }
      );
    } else {
      addEvidenceTime(detailIdentifierObservedAtMS(sample, expectedMessageCard));
    }
  }

  if (truth.requestVisible) {
    const requestCardID = truth.requestCardID;
    const expectedRequestCard = requestCardIdentifier(requestCardID);
    const expectedMessageCard = messageCardIdentifier(requestCardID);
    const hasRequestCard = detailHasIdentifier(combinedDetail, expectedRequestCard, combinedDetail.requestCardIDs || []);
    const hasMessageEvent = detailMessageEventCount(detail) === null || detailMessageEventCount(detail) > 0;
    if (!hasMessageEvent && !detailHasIdentifier(combinedDetail, expectedMessageCard, combinedDetail.messageCardIDs || [])) {
      addFailure(
        failures,
        sample,
        "detail_ui_request_message_missing",
        "Simulator detail UI did not display the server request event row.",
        {
          requestCardID,
          expectedMessageCard,
        }
      );
    } else {
      addEvidenceTime(detailIdentifierObservedAtMS(sample, expectedMessageCard));
      if (hasMessageEvent) {
        addEvidenceTime(detailValueObservedAtMS(sample, "messageList"));
      }
    }
    if (!hasRequestCard) {
      addFailure(
        failures,
        sample,
        "detail_ui_request_card_missing",
        "Simulator detail UI did not display the server request card.",
        {
          requestCardID,
          expectedRequestCard,
        }
      );
    } else {
      addEvidenceTime(detailIdentifierObservedAtMS(sample, expectedRequestCard));
    }
    const actualStatusInfo = detailRequestStatusInfo(sample, combinedDetail, requestCardID);
    const actualStatus = actualStatusInfo.status;
    if (truth.expectedStatus && actualStatus !== truth.expectedStatus) {
      addFailure(
        failures,
        sample,
        "detail_ui_request_status_mismatch",
        "Simulator request card status does not match relay detail truth.",
        {
          requestCardID,
          expectedStatus: truth.expectedStatus,
          actualStatus,
        }
      );
    } else if (truth.expectedStatus) {
      addEvidenceTime(actualStatusInfo.observedAtMs);
    }
  }

  const observedAtMs = latestObservedAtMS(evidenceTimes, fallbackObservedAtMs);
  return {
    ok: failures.length === 0,
    failures,
    observedAt: isoFromMS(observedAtMs),
    observedAtMs,
  };
}

function evaluateDockRows({ sample, rows, relayCards, failures, source }) {
  const seenKeys = new Set();
  for (const row of rows) {
    const parsed = parseSemicolonValue(row.value);
    const host = parsed.host;
    const thread = parsed.thread;
    const status = parsed.status;
    const origin = parsed.origin;
    if (!host || !thread) {
      addFailure(
        failures,
        sample,
        rowFailureCode(source, "row_missing_identity"),
        "Rendered row did not expose host/thread identity.",
        {
          identifier: row.identifier,
          value: row.value,
          source,
        }
      );
      continue;
    }
    const key = `${host}::${thread}`;
    if (seenKeys.has(key)) {
      addFailure(
        failures,
        sample,
        rowFailureCode(source, "duplicate_row"),
        "Rendered UI exposed the same row more than once.",
        { key, source }
      );
      continue;
    }
    seenKeys.add(key);
    const relayCard = relayCards.get(key);
    if (!relayCard) {
      addFailure(
        failures,
        sample,
        rowFailureCode(source, "unexpected_row"),
        "Rendered row was absent from nearest relay fresh Dock sample.",
        {
          key,
          identifier: row.identifier,
          source,
        }
      );
      continue;
    }
    if (status && status !== relayCard.status) {
      addFailure(
        failures,
        sample,
        rowFailureCode(source, "row_status_mismatch"),
        "Rendered row status does not match relay card status.",
        {
          key,
          uiStatus: status,
          relayStatus: relayCard.status,
          source,
        }
      );
    }
    const expectedOrigin = relayOrigin(relayCard);
    if (origin && origin !== expectedOrigin) {
      addFailure(
        failures,
        sample,
        rowFailureCode(source, "row_origin_mismatch"),
        "Rendered row origin does not match relay card origin.",
        {
          key,
          uiOrigin: origin,
          relayOrigin: expectedOrigin,
          source,
        }
      );
    }
  }
  return seenKeys;
}

function evaluateUISample(sample, relaySample) {
  const failures = [];
  const dockSweep = sample?.dockSweep && Array.isArray(sample.dockSweep.rows) ? sample.dockSweep : null;
  if (!relaySample) {
    return {
      ok: true,
      scored: false,
      relaySampleIndex: null,
      rootValue: sample.dockRootValue || "",
      rowCount: Array.isArray(sample.dockRows) ? sample.dockRows.length : 0,
      sweepRowCount: dockSweep ? dockSweep.rows.length : null,
      sweepStepCount: dockSweep ? dockSweep.stepCount ?? null : null,
      uiRootRows: parseRootRowCount(sample.dockRootValue || ""),
      relayRowCount: null,
      failures,
    };
  }
  const rootValue = sample.dockRootValue || "";
  const rows = Array.isArray(sample.dockRows) ? sample.dockRows : [];
  const relayCards = relayCardsByKey(relaySample);
  const relayRowCount = Number(relaySample?.freshDock?.cardCount ?? relaySample?.freshDock?.totalRows);
  const uiRootRows = parseRootRowCount(rootValue);
  const sweepRows = dockSweep ? dockSweep.rows : [];
  const detailOnlySample = Boolean(sample.detail) && rootValue === "not-visible";

  if (!detailOnlySample && !rootValue.includes("loaded")) {
    addFailure(failures, sample, "dock_ui_not_loaded", "Dock UI was not in loaded state.", { rootValue });
  }

  if (!detailOnlySample && Number.isFinite(relayRowCount) && uiRootRows !== null && uiRootRows !== relayRowCount) {
    addFailure(
      failures,
      sample,
      "dock_ui_root_count_mismatch",
      "Dock root rendered row count does not match relay fresh Dock card count.",
      { uiRootRows, relayRowCount }
    );
  }

  if (!detailOnlySample && Number.isFinite(relayRowCount) && relayRowCount > 0 && rows.length === 0) {
    addFailure(failures, sample, "dock_ui_missing_rows", "Relay has Dock rows but the rendered UI exposed no visible Dock rows.");
  }

  evaluateDockRows({ sample, rows, relayCards, failures, source: "visible" });

  if (!detailOnlySample && dockSweep) {
    const sweepSeenKeys = evaluateDockRows({
      sample,
      rows: sweepRows,
      relayCards,
      failures,
      source: "sweep",
    });
    if (Number.isFinite(relayRowCount) && sweepSeenKeys.size !== relayRowCount) {
      addFailure(
        failures,
        sample,
        "dock_ui_sweep_count_mismatch",
        "Checkpoint sweep row count does not match relay fresh Dock card count.",
        {
          sweepRows: sweepSeenKeys.size,
          relayRowCount,
          expectedRootRows: dockSweep.expectedRootRows ?? null,
        }
      );
    }
    for (const key of relayCards.keys()) {
      if (!sweepSeenKeys.has(key)) {
        addFailure(
          failures,
          sample,
          "dock_ui_sweep_missing_relay_row",
          "Checkpoint sweep did not find a relay Dock row in the rendered client.",
          { key }
        );
      }
    }
  }

  const freshnessStatus = relaySample?.freshDock?.freshness?.status || null;
  if (!detailOnlySample && freshnessStatus) {
    const hostIDs = relayHostIDs(relaySample);
    for (const hostID of hostIDs) {
      const summary = sampleHostSummary(sample, hostID, hostIDs.length === 1);
      if (freshnessStatus === "fresh") {
        if (summary && hostSummaryShowsNonFresh(summary)) {
          addFailure(
            failures,
            sample,
            "dock_ui_stale_host_summary_after_recovery",
            "Rendered UI still exposed stale host state after relay truth recovered to fresh.",
            {
              hostID,
              value: summary.value || "",
              label: summary.label || "",
            }
          );
        }
        continue;
      }
      if (!summary || !hostSummaryShowsFreshness(summary, freshnessStatus)) {
        addFailure(
          failures,
          sample,
          "dock_ui_host_freshness_missing",
          "Rendered UI did not expose the relay host freshness state.",
          {
            hostID,
            expectedFreshness: freshnessStatus,
            observedHostSummaries: sampleHostSummaries(sample).map((entry) => ({
              identifier: entry.identifier || null,
              value: entry.value || "",
              label: entry.label || "",
            })),
          }
        );
      }
    }
  }

  if (sample.detail) {
    const root = parseSemicolonValue(sample.detail.rootValue);
    const header = parseSemicolonValue(sample.detail.headerValue);
    if (root.thread && header.thread && root.thread !== header.thread) {
      addFailure(failures, sample, "detail_ui_wrong_thread", "Detail root and header disagree on thread id.", {
        rootThread: root.thread,
        headerThread: header.thread,
      });
    }
    if (root.host && header.host && root.host !== header.host) {
      addFailure(failures, sample, "detail_ui_host_mismatch", "Detail root and header disagree on host id.", {
        rootHost: root.host,
        headerHost: header.host,
      });
    }
  }

  return {
    ok: failures.length === 0,
    scored: !detailOnlySample,
    relaySampleIndex: relaySample?.sampleIndex ?? null,
    relaySampleFinishedAt: relaySample?.finishedAt || relaySample?.startedAt || null,
    rootValue,
    rowCount: rows.length,
    sweepRowCount: dockSweep ? sweepRows.length : null,
    sweepStepCount: dockSweep ? dockSweep.stepCount ?? null : null,
    sweepExpectedRootRows: dockSweep ? dockSweep.expectedRootRows ?? null : null,
    uiRootRows,
    relayRowCount: Number.isFinite(relayRowCount) ? relayRowCount : null,
    failures,
  };
}

function uiLagAttempts(uiSamples, evaluations) {
  return evaluations
    .map((evaluation, index) => {
      if (!evaluation.scored) {
        return null;
      }
      const sample = uiSamples[index];
      const checkedAtMs = sampleTimeMS(sample);
      return {
        attempt: index,
        checkedAt: sample.sampledAt || null,
        checkedAtMs,
        ok: evaluation.ok,
        findingCount: evaluation.failures.length,
        relaySampleIndex: evaluation.relaySampleIndex,
        relaySampleFinishedAt: evaluation.relaySampleFinishedAt,
        rowCount: evaluation.rowCount,
        sweepRowCount: evaluation.sweepRowCount,
        relayRowCount: evaluation.relayRowCount,
      };
    })
    .filter(Boolean);
}

function countConsecutivePassing(evaluations) {
  let best = 0;
  let current = 0;
  for (const evaluation of evaluations) {
    if (evaluation.scored && evaluation.ok) {
      current += 1;
      best = Math.max(best, current);
    } else {
      current = 0;
    }
  }
  return best;
}

function evaluateScenarioTransitionCoverage({ uiSamples, transitions, maxUiLagMs }) {
  const failures = [];
  const checks = [];
  for (const transition of transitions) {
    if (transition.relayLag && transition.relayLag.ok === false) {
      failures.push({
        code: "scenario_transition_relay_lag_failed",
        message: "Relay scenario transition already exceeded its relay lag budget.",
        scenarioID: transition.scenarioID,
        transition: transition.transition,
        route: transition.route,
        observedMs: transition.relayLag.lag_change_to_relay_ms ?? transition.relayLag.observedLagMs ?? null,
        budgetMs: transition.relayLag.maxStreamLagMs ?? maxUiLagMs,
      });
    }
    const candidates = uiSamples
      .filter((sample) => {
        const sampledAtMs = sampleTimeMS(sample);
        return sampledAtMs >= transition.atMs
          && (transition.untilMs === null || sampledAtMs < transition.untilMs);
      })
      .sort((left, right) => sampleTimeMS(left) - sampleTimeMS(right));
    const evaluations = candidates.map((sample) => ({
      sample,
      evaluation: evaluateUISample(sample, transition.truthSample),
    }));
    const firstPassing = evaluations.find((entry) => entry.evaluation.scored && entry.evaluation.ok) || null;
    const observedLagMs = firstPassing
      ? Math.max(0, sampleTimeMS(firstPassing.sample) - transition.atMs)
      : null;
    const check = {
      scenarioID: transition.scenarioID,
      transition: transition.transition,
      route: transition.route,
      relaySeenAt: transition.at,
      uiSampleCount: candidates.length,
      firstPassingSampleAt: firstPassing?.sample?.sampledAt || null,
      observedLagMs,
      ok: Boolean(firstPassing) && observedLagMs <= maxUiLagMs,
      failures: evaluations.flatMap((entry) => entry.evaluation.failures),
    };
    checks.push(check);
    if (!firstPassing) {
      failures.push({
        code: "scenario_ui_transition_not_observed",
        message: "No simulator UI sample matched the relay scenario transition before the next transition.",
        scenarioID: transition.scenarioID,
        transition: transition.transition,
        route: transition.route,
        relaySeenAt: transition.at,
        uiSampleCount: candidates.length,
      });
    } else if (observedLagMs > maxUiLagMs) {
      failures.push({
        code: "scenario_ui_transition_lag_exceeded",
        message: "Simulator UI matched the scenario transition after the rendered lag budget.",
        scenarioID: transition.scenarioID,
        transition: transition.transition,
        route: transition.route,
        observedMs: observedLagMs,
        budgetMs: maxUiLagMs,
        relaySeenAt: transition.at,
        firstPassingSampleAt: firstPassing.sample.sampledAt || null,
      });
    }
  }
  return {
    checks,
    failures,
  };
}

function evaluateDetailTransitionCoverage({ uiSamples, transitions, maxUiLagMs }) {
  const failures = [];
  const checks = [];
  for (const transition of transitions) {
    if (transition.relayLag && transition.relayLag.ok === false) {
      failures.push({
        code: "detail_transition_relay_lag_failed",
        message: "Relay detail transition already exceeded its relay lag budget.",
        scenarioID: transition.scenarioID,
        transition: transition.transition,
        route: transition.route,
        observedMs: transition.relayLag.lag_change_to_relay_ms ?? transition.relayLag.observedLagMs ?? null,
        budgetMs: transition.relayLag.maxStreamLagMs ?? maxUiLagMs,
      });
    }
    const candidates = uiSamples
      .filter((sample) => {
        const sampledAtMs = sampleTimeMS(sample);
        return sampledAtMs >= transition.atMs
          && (transition.untilMs === null || sampledAtMs < transition.untilMs);
      })
      .sort((left, right) => sampleTimeMS(left) - sampleTimeMS(right));
    const evaluations = candidates.map((sample) => ({
      sample,
      evaluation: evaluateDetailTransitionSample(sample, transition),
    }));
    const firstPassing = evaluations.find((entry) => entry.evaluation.ok) || null;
    const observedLagMs = firstPassing
      ? Math.max(0, (firstPassing.evaluation.observedAtMs ?? sampleTimeMS(firstPassing.sample)) - transition.atMs)
      : null;
    const check = {
      scenarioID: transition.scenarioID,
      transition: transition.transition,
      route: transition.route,
      relaySeenAt: transition.at,
      expected: transition.truth,
      uiSampleCount: candidates.length,
      firstPassingSampleAt: firstPassing?.evaluation?.observedAt
        || firstPassing?.sample?.finishedAt
        || firstPassing?.sample?.sampledAt
        || null,
      observedLagMs,
      ok: Boolean(firstPassing) && observedLagMs <= maxUiLagMs,
      failures: evaluations.flatMap((entry) => entry.evaluation.failures),
    };
    checks.push(check);
    if (!firstPassing) {
      failures.push({
        code: "detail_ui_transition_not_observed",
        message: "No simulator detail sample matched the relay detail transition before the next transition.",
        scenarioID: transition.scenarioID,
        transition: transition.transition,
        route: transition.route,
        relaySeenAt: transition.at,
        uiSampleCount: candidates.length,
      });
    } else if (observedLagMs > maxUiLagMs) {
      failures.push({
        code: "detail_ui_transition_lag_exceeded",
        message: "Simulator detail UI matched the transition after the rendered lag budget.",
        scenarioID: transition.scenarioID,
        transition: transition.transition,
        route: transition.route,
        observedMs: observedLagMs,
        budgetMs: maxUiLagMs,
        relaySeenAt: transition.at,
        firstPassingSampleAt: firstPassing.evaluation.observedAt
          || firstPassing.sample.finishedAt
          || firstPassing.sample.sampledAt
          || null,
      });
    }
  }
  return {
    checks,
    failures,
  };
}

function ignoredScenarioWarmupSampleIndexes(uiSamples, scenarioTransitionCoverage) {
  const ignored = new Set();
  for (const check of scenarioTransitionCoverage.checks || []) {
    if (!check.ok || !check.firstPassingSampleAt || !check.relaySeenAt) {
      continue;
    }
    const startedAtMs = dateMS(check.relaySeenAt);
    const firstPassingMs = dateMS(check.firstPassingSampleAt);
    if (startedAtMs === null || firstPassingMs === null || firstPassingMs <= startedAtMs) {
      continue;
    }
    uiSamples.forEach((sample, index) => {
      const sampledAtMs = sampleTimeMS(sample);
      if (sampledAtMs >= startedAtMs && sampledAtMs < firstPassingMs) {
        ignored.add(index);
      }
    });
  }
  return ignored;
}

function buildRenderedUIReport({ relayReport, uiSamples, maxUiLagMs = DEFAULT_MAX_UI_LAG_MS }) {
  const failures = [];
  const transitions = scenarioTransitionTruths(relayReport);
  const detailTransitions = detailTransitionTruths(relayReport);
  const relaySamples = relayTruthSamples(relayReport);
  if (!relayReport.summary?.clientPathOK) {
    failures.push({
      code: "relay_client_path_failed",
      message: "Relay report did not pass client-path proof, so rendered UI proof cannot be trusted.",
    });
  }
  if (!uiSamples.length) {
    failures.push({
      code: "dock_ui_no_samples",
      message: "No simulator displayed-UI samples were recorded.",
    });
  }
  if (!relaySamples.length) {
    failures.push({
      code: "relay_no_samples",
      message: "Relay report contained no samples.",
    });
  }

  const evaluations = uiSamples.map((sample) => evaluateUISample(sample, relaySampleAtOrBefore(relaySamples, sample)));

  const lagAttempts = uiLagAttempts(uiSamples, evaluations);
  const uiLag = evaluateStreamConvergenceLag(lagAttempts, maxUiLagMs);
  if (lagAttempts.length === 0) {
    failures.push({
      code: "dock_ui_no_scored_samples",
      message: "No simulator displayed-UI samples occurred after relay truth samples were available.",
    });
  } else if (!uiLag.ok) {
    failures.push({
      code: "dock_ui_lag_exceeded",
      message: uiLag.converged
        ? "Rendered Dock UI exceeded the convergence budget after divergence."
        : "Rendered Dock UI diverged from relay truth and did not converge.",
      observedMs: uiLag.observedLagMs,
      budgetMs: maxUiLagMs,
      firstMismatchAt: uiLag.firstMismatchAt,
      convergedAt: uiLag.convergedAt,
      lastCheckedAt: uiLag.lastCheckedAt,
    });
  }
  const scenarioTransitionCoverage = evaluateScenarioTransitionCoverage({
    uiSamples,
    transitions,
    maxUiLagMs,
  });
  const detailTransitionCoverage = evaluateDetailTransitionCoverage({
    uiSamples,
    transitions: detailTransitions,
    maxUiLagMs,
  });
  const ignoredScenarioWarmupSamples = ignoredScenarioWarmupSampleIndexes(uiSamples, scenarioTransitionCoverage);
  if (Number.isInteger(uiLag.convergedAttempt)) {
    for (const [index, evaluation] of evaluations.entries()) {
      if (index <= uiLag.convergedAttempt || ignoredScenarioWarmupSamples.has(index)) {
        continue;
      }
      failures.push(...evaluation.failures);
    }
  } else if (lagAttempts.length > 0) {
    failures.push(...(evaluations.at(-1)?.failures || []));
  }

  const bestConsecutivePassingSamples = countConsecutivePassing(evaluations);
  if (lagAttempts.length >= 2 && bestConsecutivePassingSamples < 2) {
    failures.push({
      code: "dock_ui_missing_stable_samples",
      message: "Rendered Dock UI did not produce two consecutive passing samples.",
      bestConsecutivePassingSamples,
    });
  }
  failures.push(...scenarioTransitionCoverage.failures);
  failures.push(...detailTransitionCoverage.failures);

  const report = {
    schemaVersion: 1,
    kind: "codex-dock-simulator-ui-sync-proof",
    startedAt: uiSamples[0]?.sampledAt || null,
    endedAt: uiSamples.at(-1)?.sampledAt || null,
    relayReport: {
      startedAt: relayReport.startedAt || null,
      endedAt: relayReport.endedAt || null,
      relayUrl: relayReport.relayUrl || null,
      clientPathOK: relayReport.summary?.clientPathOK ?? null,
      routeCounts: relayReport.clientPathEvidence?.routeCounts || relayReport.summary?.clientPathRouteCounts || {},
    },
    config: {
      maxUiLagMs,
    },
    summary: {
      ok: failures.length === 0,
      uiSampleCount: uiSamples.length,
      scoredUISampleCount: lagAttempts.length,
      relaySampleCount: relaySamples.length,
      scenarioTransitionCount: transitions.length,
      scenarioTransitionChecks: scenarioTransitionCoverage.checks.length,
      scenarioTransitionFailures: scenarioTransitionCoverage.failures.length,
      detailTransitionCount: detailTransitions.length,
      detailTransitionChecks: detailTransitionCoverage.checks.length,
      detailTransitionFailures: detailTransitionCoverage.failures.length,
      displayedRowChecks: evaluations.reduce((count, evaluation) => count + evaluation.rowCount, 0),
      checkpointSweepCount: uiSamples.filter((sample) => sample.dockSweep).length,
      checkpointSweepRowChecks: evaluations.reduce((count, evaluation) => count + (evaluation.sweepRowCount || 0), 0),
      detailSampleCount: uiSamples.filter((sample) => sample.detail).length,
      detailSweepCount: uiSamples.filter((sample) => sample.detailSweep).length,
      detailSweepMessageCardChecks: uiSamples.reduce((count, sample) => count + detailSweepMessageCardCount(sample), 0),
      scenarioWarmupFailureSamplesIgnored: ignoredScenarioWarmupSamples.size,
      uiLag,
      bestConsecutivePassingSamples,
      failures: failures.length,
    },
    evaluations,
    scenarioTransitionCoverage,
    detailTransitionCoverage,
    failures,
  };
  report.summary.ok = report.failures.length === 0;
  return report;
}

function markdownSummary(report) {
  const lines = [];
  lines.push("# Codex Dock Simulator Displayed-UI Sync Proof");
  lines.push("");
  lines.push(`Started: \`${report.startedAt || "unknown"}\``);
  lines.push(`Ended: \`${report.endedAt || "unknown"}\``);
  lines.push(`Relay: \`${report.relayReport.relayUrl || "unknown"}\``);
  lines.push("");
  lines.push("## Summary");
  lines.push("");
  lines.push(`- OK: ${report.summary.ok ? "true" : "false"}`);
  lines.push(`- Relay client-path OK: ${report.relayReport.clientPathOK === null ? "unknown" : String(report.relayReport.clientPathOK)}`);
  lines.push(`- UI samples: ${report.summary.uiSampleCount}`);
  lines.push(`- Scored UI samples: ${report.summary.scoredUISampleCount}`);
  lines.push(`- Relay samples: ${report.summary.relaySampleCount}`);
  lines.push(`- Scenario transitions: ${report.summary.scenarioTransitionCount}`);
  lines.push(`- Scenario transition failures: ${report.summary.scenarioTransitionFailures}`);
  lines.push(`- Detail transitions: ${report.summary.detailTransitionCount}`);
  lines.push(`- Detail transition failures: ${report.summary.detailTransitionFailures}`);
  lines.push(`- Displayed row checks: ${report.summary.displayedRowChecks}`);
  lines.push(`- Checkpoint sweeps: ${report.summary.checkpointSweepCount}`);
  lines.push(`- Checkpoint sweep row checks: ${report.summary.checkpointSweepRowChecks}`);
  lines.push(`- Detail samples: ${report.summary.detailSampleCount}`);
  lines.push(`- Detail sweeps: ${report.summary.detailSweepCount}`);
  lines.push(`- Detail sweep message-card checks: ${report.summary.detailSweepMessageCardChecks}`);
  lines.push(`- UI lag budget: ${report.config.maxUiLagMs} ms`);
  lines.push(`- UI lag observed: ${report.summary.uiLag?.observedLagMs ?? "not scored"} ms`);
  lines.push(`- UI lag converged: ${report.summary.uiLag?.converged === undefined ? "unknown" : String(report.summary.uiLag.converged)}`);
  lines.push(`- Best consecutive passing samples: ${report.summary.bestConsecutivePassingSamples}`);
  lines.push("");
  lines.push("This report judges literal simulator accessibility state. It does not count screenshots, mocks, scripted stream scenarios, or oracle-only reads as client-display proof.");
  lines.push("");
  lines.push("## Failures");
  lines.push("");
  if (!report.failures.length) {
    lines.push("- None.");
  } else {
    for (const failure of report.failures.slice(0, 50)) {
      lines.push(`- \`${failure.code}\`: ${failure.message}`);
    }
    if (report.failures.length > 50) {
      lines.push(`- ${report.failures.length - 50} more failures omitted from summary.`);
    }
  }
  lines.push("");
  return `${lines.join("\n")}\n`;
}

function writeReportFiles(report, options) {
  if (options.jsonOut) {
    fs.mkdirSync(path.dirname(options.jsonOut), { recursive: true });
    fs.writeFileSync(options.jsonOut, `${JSON.stringify(report, null, 2)}\n`, "utf8");
  }
  if (options.summaryOut) {
    fs.mkdirSync(path.dirname(options.summaryOut), { recursive: true });
    fs.writeFileSync(options.summaryOut, markdownSummary(report), "utf8");
  }
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    console.log(usage());
    return;
  }
  if (!options.relayReport || !options.uiSamples) {
    throw new Error("--relay-report and --ui-samples are required");
  }
  const report = buildRenderedUIReport({
    relayReport: readJSON(options.relayReport),
    uiSamples: readJSONL(options.uiSamples),
    maxUiLagMs: options.maxUiLagMs,
  });
  writeReportFiles(report, options);
  process.stdout.write(`${JSON.stringify({
    ok: report.summary.ok,
    summary: report.summary,
    relayReport: report.relayReport,
    reportPath: options.jsonOut || null,
    summaryPath: options.summaryOut || null,
    failures: report.failures.slice(0, 20),
  }, null, 2)}\n`);
  if (options.failOnDiff && !report.summary.ok) {
    process.exitCode = 1;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.error(`simulator-ui-sync-proof failed: ${error.message || error}`);
    process.exit(1);
  });
}

export {
  buildRenderedUIReport,
  evaluateUISample,
  ignoredScenarioWarmupSampleIndexes,
  parseRootRowCount,
  parseSemicolonValue,
};

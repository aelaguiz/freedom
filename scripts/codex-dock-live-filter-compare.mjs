#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

const DEFAULT_MAX_LAG_MS = 2000;

function usage() {
  return [
    "Usage:",
    "  node scripts/codex-dock-live-filter-compare.mjs --relay-truth <path> --ui-proof <path> --json-out <path> [options]",
    "",
    "Options:",
    "  --max-lag-ms <ms>       Nearest relay sample window. Default: 2000.",
    "  --require-moving        Require movement in a sampled relay filter and matching UI movement.",
  ].join("\n");
}

function parseArgs(argv = process.argv.slice(2)) {
  const options = {
    relayTruth: null,
    uiProof: null,
    jsonOut: null,
    maxLagMS: DEFAULT_MAX_LAG_MS,
    requireMoving: false,
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

    if (arg === "--relay-truth") {
      options.relayTruth = next();
    } else if (arg === "--ui-proof") {
      options.uiProof = next();
    } else if (arg === "--json-out") {
      options.jsonOut = next();
    } else if (arg === "--max-lag-ms") {
      options.maxLagMS = positiveInteger(next(), arg);
    } else if (arg === "--require-moving") {
      options.requireMoving = true;
    } else if (arg === "--help" || arg === "-h") {
      options.help = true;
    } else {
      throw new Error(`unknown argument ${arg}`);
    }
  }

  return options;
}

function positiveInteger(value, name) {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed <= 0) {
    throw new Error(`${name} must be a positive integer`);
  }
  return parsed;
}

function validateOptions(options) {
  if (options.help) {
    return;
  }
  for (const [name, value] of Object.entries({
    "--relay-truth": options.relayTruth,
    "--ui-proof": options.uiProof,
    "--json-out": options.jsonOut,
  })) {
    if (!value) {
      throw new Error(`${name} is required`);
    }
  }
}

function readJSON(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function parseMessageListValue(value) {
  const result = parseSemicolonValue(value);
  return {
    events: Number.isInteger(Number(result.events)) ? Number(result.events) : null,
    filter: result.filter || null,
  };
}

function parseSemicolonValue(value) {
  const result = {};
  for (const part of String(value || "").split(";")) {
    const trimmed = part.trim();
    const separator = trimmed.indexOf("=");
    if (separator === -1) {
      continue;
    }
    result[trimmed.slice(0, separator)] = trimmed.slice(separator + 1);
  }
  return result;
}

function projectionIDsFromElements(...elementGroups) {
  const ids = [];
  const seen = new Set();
  for (const element of elementGroups.flat()) {
    const projectionID = projectionIDFromElement(element);
    if (!projectionID || seen.has(projectionID)) {
      continue;
    }
    seen.add(projectionID);
    ids.push(projectionID);
  }
  return ids;
}

function projectionIDFromElement(element) {
  if (!element) {
    return null;
  }
  const parsed = parseSemicolonValue(element.value || "");
  if (isCanonicalProjectionID(parsed.projection)) {
    return parsed.projection;
  }
  const prefix = "codexdock.session.message.";
  if (typeof element.identifier === "string" && element.identifier.startsWith(prefix)) {
    const decoded = decodeAutomationSegment(element.identifier.slice(prefix.length));
    return isCanonicalProjectionID(decoded) ? decoded : null;
  }
  return null;
}

function isCanonicalProjectionID(value) {
  return typeof value === "string"
    && /^host:[^/]+\/thread:[^/]+\/.+\/row:[^/]+$/u.test(value);
}

function decodeAutomationSegment(value) {
  try {
    return decodeURIComponent(String(value || ""));
  } catch {
    return value || null;
  }
}

function flattenUISamples(uiProof) {
  const samples = [];
  for (const run of Array.isArray(uiProof?.runs) ? uiProof.runs : []) {
    for (const sample of Array.isArray(run.samples) ? run.samples : []) {
      const parsed = parseMessageListValue(sample.messageListValue);
      const uiVisibleProjectionIDs = projectionIDsFromElements(
        sample.messageCards || [],
        sample.sweepMessageCards || [],
      );
      samples.push({
        filter: sample.filter || run.filter || parsed.filter,
        sampledAt: sample.sampledAt,
        finishedAt: sample.finishedAt,
        rootCapturedAt: sample.rootCapturedAt ?? null,
        messageListCapturedAt: sample.messageListCapturedAt ?? null,
        screenKind: sample.screenKind,
        detailRootValue: sample.detailRootValue,
        messageListValue: sample.messageListValue,
        uiEvents: parsed.events,
        messageListFilter: parsed.filter,
        uiVisibleProjectionIDs,
        uiVisibleProjectionIDHead: uiVisibleProjectionIDs[0] ?? null,
      });
    }
  }
  return samples;
}

function timestamp(value) {
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function sampleTimeMS(sample) {
  return relaySampleTimeMS(sample);
}

function uiSampleTimeMS(sample) {
  // Thread Detail filter truth is the message-list value. Score it at the
  // moment that accessibility value was read, not after optional sweeps finish.
  return timestamp(sample?.messageListCapturedAt)
    ?? timestamp(sample?.sampledAt)
    ?? timestamp(sample?.finishedAt);
}

function relaySampleTimeMS(sample) {
  // Relay truth here comes from retained projection witness envelopes. The
  // sample is known only after that witness read finishes, so finishedAt is the
  // canonical clock.
  return timestamp(sample?.finishedAt) ?? timestamp(sample?.sampledAt);
}

function nearestRelaySample(relaySamples, uiSample, maxLagMS) {
  const uiTime = uiSampleTimeMS(uiSample);
  if (uiTime == null) {
    return null;
  }
  let best = null;
  for (const relaySample of relaySamples) {
    const relayTime = relaySampleTimeMS(relaySample);
    if (relayTime == null) {
      continue;
    }
    const lagMS = Math.abs(uiTime - relayTime);
    if (lagMS > maxLagMS) {
      continue;
    }
    if (!best || lagMS < best.lagMS) {
      best = { relaySample, lagMS };
    }
  }
  return best;
}

function uniqueCounts(samples, key) {
  return [...new Set(samples.map((sample) => sample[key]).filter((value) => value != null))];
}

function uniqueSequences(samples, key) {
  return [...new Set(
    samples
      .map((sample) => sample[key])
      .filter((value) => Array.isArray(value) && value.length > 0)
      .map((value) => JSON.stringify(value)),
  )];
}

function compare(relayTruth, uiProof, options) {
  const relaySamples = Array.isArray(relayTruth?.samples) ? relayTruth.samples : [];
  const uiSamples = flattenUISamples(uiProof);
  const runEvaluations = evaluateRuns(relaySamples, uiProof, options);
  const comparisons = [];
  const failures = [];

  for (const uiSample of uiSamples) {
    const nearest = nearestRelaySample(relaySamples, uiSample, options.maxLagMS);
    if (!nearest) {
      comparisons.push({ uiSample, relaySample: null, lagMS: null, expectedEvents: null, ok: false });
      continue;
    }

    const expectedEvents = nearest.relaySample?.turns?.visibleCounts?.[uiSample.filter] ?? null;
    const expectedProjectionIDHead = nearest.relaySample?.turns?.visibleProjectionIDs?.[uiSample.filter]?.[0] ?? null;
    const ok = uiSample.screenKind === "thread"
      && uiSample.messageListFilter === uiSample.filter
      && Number.isInteger(uiSample.uiEvents);

    if (!ok) {
      failures.push({
        code: "invalid_ui_filter_sample",
        message: "UI sample did not expose a valid Thread Detail filter count.",
        filter: uiSample.filter,
        sampledAt: uiSample.sampledAt,
        messageListCapturedAt: uiSample.messageListCapturedAt ?? null,
        uiEvents: uiSample.uiEvents,
        uiVisibleProjectionIDHead: uiSample.uiVisibleProjectionIDHead,
        messageListFilter: uiSample.messageListFilter,
        expectedEvents,
        expectedProjectionIDHead,
        relaySampledAt: nearest.relaySample.sampledAt,
        lagMS: nearest.lagMS,
        screenKind: uiSample.screenKind,
      });
    }

    comparisons.push({
      uiSample,
      relaySample: {
        sampledAt: nearest.relaySample.sampledAt,
        dockActivityAt: nearest.relaySample.dock?.targetCard?.activityAt ?? null,
        visibleCounts: nearest.relaySample.turns?.visibleCounts ?? {},
        visibleProjectionIDHeads: Object.fromEntries(Object.entries(nearest.relaySample.turns?.visibleProjectionIDs ?? {})
          .map(([filter, ids]) => [filter, Array.isArray(ids) ? ids[0] ?? null : null])),
      },
      lagMS: nearest.lagMS,
      expectedEvents,
      expectedProjectionIDHead,
      ok,
    });
  }

  for (const evaluation of runEvaluations) {
    if (!evaluation.ok) {
      failures.push(...evaluation.failures);
    }
  }

  const sampledFilters = Object.keys(groupUISamplesByFilter(uiSamples)).sort();
  const relayMoving = Boolean(relayTruth?.summary?.moving);
  const relayMovingFilters = movingRelayFilters(relayTruth, relaySamples, sampledFilters);
  const relayMovingInSampledFilters = relayMovingFilters.length > 0;
  const uiMoving = Object.values(groupUISamplesByFilter(uiSamples)).some((samples) => (
    uniqueCounts(samples, "uiEvents").length > 1
      || uniqueSequences(samples, "uiVisibleProjectionIDs").length > 1
  ));
  if (options.requireMoving && !relayMovingInSampledFilters) {
    failures.push({
      code: "sampled_filter_movement_not_observed",
      message: "Moving proof requires relay movement in at least one sampled Thread Detail filter.",
      relayMoving,
      relayMovingInSampledFilters,
      sampledFilters,
    });
  } else if (options.requireMoving && !uiMoving) {
    failures.push({
      code: "moving_updates_not_proven",
      message: "Moving proof requires UI count or visible projection-id changes in a sampled Thread Detail filter that moved in relay truth.",
      relayMoving,
      relayMovingInSampledFilters,
      uiMoving,
      sampledFilters,
      relayMovingFilters,
    });
  }

  return {
    schemaVersion: 1,
    kind: "codex-dock-live-filter-compare",
    mode: "settled-history-convergence",
    status: failures.length ? "fail" : "pass",
    relayTruthPath: options.relayTruth,
    uiProofPath: options.uiProof,
    maxLagMS: options.maxLagMS,
    requireMoving: options.requireMoving,
    threadID: relayTruth?.threadID ?? uiProof?.openThreadID ?? null,
    startedAt: new Date().toISOString(),
    finishedAt: new Date().toISOString(),
    summary: {
      ok: failures.length === 0,
      relaySampleCount: relaySamples.length,
      uiSampleCount: uiSamples.length,
      comparisonCount: comparisons.length,
      relayMoving,
      relayMovingInSampledFilters,
      relayMovingFilters,
      uiMoving,
      filters: summarizeUIFilters(uiSamples),
      runEvaluations: summarizeRunEvaluations(runEvaluations),
    },
    failures,
    comparisons,
    runEvaluations,
  };
}

function movingRelayFilters(relayTruth, relaySamples, filters) {
  return filters.filter((filter) => relayFilterMoved(relayTruth, relaySamples, filter));
}

function relayFilterMoved(relayTruth, relaySamples, filter) {
  if (relayTruth?.summary?.filters?.[filter]?.changed === true) {
    return true;
  }
  const counts = relaySamples
    .map((sample) => sample?.turns?.visibleCounts?.[filter])
    .filter((value) => value !== undefined);
  if (new Set(counts).size > 1) {
    return true;
  }
  const sequences = relaySamples
    .map((sample) => sample?.turns?.visibleProjectionIDs?.[filter])
    .filter((value) => Array.isArray(value) && value.length > 0)
    .map((value) => JSON.stringify(value));
  return new Set(sequences).size > 1;
}

function evaluateRuns(relaySamples, uiProof, options) {
  const evaluations = [];
  const runs = Array.isArray(uiProof?.runs) ? uiProof.runs : [];
  for (const [runIndex, run] of runs.entries()) {
    const samples = (Array.isArray(run.samples) ? run.samples : [])
      .map((sample) => {
        const parsed = parseMessageListValue(sample.messageListValue);
        return {
          ...sample,
          events: parsed.events,
          messageListFilter: parsed.filter,
          filter: sample.filter || run.filter || parsed.filter,
          uiVisibleProjectionIDs: projectionIDsFromElements(
            sample.messageCards || [],
            sample.sweepMessageCards || [],
          ),
        };
      })
      .filter((sample) => sample.sampledAt);
    const filter = run.filter || samples[0]?.filter || null;
    const failures = [];
    if (!filter) {
      failures.push({
        code: "run_filter_missing",
        message: "UI run did not identify which Thread Detail filter it sampled.",
        runIndex,
      });
      evaluations.push(runEvaluation(runIndex, run, samples, null, null, failures));
      continue;
    }
    if (!samples.length) {
      failures.push({
        code: "run_samples_missing",
        message: "UI run did not contain any samples.",
        runIndex,
        filter,
      });
      evaluations.push(runEvaluation(runIndex, run, samples, filter, null, failures));
      continue;
    }

    for (const sample of samples) {
      if (
        sample.screenKind !== "thread"
        || sample.filter !== filter
        || sample.messageListFilter !== filter
        || !Number.isInteger(sample.events)
      ) {
        failures.push({
          code: "invalid_ui_filter_sample",
          message: "UI sample did not expose a valid Thread Detail filter count.",
          runIndex,
          filter,
          sampledAt: sample.sampledAt,
          screenKind: sample.screenKind,
          messageListFilter: sample.messageListFilter,
          uiEvents: sample.events,
        });
      }
    }

    const validSamples = samples.filter((sample) => Number.isInteger(sample.events));
    const lastUISample = validSamples.at(-1) || null;
    const lastUITime = uiSampleTimeMS(lastUISample);
    const relayCutoff = Number.isFinite(lastUITime) ? lastUITime - options.maxLagMS : null;
    const relaySample = latestRelaySampleAtOrBefore(relaySamples, relayCutoff);
    const expectedEvents = relaySample?.turns?.visibleCounts?.[filter] ?? null;
    const expectedProjectionIDs = relaySample?.turns?.visibleProjectionIDs?.[filter] ?? [];
    const lastUIEvents = lastUISample?.events ?? null;
    const lastUIProjectionIDs = Array.isArray(lastUISample?.uiVisibleProjectionIDs) ? lastUISample.uiVisibleProjectionIDs : [];

    if (!relaySample) {
      failures.push({
        code: "missing_settled_relay_sample",
        message: "No settled relay truth sample was old enough to score this UI run.",
        runIndex,
        filter,
        maxLagMS: options.maxLagMS,
        lastUISampledAt: lastUISample?.sampledAt ?? null,
        lastUIMessageListCapturedAt: lastUISample?.messageListCapturedAt ?? null,
      });
    } else if (!Number.isInteger(expectedEvents)) {
      failures.push({
        code: "missing_relay_filter_count",
        message: "Settled relay truth sample did not contain this filter count.",
        runIndex,
        filter,
        relaySampledAt: relaySample.sampledAt,
      });
    } else if (!Number.isInteger(lastUIEvents) || lastUIEvents < expectedEvents) {
      failures.push({
        code: "filter_convergence_lag_exceeded",
        message: "UI filter count did not catch up to settled relay history within the lag budget.",
        runIndex,
        filter,
        lastUISampledAt: lastUISample?.sampledAt ?? null,
        lastUIMessageListCapturedAt: lastUISample?.messageListCapturedAt ?? null,
        lastUIEvents,
        expectedAtLeastEvents: expectedEvents,
        relaySampledAt: relaySample.sampledAt,
        relayFinishedAt: relaySample.finishedAt,
        maxLagMS: options.maxLagMS,
      });
    }
    failures.push(...projectionIDFailures({
      runIndex,
      filter,
      lastUISample,
      lastUIProjectionIDs,
      expectedProjectionIDs,
      relaySample,
      maxLagMS: options.maxLagMS,
    }));

    evaluations.push(runEvaluation(runIndex, run, samples, filter, relaySample, failures, {
      lastUISample,
      lastUIEvents,
      lastUIProjectionIDs,
      expectedEvents,
      expectedProjectionIDHead: expectedProjectionIDs[0] ?? null,
      relayCutoff: Number.isFinite(relayCutoff) ? new Date(relayCutoff).toISOString() : null,
    }));
  }
  return evaluations;
}

function latestRelaySampleAtOrBefore(relaySamples, cutoffMS) {
  if (!Number.isFinite(cutoffMS)) {
    return null;
  }
  let selected = null;
  for (const sample of relaySamples) {
    const sampleMS = relaySampleTimeMS(sample);
    if (!Number.isFinite(sampleMS)) {
      continue;
    }
    if (sampleMS <= cutoffMS) {
      selected = sample;
    }
  }
  return selected;
}

function projectionIDFailures({
  runIndex,
  filter,
  lastUISample,
  lastUIProjectionIDs,
  expectedProjectionIDs,
  relaySample,
  maxLagMS,
}) {
  if (!Array.isArray(expectedProjectionIDs) || !expectedProjectionIDs.length || !lastUIProjectionIDs.length) {
    return [];
  }
  const failures = [];
  const expectedSet = new Set(expectedProjectionIDs);
  const comparableActual = lastUIProjectionIDs.filter((projectionID) => expectedSet.has(projectionID));
  if (comparableActual.length > 1 && !orderedSubsequence(comparableActual, expectedProjectionIDs)) {
    failures.push({
      code: "filter_projection_order_mismatch",
      message: "UI projection ids are present but not in settled relay order.",
      runIndex,
      filter,
      lastUISampledAt: lastUISample?.sampledAt ?? null,
      lastUIMessageListCapturedAt: lastUISample?.messageListCapturedAt ?? null,
      actualProjectionIDs: comparableActual,
      expectedProjectionIDs,
      relaySampledAt: relaySample?.sampledAt ?? null,
      relayFinishedAt: relaySample?.finishedAt ?? null,
      maxLagMS,
    });
  }

  const newestExpectedID = expectedProjectionIDs[0] ?? null;
  const hasSweep = Array.isArray(lastUISample?.sweepMessageCards) && lastUISample.sweepMessageCards.length > 0;
  if (hasSweep && newestExpectedID && !lastUIProjectionIDs.includes(newestExpectedID)) {
    failures.push({
      code: "filter_newest_projection_missing",
      message: "UI checkpoint sweep did not include the newest settled relay projection row for this filter.",
      runIndex,
      filter,
      lastUISampledAt: lastUISample?.sampledAt ?? null,
      lastUIMessageListCapturedAt: lastUISample?.messageListCapturedAt ?? null,
      newestExpectedID,
      actualProjectionIDHead: lastUIProjectionIDs[0] ?? null,
      relaySampledAt: relaySample?.sampledAt ?? null,
      relayFinishedAt: relaySample?.finishedAt ?? null,
      maxLagMS,
    });
  }
  return failures;
}

function orderedSubsequence(values, reference) {
  const referenceIndex = new Map();
  reference.forEach((value, index) => {
    if (!referenceIndex.has(value)) {
      referenceIndex.set(value, index);
    }
  });
  const filtered = values.filter((value) => referenceIndex.has(value));
  for (let index = 1; index < filtered.length; index += 1) {
    if (referenceIndex.get(filtered[index]) < referenceIndex.get(filtered[index - 1])) {
      return false;
    }
  }
  return true;
}

function runEvaluation(
  runIndex,
  run,
  samples,
  filter,
  relaySample,
  failures,
  extra = {},
) {
  const counts = samples
    .map((sample) => sample.events)
    .filter((count) => Number.isInteger(count));
  const projectionIDHeads = samples
    .map((sample) => sample.uiVisibleProjectionIDs?.[0] ?? null)
    .filter(Boolean);
  return {
    runIndex,
    filter,
    selectedAt: run.selectedAt || null,
    sampleCount: samples.length,
    firstUIEvents: counts[0] ?? null,
    lastUIEvents: extra.lastUIEvents ?? counts.at(-1) ?? null,
    uniqueUIEvents: [...new Set(counts)],
    firstUIProjectionIDHead: projectionIDHeads[0] ?? null,
    lastUIProjectionIDHead: extra.lastUIProjectionIDs?.[0] ?? projectionIDHeads.at(-1) ?? null,
    uniqueUIProjectionIDHeads: [...new Set(projectionIDHeads)],
    relaySampledAt: relaySample?.sampledAt ?? null,
    relayFinishedAt: relaySample?.finishedAt ?? null,
    relayCutoff: extra.relayCutoff ?? null,
    expectedEvents: extra.expectedEvents ?? null,
    expectedProjectionIDHead: extra.expectedProjectionIDHead ?? null,
    ok: failures.length === 0,
    failures,
  };
}

function summarizeRunEvaluations(evaluations) {
  return evaluations.map((evaluation) => ({
    runIndex: evaluation.runIndex,
    filter: evaluation.filter,
    ok: evaluation.ok,
    firstUIEvents: evaluation.firstUIEvents,
    lastUIEvents: evaluation.lastUIEvents,
    expectedEvents: evaluation.expectedEvents,
    uniqueUIEvents: evaluation.uniqueUIEvents,
    firstUIProjectionIDHead: evaluation.firstUIProjectionIDHead,
    lastUIProjectionIDHead: evaluation.lastUIProjectionIDHead,
    expectedProjectionIDHead: evaluation.expectedProjectionIDHead,
    uniqueUIProjectionIDHeads: evaluation.uniqueUIProjectionIDHeads,
  }));
}

function groupUISamplesByFilter(samples) {
  const groups = {};
  for (const sample of samples) {
    const filter = sample.filter || "unknown";
    groups[filter] ||= [];
    groups[filter].push(sample);
  }
  return groups;
}

function summarizeUIFilters(samples) {
  const summary = {};
  for (const [filter, filterSamples] of Object.entries(groupUISamplesByFilter(samples))) {
    const counts = uniqueCounts(filterSamples, "uiEvents");
    const projectionIDSequences = uniqueSequences(filterSamples, "uiVisibleProjectionIDs");
    summary[filter] = {
      sampleCount: filterSamples.length,
      first: counts[0] ?? null,
      last: counts.at(-1) ?? null,
      unique: counts,
      projectionIDSequenceCount: projectionIDSequences.length,
      changed: counts.length > 1 || projectionIDSequences.length > 1,
    };
  }
  return summary;
}

function run(options) {
  validateOptions(options);
  if (options.help) {
    console.log(usage());
    return null;
  }
  const relayTruth = readJSON(options.relayTruth);
  const uiProof = readJSON(options.uiProof);
  const report = compare(relayTruth, uiProof, options);
  fs.mkdirSync(path.dirname(options.jsonOut), { recursive: true });
  fs.writeFileSync(options.jsonOut, `${JSON.stringify(report, null, 2)}\n`);
  return report;
}

function main(argv = process.argv.slice(2)) {
  const options = parseArgs(argv);
  const report = run(options);
  if (report) {
    console.log(`wrote ${options.jsonOut}`);
    console.log(`status=${report.status} relayMoving=${report.summary.relayMoving} relayMovingInSampledFilters=${report.summary.relayMovingInSampledFilters} uiMoving=${report.summary.uiMoving} comparisons=${report.summary.comparisonCount}`);
    if (report.failures.length) {
      process.exitCode = 1;
    }
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    main();
  } catch (error) {
    console.error(`live filter compare failed: ${error.message || error}`);
    process.exit(1);
  }
}

export {
  compare,
  parseArgs,
  parseMessageListValue,
  run,
};

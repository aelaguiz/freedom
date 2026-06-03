#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { JsonRpcWebSocketClient } from "./dock-relay-json-rpc-client.mjs";

const DEFAULT_RELAY_URL = "ws://127.0.0.1:4510";
const DEFAULT_DURATION_MS = 30000;
const DEFAULT_SAMPLE_MS = 1000;
const DEFAULT_VISIBLE_LIMIT = 240;

function usage() {
  return [
    "Usage:",
    "  node scripts/codex-dock-live-filter-truth.mjs --thread-id <id> --json-out <path> [options]",
    "",
    "Options:",
    "  --relay-url <ws-url>       Relay WebSocket URL. Default: ws://127.0.0.1:4510.",
    "  --source-host-id <id>      Expected relay source host. Defaults to the Dock card sourceHostID.",
    "  --duration-ms <ms>         Sampling duration. Default: 30000.",
    "  --sample-ms <ms>           Sampling interval. Default: 1000.",
    "  --visible-limit <count>    Thread Detail visible row window. Default: 240.",
  ].join("\n");
}

function parseArgs(argv = process.argv.slice(2)) {
  const options = {
    relayUrl: DEFAULT_RELAY_URL,
    threadID: null,
    sourceHostID: null,
    jsonOut: null,
    durationMS: DEFAULT_DURATION_MS,
    sampleMS: DEFAULT_SAMPLE_MS,
    visibleLimit: DEFAULT_VISIBLE_LIMIT,
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

    if (arg === "--relay-url") {
      options.relayUrl = next();
    } else if (arg === "--thread-id") {
      options.threadID = next();
    } else if (arg === "--source-host-id") {
      options.sourceHostID = next();
    } else if (arg === "--json-out") {
      options.jsonOut = next();
    } else if (arg === "--duration-ms") {
      options.durationMS = positiveInteger(next(), arg);
    } else if (arg === "--sample-ms") {
      options.sampleMS = positiveInteger(next(), arg);
    } else if (arg === "--visible-limit") {
      options.visibleLimit = positiveInteger(next(), arg);
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
  if (!options.threadID) {
    throw new Error("--thread-id is required");
  }
  if (!options.jsonOut) {
    throw new Error("--json-out is required");
  }
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function initializeClient(options) {
  const client = new JsonRpcWebSocketClient(options.relayUrl, {
    requestTimeoutMs: 30000,
  });
  await client.connect();
  await client.request("initialize", {
    clientInfo: {
      name: "codex_dock_live_filter_truth",
      title: "Codex Dock Live Filter Truth",
      version: "0.1.0",
    },
    capabilities: {
      experimentalApi: true,
      requestAttestation: false,
    },
  });
  client.notify("initialized");
  return client;
}

function threadIDForCard(card) {
  return card?.threadID || card?.threadId || null;
}

async function readDockCard(client, threadID) {
  const dock = await client.request("dock/subscribe", {});
  const cards = Array.isArray(dock?.rows) ? dock.rows : [];
  const card = cards.find((candidate) => threadIDForCard(candidate) === threadID) || null;
  return {
    totalRows: dock?.totalRows ?? null,
    rowCount: cards.length,
    complete: dock?.complete ?? null,
    freshness: dock?.freshness ?? null,
    seq: dock?.seq ?? null,
    targetCardFound: Boolean(card),
    targetCard: card ? summarizeCard(card) : null,
  };
}

function summarizeCard(card) {
  return {
    id: card.id ?? null,
    projectionID: card.projectionID ?? null,
    sourceHostID: card.sourceHostID ?? null,
    threadID: threadIDForCard(card),
    status: card.status ?? null,
    activityAt: card.activityAt ?? null,
    hostEndpoint: card.hostEndpoint ?? null,
    sourceKind: card.sourceKind ?? null,
    completeness: card.completeness ?? null,
    title: card.title || card.summary || card.lastMessagePreview || null,
  };
}

async function readDetailProjection(client, threadID, sourceHostID = null) {
  const params = {
    view: "thread.detail",
    scope: "thread",
    threadID,
  };
  if (sourceHostID) {
    params.sourceHostID = sourceHostID;
  }
  const witness = await client.request("projection/witness/read", params);
  if (witness?.byteEquivalentToDownstream !== true) {
    throw new Error("projection witness did not report byte-equivalent downstream envelopes");
  }
  if (!Array.isArray(witness?.envelopes) || witness.envelopes.length === 0) {
    throw new Error("projection witness has no retained Thread Detail envelopes for this thread");
  }
  const rows = projectionRowsFromWitness(witness);
  return {
    source: "projection/witness/read",
    byteEquivalentToDownstream: witness?.byteEquivalentToDownstream === true,
    threadID: witness?.threadID || null,
    sourceHostID: witness?.sourceHostID || null,
    view: witness?.view || null,
    viewParamsKey: witness?.viewParamsKey || null,
    seq: witness?.lastSeq ?? null,
    epoch: witness?.epoch || null,
    projectionEngineVersion: rows.at(-1)?.projectionEngineVersion ?? null,
    rowCount: rows.length,
    envelopeCount: Array.isArray(witness?.envelopes) ? witness.envelopes.length : 0,
    projectionIDs: Array.isArray(witness?.projectionIDs) ? witness.projectionIDs : [],
    rows,
  };
}

function projectionRowsFromWitness(witness) {
  const rowsByProjectionID = new Map();
  for (const envelope of witness?.envelopes || []) {
    if (envelope.kind === "delete") {
      for (const projectionID of envelope.projectionIDs || []) {
        rowsByProjectionID.delete(projectionID);
      }
      continue;
    }
    if (envelope.kind === "snapshot" || !envelope.kind) {
      rowsByProjectionID.clear();
    }
    for (const row of envelope.rows || []) {
      if (row?.projectionID) {
        rowsByProjectionID.set(row.projectionID, {
          ...row,
          projectionEngineVersion: envelope.projectionEngineVersion ?? null,
        });
      }
    }
  }
  return [...rowsByProjectionID.values()]
    .sort((left, right) => {
      const leftOrder = typeof left?.displayOrderKey === "string" ? left.displayOrderKey : "";
      const rightOrder = typeof right?.displayOrderKey === "string" ? right.displayOrderKey : "";
      if (leftOrder !== rightOrder) {
        return leftOrder.localeCompare(rightOrder);
      }
      return String(left?.projectionID || "").localeCompare(String(right?.projectionID || ""));
    });
}

function increment(map, key, by = 1) {
  map.set(key, (map.get(key) || 0) + by);
}

function sortProjectionRows(rows) {
  return [...rows].sort((left, right) => {
    const leftOrder = typeof left?.displayOrderKey === "string" ? left.displayOrderKey : "";
    const rightOrder = typeof right?.displayOrderKey === "string" ? right.displayOrderKey : "";
    if (leftOrder !== rightOrder) {
      return leftOrder.localeCompare(rightOrder);
    }
    return String(left?.projectionID || "").localeCompare(String(right?.projectionID || ""));
  });
}

function rowMatchesFilter(row, filter) {
  const visibility = row?.visibility || "unknown";
  const kind = row?.kind || "unknown";
  if (filter === "all") {
    return true;
  }
  if (filter === "messages") {
    return visibility === "request"
      || (visibility === "message" && (kind === "userMessage" || kind === "agentMessage"));
  }
  return kind === filter;
}

function projectionRowTruth(row) {
  const payload = row?.payload || {};
  return {
    projectionID: row?.projectionID || null,
    sourceHostID: row?.sourceHostID || null,
    displayOrderKey: row?.displayOrderKey || null,
    kind: payload.renderKind || row?.renderKind || row?.rowRole || row?.itemType || "unknown",
    visibility: payload.visibility || row?.visibility || "unknown",
    itemType: payload.itemType || row?.itemType || row?.rowRole || "unknown",
    turnID: payload.turnID || row?.turnID || null,
    itemID: payload.itemID || row?.itemID || null,
  };
}

function filterCountsFromProjectionRows(projectionRows, visibleLimit) {
  const itemTypeCounts = new Map();
  const rowKindCounts = new Map();
  const visibilityCounts = new Map();
  const filterCounts = new Map([
    ["messages", 0],
    ["all", 0],
    ["userMessage", 0],
    ["agentMessage", 0],
    ["command", 0],
    ["output", 0],
    ["request", 0],
    ["system", 0],
    ["unknown", 0],
  ]);

  const rows = projectionRows.map(projectionRowTruth);
  for (const row of rows) {
    increment(itemTypeCounts, row.itemType);
    increment(rowKindCounts, row.kind);
    increment(visibilityCounts, row.visibility);
    increment(filterCounts, "all");
    increment(filterCounts, row.kind);
    if (
      row.visibility === "request"
      || (row.visibility === "message" && (row.kind === "userMessage" || row.kind === "agentMessage"))
    ) {
      increment(filterCounts, "messages");
    }
  }

  const counts = Object.fromEntries(filterCounts);
  const visibleCounts = Object.fromEntries(
    Object.entries(counts).map(([filter, count]) => [filter, Math.min(count, visibleLimit)]),
  );
  const sortedRows = sortProjectionRows(rows);
  const filters = [...filterCounts.keys()];
  const visibleProjectionIDs = Object.fromEntries(
    filters.map((filter) => [
      filter,
      sortedRows
        .filter((row) => rowMatchesFilter(row, filter))
        .slice(0, visibleLimit)
        .map((row) => row.projectionID)
        .filter(Boolean),
    ]),
  );
  return {
    source: "projection/witness/read",
    turnCount: new Set(rows.map((row) => row.turnID).filter(Boolean)).size,
    pageLimited: false,
    rawItemCount: null,
    rowCount: rows.length,
    newestTurnID: sortedRows.find((row) => row.turnID)?.turnID || null,
    newestTurnCompletedAt: null,
    oldestTurnID: [...rows].reverse().find((row) => row.turnID)?.turnID || null,
    counts,
    visibleCounts,
    visibleProjectionIDs,
    rawTypeCounts: Object.fromEntries([...itemTypeCounts].sort()),
    rowKindCounts: Object.fromEntries([...rowKindCounts].sort()),
    visibilityCounts: Object.fromEntries([...visibilityCounts].sort()),
  };
}

async function sampleThread(client, options, index) {
  const sampledAt = new Date().toISOString();
  const dock = await readDockCard(client, options.threadID);
  const sourceHostID = options.sourceHostID || dock.targetCard?.sourceHostID || null;
  const detail = await readDetailProjection(client, options.threadID, sourceHostID);
  return {
    index,
    sampledAt,
    finishedAt: new Date().toISOString(),
    dock,
    detail: {
      source: detail.source,
      threadID: detail.threadID,
      sourceHostID: detail.sourceHostID,
      view: detail.view,
      viewParamsKey: detail.viewParamsKey,
      seq: detail.seq,
      epoch: detail.epoch,
      projectionEngineVersion: detail.projectionEngineVersion,
      byteEquivalentToDownstream: detail.byteEquivalentToDownstream,
      envelopeCount: detail.envelopeCount,
      projectionIDCount: detail.projectionIDs.length,
      rowCount: detail.rowCount,
    },
    turns: {
      pageCount: 1,
      ...filterCountsFromProjectionRows(detail.rows, options.visibleLimit),
    },
  };
}

function summarizeSamples(samples) {
  const filters = ["messages", "all", "userMessage", "agentMessage", "command", "output", "request", "system", "unknown"];
  const filterSummary = {};
  for (const filter of filters) {
    const values = samples.map((sample) => sample.turns?.visibleCounts?.[filter]).filter((value) => value !== undefined);
    const visibleProjectionIDHeads = samples
      .map((sample) => sample.turns?.visibleProjectionIDs?.[filter]?.[0])
      .filter(Boolean);
    const visibleProjectionIDSequences = samples
      .map((sample) => sample.turns?.visibleProjectionIDs?.[filter])
      .filter((value) => Array.isArray(value) && value.length > 0)
      .map((value) => JSON.stringify(value));
    filterSummary[filter] = {
      first: values[0] ?? null,
      last: values.at(-1) ?? null,
      unique: [...new Set(values)],
      visibleProjectionIDHeadFirst: visibleProjectionIDHeads[0] ?? null,
      visibleProjectionIDHeadLast: visibleProjectionIDHeads.at(-1) ?? null,
      visibleProjectionIDHeadUnique: [...new Set(visibleProjectionIDHeads)],
      changed: new Set(values).size > 1 || new Set(visibleProjectionIDSequences).size > 1,
    };
  }
  const activityValues = samples.map((sample) => sample.dock?.targetCard?.activityAt ?? null);
  return {
    sampleCount: samples.length,
    startedAt: samples[0]?.sampledAt ?? null,
    finishedAt: samples.at(-1)?.finishedAt ?? null,
    moving: Object.values(filterSummary).some((entry) => entry.changed) || new Set(activityValues).size > 1,
    activityAt: {
      first: activityValues[0] ?? null,
      last: activityValues.at(-1) ?? null,
      unique: [...new Set(activityValues)],
      changed: new Set(activityValues).size > 1,
    },
    filters: filterSummary,
  };
}

async function run(options) {
  validateOptions(options);
  if (options.help) {
    console.log(usage());
    return null;
  }

  const client = await initializeClient(options);
  const startedAt = new Date().toISOString();
  const samples = [];
  const deadline = Date.now() + options.durationMS;
  let index = 0;
  try {
    do {
      samples.push(await sampleThread(client, options, index));
      index += 1;
      if (Date.now() < deadline) {
        await sleep(Math.min(options.sampleMS, Math.max(0, deadline - Date.now())));
      }
    } while (Date.now() < deadline);
  } finally {
    await client.close();
  }

  const report = {
    schemaVersion: 1,
    kind: "codex-dock-live-filter-relay-truth",
    relayUrl: options.relayUrl,
    threadID: options.threadID,
    sourceHostID: options.sourceHostID,
    durationMS: options.durationMS,
    sampleMS: options.sampleMS,
    visibleLimit: options.visibleLimit,
    startedAt,
    finishedAt: new Date().toISOString(),
    summary: summarizeSamples(samples),
    samples,
  };

  fs.mkdirSync(path.dirname(options.jsonOut), { recursive: true });
  fs.writeFileSync(options.jsonOut, `${JSON.stringify(report, null, 2)}\n`);
  return report;
}

async function main(argv = process.argv.slice(2)) {
  const options = parseArgs(argv);
  const report = await run(options);
  if (report) {
    console.log(`wrote ${options.jsonOut}`);
    console.log(`moving=${report.summary.moving} messages=${report.summary.filters.messages.first}->${report.summary.filters.messages.last} all=${report.summary.filters.all.first}->${report.summary.filters.all.last}`);
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    await main();
  } catch (error) {
    console.error(`live filter truth failed: ${error.message || error}`);
    process.exit(1);
  }
}

export {
  filterCountsFromProjectionRows,
  parseArgs,
  summarizeSamples,
  sortProjectionRows,
  run,
};

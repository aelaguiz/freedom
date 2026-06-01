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
    "  --duration-ms <ms>         Sampling duration. Default: 30000.",
    "  --sample-ms <ms>           Sampling interval. Default: 1000.",
    "  --visible-limit <count>    Thread Detail visible row window. Default: 240.",
  ].join("\n");
}

function parseArgs(argv = process.argv.slice(2)) {
  const options = {
    relayUrl: DEFAULT_RELAY_URL,
    threadID: null,
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
  if (typeof card?.id === "string" && card.id.includes("::")) {
    return card.id.split("::").at(-1);
  }
  return card?.threadId || card?.threadID || card?.id || null;
}

async function readDockCard(client, threadID) {
  const dock = await client.request("dock/subscribe", {});
  const cards = Array.isArray(dock?.cards) ? dock.cards : [];
  const card = cards.find((candidate) => threadIDForCard(candidate) === threadID) || null;
  return {
    totalRows: dock?.totalRows ?? null,
    cardCount: cards.length,
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
    threadID: threadIDForCard(card),
    status: card.status ?? null,
    activityAt: card.activityAt ?? null,
    logicalHostID: card.logicalHostID ?? null,
    hostEndpoint: card.hostEndpoint ?? null,
    sourceKind: card.sourceKind ?? null,
    completeness: card.completeness ?? null,
    title: card.title || card.summary || card.lastMessagePreview || null,
  };
}

async function readTurns(client, threadID) {
  let cursor = null;
  const seenCursors = new Set();
  const turns = [];
  let pageCount = 0;

  while (true) {
    const page = await client.request("thread/turns/list", {
      threadId: threadID,
      cursor,
      limit: 250,
      sortDirection: "desc",
      itemsView: "full",
    });
    pageCount += 1;
    turns.push(...(Array.isArray(page?.data) ? page.data : []));
    const nextCursor = page?.nextCursor || null;
    if (!nextCursor) {
      break;
    }
    if (seenCursors.has(nextCursor)) {
      throw new Error(`repeated thread/turns/list cursor ${nextCursor}`);
    }
    seenCursors.add(nextCursor);
    cursor = nextCursor;
  }

  return { pageCount, turns };
}

function increment(map, key, by = 1) {
  map.set(key, (map.get(key) || 0) + by);
}

function renderedRowsForItem(item, turn, turnSequence, itemSequence, rowOffset) {
  const type = item?.type || "unknown";
  const eventDateMS = displayDateMSForItem(type, turn);
  const turnID = turn?.id || turn?.turnId || turn?.turnID || "turn";
  const itemID = item?.id || "item";
  const row = (suffix, kind, visibility, eventSequence = 0) => ({
    eventID: `${turnID}-${itemID}-${suffix}`,
    kind,
    visibility,
    eventDateMS,
    turnSequence,
    itemSequence,
    itemKey: `item:${itemID}`,
    eventSequence,
    rowOffset,
  });
  switch (type) {
  case "userMessage":
    return [row("user", "userMessage", "message")];
  case "agentMessage":
    return [row("agent", "agentMessage", "message")];
  case "plan":
    return [row("plan", "agentMessage", "thinking")];
  case "reasoning":
    return [row("reasoning", "agentMessage", "thinking")];
  case "commandExecution": {
    const rows = [row("command", "command", "tooling")];
    if (nonEmptyString(item?.aggregatedOutput)) {
      rows.push(row("output", "output", "tooling", 1));
    }
    return rows;
  }
  case "fileChange":
    return [row("file-change", "request", "request")];
  case "mcpToolCall":
  case "dynamicToolCall":
    return [row("tool", "command", "tooling")];
  default:
    return [row("unknown", "unknown", "unknown")];
  }
}

function nonEmptyString(value) {
  return typeof value === "string" && value.trim().length > 0;
}

function displayDateMSForItem(type, turn) {
  const startedAt = secondsToMS(turn?.startedAt);
  const completedAt = secondsToMS(turn?.completedAt);
  if (type === "userMessage") {
    return startedAt ?? completedAt;
  }
  return completedAt ?? startedAt;
}

function secondsToMS(value) {
  const number = Number(value);
  return Number.isFinite(number) ? Math.trunc(number * 1000) : null;
}

function sortRowsNewestFirst(rows) {
  return [...rows].sort((left, right) => {
    if (left.eventDateMS !== null && right.eventDateMS !== null && left.eventDateMS !== right.eventDateMS) {
      return right.eventDateMS - left.eventDateMS;
    }
    if (left.eventDateMS !== null && right.eventDateMS === null) {
      return -1;
    }
    if (left.eventDateMS === null && right.eventDateMS !== null) {
      return 1;
    }
    if (left.turnSequence !== right.turnSequence) {
      return left.turnSequence - right.turnSequence;
    }
    if (left.itemSequence !== right.itemSequence) {
      return right.itemSequence - left.itemSequence;
    }
    if (left.itemKey !== right.itemKey) {
      return left.itemKey < right.itemKey ? -1 : 1;
    }
    if (left.eventSequence !== right.eventSequence) {
      return right.eventSequence - left.eventSequence;
    }
    if (left.eventID !== right.eventID) {
      return left.eventID < right.eventID ? -1 : 1;
    }
    return left.rowOffset - right.rowOffset;
  });
}

function rowMatchesFilter(row, filter) {
  if (filter === "all") {
    return true;
  }
  if (filter === "messages") {
    return row.visibility === "request"
      || (row.visibility === "message" && (row.kind === "userMessage" || row.kind === "agentMessage"));
  }
  return row.kind === filter;
}

function filterCountsFromTurns(turns, visibleLimit) {
  const rawTypeCounts = new Map();
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

  let rawItemCount = 0;
  const rows = [];
  for (const [turnSequence, turn] of turns.entries()) {
    for (const [itemSequence, item] of (Array.isArray(turn?.items) ? turn.items : []).entries()) {
      rawItemCount += 1;
      increment(rawTypeCounts, item?.type || "unknown");
      for (const row of renderedRowsForItem(item, turn, turnSequence, itemSequence, rows.length)) {
        rows.push(row);
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
    }
  }

  const counts = Object.fromEntries(filterCounts);
  const visibleCounts = Object.fromEntries(
    Object.entries(counts).map(([filter, count]) => [filter, Math.min(count, visibleLimit)]),
  );
  const sortedRows = sortRowsNewestFirst(rows);
  const filters = [...filterCounts.keys()];
  const visibleEventIDs = Object.fromEntries(
    filters.map((filter) => [
      filter,
      sortedRows
        .filter((row) => rowMatchesFilter(row, filter))
        .slice(0, visibleLimit)
        .map((row) => row.eventID),
    ]),
  );
  return {
    turnCount: turns.length,
    pageLimited: false,
    rawItemCount,
    newestTurnID: turns[0]?.id || turns[0]?.turnId || turns[0]?.turnID || null,
    newestTurnCompletedAt: turns[0]?.completedAt ?? null,
    oldestTurnID: turns.at(-1)?.id || turns.at(-1)?.turnId || turns.at(-1)?.turnID || null,
    counts,
    visibleCounts,
    visibleEventIDs,
    rawTypeCounts: Object.fromEntries([...rawTypeCounts].sort()),
    rowKindCounts: Object.fromEntries([...rowKindCounts].sort()),
    visibilityCounts: Object.fromEntries([...visibilityCounts].sort()),
  };
}

async function sampleThread(client, options, index) {
  const sampledAt = new Date().toISOString();
  const dock = await readDockCard(client, options.threadID);
  const { pageCount, turns } = await readTurns(client, options.threadID);
  return {
    index,
    sampledAt,
    finishedAt: new Date().toISOString(),
    dock,
    turns: {
      pageCount,
      ...filterCountsFromTurns(turns, options.visibleLimit),
    },
  };
}

function summarizeSamples(samples) {
  const filters = ["messages", "all", "userMessage", "agentMessage", "command", "output", "request", "system", "unknown"];
  const filterSummary = {};
  for (const filter of filters) {
    const values = samples.map((sample) => sample.turns?.visibleCounts?.[filter]).filter((value) => value !== undefined);
    const visibleEventIDHeads = samples
      .map((sample) => sample.turns?.visibleEventIDs?.[filter]?.[0])
      .filter(Boolean);
    const visibleEventIDSequences = samples
      .map((sample) => sample.turns?.visibleEventIDs?.[filter])
      .filter((value) => Array.isArray(value) && value.length > 0)
      .map((value) => JSON.stringify(value));
    filterSummary[filter] = {
      first: values[0] ?? null,
      last: values.at(-1) ?? null,
      unique: [...new Set(values)],
      visibleEventIDHeadFirst: visibleEventIDHeads[0] ?? null,
      visibleEventIDHeadLast: visibleEventIDHeads.at(-1) ?? null,
      visibleEventIDHeadUnique: [...new Set(visibleEventIDHeads)],
      changed: new Set(values).size > 1 || new Set(visibleEventIDSequences).size > 1,
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
  filterCountsFromTurns,
  parseArgs,
  renderedRowsForItem,
  summarizeSamples,
  sortRowsNewestFirst,
  run,
};

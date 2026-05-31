import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { spawnSync } from "node:child_process";

const repoRoot = process.cwd();
const schemaPath = path.join(repoRoot, "contract/dock/dock-thread-card.schema.json");
const fixtureDir = path.join(repoRoot, "contract/dock/fixtures");

const forbiddenKeys = new Set([
  "messageSummary",
  "messageUpdatedAt",
  "sessions",
  "upsertSessions",
  "deleteSessionIDs",
]);

function readJSON(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function fail(message) {
  console.error(message);
  process.exitCode = 1;
}

function walk(value, visit) {
  if (Array.isArray(value)) {
    value.forEach((entry) => walk(entry, visit));
    return;
  }
  if (!value || typeof value !== "object") {
    return;
  }
  for (const [key, child] of Object.entries(value)) {
    visit(key, child);
    walk(child, visit);
  }
}

function requireObject(value, label) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    fail(`${label} must be an object`);
    return false;
  }
  return true;
}

function validateCard(card, label) {
  if (!requireObject(card, label)) {
    return;
  }
  for (const key of [
    "id",
    "logicalHostID",
    "threadID",
    "backendSessionID",
    "hostDisplayName",
    "orderKey",
    "activityAt",
    "displaySummary",
    "title",
    "status",
    "sourceKind",
    "lane",
    "archiveState",
    "freshness",
    "completeness",
  ]) {
    if (typeof card[key] !== "string" || card[key].trim() === "") {
      fail(`${label}.${key} must be a non-empty string`);
    }
  }
}

function validateStream(stream, filePath) {
  if (!requireObject(stream, filePath)) {
    return;
  }
  walk(stream, (key) => {
    if (forbiddenKeys.has(key)) {
      fail(`${path.relative(repoRoot, filePath)} contains forbidden legacy key ${key}`);
    }
  });
  if (stream.schemaVersion !== 2) {
    fail(`${path.relative(repoRoot, filePath)} schemaVersion must be 2`);
  }
  if (!["snapshot", "delta", "heartbeat"].includes(stream.kind)) {
    fail(`${path.relative(repoRoot, filePath)} has invalid kind ${stream.kind}`);
  }
  if (!["dock", "archive"].includes(stream.view)) {
    fail(`${path.relative(repoRoot, filePath)} has invalid view ${stream.view}`);
  }
  for (const [field, cards] of Object.entries({
    cards: stream.cards,
    upsertCards: stream.upsertCards,
  })) {
    if (cards === undefined) {
      continue;
    }
    if (!Array.isArray(cards)) {
      fail(`${path.relative(repoRoot, filePath)} ${field} must be an array`);
      continue;
    }
    cards.forEach((card, index) => validateCard(card, `${path.relative(repoRoot, filePath)}.${field}[${index}]`));
  }
}

const schema = readJSON(schemaPath);
if (schema?.properties?.schemaVersion?.const !== 2) {
  fail("contract schemaVersion const must be 2");
}

for (const entry of fs.readdirSync(fixtureDir).filter((name) => name.endsWith(".json")).sort()) {
  validateStream(readJSON(path.join(fixtureDir, entry)), path.join(fixtureDir, entry));
}

const generated = spawnSync(process.execPath, ["scripts/generate-dock-thread-card-contract.mjs", "--check"], {
  cwd: repoRoot,
  encoding: "utf8",
});
if (generated.status !== 0) {
  process.stderr.write(generated.stderr);
  process.stdout.write(generated.stdout);
  process.exitCode = 1;
}

if (process.exitCode) {
  process.exit(process.exitCode);
}
console.log("dock thread card contract fixtures and generated DTO are current");

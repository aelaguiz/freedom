import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { spawnSync } from "node:child_process";
import Ajv2020 from "ajv/dist/2020.js";

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

function validateStream(stream, filePath, validateSchema) {
  const relativePath = path.relative(repoRoot, filePath);
  if (!validateSchema(stream)) {
    for (const error of validateSchema.errors || []) {
      fail(`${relativePath} schema error ${error.instancePath || "/"} ${error.message}`);
    }
  }
  walk(stream, (key) => {
    if (forbiddenKeys.has(key)) {
      fail(`${relativePath} contains forbidden legacy key ${key}`);
    }
  });

  if (stream.complete === true && stream.freshness?.status !== "fresh") {
    fail(`${relativePath} complete streams must carry fresh stream freshness`);
  }

  for (const [field, cards] of Object.entries({
    cards: stream.cards,
    upsertCards: stream.upsertCards,
  })) {
    if (!Array.isArray(cards)) {
      continue;
    }
    cards.forEach((card, index) => {
      const label = `${relativePath}.${field}[${index}]`;
      if (card.completeness !== "complete" && card.freshness === "fresh") {
        fail(`${label} cannot be fresh when card completeness is ${card.completeness}`);
      }
      if (stream.complete === true && (card.completeness !== "complete" || card.freshness !== "fresh")) {
        fail(`${label} must be fresh and complete when stream complete is true`);
      }
    });
  }
}

const schema = readJSON(schemaPath);
if (schema?.properties?.schemaVersion?.const !== 2) {
  fail("contract schemaVersion const must be 2");
}

const ajv = new Ajv2020({ allErrors: true });
const validateSchema = ajv.compile(schema);

for (const entry of fs.readdirSync(fixtureDir).filter((name) => name.endsWith(".json")).sort()) {
  validateStream(readJSON(path.join(fixtureDir, entry)), path.join(fixtureDir, entry), validateSchema);
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

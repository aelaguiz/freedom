import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { spawnSync } from "node:child_process";
import Ajv2020 from "ajv/dist/2020.js";

const repoRoot = process.cwd();
const projectionContractDir = path.join(repoRoot, "contract/projection");
const schemaPath = path.join(projectionContractDir, "projection-thread-card-stream.schema.json");
const threadDetailSnapshotSchemaID = "https://codex-dock.local/contract/projection/thread-detail-snapshot.schema.json";
const threadCardStreamSchemaID = "https://codex-dock.local/contract/projection/projection-thread-card-stream.schema.json";
const projectionWitnessSchemaID = "https://codex-dock.local/contract/projection/projection-witness.schema.json";
const historicalDockSchemaPath = path.join(repoRoot, "contract/dock/dock-thread-card.schema.json");
const fixtureDir = path.join(projectionContractDir, "fixtures");
const projectionEnvelopeSchemaPath = path.join(projectionContractDir, "projection-envelope.schema.json");
const threadDetailRowSchemaPath = path.join(projectionContractDir, "payloads/thread-detail-row.schema.json");
const threadDetailSnapshotSchemaPath = path.join(projectionContractDir, "thread-detail-snapshot.schema.json");
const threadDetailUpdateSchemaPath = path.join(projectionContractDir, "thread-detail-update.schema.json");
const threadDetailDTOPath = path.join(repoRoot, "CodexDock/AppServer/ThreadDetailDTO.swift");
const dockThreadCardDTOPath = path.join(repoRoot, "CodexDock/AppServer/DockThreadCardDTO.swift");

const forbiddenKeys = new Set([
  "messageSummary",
  "messageUpdatedAt",
  "sessions",
  "upsertSessions",
  "deleteSessionIDs",
  "stateGeneration",
  "baseSeq",
  "hosts",
  "upsertHosts",
  "deleteHostIDs",
  "cards",
  "upsertCards",
  "deleteCardIDs",
]);

function readJSON(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function collectSchemaPaths(dirPath) {
  const entries = fs.readdirSync(dirPath, { withFileTypes: true });
  const paths = [];
  for (const entry of entries) {
    const entryPath = path.join(dirPath, entry.name);
    if (entry.isDirectory()) {
      paths.push(...collectSchemaPaths(entryPath));
    } else if (entry.name.endsWith(".schema.json")) {
      paths.push(entryPath);
    }
  }
  return paths.sort();
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
    rows: stream.rows,
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

function validateFixture(payload, filePath, validateSchema) {
  const relativePath = path.relative(repoRoot, filePath);
  if (!validateSchema(payload)) {
    for (const error of validateSchema.errors || []) {
      fail(`${relativePath} schema error ${error.instancePath || "/"} ${error.message}`);
    }
  }
  walk(payload, (key) => {
    if (forbiddenKeys.has(key)) {
      fail(`${relativePath} contains forbidden legacy key ${key}`);
    }
  });
}

function requiredProjectionRowFields() {
  const envelope = readJSON(projectionEnvelopeSchemaPath);
  const row = readJSON(threadDetailRowSchemaPath);
  const fields = new Set(envelope.required || []);
  const rowShape = (row.allOf || []).find((entry) => entry?.properties?.payload);
  for (const field of rowShape?.required || []) {
    fields.add(field);
  }
  fields.add("threadID");
  return [...fields].sort();
}

function requiredThreadDetailPayloadFields() {
  const row = readJSON(threadDetailRowSchemaPath);
  const rowShape = (row.allOf || []).find((entry) => entry?.properties?.payload);
  return [...(rowShape?.properties?.payload?.required || [])].sort();
}

function requiredObjectFields(filePath) {
  return [...(readJSON(filePath).required || [])].sort();
}

function swiftStructBlock(swift, structName) {
  const marker = `public struct ${structName}`;
  const start = swift.indexOf(marker);
  if (start === -1) {
    fail(`CodexDock/AppServer/ThreadDetailDTO.swift is missing ${marker}`);
    return "";
  }
  const next = swift.indexOf("\npublic struct ", start + marker.length);
  return next === -1 ? swift.slice(start) : swift.slice(start, next);
}

function assertSwiftStructFields({ swift, structName, requiredFields }) {
  const block = swiftStructBlock(swift, structName);
  for (const field of requiredFields) {
    const pattern = new RegExp(`public (?:let|var) ${field.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\b`);
    if (!pattern.test(block)) {
      fail(`CodexDock/AppServer/ThreadDetailDTO.swift ${structName} is missing required projection field ${field}`);
    }
  }
}

function assertSwiftStructNonOptionalFields({ swift, structName, requiredFields, swiftPath }) {
  const block = swiftStructBlock(swift, structName);
  for (const field of requiredFields) {
    const pattern = new RegExp(`public (?:let|var) ${field.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\s*:\\s*[^\\n?]+`);
    if (!pattern.test(block)) {
      fail(`${swiftPath} ${structName} must expose required projection field ${field} as non-optional`);
    }
  }
}

function validateThreadDetailSwiftDTO() {
  const swift = fs.readFileSync(threadDetailDTOPath, "utf8");
  assertSwiftStructFields({
    swift,
    structName: "ThreadDetailEventDTO",
    requiredFields: requiredProjectionRowFields(),
  });
  assertSwiftStructFields({
    swift,
    structName: "ThreadDetailEventPayloadDTO",
    requiredFields: requiredThreadDetailPayloadFields(),
  });
  assertSwiftStructFields({
    swift,
    structName: "ThreadDetailSnapshotDTO",
    requiredFields: requiredObjectFields(threadDetailSnapshotSchemaPath),
  });
  assertSwiftStructFields({
    swift,
    structName: "ThreadDetailUpdateDTO",
    requiredFields: requiredObjectFields(threadDetailUpdateSchemaPath),
  });

  const forbiddenSwiftDTOs = [
    "ThreadReadParams",
    "ThreadTurnsListParams",
    "ThreadTurnsListResponseDTO",
    "ThreadReadResponseDTO",
  ];
  for (const name of forbiddenSwiftDTOs) {
    if (swift.includes(`public struct ${name}`)) {
      fail(`CodexDock/AppServer/ThreadDetailDTO.swift still exposes retired raw detail DTO ${name}`);
    }
  }
}

function validateDockSwiftDTO() {
  const swift = fs.readFileSync(dockThreadCardDTOPath, "utf8");
  assertSwiftStructNonOptionalFields({
    swift,
    structName: "ThreadCardStreamUpdateDTO",
    requiredFields: requiredObjectFields(schemaPath),
    swiftPath: "CodexDock/AppServer/DockThreadCardDTO.swift",
  });
}

const schema = readJSON(schemaPath);
if (schema?.properties?.schemaVersion?.const !== 1) {
  fail("contract schemaVersion const must be 1");
}

const ajv = new Ajv2020({ allErrors: true });
for (const projectionSchemaPath of collectSchemaPaths(projectionContractDir)) {
  ajv.addSchema(readJSON(projectionSchemaPath));
}

const validateSchema = ajv.getSchema(threadCardStreamSchemaID);
const validateThreadDetailSnapshot = ajv.getSchema(threadDetailSnapshotSchemaID);
const validateProjectionWitness = ajv.getSchema(projectionWitnessSchemaID);
if (!validateSchema) {
  fail("projection thread card stream schema was not registered");
}
if (!validateThreadDetailSnapshot) {
  fail("thread detail projection snapshot schema was not registered");
}
if (!validateProjectionWitness) {
  fail("projection witness schema was not registered");
}

const historicalDockSchema = readJSON(historicalDockSchemaPath);
if (historicalDockSchema.$ref !== threadCardStreamSchemaID) {
  fail("contract/dock/dock-thread-card.schema.json must remain a compatibility pointer to the shared projection stream schema");
}
validateThreadDetailSwiftDTO();
validateDockSwiftDTO();

for (const entry of fs.readdirSync(fixtureDir).filter((name) => name.endsWith(".json")).sort()) {
  const fixturePath = path.join(fixtureDir, entry);
  const payload = readJSON(fixturePath);
  if (entry.startsWith("thread-card-stream-")) {
    validateStream(payload, fixturePath, validateSchema);
  } else if (entry.startsWith("thread-detail-snapshot")) {
    validateFixture(payload, fixturePath, validateThreadDetailSnapshot);
  } else if (entry.startsWith("projection-witness-")) {
    validateFixture(payload, fixturePath, validateProjectionWitness);
  } else {
    fail(`${path.relative(repoRoot, fixturePath)} is not assigned to a projection contract validator`);
  }
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
console.log("projection contract fixtures and generated Dock DTO are current");

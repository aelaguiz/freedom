import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import assert from "node:assert/strict";

const REPO_ROOT = path.resolve(import.meta.dirname, "..");
const COVERAGE_DOC = path.join(REPO_ROOT, "docs/CODEX_DOCK_TEST_SCENARIO_COVERAGE.md");
const FIXTURE_SCRIPT = path.join(REPO_ROOT, "scripts/dock-relay-controlled-simulator-fixture.mjs");
const MATRIX_SCRIPT = path.join(REPO_ROOT, "scripts/dock-relay-controlled-simulator-matrix.mjs");
const BUG_DOC_DIR = path.join(REPO_ROOT, "docs/bugs");

function readRepoFile(relativePath) {
  return fs.readFileSync(path.join(REPO_ROOT, relativePath), "utf8");
}

function markerBlock(source, name) {
  const start = `<!-- coverage:${name}:start -->`;
  const end = `<!-- coverage:${name}:end -->`;
  const startIndex = source.indexOf(start);
  const endIndex = source.indexOf(end);
  assert.notEqual(startIndex, -1, `missing ${start}`);
  assert.notEqual(endIndex, -1, `missing ${end}`);
  assert.ok(endIndex > startIndex, `${end} appears before ${start}`);
  return source.slice(startIndex + start.length, endIndex);
}

function backtickList(source) {
  return [...source.matchAll(/`([^`]+)`/g)].map((match) => match[1]).sort();
}

function arrayLiteralStrings(source, constName) {
  const pattern = new RegExp(`const\\s+${constName}\\s*=\\s*(?:new Set\\()?\\s*(\\[[\\s\\S]*?\\])\\s*\\)?\\s*;`);
  const match = source.match(pattern);
  assert.ok(match, `could not find ${constName}`);
  return [...match[1].matchAll(/"([^"]+)"/g)].map((item) => item[1]).sort();
}

function bugDocsOnDisk() {
  return fs.readdirSync(BUG_DOC_DIR)
    .filter((name) => name.endsWith(".md"))
    .filter((name) => !name.endsWith("_IMPLEMENTATION_LOG.md"))
    .filter((name) => !name.endsWith("_PLAN_AUDIT.md"))
    .filter((name) => !name.includes("-architecture-plan-"))
    .map((name) => `docs/bugs/${name}`)
    .sort();
}

function scenarioRows(coverageSource) {
  const rows = new Map();
  for (const line of coverageSource.split("\n")) {
    const match = line.match(/^\|\s*`([^`]+)`\s*\|\s*([^|]+)\|/);
    if (match) {
      rows.set(match[1], match[2].trim());
    }
  }
  return rows;
}

test("coverage ledger lists every supported controlled simulator scenario", () => {
  const coverage = readRepoFile("docs/CODEX_DOCK_TEST_SCENARIO_COVERAGE.md");
  const fixture = fs.readFileSync(FIXTURE_SCRIPT, "utf8");
  const supported = arrayLiteralStrings(fixture, "SUPPORTED_SCENARIOS");
  const listed = backtickList(markerBlock(coverage, "controlled-scenarios"));

  assert.deepEqual(listed, supported);
});

test("coverage ledger marks non-matrix controlled scenarios as fixture-only gaps", () => {
  const coverage = fs.readFileSync(COVERAGE_DOC, "utf8");
  const fixture = fs.readFileSync(FIXTURE_SCRIPT, "utf8");
  const matrix = fs.readFileSync(MATRIX_SCRIPT, "utf8");
  const supported = new Set(arrayLiteralStrings(fixture, "SUPPORTED_SCENARIOS"));
  const defaultMatrix = new Set(arrayLiteralStrings(matrix, "DEFAULT_REQUIRED_SCENARIOS"));
  const rows = scenarioRows(coverage);

  for (const scenario of defaultMatrix) {
    assert.ok(supported.has(scenario), `${scenario} is required by the default matrix but unsupported by the fixture`);
    assert.equal(rows.get(scenario), "current default matrix", `${scenario} must be marked current default matrix`);
  }

  const fixtureOnly = [...supported].filter((scenario) => !defaultMatrix.has(scenario)).sort();
  assert.ok(fixtureOnly.length > 0, "expected at least one fixture-only scenario to prove the guard is active");
  for (const scenario of fixtureOnly) {
    assert.equal(rows.get(scenario), "fixture-only-gap", `${scenario} must be marked fixture-only-gap`);
  }
});

test("coverage ledger lists every root bug doc", () => {
  const coverage = readRepoFile("docs/CODEX_DOCK_TEST_SCENARIO_COVERAGE.md");
  const listed = backtickList(markerBlock(coverage, "bug-docs"));

  assert.deepEqual(listed, bugDocsOnDisk());
});

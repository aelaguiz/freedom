import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import Ajv from "ajv";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, "..");
const PROOF_SCHEMA_DIR = path.join(REPO_ROOT, "contract", "proof");
const PROOF_FIELD_NAME_SCHEMA_FILE = "proof-field-name.schema.json";
const PROOF_ROUTE_NAME_SCHEMA_FILE = "proof-route-name.schema.json";
const SHARED_SCHEMA_FILES = [
  PROOF_FIELD_NAME_SCHEMA_FILE,
  PROOF_ROUTE_NAME_SCHEMA_FILE,
];

const KIND_TO_SCHEMA_FILE = new Map([
  ["codex-dock-relay-sync-audit-report", "relay-sync-audit.schema.json"],
  ["codex-dock-controlled-simulator-scenario-relay-report", "controlled-simulator-scenario-relay-report.schema.json"],
  ["codex-dock-simulator-ui-sync-proof", "simulator-ui-sync-proof.schema.json"],
  ["codex-dock-controlled-simulator-matrix-report", "controlled-simulator-matrix-report.schema.json"],
  ["codex-dock-sim-ui-dump", "sim-ui-dump.schema.json"],
]);

const PROOF_STATUS_VALUES = new Set(["pass", "fail", "blocked", "not_run"]);
const CLIENT_CARD_ROUTES = new Set([
  "dock/subscribe",
  "dock/update",
  "dock/resync",
  "archive/subscribe",
  "archive/update",
  "archive/resync",
  "thread/detail/subscribe",
  "thread/detail/resync",
  "thread/detail/update",
]);
const MANUAL_DIAGNOSTIC_ONLY_ROUTES = new Set([
  "thread/detail/read",
]);
const PASSING_PROOF_KINDS_REQUIRE_ROUTES = new Set([
  "codex-dock-relay-sync-audit-report",
  "codex-dock-controlled-simulator-scenario-relay-report",
  "codex-dock-simulator-ui-sync-proof",
]);

function loadJSON(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function loadSchemaFile(schemaFile) {
  return loadJSON(path.join(PROOF_SCHEMA_DIR, schemaFile));
}

function loadSchemaEnum(schemaFile) {
  const schema = loadSchemaFile(schemaFile);
  if (!Array.isArray(schema.enum)) {
    throw new Error(`${schemaFile} must expose an enum allow-list`);
  }
  return new Set(schema.enum);
}

const PROOF_FIELD_NAMES = loadSchemaEnum(PROOF_FIELD_NAME_SCHEMA_FILE);
const PROOF_ROUTE_NAMES = loadSchemaEnum(PROOF_ROUTE_NAME_SCHEMA_FILE);

function proofStatusForReport(report) {
  if (PROOF_STATUS_VALUES.has(report?.status)) {
    return report.status;
  }
  const ok = report?.summary?.ok;
  if (typeof ok === "boolean") {
    return ok ? "pass" : "fail";
  }
  return "blocked";
}

function finalizeProofReport(report) {
  report.status = proofStatusForReport(report);
  return report;
}

function loadProofSchemas() {
  const ajv = new Ajv({ allErrors: true, strict: true });
  for (const schemaFile of SHARED_SCHEMA_FILES) {
    ajv.addSchema(loadSchemaFile(schemaFile));
  }
  const validators = new Map();
  for (const [kind, schemaFile] of KIND_TO_SCHEMA_FILE.entries()) {
    const schema = loadSchemaFile(schemaFile);
    validators.set(kind, ajv.compile(schema));
  }
  return validators;
}

function collectStrings(value, strings = []) {
  if (typeof value === "string") {
    strings.push(value);
    return strings;
  }
  if (Array.isArray(value)) {
    for (const item of value) {
      collectStrings(item, strings);
    }
    return strings;
  }
  if (value && typeof value === "object") {
    for (const item of Object.values(value)) {
      collectStrings(item, strings);
    }
  }
  return strings;
}

function isAllowedProofObjectKey(key) {
  return PROOF_FIELD_NAMES.has(key) || PROOF_ROUTE_NAMES.has(key);
}

function collectUnknownProofKeys(value, path = "$", hits = []) {
  if (Array.isArray(value)) {
    value.forEach((item, index) => collectUnknownProofKeys(item, `${path}[${index}]`, hits));
    return hits;
  }
  if (!value || typeof value !== "object") {
    return hits;
  }
  for (const [key, child] of Object.entries(value)) {
    const childPath = `${path}.${key}`;
    if (!isAllowedProofObjectKey(key)) {
      hits.push(childPath);
    }
    collectUnknownProofKeys(child, childPath, hits);
  }
  return hits;
}

function routeSetFromReport(report) {
  const routes = new Set();
  for (const route of report?.clientPathEvidence?.routes || []) {
    routes.add(route);
  }
  for (const route of Object.keys(report?.clientPathEvidence?.routeCounts || {})) {
    routes.add(route);
  }
  for (const route of Object.keys(report?.summary?.clientPathRouteCounts || {})) {
    routes.add(route);
  }
  const relayRoutes = report?.relayReport?.clientPathRoutes
    || report?.relayReport?.clientPathEvidence?.routes
    || [];
  for (const route of relayRoutes) {
    routes.add(route);
  }
  for (const route of Object.keys(report?.relayReport?.routeCounts || {})) {
    routes.add(route);
  }
  return routes;
}

function semanticProofErrors(report) {
  const errors = [];
  const status = proofStatusForReport(report);
  if (report?.status !== status) {
    errors.push(`status must be ${status} for summary.ok=${String(report?.summary?.ok)}`);
  }
  if (status === "pass" && report?.summary?.ok === false) {
    errors.push("status pass cannot pair with summary.ok=false");
  }
  if (status === "fail" && report?.summary?.ok === true) {
    errors.push("status fail cannot pair with summary.ok=true");
  }
  for (const value of collectStrings(report)) {
    if (/^wss?:\/\/[^/]*:4500(?:\/|$)/u.test(value)) {
      errors.push(`raw app-server endpoint cannot satisfy proof: ${value}`);
    }
    if (value.includes("CODEX_DOCK_UI_DOCK_STREAM_SCENARIO")) {
      errors.push("scripted Dock stream scenario cannot satisfy live-update proof");
    }
  }
  const unknownKeyHits = collectUnknownProofKeys(report);
  if (unknownKeyHits.length > 0) {
    errors.push(`proof report contains fields outside the proof allow-list: ${unknownKeyHits.slice(0, 20).join(", ")}`);
  }
  const routes = routeSetFromReport(report);
  if (status === "pass" && PASSING_PROOF_KINDS_REQUIRE_ROUTES.has(report?.kind) && routes.size === 0) {
    errors.push("passing live-update proof must include relay-owned client route evidence");
  }
  if (status === "pass" && routes.size > 0) {
    const diagnosticOnlyRoutes = [...routes].filter((route) => MANUAL_DIAGNOSTIC_ONLY_ROUTES.has(route));
    if (diagnosticOnlyRoutes.length > 0) {
      errors.push(`manual diagnostic routes cannot satisfy live-update proof: ${diagnosticOnlyRoutes.join(", ")}`);
    }
    const hasClientCardRoute = [...routes].some((route) => CLIENT_CARD_ROUTES.has(route));
    if (!hasClientCardRoute) {
      errors.push("passing proof must include relay-owned Dock, Archive, or Thread Detail client routes");
    }
  }
  if (
    report?.kind === "codex-dock-simulator-ui-sync-proof"
    && report?.proofRunID
    && report?.relayReport?.proofRunID
    && report.proofRunID !== report.relayReport.proofRunID
  ) {
    errors.push("simulator UI proofRunID must match embedded relay proofRunID");
  }
  return errors;
}

function validateProofReport(report, {
  validators = loadProofSchemas(),
  sourcePath = "<report>",
} = {}) {
  const kind = report?.kind;
  const validate = validators.get(kind);
  const errors = [];
  if (!validate) {
    errors.push(`unsupported proof report kind ${kind || "missing"} at ${sourcePath}`);
    return errors;
  }
  if (!validate(report)) {
    for (const error of validate.errors || []) {
      errors.push(`${sourcePath}${error.instancePath || ""}: ${error.message}`);
    }
  }
  errors.push(...semanticProofErrors(report).map((message) => `${sourcePath}: ${message}`));
  return errors;
}

function assertProofReport(report, options = {}) {
  const errors = validateProofReport(report, options);
  if (errors.length) {
    throw new Error(`proof report contract failed:\n${errors.join("\n")}`);
  }
  return report;
}

function sampleProofReports() {
  return [
    {
      schemaVersion: 1,
      kind: "codex-dock-relay-sync-audit-report",
      status: "pass",
      mode: "soak",
      relayUrl: "ws://127.0.0.1:4510",
      startedAt: "2026-06-01T00:00:00Z",
      endedAt: "2026-06-01T00:00:01Z",
      summary: { ok: true, clientPathOK: true },
      clientPathEvidence: { routes: ["dock/subscribe"], routeCounts: { "dock/subscribe": 1 } },
      failures: [],
    },
    {
      schemaVersion: 1,
      kind: "codex-dock-controlled-simulator-scenario-relay-report",
      status: "pass",
      proofRunID: "sample-run",
      mode: "scenario",
      scenario: "archive-toggle",
      startedAt: "2026-06-01T00:00:00Z",
      endedAt: "2026-06-01T00:00:01Z",
      relayUrl: "ws://127.0.0.1:4510",
      summary: {
        ok: true,
        clientPathOK: true,
        scenario: "archive-toggle",
        scenarioOK: true,
        clientPathRouteCounts: { "dock/subscribe": 1 },
      },
      samples: [],
      scenarios: [{ id: "archive-toggle", ok: true }],
      clientPathEvidence: { routes: ["dock/subscribe"], routeCounts: { "dock/subscribe": 1 } },
      findings: [],
    },
    {
      schemaVersion: 1,
      kind: "codex-dock-simulator-ui-sync-proof",
      status: "pass",
      proofRunID: "sample-run",
      startedAt: "2026-06-01T00:00:00Z",
      endedAt: "2026-06-01T00:00:01Z",
      relayReport: {
        proofRunID: "sample-run",
        relayUrl: "ws://127.0.0.1:4510",
        clientPathOK: true,
        clientPathRoutes: ["dock/subscribe"],
      },
      summary: { ok: true, uiSampleCount: 1, relaySampleCount: 1, failures: 0 },
      evaluations: [],
      failures: [],
    },
    {
      schemaVersion: 1,
      kind: "codex-dock-controlled-simulator-matrix-report",
      status: "pass",
      generatedAt: "2026-06-01T00:00:00Z",
      config: { requiredScenarios: ["archive-toggle"], minPasses: 1, maxUiLagMs: 2000 },
      summary: {
        ok: true,
        reportCount: 1,
        requiredScenarioCount: 1,
        passingScenarioCount: 1,
        missingScenarioCount: 0,
        failedScenarioCount: 0,
        findings: 0,
      },
      scenarios: [],
      findings: [],
    },
    {
      schemaVersion: 1,
      kind: "codex-dock-sim-ui-dump",
      status: "pass",
      capturedAt: "2026-06-01T00:00:00Z",
      finishedAt: "2026-06-01T00:00:01Z",
      simulator: { name: "iPhone 17", udid: "sim-udid" },
      app: { bundleIdentifier: "com.aelaguiz.CodexDockApp", configuredBuildNumber: "202606020001" },
      launchMode: "activate",
      didRelaunch: false,
      stateBefore: "runningForeground",
      stateAfter: "runningForeground",
      screenBefore: "dock",
      screenAfter: "dock",
      visibleElements: [],
    },
  ];
}

export {
  KIND_TO_SCHEMA_FILE,
  PROOF_SCHEMA_DIR,
  assertProofReport,
  finalizeProofReport,
  loadProofSchemas,
  proofStatusForReport,
  sampleProofReports,
  validateProofReport,
};

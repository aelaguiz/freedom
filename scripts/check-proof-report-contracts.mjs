#!/usr/bin/env node
import fs from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import {
  assertProofReport,
  finalizeProofReport,
  loadProofSchemas,
  sampleProofReports,
  validateProofReport,
} from "./proof-report-contracts.mjs";

function usage() {
  return [
    "Usage:",
    "  node scripts/check-proof-report-contracts.mjs [report.json ...]",
    "",
    "With no report paths, compiles every proof schema and validates canonical samples.",
    "With report paths, validates each report against its schema and semantic guardrails.",
  ].join("\n");
}

function readReport(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function main(argv = process.argv.slice(2)) {
  if (argv.includes("--help") || argv.includes("-h")) {
    console.log(usage());
    return;
  }

  const validators = loadProofSchemas();
  const paths = argv.filter((arg) => !arg.startsWith("-"));
  if (!paths.length) {
    for (const report of sampleProofReports()) {
      assertProofReport(finalizeProofReport(report), {
        validators,
        sourcePath: `<sample:${report.kind}>`,
      });
    }
    console.log(`validated ${validators.size} proof schemas and ${sampleProofReports().length} canonical samples`);
    return;
  }

  const errors = [];
  for (const filePath of paths) {
    const report = readReport(filePath);
    errors.push(...validateProofReport(report, { validators, sourcePath: filePath }));
  }
  if (errors.length) {
    throw new Error(errors.join("\n"));
  }
  console.log(`validated ${paths.length} proof reports`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    main();
  } catch (error) {
    console.error(`proof report contract check failed: ${error.message || error}`);
    process.exit(1);
  }
}

export {
  main,
};

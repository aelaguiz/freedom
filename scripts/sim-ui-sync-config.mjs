#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import process from "node:process";

function usage() {
  return [
    "Usage:",
    "  node scripts/sim-ui-sync-config.mjs annotate --path <config.json> --simulator-udid <udid> --app-bundle-id <bundle-id> [--app-data-container <path>]",
  ].join("\n");
}

function parseArgs(argv) {
  const [command, ...rest] = argv;
  const args = {};
  for (let index = 0; index < rest.length; index += 1) {
    const name = rest[index];
    if (!name.startsWith("--")) {
      throw new Error(`unexpected argument: ${name}`);
    }
    const key = name.slice(2);
    const value = rest[index + 1];
    if (value === undefined || value.startsWith("--")) {
      throw new Error(`${name} requires a value`);
    }
    args[key] = value;
    index += 1;
  }
  return { command, args };
}

function requireArg(args, key) {
  const value = args[key];
  if (value === undefined || value === "") {
    throw new Error(`--${key} is required`);
  }
  return value;
}

function writeJSONAtomic(outputPath, value) {
  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  const tmpPath = path.join(path.dirname(outputPath), `.sim-ui-sync-config.${process.pid}.${Date.now()}.tmp`);
  fs.writeFileSync(tmpPath, `${JSON.stringify(value)}\n`, { mode: 0o600 });
  fs.renameSync(tmpPath, outputPath);
}

function annotate(args) {
  const configPath = requireArg(args, "path");
  const config = JSON.parse(fs.readFileSync(configPath, "utf8"));
  config.simulatorUDID = requireArg(args, "simulator-udid");
  config.appBundleID = requireArg(args, "app-bundle-id");
  const appDataContainer = String(args["app-data-container"] ?? "").trim();
  if (appDataContainer) {
    config.appDataContainer = appDataContainer;
  } else {
    delete config.appDataContainer;
  }
  writeJSONAtomic(configPath, config);
}

function main(argv = process.argv.slice(2), io = { stdout: process.stdout, stderr: process.stderr }) {
  try {
    const { command, args } = parseArgs(argv);
    if (command === "annotate") {
      annotate(args);
      return 0;
    }
    if (command === "--help" || command === "-h") {
      io.stdout.write(`${usage()}\n`);
      return 0;
    }
    throw new Error(`unknown command: ${command ?? ""}`);
  } catch (error) {
    io.stderr.write(`${error.message}\n\n${usage()}\n`);
    return 1;
  }
}

const exitCode = main();
if (exitCode !== 0) {
  process.exit(exitCode);
}

#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import process from "node:process";

import { parseEnvText } from "./codex-dock-host-service-env.mjs";

const APP_CONFIG_SECRET_KEY_PATTERN = /(OPENAI_API_KEY|TOKEN|SECRET|BEARER|PASSWORD|COOKIE|SESSION)/i;

function normalizeRelayInstanceID(value) {
  const trimmed = String(value ?? "").trim();
  return trimmed || null;
}

function parseEndpoint(text) {
  const value = String(text ?? "").trim();
  if (!value) {
    throw new Error("relay endpoint must not be empty");
  }
  if (value.includes("://") || /[/?#@\s]/.test(value)) {
    throw new Error(`relay endpoint must be host:port with no scheme, path, query, username, or password: ${value}`);
  }

  let host;
  let portText;
  if (value.startsWith("[")) {
    const closeIndex = value.indexOf("]");
    if (closeIndex === -1 || value[closeIndex + 1] !== ":") {
      throw new Error(`relay endpoint must be host:port: ${value}`);
    }
    host = value.slice(1, closeIndex);
    portText = value.slice(closeIndex + 2);
  } else {
    const separator = value.lastIndexOf(":");
    if (separator <= 0 || separator === value.length - 1 || value.indexOf(":") !== separator) {
      throw new Error(`relay endpoint must be host:port: ${value}`);
    }
    host = value.slice(0, separator);
    portText = value.slice(separator + 1);
  }

  const port = Number(portText);
  if (!Number.isInteger(port) || port <= 0 || port > 65_535) {
    throw new Error(`relay endpoint port must be an integer from 1 to 65535: ${portText}`);
  }
  if (port === 4500) {
    throw new Error(`relay endpoint must point at the Dock relay on :4510, not the raw Codex app-server on :4500: ${value}`);
  }
  return { host, port };
}

function parseEndpointList(rawValue) {
  const seen = new Set();
  const endpoints = [];
  for (const item of String(rawValue ?? "").split(",")) {
    if (!item.trim()) {
      continue;
    }
    const endpoint = parseEndpoint(item);
    const key = `${endpoint.host}:${endpoint.port}`;
    if (seen.has(key)) {
      throw new Error(`relay endpoint list must not contain duplicates: ${key}`);
    }
    seen.add(key);
    endpoints.push(endpoint);
  }
  if (endpoints.length === 0) {
    throw new Error("no relay endpoints resolved");
  }
  return endpoints;
}

function buildRelayConfig({ endpoints, relayInstanceID }) {
  const config = {
    endpoints: parseEndpointList(endpoints),
  };
  const normalizedRelayInstanceID = normalizeRelayInstanceID(relayInstanceID);
  if (normalizedRelayInstanceID) {
    config.relayInstanceID = normalizedRelayInstanceID;
  }
  return config;
}

function assertRelayConfigMatches(actual, expected) {
  const normalizedActual = {
    endpoints: Array.isArray(actual?.endpoints)
      ? actual.endpoints.map((endpoint) => ({
        host: String(endpoint?.host ?? ""),
        port: Number(endpoint?.port),
      }))
      : null,
    relayInstanceID: normalizeRelayInstanceID(actual?.relayInstanceID),
  };
  const normalizedExpected = {
    endpoints: expected.endpoints,
    relayInstanceID: normalizeRelayInstanceID(expected.relayInstanceID),
  };
  if (JSON.stringify(normalizedActual) !== JSON.stringify(normalizedExpected)) {
    throw new Error(`expected ${JSON.stringify(normalizedExpected)} got ${JSON.stringify(normalizedActual)}`);
  }
}

function buildRelayConfigFromHostEnv(text) {
  const values = parseEnvText(text);
  for (const key of Object.keys(values)) {
    if (APP_CONFIG_SECRET_KEY_PATTERN.test(key)) {
      throw new Error(`app-facing host env must not contain secret-looking key: ${key}`);
    }
  }
  if (!values.CODEX_DOCK_HOSTS) {
    throw new Error("app-facing host env is missing CODEX_DOCK_HOSTS");
  }
  if (!values.CODEX_DOCK_RELAY_INSTANCE_ID) {
    throw new Error("app-facing host env is missing CODEX_DOCK_RELAY_INSTANCE_ID");
  }
  return buildRelayConfig({
    endpoints: values.CODEX_DOCK_HOSTS,
    relayInstanceID: values.CODEX_DOCK_RELAY_INSTANCE_ID,
  });
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

function writeConfig(outputPath, config) {
  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  const tmpPath = path.join(path.dirname(outputPath), `.relay-config.${process.pid}.${Date.now()}.tmp`);
  fs.writeFileSync(tmpPath, `${JSON.stringify(config)}\n`, { mode: 0o600 });
  fs.renameSync(tmpPath, outputPath);
}

function main(argv = process.argv.slice(2), io = { stdout: process.stdout }) {
  const { command, args } = parseArgs(argv);
  if (command === "write") {
    const output = requireArg(args, "output");
    const config = buildRelayConfig({
      endpoints: requireArg(args, "endpoints"),
      relayInstanceID: args["relay-instance-id"],
    });
    writeConfig(output, config);
    io.stdout.write(`wrote ${output}\n`);
    return 0;
  }
  if (command === "verify") {
    const input = requireArg(args, "input");
    const expected = buildRelayConfig({
      endpoints: requireArg(args, "endpoints"),
      relayInstanceID: args["relay-instance-id"],
    });
    const actual = JSON.parse(fs.readFileSync(input, "utf8"));
    assertRelayConfigMatches(actual, expected);
    io.stdout.write(`verified ${input}\n`);
    return 0;
  }
  if (command === "verify-env") {
    const input = requireArg(args, "input");
    const expected = buildRelayConfig({
      endpoints: requireArg(args, "endpoints"),
      relayInstanceID: requireArg(args, "relay-instance-id"),
    });
    const actual = buildRelayConfigFromHostEnv(fs.readFileSync(input, "utf8"));
    assertRelayConfigMatches(actual, expected);
    io.stdout.write(`verified ${input}\n`);
    return 0;
  }
  throw new Error("command must be write, verify, or verify-env");
}

if (process.argv[1] && path.resolve(process.argv[1]) === path.resolve(new URL(import.meta.url).pathname)) {
  main();
}

export {
  assertRelayConfigMatches,
  buildRelayConfigFromHostEnv,
  buildRelayConfig,
  main,
  parseEndpoint,
  parseEndpointList,
};

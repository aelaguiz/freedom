#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import process from "node:process";

import { parseEnvText } from "./codex-dock-host-service-env.mjs";
import {
  DOCK_RELAY_PORT,
  MAX_TCP_PORT,
  RAW_APP_SERVER_PORT,
} from "./dock-relay-constants.mjs";

const APP_CONFIG_SECRET_KEY_PATTERN = /(OPENAI_API_KEY|TOKEN|SECRET|BEARER|PASSWORD|COOKIE|SESSION)/i;
const APP_CONFIG_FORBIDDEN_KEYS = new Set([
  "CODEX_DOCK_RELAY_INSTANCE_ID",
]);

function parseHost(text) {
  const value = String(text ?? "").trim();
  if (!value) {
    throw new Error("relay host must not be empty");
  }
  if (value.includes("://") || /[/?#@\s]/.test(value)) {
    throw new Error(`relay host must be host:port with no scheme, path, query, username, or password: ${value}`);
  }

  let host;
  let portText;
  if (value.startsWith("[")) {
    const closeIndex = value.indexOf("]");
    if (closeIndex === -1 || value[closeIndex + 1] !== ":") {
      throw new Error(`relay host must be host:port: ${value}`);
    }
    host = value.slice(1, closeIndex);
    portText = value.slice(closeIndex + 2);
  } else {
    const separator = value.lastIndexOf(":");
    if (separator <= 0 || separator === value.length - 1 || value.indexOf(":") !== separator) {
      throw new Error(`relay host must be host:port: ${value}`);
    }
    host = value.slice(0, separator);
    portText = value.slice(separator + 1);
  }

  const port = Number(portText);
  if (!Number.isInteger(port) || port <= 0 || port > MAX_TCP_PORT) {
    throw new Error(`relay host port must be an integer from 1 to ${MAX_TCP_PORT}: ${portText}`);
  }
  if (port === RAW_APP_SERVER_PORT) {
    throw new Error(`relay host must point at the Dock relay on :${DOCK_RELAY_PORT}, not the raw Codex app-server on :${RAW_APP_SERVER_PORT}: ${value}`);
  }
  return { host, port };
}

function parseHostList(rawValue) {
  const seen = new Set();
  const hosts = [];
  for (const item of String(rawValue ?? "").split(",")) {
    if (!item.trim()) {
      continue;
    }
    const host = parseHost(item);
    const key = `${host.host}:${host.port}`;
    if (seen.has(key)) {
      throw new Error(`relay host list must not contain duplicates: ${key}`);
    }
    seen.add(key);
    hosts.push(host);
  }
  if (hosts.length === 0) {
    throw new Error("no relay hosts resolved");
  }
  return hosts;
}

function buildRelayConfig({ hosts }) {
  return {
    hosts: parseHostList(hosts),
  };
}

function assertObjectKeys(value, allowedKeys, name) {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new Error(`${name} must be a JSON object`);
  }
  const extras = Object.keys(value).filter((key) => !allowedKeys.includes(key)).sort();
  if (extras.length > 0) {
    throw new Error(`${name} must not contain unexpected key: ${extras[0]}`);
  }
}

function assertRelayConfigMatches(actual, expected) {
  assertObjectKeys(actual, ["hosts"], "relay config");
  if (!Array.isArray(actual.hosts)) {
    throw new Error("relay config hosts must be an array");
  }
  for (const [index, host] of actual.hosts.entries()) {
    assertObjectKeys(host, ["host", "port"], `relay config hosts[${index}]`);
  }
  const normalizedActual = {
    hosts: actual.hosts.map((host) => ({
      host: String(host?.host ?? ""),
      port: Number(host?.port),
    })),
  };
  const normalizedExpected = {
    hosts: expected.hosts,
  };
  if (JSON.stringify(normalizedActual) !== JSON.stringify(normalizedExpected)) {
    throw new Error(`expected ${JSON.stringify(normalizedExpected)} got ${JSON.stringify(normalizedActual)}`);
  }
}

function buildRelayConfigFromHostEnv(text) {
  const values = parseEnvText(text);
  for (const key of Object.keys(values)) {
    if (APP_CONFIG_FORBIDDEN_KEYS.has(key)) {
      throw new Error(`app-facing host env must not contain phone-side relay identity: ${key}`);
    }
    if (APP_CONFIG_SECRET_KEY_PATTERN.test(key)) {
      throw new Error(`app-facing host env must not contain secret-looking key: ${key}`);
    }
  }
  if (!values.CODEX_DOCK_HOSTS) {
    throw new Error("app-facing host env is missing CODEX_DOCK_HOSTS");
  }
  return buildRelayConfig({
    hosts: values.CODEX_DOCK_HOSTS,
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
      hosts: requireArg(args, "hosts"),
    });
    writeConfig(output, config);
    io.stdout.write(`wrote ${output}\n`);
    return 0;
  }
  if (command === "verify") {
    const input = requireArg(args, "input");
    const expected = buildRelayConfig({
      hosts: requireArg(args, "hosts"),
    });
    const actual = JSON.parse(fs.readFileSync(input, "utf8"));
    assertRelayConfigMatches(actual, expected);
    io.stdout.write(`verified ${input}\n`);
    return 0;
  }
  if (command === "verify-env") {
    const input = requireArg(args, "input");
    const expected = buildRelayConfig({
      hosts: requireArg(args, "hosts"),
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
  parseHost,
  parseHostList,
};

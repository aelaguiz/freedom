#!/usr/bin/env node

import fs from "node:fs";
import http from "node:http";
import https from "node:https";
import os from "node:os";
import path from "node:path";
import process from "node:process";

function parseArgs(argv) {
  const args = {};
  const positionals = [];
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (!arg.startsWith("--")) {
      positionals.push(arg);
      continue;
    }
    const key = arg.slice(2);
    const value = argv[index + 1];
    if (value === undefined || value.startsWith("--")) {
      throw new Error(`missing value for --${key}`);
    }
    args[key] = value;
    index += 1;
  }
  return { command: positionals[0], args };
}

function httpBaseForHost(host) {
  const value = String(host || "").trim();
  if (!value) {
    throw new Error("host must not be empty");
  }
  if (value.startsWith("http://") || value.startsWith("https://")) {
    const url = new URL(value);
    url.pathname = "";
    url.search = "";
    url.hash = "";
    url.username = "";
    url.password = "";
    return url.toString().replace(/\/$/, "");
  }
  if (value.startsWith("ws://") || value.startsWith("wss://")) {
    const url = new URL(value);
    url.protocol = url.protocol === "wss:" ? "https:" : "http:";
    url.pathname = "";
    url.search = "";
    url.hash = "";
    url.username = "";
    url.password = "";
    return url.toString().replace(/\/$/, "");
  }
  return `http://${value}`;
}

function getJSON(url, timeoutMs = 5_000) {
  const client = url.startsWith("https:") ? https : http;
  return new Promise((resolve, reject) => {
    const request = client.get(url, { timeout: timeoutMs }, (response) => {
      const chunks = [];
      response.on("data", (chunk) => chunks.push(chunk));
      response.on("end", () => {
        const text = Buffer.concat(chunks).toString("utf8");
        let body = null;
        try {
          body = text ? JSON.parse(text) : null;
        } catch {
          body = { parseError: true, text: text.slice(0, 200) };
        }
        resolve({
          ok: response.statusCode >= 200 && response.statusCode < 300,
          statusCode: response.statusCode,
          body,
        });
      });
    });
    request.on("timeout", () => {
      request.destroy(new Error(`timed out after ${timeoutMs}ms`));
    });
    request.on("error", reject);
  });
}

async function getJSONOrError(url) {
  try {
    return await getJSON(url);
  } catch (error) {
    return {
      ok: false,
      statusCode: null,
      error: error?.message || String(error),
    };
  }
}

function writeJSONAtomic(filename, value) {
  fs.mkdirSync(path.dirname(filename), { recursive: true });
  const temp = `${filename}.${process.pid}.${Date.now()}.tmp`;
  fs.writeFileSync(temp, `${JSON.stringify(value, null, 2)}\n`, "utf8");
  fs.renameSync(temp, filename);
}

async function relayBundle(args) {
  const host = args.host || args.url || `127.0.0.1:${args.port || 4510}`;
  const baseURL = httpBaseForHost(host);
  const [readyz, statusz, metricsz, routesz, syncz] = await Promise.all([
    getJSONOrError(`${baseURL}/readyz`),
    getJSONOrError(`${baseURL}/statusz`),
    getJSONOrError(`${baseURL}/metricsz`),
    getJSONOrError(`${baseURL}/routesz`),
    getJSONOrError(`${baseURL}/syncz`),
  ]);
  const output = args.output || path.join(
    "/tmp",
    "codex-client",
    `relay-debug-bundle-${new Date().toISOString().replace(/[-:.]/g, "").slice(0, 15)}Z.json`,
  );
  const result = {
    schema: "codexdock.relayDebugBundleFetch.v1",
    createdAt: new Date().toISOString(),
    host,
    baseURL,
    readyz,
    statusz,
    metricsz,
    routesz,
    syncz,
  };
  writeJSONAtomic(output, result);
  return {
    ok: readyz.ok && statusz.ok && metricsz.ok && routesz.ok && syncz.ok,
    output,
    host,
  };
}

async function relayHostCompare(args) {
  const hosts = String(args.hosts || "")
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean);
  if (hosts.length === 0) {
    throw new Error("--hosts host:port[,host:port...] is required");
  }
  const compared = [];
  for (const host of hosts) {
    const baseURL = httpBaseForHost(host);
    const [readyz, statusz, routesz, syncz] = await Promise.all([
      getJSONOrError(`${baseURL}/readyz`),
      getJSONOrError(`${baseURL}/statusz`),
      getJSONOrError(`${baseURL}/routesz`),
      getJSONOrError(`${baseURL}/syncz`),
    ]);
    compared.push({
      configuredHostID: host,
      baseURL,
      readyz,
      statusz,
      routesz,
      syncz,
      appCriticalFailures: statusz.body?.appCriticalFailures || [],
    });
  }
  const result = {
    schema: "codexdock.relayHostCompare.v1",
    createdAt: new Date().toISOString(),
    host: os.hostname(),
    hosts: compared,
    ok: compared.every((entry) => entry.readyz.ok && entry.statusz.ok && entry.routesz.ok && entry.appCriticalFailures.length === 0),
  };
  if (args.output) {
    writeJSONAtomic(args.output, result);
  }
  return result;
}

async function main(argv = process.argv.slice(2), io = { stdout: process.stdout, stderr: process.stderr }) {
  const { command, args } = parseArgs(argv);
  if (command === "relay-debug-bundle") {
    io.stdout.write(`${JSON.stringify(await relayBundle(args), null, 2)}\n`);
    return 0;
  }
  if (command === "relay-host-compare") {
    const result = await relayHostCompare(args);
    io.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
    return result.ok ? 0 : 1;
  }
  throw new Error("usage: dock-relay-diagnostics.mjs relay-debug-bundle|relay-host-compare");
}

if (process.argv[1] && path.resolve(process.argv[1]) === path.resolve(new URL(import.meta.url).pathname)) {
  main().then((code) => {
    process.exitCode = code;
  }).catch((error) => {
    process.stderr.write(`${error?.message || String(error)}\n`);
    process.exitCode = 2;
  });
}

export {
  httpBaseForHost,
  main,
  relayBundle,
  relayHostCompare,
};

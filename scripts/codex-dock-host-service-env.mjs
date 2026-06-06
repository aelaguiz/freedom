import path from "node:path";
import process from "node:process";

import {
  readTextIfExists,
  writeFileAtomic,
} from "./codex-dock-host-service-runtime.mjs";
import {
  DEFAULT_REALTIME_TRANSCRIPTION_DELAY,
  DEFAULT_REALTIME_TRANSCRIPTION_MODEL,
  DOCK_RELAY_PORT,
  RAW_APP_SERVER_PORT,
} from "./dock-relay-constants.mjs";

const APP_SECRET_ENV_PATTERN = /(OPENAI_API_KEY|TOKEN|SECRET|BEARER|PASSWORD|COOKIE|SESSION)/i;
const APP_SAFE_EXACT_ENV_KEYS = new Set([
  "CODEX_DOCK_HOSTS",
]);
const OLD_APP_CONFIG_HOST_ENV_PATTERN = /^CODEX_DOCK_HOST_[A-Z0-9_]+_(WS|APP_SERVER_WS|NAME|AUTH_MODE|TOKEN|BEARER_TOKEN|TOKEN_FILE|BEARER_TOKEN_FILE)$/;

function envLineValue(value, name) {
  const string = String(value ?? "");
  if (/[\r\n]/.test(string)) {
    throw new Error(`${name} must not contain line breaks`);
  }
  return string;
}

function unquoteEnvValue(value) {
  const trimmed = String(value ?? "").trim();
  if ((trimmed.startsWith('"') && trimmed.endsWith('"')) || (trimmed.startsWith("'") && trimmed.endsWith("'"))) {
    return trimmed.slice(1, -1);
  }
  return trimmed;
}

function parseEnvText(text) {
  const values = {};
  for (const rawLine of String(text || "").split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith("#")) {
      continue;
    }
    const withoutExport = line.startsWith("export ") ? line.slice("export ".length).trim() : line;
    const equalsIndex = withoutExport.indexOf("=");
    if (equalsIndex <= 0) {
      continue;
    }
    const key = withoutExport.slice(0, equalsIndex).trim();
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(key)) {
      continue;
    }
    values[key] = unquoteEnvValue(withoutExport.slice(equalsIndex + 1));
  }
  return values;
}

function readEnvFile(filePath) {
  return parseEnvText(readTextIfExists(filePath));
}

function firstNonEmpty(...values) {
  for (const value of values) {
    const trimmed = value === undefined || value === null ? "" : String(value).trim();
    if (trimmed) {
      return trimmed;
    }
  }
  return "";
}

function parseHostEntry(entry) {
  const trimmed = String(entry || "").trim();
  const match = trimmed.match(/^(?:([^:/?#@\s]+)|\[([^\]]+)\]):(\d+)$/);
  if (!match) {
    return null;
  }
  return {
    value: trimmed,
    host: match[1] || match[2],
    port: Number(match[3]),
  };
}

function assertAppFacingRelayHosts(hosts, name) {
  for (const host of hosts) {
    if (host.port === RAW_APP_SERVER_PORT) {
      throw new Error(`${name} must point at the Dock relay on :${DOCK_RELAY_PORT}, not the raw Codex app-server on :${RAW_APP_SERVER_PORT}: ${host.value}`);
    }
  }
}

function mergeHosts(value, host) {
  const hosts = String(value || "")
    .split(",")
    .map((entry) => entry.trim())
    .map(parseHostEntry)
    .filter((entry) => entry !== null);
  assertAppFacingRelayHosts(hosts, "CODEX_DOCK_HOSTS");
  if (!hosts.some((entry) => entry.value === host)) {
    const parsedHost = parseHostEntry(host);
    if (!parsedHost) {
      throw new Error(`relay host must be host:port: ${host}`);
    }
    assertAppFacingRelayHosts([parsedHost], "CODEX_DOCK_HOSTS");
    hosts.unshift(parsedHost);
  }
  return hosts.map((entry) => entry.value).join(",");
}

function serializeEnv(values, preferredOrder) {
  const keys = [
    ...preferredOrder.filter((key) => values[key] !== undefined),
    ...Object.keys(values).filter((key) => !preferredOrder.includes(key)).sort(),
  ];
  return `${keys.map((key) => `${key}=${envLineValue(values[key], key)}`).join("\n")}\n`;
}

function isAppSafeHostEnvKey(key) {
  if (APP_SECRET_ENV_PATTERN.test(key)) {
    return false;
  }
  return APP_SAFE_EXACT_ENV_KEYS.has(key);
}

function removeOldAppConfigEnv(values) {
  for (const key of Object.keys(values)) {
    if (
      key === "CODEX_DOCK_PHONE_REACHABLE_APP_SERVER_WS"
      || key === "CODEX_DOCK_APP_SERVER_WS"
      || key === "CODEX_DOCK_APP_SERVER_BEARER_TOKEN"
      || key === "CODEX_DOCK_APP_SERVER_BEARER_TOKEN_FILE"
      || key === "CODEX_DOCK_RELAY_INSTANCE_ID"
      || OLD_APP_CONFIG_HOST_ENV_PATTERN.test(key)
    ) {
      delete values[key];
    }
  }
}

function generatedServiceEnvValues(config, runtime = {}) {
  const runtimeEnv = runtime.env || process.env;
  const repoEnv = readEnvFile(path.join(config.cwd, ".env"));
  const existing = readEnvFile(config.relay.envFile);
  removeOldAppConfigEnv(existing);

  const values = { ...existing };
  values.CODEX_DOCK_HOSTS = mergeHosts(
    firstNonEmpty(runtimeEnv.CODEX_DOCK_HOSTS, existing.CODEX_DOCK_HOSTS),
    config.relay.appEndpoint.serialized,
  );
  values.CODEX_DOCK_REAL_HOST_ID = config.host.id;
  values.CODEX_DOCK_REAL_HOST_NAME = config.host.displayName;
  values.CODEX_DOCK_OPENAI_REALTIME_TRANSCRIPTION_MODEL = firstNonEmpty(
    runtimeEnv.CODEX_DOCK_OPENAI_REALTIME_TRANSCRIPTION_MODEL,
    existing.CODEX_DOCK_OPENAI_REALTIME_TRANSCRIPTION_MODEL,
    repoEnv.CODEX_DOCK_OPENAI_REALTIME_TRANSCRIPTION_MODEL,
    DEFAULT_REALTIME_TRANSCRIPTION_MODEL,
  );
  values.CODEX_DOCK_REALTIME_TRANSCRIPTION_DELAY = firstNonEmpty(
    runtimeEnv.CODEX_DOCK_REALTIME_TRANSCRIPTION_DELAY,
    existing.CODEX_DOCK_REALTIME_TRANSCRIPTION_DELAY,
    repoEnv.CODEX_DOCK_REALTIME_TRANSCRIPTION_DELAY,
    DEFAULT_REALTIME_TRANSCRIPTION_DELAY,
  );

  const openAIKey = firstNonEmpty(
    runtimeEnv.OPENAI_API_KEY,
    repoEnv.OPENAI_API_KEY,
    existing.OPENAI_API_KEY,
  );
  if (openAIKey) {
    values.OPENAI_API_KEY = openAIKey;
  } else {
    delete values.OPENAI_API_KEY;
  }

  return values;
}

function generatedHostEnvValues(config, serviceValues) {
  const existing = readEnvFile(config.relay.hostEnvFile);
  removeOldAppConfigEnv(existing);
  const values = {};
  for (const [key, value] of Object.entries(existing)) {
    if (isAppSafeHostEnvKey(key)) {
      values[key] = value;
    }
  }
  for (const [key, value] of Object.entries(serviceValues)) {
    if (isAppSafeHostEnvKey(key)) {
      values[key] = value;
    }
  }
  values.CODEX_DOCK_HOSTS = serviceValues.CODEX_DOCK_HOSTS;
  return values;
}

function assertGeneratedEnvTarget(config, filePath, name) {
  if (path.resolve(filePath) === path.resolve(config.cwd, ".env")) {
    throw new Error(`refusing to overwrite user-owned .env; set ${name} to a generated path under ${config.runtimeDir}`);
  }
}

function writeGeneratedEnvFiles(config, runtime = {}) {
  assertGeneratedEnvTarget(config, config.relay.envFile, "service env file");
  assertGeneratedEnvTarget(config, config.relay.hostEnvFile, "host env file");
  const serviceValues = generatedServiceEnvValues(config, runtime);
  const serviceOrder = [
    "CODEX_DOCK_HOSTS",
    "CODEX_DOCK_REAL_HOST_ID",
    "CODEX_DOCK_REAL_HOST_NAME",
    "CODEX_DOCK_OPENAI_REALTIME_TRANSCRIPTION_MODEL",
    "CODEX_DOCK_REALTIME_TRANSCRIPTION_DELAY",
    "OPENAI_API_KEY",
  ];
  writeFileAtomic(config.relay.envFile, serializeEnv(serviceValues, serviceOrder), 0o600);

  const hostValues = generatedHostEnvValues(config, serviceValues);
  const hostOrder = [
    "CODEX_DOCK_HOSTS",
  ];
  writeFileAtomic(config.relay.hostEnvFile, serializeEnv(hostValues, hostOrder), 0o600);

  return [
    { role: "relay-service-env", path: config.relay.envFile },
    { role: "app-host-env", path: config.relay.hostEnvFile },
  ];
}

export {
  envLineValue,
  parseEnvText,
  writeGeneratedEnvFiles,
};

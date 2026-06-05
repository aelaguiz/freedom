import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFile } from "node:child_process";
import { promisify } from "node:util";

import {
  APP_SERVER_REGISTRY_OPEN_SESSION_FILE_SCAN_LIMIT,
  RAW_APP_SERVER_PORT,
} from "./dock-relay-constants.mjs";
import { defaultRelayLogger } from "./dock-relay-logger.mjs";
import {
  transportForEndpointURL,
  unixSocketPathFromURL,
} from "./dock-relay-json-rpc-client.mjs";

const execFileAsync = promisify(execFile);
const DEFAULT_DAEMON_SOCKET_RELATIVE_PATH = "app-server-control/app-server-control.sock";
const CODEX_THREAD_ID_SOURCE = "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}";
const CODEX_THREAD_ID_PATTERN = new RegExp(`^${CODEX_THREAD_ID_SOURCE}$`, "iu");
const CODEX_SESSION_FILE_THREAD_ID_PATTERN = new RegExp(`(?:^|-)(${CODEX_THREAD_ID_SOURCE})\\.jsonl$`, "iu");

function stableID(parts) {
  return crypto.createHash("sha256").update(parts.filter(Boolean).join("\n")).digest("hex").slice(0, 16);
}

function defaultCodexHome() {
  return process.env.CODEX_HOME || path.join(os.homedir(), ".codex");
}

function daemonSocketPathForCodexHome(codexHome = defaultCodexHome()) {
  return path.join(codexHome, DEFAULT_DAEMON_SOCKET_RELATIVE_PATH);
}

function daemonUnixURLForCodexHome(codexHome = defaultCodexHome()) {
  return `unix://${daemonSocketPathForCodexHome(codexHome)}`;
}

function codexSessionsRoot(codexHome = defaultCodexHome()) {
  return path.join(codexHome, "sessions");
}

function pathIsInside(parentPath, childPath) {
  const relative = path.relative(path.resolve(parentPath), path.resolve(childPath));
  return relative === "" || (!relative.startsWith("..") && !path.isAbsolute(relative));
}

function threadIDFromCodexSessionPath(filePath, { codexHome = defaultCodexHome() } = {}) {
  const rawPath = String(filePath || "");
  if (!rawPath) {
    return null;
  }
  const match = path.basename(rawPath).match(CODEX_SESSION_FILE_THREAD_ID_PATTERN);
  if (!match) {
    return null;
  }
  if (!pathIsInside(codexSessionsRoot(codexHome), rawPath)) {
    return null;
  }
  return match[1];
}

function unixSocketPathForEndpointURL(value, codexHome = defaultCodexHome()) {
  const raw = String(value || "");
  if (raw === "unix://") {
    return daemonSocketPathForCodexHome(codexHome);
  }
  return unixSocketPathFromURL(raw);
}

function canonicalEndpointURL(value) {
  const raw = String(value || "");
  if (raw === "unix://") {
    return daemonUnixURLForCodexHome();
  }
  if (raw.startsWith("unix://") || raw.startsWith("stdio://")) {
    return raw;
  }
  try {
    const url = new URL(raw);
    url.username = "";
    url.password = "";
    url.hash = "";
    return url.toString();
  } catch {
    return raw;
  }
}

function endpointHost(value) {
  try {
    return new URL(value).hostname;
  } catch {
    return "";
  }
}

function endpointPort(value) {
  try {
    return Number(new URL(value).port || 0);
  } catch {
    return 0;
  }
}

function isLoopbackHost(host) {
  return host === "127.0.0.1" || host === "::1" || host === "localhost";
}

function isLoopbackWebSocketURL(value) {
  const transport = transportForEndpointURL(value);
  if (transport !== "ws" && transport !== "wss") {
    return false;
  }
  return isLoopbackHost(endpointHost(value));
}

function isDockOwnedRawEndpoint(endpoint) {
  if (endpoint?.dockOwnedRaw || endpoint?.dockOwned) {
    return true;
  }
  const port = endpointPort(endpoint?.url);
  const host = endpointHost(endpoint?.url);
  return port === RAW_APP_SERVER_PORT && isLoopbackHost(host);
}

function tokenizeCommandLine(command) {
  const tokens = [];
  let current = "";
  let quote = null;
  let escaping = false;
  for (const character of String(command || "")) {
    if (escaping) {
      current += character;
      escaping = false;
      continue;
    }
    if (character === "\\") {
      escaping = true;
      continue;
    }
    if (quote) {
      if (character === quote) {
        quote = null;
      } else {
        current += character;
      }
      continue;
    }
    if (character === "'" || character === "\"") {
      quote = character;
      continue;
    }
    if (/\s/u.test(character)) {
      if (current) {
        tokens.push(current);
        current = "";
      }
      continue;
    }
    current += character;
  }
  if (current) {
    tokens.push(current);
  }
  return tokens;
}

function argValue(tokens, name) {
  const prefix = `${name}=`;
  for (let index = 0; index < tokens.length; index += 1) {
    const token = tokens[index];
    if (token === name) {
      return tokens[index + 1] || null;
    }
    if (token.startsWith(prefix)) {
      return token.slice(prefix.length);
    }
  }
  return null;
}

function commandLooksLikeCodexAppServerCommand(command) {
  return /^\s*(?:\S+\s+){0,2}\S*codex\s+app-server(?:\s|$)/u.test(String(command || ""));
}

function processLooksLikeCodexAppServer(tokens, command) {
  if (command && !commandLooksLikeCodexAppServerCommand(command)) {
    return false;
  }
  const appServerIndex = tokens.indexOf("app-server");
  if (appServerIndex <= 0 || appServerIndex > 3) {
    return false;
  }
  return path.basename(tokens[appServerIndex - 1]) === "codex";
}

function codexExecutableIndex(tokens) {
  return tokens.findIndex((token, index) => (
    index <= 3
    && path.basename(String(token || "")) === "codex"
  ));
}

function processLooksLikeCodexRuntime(tokens) {
  const codexIndex = codexExecutableIndex(tokens);
  if (codexIndex < 0) {
    return false;
  }
  return !tokens.slice(codexIndex + 1).includes("app-server");
}

function activeCodexThreadIDFromTokens(tokens) {
  const codexIndex = codexExecutableIndex(tokens);
  if (codexIndex < 0) {
    return null;
  }
  const args = tokens.slice(codexIndex + 1);
  if (args.includes("app-server")) {
    return null;
  }
  for (let index = 0; index < args.length; index += 1) {
    const token = args[index];
    if (token === "resume") {
      const threadId = args.slice(index + 1).find((candidate) => CODEX_THREAD_ID_PATTERN.test(candidate));
      return threadId || null;
    }
    if (token === "--resume") {
      const threadId = args[index + 1];
      return CODEX_THREAD_ID_PATTERN.test(threadId || "") ? threadId : null;
    }
    if (token.startsWith("--resume=")) {
      const threadId = token.slice("--resume=".length);
      return CODEX_THREAD_ID_PATTERN.test(threadId) ? threadId : null;
    }
  }
  return null;
}

function openSessionThreadIDsFromProcessInfo(processInfo, { codexHome = defaultCodexHome() } = {}) {
  const threadIds = new Set();
  if (CODEX_THREAD_ID_PATTERN.test(String(processInfo.openSessionThreadID || ""))) {
    threadIds.add(String(processInfo.openSessionThreadID));
  }
  for (const threadId of processInfo.openSessionThreadIDs || []) {
    if (CODEX_THREAD_ID_PATTERN.test(String(threadId || ""))) {
      threadIds.add(String(threadId));
    }
  }
  const paths = [];
  if (processInfo.openSessionPath) {
    paths.push(processInfo.openSessionPath);
  }
  if (Array.isArray(processInfo.openSessionPaths)) {
    paths.push(...processInfo.openSessionPaths);
  }
  for (const filePath of paths) {
    const threadId = threadIDFromCodexSessionPath(filePath, { codexHome });
    if (threadId) {
      threadIds.add(threadId);
    }
  }
  return [...threadIds];
}

function readBearerTokenFile(tokenFilePath) {
  if (!tokenFilePath) {
    return null;
  }
  const token = fs.readFileSync(tokenFilePath, "utf8").trim();
  return token || null;
}

function normalizeAppServerEndpoint(input, defaults = {}) {
  const source = input?.source || defaults.source || "configured";
  const endpointType = input?.endpointType || defaults.endpointType || "live";
  const url = String(input?.url || "");
  const transport = input?.transport || transportForEndpointURL(url);
  const codexHome = input?.codexHome || defaults.codexHome || null;
  const canonicalURL = url === "unix://"
    ? daemonUnixURLForCodexHome(codexHome || defaultCodexHome())
    : canonicalEndpointURL(url);
  let socketPath = null;
  if (transport === "unix") {
    try {
      socketPath = unixSocketPathForEndpointURL(url, codexHome || defaultCodexHome());
    } catch {
      socketPath = null;
    }
  }
  const endpoint = {
    id: input?.id || stableID([endpointType, transport, canonicalURL, input?.bearerToken ? "auth" : "none"]),
    label: input?.label || `${source}:${endpointType}:${transport}`,
    source,
    endpointType,
    transport,
    url: canonicalURL,
    socketPath,
    bearerToken: input?.bearerToken || null,
    authSource: input?.authSource || (input?.bearerToken ? "token-file" : "none"),
    codexHome,
    pid: input?.pid ?? null,
    ppid: input?.ppid ?? null,
    userAgent: input?.userAgent || null,
    dockOwnedRaw: Boolean(input?.dockOwnedRaw || input?.dockOwned),
    discoveredAt: input?.discoveredAt || null,
    lastSeenAt: input?.lastSeenAt || null,
    lastOkAt: input?.lastOkAt || null,
    failure: input?.failure || null,
  };
  endpoint.dockOwnedRaw = isDockOwnedRawEndpoint(endpoint);
  return endpoint;
}

function codexRuntimeProcessesForOpenFileScan(processes) {
  return processes
    .filter((processInfo) => {
      const tokens = Array.isArray(processInfo.args)
        ? processInfo.args.map(String)
        : tokenizeCommandLine(processInfo.command || "");
      return processLooksLikeCodexRuntime(tokens);
    })
    .filter((processInfo) => Number.isInteger(processInfo.pid) && processInfo.pid > 0)
    .slice(0, APP_SERVER_REGISTRY_OPEN_SESSION_FILE_SCAN_LIMIT);
}

function parseLsofOpenSessionThreadIDs(stdout, { codexHome = defaultCodexHome() } = {}) {
  const byPid = new Map();
  let currentPid = null;
  for (const line of String(stdout || "").split(/\r?\n/u)) {
    if (!line) {
      continue;
    }
    if (line.startsWith("p")) {
      const pid = Number(line.slice(1));
      currentPid = Number.isInteger(pid) ? pid : null;
      continue;
    }
    if (!currentPid || !line.startsWith("n")) {
      continue;
    }
    const threadId = threadIDFromCodexSessionPath(line.slice(1), { codexHome });
    if (!threadId) {
      continue;
    }
    if (!byPid.has(currentPid)) {
      byPid.set(currentPid, new Set());
    }
    byPid.get(currentPid).add(threadId);
  }
  return byPid;
}

async function annotateOpenSessionThreadIDs(processes, {
  codexHome = defaultCodexHome(),
  logger = defaultRelayLogger,
} = {}) {
  const candidates = codexRuntimeProcessesForOpenFileScan(processes);
  if (candidates.length === 0) {
    return;
  }
  const pids = candidates.map((processInfo) => String(processInfo.pid));
  let stdout = "";
  try {
    ({ stdout } = await execFileAsync("lsof", ["-w", "-Fpn", "-p", pids.join(",")], {
      maxBuffer: 2 * 1024 * 1024,
    }));
  } catch (error) {
    stdout = typeof error?.stdout === "string" ? error.stdout : "";
    if (!stdout) {
      logger.debug?.("app_server_registry.open_session_scan_failed", {
        processCount: candidates.length,
        error: error?.message || String(error),
      });
      return;
    }
  }
  const byPid = parseLsofOpenSessionThreadIDs(stdout, { codexHome });
  for (const processInfo of candidates) {
    const threadIds = [...(byPid.get(processInfo.pid) || [])];
    if (threadIds.length === 0) {
      continue;
    }
    processInfo.openSessionThreadIDs = [
      ...new Set([
        ...(processInfo.openSessionThreadIDs || []),
        ...threadIds,
      ]),
    ];
  }
}

async function defaultProcessListProvider({ codexHome = defaultCodexHome(), logger = defaultRelayLogger } = {}) {
  const { stdout } = await execFileAsync("ps", ["-axo", "pid=,ppid=,command="], {
    maxBuffer: 1024 * 1024,
  });
  const processes = stdout
    .split(/\r?\n/u)
    .map((line) => {
      const match = line.match(/^\s*(\d+)\s+(\d+)\s+(.+)$/u);
      if (!match) {
        return null;
      }
      return {
        pid: Number(match[1]),
        ppid: Number(match[2]),
        command: match[3],
      };
    })
    .filter(Boolean);
  await annotateOpenSessionThreadIDs(processes, { codexHome, logger });
  return processes;
}

function discoverAppServerEndpointsFromProcesses(processes = [], {
  codexHome = defaultCodexHome(),
  logger = defaultRelayLogger,
} = {}) {
  const endpoints = [];
  const observations = [];
  const privateThreadOwnersById = new Map();
  for (const processInfo of processes) {
    const tokens = Array.isArray(processInfo.args)
      ? processInfo.args.map(String)
      : tokenizeCommandLine(processInfo.command || "");
    if (processLooksLikeCodexRuntime(tokens)) {
      const activeThreadId = activeCodexThreadIDFromTokens(tokens);
      if (activeThreadId) {
        privateThreadOwnersById.set(activeThreadId, {
          threadId: activeThreadId,
          source: "process",
          transport: "stdio",
          pid: processInfo.pid ?? null,
          ppid: processInfo.ppid ?? null,
          ownerKind: "codex-cli-resume",
        });
      }
      for (const openSessionThreadId of openSessionThreadIDsFromProcessInfo(processInfo, { codexHome })) {
        if (!privateThreadOwnersById.has(openSessionThreadId)) {
          privateThreadOwnersById.set(openSessionThreadId, {
            threadId: openSessionThreadId,
            source: "process",
            transport: "stdio",
            pid: processInfo.pid ?? null,
            ppid: processInfo.ppid ?? null,
            ownerKind: "codex-cli-session-file",
          });
        }
      }
    }
    if (!Array.isArray(processInfo.args) && !commandLooksLikeCodexAppServerCommand(processInfo.command || "")) {
      continue;
    }
    if (!processLooksLikeCodexAppServer(tokens, processInfo.command || "")) {
      continue;
    }
    const listen = argValue(tokens, "--listen") || "stdio://";
    const tokenFile = argValue(tokens, "--ws-token-file");
    let bearerToken = null;
    let authSource = "none";
    if (tokenFile) {
      authSource = "token-file";
      try {
        bearerToken = readBearerTokenFile(tokenFile);
      } catch (error) {
        logger.warn("app_server_registry.token_file_unreadable", {
          pid: processInfo.pid,
          tokenFile,
          error,
        });
      }
    }
    const transport = transportForEndpointURL(listen);
    const descriptor = {
      source: "process",
      endpointType: transport === "stdio" ? "private" : transport === "unix" ? "history" : "live",
      label: `codex-app-server:${processInfo.pid || "unknown"}`,
      url: listen,
      bearerToken,
      authSource,
      codexHome,
      pid: processInfo.pid ?? null,
      ppid: processInfo.ppid ?? null,
    };
    if (transport === "stdio") {
      observations.push(descriptor);
    } else {
      endpoints.push(descriptor);
    }
  }
  return {
    endpoints,
    observations,
    privateThreadOwners: [...privateThreadOwnersById.values()],
  };
}

function sanitizedEndpoint(endpoint) {
  return {
    id: endpoint.id,
    label: endpoint.label,
    source: endpoint.source,
    endpointType: endpoint.endpointType,
    transport: endpoint.transport,
    url: endpoint.transport === "unix" ? "unix://<socket>" : endpoint.url,
    host: endpointHost(endpoint.url) || undefined,
    port: endpointPort(endpoint.url) || undefined,
    pid: endpoint.pid,
    codexHome: endpoint.codexHome,
    authConfigured: Boolean(endpoint.bearerToken),
    authSource: endpoint.authSource,
    dockOwnedRaw: Boolean(endpoint.dockOwnedRaw),
    lastSeenAt: endpoint.lastSeenAt,
    lastOkAt: endpoint.lastOkAt,
    failure: endpoint.failure ? {
      reason: endpoint.failure.reason || "unknown",
      message: endpoint.failure.message || null,
    } : null,
  };
}

export {
  canonicalEndpointURL,
  daemonSocketPathForCodexHome,
  daemonUnixURLForCodexHome,
  defaultCodexHome,
  defaultProcessListProvider,
  discoverAppServerEndpointsFromProcesses,
  endpointHost,
  endpointPort,
  isLoopbackWebSocketURL,
  normalizeAppServerEndpoint,
  sanitizedEndpoint,
  stableID,
  tokenizeCommandLine,
};

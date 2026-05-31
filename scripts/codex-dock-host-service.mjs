#!/usr/bin/env node
import os from "node:os";
import path from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";
import {
  ensureDirectory,
  ensureTokenFile,
  getJSON,
  readTailTextIfExists,
  redactValue,
  runCommand,
  tailText,
  writeFileAtomic,
} from "./codex-dock-host-service-runtime.mjs";
import {
  envLineValue,
  writeGeneratedEnvFiles,
} from "./codex-dock-host-service-env.mjs";
import {
  DEFAULT_PHONE_AUTH,
  DEFAULT_RELAY_LISTEN_HOST,
  DOCK_RELAY_PORT as DEFAULT_RELAY_PORT,
  RAW_APP_SERVER_LISTEN as DEFAULT_RAW_APP_SERVER_LISTEN,
  RAW_APP_SERVER_PORT as DEFAULT_RAW_APP_SERVER_PORT,
} from "./dock-relay-constants.mjs";

const DEFAULT_RUNTIME_DIR = ".codex-dock";
const DEFAULT_APP_SERVER_LABEL = "com.aelaguiz.codex-dock.app-server";
const DEFAULT_RELAY_LABEL = "com.aelaguiz.codex-dock.relay";
const VALUE_OPTIONS = new Set([
  "app-server-label",
  "codex-home",
  "codex-bin",
  "command",
  "format",
  "host-env-file",
  "host-id",
  "host-name",
  "network-profile",
  "node-bin",
  "phone-auth",
  "platform",
  "public-host",
  "raw-app-server-listen",
  "raw-token-file",
  "relay-history-url",
  "relay-label",
  "relay-listen-host",
  "relay-port",
  "relay-public-url",
  "relay-script",
  "relay-state-db",
  "runtime-dir",
  "service-env-file",
]);
const BOOLEAN_OPTIONS = new Set(["help"]);
const COMMANDS = new Set(["app-config", "doctor", "install", "logs", "render", "restart", "start", "status", "stop"]);
function usage() {
  return `Usage:
  node scripts/codex-dock-host-service.mjs render --platform <macos|linux> [--format json|text]
  node scripts/codex-dock-host-service.mjs install --platform <macos|linux>
  node scripts/codex-dock-host-service.mjs start|stop|restart|status|logs|doctor
  node scripts/codex-dock-host-service.mjs app-config [--format json|env]

Commands:
  render      Render local-sensitive launchd/systemd service file contents without installing them.
  install     Write service files, create/reuse the raw app-server token, and enable services.
  start       Start already installed services.
  stop        Stop services.
  restart     Restart services.
  status      Inspect service manager state and local health endpoints.
  logs        Print redacted service logs.
  doctor      Print redacted service, health, and config diagnostics.
  app-config  Print non-secret app-facing host config.

Common options:
	  --host-id <id>
	  --host-name <name>
	  --runtime-dir <path>
	  --service-env-file <path>
	  --codex-bin <path>
	  --node-bin <path>
  --raw-app-server-listen <ws-url>
  --relay-listen-host <host>
  --relay-port <port>
  --relay-public-url <ws-url>
  --network-profile <lan|manual|simulator-local>
  --public-host <host>`;
}

function parseArgs(argv) {
  const args = {};
  const positionals = [];

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (!arg.startsWith("--")) {
      positionals.push(arg);
      continue;
    }

    const withoutPrefix = arg.slice(2);
    const equalsIndex = withoutPrefix.indexOf("=");
    if (equalsIndex !== -1) {
      const name = withoutPrefix.slice(0, equalsIndex);
      const value = withoutPrefix.slice(equalsIndex + 1);
      if (VALUE_OPTIONS.has(name) && value === "") {
        throw new Error(`--${name} requires a value`);
      }
      if (VALUE_OPTIONS.has(name)) {
        args[name] = value;
      } else if (BOOLEAN_OPTIONS.has(name)) {
        throw new Error(`--${name} does not take a value`);
      } else {
        throw new Error(`unknown option: --${name}`);
      }
      continue;
    }

    if (BOOLEAN_OPTIONS.has(withoutPrefix)) {
      args[withoutPrefix] = true;
      continue;
    }
    if (!VALUE_OPTIONS.has(withoutPrefix)) {
      throw new Error(`unknown option: --${withoutPrefix}`);
    }

    const next = argv[index + 1];
    if (next === undefined || next === "" || next.startsWith("--")) {
      throw new Error(`--${withoutPrefix} requires a value`);
    }
    args[withoutPrefix] = next;
    index += 1;
  }

  return { args, positionals };
}

function optionValue(options, dashedName, env, envName, fallback) {
  if (options[dashedName] !== undefined) {
    return options[dashedName];
  }
  if (envName && env[envName] !== undefined && env[envName] !== "") {
    return env[envName];
  }
  return fallback;
}

function normalizePlatform(platform) {
  if (platform === "darwin" || platform === "macos") {
    return "macos";
  }
  if (platform === "linux" || platform === "systemd" || platform === "systemd-user") {
    return "linux";
  }
  throw new Error(`unsupported platform: ${platform}`);
}

function serviceManagerForPlatform(platform) {
  return normalizePlatform(platform) === "macos" ? "launchd" : "systemd-user";
}

function ensureNumber(value, name) {
  const number = Number(value);
  if (!Number.isInteger(number) || number <= 0 || number > 65_535) {
    throw new Error(`${name} must be a TCP port number`);
  }
  return number;
}

function validateWebSocketURL(value, name, { cliListen = false } = {}) {
  let url;
  try {
    url = new URL(String(value));
  } catch {
    throw new Error(`${name} must be a valid ws:// or wss:// URL`);
  }

  if (url.protocol !== "ws:" && url.protocol !== "wss:") {
    throw new Error(`${name} must use ws:// or wss://`);
  }
  if (!url.hostname) {
    throw new Error(`${name} must include a host`);
  }
  if (url.username || url.password) {
    throw new Error(`${name} must not include username or password credentials`);
  }
  if (cliListen) {
    if (url.pathname !== "/" || url.search || url.hash) throw new Error(`${name} must be ws://IP:PORT without a path, query, or hash`);
    return `${url.protocol}//${url.host}`;
  }
  return url.toString();
}

function hostIDToEnvSuffix(hostID) {
  const suffix = String(hostID).trim().replace(/[^A-Za-z0-9]+/g, "_").replace(/^_+|_+$/g, "").toUpperCase();
  if (!suffix) {
    throw new Error("host ID must contain at least one alphanumeric character");
  }
  return suffix;
}

function resolveRelayPublicURL({
  networkProfile,
  relayPublicURL,
  publicHost,
  relayPort,
  env = process.env,
}) {
  if (relayPublicURL) {
    return validateWebSocketURL(relayPublicURL, "relay public URL");
  }

  switch (networkProfile) {
  case "manual":
    throw new Error("manual network profile requires --relay-public-url");
  case "simulator-local":
    return validateWebSocketURL(`ws://127.0.0.1:${relayPort}`, "relay public URL");
  case "lan": {
    const host = publicHost || env.APP_SERVER_HOST || os.hostname();
    return validateWebSocketURL(`ws://${host}:${relayPort}`, "relay public URL");
  }
  default:
    throw new Error(`unsupported network profile: ${networkProfile}`);
  }
}

function appEndpointFromWebSocketURL(webSocketURL) {
  const url = new URL(webSocketURL);
  if (!url.port) {
    throw new Error("relay public URL must include an explicit port");
  }
  if (Number(url.port) === DEFAULT_RAW_APP_SERVER_PORT) {
    throw new Error(`relay public URL must point at the Dock relay on :${DEFAULT_RELAY_PORT}, not the raw Codex app-server on :${DEFAULT_RAW_APP_SERVER_PORT}`);
  }
  const host = url.hostname.replace(/^\[(.*)\]$/, "$1");
  const serializedHost = host.includes(":") ? `[${host}]` : host;
  return {
    host,
    port: Number(url.port),
    serialized: `${serializedHost}:${url.port}`,
  };
}

function createHostServiceConfig({
  options = {},
  env = process.env,
  cwd = process.cwd(),
  platform = process.platform,
} = {}) {
  const normalizedPlatform = normalizePlatform(optionValue(options, "platform", env, null, platform));
  const relayPort = ensureNumber(optionValue(options, "relay-port", env, "DOCK_RELAY_PORT", DEFAULT_RELAY_PORT), "relay port");
  const runtimeDir = path.resolve(cwd, optionValue(options, "runtime-dir", env, "CODEX_DOCK_RUNTIME_DIR", DEFAULT_RUNTIME_DIR));
  const logsDir = path.join(runtimeDir, "logs");
  const servicesDir = path.join(runtimeDir, "services");
  const hostID = String(optionValue(options, "host-id", env, "CODEX_DOCK_REAL_HOST_ID", os.hostname())).trim();
  const hostName = String(optionValue(options, "host-name", env, "CODEX_DOCK_REAL_HOST_NAME", hostID)).trim();
  const codexHomeValue = optionValue(options, "codex-home", env, "CODEX_HOME", null);
  const codexHome = codexHomeValue ? path.resolve(cwd, String(codexHomeValue)) : null;
  const rawAppServerListen = validateWebSocketURL(
    optionValue(options, "raw-app-server-listen", env, "APP_SERVER_LISTEN", DEFAULT_RAW_APP_SERVER_LISTEN),
    "raw app-server listen URL",
    { cliListen: true },
  );
  const rawAppServerURL = new URL(rawAppServerListen);
  const rawAppServerPort = rawAppServerURL.port || DEFAULT_RAW_APP_SERVER_PORT;
  const relayHistoryURL = validateWebSocketURL(
    optionValue(options, "relay-history-url", env, "DOCK_RELAY_HISTORY_WS", `ws://127.0.0.1:${rawAppServerPort}`),
    "relay history URL",
  );
  const networkProfile = optionValue(options, "network-profile", env, "CODEX_DOCK_NETWORK_PROFILE", "lan");
  const relayPublicURL = resolveRelayPublicURL({
    networkProfile,
    relayPublicURL: optionValue(options, "relay-public-url", env, "DOCK_RELAY_WS", null),
    publicHost: optionValue(options, "public-host", env, null, null),
    relayPort,
    env,
  });
  const appEndpoint = appEndpointFromWebSocketURL(relayPublicURL);
  const phoneAuth = String(optionValue(options, "phone-auth", env, "CODEX_DOCK_RELAY_PHONE_AUTH", DEFAULT_PHONE_AUTH));
  if (!["none", "bearer"].includes(phoneAuth)) {
    throw new Error("phone auth must be none or bearer");
  }

  const appServerLabel = String(optionValue(options, "app-server-label", env, "APP_SERVER_LABEL", DEFAULT_APP_SERVER_LABEL));
  const relayLabel = String(optionValue(options, "relay-label", env, "DOCK_RELAY_LABEL", DEFAULT_RELAY_LABEL));
  const tokenFile = path.resolve(
    cwd,
    optionValue(options, "raw-token-file", env, "CODEX_DOCK_APP_SERVER_BEARER_TOKEN_FILE", path.join(runtimeDir, "app-server.token")),
  );
  const envFile = path.resolve(
    cwd,
    optionValue(options, "service-env-file", env, "CODEX_DOCK_SERVICE_ENV_FILE", path.join(runtimeDir, "service.env")),
  );
  const hostEnvFile = path.resolve(
    cwd,
    optionValue(options, "host-env-file", env, "CODEX_DOCK_HOST_ENV_FILE", path.join(runtimeDir, "host.env")),
  );
  const relayScript = path.resolve(cwd, optionValue(options, "relay-script", env, "CODEX_DOCK_RELAY_SCRIPT", "scripts/dock-relay.mjs"));
  const relayStateDatabasePath = path.resolve(
    cwd,
    optionValue(options, "relay-state-db", env, "CODEX_DOCK_RELAY_STATE_DB", path.join(runtimeDir, "relay-state.sqlite")),
  );

  return {
    version: 1,
    platform: normalizedPlatform,
    serviceManager: serviceManagerForPlatform(normalizedPlatform),
    host: {
      id: hostID,
      displayName: hostName,
      envSuffix: hostIDToEnvSuffix(hostID),
    },
    codexHome,
    cwd,
    runtimeDir,
    logsDir,
    servicesDir,
    binaries: {
      codex: optionValue(options, "codex-bin", env, "CODEX_BIN", "codex"),
      node: optionValue(options, "node-bin", env, "NODE_BIN", process.execPath),
    },
    appServer: {
      label: appServerLabel,
      listenURL: rawAppServerListen,
      tokenFile,
      stdoutLog: path.join(logsDir, "app-server.log"),
      stderrLog: path.join(logsDir, "app-server.err.log"),
      servicePath: normalizedPlatform === "macos"
        ? path.join(servicesDir, `${appServerLabel}.plist`)
        : path.join(servicesDir, "codex-dock-app-server.service"),
    },
    relay: {
      label: relayLabel,
      script: relayScript,
      listenHost: optionValue(options, "relay-listen-host", env, "DOCK_RELAY_LISTEN_HOST", DEFAULT_RELAY_LISTEN_HOST),
      port: relayPort,
      historyURL: relayHistoryURL,
      publicURL: relayPublicURL,
      appEndpoint,
      phoneAuth,
      stateDatabasePath: relayStateDatabasePath,
      envFile,
      hostEnvFile,
      stdoutLog: path.join(logsDir, "dock-relay.log"),
      stderrLog: path.join(logsDir, "dock-relay.err.log"),
      servicePath: normalizedPlatform === "macos"
        ? path.join(servicesDir, `${relayLabel}.plist`)
        : path.join(servicesDir, "codex-dock-relay.service"),
    },
    network: {
      profile: networkProfile,
      publicURL: relayPublicURL,
    },
  };
}

function xmlEscape(value) {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
}

function launchdPlist({ label, programArguments, workingDirectory, environment, stdoutPath, stderrPath }) {
  const argsXML = programArguments.map((arg) => `    <string>${xmlEscape(arg)}</string>`).join("\n");
  const envXML = Object.entries(environment)
    .map(([key, value]) => `    <key>${xmlEscape(key)}</key>\n    <string>${xmlEscape(value)}</string>`)
    .join("\n");

  return [
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
    "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">",
    "<plist version=\"1.0\">",
    "<dict>",
    "  <key>Label</key>",
    `  <string>${xmlEscape(label)}</string>`,
    "  <key>ProgramArguments</key>",
    "  <array>",
    argsXML,
    "  </array>",
    "  <key>WorkingDirectory</key>",
    `  <string>${xmlEscape(workingDirectory)}</string>`,
    "  <key>EnvironmentVariables</key>",
    "  <dict>",
    envXML,
    "  </dict>",
    "  <key>RunAtLoad</key>",
    "  <true/>",
    "  <key>KeepAlive</key>",
    "  <true/>",
    "  <key>StandardOutPath</key>",
    `  <string>${xmlEscape(stdoutPath)}</string>`,
    "  <key>StandardErrorPath</key>",
    `  <string>${xmlEscape(stderrPath)}</string>`,
    "</dict>",
    "</plist>",
    "",
  ].join("\n");
}

function systemdQuote(value) {
  const string = String(value);
  if (/^[A-Za-z0-9_@%+=:,./-]+$/.test(string)) {
    return string;
  }
  return `"${string.replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`;
}

function systemdUnit({
  description,
  after = [],
  programArguments,
  workingDirectory,
  environment,
  stdoutPath,
  stderrPath,
}) {
  const afterLine = after.length ? [`After=${after.join(" ")}`] : [];
  const environmentLines = Object.entries(environment)
    .map(([key, value]) => `Environment=${systemdQuote(`${key}=${value}`)}`);

  return [
    "[Unit]",
    `Description=${description}`,
    ...afterLine,
    "",
    "[Service]",
    `WorkingDirectory=${systemdQuote(workingDirectory)}`,
    ...environmentLines,
    `ExecStart=${programArguments.map(systemdQuote).join(" ")}`,
    "Restart=always",
    "RestartSec=2",
    `StandardOutput=append:${stdoutPath}`,
    `StandardError=append:${stderrPath}`,
    "",
    "[Install]",
    "WantedBy=default.target",
    "",
  ].join("\n");
}

function commonEnvironment(config = {}) {
  const environment = {
    HOME: os.homedir(),
    PATH: `${os.homedir()}/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin`,
  };
  if (config.codexHome) {
    environment.CODEX_HOME = config.codexHome;
  }
  return environment;
}

function appServerArgs(config) {
  return [
    config.binaries.codex,
    "app-server",
    "--listen",
    config.appServer.listenURL,
    "--ws-auth",
    "capability-token",
    "--ws-token-file",
    config.appServer.tokenFile,
  ];
}

function relayArgs(config) {
  return [
    config.binaries.node,
    config.relay.script,
    "--listen-host",
    config.relay.listenHost,
    "--port",
    String(config.relay.port),
    "--phone-auth",
    config.relay.phoneAuth,
    "--env-file",
    config.relay.envFile,
    "--bonjour-name",
    config.host.displayName,
    "--host-id",
    config.host.id,
    "--host-name",
    config.host.displayName,
    "--host-endpoint",
    config.relay.appEndpoint.serialized,
    "--relay-state-db",
    config.relay.stateDatabasePath,
    "--history-url",
    config.relay.historyURL,
    "--history-auth-token-file",
    config.appServer.tokenFile,
  ];
}

function renderHostServices(config) {
  const environment = commonEnvironment(config);
  if (config.platform === "macos") {
    return [
      {
        role: "raw-app-server",
        serviceManager: "launchd",
        path: config.appServer.servicePath,
        contents: launchdPlist({
          label: config.appServer.label,
          programArguments: appServerArgs(config),
          workingDirectory: config.cwd,
          environment,
          stdoutPath: config.appServer.stdoutLog,
          stderrPath: config.appServer.stderrLog,
        }),
      },
      {
        role: "dock-relay",
        serviceManager: "launchd",
        path: config.relay.servicePath,
        contents: launchdPlist({
          label: config.relay.label,
          programArguments: relayArgs(config),
          workingDirectory: config.cwd,
          environment,
          stdoutPath: config.relay.stdoutLog,
          stderrPath: config.relay.stderrLog,
        }),
      },
    ];
  }

  return [
    {
      role: "raw-app-server",
      serviceManager: "systemd-user",
      path: config.appServer.servicePath,
      contents: systemdUnit({
        description: "Codex Dock raw app-server",
        programArguments: appServerArgs(config),
        workingDirectory: config.cwd,
        environment,
        stdoutPath: config.appServer.stdoutLog,
        stderrPath: config.appServer.stderrLog,
      }),
    },
    {
      role: "dock-relay",
      serviceManager: "systemd-user",
      path: config.relay.servicePath,
      contents: systemdUnit({
        description: "Codex Dock relay",
        after: ["codex-dock-app-server.service"],
        programArguments: relayArgs(config),
        workingDirectory: config.cwd,
        environment,
        stdoutPath: config.relay.stdoutLog,
        stderrPath: config.relay.stderrLog,
      }),
    },
  ];
}

function serviceEntries(config) {
  return [
    {
      role: "raw-app-server",
      label: config.appServer.label,
      unit: "codex-dock-app-server.service",
      path: config.appServer.servicePath,
      stdoutLog: config.appServer.stdoutLog,
      stderrLog: config.appServer.stderrLog,
    },
    {
      role: "dock-relay",
      label: config.relay.label,
      unit: "codex-dock-relay.service",
      path: config.relay.servicePath,
      stdoutLog: config.relay.stdoutLog,
      stderrLog: config.relay.stderrLog,
    },
  ];
}

function appConfigJSON(config) {
  return {
    version: 1,
    hosts: [
      {
        host: config.relay.appEndpoint.host,
        port: config.relay.appEndpoint.port,
      },
    ],
  };
}

function appConfigEnv(config) {
  return [
    `CODEX_DOCK_HOSTS=${envLineValue(config.relay.appEndpoint.serialized, "relay host")}`,
    "",
  ].join("\n");
}

function dryRunStatus(config) {
  return {
    version: 1,
    status: "not-installed",
    checked: false,
    reason: "Phase 1A dry-run renderer does not inspect or mutate launchd/systemd state.",
    host: {
      id: config.host.id,
      displayName: config.host.displayName,
    },
    serviceManager: config.serviceManager,
    appEndpoint: {
      host: config.relay.appEndpoint.host,
      port: config.relay.appEndpoint.port,
    },
    renderedServices: [
      {
        role: "raw-app-server",
        serviceManager: config.serviceManager,
        path: config.appServer.servicePath,
      },
      {
        role: "dock-relay",
        serviceManager: config.serviceManager,
        path: config.relay.servicePath,
      },
    ],
  };
}

function commandRunner(runtime = {}) {
  return runtime.runCommand || runCommand;
}

function runtimeUID(runtime = {}) {
  return runtime.uid ?? process.getuid?.() ?? 0;
}

function serviceTarget(config, service, runtime = {}) {
  if (config.platform === "macos") {
    return `gui/${runtimeUID(runtime)}/${service.label}`;
  }
  return service.unit;
}

function launchdDomain(runtime = {}) {
  return `gui/${runtimeUID(runtime)}`;
}

function serviceCommandOptions(config, runtime = {}) {
  return { cwd: config.cwd, env: serviceCommandEnv(runtime) };
}

function localRelayHTTPURL(config, pathname) {
  return `http://127.0.0.1:${config.relay.port}${pathname}`;
}

function httpURLForWebSocket(webSocketURL, pathname) {
  const url = new URL(webSocketURL);
  url.protocol = url.protocol === "wss:" ? "https:" : "http:";
  url.pathname = pathname;
  url.search = "";
  url.hash = "";
  url.username = "";
  url.password = "";
  return url.toString();
}

async function runServiceCommand(config, runtime, command, args, { allowFailure = false } = {}) {
  const result = await commandRunner(runtime)(command, args, serviceCommandOptions(config, runtime));
  if (!allowFailure && result.exitCode !== 0) {
    const redactedArgs = redactValue(args).join(" ");
    const error = new Error(`${redactValue(command)} ${redactedArgs} failed with exit ${result.exitCode}`);
    error.result = redactValue(result);
    throw error;
  }
  return {
    command,
    args,
    exitCode: result.exitCode,
  };
}

async function inspectLaunchdService(config, runtime, service) {
  return commandRunner(runtime)("launchctl", ["print", serviceTarget(config, service, runtime)], serviceCommandOptions(config, runtime));
}

function launchdPrintShowsReusablePath(result, servicePath) {
  return result.exitCode === 0 && String(result.stdout || "").includes(`path = ${servicePath}`) && String(result.stdout || "").includes("state = running");
}

function delay(runtime = {}, ms = 1000) {
  return runtime.sleep ? runtime.sleep(ms) : new Promise((resolve) => setTimeout(resolve, ms));
}

function serviceCommandEnv(runtime = {}) {
  const requested = runtime.commandEnv || {};
  const defaults = commonEnvironment();
  const env = { HOME: requested.HOME || defaults.HOME, PATH: requested.PATH || defaults.PATH, LANG: requested.LANG || process.env.LANG || "C.UTF-8" };
  for (const key of ["XDG_RUNTIME_DIR", "DBUS_SESSION_BUS_ADDRESS"]) {
    const value = requested[key] || process.env[key];
    if (value) env[key] = value;
  }
  return env;
}

async function bootstrapLaunchdService(config, runtime, domain, servicePath) {
  const first = await runServiceCommand(config, runtime, "launchctl", ["bootstrap", domain, servicePath], { allowFailure: true });
  if (first.exitCode === 0) {
    return [first];
  }
  await delay(runtime);
  return [first, await runServiceCommand(config, runtime, "launchctl", ["bootstrap", domain, servicePath])];
}

async function runServiceManagerAction(config, action, runtime = {}) {
  const services = serviceEntries(config);
  const commands = [];
  if (config.platform === "macos") {
    const domain = launchdDomain(runtime);
    if (action === "install") {
      for (const service of services) {
        const current = await inspectLaunchdService(config, runtime, service);
        commands.push({ command: "launchctl", args: ["print", serviceTarget(config, service, runtime)], exitCode: current.exitCode });
        if (launchdPrintShowsReusablePath(current, service.path)) {
          continue;
        }
        if (current.exitCode === 0) {
          commands.push(await runServiceCommand(config, runtime, "launchctl", ["bootout", serviceTarget(config, service, runtime)], { allowFailure: true }));
          await delay(runtime);
        }
        commands.push(...await bootstrapLaunchdService(config, runtime, domain, service.path));
      }
    } else if (action === "start") {
      for (const service of services) {
        const current = await inspectLaunchdService(config, runtime, service);
        commands.push({ command: "launchctl", args: ["print", serviceTarget(config, service, runtime)], exitCode: current.exitCode });
        if (current.exitCode !== 0) {
          commands.push(...await bootstrapLaunchdService(config, runtime, domain, service.path));
          commands.push(await runServiceCommand(config, runtime, "launchctl", ["kickstart", serviceTarget(config, service, runtime)]));
        } else if (!launchdPrintShowsReusablePath(current, service.path)) {
          commands.push(await runServiceCommand(config, runtime, "launchctl", ["bootout", serviceTarget(config, service, runtime)], { allowFailure: true }));
          await delay(runtime);
          commands.push(...await bootstrapLaunchdService(config, runtime, domain, service.path));
          commands.push(await runServiceCommand(config, runtime, "launchctl", ["kickstart", serviceTarget(config, service, runtime)]));
        }
      }
    } else if (action === "stop") {
      for (const service of [...services].reverse()) {
        commands.push(await runServiceCommand(config, runtime, "launchctl", ["bootout", serviceTarget(config, service, runtime)], { allowFailure: true }));
      }
    }
    return commands;
  }

  const units = services.map((service) => service.unit);
  if (action === "install") {
    commands.push(await runServiceCommand(config, runtime, "systemctl", ["--user", "link", "--force", ...services.map((service) => service.path)]));
    commands.push(await runServiceCommand(config, runtime, "systemctl", ["--user", "daemon-reload"]));
    commands.push(await runServiceCommand(config, runtime, "systemctl", ["--user", "enable", ...units]));
  } else if (action === "start") {
    for (const unit of units) {
      commands.push(await runServiceCommand(config, runtime, "systemctl", ["--user", "start", unit]));
    }
  } else if (action === "stop") {
    for (const unit of [...units].reverse()) {
      commands.push(await runServiceCommand(config, runtime, "systemctl", ["--user", "stop", unit], { allowFailure: true }));
    }
  }
  return commands;
}

function writeRenderedServiceFiles(config) {
  ensureDirectory(config.runtimeDir);
  ensureDirectory(config.logsDir);
  ensureDirectory(config.servicesDir);
  const files = renderHostServices(config);
  for (const file of files) {
    writeFileAtomic(file.path, file.contents, 0o600);
  }
  return files.map((file) => ({
    role: file.role,
    serviceManager: file.serviceManager,
    path: file.path,
  }));
}

async function installHostServices(config, runtime = {}) {
  const token = ensureTokenFile(config.appServer.tokenFile);
  const envFiles = writeGeneratedEnvFiles(config, runtime);
  const files = writeRenderedServiceFiles(config);
  const commands = await runServiceManagerAction(config, "install", runtime);
  return redactValue({
    version: 1,
    status: "installed",
    appServerAuth: { created: token.created },
    serviceManager: config.serviceManager,
    envFiles,
    files,
    commands,
  });
}

async function manageHostServices(config, action, runtime = {}) {
  if (action === "restart") {
    const stopped = await runServiceManagerAction(config, "stop", runtime);
    const started = await runServiceManagerAction(config, "start", runtime);
    return redactValue({ version: 1, status: "restarted", serviceManager: config.serviceManager, commands: [...stopped, ...started] });
  }
  const commands = await runServiceManagerAction(config, action, runtime);
  const status = action === "stop" ? "stopped" : "started";
  return redactValue({ version: 1, status, serviceManager: config.serviceManager, commands });
}

async function serviceState(config, runtime = {}) {
  const services = [];
  for (const service of serviceEntries(config)) {
    const result = config.platform === "macos"
      ? await runServiceCommand(config, runtime, "launchctl", ["print", serviceTarget(config, service, runtime)], { allowFailure: true })
      : await runServiceCommand(config, runtime, "systemctl", ["--user", "is-active", service.unit], { allowFailure: true });
    services.push({
      role: service.role,
      id: config.platform === "macos" ? service.label : service.unit,
      path: service.path,
      active: result.exitCode === 0,
      exitCode: result.exitCode,
    });
  }
  return services;
}

async function checkHealth(name, url, runtime = {}) {
  try {
    const result = await (runtime.getJSON || getJSON)(url);
    return redactValue({ name, url, ok: result.ok, statusCode: result.statusCode, body: result.body });
  } catch (error) {
    return redactValue({ name, url, ok: false, error });
  }
}

async function checkRelayStatusz(name, url, runtime = {}) {
  try {
    const result = await (runtime.getJSON || getJSON)(url);
    const snapshotOK = result.body?.ok === true;
    const historyOK = result.body?.history?.lastHealth?.ok === true;
    const appCriticalFailures = Array.isArray(result.body?.appCriticalFailures)
      ? result.body.appCriticalFailures.map((route) => ({
        route: route.route,
        routeStatus: route.routeStatus,
        statusReasons: route.statusReasons,
      }))
      : [];
    const routesOK = appCriticalFailures.length === 0;
    return redactValue({
      name,
      url,
      ok: result.ok && snapshotOK && historyOK && routesOK,
      statusCode: result.statusCode,
      snapshotOK,
      historyOK,
      routesOK,
      appCriticalFailures,
      body: result.body,
    });
  } catch (error) {
    return redactValue({ name, url, ok: false, snapshotOK: false, historyOK: false, routesOK: false, error });
  }
}

async function statusHostServices(config, runtime = {}) {
  const services = await serviceState(config, runtime);
  const health = [
    await checkHealth("raw-app-server-readyz", httpURLForWebSocket(config.appServer.listenURL, "/readyz"), runtime),
    await checkHealth("relay-readyz", localRelayHTTPURL(config, "/readyz"), runtime),
    await checkRelayStatusz("relay-statusz", localRelayHTTPURL(config, "/statusz"), runtime),
  ];
  if (config.network.profile !== "simulator-local") {
    health.push(await checkHealth("relay-app-facing-readyz", httpURLForWebSocket(config.relay.publicURL, "/readyz"), runtime));
  }
  const ready = services.every((service) => service.active) && health.every((entry) => entry.ok);
  return redactValue({
    version: 1,
    status: ready ? "ready" : "not-ready",
    checked: true,
    host: {
      id: config.host.id,
      displayName: config.host.displayName,
    },
    serviceManager: config.serviceManager,
    appEndpoint: {
      host: config.relay.appEndpoint.host,
      port: config.relay.appEndpoint.port,
    },
    services,
    health,
  });
}

async function logsHostServices(config, runtime = {}) {
  if (config.platform === "linux") {
    const commands = [];
    for (const service of serviceEntries(config)) {
      const result = await commandRunner(runtime)("journalctl", ["--user", "-u", service.unit, "-n", "200", "--no-pager"], { cwd: config.cwd, env: serviceCommandEnv(runtime) });
      commands.push({
        role: service.role,
        exitCode: result.exitCode,
        stdout: redactValue(tailText(result.stdout, 200), "log"),
        stderr: redactValue(tailText(result.stderr, 40), "log"),
      });
    }
    return { version: 1, serviceManager: config.serviceManager, logs: commands };
  }
  return {
    version: 1,
    serviceManager: config.serviceManager,
    logs: serviceEntries(config).map((service) => ({
      role: service.role,
      stdout: redactValue(tailText(readTailTextIfExists(service.stdoutLog), 200), "log"),
      stderr: redactValue(tailText(readTailTextIfExists(service.stderrLog), 200), "log"),
    })),
  };
}

async function doctorHostServices(config, runtime = {}) {
  const status = await statusHostServices(config, runtime);
  const problems = [];
  for (const service of status.services) {
    if (!service.active) {
      problems.push(`${service.role} service is not active`);
    }
  }
  for (const health of status.health) {
    if (!health.ok) {
      problems.push(`${health.name} is not healthy`);
    }
    for (const failure of health.appCriticalFailures || []) {
      problems.push(`${health.name} app-critical route ${failure.route} is ${failure.routeStatus}`);
    }
  }
  return redactValue({
    version: 1,
    status: problems.length ? "failed" : "passed",
    problems,
    checks: status,
  });
}

function renderText(files) {
  return files.map((file) => [
    `# ${file.role}: ${file.path}`,
    file.contents,
  ].join("\n")).join("\n");
}

async function main(argv = process.argv.slice(2), io = { stdout: process.stdout, stderr: process.stderr }, runtime = {}) {
  const { args, positionals } = parseArgs(argv);
  const command = positionals[0] || args.command;
  if (!command || args.help) {
    io.stdout.write(`${usage()}\n`);
    return 0;
  }
  if (!COMMANDS.has(command)) {
    throw new Error(`unknown command: ${command}`);
  }

  const config = createHostServiceConfig({
    options: args,
    env: runtime.env || process.env,
    cwd: runtime.cwd || process.cwd(),
    platform: runtime.platform || process.platform,
  });
  switch (command) {
  case "render": {
    const format = args.format || "text";
    const files = renderHostServices(config);
    if (format === "json") {
      io.stdout.write(`${JSON.stringify({ version: 1, config: redactValue(config), files }, null, 2)}\n`);
    } else if (format === "text") {
      io.stdout.write(renderText(files));
    } else {
      throw new Error("render format must be json or text");
    }
    return 0;
  }
  case "app-config": {
    const format = args.format || "json";
    if (format === "json") {
      io.stdout.write(`${JSON.stringify(appConfigJSON(config), null, 2)}\n`);
    } else if (format === "env") {
      io.stdout.write(appConfigEnv(config));
    } else {
      throw new Error("app-config format must be json or env");
    }
    return 0;
  }
  case "status":
  {
    const status = await statusHostServices(config, runtime);
    io.stdout.write(`${JSON.stringify(status, null, 2)}\n`);
    return status.status === "ready" ? 0 : 1;
  }
  case "install":
    io.stdout.write(`${JSON.stringify(await installHostServices(config, runtime), null, 2)}\n`);
    return 0;
  case "start":
  case "stop":
  case "restart":
    io.stdout.write(`${JSON.stringify(await manageHostServices(config, command, runtime), null, 2)}\n`);
    return 0;
  case "logs":
    io.stdout.write(`${JSON.stringify(await logsHostServices(config, runtime), null, 2)}\n`);
    return 0;
  case "doctor":
  {
    const result = await doctorHostServices(config, runtime);
    io.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
    return result.status === "passed" ? 0 : 1;
  }
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().then((code) => {
    process.exitCode = code;
  }).catch((error) => {
    process.stderr.write(`${redactValue(error.message)}\n\n${usage()}\n`);
    process.exitCode = 2;
  });
}

export {
  appConfigEnv,
  appConfigJSON,
  createHostServiceConfig,
  dryRunStatus,
  doctorHostServices,
  hostIDToEnvSuffix,
  installHostServices,
  logsHostServices,
  main,
  manageHostServices,
  redactValue,
  renderHostServices,
  resolveRelayPublicURL,
  statusHostServices,
  validateWebSocketURL,
};

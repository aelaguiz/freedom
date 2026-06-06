import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import {
  appConfigEnv,
  appConfigJSON,
  createHostServiceConfig,
  dryRunStatus,
  main,
  redactValue,
  renderHostServices,
  resolveRelayPublicURL,
  validateWebSocketURL,
} from "./codex-dock-host-service.mjs";

const baseEnv = {};
const hostServiceScriptPath = fileURLToPath(new URL("./codex-dock-host-service.mjs", import.meta.url));
const secretLogFixture = [
  "{\"method\":\"turn/start\",\"params\":{\"text\":\"private user request\"},\"headers\":{\"cookie\":\"sid=abc123\"}}",
  "{\"body\":{\"prompt\":\"private prompt\"},\"payload\":{\"transcript\":\"private transcript\"},\"request\":{\"base64Audio\":\"QUJDREVGRw==\"},\"response\":{\"text\":\"private response\"}}",
  "Cookie: sid=abc123; sessionid=def456",
  "Authorization: Bearer bearer-secret-value",
  "OPENAI_API_KEY=plain-secret-token",
  "sk-secretsecretsecretsecret",
].join("\n");
const forbiddenSecrets = [
  "private user request",
  "private prompt",
  "private transcript",
  "private response",
  "sid=abc123",
  "sessionid=def456",
  "bearer-secret-value",
  "plain-secret-token",
  "sk-secretsecretsecretsecret",
  "app-server-secret-token",
  "hidden-secret-token",
  "app-server.token",
];

function tempDir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), "codex-dock-host-service-test-"));
}

function captureIO() {
  let stdout = "";
  let stderr = "";
  return {
    io: {
      stdout: { write(value) { stdout += value; } },
      stderr: { write(value) { stderr += value; } },
    },
    stdout: () => stdout,
    stderr: () => stderr,
  };
}

function assertNoForbiddenSecrets(text) {
  for (const secret of forbiddenSecrets) {
    assert.equal(String(text).includes(secret), false, `leaked ${secret}`);
  }
}

function fakeRunner(resultFor = () => ({ exitCode: 0, stdout: "", stderr: "" })) {
  const calls = [];
  return {
    calls,
    runCommand: async (command, args, options = {}) => {
      calls.push({ command, args, options });
      return {
        command,
        args,
        exitCode: 0,
        stdout: "",
        stderr: "",
        ...resultFor(command, args, options),
      };
    },
  };
}

function makeConfig(overrides = {}) {
  return createHostServiceConfig({
    cwd: "/tmp/codex-client-host-service-test",
    platform: overrides.platform || "macos",
    env: baseEnv,
    hostname: overrides.hostname || "test-host",
    options: {
      "host-id": "home",
      "host-name": "Home",
      "runtime-dir": ".codex-dock-home",
      "service-env-file": "/tmp/codex-client-host-service-test/service.env",
      "node-bin": "/usr/bin/node",
      "network-profile": "lan",
      "public-host": "home.local",
      ...overrides.options,
    },
  });
}

test("host identity auto-derives home when explicit overrides are omitted", () => {
  const config = createHostServiceConfig({
    cwd: "/tmp/codex-client-host-service-test",
    platform: "linux",
    env: baseEnv,
    hostname: "home",
    options: {
      "runtime-dir": ".codex-dock-home",
      "network-profile": "lan",
      "public-host": "100.66.11.7",
    },
  });

  assert.equal(config.host.id, "home");
  assert.equal(config.host.displayName, "Home");
  assert.equal(config.relay.appEndpoint.serialized, "100.66.11.7:4510");
});

test("host identity auto-derives Amir-M5 from tailnet host", () => {
  const config = createHostServiceConfig({
    cwd: "/tmp/codex-client-host-service-test",
    platform: "macos",
    env: baseEnv,
    hostname: "amir-m5.fairy-salmon.ts.net",
    options: {
      "runtime-dir": ".codex-dock",
      "network-profile": "lan",
      "public-host": "amir-m5.fairy-salmon.ts.net",
    },
  });

  assert.equal(config.host.id, "Amir-M5");
  assert.equal(config.host.displayName, "Amir-M5");
  assert.equal(config.relay.appEndpoint.serialized, "amir-m5.fairy-salmon.ts.net:4510");
});

test("explicit host identity still wins over auto-derived identity", () => {
  const config = createHostServiceConfig({
    cwd: "/tmp/codex-client-host-service-test",
    platform: "linux",
    env: baseEnv,
    hostname: "home",
    options: {
      "host-id": "fixture-host",
      "host-name": "Fixture Host",
      "runtime-dir": ".codex-dock-fixture",
      "network-profile": "lan",
      "public-host": "100.66.11.7",
    },
  });

  assert.equal(config.host.id, "fixture-host");
  assert.equal(config.host.displayName, "Fixture Host");
});

test("macOS render emits a single relay launchd service by default", () => {
  const config = makeConfig({ platform: "macos" });
  const files = renderHostServices(config);
  const relay = files.find((file) => file.role === "dock-relay");

  assert.equal(files.length, 1);
  assert.equal(relay.serviceManager, "launchd");
  assert.equal(files.some((file) => file.role === "raw-app-server"), false);
  assert.equal("appServer" in config, false);
  assert.match(relay.path, /com\.aelaguiz\.codex-dock\.relay\.plist$/);
  assert.equal(relay.contents.includes("app-server"), false);
  assert.equal(relay.contents.includes("--history-url"), false);
  assert.equal(relay.contents.includes("--history-auth-token-file"), false);
  assert.match(relay.contents, /<string>--phone-auth<\/string>/);
  assert.match(relay.contents, /<string>none<\/string>/);
  assert.match(relay.contents, /<string>--host-id<\/string>/);
  assert.match(relay.contents, /<string>home<\/string>/);
  assert.match(relay.contents, /<string>--host-name<\/string>/);
  assert.match(relay.contents, /<string>Home<\/string>/);
  assert.match(relay.contents, /<string>--host-endpoint<\/string>/);
  assert.match(relay.contents, /<string>home\.local:4510<\/string>/);
  assert.match(relay.contents, /<string>--relay-state-db<\/string>/);
  assert.match(relay.contents, /<string>\/tmp\/codex-client-host-service-test\/\.codex-dock-home\/relay-state\.sqlite<\/string>/);
});

test("render can point the relay at an explicit Codex home", () => {
  const config = makeConfig({
    options: {
      "codex-home": "/tmp/codex-client/isolated-home",
    },
  });
  const files = renderHostServices(config);
  const relay = files.find((file) => file.role === "dock-relay");

  assert.equal(files.length, 1);
  assert.equal(config.codexHome, "/tmp/codex-client/isolated-home");
  assert.match(relay.contents, /<key>CODEX_HOME<\/key>\n    <string>\/tmp\/codex-client\/isolated-home<\/string>/);
  assert.equal(config.relay.stateDatabasePath, "/tmp/codex-client-host-service-test/.codex-dock-home/relay-state.sqlite");
});

test("render can isolate relay state under an explicit database path", () => {
  const config = makeConfig({
    options: {
      "relay-state-db": "/tmp/codex-client/isolated-service/relay-state.sqlite",
    },
  });
  const relay = renderHostServices(config).find((file) => file.role === "dock-relay");

  assert.equal(config.relay.stateDatabasePath, "/tmp/codex-client/isolated-service/relay-state.sqlite");
  assert.match(relay.contents, /<string>--relay-state-db<\/string>/);
  assert.match(relay.contents, /<string>\/tmp\/codex-client\/isolated-service\/relay-state\.sqlite<\/string>/);
});

test("Linux render emits one systemd user relay service without requiring systemd to run", () => {
  const config = makeConfig({
    platform: "linux",
    options: {
      "public-host": "100.66.11.7",
      "network-profile": "lan",
    },
  });
  const files = renderHostServices(config);
  const relay = files.find((file) => file.role === "dock-relay");

  assert.equal(config.serviceManager, "systemd-user");
  assert.equal(files.length, 1);
  assert.equal(relay.path.endsWith("codex-dock-relay.service"), true);
  assert.match(relay.contents, /\[Service\]/);
  assert.equal(relay.contents.includes("codex-dock-app-server.service"), false);
  assert.equal(relay.contents.includes("--history-auth-token-file"), false);
  assert.equal(relay.contents.includes("--history-url"), false);
  assert.match(relay.contents, /Restart=always/);
});

test("app-config output is app-facing and non-secret", () => {
  const config = makeConfig({
    options: {
      "service-env-file": "/tmp/secret/service.env",
      "relay-public-url": "ws://home.local:4510",
      "phone-auth": "none",
    },
  });

  const json = appConfigJSON(config);
  const envText = appConfigEnv(config);
  const combined = `${JSON.stringify(json)}\n${envText}`;

  assert.deepEqual(json, {
    version: 1,
    hosts: [
      {
        host: "home.local",
        port: 4510,
      },
    ],
  });
  assert.match(envText, /CODEX_DOCK_HOSTS=home\.local:4510/);
  assert.equal(envText.includes("CODEX_DOCK_RELAY_INSTANCE_ID"), false);
  assert.equal(envText.includes("CODEX_DOCK_HOST_HOME_WS"), false);
  assert.equal(envText.includes("CODEX_DOCK_HOST_HOME_NAME"), false);
  assert.equal(envText.includes("CODEX_DOCK_HOST_HOME_AUTH_MODE"), false);
  assert.equal(combined.includes("OPENAI_API_KEY"), false);
  assert.equal(combined.includes("app-server.token"), false);
  assert.equal(combined.includes("service.env"), false);
  assert.equal(combined.includes("secret"), false);
});

test("write-env writes generated env with auto-derived home identity", async () => {
  const cwd = tempDir();
  const runtimeDir = path.join(cwd, ".codex-dock-test");
  const output = captureIO();

  const code = await main([
    "write-env",
    "--platform",
    "linux",
    "--runtime-dir",
    ".codex-dock-test",
    "--network-profile",
    "lan",
    "--public-host",
    "100.66.11.7",
  ], output.io, { cwd, platform: "linux", hostname: "home" });

  assert.equal(code, 0);
  const result = JSON.parse(output.stdout());
  assert.equal(result.status, "wrote-env");
  assert.deepEqual(result.host, {
    id: "home",
    displayName: "Home",
    envSuffix: "HOME",
  });

  const serviceEnv = fs.readFileSync(path.join(runtimeDir, "service.env"), "utf8");
  const hostEnv = fs.readFileSync(path.join(runtimeDir, "host.env"), "utf8");
  assert.match(serviceEnv, /CODEX_DOCK_REAL_HOST_ID=home/);
  assert.match(serviceEnv, /CODEX_DOCK_REAL_HOST_NAME=Home/);
  assert.match(serviceEnv, /CODEX_DOCK_HOSTS=100\.66\.11\.7:4510/);
  assert.match(hostEnv, /CODEX_DOCK_HOSTS=100\.66\.11\.7:4510/);
  assert.equal(hostEnv.includes("CODEX_DOCK_REAL_HOST_ID"), false);
  assert.equal(hostEnv.includes("OPENAI_API_KEY"), false);
});

test("write-env refuses to overwrite user-owned .env", async () => {
  const cwd = tempDir();
  await assert.rejects(
    () => main([
      "write-env",
      "--platform",
      "linux",
      "--runtime-dir",
      ".codex-dock-test",
      "--service-env-file",
      ".env",
      "--network-profile",
      "lan",
      "--public-host",
      "100.66.11.7",
    ], captureIO().io, { cwd, platform: "linux", hostname: "home" }),
    /refusing to overwrite user-owned \.env/,
  );
});

test("app-config rejects raw app-server port as relay public URL", () => {
  assert.throws(
    () => makeConfig({
      options: {
        "relay-public-url": "ws://127.0.0.1:4500",
      },
    }),
    /relay public URL must point at the Dock relay on :4510, not the raw Codex app-server on :4500/,
  );
});

test("network profiles produce relay URLs without app or relay code depending on Tailscale", () => {
  assert.equal(
    resolveRelayPublicURL({
      networkProfile: "lan",
      publicHost: "codex-host.local",
      relayPort: 4510,
      env: baseEnv,
    }),
    "ws://codex-host.local:4510/",
  );
  assert.equal(
    resolveRelayPublicURL({
      networkProfile: "simulator-local",
      relayPort: 4510,
      env: baseEnv,
    }),
    "ws://127.0.0.1:4510/",
  );
  assert.throws(
    () => resolveRelayPublicURL({ networkProfile: "tailscale", relayPort: 4510, env: baseEnv }),
    /unsupported network profile/,
  );
});

test("WebSocket URLs reject credentials and unsupported schemes", () => {
  assert.equal(validateWebSocketURL("wss://host.example:4510", "relay URL"), "wss://host.example:4510/");
  assert.throws(
    () => validateWebSocketURL("http://host.example:4510", "relay URL"),
    /must use ws:\/\/ or wss:\/\//,
  );
  assert.throws(
    () => validateWebSocketURL("ws://user:pass@host.example:4510", "relay URL"),
    /must not include username or password/,
  );
});

test("redaction removes secrets, credentialed URLs, raw audio, transcript, and prompt fields", () => {
  const redacted = redactValue({
    authorization: "Bearer relay-secret-token",
    openAIAPIKey: "sk-secretsecretsecretsecret",
    endpointURL: "ws://user:pass@host.example:4510/path?token=secret",
    base64Audio: Buffer.from("audio").toString("base64"),
    transcript: "private transcript",
    prompt: "private prompt",
    headers: { cookie: "sid=abc123" },
    params: { text: "private user request" },
    nested: {
      message: "failed to reach ws://user:pass@host.example:4510/path?token=secret#frag",
      envDump: "OPENAI_API_KEY=plain-secret-token",
      tokenFile: "/tmp/codex/app-server.token",
      statusURL: "ws://host.example:4510/statusz?token=secret",
      cookieLine: "Cookie: sid=abc123; sessionid=def456",
      jsonLine: "{\"method\":\"turn/start\",\"params\":{\"text\":\"private user request\"}}",
    },
  });

  assert.equal(redacted.authorization, "<redacted>");
  assert.equal(redacted.openAIAPIKey, "<redacted>");
  assert.equal(redacted.endpointURL, "ws://host.example:4510/path");
  assert.equal(redacted.base64Audio, "<redacted>");
  assert.equal(redacted.transcript, "<redacted>");
  assert.equal(redacted.prompt, "<redacted>");
  assert.equal(redacted.headers, "<redacted-payload>");
  assert.equal(redacted.params, "<redacted-payload>");
  assert.equal(redacted.nested.message, "failed to reach ws://host.example:4510/path");
  assert.equal(redacted.nested.envDump, "OPENAI_API_KEY=<redacted>");
  assert.equal(redacted.nested.tokenFile, "<redacted>");
  assert.equal(redacted.nested.statusURL, "ws://host.example:4510/statusz");
  assert.equal(redacted.nested.cookieLine.includes("sid=abc123"), false);
  assert.equal(redacted.nested.cookieLine.includes("sessionid=def456"), false);
  assert.equal(redacted.nested.jsonLine.includes("private user request"), false);
});

test("dry-run status does not pretend services are installed or ready", () => {
  const config = makeConfig();
  const status = dryRunStatus(config);
  const text = JSON.stringify(status);

  assert.equal(status.status, "not-installed");
  assert.equal(status.checked, false);
  assert.deepEqual(status.appEndpoint, { host: "home.local", port: 4510 });
  assert.equal(text.includes("ready"), false);
  assert.equal(text.includes("app-server.token"), false);
  assert.equal(text.includes("OPENAI_API_KEY"), false);
});

test("install writes only relay service files and calls launchd through an injected runner", async () => {
  const cwd = tempDir();
  fs.writeFileSync(path.join(cwd, ".env"), "OPENAI_API_KEY=sk-testtesttesttesttest\n");
  const runner = fakeRunner();
  const output = captureIO();

  await main([
    "install",
    "--platform",
    "macos",
    "--runtime-dir",
    ".codex-dock-test",
    "--host-id",
    "home",
    "--host-name",
    "Home",
    "--public-host",
    "home.local",
  ], output.io, { cwd, platform: "macos", uid: 501, runCommand: runner.runCommand });

  const parsed = JSON.parse(output.stdout());

  assert.equal(parsed.status, "installed");
  assert.equal("appServerAuth" in parsed, false);
  assert.equal(output.stdout().includes("app-server.token"), false);
  assert.match(fs.readFileSync(path.join(cwd, ".codex-dock-test", "service.env"), "utf8"), /OPENAI_API_KEY=sk-testtesttesttesttest/);
  assert.match(fs.readFileSync(path.join(cwd, ".codex-dock-test", "service.env"), "utf8"), /CODEX_DOCK_HOSTS=home\.local:4510/);
  assert.equal(fs.readFileSync(path.join(cwd, ".codex-dock-test", "service.env"), "utf8").includes("CODEX_DOCK_RELAY_INSTANCE_ID"), false);
  const generatedHostEnv = fs.readFileSync(path.join(cwd, ".codex-dock-test", "host.env"), "utf8");
  assert.match(generatedHostEnv, /CODEX_DOCK_HOSTS=home\.local:4510/);
  assert.equal(generatedHostEnv.includes("CODEX_DOCK_RELAY_INSTANCE_ID"), false);
  assert.equal(generatedHostEnv.includes("CODEX_DOCK_HOST_HOME_AUTH_MODE"), false);
  assert.equal(generatedHostEnv.includes("CODEX_DOCK_PHONE_REACHABLE_APP_SERVER_WS"), false);
  assert.equal(generatedHostEnv.includes("OPENAI_API_KEY"), false);
  assert.equal(fs.existsSync(path.join(cwd, ".codex-dock-test", "app-server.token")), false);
  assert.equal(fs.existsSync(path.join(cwd, ".codex-dock-test", "services", "com.aelaguiz.codex-dock.app-server.plist")), false);
  assert.equal(fs.existsSync(path.join(cwd, ".codex-dock-test", "services", "com.aelaguiz.codex-dock.relay.plist")), true);
  assert.deepEqual(runner.calls.map((call) => [call.command, call.args[0], call.args[1]]), [
    ["launchctl", "print", "gui/501/com.aelaguiz.codex-dock.app-server"],
    ["launchctl", "print", "gui/501/com.aelaguiz.codex-dock.relay"],
    ["launchctl", "bootout", "gui/501/com.aelaguiz.codex-dock.relay"],
    ["launchctl", "bootstrap", "gui/501"],
  ]);
});

test("install removes stale legacy raw app-server service files and stops loaded launchd job", async () => {
  const cwd = tempDir();
  const runtimeDir = path.join(cwd, ".codex-dock-test");
  const servicesDir = path.join(runtimeDir, "services");
  const legacyPath = path.join(servicesDir, "com.aelaguiz.codex-dock.app-server.plist");
  fs.mkdirSync(servicesDir, { recursive: true });
  fs.writeFileSync(legacyPath, "old raw app-server plist");
  const runner = fakeRunner((command, args) => {
    if (command === "launchctl" && args[0] === "print" && args[1].includes("app-server")) {
      return { exitCode: 0, stdout: `gui/501/com.aelaguiz.codex-dock.app-server = {\npath = ${legacyPath}\nstate = running\n}`, stderr: "" };
    }
    return { exitCode: 0, stdout: "", stderr: "" };
  });

  await main([
    "install",
    "--platform",
    "macos",
    "--runtime-dir",
    ".codex-dock-test",
    "--host-id",
    "home",
    "--host-name",
    "Home",
    "--public-host",
    "home.local",
  ], captureIO().io, { cwd, platform: "macos", uid: 501, runCommand: runner.runCommand });

  assert.equal(fs.existsSync(legacyPath), false);
  assert.equal(runner.calls.some((call) => call.command === "launchctl" && call.args[0] === "bootout" && call.args[1] === "gui/501/com.aelaguiz.codex-dock.app-server"), true);
});

test("install writes two-host app env from app-safe service env keys only", async () => {
  const cwd = tempDir();
  const runtimeDir = path.join(cwd, ".codex-dock-test");
  fs.mkdirSync(runtimeDir, { recursive: true });
  fs.writeFileSync(path.join(runtimeDir, "service.env"), [
    "CODEX_DOCK_HOSTS=100.66.11.7:4510,Amir-M5,home",
    "CODEX_DOCK_HOST_AMIR_M5_WS=ws://192.168.50.117:4510/",
    "CODEX_DOCK_HOST_AMIR_M5_NAME=Amir-M5",
    "CODEX_DOCK_HOST_AMIR_M5_AUTH_MODE=none",
    "CODEX_DOCK_HOST_AMIR_M5_TOKEN=hidden-secret-token",
    "CODEX_DOCK_HOST_HOME_WS=ws://100.66.11.7:4510/",
    "CODEX_DOCK_HOST_HOME_NAME=Home",
    "CODEX_DOCK_HOST_HOME_AUTH_MODE=none",
    "CODEX_DOCK_HOST_HOME_BEARER_TOKEN=app-server-secret-token",
    "CODEX_DOCK_HOST_STALE_WS=ws://stale.local:4510/",
    "CODEX_DOCK_HOST_STALE_NAME=Stale",
    "CODEX_DOCK_HOST_STALE_AUTH_MODE=none",
    "CODEX_DOCK_APP_SERVER_BEARER_TOKEN_FILE=/tmp/secret/app-server.token",
    "CODEX_DOCK_OPENAI_REALTIME_TRANSCRIPTION_MODEL=gpt-realtime-whisper",
    "OPENAI_API_KEY=plain-secret-token",
    "PROMPT_TEXT=private prompt",
    "",
  ].join("\n"));

  await main([
    "install",
    "--platform",
    "macos",
    "--runtime-dir",
    ".codex-dock-test",
    "--host-id",
    "Amir-M5",
    "--host-name",
    "Amir-M5",
    "--relay-public-url",
    "ws://192.168.50.117:4510/",
  ], captureIO().io, { cwd, platform: "macos", uid: 501, runCommand: fakeRunner().runCommand });

  const hostEnv = fs.readFileSync(path.join(runtimeDir, "host.env"), "utf8");
  assert.match(hostEnv, /CODEX_DOCK_HOSTS=192\.168\.50\.117:4510,100\.66\.11\.7:4510/);
  assert.equal(hostEnv.includes("CODEX_DOCK_RELAY_INSTANCE_ID"), false);
  assert.equal(hostEnv.includes("CODEX_DOCK_HOST_AMIR_M5_WS"), false);
  assert.equal(hostEnv.includes("CODEX_DOCK_HOST_AMIR_M5_NAME"), false);
  assert.equal(hostEnv.includes("CODEX_DOCK_HOST_AMIR_M5_AUTH_MODE"), false);
  assert.equal(hostEnv.includes("CODEX_DOCK_HOST_HOME_WS"), false);
  assert.equal(hostEnv.includes("CODEX_DOCK_HOST_HOME_NAME"), false);
  assert.equal(hostEnv.includes("CODEX_DOCK_HOST_HOME_AUTH_MODE"), false);
  assert.equal(hostEnv.includes("CODEX_DOCK_HOST_STALE_WS"), false);
  assert.equal(hostEnv.includes("CODEX_DOCK_HOST_STALE_NAME"), false);
  assert.equal(hostEnv.includes("OPENAI_API_KEY"), false);
  assert.equal(hostEnv.includes("CODEX_DOCK_OPENAI_REALTIME_TRANSCRIPTION_MODEL"), false);
  assert.equal(hostEnv.includes("PROMPT_TEXT"), false);
  assert.equal(/TOKEN|TOKEN_FILE|BEARER|SECRET|PASSWORD|COOKIE|SESSION/.test(hostEnv), false);
  assertNoForbiddenSecrets(hostEnv);
});

test("install rejects stale raw app-server endpoint in app-facing host env", async () => {
  const cwd = tempDir();
  const runtimeDir = path.join(cwd, ".codex-dock-test");
  fs.mkdirSync(runtimeDir, { recursive: true });
  fs.writeFileSync(path.join(runtimeDir, "service.env"), [
    "CODEX_DOCK_HOSTS=127.0.0.1:4500",
    "",
  ].join("\n"));

  await assert.rejects(
    () => main([
      "install",
      "--platform",
      "macos",
      "--runtime-dir",
      ".codex-dock-test",
      "--host-id",
      "Amir-M5",
      "--host-name",
      "Amir-M5",
      "--relay-public-url",
      "ws://192.168.50.117:4510/",
    ], captureIO().io, { cwd, platform: "macos", uid: 501, runCommand: fakeRunner().runCommand }),
    /CODEX_DOCK_HOSTS must point at the Dock relay on :4510, not the raw Codex app-server on :4500: 127\.0\.0\.1:4500/,
  );
  assert.equal(fs.existsSync(path.join(runtimeDir, "host.env")), false);
});

test("install reuses loaded launchd services when they already point at rendered paths", async () => {
  const cwd = tempDir();
  const relayPath = path.join(cwd, ".codex-dock-test", "services", "com.aelaguiz.codex-dock.relay.plist");
  const runner = fakeRunner((command, args) => {
    if (command === "launchctl" && args[0] === "print" && args[1].includes("relay")) {
      return { exitCode: 0, stdout: `path = ${relayPath}\nstate = running\n`, stderr: "" };
    }
    return { exitCode: 0, stdout: "", stderr: "" };
  });

  await main([
    "install",
    "--platform",
    "macos",
    "--runtime-dir",
    ".codex-dock-test",
    "--host-id",
    "home",
    "--host-name",
    "Home",
    "--public-host",
    "home.local",
  ], captureIO().io, { cwd, platform: "macos", uid: 501, runCommand: runner.runCommand });

  assert.deepEqual(runner.calls.map((call) => [call.command, call.args[0], call.args[1]]), [
    ["launchctl", "print", "gui/501/com.aelaguiz.codex-dock.app-server"],
    ["launchctl", "print", "gui/501/com.aelaguiz.codex-dock.relay"],
  ]);
});

test("systemd install links and enables only the relay service without starting it", async () => {
  const cwd = tempDir();
  const runner = fakeRunner();
  const output = captureIO();

  await main([
    "install",
    "--platform",
    "linux",
    "--runtime-dir",
    ".codex-dock-test",
    "--host-id",
    "home",
    "--host-name",
    "Home",
    "--public-host",
    "home.local",
  ], output.io, { cwd, platform: "linux", runCommand: runner.runCommand });

  const parsed = JSON.parse(output.stdout());

  assert.equal(parsed.status, "installed");
  assert.equal("appServerAuth" in parsed, false);
  assert.equal(fs.existsSync(path.join(cwd, ".codex-dock-test", "app-server.token")), false);
  assert.deepEqual(runner.calls.map((call) => call.args.slice(0, 3)), [
    ["--user", "stop", "codex-dock-app-server.service"],
    ["--user", "disable", "codex-dock-app-server.service"],
    ["--user", "link", "--force"],
    ["--user", "daemon-reload"],
    ["--user", "enable", "codex-dock-relay.service"],
  ]);
  assert.equal(runner.calls[2].args.includes(path.join(cwd, ".codex-dock-test", "services", "codex-dock-app-server.service")), false);
  assert.equal(runner.calls[2].args.includes(path.join(cwd, ".codex-dock-test", "services", "codex-dock-relay.service")), true);
  assert.equal(JSON.stringify(runner.calls).includes("--now"), false);
  assert.equal(JSON.stringify(runner.calls).includes('"start"'), false);
});

test("systemd start restarts the relay service and cleans legacy raw app-server", async () => {
  const cwd = tempDir();
  const startRunner = fakeRunner();
  const stopRunner = fakeRunner();

  await main([
    "start",
    "--platform",
    "linux",
    "--runtime-dir",
    ".codex-dock-test",
    "--host-id",
    "home",
    "--host-name",
    "Home",
    "--public-host",
    "home.local",
  ], captureIO().io, { cwd, platform: "linux", runCommand: startRunner.runCommand });

  await main([
    "stop",
    "--platform",
    "linux",
    "--runtime-dir",
    ".codex-dock-test",
    "--host-id",
    "home",
    "--host-name",
    "Home",
    "--public-host",
    "home.local",
  ], captureIO().io, { cwd, platform: "linux", runCommand: stopRunner.runCommand });

  assert.deepEqual(startRunner.calls.map((call) => call.args.slice(0, 3)), [
    ["--user", "stop", "codex-dock-app-server.service"],
    ["--user", "disable", "codex-dock-app-server.service"],
    ["--user", "restart", "codex-dock-relay.service"],
  ]);
  assert.deepEqual(stopRunner.calls.map((call) => call.args.slice(0, 3)), [
    ["--user", "stop", "codex-dock-app-server.service"],
    ["--user", "disable", "codex-dock-app-server.service"],
    ["--user", "stop", "codex-dock-relay.service"],
  ]);
});

test("macOS start force-kickstarts loaded launchd services so new arguments take effect", async () => {
  const cwd = tempDir();
  const runner = fakeRunner((command, args) => {
    if (command === "launchctl" && args[0] === "print") {
      const servicePath = path.join(cwd, ".codex-dock-test", "services", "com.aelaguiz.codex-dock.relay.plist");
      return { exitCode: 0, stdout: `path = ${servicePath}\nstate = running\n`, stderr: "" };
    }
    return { exitCode: 0, stdout: "", stderr: "" };
  });

  await main([
    "start",
    "--platform",
    "macos",
    "--runtime-dir",
    ".codex-dock-test",
    "--host-id",
    "home",
    "--host-name",
    "Home",
    "--public-host",
    "home.local",
  ], captureIO().io, { cwd, platform: "macos", uid: 501, runCommand: runner.runCommand });

  assert.deepEqual(runner.calls.map((call) => [call.command, call.args[0], call.args[1]]), [
    ["launchctl", "print", "gui/501/com.aelaguiz.codex-dock.app-server"],
    ["launchctl", "print", "gui/501/com.aelaguiz.codex-dock.relay"],
    ["launchctl", "kickstart", "-k"],
  ]);
  assert.equal(runner.calls[2].args[2], "gui/501/com.aelaguiz.codex-dock.relay");
});

test("macOS start re-bootstraps loaded launchd services that are not running", async () => {
  const cwd = tempDir();
  const runner = fakeRunner((command, args) => {
    if (command === "launchctl" && args[0] === "print") {
      const servicePath = path.join(cwd, ".codex-dock-test", "services", "com.aelaguiz.codex-dock.relay.plist");
      return { exitCode: 0, stdout: `path = ${servicePath}\nstate = waiting\n`, stderr: "" };
    }
    return { exitCode: 0, stdout: "", stderr: "" };
  });

  await main([
    "start",
    "--platform",
    "macos",
    "--runtime-dir",
    ".codex-dock-test",
    "--host-id",
    "home",
    "--host-name",
    "Home",
    "--public-host",
    "home.local",
  ], captureIO().io, { cwd, platform: "macos", uid: 501, runCommand: runner.runCommand });

  assert.deepEqual(runner.calls.map((call) => [call.command, call.args[0], call.args[1]]), [
    ["launchctl", "print", "gui/501/com.aelaguiz.codex-dock.app-server"],
    ["launchctl", "print", "gui/501/com.aelaguiz.codex-dock.relay"],
    ["launchctl", "bootout", "gui/501/com.aelaguiz.codex-dock.relay"],
    ["launchctl", "bootstrap", "gui/501"],
    ["launchctl", "kickstart", "gui/501/com.aelaguiz.codex-dock.relay"],
  ]);
});

test("service-manager failures are redacted and child environments are secret-free", async () => {
  const cwd = tempDir();
  const runner = fakeRunner((command, args) => {
    if (command === "launchctl" && args[0] === "bootstrap") {
      return { exitCode: 1, stdout: secretLogFixture, stderr: secretLogFixture };
    }
    return { exitCode: 0, stdout: "", stderr: "" };
  });

  await assert.rejects(
    () => main([
      "install",
      "--platform",
      "macos",
      "--runtime-dir",
      path.join(cwd, "secret-runtime"),
      "--host-id",
      "home",
      "--host-name",
      "Home",
      "--public-host",
      "home.local",
    ], captureIO().io, {
      cwd,
      platform: "macos",
      uid: 501,
      commandEnv: {
        HOME: "/tmp/test-home",
        PATH: "/usr/bin",
        LANG: "en_US.UTF-8",
        XDG_RUNTIME_DIR: "/run/user/501",
        DBUS_SESSION_BUS_ADDRESS: "unix:path=/run/user/501/bus",
        OPENAI_API_KEY: "plain-secret-token",
        CODEX_DOCK_APP_SERVER_BEARER_TOKEN: "bearer-secret-value",
      },
      runCommand: runner.runCommand,
    }),
    (error) => {
      const text = `${error.message}\n${JSON.stringify(error.result)}`;
      assertNoForbiddenSecrets(text);
      assert.equal(text.includes("secret-runtime"), false);
      return true;
    },
  );

  for (const call of runner.calls) {
    assert.equal(call.options.cwd, cwd);
    assert.equal(call.options.env.HOME, "/tmp/test-home");
    assert.equal(call.options.env.PATH, "/usr/bin");
    assert.equal(call.options.env.LANG, "en_US.UTF-8");
    assert.equal(call.options.env.XDG_RUNTIME_DIR, "/run/user/501");
    assert.equal(call.options.env.DBUS_SESSION_BUS_ADDRESS, "unix:path=/run/user/501/bus");
    assert.equal("OPENAI_API_KEY" in call.options.env, false);
    assert.equal("CODEX_DOCK_APP_SERVER_BEARER_TOKEN" in call.options.env, false);
  }
});

test("status checks systemd services and local health without leaking token output", async () => {
  const runner = fakeRunner((command, args) => {
    assert.equal(command, "systemctl");
    if (args.includes("codex-dock-relay.service")) {
      return { exitCode: 0, stdout: "active\n", stderr: "--ws-token-file /tmp/secret/app-server.token" };
    }
    return { exitCode: 1, stdout: "inactive\n", stderr: "missing token /tmp/secret/app-server.token" };
  });
  const output = captureIO();

  await main([
    "status",
    "--platform",
    "linux",
    "--runtime-dir",
    ".codex-dock-test",
    "--host-id",
    "home",
    "--host-name",
    "Home",
    "--public-host",
    "100.66.11.7",
  ], output.io, {
    cwd: tempDir(),
    platform: "linux",
    runCommand: runner.runCommand,
    getJSON: async (url) => ({
      ok: true,
      statusCode: 200,
      body: url.includes("statusz") ? {
        ok: true,
        host: {
          id: "home",
          relayInstanceID: "home",
          displayName: "Home",
        },
        appServerRegistry: {
          ok: true,
          status: "ready",
          history: {
            url: "unix://<socket>",
            authConfigured: false,
          },
          counts: {
            endpoints: 1,
            liveEndpoints: 2,
            unreachableObserved: 1,
            failedEndpoints: 0,
            threadOwners: 4,
            privateOwners: 1,
          },
        },
        headers: { cookie: "sid=abc123", "set-cookie": "sessionid=def456" },
        params: { text: "private user request" },
        body: { prompt: "private prompt" },
        payload: { transcript: "private transcript" },
        request: { base64Audio: "QUJDREVGRw==" },
        response: { text: "private response" },
      } : { ok: true },
    }),
  });

  const parsed = JSON.parse(output.stdout());
  const text = output.stdout();
  assert.equal(parsed.status, "ready");
  assert.equal(parsed.services.length, 1);
  assert.equal(parsed.services[0].role, "dock-relay");
  assert.equal(parsed.health.length, 3);
  assert.equal(parsed.health[1].identity.ok, true);
  assert.equal(text.includes("app-server.token"), false);
  assert.equal(text.includes("user:pass"), false);
  assert.equal(text.includes("token=secret"), false);
  assertNoForbiddenSecrets(text);
  assert.equal(parsed.health[1].body, "<redacted-payload>");
});

test("status fails when running relay reports the wrong host identity", async () => {
  const runner = fakeRunner((command, args) => {
    assert.equal(command, "systemctl");
    if (args.includes("codex-dock-relay.service")) {
      return { exitCode: 0, stdout: "active\n", stderr: "" };
    }
    return { exitCode: 1, stdout: "inactive\n", stderr: "" };
  });
  const output = captureIO();

  const code = await main([
    "status",
    "--platform",
    "linux",
    "--runtime-dir",
    ".codex-dock-test",
    "--public-host",
    "100.66.11.7",
  ], output.io, {
    cwd: tempDir(),
    platform: "linux",
    hostname: "home",
    runCommand: runner.runCommand,
    getJSON: async (url) => ({
      ok: true,
      statusCode: 200,
      body: url.includes("statusz") ? {
        ok: true,
        host: {
          id: "Amir-M5",
          relayInstanceID: "Amir-M5",
          displayName: "Amir-M5",
        },
        appServerRegistry: {
          ok: true,
          status: "ready",
        },
        appCriticalFailures: [],
      } : { ok: true },
    }),
  });

  const parsed = JSON.parse(output.stdout());
  assert.equal(code, 1);
  assert.equal(parsed.status, "not-ready");
  assert.equal(parsed.host.id, "home");
  assert.equal(parsed.host.displayName, "Home");
  assert.equal(parsed.health[1].identity.ok, false);
  assert.match(parsed.health[1].identity.problems.join("\n"), /expected host id home but statusz reported Amir-M5/);
  assert.match(parsed.health[1].identity.problems.join("\n"), /expected host display name Home but statusz reported Amir-M5/);
});

test("status and doctor return nonzero codes when services are not ready", async () => {
  const runner = fakeRunner(() => ({ exitCode: 1, stdout: "inactive\n", stderr: "inactive" }));
  const statusOutput = captureIO();
  const doctorOutput = captureIO();
  const args = [
    "--platform",
    "linux",
    "--runtime-dir",
    ".codex-dock-test",
    "--host-id",
    "home",
    "--host-name",
    "Home",
    "--public-host",
    "home.local",
  ];
  const runtime = {
    cwd: tempDir(),
    platform: "linux",
    runCommand: runner.runCommand,
    getJSON: async () => ({ ok: false, statusCode: 503, body: { ok: false } }),
  };

  const statusCode = await main(["status", ...args], statusOutput.io, runtime);
  const doctorCode = await main(["doctor", ...args], doctorOutput.io, runtime);

  assert.equal(statusCode, 1);
  assert.equal(JSON.parse(statusOutput.stdout()).status, "not-ready");
  assert.equal(doctorCode, 1);
  assert.equal(JSON.parse(doctorOutput.stdout()).status, "failed");
});

test("logs and doctor redact service-manager and service output", async () => {
  const cwd = tempDir();
  const logDir = path.join(cwd, ".codex-dock-test", "logs");
  fs.mkdirSync(logDir, { recursive: true });
  fs.writeFileSync(path.join(logDir, "dock-relay.log"), `Bearer app-server-secret-token\ntranscript private transcript\n${secretLogFixture}\n`);
  fs.writeFileSync(path.join(logDir, "dock-relay.err.log"), `OPENAI_API_KEY=plain-secret-token\n${secretLogFixture}\n`);
  const output = captureIO();

  await main([
    "logs",
    "--platform",
    "macos",
    "--runtime-dir",
    ".codex-dock-test",
    "--host-id",
    "home",
    "--host-name",
    "Home",
    "--public-host",
    "home.local",
  ], output.io, { cwd, platform: "macos" });

  const text = output.stdout();
  assertNoForbiddenSecrets(text);

  const doctorOutput = captureIO();
  await main([
    "doctor",
    "--platform",
    "linux",
    "--runtime-dir",
    ".codex-dock-test",
    "--host-id",
    "home",
    "--host-name",
    "Home",
    "--public-host",
    "home.local",
  ], doctorOutput.io, {
    cwd,
    platform: "linux",
    runCommand: fakeRunner(() => ({ exitCode: 1, stdout: "inactive", stderr: "OPENAI_API_KEY=plain-secret-token" })).runCommand,
    getJSON: async () => { throw new Error("Bearer hidden-secret-token"); },
  });
  const doctorText = doctorOutput.stdout();
  assertNoForbiddenSecrets(doctorText);
  assert.match(JSON.parse(doctorText).problems.join("\n"), /service is not active/);
});

test("macOS logs read bounded tail bytes from large service logs", async () => {
  const cwd = tempDir();
  const logDir = path.join(cwd, ".codex-dock-test", "logs");
  fs.mkdirSync(logDir, { recursive: true });
  fs.writeFileSync(path.join(logDir, "dock-relay.log"), `old-line\n${"x".repeat(1_100_000)}\nrecent-line\n`);
  fs.writeFileSync(path.join(logDir, "dock-relay.err.log"), `old-relay-line\n${"y".repeat(1_100_000)}\nrecent-relay-line\n`);
  const output = captureIO();

  await main([
    "logs",
    "--platform",
    "macos",
    "--runtime-dir",
    ".codex-dock-test",
    "--host-id",
    "home",
    "--host-name",
    "Home",
    "--public-host",
    "home.local",
  ], output.io, { cwd, platform: "macos" });

  const text = output.stdout();
  assert.equal(text.includes("recent-line"), true);
  assert.equal(text.includes("recent-relay-line"), true);
  assert.equal(text.includes("old-line"), false);
  assert.equal(text.includes("old-relay-line"), false);
});

test("linux logs redact JSON-RPC payloads cookies and provider secrets", async () => {
  const runner = fakeRunner(() => ({ exitCode: 0, stdout: secretLogFixture, stderr: secretLogFixture }));
  const output = captureIO();

  await main([
    "logs",
    "--platform",
    "linux",
    "--runtime-dir",
    ".codex-dock-test",
    "--host-id",
    "home",
    "--host-name",
    "Home",
    "--public-host",
    "home.local",
  ], output.io, { cwd: tempDir(), platform: "linux", runCommand: runner.runCommand });

  const text = output.stdout();
  assertNoForbiddenSecrets(text);
  assert.equal(text.includes("<redacted-payload>"), true);
  assert.equal(runner.calls.length, 1);
});

test("CLI rejects missing option values and unknown options", async () => {
  const io = {
    stdout: { write() {} },
    stderr: { write() {} },
  };

  await assert.rejects(
    () => main(["render", "--relay-port", "--format", "json"], io),
    /--relay-port requires a value/,
  );
  await assert.rejects(
    () => main(["render", "--host-name"], io),
    /--host-name requires a value/,
  );
  await assert.rejects(
    () => main(["render", "--host-name="], io),
    /--host-name requires a value/,
  );
  await assert.rejects(
    () => main(["render", "--relay-pubilc-url", "ws://home.local:4510"], io),
    /unknown option: --relay-pubilc-url/,
  );
  await assert.rejects(
    () => main(["app-config", "--env-file", "/tmp/secret/service.env"], io),
    /unknown option: --env-file/,
  );
  await assert.rejects(
    () => main(["render", "--help=false"], io),
    /--help does not take a value/,
  );
  await assert.rejects(
    () => main(["start", "--network-profile", "manual"], io),
    /manual network profile requires --relay-public-url/,
  );
});

test("CLI service env option avoids Node 25 --env-file interception", () => {
  const result = spawnSync(process.execPath, [
    hostServiceScriptPath,
    "app-config",
    "--service-env-file",
    "/tmp/secret/service.env",
    "--network-profile",
    "simulator-local",
  ], {
    cwd: tempDir(),
    encoding: "utf8",
    env: {
      HOME: os.homedir(),
      PATH: process.env.PATH || "/usr/bin:/bin",
    },
  });

  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stderr, "");
  assert.match(result.stdout, /"host": "127\.0\.0\.1"/);
  assert.match(result.stdout, /"port": 4510/);
  assert.equal(result.stdout.includes("service.env"), false);
});

test("env app-config values reject line breaks", () => {
  const config = makeConfig();
  config.relay.appEndpoint.serialized = "home.local:4510\nCODEX_DOCK_HOST_HOME_BEARER_TOKEN=secret";

  assert.throws(
    () => appConfigEnv(config),
    /relay host must not contain line breaks/,
  );
});

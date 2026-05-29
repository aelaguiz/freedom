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
    options: {
      "host-id": "home",
      "host-name": "Home",
      "runtime-dir": ".codex-dock-home",
      "service-env-file": "/tmp/codex-client-host-service-test/service.env",
      "codex-bin": "/usr/local/bin/codex",
      "node-bin": "/usr/bin/node",
      "network-profile": "lan",
      "public-host": "home.local",
      ...overrides.options,
    },
  });
}

test("macOS render emits launchd services with raw app-server loopback by default", () => {
  const config = makeConfig({ platform: "macos" });
  const files = renderHostServices(config);
  const appServer = files.find((file) => file.role === "raw-app-server");
  const relay = files.find((file) => file.role === "dock-relay");

  assert.equal(files.length, 2);
  assert.equal(appServer.serviceManager, "launchd");
  assert.equal(relay.serviceManager, "launchd");
  assert.equal(config.appServer.listenURL, "ws://127.0.0.1:4500");
  assert.match(appServer.path, /com\.aelaguiz\.codex-dock\.app-server\.plist$/);
  assert.match(appServer.contents, /<string>app-server<\/string>/);
  assert.match(appServer.contents, /<string>ws:\/\/127\.0\.0\.1:4500<\/string>/);
  assert.match(appServer.contents, /<string>capability-token<\/string>/);
  assert.match(relay.contents, /<string>--history-url<\/string>/);
  assert.match(relay.contents, /<string>ws:\/\/127\.0\.0\.1:4500\/<\/string>/);
  assert.match(relay.contents, /<string>--phone-auth<\/string>/);
  assert.match(relay.contents, /<string>none<\/string>/);
  assert.match(relay.contents, /<string>--host-id<\/string>/);
  assert.match(relay.contents, /<string>home<\/string>/);
  assert.match(relay.contents, /<string>--host-name<\/string>/);
  assert.match(relay.contents, /<string>Home<\/string>/);
});

test("Linux render emits systemd user services without requiring systemd to run", () => {
  const config = makeConfig({
    platform: "linux",
    options: {
      "public-host": "100.66.11.7",
      "network-profile": "lan",
    },
  });
  const files = renderHostServices(config);
  const appServer = files.find((file) => file.role === "raw-app-server");
  const relay = files.find((file) => file.role === "dock-relay");

  assert.equal(config.serviceManager, "systemd-user");
  assert.equal(appServer.path.endsWith("codex-dock-app-server.service"), true);
  assert.equal(relay.path.endsWith("codex-dock-relay.service"), true);
  assert.match(appServer.contents, /\[Service\]/);
  assert.match(appServer.contents, /ExecStart=\/usr\/local\/bin\/codex app-server --listen ws:\/\/127\.0\.0\.1:4500/);
  assert.match(relay.contents, /After=codex-dock-app-server\.service/);
  assert.match(relay.contents, /--history-auth-token-file/);
  assert.match(relay.contents, /Restart=always/);
});

test("app-config output is app-facing and non-secret", () => {
  const config = makeConfig({
    options: {
      "raw-token-file": "/tmp/secret/app-server.token",
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

test("install writes service files creates a token and calls launchd through an injected runner", async () => {
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
  const tokenPath = path.join(cwd, ".codex-dock-test", "app-server.token");
  const tokenText = fs.readFileSync(tokenPath, "utf8").trim();
  const mode = fs.statSync(tokenPath).mode & 0o777;

  assert.equal(parsed.status, "installed");
  assert.equal(parsed.appServerAuth.created, true);
  assert.equal(mode, 0o600);
  assert.equal(tokenText.length > 20, true);
  assert.equal(output.stdout().includes(tokenText), false);
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
  assert.equal(fs.existsSync(path.join(cwd, ".codex-dock-test", "services", "com.aelaguiz.codex-dock.app-server.plist")), true);
  assert.deepEqual(runner.calls.map((call) => [call.command, call.args[0], call.args[1]]), [
    ["launchctl", "print", "gui/501/com.aelaguiz.codex-dock.app-server"],
    ["launchctl", "bootout", "gui/501/com.aelaguiz.codex-dock.app-server"],
    ["launchctl", "bootstrap", "gui/501"],
    ["launchctl", "print", "gui/501/com.aelaguiz.codex-dock.relay"],
    ["launchctl", "bootout", "gui/501/com.aelaguiz.codex-dock.relay"],
    ["launchctl", "bootstrap", "gui/501"],
  ]);
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
  const appServerPath = path.join(cwd, ".codex-dock-test", "services", "com.aelaguiz.codex-dock.app-server.plist");
  const relayPath = path.join(cwd, ".codex-dock-test", "services", "com.aelaguiz.codex-dock.relay.plist");
  const runner = fakeRunner((command, args) => {
    if (command === "launchctl" && args[0] === "print" && args[1].includes("app-server")) {
      return { exitCode: 0, stdout: `path = ${appServerPath}\nstate = running\n`, stderr: "" };
    }
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

test("install reuses an existing token and systemd install does not start services", async () => {
  const cwd = tempDir();
  const tokenPath = path.join(cwd, ".codex-dock-test", "app-server.token");
  fs.mkdirSync(path.dirname(tokenPath), { recursive: true });
  fs.writeFileSync(tokenPath, "existing-token\n", { mode: 0o644 });
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
  const mode = fs.statSync(tokenPath).mode & 0o777;

  assert.equal(parsed.status, "installed");
  assert.equal(parsed.appServerAuth.created, false);
  assert.equal(fs.readFileSync(tokenPath, "utf8"), "existing-token\n");
  assert.equal(mode, 0o600);
  assert.deepEqual(runner.calls.map((call) => call.args.slice(0, 3)), [
    ["--user", "link", "--force"],
    ["--user", "daemon-reload"],
    ["--user", "enable", "codex-dock-app-server.service"],
  ]);
  assert.equal(runner.calls[0].args.includes(path.join(cwd, ".codex-dock-test", "services", "codex-dock-app-server.service")), true);
  assert.equal(runner.calls[0].args.includes(path.join(cwd, ".codex-dock-test", "services", "codex-dock-relay.service")), true);
  assert.equal(JSON.stringify(runner.calls).includes("--now"), false);
  assert.equal(JSON.stringify(runner.calls).includes('"start"'), false);
});

test("systemd start and stop respect app-server before relay dependency order", async () => {
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
    ["--user", "start", "codex-dock-app-server.service"],
    ["--user", "start", "codex-dock-relay.service"],
  ]);
  assert.deepEqual(stopRunner.calls.map((call) => call.args.slice(0, 3)), [
    ["--user", "stop", "codex-dock-relay.service"],
    ["--user", "stop", "codex-dock-app-server.service"],
  ]);
});

test("macOS start reuses loaded launchd services without kickstarting them", async () => {
  const cwd = tempDir();
  const runner = fakeRunner((command, args) => {
    if (command === "launchctl" && args[0] === "print") {
      const servicePath = args[1].endsWith(".app-server")
        ? path.join(cwd, ".codex-dock-test", "services", "com.aelaguiz.codex-dock.app-server.plist")
        : path.join(cwd, ".codex-dock-test", "services", "com.aelaguiz.codex-dock.relay.plist");
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
  ]);
});

test("macOS start re-bootstraps loaded launchd services that are not running", async () => {
  const cwd = tempDir();
  const runner = fakeRunner((command, args) => {
    if (command === "launchctl" && args[0] === "print") {
      const servicePath = args[1].endsWith(".app-server")
        ? path.join(cwd, ".codex-dock-test", "services", "com.aelaguiz.codex-dock.app-server.plist")
        : path.join(cwd, ".codex-dock-test", "services", "com.aelaguiz.codex-dock.relay.plist");
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
    ["launchctl", "bootout", "gui/501/com.aelaguiz.codex-dock.app-server"],
    ["launchctl", "bootstrap", "gui/501"],
    ["launchctl", "kickstart", "gui/501/com.aelaguiz.codex-dock.app-server"],
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
    if (args.includes("codex-dock-app-server.service") || args.includes("codex-dock-relay.service")) {
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
        history: {
          url: "ws://user:pass@127.0.0.1:4500?token=secret",
          lastHealth: { ok: true, status: "up" },
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
  assert.equal(parsed.services.length, 2);
  assert.equal(parsed.health.length, 4);
  assert.equal(text.includes("app-server.token"), false);
  assert.equal(text.includes("user:pass"), false);
  assert.equal(text.includes("token=secret"), false);
  assertNoForbiddenSecrets(text);
  assert.equal(parsed.health[2].body, "<redacted-payload>");
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
  fs.writeFileSync(path.join(logDir, "app-server.log"), `Bearer app-server-secret-token\ntranscript private transcript\n${secretLogFixture}\n`);
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
  assert.equal(runner.calls.length, 2);
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

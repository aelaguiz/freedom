import assert from "node:assert/strict";
import test from "node:test";

import {
  assertRelayConfigMatches,
  buildRelayConfigFromHostEnv,
  buildRelayConfig,
  parseEndpointList,
} from "./device-relay-config.mjs";

test("device relay config writes relay instance identity and multiple endpoints", () => {
  assert.deepEqual(
    buildRelayConfig({
      relayInstanceID: "Amir-M5",
      endpoints: "amir-m5.fairy-salmon.ts.net:4510,home.fairy-salmon.ts.net:4510",
    }),
    {
      relayInstanceID: "Amir-M5",
      endpoints: [
        { host: "amir-m5.fairy-salmon.ts.net", port: 4510 },
        { host: "home.fairy-salmon.ts.net", port: 4510 },
      ],
    },
  );
});

test("device relay config parses bracketed IPv6 endpoints", () => {
  assert.deepEqual(
    parseEndpointList("[fd7a:115c:a1e0::1]:4510"),
    [{ host: "fd7a:115c:a1e0::1", port: 4510 }],
  );
});

test("device relay config verification ignores JSON object key order", () => {
  assert.doesNotThrow(() => assertRelayConfigMatches(
    {
      relayInstanceID: "Amir-M5",
      endpoints: [
        { port: 4510, host: "Amir-M5.local" },
        { port: 4510, host: "192.168.50.74" },
      ],
    },
    buildRelayConfig({
      relayInstanceID: "Amir-M5",
      endpoints: "Amir-M5.local:4510,192.168.50.74:4510",
    }),
  ));
});

test("device relay config verification still fails on missing relay identity", () => {
  assert.throws(
    () => assertRelayConfigMatches(
      {
        endpoints: [
          { port: 4510, host: "Amir-M5.local" },
          { port: 4510, host: "192.168.50.74" },
        ],
      },
      buildRelayConfig({
        relayInstanceID: "Amir-M5",
        endpoints: "Amir-M5.local:4510,192.168.50.74:4510",
      }),
    ),
    /relayInstanceID/,
  );
});

test("host env verification accepts only app-facing relay config", () => {
  assert.deepEqual(
    buildRelayConfigFromHostEnv([
      "CODEX_DOCK_HOSTS=amir-m5.fairy-salmon.ts.net:4510,home.fairy-salmon.ts.net:4510",
      "CODEX_DOCK_RELAY_INSTANCE_ID=Amir-M5",
      "",
    ].join("\n")),
    {
      relayInstanceID: "Amir-M5",
      endpoints: [
        { host: "amir-m5.fairy-salmon.ts.net", port: 4510 },
        { host: "home.fairy-salmon.ts.net", port: 4510 },
      ],
    },
  );
});

test("host env verification rejects secrets and raw app-server endpoints", () => {
  assert.throws(
    () => buildRelayConfigFromHostEnv([
      "CODEX_DOCK_HOSTS=home.local:4510",
      "CODEX_DOCK_RELAY_INSTANCE_ID=home",
      "OPENAI_API_KEY=secret",
      "",
    ].join("\n")),
    /secret-looking key/,
  );
  assert.throws(
    () => buildRelayConfigFromHostEnv([
      "CODEX_DOCK_HOSTS=127.0.0.1:4500",
      "CODEX_DOCK_RELAY_INSTANCE_ID=home",
      "",
    ].join("\n")),
    /raw Codex app-server/,
  );
});

test("device relay config rejects unsafe endpoint strings", () => {
  assert.throws(
    () => parseEndpointList("ws://home.local:4510"),
    /must be host:port/,
  );
  assert.throws(
    () => parseEndpointList("token@home.local:4510"),
    /no scheme, path, query, username, or password/,
  );
  assert.throws(
    () => parseEndpointList("home.local:4510,home.local:4510"),
    /must not contain duplicates/,
  );
  assert.throws(
    () => parseEndpointList("127.0.0.1:4500"),
    /raw Codex app-server/,
  );
});

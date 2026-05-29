import assert from "node:assert/strict";
import test from "node:test";

import {
  assertRelayConfigMatches,
  buildRelayConfigFromHostEnv,
  buildRelayConfig,
  parseHostList,
} from "./device-relay-config.mjs";

test("device relay config writes host list without relay identity", () => {
  assert.deepEqual(
    buildRelayConfig({
      hosts: "amir-m5.fairy-salmon.ts.net:4510,home.fairy-salmon.ts.net:4510",
    }),
    {
      hosts: [
        { host: "amir-m5.fairy-salmon.ts.net", port: 4510 },
        { host: "home.fairy-salmon.ts.net", port: 4510 },
      ],
    },
  );
});

test("device relay config parses bracketed IPv6 hosts", () => {
  assert.deepEqual(
    parseHostList("[fd7a:115c:a1e0::1]:4510"),
    [{ host: "fd7a:115c:a1e0::1", port: 4510 }],
  );
});

test("device relay config verification ignores JSON object key order", () => {
  assert.doesNotThrow(() => assertRelayConfigMatches(
    {
      hosts: [
        { port: 4510, host: "Amir-M5.local" },
        { port: 4510, host: "192.168.50.74" },
      ],
    },
    buildRelayConfig({
      hosts: "Amir-M5.local:4510,192.168.50.74:4510",
    }),
  ));
});

test("device relay config verification fails on old endpoint-list JSON", () => {
  assert.throws(
    () => assertRelayConfigMatches(
      {
        relayInstanceID: "Amir-M5",
        endpoints: [
          { port: 4510, host: "Amir-M5.local" },
          { port: 4510, host: "192.168.50.74" },
        ],
      },
      buildRelayConfig({
        hosts: "Amir-M5.local:4510,192.168.50.74:4510",
      }),
    ),
    /unexpected key: endpoints/,
  );
});

test("device relay config verification fails on extra phone identity", () => {
  assert.throws(
    () => assertRelayConfigMatches(
      {
        hosts: [{ host: "Amir-M5.local", port: 4510 }],
        relayInstanceID: "Amir-M5",
      },
      buildRelayConfig({
        hosts: "Amir-M5.local:4510",
      }),
    ),
    /unexpected key: relayInstanceID/,
  );
});

test("host env verification accepts only app-facing relay hosts", () => {
  assert.deepEqual(
    buildRelayConfigFromHostEnv([
      "CODEX_DOCK_HOSTS=amir-m5.fairy-salmon.ts.net:4510,home.fairy-salmon.ts.net:4510",
      "",
    ].join("\n")),
    {
      hosts: [
        { host: "amir-m5.fairy-salmon.ts.net", port: 4510 },
        { host: "home.fairy-salmon.ts.net", port: 4510 },
      ],
    },
  );
});

test("host env verification rejects phone-side relay identity", () => {
  assert.throws(
    () => buildRelayConfigFromHostEnv([
      "CODEX_DOCK_HOSTS=amir-m5.fairy-salmon.ts.net:4510",
      "CODEX_DOCK_RELAY_INSTANCE_ID=Amir-M5",
      "",
    ].join("\n")),
    /phone-side relay identity/,
  );
});

test("host env verification rejects secrets and raw app-server hosts", () => {
  assert.throws(
    () => buildRelayConfigFromHostEnv([
      "CODEX_DOCK_HOSTS=home.local:4510",
      "OPENAI_API_KEY=secret",
      "",
    ].join("\n")),
    /secret-looking key/,
  );
  assert.throws(
    () => buildRelayConfigFromHostEnv([
      "CODEX_DOCK_HOSTS=127.0.0.1:4500",
      "",
    ].join("\n")),
    /raw Codex app-server/,
  );
});

test("device relay config rejects unsafe host strings", () => {
  assert.throws(
    () => parseHostList("ws://home.local:4510"),
    /must be host:port/,
  );
  assert.throws(
    () => parseHostList("token@home.local:4510"),
    /no scheme, path, query, username, or password/,
  );
  assert.throws(
    () => parseHostList("home.local:4510,home.local:4510"),
    /must not contain duplicates/,
  );
  assert.throws(
    () => parseHostList("127.0.0.1:4500"),
    /raw Codex app-server/,
  );
});

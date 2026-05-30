import fs from "node:fs";
import process from "node:process";

import { DEFAULT_PHONE_AUTH } from "./dock-relay-constants.mjs";

function readToken(path) {
  const value = fs.readFileSync(path, "utf8").trim();
  if (!value) {
    throw new Error(`token file is empty: ${path}`);
  }
  return value;
}

function loadDotEnvFile(path = ".env", environment = process.env) {
  if (!fs.existsSync(path)) {
    return {};
  }

  const loaded = {};
  const text = fs.readFileSync(path, "utf8");
  for (const rawLine of text.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith("#")) {
      continue;
    }

    const match = line.match(/^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/);
    if (!match) {
      continue;
    }

    const key = match[1];
    let value = match[2].trim();
    if (
      (value.startsWith('"') && value.endsWith('"'))
      || (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    loaded[key] = value;
    if (environment[key] === undefined) {
      environment[key] = value;
    }
  }
  return loaded;
}

function parsePhoneAuthMode(value) {
  const mode = String(value || DEFAULT_PHONE_AUTH).toLowerCase();
  if (mode !== "none" && mode !== "bearer") {
    throw new Error("--phone-auth must be none or bearer");
  }
  return mode;
}

export {
  loadDotEnvFile,
  parsePhoneAuthMode,
  readToken,
};

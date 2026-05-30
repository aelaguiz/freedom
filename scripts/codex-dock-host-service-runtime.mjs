import crypto from "node:crypto";
import fs from "node:fs";
import http from "node:http";
import https from "node:https";
import path from "node:path";
import { spawn } from "node:child_process";

import { HEALTH_TIMEOUT_MS } from "./dock-relay-constants.mjs";

const REDACTED = "<redacted>";
const REDACTED_PAYLOAD = "<redacted-payload>";
const SENSITIVE_KEY_PATTERN = /(authorization|bearer|token|secret|password|api[_-]?key|apikey|openai[_-]?.*key|cookie|set-cookie|session|sessionid|sid|headers|base64[_-]?audio|audio|transcript|prompt|delta[_-]?text|partial[_-]?text)/i;
const SENSITIVE_PAYLOAD_KEY_PATTERN = /^(body|headers|params|payload|request|response)$/i;

function runCommand(command, args = [], options = {}) {
  return new Promise((resolve) => {
    const child = spawn(command, args, {
      cwd: options.cwd,
      env: options.env,
      stdio: ["ignore", "pipe", "pipe"],
    });
    const stdout = [];
    const stderr = [];
    child.stdout.on("data", (chunk) => stdout.push(chunk));
    child.stderr.on("data", (chunk) => stderr.push(chunk));
    child.on("error", (error) => {
      resolve({
        command,
        args,
        exitCode: 127,
        stdout: "",
        stderr: error.message,
        error,
      });
    });
    child.on("close", (exitCode) => {
      resolve({
        command,
        args,
        exitCode,
        stdout: Buffer.concat(stdout).toString("utf8"),
        stderr: Buffer.concat(stderr).toString("utf8"),
      });
    });
  });
}

function ensureDirectory(dir) {
  fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
}

function writeFileAtomic(filePath, contents, mode = 0o600) {
  ensureDirectory(path.dirname(filePath));
  const tempPath = path.join(path.dirname(filePath), `.${path.basename(filePath)}.${process.pid}.tmp`);
  fs.writeFileSync(tempPath, contents, { mode });
  fs.renameSync(tempPath, filePath);
  fs.chmodSync(filePath, mode);
}

function ensureTokenFile(filePath) {
  ensureDirectory(path.dirname(filePath));
  if (fs.existsSync(filePath)) {
    const existing = fs.readFileSync(filePath, "utf8").trim();
    if (existing) {
      fs.chmodSync(filePath, 0o600);
      return { created: false };
    }
  }
  const token = crypto.randomBytes(32).toString("base64url");
  writeFileAtomic(filePath, `${token}\n`, 0o600);
  return { created: true };
}

function readTextIfExists(filePath) {
  try {
    return fs.readFileSync(filePath, "utf8");
  } catch (error) {
    if (error?.code === "ENOENT") {
      return "";
    }
    throw error;
  }
}

function readTailTextIfExists(filePath, maxBytes = 1_048_576) {
  try {
    const stats = fs.statSync(filePath);
    const bytesToRead = Math.min(stats.size, maxBytes);
    const start = Math.max(0, stats.size - bytesToRead);
    const fd = fs.openSync(filePath, "r");
    try {
      const buffer = Buffer.alloc(bytesToRead);
      fs.readSync(fd, buffer, 0, bytesToRead, start);
      return buffer.toString("utf8");
    } finally {
      fs.closeSync(fd);
    }
  } catch (error) {
    if (error?.code === "ENOENT") {
      return "";
    }
    throw error;
  }
}

function tailText(text, maxLines = 200) {
  const lines = String(text).split(/\r?\n/);
  return lines.slice(Math.max(0, lines.length - maxLines)).join("\n");
}

function getJSON(url, timeoutMs = HEALTH_TIMEOUT_MS) {
  const client = String(url).startsWith("https:") ? https : http;
  return new Promise((resolve, reject) => {
    const request = client.get(url, { timeout: timeoutMs }, (response) => {
      const chunks = [];
      response.on("data", (chunk) => chunks.push(chunk));
      response.on("end", () => {
        const body = Buffer.concat(chunks).toString("utf8");
        let parsed = null;
        if (body) {
          try {
            parsed = JSON.parse(body);
          } catch {
            parsed = null;
          }
        }
        resolve({
          ok: response.statusCode >= 200 && response.statusCode < 300,
          statusCode: response.statusCode,
          body: parsed,
        });
      });
    });
    request.on("timeout", () => {
      request.destroy(new Error(`timed out after ${timeoutMs}ms`));
    });
    request.on("error", reject);
  });
}

function redactBasicSecrets(value) {
  return String(value)
    .replace(/Bearer\s+[A-Za-z0-9._~+/=-]+/gi, "Bearer <redacted>")
    .replace(/\b(set-cookie|cookie)\s*:\s*[^\r\n]+/gi, "$1: <redacted>")
    .replace(/\b(sessionid|session|sid)\s*=\s*[^ \r\n;,]+/gi, "$1=<redacted>")
    .replace(/(authorization|api[_-]?key|openai[_-]?api[_-]?key|token|secret)\s*[:=]\s*[^ \r\n;,]+/gi, "$1=<redacted>")
    .replace(/\b(base64[_-]?audio|audio|transcript|prompt|delta[_-]?text|partial[_-]?text)\b[^\r\n]*/gi, "$1 <redacted>")
    .replace(/sk-[A-Za-z0-9]{16,}/g, "sk-<redacted>")
    .replace(/\b[A-Za-z0-9+/]{120,}={0,2}\b/g, "<redacted-large-token>")
    .replace(/[^\s"']*(?:token|secret)[^\s"']*/gi, REDACTED);
}

function sanitizeJSONLine(line) {
  const trimmed = line.trim();
  if (!trimmed || (!trimmed.startsWith("{") && !trimmed.startsWith("["))) {
    return null;
  }
  try {
    const parsed = JSON.parse(trimmed);
    const redacted = JSON.stringify(redactValue(parsed));
    return line.replace(trimmed, redacted);
  } catch {
    return null;
  }
}

function sanitizeURL(value) {
  try {
    const url = new URL(String(value));
    url.username = "";
    url.password = "";
    url.search = "";
    url.hash = "";
    return redactBasicSecrets(url.toString());
  } catch {
    return redactBasicSecrets(value);
  }
}

function sanitizeString(value) {
  return String(value).split(/\r?\n/).map((line) => {
    const jsonLine = sanitizeJSONLine(line);
    if (jsonLine !== null) {
      return jsonLine;
    }
    return redactBasicSecrets(line.replace(/\b(?:wss?|https?):\/\/[^\s<>"']+/gi, (url) => sanitizeURL(url)));
  }).join("\n");
}

function redactValue(value, key = "", seen = new WeakSet()) {
  if (value === undefined) {
    return undefined;
  }
  if (key && SENSITIVE_PAYLOAD_KEY_PATTERN.test(key)) {
    return REDACTED_PAYLOAD;
  }
  if (key && SENSITIVE_KEY_PATTERN.test(key)) {
    return REDACTED;
  }
  if (value === null || typeof value === "number" || typeof value === "boolean") {
    return value;
  }
  if (typeof value === "string") {
    if (/url|endpoint|host/i.test(key)) {
      return sanitizeURL(value);
    }
    return sanitizeString(value);
  }
  if (value instanceof Error) {
    const output = {
      name: sanitizeString(value.name || "Error"),
      message: sanitizeString(value.message || String(value)),
    };
    if (value.code !== undefined) {
      output.code = redactValue(value.code, "code", seen);
    }
    return output;
  }
  if (Array.isArray(value)) {
    return value.map((item) => redactValue(item, key, seen));
  }
  if (typeof value === "object") {
    if (seen.has(value)) {
      return "<cycle>";
    }
    seen.add(value);
    const output = {};
    for (const [childKey, childValue] of Object.entries(value)) {
      const redacted = redactValue(childValue, childKey, seen);
      if (redacted !== undefined) {
        output[childKey] = redacted;
      }
    }
    seen.delete(value);
    return output;
  }
  return sanitizeString(value);
}

export {
  ensureDirectory,
  ensureTokenFile,
  getJSON,
  readTailTextIfExists,
  readTextIfExists,
  redactValue,
  runCommand,
  tailText,
  writeFileAtomic,
};

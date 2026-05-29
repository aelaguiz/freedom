import fs from "node:fs";
import process from "node:process";

const SERVICE_NAME = "codex-dock-relay";
const REDACTED = "<redacted>";
const REDACTED_PAYLOAD = "<redacted-payload>";
const MAX_STRING_LENGTH = 500;
const MAX_ARRAY_LENGTH = 20;
const MAX_OBJECT_KEYS = 40;

const SENSITIVE_KEY_PATTERN = /(^|[_-])(authorization|bearer|token|secret|password|api[_-]?key|apikey|openai[_-]?.*key|base64[_-]?audio|audio|transcript|prompt|delta[_-]?text|partial[_-]?text|headers)([_-]|$)/i;
const SENSITIVE_PAYLOAD_KEY_PATTERN = /^(body|headers|params|payload|request|response)$/i;

function clipString(value, maxLength = MAX_STRING_LENGTH) {
  if (value.length <= maxLength) {
    return value;
  }
  return `${value.slice(0, Math.max(0, maxLength - 3))}...`;
}

function redactString(value) {
  return clipString(String(value)
    .replace(/Bearer\s+[A-Za-z0-9._~+/=-]+/gi, "Bearer <redacted>")
    .replace(/(authorization|api[_-]?key|openai[_-]?api[_-]?key|token|secret)\s*[:=]\s*[^ \r\n;,]+/gi, "$1=<redacted>")
    .replace(/sk-[A-Za-z0-9]{16,}/g, "sk-<redacted>")
    .replace(/\b[A-Za-z0-9+/]{120,}={0,2}\b/g, "<redacted-large-token>"));
}

function sanitizeUrl(value) {
  try {
    const url = new URL(String(value));
    url.username = "";
    url.password = "";
    url.search = "";
    url.hash = "";
    return redactString(url.toString());
  } catch {
    return redactString(value);
  }
}

function sanitizeError(error) {
  const result = {
    name: redactString(error?.name || "Error"),
    message: redactString(error?.message || String(error)),
  };
  if (error?.code !== undefined) {
    result.code = sanitizeValue(error.code, "code");
  }
  return result;
}

function sanitizeValue(value, key = "", seen = new WeakSet()) {
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
  if (typeof value === "bigint") {
    return value.toString();
  }
  if (typeof value === "string") {
    if (/url|endpoint|host/i.test(key)) {
      return sanitizeUrl(value);
    }
    return redactString(value);
  }
  if (value instanceof URL) {
    return sanitizeUrl(value.toString());
  }
  if (value instanceof Error) {
    return sanitizeError(value);
  }
  if (Buffer.isBuffer(value) || value instanceof Uint8Array) {
    return `<redacted-bytes length=${value.byteLength}>`;
  }
  if (Array.isArray(value)) {
    return value
      .slice(0, MAX_ARRAY_LENGTH)
      .map((item) => sanitizeValue(item, key, seen));
  }
  if (typeof value === "object") {
    if (seen.has(value)) {
      return "<cycle>";
    }
    seen.add(value);
    const output = {};
    for (const [childKey, childValue] of Object.entries(value).slice(0, MAX_OBJECT_KEYS)) {
      const sanitized = sanitizeValue(childValue, childKey, seen);
      if (sanitized !== undefined) {
        output[childKey] = sanitized;
      }
    }
    seen.delete(value);
    return output;
  }
  return redactString(String(value));
}

function sanitizeFields(fields = {}) {
  const output = {};
  for (const [key, value] of Object.entries(fields || {})) {
    const sanitized = sanitizeValue(value, key);
    if (sanitized !== undefined) {
      output[key] = sanitized;
    }
  }
  return output;
}

function writeRecord(stream, record) {
  const line = `${JSON.stringify(record)}\n`;
  if (typeof stream.write === "function") {
    stream.write(line);
    return;
  }
  fs.writeSync(process.stderr.fd, line);
}

function writeRecordSync(stream, record) {
  const line = `${JSON.stringify(record)}\n`;
  if (typeof stream.fd === "number") {
    fs.writeSync(stream.fd, line);
    return;
  }
  if (typeof stream.write === "function") {
    stream.write(line);
    return;
  }
  fs.writeSync(process.stderr.fd, line);
}

function createRelayLogger({
  stream = process.stderr,
  clock = () => new Date(),
} = {}) {
  function record(level, event, fields = {}, sync = false) {
    const timestamp = clock();
    const payload = {
      timestamp: timestamp instanceof Date ? timestamp.toISOString() : new Date(timestamp).toISOString(),
      level,
      service: SERVICE_NAME,
      event: redactString(event),
      fields: sanitizeFields(fields),
    };
    if (sync) {
      writeRecordSync(stream, payload);
    } else {
      writeRecord(stream, payload);
    }
  }

  return {
    debug(event, fields) {
      record("debug", event, fields);
    },
    info(event, fields) {
      record("info", event, fields);
    },
    warn(event, fields) {
      record("warn", event, fields);
    },
    error(event, fields) {
      record("error", event, fields);
    },
    fault(event, fields) {
      record("fault", event, fields);
    },
    fatalSync(event, fields) {
      record("fault", event, fields, true);
    },
  };
}

const defaultRelayLogger = createRelayLogger();

function installRelayFatalHandlers(logger = defaultRelayLogger) {
  process.once("uncaughtException", (error) => {
    logger.fatalSync("process.uncaught_exception", { error });
    process.exit(1);
  });
  process.once("unhandledRejection", (reason) => {
    logger.fatalSync("process.unhandled_rejection", {
      error: reason instanceof Error ? reason : new Error(String(reason)),
    });
    process.exit(1);
  });
}

export {
  createRelayLogger,
  defaultRelayLogger,
  installRelayFatalHandlers,
  redactString,
  sanitizeFields,
};

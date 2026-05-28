const DEFAULT_TRANSCRIPTION_MODEL = "gpt-4o-transcribe";
const DEFAULT_TRANSCRIPTION_TIMEOUT_MS = 30_000;
const DEFAULT_TRANSCRIPTION_MAX_BYTES = 10 * 1024 * 1024;
const DEFAULT_TRANSCRIPTION_ENDPOINT = "https://api.openai.com/v1/audio/transcriptions";

const SUPPORTED_AUDIO_MIME_TYPES = new Set([
  "audio/aac",
  "audio/mp4",
  "audio/mpeg",
  "audio/m4a",
  "audio/wav",
  "audio/webm",
  "audio/x-m4a",
]);

function parsePositiveInteger(value, fallback) {
  const number = Number(value);
  if (!Number.isFinite(number) || number <= 0) {
    return fallback;
  }
  return Math.floor(number);
}

function jsonRpcRequestError(code, message) {
  return Object.assign(new Error(message), { code });
}

function decodedAudioTranscribeParams(params = {}, maxBytes = DEFAULT_TRANSCRIPTION_MAX_BYTES) {
  if (!params || typeof params !== "object" || Array.isArray(params)) {
    throw jsonRpcRequestError(-32602, "audio/transcribe requires object params");
  }
  if (params.model !== undefined) {
    throw jsonRpcRequestError(-32602, "audio/transcribe model is configured on the relay");
  }

  const mimeType = String(params.mimeType || "").trim().toLowerCase();
  if (!SUPPORTED_AUDIO_MIME_TYPES.has(mimeType)) {
    throw jsonRpcRequestError(-32602, "audio/transcribe requires a supported audio mimeType");
  }

  const base64Audio = String(params.base64Audio || "").replace(/\s+/g, "");
  if (!base64Audio || base64Audio.length % 4 !== 0 || !/^[A-Za-z0-9+/]+={0,2}$/.test(base64Audio)) {
    throw jsonRpcRequestError(-32602, "audio/transcribe requires base64Audio");
  }

  const approximateBytes = Math.floor((base64Audio.length * 3) / 4);
  if (approximateBytes > maxBytes + 2) {
    throw jsonRpcRequestError(-32602, "audio/transcribe audio payload is too large");
  }

  const bytes = Buffer.from(base64Audio, "base64");
  if (!bytes.length) {
    throw jsonRpcRequestError(-32602, "audio/transcribe requires non-empty audio");
  }
  if (bytes.length > maxBytes) {
    throw jsonRpcRequestError(-32602, "audio/transcribe audio payload is too large");
  }

  return { mimeType, bytes };
}

async function transcribeAudio(config, params = {}) {
  const maxBytes = parsePositiveInteger(
    config.transcriptionMaxBytes,
    DEFAULT_TRANSCRIPTION_MAX_BYTES,
  );
  const { mimeType, bytes } = decodedAudioTranscribeParams(params, maxBytes);
  const apiKey = config.openAIAPIKey || process.env.OPENAI_API_KEY;
  if (!apiKey) {
    throw jsonRpcRequestError(-32000, "OpenAI transcription key is not configured on the relay");
  }

  const model = config.openAITranscriptionModel || DEFAULT_TRANSCRIPTION_MODEL;
  const endpoint = config.openAITranscriptionEndpoint || DEFAULT_TRANSCRIPTION_ENDPOINT;
  const fetchFn = config.fetch || globalThis.fetch;
  if (typeof fetchFn !== "function") {
    throw jsonRpcRequestError(-32000, "relay runtime does not provide fetch");
  }

  const controller = new AbortController();
  const timeoutMs = parsePositiveInteger(
    config.transcriptionTimeoutMs,
    DEFAULT_TRANSCRIPTION_TIMEOUT_MS,
  );
  const timer = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const form = new FormData();
    form.set("model", model);
    form.set("response_format", "json");
    form.set("file", new Blob([bytes], { type: mimeType }), "recording.m4a");

    const response = await fetchFn(endpoint, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
      },
      body: form,
      signal: controller.signal,
    });

    if (!response || typeof response.ok !== "boolean") {
      throw jsonRpcRequestError(-32000, "OpenAI transcription returned an invalid response");
    }
    if (!response.ok) {
      throw jsonRpcRequestError(
        -32000,
        `OpenAI transcription failed with status ${response.status || "unknown"}`,
      );
    }

    const body = await response.json();
    const text = String(body?.text || "").trim();
    if (!text) {
      throw jsonRpcRequestError(-32000, "OpenAI transcription returned no text");
    }
    return { text };
  } catch (error) {
    if (error?.name === "AbortError") {
      throw jsonRpcRequestError(-32000, "OpenAI transcription timed out");
    }
    if (typeof error?.code === "number") {
      throw error;
    }
    throw jsonRpcRequestError(-32000, "OpenAI transcription request failed");
  } finally {
    clearTimeout(timer);
  }
}

export {
  DEFAULT_TRANSCRIPTION_ENDPOINT,
  DEFAULT_TRANSCRIPTION_MODEL,
  decodedAudioTranscribeParams,
  transcribeAudio,
};

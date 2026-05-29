import crypto from "node:crypto";
import WebSocket from "ws";

import {
  DEFAULT_REALTIME_TRANSCRIPTION_CONNECT_TIMEOUT_MS,
  DEFAULT_REALTIME_TRANSCRIPTION_DELAY,
  DEFAULT_REALTIME_TRANSCRIPTION_ENDPOINT,
  DEFAULT_REALTIME_TRANSCRIPTION_LANGUAGE,
  DEFAULT_REALTIME_TRANSCRIPTION_MAX_CHUNK_BYTES,
  DEFAULT_REALTIME_TRANSCRIPTION_MAX_DURATION_MS,
  DEFAULT_REALTIME_TRANSCRIPTION_MAX_PENDING_BYTES,
  DEFAULT_REALTIME_TRANSCRIPTION_MAX_TEXT_BYTES,
  DEFAULT_REALTIME_TRANSCRIPTION_MODEL,
  DEFAULT_REALTIME_TRANSCRIPTION_NON_SILENT_PEAK,
  DEFAULT_REALTIME_TRANSCRIPTION_SAMPLE_RATE,
} from "./dock-relay-constants.mjs";
import { defaultRelayLogger } from "./dock-relay-logger.mjs";

const SUPPORTED_REALTIME_TRANSCRIPTION_DELAYS = new Set([
  "minimal",
  "low",
  "medium",
  "high",
  "xhigh",
]);

const DEFAULT_SUPPORTED_REALTIME_TRANSCRIPTION_LANGUAGES = new Set(["en"]);

const FORBIDDEN_PHONE_PROVIDER_FIELDS = new Set([
  "OpenAI-Safety-Identifier",
  "apiKey",
  "authorization",
  "baseURL",
  "clientSecret",
  "endpoint",
  "headers",
  "model",
  "openAIAPIKey",
  "openAISafetyIdentifier",
  "providerHeaders",
  "safetyIdentifier",
  "sendOpenAIEvent",
  "url",
]);

function jsonRpcRequestError(code, message) {
  return Object.assign(new Error(message), { code });
}

function parsePositiveInteger(value, fallback) {
  const number = Number(value);
  if (!Number.isFinite(number) || number <= 0) {
    return fallback;
  }
  return Math.floor(number);
}

function parseStringSet(value, fallback) {
  if (!value) {
    return new Set(fallback);
  }
  const values = String(value)
    .split(",")
    .map((item) => item.trim().toLowerCase())
    .filter(Boolean);
  return values.length ? new Set(values) : new Set(fallback);
}

function assertPlainObject(params, method) {
  if (!params || typeof params !== "object" || Array.isArray(params)) {
    throw jsonRpcRequestError(-32602, `${method} requires object params`);
  }
}

function assertNoPhoneProviderConfig(params, method) {
  for (const key of Object.keys(params || {})) {
    if (FORBIDDEN_PHONE_PROVIDER_FIELDS.has(key)) {
      throw jsonRpcRequestError(-32602, `${method} provider configuration is relay-owned`);
    }
  }
}

function normalizedBase64Audio(value, maxBytes, method) {
  const base64Audio = String(value || "").replace(/\s+/g, "");
  if (!base64Audio || base64Audio.length % 4 !== 0 || !/^[A-Za-z0-9+/]+={0,2}$/.test(base64Audio)) {
    throw jsonRpcRequestError(-32602, `${method} requires base64Audio`);
  }

  const approximateBytes = Math.floor((base64Audio.length * 3) / 4);
  if (approximateBytes > maxBytes + 2) {
    throw jsonRpcRequestError(-32602, `${method} audio chunk is too large`);
  }

  const bytes = Buffer.from(base64Audio, "base64");
  if (!bytes.length) {
    throw jsonRpcRequestError(-32602, `${method} requires non-empty audio`);
  }
  if (bytes.length > maxBytes) {
    throw jsonRpcRequestError(-32602, `${method} audio chunk is too large`);
  }
  return {
    base64Audio,
    byteLength: bytes.length,
    audioStats: pcm16MonoAudioStats(bytes),
  };
}

function base64AudioStats(value) {
  const encodedCharacters = String(value || "").replace(/\s+/g, "").length;
  return {
    encodedCharacters,
    estimatedBytes: Math.floor((encodedCharacters * 3) / 4),
  };
}

function pcm16MonoAudioStats(bytes) {
  const sampleCount = Math.floor(bytes.length / 2);
  if (!sampleCount) {
    return {
      sampleCount: 0,
      peakAbs: 0,
      rms: 0,
    };
  }

  let peakAbs = 0;
  let sumSquares = 0;
  for (let index = 0; index < sampleCount * 2; index += 2) {
    const sample = bytes.readInt16LE(index);
    const absoluteSample = Math.abs(sample);
    peakAbs = Math.max(peakAbs, absoluteSample);
    sumSquares += sample * sample;
  }

  return {
    sampleCount,
    peakAbs,
    rms: Math.round(Math.sqrt(sumSquares / sampleCount)),
  };
}

function appendAudioValidationReason(error) {
  const message = String(error?.message || "");
  if (message.includes("too large")) {
    return "chunk_too_large";
  }
  if (message.includes("non-empty")) {
    return "empty_audio";
  }
  if (message.includes("base64Audio")) {
    return "invalid_audio";
  }
  return "invalid_audio";
}

function buildRealtimeTranscriptionUrl(endpoint) {
  let url;
  try {
    url = new URL(endpoint || DEFAULT_REALTIME_TRANSCRIPTION_ENDPOINT);
  } catch {
    throw jsonRpcRequestError(-32000, "OpenAI Realtime transcription endpoint is invalid");
  }
  if (url.protocol !== "wss:") {
    throw jsonRpcRequestError(-32000, "OpenAI Realtime transcription endpoint must use wss");
  }
  url.searchParams.set("intent", "transcription");
  url.searchParams.delete("model");
  return url.toString();
}

function safeText(value) {
  return String(value || "").slice(0, DEFAULT_REALTIME_TRANSCRIPTION_MAX_TEXT_BYTES);
}

function waitForWebSocketOpen(ws, timeoutMs) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      cleanup();
      try {
        ws.close();
      } catch {
        // Ignore close failures after a timed-out connection attempt.
      }
      reject(jsonRpcRequestError(-32000, "OpenAI Realtime transcription connection timed out"));
    }, timeoutMs);

    function cleanup() {
      clearTimeout(timer);
      ws.off("open", onOpen);
      ws.off("error", onError);
      ws.off("close", onClose);
    }

    function onOpen() {
      cleanup();
      resolve();
    }

    function onError() {
      cleanup();
      reject(jsonRpcRequestError(-32000, "OpenAI Realtime transcription connection failed"));
    }

    function onClose() {
      cleanup();
      reject(jsonRpcRequestError(-32000, "OpenAI Realtime transcription connection closed"));
    }

    ws.once("open", onOpen);
    ws.once("error", onError);
    ws.once("close", onClose);
  });
}

// This manager is a narrow transcription bridge, not a generic OpenAI event proxy.
class RealtimeTranscriptionManager {
  constructor(config, options = {}) {
    this.config = config;
    this.sendNotification = options.sendNotification;
    this.logger = options.logger || config.logger || defaultRelayLogger;
    this.activeSession = null;
  }

  async start(params = {}) {
    const startedAt = Date.now();
    assertPlainObject(params, "audio/transcription/start");
    assertNoPhoneProviderConfig(params, "audio/transcription/start");
    if (this.activeSession) {
      this.logger.warn("transcription.start_rejected", {
        reason: "active_session_exists",
        activeSessionId: this.activeSession.id,
      });
      throw jsonRpcRequestError(-32000, "audio/transcription/start already has an active session");
    }

    const apiKey = this.config.openAIAPIKey;
    if (!apiKey) {
      this.logger.warn("transcription.start_rejected", {
        reason: "missing_api_key",
      });
      throw jsonRpcRequestError(-32000, "OpenAI Realtime transcription key is not configured on the relay");
    }

    const model = this.config.openAIRealtimeTranscriptionModel
      || DEFAULT_REALTIME_TRANSCRIPTION_MODEL;
    const language = this.validatedLanguage(params.language);
    const delay = this.validatedDelay(params.delay);
    const endpoint = buildRealtimeTranscriptionUrl(
      this.config.openAIRealtimeTranscriptionEndpoint || DEFAULT_REALTIME_TRANSCRIPTION_ENDPOINT,
    );
    const connectTimeoutMs = parsePositiveInteger(
      this.config.realtimeTranscriptionConnectTimeoutMs,
      DEFAULT_REALTIME_TRANSCRIPTION_CONNECT_TIMEOUT_MS,
    );
    const maxChunkBytes = parsePositiveInteger(
      this.config.realtimeTranscriptionMaxChunkBytes,
      DEFAULT_REALTIME_TRANSCRIPTION_MAX_CHUNK_BYTES,
    );
    const maxPendingBytes = parsePositiveInteger(
      this.config.realtimeTranscriptionMaxPendingBytes,
      DEFAULT_REALTIME_TRANSCRIPTION_MAX_PENDING_BYTES,
    );
    const maxDurationMs = parsePositiveInteger(
      this.config.realtimeTranscriptionMaxDurationMs,
      DEFAULT_REALTIME_TRANSCRIPTION_MAX_DURATION_MS,
    );
    const headers = {
      Authorization: `Bearer ${apiKey}`,
    };
    if (this.config.openAISafetyIdentifier) {
      headers["OpenAI-Safety-Identifier"] = String(this.config.openAISafetyIdentifier);
    }

    const makeWebSocket = this.config.openAIRealtimeWebSocketFactory
      || ((url, options) => new WebSocket(url, options));
    const ws = makeWebSocket(endpoint, { headers });
    const session = {
      id: crypto.randomUUID(),
      ws,
      model,
      language,
      delay,
      lastSequence: 0,
      partials: new Map(),
      closing: false,
      maxDurationTimer: null,
      acceptedChunks: 0,
      acceptedBytes: 0,
      peakAbs: 0,
      maxRms: 0,
      nonSilentChunks: 0,
    };
    this.activeSession = session;
    this.logger.info("transcription.start_requested", {
      sessionId: session.id,
      endpoint,
      model,
      language,
      delay,
      sampleRate: DEFAULT_REALTIME_TRANSCRIPTION_SAMPLE_RATE,
      connectTimeoutMs,
      maxChunkBytes,
      maxPendingBytes,
      maxDurationMs,
      safetyIdentifierConfigured: Boolean(this.config.openAISafetyIdentifier),
    });

    try {
      await waitForWebSocketOpen(ws, connectTimeoutMs);
      this.attachUpstreamHandlers(session);
      this.armMaxDuration(session);
      this.sendUpstream(session, this.sessionUpdateEvent(session));
      this.logger.info("transcription.start_succeeded", {
        sessionId: session.id,
        model,
        language,
        delay,
        durationMs: Date.now() - startedAt,
      });
      return {
        sessionId: session.id,
        format: "audio/pcm",
        sampleRate: DEFAULT_REALTIME_TRANSCRIPTION_SAMPLE_RATE,
        model,
        language,
        delay,
      };
    } catch (error) {
      this.closeSession(session, "start_failed", { emitClosed: false });
      this.logger.error("transcription.start_failed", {
        sessionId: session.id,
        durationMs: Date.now() - startedAt,
        error,
      });
      throw error;
    }
  }

  append(params = {}) {
    assertPlainObject(params, "audio/transcription/append");
    assertNoPhoneProviderConfig(params, "audio/transcription/append");
    const session = this.requireActiveSession(params.sessionId, "audio/transcription/append");
    const sequence = Number(params.sequence);
    if (!Number.isInteger(sequence) || sequence <= session.lastSequence) {
      this.logger.warn("transcription.append_rejected", {
        sessionId: params.sessionId,
        sequence,
        lastSequence: session.lastSequence,
        reason: "invalid_sequence",
      });
      throw jsonRpcRequestError(-32602, "audio/transcription/append requires a monotonic sequence");
    }
    const maxBytes = parsePositiveInteger(
      this.config.realtimeTranscriptionMaxChunkBytes,
      DEFAULT_REALTIME_TRANSCRIPTION_MAX_CHUNK_BYTES,
    );
    let base64Audio;
    let byteLength;
    let audioStats;
    try {
      const normalized = normalizedBase64Audio(
        params.base64Audio,
        maxBytes,
        "audio/transcription/append",
      );
      base64Audio = normalized.base64Audio;
      byteLength = normalized.byteLength;
      audioStats = normalized.audioStats;
    } catch (error) {
      this.logger.warn("transcription.append_rejected", {
        sessionId: session.id,
        sequence,
        maxBytes,
        ...base64AudioStats(params.base64Audio),
        reason: appendAudioValidationReason(error),
      });
      throw error;
    }
    const maxPendingBytes = parsePositiveInteger(
      this.config.realtimeTranscriptionMaxPendingBytes,
      DEFAULT_REALTIME_TRANSCRIPTION_MAX_PENDING_BYTES,
    );
    if (session.ws.bufferedAmount + byteLength > maxPendingBytes) {
      this.logger.warn("transcription.append_rejected", {
        sessionId: session.id,
        sequence,
        bytes: byteLength,
        bufferedBytes: session.ws.bufferedAmount,
        maxPendingBytes,
        reason: "pending_audio_queue_full",
      });
      throw jsonRpcRequestError(-32000, "audio/transcription/append pending audio queue is full");
    }

    this.sendUpstream(session, {
      type: "input_audio_buffer.append",
      audio: base64Audio,
    });
    session.lastSequence = sequence;
    session.acceptedChunks += 1;
    session.acceptedBytes += byteLength;
    this.recordAudioStats(session, audioStats);
    this.logger.debug("transcription.append_accepted", {
      sessionId: session.id,
      sequence,
      bytes: byteLength,
      samples: audioStats.sampleCount,
      peakAbs: audioStats.peakAbs,
      rms: audioStats.rms,
      bufferedBytes: session.ws.bufferedAmount,
      acceptedChunks: session.acceptedChunks,
      acceptedBytes: session.acceptedBytes,
      sessionPeakAbs: session.peakAbs,
      sessionMaxRms: session.maxRms,
      nonSilentChunks: session.nonSilentChunks,
    });
    return { sessionId: session.id, acceptedSequence: sequence };
  }

  commit(params = {}) {
    assertPlainObject(params, "audio/transcription/commit");
    assertNoPhoneProviderConfig(params, "audio/transcription/commit");
    const session = this.requireActiveSession(params.sessionId, "audio/transcription/commit");
    this.logger.info("transcription.commit_requested", {
      sessionId: session.id,
      lastSequence: session.lastSequence,
      acceptedChunks: session.acceptedChunks,
      acceptedBytes: session.acceptedBytes,
      peakAbs: session.peakAbs,
      maxRms: session.maxRms,
      nonSilentChunks: session.nonSilentChunks,
    });
    this.sendUpstream(session, { type: "input_audio_buffer.commit" });
    this.logger.info("transcription.commit_sent", {
      sessionId: session.id,
      acceptedChunks: session.acceptedChunks,
      acceptedBytes: session.acceptedBytes,
      peakAbs: session.peakAbs,
      maxRms: session.maxRms,
      nonSilentChunks: session.nonSilentChunks,
    });
    return { sessionId: session.id, committed: true };
  }

  cancel(params = {}) {
    assertPlainObject(params, "audio/transcription/cancel");
    assertNoPhoneProviderConfig(params, "audio/transcription/cancel");
    const session = this.requireActiveSession(params.sessionId, "audio/transcription/cancel");
    this.logger.info("transcription.cancel_requested", {
      sessionId: session.id,
    });
    this.closeSession(session, "canceled", { emitCanceled: true });
    return { sessionId: session.id, canceled: true };
  }

  closeAll(reason = "closed") {
    if (this.activeSession) {
      this.logger.info("transcription.close_all", {
        sessionId: this.activeSession.id,
        reason,
      });
      this.closeSession(this.activeSession, reason, { emitClosed: true });
    }
  }

  validatedLanguage(value) {
    const language = String(
      value || this.config.realtimeTranscriptionLanguage || DEFAULT_REALTIME_TRANSCRIPTION_LANGUAGE,
    ).trim().toLowerCase();
    const allowed = parseStringSet(
      this.config.realtimeTranscriptionAllowedLanguages,
      DEFAULT_SUPPORTED_REALTIME_TRANSCRIPTION_LANGUAGES,
    );
    if (!allowed.has(language)) {
      throw jsonRpcRequestError(-32602, "audio/transcription/start language is not allowed");
    }
    return language;
  }

  validatedDelay(value) {
    const delay = String(
      value || this.config.realtimeTranscriptionDelay || DEFAULT_REALTIME_TRANSCRIPTION_DELAY,
    ).trim().toLowerCase();
    if (!SUPPORTED_REALTIME_TRANSCRIPTION_DELAYS.has(delay)) {
      throw jsonRpcRequestError(-32602, "audio/transcription/start delay is not allowed");
    }
    return delay;
  }

  requireActiveSession(sessionId, method) {
    const session = this.activeSession;
    if (!session || session.id !== sessionId || session.closing) {
      this.logger.warn("transcription.session_required_rejected", {
        sessionId,
        method,
        activeSessionId: session?.id || null,
        closing: Boolean(session?.closing),
      });
      throw jsonRpcRequestError(-32602, `${method} requires an active sessionId`);
    }
    if (session.ws.readyState !== WebSocket.OPEN) {
      this.logger.warn("transcription.session_required_rejected", {
        sessionId,
        method,
        reason: "upstream_not_open",
        readyState: session.ws.readyState,
      });
      throw jsonRpcRequestError(-32000, `${method} upstream session is not open`);
    }
    return session;
  }

  attachUpstreamHandlers(session) {
    session.ws.on("message", (data) => {
      this.handleUpstreamMessage(session, data);
    });
    session.ws.on("error", (error) => {
      this.logger.error("transcription.upstream_error", {
        sessionId: session.id,
        error,
      });
      this.failSession(session, "upstream_error");
    });
    session.ws.on("close", (code, reason) => {
      if (this.activeSession === session && !session.closing) {
        this.logger.warn("transcription.upstream_closed", {
          sessionId: session.id,
          code,
          reasonBytes: reason?.byteLength || 0,
        });
        this.failSession(session, "upstream_closed");
      }
    });
  }

  armMaxDuration(session) {
    const maxDurationMs = parsePositiveInteger(
      this.config.realtimeTranscriptionMaxDurationMs,
      DEFAULT_REALTIME_TRANSCRIPTION_MAX_DURATION_MS,
    );
    session.maxDurationTimer = setTimeout(() => {
      this.logger.warn("transcription.duration_exceeded", {
        sessionId: session.id,
        maxDurationMs,
      });
      this.failSession(session, "duration_exceeded");
    }, maxDurationMs);
    session.maxDurationTimer.unref?.();
  }

  sessionUpdateEvent(session) {
    return {
      type: "session.update",
      session: {
        type: "transcription",
        audio: {
          input: {
            format: {
              type: "audio/pcm",
              rate: DEFAULT_REALTIME_TRANSCRIPTION_SAMPLE_RATE,
            },
            transcription: {
              model: session.model,
              language: session.language,
              delay: session.delay,
            },
          },
        },
      },
    };
  }

  sendUpstream(session, event) {
    if (session.ws.readyState !== WebSocket.OPEN) {
      this.logger.warn("transcription.send_upstream_rejected", {
        sessionId: session.id,
        type: event?.type,
        readyState: session.ws.readyState,
      });
      throw jsonRpcRequestError(-32000, "OpenAI Realtime transcription upstream is not open");
    }
    session.ws.send(JSON.stringify(event));
    this.logger.debug("transcription.upstream_event_sent", {
      sessionId: session.id,
      type: event?.type,
    });
  }

  recordAudioStats(session, audioStats) {
    session.peakAbs = Math.max(session.peakAbs, audioStats.peakAbs);
    session.maxRms = Math.max(session.maxRms, audioStats.rms);
    if (audioStats.peakAbs >= DEFAULT_REALTIME_TRANSCRIPTION_NON_SILENT_PEAK) {
      session.nonSilentChunks += 1;
    }
  }

  handleUpstreamMessage(session, data) {
    if (this.activeSession !== session || session.closing) {
      return;
    }
    let event;
    try {
      event = JSON.parse(data.toString());
    } catch {
      this.logger.warn("transcription.invalid_upstream_json", {
        sessionId: session.id,
        bytes: data?.byteLength,
      });
      this.failSession(session, "invalid_upstream_event");
      return;
    }

    switch (event.type) {
      case "conversation.item.input_audio_transcription.delta":
        this.handleDelta(session, event);
        break;
      case "conversation.item.input_audio_transcription.completed":
        this.handleCompleted(session, event);
        break;
      case "error":
        this.logger.error("transcription.upstream_error_event", {
          sessionId: session.id,
          upstreamErrorType: event.error?.type || null,
          upstreamErrorCode: event.error?.code || null,
        });
        this.failSession(session, "upstream_error");
        break;
      default:
        this.logger.debug("transcription.upstream_event_ignored", {
          sessionId: session.id,
          type: event.type || "unknown",
        });
        break;
    }
  }

  handleDelta(session, event) {
    const itemId = String(event.item_id || "");
    const contentIndex = Number.isInteger(event.content_index) ? event.content_index : 0;
    const deltaText = safeText(event.delta);
    if (!itemId || !deltaText) {
      this.logger.warn("transcription.invalid_delta_event", {
        sessionId: session.id,
        itemId: Boolean(itemId),
        deltaCharacters: deltaText.length,
      });
      this.failSession(session, "invalid_upstream_event");
      return;
    }
    const key = `${itemId}:${contentIndex}`;
    const partialText = safeText(`${session.partials.get(key) || ""}${deltaText}`);
    session.partials.set(key, partialText);
    this.notify("audio/transcription/delta", {
      sessionId: session.id,
      itemId,
      contentIndex,
      deltaText,
      partialText,
    });
    this.logger.debug("transcription.delta_forwarded", {
      sessionId: session.id,
      itemId,
      contentIndex,
      deltaCharacters: deltaText.length,
      partialCharacters: partialText.length,
    });
  }

  handleCompleted(session, event) {
    const itemId = String(event.item_id || "");
    const contentIndex = Number.isInteger(event.content_index) ? event.content_index : 0;
    const key = `${itemId}:${contentIndex}`;
    const transcript = safeText(event.transcript || session.partials.get(key) || "");
    if (!itemId) {
      this.logger.warn("transcription.invalid_completed_event", {
        sessionId: session.id,
        itemId: Boolean(itemId),
        transcriptCharacters: transcript.length,
      });
      this.failSession(session, "invalid_upstream_event");
      return;
    }
    if (!transcript) {
      this.notify("audio/transcription/completed", {
        sessionId: session.id,
        itemId,
        contentIndex,
        transcript,
      });
      this.logger.info("transcription.completed_empty", {
        sessionId: session.id,
        itemId,
        contentIndex,
        acceptedChunks: session.acceptedChunks,
        acceptedBytes: session.acceptedBytes,
        peakAbs: session.peakAbs,
        maxRms: session.maxRms,
        nonSilentChunks: session.nonSilentChunks,
      });
      this.closeSession(session, "completed_empty", { emitClosed: true });
      return;
    }
    this.notify("audio/transcription/completed", {
      sessionId: session.id,
      itemId,
      contentIndex,
      transcript,
    });
    this.logger.info("transcription.completed_forwarded", {
      sessionId: session.id,
      itemId,
      contentIndex,
      transcriptCharacters: transcript.length,
      acceptedChunks: session.acceptedChunks,
      acceptedBytes: session.acceptedBytes,
      peakAbs: session.peakAbs,
      maxRms: session.maxRms,
      nonSilentChunks: session.nonSilentChunks,
    });
    this.closeSession(session, "completed", { emitClosed: true });
  }

  failSession(session, reason) {
    this.logger.warn("transcription.session_failed", {
      sessionId: session.id,
      reason,
      acceptedChunks: session.acceptedChunks,
      acceptedBytes: session.acceptedBytes,
      lastSequence: session.lastSequence,
      peakAbs: session.peakAbs,
      maxRms: session.maxRms,
      nonSilentChunks: session.nonSilentChunks,
    });
    this.closeSession(session, reason, { emitFailed: true });
  }

  closeSession(session, reason, options = {}) {
    if (this.activeSession !== session) {
      return;
    }
    session.closing = true;
    this.logger.info("transcription.session_closing", {
      sessionId: session.id,
      reason,
      emitFailed: Boolean(options.emitFailed),
      emitCanceled: Boolean(options.emitCanceled),
      emitClosed: options.emitClosed !== false,
      acceptedChunks: session.acceptedChunks,
      acceptedBytes: session.acceptedBytes,
      lastSequence: session.lastSequence,
      peakAbs: session.peakAbs,
      maxRms: session.maxRms,
      nonSilentChunks: session.nonSilentChunks,
    });
    if (session.maxDurationTimer) {
      clearTimeout(session.maxDurationTimer);
      session.maxDurationTimer = null;
    }

    if (options.emitFailed) {
      this.notify("audio/transcription/failed", {
        sessionId: session.id,
        reason,
      });
    }
    if (options.emitCanceled) {
      this.notify("audio/transcription/canceled", {
        sessionId: session.id,
      });
    }

    this.activeSession = null;
    try {
      if (session.ws.readyState === WebSocket.OPEN || session.ws.readyState === WebSocket.CONNECTING) {
        session.ws.close(1000, "transcription closed");
      }
    } catch {
      // The session is already being torn down; app-visible state is emitted above.
    }

    if (options.emitClosed !== false) {
      this.notify("audio/transcription/closed", {
        sessionId: session.id,
        reason,
      });
    }
  }

  notify(method, params) {
    if (typeof this.sendNotification === "function") {
      this.sendNotification(method, params);
    }
  }
}

export {
  DEFAULT_REALTIME_TRANSCRIPTION_DELAY,
  DEFAULT_REALTIME_TRANSCRIPTION_ENDPOINT,
  DEFAULT_REALTIME_TRANSCRIPTION_LANGUAGE,
  DEFAULT_REALTIME_TRANSCRIPTION_MODEL,
  DEFAULT_REALTIME_TRANSCRIPTION_SAMPLE_RATE,
  RealtimeTranscriptionManager,
  buildRealtimeTranscriptionUrl,
};

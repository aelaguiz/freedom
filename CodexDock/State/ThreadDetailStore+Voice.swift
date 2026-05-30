import Foundation

public struct ComposerState: Equatable, Sendable {
    public var draft: String
    public var isSending: Bool
    public var lastError: String?
    public var voice: ComposerVoiceState

    public init(
        draft: String = "",
        isSending: Bool = false,
        lastError: String? = nil,
        voice: ComposerVoiceState = ComposerVoiceState()
    ) {
        self.draft = draft
        self.isSending = isSending
        self.lastError = lastError
        self.voice = voice
    }

    public var canSend: Bool {
        !isSending
            && !voice.phase.isBusy
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var canEditDraft: Bool {
        !voice.phase.isBusy
    }

    public var canStartVoiceCapture: Bool {
        !isSending && !voice.phase.isBusy
    }
}

public struct ComposerRenderState: Equatable, Sendable {
    public let draft: String
    public let isSending: Bool
    public let lastError: String?
    public let voice: ComposerVoiceRenderState
    public let canSend: Bool
    public let canEditDraft: Bool
    public let canStartVoiceCapture: Bool

    public init(composer: ComposerState) {
        self.draft = composer.draft
        self.isSending = composer.isSending
        self.lastError = composer.lastError
        self.voice = ComposerVoiceRenderState(voice: composer.voice)
        self.canSend = composer.canSend
        self.canEditDraft = composer.canEditDraft
        self.canStartVoiceCapture = composer.canStartVoiceCapture
    }
}

public enum ComposerVoicePhase: Equatable, Sendable {
    case idle
    case starting
    case streaming
    case finalizing

    public var isBusy: Bool {
        self != .idle
    }

    public var label: String {
        switch self {
        case .idle:
            return "Dictate"
        case .starting:
            return "Starting"
        case .streaming:
            return "Listening"
        case .finalizing:
            return "Finalizing"
        }
    }
}

public enum ComposerVoiceInteractionMode: Equatable, Sendable {
    case hold
    case tap
}

public struct ComposerVoiceState: Equatable, Sendable {
    public var phase: ComposerVoicePhase
    public var interactionMode: ComposerVoiceInteractionMode?
    public var sessionID: String?
    public var activeSegmentID: String?
    public var provisionalTranscript: String?
    public var finalTranscript: String?
    public var lastError: String?

    public init(
        phase: ComposerVoicePhase = .idle,
        interactionMode: ComposerVoiceInteractionMode? = nil,
        sessionID: String? = nil,
        activeSegmentID: String? = nil,
        provisionalTranscript: String? = nil,
        finalTranscript: String? = nil,
        lastError: String? = nil
    ) {
        self.phase = phase
        self.interactionMode = interactionMode
        self.sessionID = sessionID
        self.activeSegmentID = activeSegmentID
        self.provisionalTranscript = provisionalTranscript
        self.finalTranscript = finalTranscript
        self.lastError = lastError
    }
}

public struct ComposerVoiceRenderState: Equatable, Sendable {
    public let phase: ComposerVoicePhase
    public let interactionMode: ComposerVoiceInteractionMode?
    public let sessionID: String?
    public let activeSegmentID: String?
    public let provisionalTranscript: String?
    public let finalTranscript: String?
    public let lastError: String?

    public init(voice: ComposerVoiceState) {
        self.phase = voice.phase
        self.interactionMode = voice.interactionMode
        self.sessionID = voice.sessionID
        self.activeSegmentID = voice.activeSegmentID
        self.provisionalTranscript = voice.provisionalTranscript
        self.finalTranscript = voice.finalTranscript
        self.lastError = voice.lastError
    }
}

struct ActiveDictationSegment {
    let id: String
    let baseDraft: String
    var transcript: String
}

struct VoiceForwardingSummary {
    var chunks = 0
    var bytes = 0
    var lastSequence = 0

    mutating func record(_ chunk: VoiceAudioChunk) {
        chunks += 1
        bytes += chunk.audio.count
        lastSequence = chunk.sequence
    }
}

struct SilentLiveVoiceCaptureController: LiveVoiceCaptureControlling {
    func startCapture() async throws -> any LiveVoiceCaptureSession {
        SilentLiveVoiceCaptureSession()
    }
}

private final class SilentLiveVoiceCaptureSession: @unchecked Sendable, LiveVoiceCaptureSession {
    let chunks: AsyncStream<VoiceAudioChunk>

    private let continuation: AsyncStream<VoiceAudioChunk>.Continuation

    init() {
        let stream = AsyncStream.makeStream(of: VoiceAudioChunk.self)
        self.chunks = stream.stream
        self.continuation = stream.continuation
    }

    func stop() async {
        continuation.finish()
    }

    func cancel() async {
        continuation.finish()
    }
}

@MainActor
extension ThreadDetailStore {
    public func beginVoiceCapture(
        interactionMode: ComposerVoiceInteractionMode = .hold
    ) async {
        guard composer.canStartVoiceCapture else {
            DockLog.voice.debug("voice capture start skipped reason=busy thread_id=\(DockLog.publicID(self.row.id.threadID), privacy: .public)")
            return
        }

        let startedAt = Date()
        let signpostState = DockSignpost.voice.beginInterval("voice.capture")
        DockLog.voice.notice("voice capture starting thread_id=\(DockLog.publicID(self.row.id.threadID), privacy: .public) mode=\(interactionMode.logDescription, privacy: .public)")
        let segment = ActiveDictationSegment(
            id: UUID().uuidString,
            baseDraft: composer.draft,
            transcript: ""
        )
        activeDictationSegment = segment
        composer.voice = ComposerVoiceState(
            phase: .starting,
            interactionMode: interactionMode,
            activeSegmentID: segment.id
        )
        composer.lastError = nil

        var startedSession: (any RealtimeTranscriptionSession)?
        var startedCaptureSession: (any LiveVoiceCaptureSession)?
        do {
            let captureSession = try await voiceCaptureEngine.startCapture(
                using: liveVoiceCaptureController
            )
            startedCaptureSession = captureSession
            DockLog.voice.notice("voice capture stream started thread_id=\(DockLog.publicID(self.row.id.threadID), privacy: .public) duration_ms=\(DockLog.milliseconds(since: startedAt), privacy: .public)")
            guard activeDictationSegment?.id == segment.id else {
                DockSignpost.voice.endInterval("voice.capture", signpostState)
                await captureSession.cancel()
                return
            }
            let session = try await transcriptionService.startSession()
            startedSession = session
            DockLog.transcription.notice("transcription session started thread_id=\(DockLog.publicID(self.row.id.threadID), privacy: .public) session_id=\(DockLog.publicID(session.id), privacy: .public)")
            guard activeDictationSegment?.id == segment.id else {
                DockSignpost.voice.endInterval("voice.capture", signpostState)
                await captureSession.cancel()
                await session.cancel()
                return
            }
            let shouldCommitImmediately = composer.voice.phase == .finalizing
            activeTranscriptionSession = session
            activeVoiceCaptureSession = captureSession
            composer.voice = ComposerVoiceState(
                phase: shouldCommitImmediately ? .finalizing : .streaming,
                interactionMode: interactionMode,
                sessionID: session.id,
                activeSegmentID: segment.id
            )
            startTranscriptionObservation(session: session)
            startVoiceCaptureForwarding(captureSession: captureSession, transcriptionSession: session)
            DockSignpost.voice.endInterval("voice.capture", signpostState)
            if shouldCommitImmediately {
                await stopActiveVoiceCapture()
                await commitActiveTranscriptionSession()
            }
        } catch {
            DockSignpost.voice.endInterval("voice.capture", signpostState)
            await startedCaptureSession?.cancel()
            await startedSession?.cancel()
            activeDictationSegment = nil
            activeTranscriptionSession = nil
            activeVoiceCaptureSession = nil
            composer.voice = ComposerVoiceState(phase: .idle, lastError: voiceMessage(from: error))
            DockLog.voice.error("voice capture start failed thread_id=\(DockLog.publicID(self.row.id.threadID), privacy: .public) duration_ms=\(DockLog.milliseconds(since: startedAt), privacy: .public) error=\(DockLog.errorSummary(error), privacy: .public)")
        }
    }

    public func toggleTapVoiceCapture() async {
        switch composer.voice.phase {
        case .idle:
            await beginVoiceCapture(interactionMode: .tap)
        case .starting, .streaming:
            guard composer.voice.interactionMode == .tap else {
                return
            }
            await finishVoiceCapture(interactionMode: .tap)
        case .finalizing:
            return
        }
    }

    public func finishVoiceCapture(
        interactionMode: ComposerVoiceInteractionMode = .hold
    ) async {
        guard composer.voice.phase == .streaming || composer.voice.phase == .starting else {
            DockLog.voice.debug("voice capture finish skipped phase=\(self.composer.voice.phase.logDescription, privacy: .public)")
            return
        }
        guard composer.voice.interactionMode == interactionMode else {
            DockLog.voice.debug("voice capture finish skipped reason=mode_mismatch requested=\(interactionMode.logDescription, privacy: .public)")
            return
        }

        composer.voice.phase = .finalizing
        DockLog.voice.notice("voice capture finalizing thread_id=\(DockLog.publicID(self.row.id.threadID), privacy: .public) session_id=\(DockLog.publicID(self.composer.voice.sessionID), privacy: .public)")

        guard activeTranscriptionSession != nil else {
            DockLog.voice.notice("voice capture finalizing deferred reason=transcription_session_not_ready thread_id=\(DockLog.publicID(self.row.id.threadID), privacy: .public) mode=\(interactionMode.logDescription, privacy: .public)")
            return
        }
        await stopActiveVoiceCapture()
        await commitActiveTranscriptionSession()
    }

    public func cancelVoiceCapture() async {
        DockLog.voice.notice("voice capture canceled thread_id=\(DockLog.publicID(self.row.id.threadID), privacy: .public) session_id=\(DockLog.publicID(self.composer.voice.sessionID), privacy: .public)")
        await cancelActiveVoiceCapture()
        await activeTranscriptionSession?.cancel()
        cancelActiveDictation()
    }

    private func commitActiveTranscriptionSession() async {
        let sessionID = activeTranscriptionSession?.id
        let startedAt = Date()
        let signpostState = DockSignpost.transcription.beginInterval("transcription.commit")
        DockLog.transcription.notice("transcription commit started thread_id=\(DockLog.publicID(self.row.id.threadID), privacy: .public) session_id=\(DockLog.publicID(sessionID), privacy: .public)")
        do {
            try await activeTranscriptionSession?.commit()
            await transcriptionTask?.value
            DockLog.transcription.notice("transcription commit finished thread_id=\(DockLog.publicID(self.row.id.threadID), privacy: .public) session_id=\(DockLog.publicID(sessionID), privacy: .public) duration_ms=\(DockLog.milliseconds(since: startedAt), privacy: .public)")
        } catch {
            await cancelActiveVoiceCapture()
            failActiveDictation(message: voiceMessage(from: error))
            DockLog.transcription.error("transcription commit failed thread_id=\(DockLog.publicID(self.row.id.threadID), privacy: .public) session_id=\(DockLog.publicID(sessionID), privacy: .public) duration_ms=\(DockLog.milliseconds(since: startedAt), privacy: .public) error=\(DockLog.errorSummary(error), privacy: .public)")
        }
        DockSignpost.transcription.endInterval("transcription.commit", signpostState)
        if let sessionID,
           activeTranscriptionSession?.id == sessionID,
           composer.voice.phase == .finalizing {
            DockLog.transcription.warning("transcription commit ended without terminal event thread_id=\(DockLog.publicID(self.row.id.threadID), privacy: .public) session_id=\(DockLog.publicID(sessionID), privacy: .public)")
            await cancelActiveVoiceCapture()
            failActiveDictation(message: "Realtime transcription stopped. Try again.")
        }
    }

    func startTranscriptionObservation(session: any RealtimeTranscriptionSession) {
        transcriptionTask?.cancel()
        transcriptionTask = Task { [weak self] in
            for await event in session.events {
                guard let self else {
                    return
                }
                if await handle(transcriptionEvent: event) {
                    return
                }
            }
            await self?.handleTranscriptionEventStreamEnded(sessionID: session.id)
        }
    }

    private func startVoiceCaptureForwarding(
        captureSession: any LiveVoiceCaptureSession,
        transcriptionSession: any RealtimeTranscriptionSession
    ) {
        voiceCaptureTask?.cancel()
        let voiceCaptureEngine = voiceCaptureEngine
        voiceCaptureTask = Task.detached(priority: .userInitiated) { [weak self, captureSession, transcriptionSession, voiceCaptureEngine] in
            let startedAt = Date()
            guard let self else {
                return
            }
            let summary: VoiceForwardingSummary
            do {
                summary = try await voiceCaptureEngine.forwardAudio(
                    from: captureSession,
                    to: transcriptionSession
                )
            } catch let failure as VoiceCaptureForwardingFailure {
                await self.handleVoiceCaptureAppendFailure(
                    failure.error,
                    sessionID: transcriptionSession.id,
                    summary: failure.summary,
                    failedSequence: failure.failedSequence,
                    failedBytes: failure.failedBytes
                )
                return
            } catch {
                await self.handleVoiceCaptureAppendFailure(
                    error,
                    sessionID: transcriptionSession.id,
                    summary: VoiceForwardingSummary(),
                    failedSequence: -1,
                    failedBytes: 0
                )
                return
            }
            await self.handleVoiceCaptureStreamEnded(
                sessionID: transcriptionSession.id,
                summary: summary,
                durationMS: DockLog.milliseconds(since: startedAt)
            )
        }
    }

    private func handleVoiceCaptureAppendFailure(
        _ error: Error,
        sessionID: String,
        summary: VoiceForwardingSummary,
        failedSequence: Int,
        failedBytes: Int
    ) async {
        guard activeTranscriptionSession?.id == sessionID,
              composer.voice.phase.isBusy else {
            return
        }
        await cancelActiveVoiceCapture()
        await activeTranscriptionSession?.cancel()
        failActiveDictation(message: voiceMessage(from: error))
        DockLog.transcription.error("voice audio append failed session_id=\(DockLog.publicID(sessionID), privacy: .public) failed_sequence=\(failedSequence, privacy: .public) failed_bytes=\(failedBytes, privacy: .public) forwarded_chunks=\(summary.chunks, privacy: .public) forwarded_bytes=\(summary.bytes, privacy: .public) last_sequence=\(summary.lastSequence, privacy: .public) error=\(DockLog.errorSummary(error), privacy: .public)")
    }

    private func handleVoiceCaptureStreamEnded(
        sessionID: String,
        summary: VoiceForwardingSummary,
        durationMS: Int
    ) async {
        guard activeTranscriptionSession?.id == sessionID else {
            DockLog.voice.debug("voice capture stream ended ignored reason=stale_session session_id=\(DockLog.publicID(sessionID), privacy: .public) forwarded_chunks=\(summary.chunks, privacy: .public) forwarded_bytes=\(summary.bytes, privacy: .public) last_sequence=\(summary.lastSequence, privacy: .public) duration_ms=\(durationMS, privacy: .public)")
            return
        }
        let phase = composer.voice.phase
        let hasActiveCapture = activeVoiceCaptureSession != nil
        DockLog.voice.notice("voice capture stream ended session_id=\(DockLog.publicID(sessionID), privacy: .public) phase=\(phase.logDescription, privacy: .public) active_capture=\(hasActiveCapture, privacy: .public) forwarded_chunks=\(summary.chunks, privacy: .public) forwarded_bytes=\(summary.bytes, privacy: .public) last_sequence=\(summary.lastSequence, privacy: .public) duration_ms=\(durationMS, privacy: .public)")
        guard activeTranscriptionSession?.id == sessionID,
              activeVoiceCaptureSession != nil,
              composer.voice.phase == .streaming else {
            return
        }
        await cancelActiveVoiceCapture()
        await activeTranscriptionSession?.cancel()
        failActiveDictation(message: "Voice capture stopped. Try again.")
        DockLog.voice.warning("voice capture stream ended unexpectedly session_id=\(DockLog.publicID(sessionID), privacy: .public)")
    }

    private func stopActiveVoiceCapture() async {
        let captureSession = activeVoiceCaptureSession
        DockLog.voice.debug("voice capture stop requested session_id=\(DockLog.publicID(self.composer.voice.sessionID), privacy: .public) active_capture=\((captureSession != nil), privacy: .public) phase=\(self.composer.voice.phase.logDescription, privacy: .public)")
        activeVoiceCaptureSession = nil
        await voiceCaptureEngine.stop(captureSession)
        await voiceCaptureTask?.value
        voiceCaptureTask = nil
    }

    func cancelActiveVoiceCapture() async {
        let captureSession = activeVoiceCaptureSession
        DockLog.voice.debug("voice capture cancel requested session_id=\(DockLog.publicID(self.composer.voice.sessionID), privacy: .public) active_capture=\((captureSession != nil), privacy: .public) phase=\(self.composer.voice.phase.logDescription, privacy: .public)")
        activeVoiceCaptureSession = nil
        voiceCaptureTask?.cancel()
        voiceCaptureTask = nil
        await voiceCaptureEngine.cancel(captureSession)
    }

    private func handleTranscriptionEventStreamEnded(sessionID: String) async {
        guard activeTranscriptionSession?.id == sessionID else {
            return
        }
        let phase = composer.voice.phase
        DockLog.transcription.warning("transcription event stream ended session_id=\(DockLog.publicID(sessionID), privacy: .public) phase=\(phase.logDescription, privacy: .public) voice_busy=\(phase.isBusy, privacy: .public)")
        guard phase.isBusy else {
            activeTranscriptionSession = nil
            return
        }
        await cancelActiveVoiceCapture()
        failActiveDictation(
            message: "Realtime transcription stopped. Try again.",
            cancelObservation: false
        )
    }

    private func handle(transcriptionEvent event: RealtimeTranscriptionEvent) async -> Bool {
        guard event.sessionID == activeTranscriptionSession?.id else {
            return false
        }

        switch event {
        case .started:
            DockLog.transcription.debug("transcription event started session_id=\(DockLog.publicID(event.sessionID), privacy: .public)")
            return false
        case .delta(_, _, let sequence, _, let partialText):
            DockLog.transcription.debug("transcription event delta session_id=\(DockLog.publicID(event.sessionID), privacy: .public) sequence=\(sequence ?? -1, privacy: .public) partial_characters=\(partialText.count, privacy: .public)")
            await scheduleActiveDictationReplacement(with: partialText)
            return false
        case .completed(_, _, let text):
            await stopActiveVoiceCapture()
            await completeActiveDictation(with: text)
            DockLog.transcription.notice("transcription event completed session_id=\(DockLog.publicID(event.sessionID), privacy: .public) characters=\(text.count, privacy: .public)")
            return true
        case .failed(_, let code, let message):
            await cancelActiveVoiceCapture()
            failActiveDictation(message: message, cancelObservation: false)
            DockLog.transcription.warning("transcription event failed session_id=\(DockLog.publicID(event.sessionID), privacy: .public) code=\(code, privacy: .public)")
            return true
        case .canceled:
            await cancelActiveVoiceCapture()
            cancelActiveDictation(cancelObservation: false)
            DockLog.transcription.notice("transcription event canceled session_id=\(DockLog.publicID(event.sessionID), privacy: .public)")
            return true
        case .closed:
            if composer.voice.phase.isBusy {
                await cancelActiveVoiceCapture()
                failActiveDictation(
                    message: "Realtime transcription stopped. Try again.",
                    cancelObservation: false
                )
                DockLog.transcription.warning("transcription event closed while busy session_id=\(DockLog.publicID(event.sessionID), privacy: .public)")
                return true
            }
            return false
        }
    }

    private func scheduleActiveDictationReplacement(with transcript: String) async {
        guard var segment = activeDictationSegment else {
            return
        }

        segment.transcript = await transcriptionEngine.normalizedTranscript(transcript)
        activeDictationSegment = segment
        composer.lastError = nil
        composer.voice.provisionalTranscript = segment.transcript
        let segmentID = segment.id
        voiceTranscriptPublishTask?.cancel()
        voiceTranscriptPublishTask = Task { [weak self] in
            do {
                try await Task.sleep(
                    for: .milliseconds(CodexDockConstants.Rendering.voiceTranscriptPublishDebounceMilliseconds)
                )
            } catch {
                return
            }
            await self?.publishActiveDictationDraft(segmentID: segmentID)
        }
    }

    private func publishActiveDictationDraft(segmentID: String) async {
        guard let segment = activeDictationSegment,
              segment.id == segmentID else {
            return
        }
        // Only the active provisional segment may be replaced by transcript updates.
        composer.draft = await transcriptionEngine.draft(
            base: segment.baseDraft,
            transcript: segment.transcript
        )
        voiceTranscriptPublishTask = nil
    }

    private func flushActiveDictationDraft() {
        voiceTranscriptPublishTask?.cancel()
        voiceTranscriptPublishTask = nil
        guard let segment = activeDictationSegment else {
            return
        }
        composer.draft = draft(base: segment.baseDraft, transcript: segment.transcript)
    }

    private func completeActiveDictation(with transcript: String) async {
        guard var segment = activeDictationSegment else {
            return
        }

        voiceTranscriptPublishTask?.cancel()
        voiceTranscriptPublishTask = nil

        do {
            composer.draft = try await transcriptionEngine.finalDraft(
                base: segment.baseDraft,
                transcript: transcript
            )
            segment.transcript = await transcriptionEngine.normalizedTranscript(transcript)
        } catch {
            failActiveDictation(message: TranscriptionServiceError.emptyTranscript.localizedDescription)
            return
        }

        activeDictationSegment = nil
        activeTranscriptionSession = nil
        composer.voice = ComposerVoiceState()
        composer.lastError = nil
    }

    private func cancelActiveDictation(cancelObservation: Bool = true) {
        voiceTranscriptPublishTask?.cancel()
        voiceTranscriptPublishTask = nil
        if let segment = activeDictationSegment {
            composer.draft = segment.baseDraft
        }
        activeDictationSegment = nil
        activeTranscriptionSession = nil
        if cancelObservation {
            transcriptionTask?.cancel()
            transcriptionTask = nil
        }
        composer.voice = ComposerVoiceState()
    }

    func failActiveDictation(message: String, cancelObservation: Bool = true) {
        voiceTranscriptPublishTask?.cancel()
        voiceTranscriptPublishTask = nil
        if let segment = activeDictationSegment, segment.transcript.isEmpty {
            composer.draft = segment.baseDraft
        } else {
            flushActiveDictationDraft()
        }
        activeDictationSegment = nil
        activeTranscriptionSession = nil
        if cancelObservation {
            transcriptionTask?.cancel()
            transcriptionTask = nil
        }
        composer.voice = ComposerVoiceState(phase: .idle, lastError: message)
    }

    private func draft(base: String, transcript: String) -> String {
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranscript.isEmpty else {
            return base
        }
        guard !base.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return trimmedTranscript
        }
        if base.last?.isWhitespace == true {
            return base + trimmedTranscript
        }
        return "\(base) \(trimmedTranscript)"
    }

    private func voiceMessage(from error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }
        return "Voice input failed."
    }
}

extension ComposerVoiceInteractionMode {
    var logDescription: String {
        switch self {
        case .hold:
            return "hold"
        case .tap:
            return "tap"
        }
    }
}

extension ComposerVoicePhase {
    var logDescription: String {
        switch self {
        case .idle:
            return "idle"
        case .starting:
            return "starting"
        case .streaming:
            return "streaming"
        case .finalizing:
            return "finalizing"
        }
    }
}

import Foundation

struct VoiceCaptureForwardingFailure: Error {
    let error: Error
    let summary: VoiceForwardingSummary
    let failedSequence: Int
    let failedBytes: Int
}

actor VoiceCaptureEngine {
    func startCapture(
        using controller: any LiveVoiceCaptureControlling
    ) async throws -> any LiveVoiceCaptureSession {
        try await controller.startCapture()
    }

    func stop(_ session: (any LiveVoiceCaptureSession)?) async {
        await session?.stop()
    }

    func cancel(_ session: (any LiveVoiceCaptureSession)?) async {
        await session?.cancel()
    }

    func forwardAudio(
        from captureSession: any LiveVoiceCaptureSession,
        to transcriptionSession: any RealtimeTranscriptionSession
    ) async throws -> VoiceForwardingSummary {
        var summary = VoiceForwardingSummary()
        for await chunk in captureSession.chunks {
            guard !Task.isCancelled else {
                return summary
            }
            do {
                try await transcriptionSession.appendAudio(
                    chunk.audio,
                    sequence: chunk.sequence
                )
                summary.record(chunk)
                DockLog.transcription.debug("transcription audio appended session_id=\(DockLog.publicID(transcriptionSession.id), privacy: .public) sequence=\(chunk.sequence, privacy: .public) bytes=\(chunk.audio.count, privacy: .public)")
            } catch {
                throw VoiceCaptureForwardingFailure(
                    error: error,
                    summary: summary,
                    failedSequence: chunk.sequence,
                    failedBytes: chunk.audio.count
                )
            }
        }
        return summary
    }
}

import Foundation

public enum RealtimeTranscriptionEvent: Equatable, Sendable {
    case started(sessionID: String)
    case delta(
        sessionID: String,
        itemID: String?,
        sequence: Int?,
        deltaText: String,
        partialText: String
    )
    case completed(sessionID: String, itemID: String?, text: String)
    case failed(sessionID: String, code: String, message: String)
    case canceled(sessionID: String)
    case closed(sessionID: String)
}

public extension RealtimeTranscriptionEvent {
    var sessionID: String {
        switch self {
        case .started(let sessionID),
             .delta(let sessionID, _, _, _, _),
             .completed(let sessionID, _, _),
             .failed(let sessionID, _, _),
             .canceled(let sessionID),
             .closed(let sessionID):
            return sessionID
        }
    }
}

public protocol RealtimeTranscriptionSession: Sendable {
    var id: String { get }
    var events: AsyncStream<RealtimeTranscriptionEvent> { get }

    func appendAudio(_ chunk: Data, sequence: Int) async throws
    func commit() async throws
    func cancel() async
}

public protocol RealtimeTranscriptionServicing: Sendable {
    func startSession() async throws -> any RealtimeTranscriptionSession
}

public struct VoiceAudioChunk: Equatable, Sendable {
    public let sequence: Int
    public let audio: Data
    public let format: VoiceAudioFormat

    public init(sequence: Int, audio: Data, format: VoiceAudioFormat) {
        self.sequence = sequence
        self.audio = audio
        self.format = format
    }
}

public enum VoiceAudioFormat: Equatable, Sendable {
    case pcm16Mono24k
}

public protocol LiveVoiceCaptureSession: Sendable {
    var chunks: AsyncStream<VoiceAudioChunk> { get }

    func stop() async
    func cancel() async
}

public protocol LiveVoiceCaptureControlling: Sendable {
    func startCapture() async throws -> any LiveVoiceCaptureSession
}

public enum TranscriptionServiceError: Error, Equatable, LocalizedError, Sendable {
    case emptyTranscript
    case transportFailed
    case realtimeUnavailable

    public var errorDescription: String? {
        switch self {
        case .emptyTranscript:
            return "No speech was detected."
        case .transportFailed:
            return "Realtime transcription could not reach the relay."
        case .realtimeUnavailable:
            return "Realtime transcription is not connected yet."
        }
    }
}

public struct UnavailableRealtimeTranscriptionService: RealtimeTranscriptionServicing {
    public init() {}

    public func startSession() async throws -> any RealtimeTranscriptionSession {
        throw TranscriptionServiceError.realtimeUnavailable
    }
}

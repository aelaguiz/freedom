import Foundation

#if os(iOS)
import AVFoundation
#endif

@MainActor
public protocol VoiceCaptureControlling: Sendable {
    func startRecording() async throws -> URL
    func stopRecording() async throws -> URL
    func cancelRecording() async
}

public enum VoiceCaptureError: Error, Equatable, LocalizedError, Sendable {
    case microphoneDenied
    case recordingUnavailable
    case notRecording
    case unsupportedPlatform

    public var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            return "Microphone access is not allowed."
        case .recordingUnavailable:
            return "Voice recording could not start."
        case .notRecording:
            return "Voice recording is not active."
        case .unsupportedPlatform:
            return "Voice recording is not supported on this platform."
        }
    }
}

@MainActor
public final class VoiceCaptureController: VoiceCaptureControlling {
    #if os(iOS)
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    #endif

    public init() {}

    public func startRecording() async throws -> URL {
        #if os(iOS)
        try await ensurePermission()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.prepareToRecord()
        guard recorder.record() else {
            throw VoiceCaptureError.recordingUnavailable
        }

        self.recorder = recorder
        self.recordingURL = url
        return url
        #else
        throw VoiceCaptureError.unsupportedPlatform
        #endif
    }

    public func stopRecording() async throws -> URL {
        #if os(iOS)
        guard let recorder, let recordingURL else {
            throw VoiceCaptureError.notRecording
        }
        recorder.stop()
        self.recorder = nil
        self.recordingURL = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return recordingURL
        #else
        throw VoiceCaptureError.unsupportedPlatform
        #endif
    }

    public func cancelRecording() async {
        #if os(iOS)
        recorder?.stop()
        recorder = nil
        if let recordingURL {
            try? FileManager.default.removeItem(at: recordingURL)
        }
        recordingURL = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    #if os(iOS)
    private func ensurePermission() async throws {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return
        case .denied:
            throw VoiceCaptureError.microphoneDenied
        case .undetermined:
            let granted = await AVAudioApplication.requestRecordPermission()
            guard granted else {
                throw VoiceCaptureError.microphoneDenied
            }
        @unknown default:
            throw VoiceCaptureError.microphoneDenied
        }
    }
    #endif
}

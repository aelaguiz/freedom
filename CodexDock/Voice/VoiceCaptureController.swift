import Foundation

#if os(iOS)
@preconcurrency import AVFoundation
#endif

public enum VoiceCaptureError: Error, Equatable, LocalizedError, Sendable {
    case microphoneDenied
    case recordingUnavailable
    case unsupportedPlatform

    public var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            return "Microphone access is not allowed."
        case .recordingUnavailable:
            return "Voice recording could not start."
        case .unsupportedPlatform:
            return "Voice recording is not supported on this platform."
        }
    }
}

enum VoiceCaptureRouteChangeKind: Equatable, Sendable {
    case oldDeviceUnavailable
    case categoryChange
    case other
}

enum VoiceCaptureInterruptionKind: Equatable, Sendable {
    case began
    case ended
    case other
}

struct VoiceCaptureSessionStopPolicy {
    static func shouldStopForRouteChange(_ reason: VoiceCaptureRouteChangeKind) -> Bool {
        reason == .oldDeviceUnavailable
    }

    static func shouldStopForInterruption(_ type: VoiceCaptureInterruptionKind?) -> Bool {
        type != .ended
    }
}

public final class LiveVoiceCaptureController: LiveVoiceCaptureControlling {
    public init() {}

    public func startCapture() async throws -> any LiveVoiceCaptureSession {
        #if os(iOS)
        DockLog.voice.notice("voice capture controller permission check started")
        try await Self.ensurePermission()

        #if targetEnvironment(simulator)
        // Simulator audio input can SIGTRAP inside AVAudioEngine startup; real mic
        // acceptance belongs on the physical iPhone path.
        DockLog.voice.warning("voice capture unavailable on simulator")
        throw VoiceCaptureError.recordingUnavailable
        #else
        let startedAt = Date()
        DockLog.voice.notice("voice capture engine start requested")
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(
            .playAndRecord,
            mode: .spokenAudio,
            options: [.defaultToSpeaker, .allowBluetoothHFP]
        )
        do {
            try audioSession.setPreferredSampleRate(CodexDockConstants.Voice.sampleRate)
        } catch {
            DockLog.voice.debug("voice capture preferred sample rate not applied error=\(DockLog.errorSummary(error), privacy: .public)")
        }
        do {
            try audioSession.setPreferredInputNumberOfChannels(CodexDockConstants.Voice.channelCount)
        } catch {
            DockLog.voice.debug("voice capture preferred input channel count not applied error=\(DockLog.errorSummary(error), privacy: .public)")
        }
        try audioSession.setActive(true)
        DockLog.voice.notice("voice capture audio session active sample_rate=\(audioSession.sampleRate, privacy: .public) input_channels=\(audioSession.inputNumberOfChannels, privacy: .public) input_available=\(audioSession.isInputAvailable, privacy: .public) io_buffer_duration=\(audioSession.ioBufferDuration, privacy: .public) input_ports=\(voiceCapturePortTypes(audioSession.currentRoute.inputs), privacy: .public) output_ports=\(voiceCapturePortTypes(audioSession.currentRoute.outputs), privacy: .public)")

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        DockLog.voice.notice("voice capture input format sample_rate=\(inputFormat.sampleRate, privacy: .public) channels=\(inputFormat.channelCount, privacy: .public) common_format=\(inputFormat.commonFormat.rawValue, privacy: .public) interleaved=\(inputFormat.isInterleaved, privacy: .public)")
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            DockLog.voice.error("voice capture invalid input format sample_rate=\(inputFormat.sampleRate, privacy: .public) channels=\(inputFormat.channelCount, privacy: .public)")
            throw VoiceCaptureError.recordingUnavailable
        }

        let stream = AsyncStream.makeStream(of: VoiceAudioChunk.self)
        let emitter = PCM16Mono24kChunkEmitter(
            inputFormat: inputFormat,
            continuation: stream.continuation
        )

        inputNode.installTap(
            onBus: 0,
            bufferSize: CodexDockConstants.Voice.tapBufferFrameCount,
            format: inputFormat,
            block: makeVoiceCaptureTapBlock(emitter: emitter)
        )

        do {
            engine.prepare()
            try engine.start()
            DockLog.voice.notice("voice capture engine started sample_rate=\(inputFormat.sampleRate, privacy: .public) channels=\(inputFormat.channelCount, privacy: .public) duration_ms=\(DockLog.milliseconds(since: startedAt), privacy: .public)")
            return AVAudioEngineLiveVoiceCaptureSession(
                engine: engine,
                chunks: stream.stream,
                continuation: stream.continuation,
                emitter: emitter,
                startedAt: startedAt
            )
        } catch {
            inputNode.removeTap(onBus: 0)
            stream.continuation.finish()
            try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            DockLog.voice.error("voice capture engine start failed duration_ms=\(DockLog.milliseconds(since: startedAt), privacy: .public) error=\(DockLog.errorSummary(error), privacy: .public)")
            throw VoiceCaptureError.recordingUnavailable
        }
        #endif
        #else
        DockLog.voice.warning("voice capture unsupported platform")
        throw VoiceCaptureError.unsupportedPlatform
        #endif
    }

    #if os(iOS)
    private static func ensurePermission() async throws {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            DockLog.voice.notice("voice capture microphone permission granted")
            return
        case .denied:
            DockLog.voice.warning("voice capture microphone permission denied")
            throw VoiceCaptureError.microphoneDenied
        case .undetermined:
            let granted = await AVAudioApplication.requestRecordPermission()
            guard granted else {
                DockLog.voice.warning("voice capture microphone permission denied after prompt")
                throw VoiceCaptureError.microphoneDenied
            }
            DockLog.voice.notice("voice capture microphone permission granted after prompt")
        @unknown default:
            DockLog.voice.warning("voice capture microphone permission unknown")
            throw VoiceCaptureError.microphoneDenied
        }
    }
    #endif
}

#if os(iOS)
private struct NotificationObserverToken: @unchecked Sendable {
    let value: NSObjectProtocol
}

private final class AVAudioEngineLiveVoiceCaptureSession: @unchecked Sendable, LiveVoiceCaptureSession {
    let chunks: AsyncStream<VoiceAudioChunk>

    private let engine: AVAudioEngine
    private let continuation: AsyncStream<VoiceAudioChunk>.Continuation
    private let emitter: PCM16Mono24kChunkEmitter
    private let startedAt: Date
    private let finishLock = NSLock()
    private var interruptionObserver: NotificationObserverToken?
    private var routeChangeObserver: NotificationObserverToken?
    private var isFinished = false

    init(
        engine: AVAudioEngine,
        chunks: AsyncStream<VoiceAudioChunk>,
        continuation: AsyncStream<VoiceAudioChunk>.Continuation,
        emitter: PCM16Mono24kChunkEmitter,
        startedAt: Date = Date()
    ) {
        self.engine = engine
        self.chunks = chunks
        self.continuation = continuation
        self.emitter = emitter
        self.startedAt = startedAt
        self.interruptionObserver = NotificationObserverToken(
            value: NotificationCenter.default.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: AVAudioSession.sharedInstance(),
                queue: nil
            ) { [weak self] notification in
                let kind = Self.interruptionKind(from: notification)
                let rawType = Self.interruptionRawValue(from: notification).map { Int($0) } ?? -1
                let shouldStop = VoiceCaptureSessionStopPolicy.shouldStopForInterruption(kind)
                DockLog.voice.debug("voice capture interruption observed kind=\(kind?.logDescription ?? "unknown", privacy: .public) raw_type=\(rawType, privacy: .public) stops=\(shouldStop, privacy: .public)")
                guard shouldStop else {
                    return
                }
                DockLog.voice.warning("voice capture interruption stopping kind=\(kind?.logDescription ?? "unknown", privacy: .public)")
                Task { [weak self] in
                    self?.finish(reason: "interruption_\(kind?.logDescription ?? "unknown")")
                }
            }
        )
        self.routeChangeObserver = NotificationObserverToken(
            value: NotificationCenter.default.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: AVAudioSession.sharedInstance(),
                queue: nil
            ) { [weak self] notification in
                guard let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt else {
                    DockLog.voice.debug("voice capture route change observed kind=unknown raw_reason=-1 stops=false")
                    return
                }
                guard let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
                    DockLog.voice.debug("voice capture route change observed kind=other raw_reason=\(reasonValue, privacy: .public) stops=false")
                    return
                }
                let kind = Self.routeChangeKind(from: reason)
                let shouldStop = VoiceCaptureSessionStopPolicy.shouldStopForRouteChange(kind)
                DockLog.voice.debug("voice capture route change observed kind=\(kind.logDescription, privacy: .public) raw_reason=\(reasonValue, privacy: .public) stops=\(shouldStop, privacy: .public) previous_input_ports=\(Self.previousInputPortTypes(from: notification), privacy: .public) current_input_ports=\(voiceCapturePortTypes(AVAudioSession.sharedInstance().currentRoute.inputs), privacy: .public)")
                guard shouldStop else {
                    return
                }
                DockLog.voice.warning("voice capture route change stopping kind=\(kind.logDescription, privacy: .public) raw_reason=\(reasonValue, privacy: .public)")
                Task { [weak self] in
                    self?.finish(reason: "route_change_\(kind.logDescription)")
                }
            }
        )
    }

    deinit {
        guard !isFinished else {
            return
        }
        isFinished = true
        let interruptionObserver = interruptionObserver
        let routeChangeObserver = routeChangeObserver
        let engine = engine
        let continuation = continuation
        let emitter = emitter
        let startedAt = startedAt
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver.value)
        }
        if let routeChangeObserver {
            NotificationCenter.default.removeObserver(routeChangeObserver.value)
        }
        emitter.close()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        continuation.finish()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        DockLog.voice.notice("voice capture session deinitialized chunks=\(emitter.emittedChunkCount, privacy: .public) bytes=\(emitter.emittedByteCount, privacy: .public) duration_ms=\(DockLog.milliseconds(since: startedAt), privacy: .public)")
    }

    func stop() async {
        finish(reason: "stop")
    }

    func cancel() async {
        finish(reason: "cancel")
    }

    private func finish(reason: String) {
        finishLock.lock()
        guard !isFinished else {
            finishLock.unlock()
            return
        }
        isFinished = true
        let interruptionObserver = interruptionObserver
        let routeChangeObserver = routeChangeObserver
        self.interruptionObserver = nil
        self.routeChangeObserver = nil
        finishLock.unlock()

        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver.value)
        }
        if let routeChangeObserver {
            NotificationCenter.default.removeObserver(routeChangeObserver.value)
        }
        emitter.close()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        continuation.finish()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        DockLog.voice.notice("voice capture session finished reason=\(reason, privacy: .public) chunks=\(self.emitter.emittedChunkCount, privacy: .public) bytes=\(self.emitter.emittedByteCount, privacy: .public) duration_ms=\(DockLog.milliseconds(since: self.startedAt), privacy: .public)")
    }

    private nonisolated static func routeChangeKind(
        from reason: AVAudioSession.RouteChangeReason
    ) -> VoiceCaptureRouteChangeKind {
        switch reason {
        case .oldDeviceUnavailable:
            return .oldDeviceUnavailable
        case .categoryChange:
            return .categoryChange
        default:
            return .other
        }
    }

    private nonisolated static func interruptionKind(
        from notification: Notification
    ) -> VoiceCaptureInterruptionKind? {
        guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return nil
        }

        switch type {
        case .began:
            return .began
        case .ended:
            return .ended
        @unknown default:
            return .other
        }
    }

    private nonisolated static func interruptionRawValue(from notification: Notification) -> UInt? {
        notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
    }

    private nonisolated static func previousInputPortTypes(from notification: Notification) -> String {
        guard let route = notification.userInfo?[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription else {
            return "none"
        }
        let values = route.inputs.map { $0.portType.rawValue }.filter { !$0.isEmpty }
        return values.isEmpty ? "none" : values.joined(separator: ",")
    }
}

fileprivate func voiceCapturePortTypes(_ ports: [AVAudioSessionPortDescription]) -> String {
    let values = ports.map { $0.portType.rawValue }.filter { !$0.isEmpty }
    return values.isEmpty ? "none" : values.joined(separator: ",")
}

private func makeVoiceCaptureTapBlock(emitter: PCM16Mono24kChunkEmitter) -> AVAudioNodeTapBlock {
    { buffer, _ in
        emitter.emit(buffer)
    }
}

private final class PCM16Mono24kChunkEmitter: @unchecked Sendable {
    private let inputFormat: AVAudioFormat
    private let continuation: AsyncStream<VoiceAudioChunk>.Continuation
    private let lock = NSLock()
    private var nextSequence = 1
    private var isClosed = false
    private var emittedChunks = 0
    private var emittedBytes = 0

    init(inputFormat: AVAudioFormat, continuation: AsyncStream<VoiceAudioChunk>.Continuation) {
        self.inputFormat = inputFormat
        self.continuation = continuation
    }

    func emit(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        guard !isClosed else {
            lock.unlock()
            return
        }
        let sequence = nextSequence
        nextSequence += 1
        lock.unlock()

        let audio = pcm16Mono24kData(from: buffer, inputFormat: inputFormat)
        guard !audio.isEmpty else {
            return
        }
        lock.lock()
        emittedChunks += 1
        emittedBytes += audio.count
        lock.unlock()
        continuation.yield(
            VoiceAudioChunk(sequence: sequence, audio: audio, format: .pcm16Mono24k)
        )
    }

    func close() {
        lock.lock()
        isClosed = true
        lock.unlock()
    }

    var emittedChunkCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return emittedChunks
    }

    var emittedByteCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return emittedBytes
    }

    private func pcm16Mono24kData(
        from buffer: AVAudioPCMBuffer,
        inputFormat: AVAudioFormat
    ) -> Data {
        let inputFrameCount = Int(buffer.frameLength)
        let channelCount = Int(inputFormat.channelCount)
        guard inputFrameCount > 0, channelCount > 0, inputFormat.sampleRate > 0 else {
            return Data()
        }

        let outputSampleRate = CodexDockConstants.Voice.sampleRate
        let outputFrameCount = max(
            1,
            Int((Double(inputFrameCount) * outputSampleRate / inputFormat.sampleRate).rounded(.down))
        )
        var data = Data()
        data.reserveCapacity(outputFrameCount * MemoryLayout<Int16>.size)

        if let channels = buffer.floatChannelData {
            for outputIndex in 0..<outputFrameCount {
                let sourceIndex = min(
                    inputFrameCount - 1,
                    Int(Double(outputIndex) * inputFormat.sampleRate / outputSampleRate)
                )
                var sample: Float = 0
                for channel in 0..<channelCount {
                    sample += channels[channel][sourceIndex]
                }
                appendPCM16(sample / Float(channelCount), to: &data)
            }
            return data
        }

        if let channels = buffer.int16ChannelData {
            for outputIndex in 0..<outputFrameCount {
                let sourceIndex = min(
                    inputFrameCount - 1,
                    Int(Double(outputIndex) * inputFormat.sampleRate / outputSampleRate)
                )
                var sample: Float = 0
                for channel in 0..<channelCount {
                    sample += Float(channels[channel][sourceIndex]) / Float(Int16.max)
                }
                appendPCM16(sample / Float(channelCount), to: &data)
            }
            return data
        }

        return Data()
    }

    private func appendPCM16(_ sample: Float, to data: inout Data) {
        let clamped = min(max(sample, -1), 1)
        var value = Int16(clamped * Float(Int16.max)).littleEndian
        withUnsafeBytes(of: &value) { bytes in
            data.append(contentsOf: bytes)
        }
    }
}

private extension VoiceCaptureRouteChangeKind {
    var logDescription: String {
        switch self {
        case .oldDeviceUnavailable:
            return "oldDeviceUnavailable"
        case .categoryChange:
            return "categoryChange"
        case .other:
            return "other"
        }
    }
}

private extension VoiceCaptureInterruptionKind {
    var logDescription: String {
        switch self {
        case .began:
            return "began"
        case .ended:
            return "ended"
        case .other:
            return "other"
        }
    }
}
#endif

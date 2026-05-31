import XCTest
@testable import CodexDock

struct FakeThreadDetailSessionFactory: ThreadDetailSessionMaking {
    let session: FakeThreadDetailSession

    func makeSession(for host: DockHostConfiguration) -> any ThreadDetailSession {
        session
    }
}

actor FakeThreadDetailSession: ThreadDetailSession {
    nonisolated let connectionStates: AsyncStream<AppServerConnectionState>
    nonisolated let notifications: AsyncStream<JSONRPCNotification>
    nonisolated let serverRequests: AsyncStream<JSONRPCRequest>

    private let connectionStateContinuation: AsyncStream<AppServerConnectionState>.Continuation
    private let notificationContinuation: AsyncStream<JSONRPCNotification>.Continuation
    private let serverRequestContinuation: AsyncStream<JSONRPCRequest>.Continuation
    private var readResults: [Result<ThreadReadResponseDTO, any Error>]
    private var turnsListResults: [Result<ThreadTurnsListResponseDTO, any Error>]
    private var resumeResults: [Result<ThreadResumeResponseDTO, any Error>]
    private let turnStartResult: Result<TurnStartResponseDTO, any Error>
    private let turnSteerResult: Result<TurnSteerResponseDTO, any Error>
    private let resumeDelay: Duration?
    private var readParams: [ThreadReadParams] = []
    private var turnsListParams: [ThreadTurnsListParams] = []
    private var resumeParams: [ThreadResumeParams] = []
    private var turnStartParams: [TurnStartParams] = []
    private var turnSteerParams: [TurnSteerParams] = []
    private var sentResponses: [SentServerResponse] = []

    init(
        readResult: Result<ThreadReadResponseDTO, any Error>,
        turnsListResult: Result<ThreadTurnsListResponseDTO, any Error> = .success(
            ThreadTurnsListResponseDTO(data: [])
        ),
        resumeResult: Result<ThreadResumeResponseDTO, any Error>,
        turnStartResult: Result<TurnStartResponseDTO, any Error> = .success(
            TurnStartResponseDTO(
                turn: .object([
                    "id": .string("turn-started"),
                    "status": .string("inProgress"),
                ])
            )
        ),
        turnSteerResult: Result<TurnSteerResponseDTO, any Error> = .success(
            TurnSteerResponseDTO(turnId: "turn-started")
        ),
        resumeDelay: Duration? = nil,
        readResults: [Result<ThreadReadResponseDTO, any Error>]? = nil,
        turnsListResults: [Result<ThreadTurnsListResponseDTO, any Error>]? = nil,
        resumeResults: [Result<ThreadResumeResponseDTO, any Error>]? = nil
    ) {
        let connectionStates = AsyncStream.makeStream(of: AppServerConnectionState.self)
        let notifications = AsyncStream.makeStream(of: JSONRPCNotification.self)
        let serverRequests = AsyncStream.makeStream(of: JSONRPCRequest.self)
        self.connectionStates = connectionStates.stream
        self.connectionStateContinuation = connectionStates.continuation
        self.notifications = notifications.stream
        self.notificationContinuation = notifications.continuation
        self.serverRequests = serverRequests.stream
        self.serverRequestContinuation = serverRequests.continuation
        self.readResults = readResults ?? [readResult]
        self.turnsListResults = turnsListResults ?? [turnsListResult]
        self.resumeResults = resumeResults ?? [resumeResult]
        self.turnStartResult = turnStartResult
        self.turnSteerResult = turnSteerResult
        self.resumeDelay = resumeDelay
    }

    func connectAndInitialize(
        params: InitializeParams,
        timeout: Duration
    ) async throws -> InitializeResponse {
        connectionStateContinuation.yield(.connecting)
        connectionStateContinuation.yield(.connected)
        return InitializeResponse(
            userAgent: "fake-codex",
            codexHome: "/Users/aelaguiz/.codex",
            platformFamily: "unix",
            platformOs: "macos"
        )
    }

    func threadRead(
        params: ThreadReadParams,
        timeout: Duration
    ) async throws -> ThreadReadResponseDTO {
        readParams.append(params)
        let result = readResults.count > 1 ? readResults.removeFirst() : readResults[0]
        return try result.get()
    }

    func threadTurnsList(
        params: ThreadTurnsListParams,
        timeout: Duration
    ) async throws -> ThreadTurnsListResponseDTO {
        turnsListParams.append(params)
        let result = turnsListResults.count > 1 ? turnsListResults.removeFirst() : turnsListResults[0]
        return try result.get()
    }

    func threadResume(
        params: ThreadResumeParams,
        timeout: Duration
    ) async throws -> ThreadResumeResponseDTO {
        resumeParams.append(params)
        if let resumeDelay {
            try await Task.sleep(for: resumeDelay)
        }
        let result = resumeResults.count > 1 ? resumeResults.removeFirst() : resumeResults[0]
        return try result.get()
    }

    func turnStart(
        params: TurnStartParams,
        timeout: Duration
    ) async throws -> TurnStartResponseDTO {
        turnStartParams.append(params)
        return try turnStartResult.get()
    }

    func turnSteer(
        params: TurnSteerParams,
        timeout: Duration
    ) async throws -> TurnSteerResponseDTO {
        turnSteerParams.append(params)
        return try turnSteerResult.get()
    }

    func sendResponse(id: JSONRPCRequestID, result: JSONValue) async throws {
        sentResponses.append(SentServerResponse(id: id, result: result))
    }

    func disconnect() async {
        connectionStateContinuation.yield(.closed(reason: "client disconnected"))
        connectionStateContinuation.finish()
        notificationContinuation.finish()
        serverRequestContinuation.finish()
    }

    func emitConnectionState(_ state: AppServerConnectionState) {
        connectionStateContinuation.yield(state)
    }

    func emitNotification(_ notification: JSONRPCNotification) {
        notificationContinuation.yield(notification)
    }

    func emitServerRequest(_ request: JSONRPCRequest) {
        serverRequestContinuation.yield(request)
    }

    func finishNotifications() {
        notificationContinuation.finish()
    }

    func finishServerRequests() {
        serverRequestContinuation.finish()
    }

    func finishConnectionStates() {
        connectionStateContinuation.finish()
    }

    func readParamsSnapshot() -> [ThreadReadParams] {
        readParams
    }

    func turnsListParamsSnapshot() -> [ThreadTurnsListParams] {
        turnsListParams
    }

    func resumeParamsSnapshot() -> [ThreadResumeParams] {
        resumeParams
    }

    func turnStartParamsSnapshot() -> [TurnStartParams] {
        turnStartParams
    }

    func turnSteerParamsSnapshot() -> [TurnSteerParams] {
        turnSteerParams
    }

    func sentResponsesSnapshot() -> [SentServerResponse] {
        sentResponses
    }
}

final class FakeRealtimeTranscriptionService: @unchecked Sendable, RealtimeTranscriptionServicing {
    let session: FakeRealtimeTranscriptionSession
    private let startResult: Result<Void, TranscriptionServiceError>
    var startDelay: Duration?
    private(set) var startCount = 0

    init(
        session: FakeRealtimeTranscriptionSession = FakeRealtimeTranscriptionSession(),
        startResult: Result<Void, TranscriptionServiceError> = .success(()),
        startDelay: Duration? = nil
    ) {
        self.session = session
        self.startResult = startResult
        self.startDelay = startDelay
    }

    func startSession() async throws -> any RealtimeTranscriptionSession {
        startCount += 1
        if let startDelay {
            try await Task.sleep(for: startDelay)
        }
        try startResult.get()
        session.emit(.started(sessionID: session.id))
        return session
    }
}

final class FakeRealtimeTranscriptionSession: @unchecked Sendable, RealtimeTranscriptionSession {
    let id: String
    let events: AsyncStream<RealtimeTranscriptionEvent>

    private let continuation: AsyncStream<RealtimeTranscriptionEvent>.Continuation
    private(set) var commitCount = 0
    private(set) var cancelCount = 0
    private(set) var appendedChunks: [(chunk: Data, sequence: Int)] = []
    var eventsOnCommit: [RealtimeTranscriptionEvent] = []
    var commitError: TranscriptionServiceError?
    var commitDelay: Duration?

    init(id: String = "fake-transcription-session") {
        self.id = id
        let stream = AsyncStream.makeStream(of: RealtimeTranscriptionEvent.self)
        self.events = stream.stream
        self.continuation = stream.continuation
    }

    func appendAudio(_ chunk: Data, sequence: Int) async throws {
        appendedChunks.append((chunk: chunk, sequence: sequence))
    }

    func commit() async throws {
        commitCount += 1
        if let commitDelay {
            try? await Task.sleep(for: commitDelay)
        }
        if let commitError {
            throw commitError
        }
        for event in eventsOnCommit {
            emit(event)
        }
        continuation.finish()
    }

    func cancel() async {
        cancelCount += 1
        emit(.canceled(sessionID: id))
        emit(.closed(sessionID: id))
        continuation.finish()
    }

    func emit(_ event: RealtimeTranscriptionEvent) {
        continuation.yield(event)
    }

    func finish() {
        continuation.finish()
    }
}

final class FakeLiveVoiceCaptureController: @unchecked Sendable, LiveVoiceCaptureControlling {
    let session: FakeLiveVoiceCaptureSession
    private let startResult: Result<Void, VoiceCaptureError>
    private(set) var startCount = 0

    init(
        session: FakeLiveVoiceCaptureSession = FakeLiveVoiceCaptureSession(),
        startResult: Result<Void, VoiceCaptureError> = .success(())
    ) {
        self.session = session
        self.startResult = startResult
    }

    func startCapture() async throws -> any LiveVoiceCaptureSession {
        startCount += 1
        try startResult.get()
        return session
    }
}

final class FakeLiveVoiceCaptureSession: @unchecked Sendable, LiveVoiceCaptureSession {
    let chunks: AsyncStream<VoiceAudioChunk>

    private let continuation: AsyncStream<VoiceAudioChunk>.Continuation
    private(set) var stopCount = 0
    private(set) var cancelCount = 0

    init() {
        let stream = AsyncStream.makeStream(of: VoiceAudioChunk.self)
        self.chunks = stream.stream
        self.continuation = stream.continuation
    }

    func emit(_ chunk: VoiceAudioChunk) {
        continuation.yield(chunk)
    }

    func finishChunks() {
        continuation.finish()
    }

    func stop() async {
        stopCount += 1
        continuation.finish()
    }

    func cancel() async {
        cancelCount += 1
        continuation.finish()
    }
}

enum FakeThreadDetailError: Error, LocalizedError, Sendable {
    case resumeFailed
    case turnFailed

    var errorDescription: String? {
        switch self {
        case .resumeFailed:
            return "resume failed"
        case .turnFailed:
            return "turn failed"
        }
    }
}

struct SentServerResponse: Equatable, Sendable {
    let id: JSONRPCRequestID
    let result: JSONValue
}

func makeDetailHost() -> DockHostConfiguration {
    try! DockHostConfiguration(host: "192.168.50.117", port: 4510)
}

func makeDetailRow(
    hostID: String,
    threadID: String,
    sourceHostID: String? = nil,
    status: DockRowStatusKind = .running
) -> DockRowViewModel {
    DockRowViewModel(
        id: HostScopedThreadID(hostID: hostID, threadID: threadID),
        sourceHostID: sourceHostID,
        backendSessionID: "\(threadID)-session",
        title: "Build live detail",
        hostDisplayName: "Test host",
        hostEndpoint: "\(hostID):4510",
        repository: "codex-client",
        branch: "main",
        status: status,
        lastActivity: "now",
        lastActivityDate: Date(timeIntervalSince1970: 2_000),
        summary: "Open a real thread",
        rail: .blue,
        label: nil,
        origin: .humanInteractive(subtype: .cli)
    )
}

func makeDetailThread(_ id: String, text: String) -> ThreadDTO {
    ThreadDTO(
        id: id,
        turns: [
            makeDetailTurn(id: "turn-1", text: text),
        ]
    )
}

func makeDetailTurn(
    id: String,
    startedAt: Int64? = nil,
    text: String
) -> JSONValue {
    var fields: [String: JSONValue] = [
        "id": .string(id),
        "items": .array([
            .object([
                "id": .string("\(id)-agent"),
                "type": .string("agentMessage"),
                "text": .string(text),
            ]),
        ]),
    ]
    if let startedAt {
        fields["startedAt"] = .integer(startedAt)
    }
    return .object(fields)
}

@MainActor
func waitForDetailStore(
    timeout: Duration = .seconds(2),
    _ predicate: @escaping () -> Bool
) async throws {
    let start = ContinuousClock.now
    while start.duration(to: .now) < timeout {
        if predicate() {
            return
        }
        try await Task.sleep(for: .milliseconds(10))
    }
    throw DetailStoreTimeoutError()
}

@MainActor
func waitForDetailStoreAsync(
    timeout: Duration = .seconds(2),
    _ predicate: @escaping () async -> Bool
) async throws {
    let start = ContinuousClock.now
    while start.duration(to: .now) < timeout {
        if await predicate() {
            return
        }
        try await Task.sleep(for: .milliseconds(10))
    }
    throw DetailStoreTimeoutError()
}

struct DetailStoreTimeoutError: Error {}

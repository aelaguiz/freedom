import XCTest
@testable import CodexDock

final class ThreadDetailStoreTests: XCTestCase {
    @MainActor
    func testLoadReadsAndResumesMatchingThread() async throws {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let session = FakeThreadDetailSession(
            readResult: .success(
                ThreadReadResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))
            ),
            turnsListResult: .success(
                ThreadTurnsListResponseDTO(data: makeDetailThread("thread-1", text: "Paged turn").turns ?? [])
            ),
            resumeResult: .success(
                ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))
            )
        )
        let store = ThreadDetailStore(
            host: host,
            row: row,
            factory: FakeThreadDetailSessionFactory(session: session),
            now: { Date(timeIntervalSince1970: 3_000) }
        )

        await store.load()

        guard case let .loaded(snapshot) = store.state else {
            return XCTFail("Expected loaded state, got \(store.state)")
        }

        XCTAssertEqual(snapshot.header.threadID, "thread-1")
        XCTAssertEqual(snapshot.liveState, .live)
        XCTAssertEqual(snapshot.events.map(\.body), ["Paged turn"])
        let readParams = await session.readParamsSnapshot()
        let turnsListParams = await session.turnsListParamsSnapshot()
        let resumeParams = await session.resumeParamsSnapshot()
        XCTAssertEqual(readParams, [
            ThreadReadParams(threadId: "thread-1", includeTurns: false),
        ])
        XCTAssertEqual(turnsListParams, [
            ThreadTurnsListParams(threadId: "thread-1", limit: 10),
        ])
        XCTAssertEqual(resumeParams, [
            ThreadResumeParams(threadId: "thread-1", excludeTurns: true),
        ])
    }

    @MainActor
    func testLoadPublishesPagedTurnsNewestFirstForDisplay() async throws {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let session = FakeThreadDetailSession(
            readResult: .success(ThreadReadResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            turnsListResult: .success(
                ThreadTurnsListResponseDTO(data: [
                    makeDetailTurn(id: "turn-old", startedAt: 1_700_000_000, text: "Old paged turn"),
                    makeDetailTurn(id: "turn-new", startedAt: 1_700_000_100, text: "New paged turn"),
                ])
            ),
            resumeResult: .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-1", turns: [])))
        )
        let store = ThreadDetailStore(
            host: host,
            row: row,
            factory: FakeThreadDetailSessionFactory(session: session)
        )

        await store.load()

        guard case let .loaded(snapshot) = store.state else {
            return XCTFail("Expected loaded state, got \(store.state)")
        }

        XCTAssertEqual(snapshot.events.map(\.body), ["New paged turn", "Old paged turn"])
        let readParams = await session.readParamsSnapshot()
        let turnsListParams = await session.turnsListParamsSnapshot()
        let resumeParams = await session.resumeParamsSnapshot()
        XCTAssertEqual(readParams, [
            ThreadReadParams(threadId: "thread-1", includeTurns: false),
        ])
        XCTAssertEqual(turnsListParams, [
            ThreadTurnsListParams(threadId: "thread-1", limit: 10),
        ])
        XCTAssertEqual(resumeParams, [
            ThreadResumeParams(threadId: "thread-1", excludeTurns: true),
        ])
    }

    @MainActor
    func testResumeFailureKeepsReadEventsAndMarksDetailStale() async {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let session = FakeThreadDetailSession(
            readResult: .success(
                ThreadReadResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))
            ),
            turnsListResult: .success(
                ThreadTurnsListResponseDTO(data: makeDetailThread("thread-1", text: "Stored turn").turns ?? [])
            ),
            resumeResult: .failure(.resumeFailed)
        )
        let store = ThreadDetailStore(
            host: host,
            row: row,
            factory: FakeThreadDetailSessionFactory(session: session)
        )

        await store.load()

        guard case let .loaded(snapshot) = store.state else {
            return XCTFail("Expected loaded state, got \(store.state)")
        }

        XCTAssertEqual(snapshot.events.map(\.body), ["Stored turn"])
        guard case let .stale(message) = snapshot.liveState else {
            return XCTFail("Expected stale detail, got \(snapshot.liveState)")
        }
        XCTAssertTrue(message.contains("resume failed"))
    }

    @MainActor
    func testLiveNotificationsMergeMatchingThreadAndIgnoreOtherThreads() async throws {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let session = FakeThreadDetailSession(
            readResult: .success(ThreadReadResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            resumeResult: .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-1", turns: [])))
        )
        let store = ThreadDetailStore(
            host: host,
            row: row,
            factory: FakeThreadDetailSessionFactory(session: session),
            now: { Date(timeIntervalSince1970: 3_000) }
        )

        await store.load()
        await session.emitNotification(
            JSONRPCNotification(
                method: "item/agentMessage/delta",
                params: .object([
                    "threadId": .string("other-thread"),
                    "turnId": .string("turn-1"),
                    "itemId": .string("agent-1"),
                    "delta": .string("wrong"),
                ])
            )
        )
        try await Task.sleep(for: .milliseconds(50))

        guard case let .loaded(emptySnapshot) = store.state else {
            return XCTFail("Expected loaded state, got \(store.state)")
        }
        XCTAssertEqual(emptySnapshot.events, [])

        await session.emitNotification(
            JSONRPCNotification(
                method: "item/agentMessage/delta",
                params: .object([
                    "threadId": .string("thread-1"),
                    "turnId": .string("turn-1"),
                    "itemId": .string("agent-1"),
                    "delta": .string("hello "),
                ])
            )
        )
        await session.emitNotification(
            JSONRPCNotification(
                method: "item/agentMessage/delta",
                params: .object([
                    "threadId": .string("thread-1"),
                    "turnId": .string("turn-1"),
                    "itemId": .string("agent-1"),
                    "delta": .string("world"),
                ])
            )
        )

        try await waitForDetailStore {
            guard case let .loaded(snapshot) = store.state else {
                return false
            }
            return snapshot.events.map(\.body) == ["hello world"]
                && snapshot.liveState == .live
        }
    }

    @MainActor
    func testLiveDeltaAppearsBeforePagedHistoryAndMergesInPlace() async throws {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let session = FakeThreadDetailSession(
            readResult: .success(ThreadReadResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            turnsListResult: .success(
                ThreadTurnsListResponseDTO(data: [
                    makeDetailTurn(id: "turn-old", startedAt: 1_000, text: "Older stored"),
                ])
            ),
            resumeResult: .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-1", turns: [])))
        )
        let store = ThreadDetailStore(
            host: host,
            row: row,
            factory: FakeThreadDetailSessionFactory(session: session),
            now: { Date(timeIntervalSince1970: 3_000) }
        )

        await store.load()
        await session.emitNotification(
            JSONRPCNotification(
                method: "item/agentMessage/delta",
                params: .object([
                    "threadId": .string("thread-1"),
                    "turnId": .string("turn-live"),
                    "itemId": .string("agent-live"),
                    "delta": .string("hello "),
                ])
            )
        )
        await session.emitNotification(
            JSONRPCNotification(
                method: "item/agentMessage/delta",
                params: .object([
                    "threadId": .string("thread-1"),
                    "turnId": .string("turn-live"),
                    "itemId": .string("agent-live"),
                    "delta": .string("world"),
                ])
            )
        )

        try await waitForDetailStore {
            guard case let .loaded(snapshot) = store.state else {
                return false
            }
            return snapshot.events.map(\.body) == ["hello world", "Older stored"]
        }
    }

    @MainActor
    func testServerRequestAppearsAsNeedsAttentionEvent() async throws {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let session = FakeThreadDetailSession(
            readResult: .success(ThreadReadResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            resumeResult: .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-1", turns: [])))
        )
        let store = ThreadDetailStore(
            host: host,
            row: row,
            factory: FakeThreadDetailSessionFactory(session: session),
            now: { Date(timeIntervalSince1970: 3_000) }
        )

        await store.load()
        await session.emitServerRequest(
            JSONRPCRequest(
                id: .string("approval-1"),
                method: "item/commandExecution/requestApproval",
                params: .object([
                    "threadId": .string("thread-1"),
                    "command": .array([.string("make"), .string("test")]),
                ])
            )
        )

        try await waitForDetailStore {
            guard case let .loaded(snapshot) = store.state else {
                return false
            }
            return snapshot.events.count == 1
                && snapshot.events[0].kind == .request
                && snapshot.events[0].body == "make test"
        }
        XCTAssertEqual(store.requestCards.count, 1)
        XCTAssertEqual(store.requestCards[0].kind, .commandApproval)
    }

    @MainActor
    func testServerRequestEventAppearsNewestWithoutBreakingRequestCardResponse() async throws {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let session = FakeThreadDetailSession(
            readResult: .success(ThreadReadResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            turnsListResult: .success(
                ThreadTurnsListResponseDTO(data: [
                    makeDetailTurn(id: "turn-old", startedAt: 1_000, text: "Older stored"),
                ])
            ),
            resumeResult: .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-1", turns: [])))
        )
        let store = ThreadDetailStore(
            host: host,
            row: row,
            factory: FakeThreadDetailSessionFactory(session: session),
            now: { Date(timeIntervalSince1970: 3_000) }
        )

        await store.load()
        await session.emitServerRequest(
            JSONRPCRequest(
                id: .string("approval-1"),
                method: "item/commandExecution/requestApproval",
                params: .object([
                    "threadId": .string("thread-1"),
                    "turnId": .string("turn-live"),
                    "itemId": .string("cmd-live"),
                    "command": .array([.string("make"), .string("test")]),
                ])
            )
        )

        try await waitForDetailStore {
            guard case let .loaded(snapshot) = store.state else {
                return false
            }
            return snapshot.events.map(\.body) == ["make test", "Older stored"]
                && store.requestCards.count == 1
        }

        XCTAssertEqual(store.requestCards[0].kind, .commandApproval)
        await store.respond(to: "request-approval-1", action: .accept)

        let sentResponses = await session.sentResponsesSnapshot()
        XCTAssertEqual(
            sentResponses,
            [
                SentServerResponse(
                    id: .string("approval-1"),
                    result: .object(["decision": .string("accept")])
                ),
            ]
        )
        XCTAssertEqual(store.requestCards[0].status, .resolved)
    }

    @MainActor
    func testSendDraftStartsTurnWhenNoActiveTurnAndClearsDraft() async {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let session = FakeThreadDetailSession(
            readResult: .success(ThreadReadResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            resumeResult: .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            turnStartResult: .success(
                TurnStartResponseDTO(
                    turn: .object([
                        "id": .string("turn-new"),
                        "status": .string("inProgress"),
                    ])
                )
            )
        )
        let store = ThreadDetailStore(
            host: host,
            row: row,
            factory: FakeThreadDetailSessionFactory(session: session)
        )

        await store.load()
        store.updateDraft("Run the smoke test")
        await store.sendDraft()

        XCTAssertEqual(store.composer.draft, "")
        XCTAssertEqual(store.composer.lastError, nil)
        let startParams = await session.turnStartParamsSnapshot()
        let steerParams = await session.turnSteerParamsSnapshot()
        XCTAssertEqual(startParams, [
            TurnStartParams.text(threadId: "thread-1", text: "Run the smoke test"),
        ])
        XCTAssertEqual(steerParams, [])
    }

    @MainActor
    func testSendDraftSteersKnownActiveTurn() async {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let thread = ThreadDTO(
            id: "thread-1",
            turns: [
                .object([
                    "id": .string("active-turn"),
                    "status": .string("inProgress"),
                    "items": .array([]),
                ]),
            ]
        )
        let session = FakeThreadDetailSession(
            readResult: .success(ThreadReadResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            turnsListResult: .success(ThreadTurnsListResponseDTO(data: thread.turns ?? [])),
            resumeResult: .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            turnSteerResult: .success(TurnSteerResponseDTO(turnId: "active-turn"))
        )
        let store = ThreadDetailStore(
            host: host,
            row: row,
            factory: FakeThreadDetailSessionFactory(session: session)
        )

        await store.load()
        store.updateDraft("Also check the relay")
        await store.sendDraft()

        let startParams = await session.turnStartParamsSnapshot()
        let steerParams = await session.turnSteerParamsSnapshot()
        XCTAssertEqual(startParams, [])
        XCTAssertEqual(steerParams, [
            TurnSteerParams.text(
                threadId: "thread-1",
                text: "Also check the relay",
                expectedTurnId: "active-turn"
            ),
        ])
    }

    @MainActor
    func testSendDraftFailurePreservesDraftAndPublishesError() async {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let session = FakeThreadDetailSession(
            readResult: .success(ThreadReadResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            resumeResult: .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            turnStartResult: .failure(.turnFailed)
        )
        let store = ThreadDetailStore(
            host: host,
            row: row,
            factory: FakeThreadDetailSessionFactory(session: session)
        )

        await store.load()
        store.updateDraft("Do not lose this")
        await store.sendDraft()

        XCTAssertEqual(store.composer.draft, "Do not lose this")
        XCTAssertEqual(store.composer.isSending, false)
        XCTAssertEqual(store.composer.lastError, "turn failed")
    }

    @MainActor
    func testVoiceTranscriptInsertsDraftWithoutSending() async {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let session = FakeThreadDetailSession(
            readResult: .success(ThreadReadResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            resumeResult: .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-1", turns: [])))
        )
        let store = ThreadDetailStore(
            host: host,
            row: row,
            factory: FakeThreadDetailSessionFactory(session: session),
            voiceCapture: FakeVoiceCaptureController(),
            transcriptionService: FakeTranscriptionService(result: .success("Check relay status"))
        )

        await store.load()
        await store.beginVoiceCapture()
        XCTAssertEqual(store.composer.voice.phase, .recording)
        await store.finishVoiceCapture()

        XCTAssertEqual(store.composer.draft, "Check relay status")
        XCTAssertEqual(store.composer.voice, ComposerVoiceState())
        let beforeSendStartParams = await session.turnStartParamsSnapshot()
        XCTAssertEqual(beforeSendStartParams, [])

        await store.sendDraft()
        let afterSendStartParams = await session.turnStartParamsSnapshot()
        XCTAssertEqual(
            afterSendStartParams,
            [TurnStartParams.text(threadId: "thread-1", text: "Check relay status")]
        )
    }

    @MainActor
    func testVoiceTranscriptAppendsToEditableDraftWithoutAutoSubmit() async {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let session = FakeThreadDetailSession(
            readResult: .success(ThreadReadResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            resumeResult: .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-1", turns: [])))
        )
        let store = ThreadDetailStore(
            host: host,
            row: row,
            factory: FakeThreadDetailSessionFactory(session: session),
            voiceCapture: FakeVoiceCaptureController(),
            transcriptionService: FakeTranscriptionService(result: .success("then summarize failures"))
        )

        await store.load()
        store.updateDraft("Run tests")
        await store.beginVoiceCapture()
        await store.finishVoiceCapture()

        XCTAssertEqual(store.composer.draft, "Run tests then summarize failures")
        store.updateDraft("Run tests and summarize failures")
        XCTAssertEqual(store.composer.draft, "Run tests and summarize failures")
        let startParams = await session.turnStartParamsSnapshot()
        XCTAssertEqual(startParams, [])
    }

    @MainActor
    func testVoiceTranscriptionFailureKeepsDraftRecoverable() async {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let session = FakeThreadDetailSession(
            readResult: .success(ThreadReadResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            resumeResult: .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-1", turns: [])))
        )
        let store = ThreadDetailStore(
            host: host,
            row: row,
            factory: FakeThreadDetailSessionFactory(session: session),
            voiceCapture: FakeVoiceCaptureController(),
            transcriptionService: FakeTranscriptionService(result: .failure(.requestFailed(statusCode: 500)))
        )

        await store.load()
        store.updateDraft("Keep this")
        await store.beginVoiceCapture()
        await store.finishVoiceCapture()

        XCTAssertEqual(store.composer.draft, "Keep this")
        XCTAssertEqual(store.composer.voice.phase, .idle)
        XCTAssertEqual(store.composer.voice.lastError, "Transcription request failed.")
        let startParams = await session.turnStartParamsSnapshot()
        XCTAssertEqual(startParams, [])
    }

    @MainActor
    func testRespondingToRequestCardSendsJsonRPCResponseAndMarksResolved() async throws {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let session = FakeThreadDetailSession(
            readResult: .success(ThreadReadResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            resumeResult: .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-1", turns: [])))
        )
        let store = ThreadDetailStore(
            host: host,
            row: row,
            factory: FakeThreadDetailSessionFactory(session: session)
        )

        await store.load()
        await session.emitServerRequest(
            JSONRPCRequest(
                id: .string("approval-1"),
                method: "item/commandExecution/requestApproval",
                params: .object([
                    "threadId": .string("thread-1"),
                    "turnId": .string("turn-1"),
                    "itemId": .string("cmd-1"),
                    "command": .string("swift test"),
                ])
            )
        )
        try await waitForDetailStore {
            store.requestCards.count == 1
        }

        await store.respond(to: "request-approval-1", action: .accept)

        let sentResponses = await session.sentResponsesSnapshot()
        XCTAssertEqual(
            sentResponses,
            [
                SentServerResponse(
                    id: .string("approval-1"),
                    result: .object(["decision": .string("accept")])
                ),
            ]
        )
        XCTAssertEqual(store.requestCards[0].status, .resolved)
    }

    @MainActor
    func testThreadIdentityMismatchFailsVisible() async {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let session = FakeThreadDetailSession(
            readResult: .success(ThreadReadResponseDTO(thread: ThreadDTO(id: "wrong-thread", turns: []))),
            resumeResult: .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "wrong-thread", turns: [])))
        )
        let store = ThreadDetailStore(
            host: host,
            row: row,
            factory: FakeThreadDetailSessionFactory(session: session)
        )

        await store.load()

        guard case let .error(header, message) = store.state else {
            return XCTFail("Expected error state, got \(store.state)")
        }
        XCTAssertEqual(header.threadID, "thread-1")
        XCTAssertTrue(message.contains("wrong-thread"))
    }
}

private struct FakeThreadDetailSessionFactory: ThreadDetailSessionMaking {
    let session: FakeThreadDetailSession

    func makeSession(for host: DockHostConfiguration) -> any ThreadDetailSession {
        session
    }
}

private actor FakeThreadDetailSession: ThreadDetailSession {
    nonisolated let notifications: AsyncStream<JSONRPCNotification>
    nonisolated let serverRequests: AsyncStream<JSONRPCRequest>

    private let notificationContinuation: AsyncStream<JSONRPCNotification>.Continuation
    private let serverRequestContinuation: AsyncStream<JSONRPCRequest>.Continuation
    private let readResult: Result<ThreadReadResponseDTO, FakeThreadDetailError>
    private let turnsListResult: Result<ThreadTurnsListResponseDTO, FakeThreadDetailError>
    private let resumeResult: Result<ThreadResumeResponseDTO, FakeThreadDetailError>
    private let turnStartResult: Result<TurnStartResponseDTO, FakeThreadDetailError>
    private let turnSteerResult: Result<TurnSteerResponseDTO, FakeThreadDetailError>
    private var readParams: [ThreadReadParams] = []
    private var turnsListParams: [ThreadTurnsListParams] = []
    private var resumeParams: [ThreadResumeParams] = []
    private var turnStartParams: [TurnStartParams] = []
    private var turnSteerParams: [TurnSteerParams] = []
    private var sentResponses: [SentServerResponse] = []

    init(
        readResult: Result<ThreadReadResponseDTO, FakeThreadDetailError>,
        turnsListResult: Result<ThreadTurnsListResponseDTO, FakeThreadDetailError> = .success(
            ThreadTurnsListResponseDTO(data: [])
        ),
        resumeResult: Result<ThreadResumeResponseDTO, FakeThreadDetailError>,
        turnStartResult: Result<TurnStartResponseDTO, FakeThreadDetailError> = .success(
            TurnStartResponseDTO(
                turn: .object([
                    "id": .string("turn-started"),
                    "status": .string("inProgress"),
                ])
            )
        ),
        turnSteerResult: Result<TurnSteerResponseDTO, FakeThreadDetailError> = .success(
            TurnSteerResponseDTO(turnId: "turn-started")
        )
    ) {
        let notifications = AsyncStream.makeStream(of: JSONRPCNotification.self)
        let serverRequests = AsyncStream.makeStream(of: JSONRPCRequest.self)
        self.notifications = notifications.stream
        self.notificationContinuation = notifications.continuation
        self.serverRequests = serverRequests.stream
        self.serverRequestContinuation = serverRequests.continuation
        self.readResult = readResult
        self.turnsListResult = turnsListResult
        self.resumeResult = resumeResult
        self.turnStartResult = turnStartResult
        self.turnSteerResult = turnSteerResult
    }

    func connectAndInitialize(
        params: InitializeParams,
        timeout: Duration
    ) async throws -> InitializeResponse {
        InitializeResponse(
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
        return try readResult.get()
    }

    func threadTurnsList(
        params: ThreadTurnsListParams,
        timeout: Duration
    ) async throws -> ThreadTurnsListResponseDTO {
        turnsListParams.append(params)
        return try turnsListResult.get()
    }

    func threadResume(
        params: ThreadResumeParams,
        timeout: Duration
    ) async throws -> ThreadResumeResponseDTO {
        resumeParams.append(params)
        return try resumeResult.get()
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
        notificationContinuation.finish()
        serverRequestContinuation.finish()
    }

    func emitNotification(_ notification: JSONRPCNotification) {
        notificationContinuation.yield(notification)
    }

    func emitServerRequest(_ request: JSONRPCRequest) {
        serverRequestContinuation.yield(request)
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

@MainActor
private final class FakeVoiceCaptureController: VoiceCaptureControlling {
    private let audioURL: URL

    init() {
        self.audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
    }

    func startRecording() async throws -> URL {
        try Data("fake audio".utf8).write(to: audioURL)
        return audioURL
    }

    func stopRecording() async throws -> URL {
        audioURL
    }

    func cancelRecording() async {}
}

private struct FakeTranscriptionService: TranscriptionServicing {
    let result: Result<String, TranscriptionServiceError>

    func transcribe(audioFile: URL) async throws -> String {
        try result.get()
    }
}

private enum FakeThreadDetailError: Error, LocalizedError, Sendable {
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

private struct SentServerResponse: Equatable, Sendable {
    let id: JSONRPCRequestID
    let result: JSONValue
}

private func makeDetailHost() -> DockHostConfiguration {
    DockHostConfiguration(
        id: "Amir-M5",
        displayName: "Amir-M5",
        webSocketURL: URL(string: "ws://192.168.50.117:4510")!,
        bearerToken: "test-token"
    )
}

private func makeDetailRow(hostID: String, threadID: String) -> DockRowViewModel {
    DockRowViewModel(
        id: HostScopedThreadID(hostID: hostID, threadID: threadID),
        backendSessionID: "\(threadID)-session",
        title: "Build live detail",
        repository: "codex-client",
        branch: "main",
        status: .running,
        lastActivity: "now",
        lastActivityDate: Date(timeIntervalSince1970: 2_000),
        summary: "Open a real thread",
        rail: .blue,
        label: nil,
        origin: .humanInteractive(subtype: .cli)
    )
}

private func makeDetailThread(_ id: String, text: String) -> ThreadDTO {
    ThreadDTO(
        id: id,
        turns: [
            makeDetailTurn(id: "turn-1", text: text),
        ]
    )
}

private func makeDetailTurn(
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
private func waitForDetailStore(
    timeout: Duration = .seconds(1),
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

private struct DetailStoreTimeoutError: Error {}

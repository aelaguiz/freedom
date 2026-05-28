import XCTest
@testable import CodexDock

final class ThreadDetailStoreTests: XCTestCase {
    @MainActor
    func testLoadReadsAndResumesMatchingThread() async throws {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let session = FakeThreadDetailSession(
            readResult: .success(
                ThreadReadResponseDTO(thread: makeDetailThread("thread-1", text: "Stored turn"))
            ),
            resumeResult: .success(
                ThreadResumeResponseDTO(thread: makeDetailThread("thread-1", text: "Live turn"))
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
        XCTAssertEqual(snapshot.events.map(\.body), ["Live turn"])
        let readParams = await session.readParamsSnapshot()
        let resumeParams = await session.resumeParamsSnapshot()
        XCTAssertEqual(readParams, [
            ThreadReadParams(threadId: "thread-1", includeTurns: true),
        ])
        XCTAssertEqual(resumeParams, [
            ThreadResumeParams(threadId: "thread-1"),
        ])
    }

    @MainActor
    func testResumeFailureKeepsReadEventsAndMarksDetailStale() async {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let session = FakeThreadDetailSession(
            readResult: .success(
                ThreadReadResponseDTO(thread: makeDetailThread("thread-1", text: "Stored turn"))
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
    private let resumeResult: Result<ThreadResumeResponseDTO, FakeThreadDetailError>
    private var readParams: [ThreadReadParams] = []
    private var resumeParams: [ThreadResumeParams] = []

    init(
        readResult: Result<ThreadReadResponseDTO, FakeThreadDetailError>,
        resumeResult: Result<ThreadResumeResponseDTO, FakeThreadDetailError>
    ) {
        let notifications = AsyncStream.makeStream(of: JSONRPCNotification.self)
        let serverRequests = AsyncStream.makeStream(of: JSONRPCRequest.self)
        self.notifications = notifications.stream
        self.notificationContinuation = notifications.continuation
        self.serverRequests = serverRequests.stream
        self.serverRequestContinuation = serverRequests.continuation
        self.readResult = readResult
        self.resumeResult = resumeResult
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

    func threadResume(
        params: ThreadResumeParams,
        timeout: Duration
    ) async throws -> ThreadResumeResponseDTO {
        resumeParams.append(params)
        return try resumeResult.get()
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

    func resumeParamsSnapshot() -> [ThreadResumeParams] {
        resumeParams
    }
}

private enum FakeThreadDetailError: Error, LocalizedError, Sendable {
    case resumeFailed

    var errorDescription: String? {
        switch self {
        case .resumeFailed:
            return "resume failed"
        }
    }
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
        title: "Build live detail",
        repository: "codex-client",
        branch: "main",
        status: .running,
        lastActivity: "now",
        lastActivityDate: Date(timeIntervalSince1970: 2_000),
        summary: "Open a real thread",
        rail: .blue
    )
}

private func makeDetailThread(_ id: String, text: String) -> ThreadDTO {
    ThreadDTO(
        id: id,
        turns: [
            .object([
                "id": .string("turn-1"),
                "items": .array([
                    .object([
                        "id": .string("agent-1"),
                        "type": .string("agentMessage"),
                        "text": .string(text),
                    ]),
                ]),
            ]),
        ]
    )
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

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
            ThreadTurnsListParams(threadId: "thread-1", limit: 250, sortDirection: .desc, itemsView: .full),
        ])
        XCTAssertEqual(resumeParams, [
            ThreadResumeParams(threadId: "thread-1", excludeTurns: true),
        ])
    }

    @MainActor
    func testLoadBuffersLiveNotificationsUntilReadTurnsAndResumeFinish() async throws {
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
            ),
            resumeDelay: .milliseconds(100)
        )
        let store = ThreadDetailStore(
            host: host,
            row: row,
            factory: FakeThreadDetailSessionFactory(session: session),
            now: { Date(timeIntervalSince1970: 3_000) }
        )

        let loadTask = Task {
            await store.load()
        }
        let start = ContinuousClock.now
        var resumeStarted = false
        while start.duration(to: .now) < .seconds(2) {
            if await !session.resumeParamsSnapshot().isEmpty {
                resumeStarted = true
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(resumeStarted)

        await session.emitNotification(
            JSONRPCNotification(
                method: "item/agentMessage/delta",
                params: .object([
                    "threadId": .string("thread-1"),
                    "turnId": .string("turn-live"),
                    "itemId": .string("agent-live"),
                    "delta": .string("Buffered live"),
                ])
            )
        )
        await loadTask.value

        guard case let .loaded(snapshot) = store.state else {
            return XCTFail("Expected loaded state, got \(store.state)")
        }
        XCTAssertEqual(snapshot.liveState, .live)
        XCTAssertEqual(snapshot.events.map(\.body), ["Buffered live", "Paged turn"])
    }

    @MainActor
    func testLoadPagesAllTurnsAndPublishesNewestFirstForDisplay() async throws {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let session = FakeThreadDetailSession(
            readResult: .success(ThreadReadResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            resumeResult: .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            turnsListResults: [
                .success(
                    ThreadTurnsListResponseDTO(
                        data: [
                            makeDetailTurn(id: "turn-old", startedAt: 1_700_000_000, text: "Old paged turn"),
                        ],
                        nextCursor: "page-2"
                    )
                ),
                .success(
                    ThreadTurnsListResponseDTO(data: [
                        makeDetailTurn(id: "turn-new", startedAt: 1_700_000_100, text: "New paged turn"),
                    ])
                ),
            ]
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
            ThreadTurnsListParams(threadId: "thread-1", limit: 250, sortDirection: .desc, itemsView: .full),
            ThreadTurnsListParams(threadId: "thread-1", cursor: "page-2", limit: 250, sortDirection: .desc, itemsView: .full),
        ])
        XCTAssertEqual(resumeParams, [
            ThreadResumeParams(threadId: "thread-1", excludeTurns: true),
        ])
    }

    @MainActor
    func testLoadFailsLoudlyWhenTurnsCursorRepeats() async throws {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let session = FakeThreadDetailSession(
            readResult: .success(ThreadReadResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            resumeResult: .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            turnsListResults: [
                .success(
                    ThreadTurnsListResponseDTO(
                        data: [
                            makeDetailTurn(id: "turn-old", startedAt: 1_700_000_000, text: "Old paged turn"),
                        ],
                        nextCursor: "same-page"
                    )
                ),
                .success(
                    ThreadTurnsListResponseDTO(
                        data: [
                            makeDetailTurn(id: "turn-new", startedAt: 1_700_000_100, text: "New paged turn"),
                        ],
                        nextCursor: "same-page"
                    )
                ),
            ]
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
        XCTAssertTrue(message.contains("repeated thread turns cursor same-page"))
        let turnsListParams = await session.turnsListParamsSnapshot()
        let resumeParams = await session.resumeParamsSnapshot()
        XCTAssertEqual(turnsListParams, [
            ThreadTurnsListParams(threadId: "thread-1", limit: 250, sortDirection: .desc, itemsView: .full),
            ThreadTurnsListParams(threadId: "thread-1", cursor: "same-page", limit: 250, sortDirection: .desc, itemsView: .full),
        ])
        XCTAssertEqual(resumeParams, [ThreadResumeParams]())
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
            resumeResult: .failure(FakeThreadDetailError.resumeFailed)
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
    func testHumanOnlyThreadRejectionShowsUnavailableAndDoesNotResume() async {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "spawned-child")
        let rejected = AppServerClientError.server(
            JSONRPCErrorObject(
                code: -32043,
                message: "thread rejected by human-only filter",
                data: .object([
                    "threadId": .string("spawned-child"),
                    "reason": .string("sub_agent_thread_spawn"),
                ])
            )
        )
        let session = FakeThreadDetailSession(
            readResult: .failure(rejected),
            resumeResult: .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "spawned-child", turns: [])))
        )
        let store = ThreadDetailStore(
            host: host,
            row: row,
            factory: FakeThreadDetailSessionFactory(session: session)
        )

        await store.load()

        guard case let .error(header, message) = store.state else {
            return XCTFail("Expected unavailable detail, got \(store.state)")
        }
        XCTAssertEqual(header.threadID, "spawned-child")
        XCTAssertEqual(message, "Thread unavailable.")
        let resumeParams = await session.resumeParamsSnapshot()
        XCTAssertEqual(resumeParams, [])
    }

    @MainActor
    func testConnectionOfflineMarksLoadedLiveDetailStale() async throws {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let session = FakeThreadDetailSession(
            readResult: .success(ThreadReadResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            turnsListResult: .success(
                ThreadTurnsListResponseDTO(data: makeDetailThread("thread-1", text: "Stored turn").turns ?? [])
            ),
            resumeResult: .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-1", turns: [])))
        )
        let store = ThreadDetailStore(
            host: host,
            row: row,
            factory: FakeThreadDetailSessionFactory(session: session)
        )

        await store.load()
        await session.emitConnectionState(.offline(reason: "transport closed"))

        try await waitForDetailStore {
            guard case let .loaded(snapshot) = store.state,
                  case let .stale(message) = snapshot.liveState else {
                return false
            }
            return message == "transport closed"
                && snapshot.events.map(\.body) == ["Stored turn"]
        }
    }

    @MainActor
    func testConnectionErrorMarksLoadedLiveDetailStale() async throws {
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
        await session.emitConnectionState(.error(message: "malformed app-server message"))

        try await waitForDetailStore {
            guard case let .loaded(snapshot) = store.state,
                  case let .stale(message) = snapshot.liveState else {
                return false
            }
            return message == "malformed app-server message"
        }
    }

    @MainActor
    func testNotificationStreamEndMarksLoadedLiveDetailStale() async throws {
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
        await session.finishNotifications()

        try await waitForDetailStore {
            guard case let .loaded(snapshot) = store.state,
                  case let .stale(message) = snapshot.liveState else {
                return false
            }
            return message == "Live update stream ended."
        }
    }

    @MainActor
    func testServerRequestStreamEndMarksLoadedLiveDetailStale() async throws {
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
        await session.finishServerRequests()

        try await waitForDetailStore {
            guard case let .loaded(snapshot) = store.state,
                  case let .stale(message) = snapshot.liveState else {
                return false
            }
            return message == "Server request stream ended."
        }
    }

    @MainActor
    func testCloseDoesNotPublishStaleWhenSessionStreamsEnd() async throws {
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
        store.close()
        try await Task.sleep(for: .milliseconds(50))

        guard case let .loaded(snapshot) = store.state else {
            return XCTFail("Expected loaded state, got \(store.state)")
        }
        XCTAssertEqual(snapshot.liveState, .live)
    }

    @MainActor
    func testConnectionDropPreservesDraftRequestCardsAndEvents() async throws {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let session = FakeThreadDetailSession(
            readResult: .success(ThreadReadResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            turnsListResult: .success(
                ThreadTurnsListResponseDTO(data: [
                    makeDetailTurn(id: "turn-old", startedAt: 1_000, text: "Stored turn"),
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
        store.updateDraft("Keep this draft")
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
            store.requestCards.count == 1
        }

        await session.emitConnectionState(.offline(reason: "transport closed"))

        try await waitForDetailStore {
            guard case let .loaded(snapshot) = store.state,
                  case let .stale(message) = snapshot.liveState else {
                return false
            }
            return message == "transport closed"
                && snapshot.events.map(\.body) == ["make test", "Stored turn"]
        }
        XCTAssertEqual(store.composer.draft, "Keep this draft")
        XCTAssertEqual(store.requestCards.count, 1)
        XCTAssertEqual(store.requestCards[0].status, .pending)
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
    func testLiveDeltaAppearsAfterPagedHistoryAndMergesInPlace() async throws {
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
                    "startedAtMs": .integer(2_999_000),
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
                && snapshot.events[0].visibilityCategory == .request
                && snapshot.events[0].body == "make test"
        }
        XCTAssertEqual(store.requestCards.count, 1)
        XCTAssertEqual(store.requestCards[0].kind, .commandApproval)
        XCTAssertEqual(store.requestCards[0].requestedAt, Date(timeIntervalSince1970: 2_999))
        if case let .loaded(snapshot) = store.state {
            XCTAssertEqual(snapshot.events[0].date, Date(timeIntervalSince1970: 2_999))
            XCTAssertEqual(snapshot.events[0].activityDate, Date(timeIntervalSince1970: 2_999))
        }
    }

    @MainActor
    func testServerRequestEventAppearsNewestFirstWithoutBreakingRequestCardResponse() async throws {
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
            turnStartResult: .failure(FakeThreadDetailError.turnFailed)
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
    func testVoicePartialTextUpdatesDraftBeforeCommit() async throws {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let session = FakeThreadDetailSession(
            readResult: .success(ThreadReadResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            resumeResult: .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-1", turns: [])))
        )
        let realtime = FakeRealtimeTranscriptionService()
        let store = ThreadDetailStore(
            host: host,
            row: row,
            factory: FakeThreadDetailSessionFactory(session: session),
            realtimeTranscriptionService: realtime
        )

        await store.load()
        await store.beginVoiceCapture()
        XCTAssertEqual(store.composer.voice.phase, .streaming)
        XCTAssertFalse(store.composer.canSend)

        realtime.session.emit(
            .delta(
                sessionID: realtime.session.id,
                itemID: "item-1",
                sequence: 1,
                deltaText: "Check",
                partialText: "Check"
            )
        )

        try await waitForDetailStore {
            store.composer.draft == "Check"
        }
        XCTAssertEqual(store.composer.voice.provisionalTranscript, "Check")
        let startParams = await session.turnStartParamsSnapshot()
        XCTAssertEqual(startParams, [])
    }

    @MainActor
    func testVoiceStreamsLiveCaptureChunksIntoRealtimeSessionBeforeCommit() async throws {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let session = FakeThreadDetailSession(
            readResult: .success(ThreadReadResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            resumeResult: .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-1", turns: [])))
        )
        let realtimeSession = FakeRealtimeTranscriptionSession()
        realtimeSession.eventsOnCommit = [
            .completed(sessionID: realtimeSession.id, itemID: "item-1", text: "capture worked"),
        ]
        let realtime = FakeRealtimeTranscriptionService(session: realtimeSession)
        let capture = FakeLiveVoiceCaptureController()
        let store = ThreadDetailStore(
            host: host,
            row: row,
            factory: FakeThreadDetailSessionFactory(session: session),
            realtimeTranscriptionService: realtime,
            liveVoiceCaptureController: capture
        )

        await store.load()
        await store.beginVoiceCapture()
        XCTAssertEqual(store.composer.voice.phase, .streaming)

        capture.session.emit(
            VoiceAudioChunk(sequence: 1, audio: Data([1, 2, 3]), format: .pcm16Mono24k)
        )
        capture.session.emit(
            VoiceAudioChunk(sequence: 2, audio: Data([4, 5, 6]), format: .pcm16Mono24k)
        )

        try await waitForDetailStore {
            realtimeSession.appendedChunks.count == 2
        }
        XCTAssertEqual(realtimeSession.appendedChunks[0].chunk, Data([1, 2, 3]))
        XCTAssertEqual(realtimeSession.appendedChunks[0].sequence, 1)
        XCTAssertEqual(realtimeSession.appendedChunks[1].chunk, Data([4, 5, 6]))
        XCTAssertEqual(realtimeSession.appendedChunks[1].sequence, 2)

        await store.finishVoiceCapture()

        XCTAssertEqual(capture.session.stopCount, 1)
        XCTAssertEqual(realtimeSession.commitCount, 1)
        XCTAssertEqual(store.composer.draft, "capture worked")
    }

    @MainActor
    func testVoiceFinalTranscriptReplacesCumulativePartialWithoutAutoSubmit() async throws {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let session = FakeThreadDetailSession(
            readResult: .success(ThreadReadResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            resumeResult: .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-1", turns: [])))
        )
        let realtimeSession = FakeRealtimeTranscriptionSession()
        realtimeSession.eventsOnCommit = [
            .completed(sessionID: realtimeSession.id, itemID: "item-1", text: "Check relay status"),
        ]
        let realtime = FakeRealtimeTranscriptionService(session: realtimeSession)
        let store = ThreadDetailStore(
            host: host,
            row: row,
            factory: FakeThreadDetailSessionFactory(session: session),
            realtimeTranscriptionService: realtime
        )

        await store.load()
        await store.beginVoiceCapture()
        realtime.session.emit(
            .delta(
                sessionID: realtime.session.id,
                itemID: "item-1",
                sequence: 1,
                deltaText: "Check",
                partialText: "Check"
            )
        )
        realtime.session.emit(
            .delta(
                sessionID: realtime.session.id,
                itemID: "item-1",
                sequence: 2,
                deltaText: " relay",
                partialText: "Check relay"
            )
        )
        try await waitForDetailStore {
            store.composer.draft == "Check relay"
        }

        await store.finishVoiceCapture()

        XCTAssertEqual(realtime.session.commitCount, 1)
        XCTAssertEqual(store.composer.draft, "Check relay status")
        XCTAssertEqual(store.composer.voice, ComposerVoiceState())
        let beforeSendStartParams = await session.turnStartParamsSnapshot()
        XCTAssertEqual(beforeSendStartParams, [])

        await store.sendDraft()
        let afterSendStartParams = await session.turnStartParamsSnapshot()
        XCTAssertEqual(afterSendStartParams, [
            TurnStartParams.text(threadId: "thread-1", text: "Check relay status"),
        ])
    }

    @MainActor
    func testVoiceReleaseWhileStartingCommitsAfterSessionAndCaptureStart() async throws {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let session = FakeThreadDetailSession(
            readResult: .success(ThreadReadResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            resumeResult: .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-1", turns: [])))
        )
        let realtimeSession = FakeRealtimeTranscriptionSession()
        realtimeSession.eventsOnCommit = [
            .completed(sessionID: realtimeSession.id, itemID: "item-1", text: "late release transcript"),
        ]
        let realtime = FakeRealtimeTranscriptionService(
            session: realtimeSession,
            startDelay: .milliseconds(50)
        )
        let capture = FakeLiveVoiceCaptureController()
        let store = ThreadDetailStore(
            host: host,
            row: row,
            factory: FakeThreadDetailSessionFactory(session: session),
            realtimeTranscriptionService: realtime,
            liveVoiceCaptureController: capture
        )

        await store.load()
        let beginTask = Task {
            await store.beginVoiceCapture()
        }
        try await waitForDetailStore {
            store.composer.voice.phase == .starting
        }

        await store.finishVoiceCapture()
        XCTAssertEqual(store.composer.voice.phase, .finalizing)
        await beginTask.value

        try await waitForDetailStore {
            store.composer.draft == "late release transcript"
        }
        XCTAssertEqual(capture.startCount, 1)
        XCTAssertEqual(capture.session.stopCount, 1)
        XCTAssertEqual(realtimeSession.commitCount, 1)
        XCTAssertEqual(store.composer.voice, ComposerVoiceState())
    }

    @MainActor
    func testTapVoiceCaptureStartsAndStopsWithoutAutoSubmit() async throws {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let session = FakeThreadDetailSession(
            readResult: .success(ThreadReadResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            resumeResult: .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-1", turns: [])))
        )
        let realtimeSession = FakeRealtimeTranscriptionSession()
        realtimeSession.eventsOnCommit = [
            .completed(sessionID: realtimeSession.id, itemID: "item-1", text: "tap transcript"),
        ]
        let realtime = FakeRealtimeTranscriptionService(session: realtimeSession)
        let capture = FakeLiveVoiceCaptureController()
        let store = ThreadDetailStore(
            host: host,
            row: row,
            factory: FakeThreadDetailSessionFactory(session: session),
            realtimeTranscriptionService: realtime,
            liveVoiceCaptureController: capture
        )

        await store.load()
        store.updateDraft("Prefix")
        await store.toggleTapVoiceCapture()

        XCTAssertEqual(store.composer.voice.phase, .streaming)
        XCTAssertEqual(store.composer.voice.interactionMode, .tap)
        XCTAssertFalse(store.composer.canSend)

        capture.session.emit(
            VoiceAudioChunk(sequence: 1, audio: Data([1, 2, 3]), format: .pcm16Mono24k)
        )
        try await waitForDetailStore {
            realtimeSession.appendedChunks.count == 1
        }

        await store.toggleTapVoiceCapture()

        XCTAssertEqual(capture.session.stopCount, 1)
        XCTAssertEqual(realtimeSession.commitCount, 1)
        XCTAssertEqual(store.composer.draft, "Prefix tap transcript")
        XCTAssertEqual(store.composer.voice, ComposerVoiceState())
        let startParams = await session.turnStartParamsSnapshot()
        XCTAssertEqual(startParams, [])
    }

    @MainActor
    func testTapVoiceCaptureRepeatedStopWhileFinalizingDoesNotDuplicateCommit() async throws {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let session = FakeThreadDetailSession(
            readResult: .success(ThreadReadResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            resumeResult: .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-1", turns: [])))
        )
        let realtimeSession = FakeRealtimeTranscriptionSession()
        realtimeSession.commitDelay = .milliseconds(50)
        realtimeSession.eventsOnCommit = [
            .completed(sessionID: realtimeSession.id, itemID: "item-1", text: "single commit"),
        ]
        let realtime = FakeRealtimeTranscriptionService(session: realtimeSession)
        let capture = FakeLiveVoiceCaptureController()
        let store = ThreadDetailStore(
            host: host,
            row: row,
            factory: FakeThreadDetailSessionFactory(session: session),
            realtimeTranscriptionService: realtime,
            liveVoiceCaptureController: capture
        )

        await store.load()
        await store.toggleTapVoiceCapture()
        let stopTask = Task {
            await store.toggleTapVoiceCapture()
        }
        try await waitForDetailStore {
            store.composer.voice.phase == .finalizing
        }

        await store.toggleTapVoiceCapture()
        await stopTask.value

        XCTAssertEqual(realtimeSession.commitCount, 1)
        XCTAssertEqual(capture.session.stopCount, 1)
        XCTAssertEqual(store.composer.draft, "single commit")
        XCTAssertEqual(store.composer.voice, ComposerVoiceState())
    }

    @MainActor
    func testTapVoiceCaptureStopWhileStartingCommitsAfterSessionAndCaptureStart() async throws {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let session = FakeThreadDetailSession(
            readResult: .success(ThreadReadResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            resumeResult: .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-1", turns: [])))
        )
        let realtimeSession = FakeRealtimeTranscriptionSession()
        realtimeSession.eventsOnCommit = [
            .completed(sessionID: realtimeSession.id, itemID: "item-1", text: "rapid tap transcript"),
        ]
        let realtime = FakeRealtimeTranscriptionService(
            session: realtimeSession,
            startDelay: .milliseconds(50)
        )
        let capture = FakeLiveVoiceCaptureController()
        let store = ThreadDetailStore(
            host: host,
            row: row,
            factory: FakeThreadDetailSessionFactory(session: session),
            realtimeTranscriptionService: realtime,
            liveVoiceCaptureController: capture
        )

        await store.load()
        let startTask = Task {
            await store.toggleTapVoiceCapture()
        }
        try await waitForDetailStore {
            store.composer.voice.phase == .starting
                && store.composer.voice.interactionMode == .tap
        }

        await store.toggleTapVoiceCapture()
        XCTAssertEqual(store.composer.voice.phase, .finalizing)
        await startTask.value

        try await waitForDetailStore {
            store.composer.draft == "rapid tap transcript"
        }
        XCTAssertEqual(capture.startCount, 1)
        XCTAssertEqual(capture.session.stopCount, 1)
        XCTAssertEqual(realtimeSession.commitCount, 1)
        XCTAssertEqual(store.composer.voice, ComposerVoiceState())
    }

    @MainActor
    func testHoldReleaseDoesNotFinalizeActiveTapDictation() async throws {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let session = FakeThreadDetailSession(
            readResult: .success(ThreadReadResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            resumeResult: .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-1", turns: [])))
        )
        let realtimeSession = FakeRealtimeTranscriptionSession()
        realtimeSession.eventsOnCommit = [
            .completed(sessionID: realtimeSession.id, itemID: "item-1", text: "tap transcript"),
        ]
        let realtime = FakeRealtimeTranscriptionService(session: realtimeSession)
        let capture = FakeLiveVoiceCaptureController()
        let store = ThreadDetailStore(
            host: host,
            row: row,
            factory: FakeThreadDetailSessionFactory(session: session),
            realtimeTranscriptionService: realtime,
            liveVoiceCaptureController: capture
        )

        await store.load()
        await store.toggleTapVoiceCapture()
        await store.finishVoiceCapture()

        XCTAssertEqual(store.composer.voice.phase, .streaming)
        XCTAssertEqual(store.composer.voice.interactionMode, .tap)
        XCTAssertEqual(realtimeSession.commitCount, 0)
        XCTAssertEqual(capture.session.stopCount, 0)

        await store.toggleTapVoiceCapture()

        XCTAssertEqual(realtimeSession.commitCount, 1)
        XCTAssertEqual(capture.session.stopCount, 1)
        XCTAssertEqual(store.composer.draft, "tap transcript")
    }

    @MainActor
    func testTapVoiceCaptureCloseCancelsCaptureAndSessionWithoutSubmitting() async throws {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let session = FakeThreadDetailSession(
            readResult: .success(ThreadReadResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            resumeResult: .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-1", turns: [])))
        )
        let realtime = FakeRealtimeTranscriptionService()
        let capture = FakeLiveVoiceCaptureController()
        let store = ThreadDetailStore(
            host: host,
            row: row,
            factory: FakeThreadDetailSessionFactory(session: session),
            realtimeTranscriptionService: realtime,
            liveVoiceCaptureController: capture
        )

        await store.load()
        store.updateDraft("Keep this")
        await store.toggleTapVoiceCapture()
        realtime.session.emit(
            .delta(
                sessionID: realtime.session.id,
                itemID: "item-1",
                sequence: 1,
                deltaText: "partial",
                partialText: "partial"
            )
        )
        try await waitForDetailStore {
            store.composer.draft == "Keep this partial"
        }

        store.close()

        try await waitForDetailStore {
            realtime.session.cancelCount == 1
        }
        XCTAssertEqual(capture.session.cancelCount, 1)
        XCTAssertEqual(store.composer.draft, "Keep this")
        XCTAssertEqual(store.composer.voice, ComposerVoiceState())
        let startParams = await session.turnStartParamsSnapshot()
        XCTAssertEqual(startParams, [])
    }

    @MainActor
    func testUnexpectedCaptureStreamEndFailsRecoverablyWithoutSubmitting() async throws {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let session = FakeThreadDetailSession(
            readResult: .success(ThreadReadResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            resumeResult: .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-1", turns: [])))
        )
        let realtime = FakeRealtimeTranscriptionService()
        let capture = FakeLiveVoiceCaptureController()
        let store = ThreadDetailStore(
            host: host,
            row: row,
            factory: FakeThreadDetailSessionFactory(session: session),
            realtimeTranscriptionService: realtime,
            liveVoiceCaptureController: capture
        )

        await store.load()
        store.updateDraft("Keep")
        await store.toggleTapVoiceCapture()
        capture.session.emit(
            VoiceAudioChunk(sequence: 1, audio: Data([1, 2, 3]), format: .pcm16Mono24k)
        )
        try await waitForDetailStore {
            realtime.session.appendedChunks.count == 1
        }
        realtime.session.emit(
            .delta(
                sessionID: realtime.session.id,
                itemID: "item-1",
                sequence: 1,
                deltaText: "partial",
                partialText: "partial"
            )
        )
        try await waitForDetailStore(timeout: .seconds(5)) {
            store.composer.draft == "Keep partial"
        }

        capture.session.finishChunks()

        try await waitForDetailStore(timeout: .seconds(15)) {
            store.composer.voice.lastError == "Voice capture stopped. Try again."
        }
        XCTAssertEqual(realtime.session.cancelCount, 1)
        XCTAssertEqual(store.composer.draft, "Keep partial")
        let startParams = await session.turnStartParamsSnapshot()
        XCTAssertEqual(startParams, [])
    }

    @MainActor
    func testHoldVoiceCaptureStreamEndWhileHeldFailsRecoverablyAndReleaseDoesNotCommit() async throws {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let session = FakeThreadDetailSession(
            readResult: .success(ThreadReadResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            resumeResult: .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-1", turns: [])))
        )
        let realtime = FakeRealtimeTranscriptionService()
        let capture = FakeLiveVoiceCaptureController()
        let store = ThreadDetailStore(
            host: host,
            row: row,
            factory: FakeThreadDetailSessionFactory(session: session),
            realtimeTranscriptionService: realtime,
            liveVoiceCaptureController: capture
        )

        await store.load()
        store.updateDraft("Keep")
        await store.beginVoiceCapture()
        XCTAssertEqual(store.composer.voice.phase, .streaming)
        XCTAssertEqual(store.composer.voice.interactionMode, .hold)

        capture.session.emit(
            VoiceAudioChunk(sequence: 1, audio: Data([1, 2, 3]), format: .pcm16Mono24k)
        )
        try await waitForDetailStore {
            realtime.session.appendedChunks.count == 1
        }
        realtime.session.emit(
            .delta(
                sessionID: realtime.session.id,
                itemID: "item-1",
                sequence: 1,
                deltaText: "partial",
                partialText: "partial"
            )
        )
        try await waitForDetailStore(timeout: .seconds(5)) {
            store.composer.draft == "Keep partial"
        }

        capture.session.finishChunks()

        try await waitForDetailStore(timeout: .seconds(15)) {
            store.composer.voice.lastError == "Voice capture stopped. Try again."
        }
        XCTAssertEqual(store.composer.draft, "Keep partial")
        XCTAssertEqual(realtime.session.cancelCount, 1)
        XCTAssertEqual(realtime.session.commitCount, 0)
        XCTAssertEqual(capture.session.cancelCount, 1)
        XCTAssertEqual(capture.session.stopCount, 0)
        let startParams = await session.turnStartParamsSnapshot()
        XCTAssertEqual(startParams, [])

        await store.finishVoiceCapture()

        XCTAssertEqual(realtime.session.cancelCount, 1)
        XCTAssertEqual(realtime.session.commitCount, 0)
        XCTAssertEqual(capture.session.cancelCount, 1)
        XCTAssertEqual(capture.session.stopCount, 0)
    }

    @MainActor
    func testTranscriptionEventStreamEndWhileBusyFailsRecoverably() async throws {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let session = FakeThreadDetailSession(
            readResult: .success(ThreadReadResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            resumeResult: .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-1", turns: [])))
        )
        let realtime = FakeRealtimeTranscriptionService()
        let capture = FakeLiveVoiceCaptureController()
        let store = ThreadDetailStore(
            host: host,
            row: row,
            factory: FakeThreadDetailSessionFactory(session: session),
            realtimeTranscriptionService: realtime,
            liveVoiceCaptureController: capture
        )

        await store.load()
        store.updateDraft("Keep")
        await store.beginVoiceCapture()
        realtime.session.emit(
            .delta(
                sessionID: realtime.session.id,
                itemID: "item-1",
                sequence: 1,
                deltaText: "partial",
                partialText: "partial"
            )
        )
        try await waitForDetailStore {
            store.composer.draft == "Keep partial"
        }

        realtime.session.finish()

        try await waitForDetailStore {
            store.composer.voice.lastError == "Realtime transcription stopped. Try again."
        }
        XCTAssertEqual(store.composer.draft, "Keep partial")
        XCTAssertEqual(capture.session.cancelCount, 1)
        XCTAssertEqual(capture.session.stopCount, 0)
        XCTAssertEqual(realtime.session.commitCount, 0)
        XCTAssertEqual(store.composer.canSend, true)
    }

    @MainActor
    func testHoldAndTapVoiceControlsDoNotCreateDuplicateStreams() async throws {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let session = FakeThreadDetailSession(
            readResult: .success(ThreadReadResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            resumeResult: .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-1", turns: [])))
        )
        let realtime = FakeRealtimeTranscriptionService()
        let capture = FakeLiveVoiceCaptureController()
        let store = ThreadDetailStore(
            host: host,
            row: row,
            factory: FakeThreadDetailSessionFactory(session: session),
            realtimeTranscriptionService: realtime,
            liveVoiceCaptureController: capture
        )

        await store.load()
        await store.beginVoiceCapture()
        await store.toggleTapVoiceCapture()

        XCTAssertEqual(realtime.startCount, 1)
        XCTAssertEqual(capture.startCount, 1)
        XCTAssertEqual(store.composer.voice.phase, .streaming)
        XCTAssertEqual(store.composer.voice.interactionMode, .hold)

        await store.cancelVoiceCapture()
        await store.toggleTapVoiceCapture()
        await store.beginVoiceCapture()

        XCTAssertEqual(realtime.startCount, 2)
        XCTAssertEqual(capture.startCount, 2)
        XCTAssertEqual(store.composer.voice.phase, .streaming)
        XCTAssertEqual(store.composer.voice.interactionMode, .tap)
    }

    @MainActor
    func testRelayRealtimeClientDrivesStoreDraftFromDeltaAndFinalEvents() async throws {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let detailSession = FakeThreadDetailSession(
            readResult: .success(ThreadReadResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            resumeResult: .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-1", turns: [])))
        )
        let voiceTransport = ScriptedAppServerTransport()
        let voiceClient = AppServerClient(transport: voiceTransport)
        let observabilityStore = ClientObservabilityStore(persistenceDirectory: nil)
        let realtime = RelayRealtimeTranscriptionClient(
            host: host,
            observabilityStore: observabilityStore
        ) { _ in voiceClient }
        let capture = FakeLiveVoiceCaptureController()
        let store = ThreadDetailStore(
            host: host,
            row: row,
            factory: FakeThreadDetailSessionFactory(session: detailSession),
            realtimeTranscriptionService: realtime,
            liveVoiceCaptureController: capture
        )

        await store.load()
        store.updateDraft("Run tests")

        let beginTask = Task {
            await store.beginVoiceCapture()
        }
        let initializeRequest = try await voiceTransport.nextSentRequest()
        XCTAssertEqual(initializeRequest.method, AppServerMethods.initialize)
        await voiceTransport.enqueue(
            .response(
                JSONRPCResponse(
                    id: initializeRequest.id,
                    result: .object([
                        "userAgent": .string("codex-test"),
                        "codexHome": .string("/tmp/codex"),
                        "platformFamily": .string("unix"),
                        "platformOs": .string("macos"),
                    ])
                )
            )
        )
        let initializedNotification = try await voiceTransport.nextSentNotification()
        XCTAssertEqual(initializedNotification.method, AppServerMethods.initialized)
        let startRequest = try await voiceTransport.nextSentRequest()
        XCTAssertEqual(startRequest.method, AppServerMethods.audioTranscriptionStart)
        await voiceTransport.enqueue(
            .response(
                JSONRPCResponse(
                    id: startRequest.id,
                    result: try JSONValue.encoded(
                        AudioTranscriptionStartResponseDTO(
                            sessionId: "transcription-1",
                            format: "audio/pcm",
                            sampleRate: 24_000,
                            model: "gpt-realtime-whisper"
                        )
                    )
                )
            )
        )
        await beginTask.value
        XCTAssertEqual(store.composer.voice.phase, .streaming)

        capture.session.emit(
            VoiceAudioChunk(sequence: 1, audio: Data([9, 8, 7]), format: .pcm16Mono24k)
        )
        let appendRequest = try await voiceTransport.nextSentRequest()
        XCTAssertEqual(appendRequest.method, AppServerMethods.audioTranscriptionAppend)
        guard case .object(let appendParams) = try XCTUnwrap(appendRequest.params) else {
            return XCTFail("Expected audio/transcription/append params")
        }
        XCTAssertEqual(appendParams["sessionId"], .string("transcription-1"))
        XCTAssertEqual(appendParams["sequence"], .integer(1))
        XCTAssertEqual(appendParams["base64Audio"], .string(Data([9, 8, 7]).base64EncodedString()))
        await voiceTransport.enqueue(
            .response(
                JSONRPCResponse(
                    id: appendRequest.id,
                    result: try JSONValue.encoded(
                        AudioTranscriptionAppendResponseDTO(
                            sessionId: "transcription-1",
                            acceptedSequence: 1
                        )
                    )
                )
            )
        )

        await voiceTransport.enqueue(
            .notification(
                JSONRPCNotification(
                    method: AppServerMethods.audioTranscriptionDelta,
                    params: try JSONValue.encoded(
                        AudioTranscriptionDeltaNotificationDTO(
                            sessionId: "transcription-1",
                            itemId: "item-1",
                            contentIndex: 0,
                            deltaText: "then summarize",
                            partialText: "then summarize"
                        )
                    )
                )
            )
        )
        try await waitForDetailStore {
            store.composer.draft == "Run tests then summarize"
        }

        let finishTask = Task {
            await store.finishVoiceCapture()
        }
        let commitRequest = try await voiceTransport.nextSentRequest()
        XCTAssertEqual(commitRequest.method, AppServerMethods.audioTranscriptionCommit)
        await voiceTransport.enqueue(
            .response(
                JSONRPCResponse(
                    id: commitRequest.id,
                    result: try JSONValue.encoded(
                        AudioTranscriptionCommitResponseDTO(
                            sessionId: "transcription-1",
                            committed: true
                        )
                    )
                )
            )
        )
        await voiceTransport.enqueue(
            .notification(
                JSONRPCNotification(
                    method: AppServerMethods.audioTranscriptionCompleted,
                    params: try JSONValue.encoded(
                        AudioTranscriptionCompletedNotificationDTO(
                            sessionId: "transcription-1",
                            itemId: "item-1",
                            contentIndex: 0,
                            transcript: "then summarize failures"
                        )
                    )
                )
            )
        )
        await finishTask.value

        XCTAssertEqual(store.composer.draft, "Run tests then summarize failures")
        XCTAssertEqual(store.composer.voice, ComposerVoiceState())
        let voiceMethods = await voiceTransport.sentMethodsSnapshot()
        XCTAssertFalse(voiceMethods.contains("audio/transcribe"))
        try await waitForDetailStoreAsync {
            let routes = await observabilityStore.snapshots().map(\.route)
            return routes.contains(AppServerMethods.audioTranscriptionStart)
                && routes.contains(AppServerMethods.audioTranscriptionAppend)
                && routes.contains(AppServerMethods.audioTranscriptionCommit)
                && routes.contains(AppServerMethods.audioTranscriptionCompleted)
        }
        let bundle = await observabilityStore.diagnosticBundle(hosts: [host.id])
        XCTAssertTrue(bundle.omitted.contains("audio"))
        XCTAssertTrue(bundle.omitted.contains("transcripts"))
        let bundleText = String(data: try JSONEncoder().encode(bundle), encoding: .utf8) ?? ""
        XCTAssertFalse(bundleText.contains(Data([9, 8, 7]).base64EncodedString()))
        XCTAssertFalse(bundleText.contains("then summarize failures"))
        let startParams = await detailSession.turnStartParamsSnapshot()
        XCTAssertEqual(startParams, [])
    }

    @MainActor
    func testVoicePreservesTypedPrefixAndLocksEditsWhileActive() async throws {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let session = FakeThreadDetailSession(
            readResult: .success(ThreadReadResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            resumeResult: .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-1", turns: [])))
        )
        let realtimeSession = FakeRealtimeTranscriptionSession()
        realtimeSession.eventsOnCommit = [
            .completed(sessionID: realtimeSession.id, itemID: "item-1", text: "then summarize failures"),
        ]
        let realtime = FakeRealtimeTranscriptionService(session: realtimeSession)
        let store = ThreadDetailStore(
            host: host,
            row: row,
            factory: FakeThreadDetailSessionFactory(session: session),
            realtimeTranscriptionService: realtime
        )

        await store.load()
        store.updateDraft("Run tests")
        await store.beginVoiceCapture()
        realtime.session.emit(
            .delta(
                sessionID: realtime.session.id,
                itemID: "item-1",
                sequence: 1,
                deltaText: "then summarize",
                partialText: "then summarize"
            )
        )
        try await waitForDetailStore {
            store.composer.draft == "Run tests then summarize"
        }

        store.updateDraft("User edit should be ignored")
        XCTAssertEqual(store.composer.draft, "Run tests then summarize")
        await store.finishVoiceCapture()

        XCTAssertEqual(store.composer.draft, "Run tests then summarize failures")
        store.updateDraft("Run tests and summarize failures")
        XCTAssertEqual(store.composer.draft, "Run tests and summarize failures")
        let startParams = await session.turnStartParamsSnapshot()
        XCTAssertEqual(startParams, [])
    }

    @MainActor
    func testVoiceCancelRemovesOnlyActiveProvisionalSegment() async throws {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let session = FakeThreadDetailSession(
            readResult: .success(ThreadReadResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            resumeResult: .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-1", turns: [])))
        )
        let realtime = FakeRealtimeTranscriptionService()
        let store = ThreadDetailStore(
            host: host,
            row: row,
            factory: FakeThreadDetailSessionFactory(session: session),
            realtimeTranscriptionService: realtime
        )

        await store.load()
        store.updateDraft("Run tests")
        await store.beginVoiceCapture()
        realtime.session.emit(
            .delta(
                sessionID: realtime.session.id,
                itemID: "item-1",
                sequence: 1,
                deltaText: "then stop",
                partialText: "then stop"
            )
        )
        try await waitForDetailStore {
            store.composer.draft == "Run tests then stop"
        }

        await store.cancelVoiceCapture()

        XCTAssertEqual(realtime.session.cancelCount, 1)
        XCTAssertEqual(store.composer.draft, "Run tests")
        XCTAssertEqual(store.composer.voice, ComposerVoiceState())
        let startParams = await session.turnStartParamsSnapshot()
        XCTAssertEqual(startParams, [])
    }

    @MainActor
    func testVoiceFailureAfterPartialFreezesVisiblePartialAsEditableDraft() async throws {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let session = FakeThreadDetailSession(
            readResult: .success(ThreadReadResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            resumeResult: .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-1", turns: [])))
        )
        let realtime = FakeRealtimeTranscriptionService()
        let store = ThreadDetailStore(
            host: host,
            row: row,
            factory: FakeThreadDetailSessionFactory(session: session),
            realtimeTranscriptionService: realtime
        )

        await store.load()
        store.updateDraft("Keep this")
        await store.beginVoiceCapture()
        realtime.session.emit(
            .delta(
                sessionID: realtime.session.id,
                itemID: "item-1",
                sequence: 1,
                deltaText: "spoken partial",
                partialText: "spoken partial"
            )
        )
        try await waitForDetailStore {
            store.composer.draft == "Keep this spoken partial"
        }
        realtime.session.emit(
            .failed(
                sessionID: realtime.session.id,
                code: "upstream_failed",
                message: "Realtime transcription stopped."
            )
        )

        try await waitForDetailStore {
            store.composer.voice.lastError == "Realtime transcription stopped."
        }
        XCTAssertEqual(store.composer.draft, "Keep this spoken partial")
        store.updateDraft("Keep this edited partial")
        XCTAssertEqual(store.composer.draft, "Keep this edited partial")
        let startParams = await session.turnStartParamsSnapshot()
        XCTAssertEqual(startParams, [])
    }

    @MainActor
    func testVoiceFailureBeforePartialPreservesExistingDraft() async throws {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let session = FakeThreadDetailSession(
            readResult: .success(ThreadReadResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            resumeResult: .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-1", turns: [])))
        )
        let realtime = FakeRealtimeTranscriptionService()
        let store = ThreadDetailStore(
            host: host,
            row: row,
            factory: FakeThreadDetailSessionFactory(session: session),
            realtimeTranscriptionService: realtime
        )

        await store.load()
        store.updateDraft("Keep this")
        await store.beginVoiceCapture()
        realtime.session.emit(
            .failed(
                sessionID: realtime.session.id,
                code: "upstream_failed",
                message: "Realtime transcription stopped."
            )
        )

        try await waitForDetailStore {
            store.composer.voice.lastError == "Realtime transcription stopped."
        }
        XCTAssertEqual(store.composer.draft, "Keep this")
        store.updateDraft("Keep this editable")
        XCTAssertEqual(store.composer.draft, "Keep this editable")
    }

    @MainActor
    func testVoiceCommitFailureFreezesVisiblePartialAsEditableDraft() async throws {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let session = FakeThreadDetailSession(
            readResult: .success(ThreadReadResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            resumeResult: .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-1", turns: [])))
        )
        let realtimeSession = FakeRealtimeTranscriptionSession()
        realtimeSession.commitError = .transportFailed
        let realtime = FakeRealtimeTranscriptionService(session: realtimeSession)
        let store = ThreadDetailStore(
            host: host,
            row: row,
            factory: FakeThreadDetailSessionFactory(session: session),
            realtimeTranscriptionService: realtime
        )

        await store.load()
        store.updateDraft("Keep this")
        await store.beginVoiceCapture()
        realtime.session.emit(
            .delta(
                sessionID: realtime.session.id,
                itemID: "item-1",
                sequence: 1,
                deltaText: "spoken partial",
                partialText: "spoken partial"
            )
        )
        try await waitForDetailStore {
            store.composer.draft == "Keep this spoken partial"
        }

        await store.finishVoiceCapture()

        XCTAssertEqual(realtime.session.commitCount, 1)
        XCTAssertEqual(store.composer.draft, "Keep this spoken partial")
        XCTAssertEqual(store.composer.voice.lastError, "Realtime transcription could not reach the relay.")
        store.updateDraft("Keep this edited after failure")
        XCTAssertEqual(store.composer.draft, "Keep this edited after failure")
    }

    @MainActor
    func testVoiceStartupFailurePreservesExistingDraft() async {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let session = FakeThreadDetailSession(
            readResult: .success(ThreadReadResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            resumeResult: .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-1", turns: [])))
        )
        let realtime = FakeRealtimeTranscriptionService(startResult: .failure(.transportFailed))
        let store = ThreadDetailStore(
            host: host,
            row: row,
            factory: FakeThreadDetailSessionFactory(session: session),
            realtimeTranscriptionService: realtime
        )

        await store.load()
        store.updateDraft("Keep this")
        await store.beginVoiceCapture()

        XCTAssertEqual(realtime.startCount, 1)
        XCTAssertEqual(store.composer.draft, "Keep this")
        XCTAssertEqual(store.composer.voice.phase, .idle)
        XCTAssertEqual(store.composer.voice.lastError, "Realtime transcription could not reach the relay.")
    }

    @MainActor
    func testUnavailableRealtimeServiceFailsVisiblyWithoutUsingOneShotFallback() async {
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
            realtimeTranscriptionService: UnavailableRealtimeTranscriptionService()
        )

        await store.load()
        store.updateDraft("Keep this")
        await store.beginVoiceCapture()

        XCTAssertEqual(store.composer.draft, "Keep this")
        XCTAssertEqual(store.composer.voice.phase, .idle)
        XCTAssertEqual(store.composer.voice.lastError, "Realtime transcription is not connected yet.")
    }

    @MainActor
    func testVoiceBusyStateDisablesSendAndDoesNotSubmit() async {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let session = FakeThreadDetailSession(
            readResult: .success(ThreadReadResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            resumeResult: .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-1", turns: [])))
        )
        let realtime = FakeRealtimeTranscriptionService()
        let store = ThreadDetailStore(
            host: host,
            row: row,
            factory: FakeThreadDetailSessionFactory(session: session),
            realtimeTranscriptionService: realtime
        )

        await store.load()
        store.updateDraft("Do not send yet")
        await store.beginVoiceCapture()

        XCTAssertFalse(store.composer.canSend)
        await store.sendDraft()

        XCTAssertEqual(store.composer.draft, "Do not send yet")
        XCTAssertEqual(store.composer.lastError, "Finish dictation before sending.")
        let startParams = await session.turnStartParamsSnapshot()
        XCTAssertEqual(startParams, [])
    }

    @MainActor
    func testCloseRemovesProvisionalVoiceSegmentAndCancelsSession() async throws {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let session = FakeThreadDetailSession(
            readResult: .success(ThreadReadResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            resumeResult: .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-1", turns: [])))
        )
        let realtime = FakeRealtimeTranscriptionService()
        let store = ThreadDetailStore(
            host: host,
            row: row,
            factory: FakeThreadDetailSessionFactory(session: session),
            realtimeTranscriptionService: realtime
        )

        await store.load()
        store.updateDraft("Run tests")
        await store.beginVoiceCapture()
        realtime.session.emit(
            .delta(
                sessionID: realtime.session.id,
                itemID: "item-1",
                sequence: 1,
                deltaText: "then close",
                partialText: "then close"
            )
        )
        try await waitForDetailStore {
            store.composer.draft == "Run tests then close"
        }

        store.close()

        try await waitForDetailStore {
            realtime.session.cancelCount == 1
        }
        XCTAssertEqual(store.composer.draft, "Run tests")
        XCTAssertEqual(store.composer.voice, ComposerVoiceState())
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

    @MainActor
    func testLogicalHostRowCanOpenEndpointBackedDetail() async {
        let host = try! DockHostConfiguration(host: "amir-m5.fairy-salmon.ts.net", port: 4510)
        let row = makeDetailRow(
            hostID: "Amir-M5",
            threadID: "thread-1",
            sourceHostID: host.id
        )
        let resolver = DockHostIdentityResolver(
            hosts: [host],
            observations: [
                DockHostIdentityObservation(
                    configuredHostID: host.id,
                    streamHostID: "Amir-M5",
                    logicalHostID: "Amir-M5",
                    displayName: "Amir-M5",
                    endpoint: host.endpoint.displayEndpoint
                )
            ]
        )
        let thread = makeDetailThread("thread-1", text: "Thread detail loaded")
        let session = FakeThreadDetailSession(
            readResult: .success(ThreadReadResponseDTO(thread: thread)),
            resumeResult: .success(ThreadResumeResponseDTO(thread: thread))
        )
        let store = ThreadDetailStore(
            host: host,
            row: row,
            factory: FakeThreadDetailSessionFactory(session: session),
            hostIdentityResolver: resolver
        )

        await store.load()

        guard case let .loaded(snapshot) = store.state else {
            return XCTFail("Expected loaded detail, got \(store.state)")
        }
        XCTAssertEqual(snapshot.header.hostID, host.id)
        XCTAssertEqual(snapshot.header.threadID, "thread-1")
    }
}

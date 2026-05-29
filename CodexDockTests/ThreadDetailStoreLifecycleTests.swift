import XCTest
@testable import CodexDock

final class ThreadDetailStoreTestsLifecycle: XCTestCase {
    @MainActor
    func testBackgroundMarksDetailStaleAndPreservesDraftRequestCardsAndEvents() async throws {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let lifecycle = AppLifecycleCoordinator()
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
            lifecycleCoordinator: lifecycle,
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
        store.updateRequestCardInput(cardID: "request-approval-1", draft: "Looks good")

        lifecycle.handle(.background)

        try await waitForDetailStore {
            guard case let .loaded(snapshot) = store.state,
                  case let .stale(message) = snapshot.liveState else {
                return false
            }
            return message == "Backgrounded"
                && snapshot.events.map(\.body) == ["make test", "Stored turn"]
        }
        XCTAssertEqual(store.composer.draft, "Keep this draft")
        XCTAssertEqual(store.requestCards.count, 1)
        XCTAssertEqual(store.requestCards[0].inputDraft, "Looks good")
        XCTAssertEqual(store.requestCards[0].status, .pending)
        let readParams = await session.readParamsSnapshot()
        let turnsListParams = await session.turnsListParamsSnapshot()
        let resumeParams = await session.resumeParamsSnapshot()
        XCTAssertEqual(readParams.count, 1)
        XCTAssertEqual(turnsListParams.count, 1)
        XCTAssertEqual(resumeParams.count, 1)
    }

    @MainActor
    func testReconnectPublishesReconnectingThenCompactRehydratesToLive() async throws {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let session = FakeThreadDetailSession(
            readResult: .success(ThreadReadResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            turnsListResult: .success(ThreadTurnsListResponseDTO(data: [])),
            resumeResult: .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            turnsListResults: [
                .success(
                    ThreadTurnsListResponseDTO(data: [
                        makeDetailTurn(id: "turn-initial", startedAt: 1_000, text: "Initial turn"),
                    ])
                ),
                .success(
                    ThreadTurnsListResponseDTO(data: [
                        makeDetailTurn(id: "turn-rehydrated", startedAt: 2_000, text: "Rehydrated turn"),
                    ])
                ),
            ],
            resumeResults: [
                .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
                .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            ]
        )
        let store = ThreadDetailStore(
            host: host,
            row: row,
            factory: FakeThreadDetailSessionFactory(session: session)
        )

        await store.load()
        await session.emitConnectionState(.reconnecting(attempt: 1, reason: "transport closed"))
        try await waitForDetailStore {
            guard case let .loaded(snapshot) = store.state,
                  case let .reconnecting(message) = snapshot.liveState else {
                return false
            }
            return message == "transport closed"
        }

        await session.emitConnectionState(.connected)

        try await waitForDetailStore {
            guard case let .loaded(snapshot) = store.state else {
                return false
            }
            return snapshot.liveState == .live
                && snapshot.events.contains { $0.body == "Rehydrated turn" }
        }

        let readParams = await session.readParamsSnapshot()
        let turnsListParams = await session.turnsListParamsSnapshot()
        let resumeParams = await session.resumeParamsSnapshot()
        XCTAssertEqual(readParams, [
            ThreadReadParams(threadId: "thread-1", includeTurns: false),
            ThreadReadParams(threadId: "thread-1", includeTurns: false),
        ])
        XCTAssertEqual(turnsListParams, [
            ThreadTurnsListParams(threadId: "thread-1", limit: 10),
            ThreadTurnsListParams(threadId: "thread-1", limit: 10),
        ])
        XCTAssertEqual(resumeParams, [
            ThreadResumeParams(threadId: "thread-1", excludeTurns: true),
            ThreadResumeParams(threadId: "thread-1", excludeTurns: true),
        ])
    }

    @MainActor
    func testReconnectRehydratePreservesDraftRequestCardInputAndStatus() async throws {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let session = FakeThreadDetailSession(
            readResult: .success(ThreadReadResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            turnsListResult: .success(ThreadTurnsListResponseDTO(data: [])),
            resumeResult: .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            turnsListResults: [
                .success(ThreadTurnsListResponseDTO(data: [])),
                .success(ThreadTurnsListResponseDTO(data: [])),
            ],
            resumeResults: [
                .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
                .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            ]
        )
        let store = ThreadDetailStore(
            host: host,
            row: row,
            factory: FakeThreadDetailSessionFactory(session: session)
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
        store.updateRequestCardInput(cardID: "request-approval-1", draft: "Looks good")

        await session.emitConnectionState(.reconnecting(attempt: 1, reason: "transport closed"))
        await session.emitConnectionState(.connected)

        try await waitForDetailStore {
            guard case let .loaded(snapshot) = store.state else {
                return false
            }
            return snapshot.liveState == .live
        }
        XCTAssertEqual(store.composer.draft, "Keep this draft")
        XCTAssertEqual(store.requestCards.count, 1)
        XCTAssertEqual(store.requestCards[0].inputDraft, "Looks good")
        XCTAssertEqual(store.requestCards[0].status, .pending)
    }

    @MainActor
    func testForegroundResumeRunsCompactReadTurnsResumeBeforeReturningLive() async throws {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let lifecycle = AppLifecycleCoordinator()
        let session = FakeThreadDetailSession(
            readResult: .success(ThreadReadResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            turnsListResult: .success(ThreadTurnsListResponseDTO(data: [])),
            resumeResult: .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            turnsListResults: [
                .success(
                    ThreadTurnsListResponseDTO(data: [
                        makeDetailTurn(id: "turn-initial", startedAt: 1_000, text: "Initial turn"),
                    ])
                ),
                .success(
                    ThreadTurnsListResponseDTO(data: [
                        makeDetailTurn(id: "turn-resumed", startedAt: 2_000, text: "Foreground resumed turn"),
                    ])
                ),
            ],
            resumeResults: [
                .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
                .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            ]
        )
        let store = ThreadDetailStore(
            host: host,
            row: row,
            factory: FakeThreadDetailSessionFactory(session: session),
            lifecycleCoordinator: lifecycle
        )

        await store.load()
        lifecycle.handle(.background)
        try await waitForDetailStore {
            guard case let .loaded(snapshot) = store.state else {
                return false
            }
            return snapshot.liveState == .stale("Backgrounded")
        }

        lifecycle.handle(.active)

        try await waitForDetailStore {
            guard case let .loaded(snapshot) = store.state else {
                return false
            }
            return snapshot.liveState == .live
                && snapshot.events.contains { $0.body == "Foreground resumed turn" }
        }

        let readParams = await session.readParamsSnapshot()
        let turnsListParams = await session.turnsListParamsSnapshot()
        let resumeParams = await session.resumeParamsSnapshot()
        XCTAssertEqual(readParams, [
            ThreadReadParams(threadId: "thread-1", includeTurns: false),
            ThreadReadParams(threadId: "thread-1", includeTurns: false),
        ])
        XCTAssertEqual(turnsListParams, [
            ThreadTurnsListParams(threadId: "thread-1", limit: 10),
            ThreadTurnsListParams(threadId: "thread-1", limit: 10),
        ])
        XCTAssertEqual(resumeParams, [
            ThreadResumeParams(threadId: "thread-1", excludeTurns: true),
            ThreadResumeParams(threadId: "thread-1", excludeTurns: true),
        ])
    }

    @MainActor
    func testForegroundResumeWaitsForReconnectBeforeRehydratingDetail() async throws {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let lifecycle = AppLifecycleCoordinator()
        let session = FakeThreadDetailSession(
            readResult: .success(ThreadReadResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            turnsListResult: .success(ThreadTurnsListResponseDTO(data: [])),
            resumeResult: .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            readResults: [
                .success(ThreadReadResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
                .success(ThreadReadResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            ],
            turnsListResults: [
                .success(ThreadTurnsListResponseDTO(data: [])),
                .success(ThreadTurnsListResponseDTO(data: [
                    makeDetailTurn(id: "turn-resumed", text: "Rehydrated after socket returned"),
                ])),
            ],
            resumeResults: [
                .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
                .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            ]
        )
        let store = ThreadDetailStore(
            host: host,
            row: row,
            factory: FakeThreadDetailSessionFactory(session: session),
            lifecycleCoordinator: lifecycle
        )

        await store.load()
        await session.emitConnectionState(.reconnecting(attempt: 1, reason: "transport closed"))
        lifecycle.handle(.background)
        lifecycle.handle(.active)

        try await waitForDetailStore {
            guard case let .loaded(snapshot) = store.state else {
                return false
            }
            return snapshot.liveState == .reconnecting("Resuming")
        }
        try await Task.sleep(for: .milliseconds(50))
        let readParamsBeforeReconnect = await session.readParamsSnapshot()
        XCTAssertEqual(readParamsBeforeReconnect.count, 1)

        await session.emitConnectionState(.connected)

        try await waitForDetailStore {
            guard case let .loaded(snapshot) = store.state else {
                return false
            }
            return snapshot.liveState == .live
                && snapshot.events.contains { $0.body == "Rehydrated after socket returned" }
        }
        let readParamsAfterReconnect = await session.readParamsSnapshot()
        XCTAssertEqual(readParamsAfterReconnect.count, 2)
    }

    @MainActor
    func testReconnectRehydrateDoesNotDuplicateExistingEvents() async throws {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let turn = makeDetailTurn(id: "turn-same", startedAt: 1_000, text: "Same turn")
        let session = FakeThreadDetailSession(
            readResult: .success(ThreadReadResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            turnsListResult: .success(ThreadTurnsListResponseDTO(data: [])),
            resumeResult: .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            turnsListResults: [
                .success(ThreadTurnsListResponseDTO(data: [turn])),
                .success(ThreadTurnsListResponseDTO(data: [turn])),
            ],
            resumeResults: [
                .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
                .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            ]
        )
        let store = ThreadDetailStore(
            host: host,
            row: row,
            factory: FakeThreadDetailSessionFactory(session: session)
        )

        await store.load()
        await session.emitConnectionState(.reconnecting(attempt: 1, reason: "transport closed"))
        await session.emitConnectionState(.connected)

        try await waitForDetailStore {
            guard case let .loaded(snapshot) = store.state else {
                return false
            }
            return snapshot.liveState == .live
                && snapshot.events.filter { $0.body == "Same turn" }.count == 1
        }
    }

    @MainActor
    func testReconnectFailureLeavesLoadedSnapshotStale() async throws {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let session = FakeThreadDetailSession(
            readResult: .success(ThreadReadResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            turnsListResult: .success(
                ThreadTurnsListResponseDTO(data: [
                    makeDetailTurn(id: "turn-initial", text: "Initial turn"),
                ])
            ),
            resumeResult: .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            readResults: [
                .success(ThreadReadResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
                .failure(.resumeFailed),
            ]
        )
        let store = ThreadDetailStore(
            host: host,
            row: row,
            factory: FakeThreadDetailSessionFactory(session: session)
        )

        await store.load()
        await session.emitConnectionState(.reconnecting(attempt: 1, reason: "transport closed"))
        await session.emitConnectionState(.connected)

        try await waitForDetailStore {
            guard case let .loaded(snapshot) = store.state,
                  case let .stale(message) = snapshot.liveState else {
                return false
            }
            return message.contains("resume failed")
                && snapshot.events.map(\.body) == ["Initial turn"]
        }
    }

    @MainActor
    func testClosedThreadDoesNotReconnectOrBecomeStale() async throws {
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
        await session.emitNotification(
            JSONRPCNotification(
                method: "thread/closed",
                params: .object(["threadId": .string("thread-1")])
            )
        )
        try await waitForDetailStore {
            guard case let .loaded(snapshot) = store.state else {
                return false
            }
            return snapshot.liveState == .closed
        }

        await session.emitConnectionState(.reconnecting(attempt: 1, reason: "transport closed"))
        await session.emitConnectionState(.connected)
        try await Task.sleep(for: .milliseconds(50))

        guard case let .loaded(snapshot) = store.state else {
            return XCTFail("Expected loaded state, got \(store.state)")
        }
        XCTAssertEqual(snapshot.liveState, .closed)
        let readParams = await session.readParamsSnapshot()
        XCTAssertEqual(readParams.count, 1)
    }

    @MainActor
    func testFailedSendIsNotAutoReplayedAfterReconnect() async throws {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let session = FakeThreadDetailSession(
            readResult: .success(ThreadReadResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            turnsListResult: .success(ThreadTurnsListResponseDTO(data: [])),
            resumeResult: .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            turnStartResult: .failure(.turnFailed),
            turnsListResults: [
                .success(ThreadTurnsListResponseDTO(data: [])),
                .success(ThreadTurnsListResponseDTO(data: [])),
            ],
            resumeResults: [
                .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
                .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            ]
        )
        let store = ThreadDetailStore(
            host: host,
            row: row,
            factory: FakeThreadDetailSessionFactory(session: session)
        )

        await store.load()
        store.updateDraft("Do not replay this")
        await store.sendDraft()
        XCTAssertEqual(store.composer.lastError, "turn failed")

        await session.emitConnectionState(.reconnecting(attempt: 1, reason: "transport closed"))
        await session.emitConnectionState(.connected)
        try await waitForDetailStore {
            guard case let .loaded(snapshot) = store.state else {
                return false
            }
            return snapshot.liveState == .live
        }

        let startParams = await session.turnStartParamsSnapshot()
        XCTAssertEqual(startParams, [
            TurnStartParams.text(threadId: "thread-1", text: "Do not replay this"),
        ])
        XCTAssertEqual(store.composer.draft, "Do not replay this")
        XCTAssertEqual(store.composer.lastError, "turn failed")
    }

    @MainActor
    func testBackgroundStopsVoiceCaptureAndFreezesPartialWithoutSubmitting() async throws {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let lifecycle = AppLifecycleCoordinator()
        let realtime = FakeRealtimeTranscriptionService()
        let session = FakeThreadDetailSession(
            readResult: .success(ThreadReadResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            resumeResult: .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-1", turns: [])))
        )
        let store = ThreadDetailStore(
            host: host,
            row: row,
            factory: FakeThreadDetailSessionFactory(session: session),
            realtimeTranscriptionService: realtime,
            lifecycleCoordinator: lifecycle
        )

        await store.load()
        store.updateDraft("Keep this")
        await store.beginVoiceCapture()
        XCTAssertEqual(store.composer.voice.phase, .streaming)
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

        lifecycle.handle(.background)

        try await waitForDetailStore {
            realtime.session.cancelCount == 1
                && store.composer.voice.lastError == "Dictation stopped because the app moved to the background."
        }
        XCTAssertEqual(store.composer.draft, "Keep this spoken partial")
        let startParams = await session.turnStartParamsSnapshot()
        XCTAssertEqual(startParams, [])
    }
}

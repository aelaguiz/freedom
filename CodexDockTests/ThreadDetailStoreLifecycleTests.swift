import XCTest
@testable import CodexDock

final class ThreadDetailStoreTestsLifecycle: XCTestCase {
    @MainActor
    func testBackgroundMarksDetailStaleAndPreservesDraftRequestCardsAndEvents() async throws {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let lifecycle = AppLifecycleCoordinator()
        let session = FakeThreadDetailSession(
            detailSubscribeResult: .success(.thread("thread-1")),
            projectionRowsResult: .success(
                [
                    makeProjectedDetailEvent(turnID: "turn-old", startedAt: 1_000, text: "Stored turn"),
                ]
            ),
            detailResyncResult: .success(.thread("thread-1"))
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
        store.updateRequestCardInput(cardID: try XCTUnwrap(store.requestCards.first?.id), draft: "Looks good")

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
        XCTAssertEqual(session.detailSubscribeParamsSnapshot().count, 1)
        XCTAssertEqual(session.detailResyncParamsSnapshot().count, 0)
    }

    @MainActor
    func testReconnectPublishesReconnectingThenCompactRehydratesToLive() async throws {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let session = FakeThreadDetailSession(
            detailSubscribeResult: .success(.thread("thread-1")),
            projectionRowsResult: .success([]),
            detailResyncResult: .success(.thread("thread-1")),
            projectionRowsResults: [
                .success(
                    [
                        makeProjectedDetailEvent(turnID: "turn-initial", startedAt: 1_000, text: "Initial turn"),
                    ]
                ),
                .success(
                    [
                        makeProjectedDetailEvent(turnID: "turn-rehydrated", startedAt: 2_000, text: "Rehydrated turn"),
                    ]
                ),
            ],
            detailResyncResults: [
                .success(.thread("thread-1")),
                .success(.thread("thread-1")),
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

        XCTAssertEqual(session.detailSubscribeParamsSnapshot(), [
            ThreadDetailParams(threadId: "thread-1"),
        ])
        XCTAssertEqual(session.detailResyncParamsSnapshot(), [
            ThreadDetailParams(threadId: "thread-1"),
        ])
    }

    @MainActor
    func testReconnectRehydrateReplacesHistoryBeforeReplayingBufferedLiveNotification() async throws {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let session = FakeThreadDetailSession(
            detailSubscribeResult: .success(.thread("thread-1")),
            projectionRowsResult: .success([]),
            detailResyncResult: .success(.thread("thread-1")),
            projectionDelay: .milliseconds(100),
            projectionRowsResults: [
                .success(
                    [
                        makeProjectedDetailEvent(turnID: "turn-initial", startedAt: 1_000, text: "Initial stale turn"),
                    ]
                ),
                .success(
                    [
                        makeProjectedDetailEvent(turnID: "turn-rehydrated", startedAt: 2_000, text: "Canonical rehydrated turn"),
                    ]
                ),
            ],
            detailResyncResults: [
                .success(.thread("thread-1")),
                .success(.thread("thread-1")),
            ]
        )
        let store = ThreadDetailStore(
            host: host,
            row: row,
            factory: FakeThreadDetailSessionFactory(session: session),
            now: { Date(timeIntervalSince1970: 3_000) }
        )

        await store.load()
        await session.emitConnectionState(.reconnecting(attempt: 1, reason: "transport closed"))
        await session.emitConnectionState(.connected)
        try await waitForDetailStoreAsync {
            session.detailResyncParamsSnapshot().count == 1
        }

        await session.emitProjectedAgentDelta(
            turnID: "turn-live",
            itemID: "agent-live",
            text: "Buffered during recovery"
        )
        try await Task.sleep(for: .milliseconds(20))
        guard case let .loaded(reconnectingSnapshot) = store.state else {
            return XCTFail("Expected loaded state, got \(store.state)")
        }
        XCTAssertEqual(reconnectingSnapshot.liveState, .reconnecting("transport closed"))
        XCTAssertFalse(reconnectingSnapshot.events.contains { $0.body == "Buffered during recovery" })

        try await waitForDetailStore {
            guard case let .loaded(snapshot) = store.state else {
                return false
            }
            return snapshot.liveState == .live
                && snapshot.events.contains { $0.body == "Buffered during recovery" }
                && snapshot.events.contains { $0.body == "Canonical rehydrated turn" }
                && !snapshot.events.contains { $0.body == "Initial stale turn" }
        }
    }

    @MainActor
    func testReconnectRehydratePreservesDraftRequestCardInputAndStatus() async throws {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let session = FakeThreadDetailSession(
            detailSubscribeResult: .success(.thread("thread-1")),
            projectionRowsResult: .success([]),
            detailResyncResult: .success(.thread("thread-1")),
            projectionRowsResults: [
                .success([]),
                .success([]),
            ],
            detailResyncResults: [
                .success(.thread("thread-1")),
                .success(.thread("thread-1")),
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
        store.updateRequestCardInput(cardID: try XCTUnwrap(store.requestCards.first?.id), draft: "Looks good")

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
    func testForegroundResumeRunsProjectionResyncBeforeReturningLive() async throws {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let lifecycle = AppLifecycleCoordinator()
        let session = FakeThreadDetailSession(
            detailSubscribeResult: .success(.thread("thread-1")),
            projectionRowsResult: .success([]),
            detailResyncResult: .success(.thread("thread-1")),
            projectionRowsResults: [
                .success(
                    [
                        makeProjectedDetailEvent(turnID: "turn-initial", startedAt: 1_000, text: "Initial turn"),
                    ]
                ),
                .success(
                    [
                        makeProjectedDetailEvent(turnID: "turn-resumed", startedAt: 2_000, text: "Foreground resumed turn"),
                    ]
                ),
            ],
            detailResyncResults: [
                .success(.thread("thread-1")),
                .success(.thread("thread-1")),
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

        XCTAssertEqual(session.detailSubscribeParamsSnapshot(), [
            ThreadDetailParams(threadId: "thread-1"),
        ])
        XCTAssertEqual(session.detailResyncParamsSnapshot(), [
            ThreadDetailParams(threadId: "thread-1"),
        ])
    }

    @MainActor
    func testForegroundResumeWaitsForReconnectBeforeRehydratingDetail() async throws {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let lifecycle = AppLifecycleCoordinator()
        let session = FakeThreadDetailSession(
            detailSubscribeResult: .success(.thread("thread-1")),
            projectionRowsResult: .success([]),
            detailResyncResult: .success(.thread("thread-1")),
            detailSubscribeResults: [
                .success(.thread("thread-1")),
                .success(.thread("thread-1")),
            ],
            projectionRowsResults: [
                .success([]),
                .success([
                    makeProjectedDetailEvent(turnID: "turn-resumed", text: "Rehydrated after socket returned"),
                ]),
            ],
            detailResyncResults: [
                .success(.thread("thread-1")),
                .success(.thread("thread-1")),
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
        try await waitForDetailStore {
            guard case let .loaded(snapshot) = store.state else {
                return false
            }
            return snapshot.liveState == .reconnecting("transport closed")
        }
        lifecycle.handle(.background)
        lifecycle.handle(.active)

        try await waitForDetailStore {
            guard case let .loaded(snapshot) = store.state else {
                return false
            }
            return snapshot.liveState == .reconnecting("Resuming")
        }
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(session.detailSubscribeParamsSnapshot().count, 1)
        XCTAssertEqual(session.detailResyncParamsSnapshot().count, 0)

        await session.emitConnectionState(.connected)

        try await waitForDetailStore {
            guard case let .loaded(snapshot) = store.state else {
                return false
            }
            return snapshot.liveState == .live
                && snapshot.events.contains { $0.body == "Rehydrated after socket returned" }
        }
        XCTAssertEqual(session.detailResyncParamsSnapshot().count, 1)
    }

    @MainActor
    func testReconnectRehydrateDoesNotDuplicateExistingEvents() async throws {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let turn = makeProjectedDetailEvent(turnID: "turn-same", startedAt: 1_000, text: "Same turn")
        let session = FakeThreadDetailSession(
            detailSubscribeResult: .success(.thread("thread-1")),
            projectionRowsResult: .success([]),
            detailResyncResult: .success(.thread("thread-1")),
            projectionRowsResults: [
                .success([turn]),
                .success([turn]),
            ],
            detailResyncResults: [
                .success(.thread("thread-1")),
                .success(.thread("thread-1")),
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
            detailSubscribeResult: .success(.thread("thread-1")),
            projectionRowsResult: .success(
                [
                    makeProjectedDetailEvent(turnID: "turn-initial", text: "Initial turn"),
                ]
            ),
            detailResyncResult: .success(.thread("thread-1")),
            detailResyncResults: [.failure(FakeThreadDetailError.projectionFailed)]
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
            return message.contains("projection failed")
                && snapshot.events.map(\.body) == ["Initial turn"]
        }
    }

    @MainActor
    func testClosedThreadDoesNotReconnectOrBecomeStale() async throws {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let session = FakeThreadDetailSession(
            detailSubscribeResult: .success(.thread("thread-1")),
            detailResyncResult: .success(.thread("thread-1"))
        )
        let store = ThreadDetailStore(
            host: host,
            row: row,
            factory: FakeThreadDetailSessionFactory(session: session)
        )

        await store.load()
        await session.emitProjectedThreadClosed(threadID: "thread-1")
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
        XCTAssertEqual(session.detailSubscribeParamsSnapshot().count, 1)
        XCTAssertEqual(session.detailResyncParamsSnapshot().count, 0)
    }

    @MainActor
    func testFailedSendIsNotAutoReplayedAfterReconnect() async throws {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let session = FakeThreadDetailSession(
            detailSubscribeResult: .success(.thread("thread-1")),
            projectionRowsResult: .success([]),
            detailResyncResult: .success(.thread("thread-1")),
            threadMessageSendResult: .failure(FakeThreadDetailError.turnFailed),
            projectionRowsResults: [
                .success([]),
                .success([]),
            ],
            detailResyncResults: [
                .success(.thread("thread-1")),
                .success(.thread("thread-1")),
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
        try await waitForDetailStore {
            guard case let .loaded(snapshot) = store.state else {
                return false
            }
            return snapshot.pendingOutboundMessages.first?.deliveryState == .failedAmbiguous("turn failed")
        }

        await session.emitConnectionState(.reconnecting(attempt: 1, reason: "transport closed"))
        await session.emitConnectionState(.connected)
        try await waitForDetailStore {
            guard case let .loaded(snapshot) = store.state else {
                return false
            }
            return snapshot.liveState == .live
        }

        let messageParams = session.threadMessageSendParamsSnapshot()
        let startParams = session.turnStartParamsSnapshot()
        XCTAssertEqual(messageParams.count, 1)
        XCTAssertEqual(messageParams.first?.threadId, "thread-1")
        XCTAssertEqual(messageParams.first?.input, [TurnUserInputDTO(text: "Do not replay this")])
        XCTAssertEqual(startParams, [])
        XCTAssertEqual(store.composer.draft, "")
        XCTAssertEqual(store.composer.lastError, nil)
    }

    @MainActor
    func testBackgroundStopsVoiceCaptureAndFreezesPartialWithoutSubmitting() async throws {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let lifecycle = AppLifecycleCoordinator()
        let realtime = FakeRealtimeTranscriptionService()
        let session = FakeThreadDetailSession(
            detailSubscribeResult: .success(.thread("thread-1")),
            detailResyncResult: .success(.thread("thread-1"))
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
        let startParams = session.turnStartParamsSnapshot()
        XCTAssertEqual(startParams, [])
    }
}

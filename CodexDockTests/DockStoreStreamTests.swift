import XCTest
@testable import CodexDock

final class DockStoreStreamTests: XCTestCase {
    @MainActor
    func testSequenceGapRequestsResyncAndKeepsHostRows() async throws {
        let host = makeHost()
        let connection = ManualThreadCardStreamConnection(
            subscribeSnapshot: dockStreamSnapshot(
                host: host,
                epoch: "epoch-1",
                seq: 1,
                cards: [
                    threadCardFixture(host: host, threadID: "thread-a", title: "Initial row", updatedAt: 1_000)
                ]
            ),
            resyncSnapshots: [
                dockStreamSnapshot(
                    host: host,
                    epoch: "epoch-1",
                    seq: 3,
                    cards: [
                        threadCardFixture(host: host, threadID: "thread-resynced", title: "Resynced row", updatedAt: 1_100)
                    ]
                )
            ]
        )
        let store = DockStore(host: host, streamClient: ManualThreadCardStreamClient(connection: connection))

        await store.load()
        await connection.send(
            ThreadCardStreamUpdateDTO(
                kind: .delta,
                schemaVersion: CodexDockConstants.Dock.streamSchemaVersion,
                view: .dock,
                epoch: "epoch-1",
                baseSeq: 99,
                seq: 100,
                upsertCards: [
                    threadCardFixture(host: host, threadID: "bad-delta", title: "Bad delta", updatedAt: 1_200)
                ]
            )
        )

        guard let snapshot = await waitForLoadedSnapshot(
            from: store,
            where: { $0.rows.map(\.id.threadID) == ["thread-resynced"] }
        ) else {
            return XCTFail("Expected sequence gap to resync, got \(store.state)")
        }
        XCTAssertEqual(snapshot.rows.map(\.title), ["Resynced row"])
    }

    @MainActor
    func testSchemaMismatchRequestsResyncAndKeepsHostRows() async throws {
        let host = makeHost()
        let connection = ManualThreadCardStreamConnection(
            subscribeSnapshot: dockStreamSnapshot(
                host: host,
                epoch: "epoch-1",
                seq: 1,
                cards: [
                    threadCardFixture(host: host, threadID: "thread-a", title: "Initial row", updatedAt: 1_000)
                ]
            ),
            resyncSnapshots: [
                dockStreamSnapshot(
                    host: host,
                    epoch: "epoch-1",
                    seq: 3,
                    cards: [
                        threadCardFixture(host: host, threadID: "thread-resynced", title: "Schema resynced row", updatedAt: 1_100)
                    ]
                )
            ]
        )
        let store = DockStore(host: host, streamClient: ManualThreadCardStreamClient(connection: connection))

        await store.load()
        await connection.send(
            ThreadCardStreamUpdateDTO(
                kind: .delta,
                schemaVersion: CodexDockConstants.Dock.streamSchemaVersion + 1,
                view: .dock,
                epoch: "epoch-1",
                baseSeq: 1,
                seq: 2,
                upsertCards: [
                    threadCardFixture(host: host, threadID: "bad-schema", title: "Bad schema delta", updatedAt: 1_200)
                ]
            )
        )

        guard let snapshot = await waitForLoadedSnapshot(
            from: store,
            where: { $0.rows.map(\.id.threadID) == ["thread-resynced"] }
        ) else {
            return XCTFail("Expected schema mismatch to resync, got \(store.state)")
        }
        XCTAssertEqual(snapshot.rows.map(\.title), ["Schema resynced row"])
        XCTAssertEqual(snapshot.hostStates.map(\.status), [.loaded(rowCount: 1)])
    }

    @MainActor
    func testMissingSchemaRequestsResync() async throws {
        let host = makeHost()
        let connection = ManualThreadCardStreamConnection(
            subscribeSnapshot: dockStreamSnapshot(
                host: host,
                epoch: "epoch-1",
                seq: 1,
                cards: [
                    threadCardFixture(host: host, threadID: "thread-a", title: "Initial row", updatedAt: 1_000)
                ]
            ),
            resyncSnapshots: [
                dockStreamSnapshot(
                    host: host,
                    epoch: "epoch-1",
                    seq: 3,
                    cards: [
                        threadCardFixture(host: host, threadID: "thread-resynced", title: "Missing schema resynced row", updatedAt: 1_100)
                    ]
                )
            ]
        )
        let store = DockStore(host: host, streamClient: ManualThreadCardStreamClient(connection: connection))

        await store.load()
        await connection.send(
            ThreadCardStreamUpdateDTO(
                kind: .delta,
                view: .dock,
                epoch: "epoch-1",
                baseSeq: 1,
                seq: 2,
                upsertCards: [
                    threadCardFixture(host: host, threadID: "missing-schema", title: "Missing schema delta", updatedAt: 1_200)
                ]
            )
        )

        guard let snapshot = await waitForLoadedSnapshot(
            from: store,
            where: { $0.rows.map(\.id.threadID) == ["thread-resynced"] }
        ) else {
            return XCTFail("Expected missing schema to resync, got \(store.state)")
        }
        XCTAssertEqual(snapshot.rows.map(\.title), ["Missing schema resynced row"])
    }

    @MainActor
    func testHostResyncDoesNotClearOtherHostRows() async throws {
        let amir = makeHost()
        let home = makeHost(url: "ws://100.66.11.7:4510")
        let registry = try HostRegistry(hosts: [amir, home])
        let amirConnection = ManualThreadCardStreamConnection(
            subscribeSnapshot: dockStreamSnapshot(
                host: amir,
                epoch: "amir-epoch",
                seq: 1,
                cards: [
                    threadCardFixture(host: amir, threadID: "amir-initial", title: "Amir initial", updatedAt: 1_000)
                ]
            ),
            resyncSnapshots: [
                dockStreamSnapshot(
                    host: amir,
                    epoch: "amir-epoch",
                    seq: 3,
                    cards: [
                        threadCardFixture(host: amir, threadID: "amir-resynced", title: "Amir resynced", updatedAt: 1_300)
                    ]
                )
            ]
        )
        let homeConnection = ManualThreadCardStreamConnection(
            subscribeSnapshot: dockStreamSnapshot(
                host: home,
                epoch: "home-epoch",
                seq: 1,
                cards: [
                    threadCardFixture(host: home, threadID: "home-row", title: "Home row", updatedAt: 1_200)
                ]
            )
        )
        let streamClient = SequencedManualThreadCardStreamClient(connections: [amirConnection, homeConnection])
        let store = DockStore(registry: registry, streamClient: streamClient)

        await store.load()
        await amirConnection.send(
            ThreadCardStreamUpdateDTO(
                kind: .delta,
                schemaVersion: CodexDockConstants.Dock.streamSchemaVersion + 1,
                view: .dock,
                epoch: "amir-epoch",
                baseSeq: 1,
                seq: 2,
                upsertCards: [
                    threadCardFixture(host: amir, threadID: "bad-schema", title: "Bad schema delta", updatedAt: 1_400)
                ]
            )
        )

        guard let snapshot = await waitForLoadedSnapshot(
            from: store,
            where: { $0.rows.map(\.id.threadID) == ["amir-resynced", "home-row"] }
        ) else {
            return XCTFail("Expected one host resync to retain the other host rows, got \(store.state)")
        }
        XCTAssertEqual(snapshot.hostStates.map(\.status), [
            .loaded(rowCount: 1),
            .loaded(rowCount: 1)
        ])
        XCTAssertEqual(snapshot.rows.map(\.hostDisplayName), [amir.displayName, home.displayName])
    }

    @MainActor
    func testStaleHeartbeatRetainsLastGoodRows() async throws {
        let host = makeHost()
        let connection = ManualThreadCardStreamConnection(
            subscribeSnapshot: dockStreamSnapshot(
                host: host,
                epoch: "epoch-1",
                seq: 1,
                cards: [
                    threadCardFixture(host: host, threadID: "thread-a", title: "Last good", updatedAt: 1_000)
                ]
            )
        )
        let store = DockStore(host: host, streamClient: ManualThreadCardStreamClient(connection: connection))

        await store.load()
        await connection.send(
            ThreadCardStreamUpdateDTO(
                kind: .heartbeat,
                schemaVersion: CodexDockConstants.Dock.streamSchemaVersion,
                view: .dock,
                epoch: "epoch-1",
                seq: 1,
                freshness: DockStreamFreshnessDTO(status: .stale, lastError: "refresh failed")
            )
        )

        guard let snapshot = await waitForLoadedSnapshot(
            from: store,
            where: { $0.hostStates.map(\.status) == [.partial(rowCount: 1, message: "refresh failed")] }
        ) else {
            return XCTFail("Expected stale heartbeat to retain rows, got \(store.state)")
        }
        XCTAssertTrue(snapshot.isPartial)
        XCTAssertEqual(snapshot.rows.map(\.id.threadID), ["thread-a"])
    }

    @MainActor
    func testStreamDropsNonHumanCardsFromSnapshotsAndDeltas() async throws {
        let host = makeHost()
        let connection = ManualThreadCardStreamConnection(
            subscribeSnapshot: dockStreamSnapshot(
                host: host,
                epoch: "epoch-1",
                seq: 1,
                cards: [
                    threadCardFixture(host: host, threadID: "human-initial", title: "Human initial", updatedAt: 1_000),
                    threadCardFixture(host: host, threadID: "agent-initial", title: "Agent initial", updatedAt: 1_100, sourceKind: .automation, lane: .agent),
                    threadCardFixture(host: host, threadID: "unknown-initial", title: "Unknown initial", updatedAt: 1_200, sourceKind: .unknown, lane: .unknown)
                ]
            )
        )
        let store = DockStore(host: host, streamClient: ManualThreadCardStreamClient(connection: connection))

        await store.load()

        guard let initialSnapshot = await waitForLoadedSnapshot(
            from: store,
            where: { $0.rows.map(\.id.threadID) == ["human-initial"] }
        ) else {
            return XCTFail("Expected non-human snapshot cards to be dropped, got \(store.state)")
        }
        XCTAssertEqual(initialSnapshot.hostStates.map(\.status), [.loaded(rowCount: 1)])

        await connection.send(
            ThreadCardStreamUpdateDTO(
                kind: .delta,
                schemaVersion: CodexDockConstants.Dock.streamSchemaVersion,
                view: .dock,
                epoch: "epoch-1",
                baseSeq: 1,
                seq: 2,
                upsertCards: [
                    threadCardFixture(host: host, threadID: "human-delta", title: "Human delta", updatedAt: 1_300),
                    threadCardFixture(host: host, threadID: "agent-delta", title: "Agent delta", updatedAt: 1_400, sourceKind: .automation, lane: .agent)
                ],
                deleteCardIDs: []
            )
        )

        guard let updatedSnapshot = await waitForLoadedSnapshot(
            from: store,
            where: { $0.rows.map(\.id.threadID) == ["human-delta", "human-initial"] }
        ) else {
            return XCTFail("Expected non-human delta cards to be dropped, got \(store.state)")
        }
        XCTAssertEqual(updatedSnapshot.hostStates.map(\.status), [.loaded(rowCount: 2)])
    }

    func testSnapshotCollectorKeepsTerminalIncompleteWindowPartialAfterDroppingNonHumanCards() async throws {
        let host = makeHost()
        let connection = ManualThreadCardStreamConnection(
            subscribeSnapshot: dockStreamSnapshot(
                host: host,
                epoch: "epoch-1",
                seq: 1,
                cards: [
                    threadCardFixture(host: host, threadID: "human-final", title: "Human final", updatedAt: 1_000),
                    threadCardFixture(host: host, threadID: "agent-final", title: "Agent final", updatedAt: 1_100, sourceKind: .automation, lane: .agent)
                ],
                complete: false,
                totalRows: 2,
                window: DockStreamWindowDTO(offset: 0, limit: 2, rowCount: 2)
            )
        )

        let collection = try await ThreadCardStreamSnapshotCollector(
            expectedView: .dock,
            timeout: .milliseconds(100)
        ).collect(from: connection)

        XCTAssertEqual(collection.cards.map(\.threadID), ["human-final"])
        XCTAssertFalse(collection.isComplete)
        XCTAssertEqual(collection.hostLoadStatus, .partial(rowCount: 1, message: "Stream incomplete"))
    }

    @MainActor
    func testWindowedSnapshotIsExplicitlyPartial() async throws {
        let host = makeHost()
        let connection = ManualThreadCardStreamConnection(
            subscribeSnapshot: dockStreamSnapshot(
                host: host,
                epoch: "epoch-1",
                seq: 1,
                cards: [
                    threadCardFixture(host: host, threadID: "thread-a", title: "Window row", updatedAt: 1_000)
                ],
                complete: false,
                totalRows: 3,
                window: DockStreamWindowDTO(offset: 0, limit: 1, rowCount: 1, nextOffset: 1)
            )
        )
        let store = DockStore(host: host, streamClient: ManualThreadCardStreamClient(connection: connection))

        await store.load()

        guard let snapshot = await waitForLoadedSnapshot(
            from: store,
            where: { $0.hostStates.map(\.status) == [.partial(rowCount: 1, message: "Showing 1 of 3")] }
        ) else {
            return XCTFail("Expected windowed snapshot to be partial, got \(store.state)")
        }
        XCTAssertTrue(snapshot.isPartial)
        XCTAssertEqual(snapshot.rows.map(\.id.threadID), ["thread-a"])
    }

    @MainActor
    func testWindowedSnapshotCompletesWithStreamedCatchupDeltas() async throws {
        let host = makeHost()
        let connection = ManualThreadCardStreamConnection(
            subscribeSnapshot: dockStreamSnapshot(
                host: host,
                epoch: "epoch-1",
                seq: 1,
                cards: [
                    threadCardFixture(host: host, threadID: "thread-a", title: "Window row A", updatedAt: 1_000)
                ],
                complete: false,
                totalRows: 3,
                window: DockStreamWindowDTO(offset: 0, limit: 1, rowCount: 1, nextOffset: 1)
            )
        )
        let store = DockStore(host: host, streamClient: ManualThreadCardStreamClient(connection: connection))

        await store.load()
        await connection.send(
            ThreadCardStreamUpdateDTO(
                kind: .delta,
                schemaVersion: CodexDockConstants.Dock.streamSchemaVersion,
                view: .dock,
                complete: false,
                totalRows: 3,
                window: DockStreamWindowDTO(offset: 1, limit: 1, rowCount: 1, nextOffset: 2),
                stateGeneration: 1,
                epoch: "epoch-1",
                baseSeq: 1,
                seq: 1,
                upsertCards: [
                    threadCardFixture(host: host, threadID: "thread-b", title: "Window row B", updatedAt: 900)
                ],
                deleteCardIDs: []
            )
        )
        await connection.send(
            ThreadCardStreamUpdateDTO(
                kind: .delta,
                schemaVersion: CodexDockConstants.Dock.streamSchemaVersion,
                view: .dock,
                complete: true,
                totalRows: 3,
                window: DockStreamWindowDTO(offset: 2, limit: 1, rowCount: 1),
                stateGeneration: 1,
                epoch: "epoch-1",
                baseSeq: 1,
                seq: 1,
                upsertCards: [
                    threadCardFixture(host: host, threadID: "thread-c", title: "Window row C", updatedAt: 800)
                ],
                deleteCardIDs: []
            )
        )

        guard let snapshot = await waitForLoadedSnapshot(
            from: store,
            where: { $0.hostStates.map(\.status) == [.loaded(rowCount: 3)] }
        ) else {
            return XCTFail("Expected streamed catch-up windows to complete the host, got \(store.state)")
        }
        XCTAssertFalse(snapshot.isPartial)
        XCTAssertEqual(snapshot.rows.map(\.id.threadID), ["thread-a", "thread-b", "thread-c"])
    }

    @MainActor
    func testSnapshotMissingWindowContractRequestsResync() async throws {
        let host = makeHost()
        let connection = ManualThreadCardStreamConnection(
            subscribeSnapshot: dockStreamSnapshot(
                host: host,
                epoch: "epoch-1",
                seq: 1,
                cards: [
                    threadCardFixture(host: host, threadID: "thread-a", title: "Initial row", updatedAt: 1_000)
                ]
            ),
            resyncSnapshots: [
                dockStreamSnapshot(
                    host: host,
                    epoch: "epoch-2",
                    seq: 1,
                    cards: [
                        threadCardFixture(host: host, threadID: "thread-resynced", title: "Contract row", updatedAt: 1_200)
                    ]
                )
            ]
        )
        let store = DockStore(host: host, streamClient: ManualThreadCardStreamClient(connection: connection))

        await store.load()
        await connection.send(
            ThreadCardStreamUpdateDTO(
                kind: .snapshot,
                schemaVersion: CodexDockConstants.Dock.streamSchemaVersion,
                epoch: "legacy-epoch",
                seq: 2,
                freshness: DockStreamFreshnessDTO(status: .fresh),
                hosts: [DockStreamHostDTO(id: host.id, logicalHostID: host.id, displayName: host.displayName, endpoint: host.endpoint.displayEndpoint)],
                cards: [
                    threadCardFixture(host: host, threadID: "legacy-row", title: "Legacy row", updatedAt: 1_100)
                ]
            )
        )

        guard let snapshot = await waitForLoadedSnapshot(
            from: store,
            where: { $0.rows.map(\.id.threadID) == ["thread-resynced"] }
        ) else {
            return XCTFail("Expected legacy snapshot to trigger resync, got \(store.state)")
        }
        XCTAssertEqual(snapshot.hostStates.map(\.status), [.loaded(rowCount: 1)])
    }

    @MainActor
    func testClosedStreamMarksHostOfflineAndRetainsRows() async throws {
        let host = makeHost()
        let connection = ManualThreadCardStreamConnection(
            subscribeSnapshot: dockStreamSnapshot(
                host: host,
                epoch: "epoch-1",
                seq: 1,
                cards: [
                    threadCardFixture(host: host, threadID: "thread-a", title: "Last good", updatedAt: 1_000)
                ]
            )
        )
        let store = DockStore(host: host, streamClient: ManualThreadCardStreamClient(connection: connection))

        await store.load()
        await connection.finish()

        guard let snapshot = await waitForLoadedSnapshot(
            from: store,
            where: { $0.hostStates.map(\.status) == [.partial(rowCount: 1, message: "Offline: Relay stream closed")] }
        ) else {
            return XCTFail("Expected closed stream to retain rows and mark host offline, got \(store.state)")
        }
        XCTAssertTrue(snapshot.isPartial)
        XCTAssertEqual(snapshot.rows.map(\.id.threadID), ["thread-a"])
    }

    @MainActor
    func testClosedStreamReconnectsAndReplacesHostRows() async throws {
        let host = makeHost()
        let firstConnection = ManualThreadCardStreamConnection(
            subscribeSnapshot: dockStreamSnapshot(
                host: host,
                epoch: "epoch-1",
                seq: 1,
                cards: [
                    threadCardFixture(host: host, threadID: "thread-a", title: "Last good", updatedAt: 1_000)
                ]
            )
        )
        let secondConnection = ManualThreadCardStreamConnection(
            subscribeSnapshot: dockStreamSnapshot(
                host: host,
                epoch: "epoch-2",
                seq: 1,
                cards: [
                    threadCardFixture(host: host, threadID: "thread-b", title: "Reconnected row", updatedAt: 1_200)
                ]
            )
        )
        let streamClient = SequencedManualThreadCardStreamClient(connections: [firstConnection, secondConnection])
        let store = DockStore(
            host: host,
            streamClient: streamClient,
            streamReconnectDelay: .milliseconds(10)
        )

        await store.load()
        await firstConnection.finish()

        guard let snapshot = await waitForLoadedSnapshot(
            from: store,
            where: { $0.rows.map(\.id.threadID) == ["thread-b"] }
        ) else {
            return XCTFail("Expected closed stream to reconnect and replace rows, got \(store.state)")
        }
        XCTAssertEqual(snapshot.hostStates.map(\.status), [.loaded(rowCount: 1)])
        XCTAssertEqual(snapshot.rows.map(\.title), ["Reconnected row"])
        let connectCount = await streamClient.connectCount()
        XCTAssertEqual(connectCount, 2)
    }
}

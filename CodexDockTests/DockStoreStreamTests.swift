import XCTest
@testable import CodexDock

final class DockStoreStreamTests: XCTestCase {
    @MainActor
    func testProjectionIDIsPrimaryCardIdentityForUpsertAndDelete() async throws {
        let host = makeHost()
        let projectionID = "host:\(host.id)/thread:thread-a/row:threadCard"
        let connection = ScriptedThreadCardTransportConnection(
            subscribeSnapshot: dockStreamSnapshot(
                host: host,
                epoch: "epoch-1",
                seq: 1,
                cards: [
                    threadCardFixture(
                        host: host,
                        threadID: "thread-a",
                        title: "Initial row",
                        updatedAt: 1_000,
                        projectionID: projectionID
                    )
                ]
            )
        )
        let store = DockStore(host: host, streamClient: ScriptedThreadCardTransportClient(connection: connection))

        await store.load()
        await connection.send(
            ThreadCardStreamUpdateDTO(
                kind: .upsert,
                schemaVersion: CodexDockConstants.Dock.streamSchemaVersion,
                identityVersion: 1,
                projectionEngineVersion: 1,
                sourceHostID: host.id,
                view: .dock,
                scope: "view",
                viewParamsKey: "dock:\(host.id)",
                epoch: "epoch-1",
                seq: 2,
                order: "displayOrderKeyAscending",
                rows: [
                    threadCardFixture(
                        host: host,
                        threadID: "thread-a",
                        title: "Projection update",
                        updatedAt: 1_100,
                        projectionID: projectionID
                    )
                ]
            )
        )

        guard let updated = await waitForLoadedSnapshot(
            from: store,
            where: { $0.rows.map(\.title) == ["Projection update"] }
        ) else {
            return XCTFail("Expected projection-keyed upsert to replace the existing row, got \(store.state)")
        }
        XCTAssertEqual(updated.rows.map(\.threadID), ["thread-a"])

        await connection.send(
            ThreadCardStreamUpdateDTO(
                kind: .upsert,
                schemaVersion: CodexDockConstants.Dock.streamSchemaVersion,
                identityVersion: 1,
                projectionEngineVersion: 1,
                sourceHostID: host.id,
                view: .dock,
                scope: "view",
                viewParamsKey: "dock:\(host.id)",
                epoch: "epoch-1",
                seq: 3,
                order: "displayOrderKeyAscending",
                projectionIDs: [projectionID]
            )
        )

        guard let deleted = await waitForLoadedSnapshot(
            from: store,
            where: { $0.rows.isEmpty }
        ) else {
            return XCTFail("Expected projection-keyed delete to remove the row, got \(store.state)")
        }
        XCTAssertTrue(deleted.rows.isEmpty)
    }

    @MainActor
    func testSequenceGapRequestsResyncAndKeepsHostRows() async throws {
        let host = makeHost()
        let connection = ScriptedThreadCardTransportConnection(
            subscribeSnapshot: dockStreamSnapshot(
                host: host,
                epoch: "epoch-1",
                seq: 3,
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
        let store = DockStore(host: host, streamClient: ScriptedThreadCardTransportClient(connection: connection))

        await store.load()
        await connection.send(
            ThreadCardStreamUpdateDTO(
                kind: .upsert,
                schemaVersion: CodexDockConstants.Dock.streamSchemaVersion,
                identityVersion: 1,
                projectionEngineVersion: 1,
                sourceHostID: host.id,
                view: .dock,
                scope: "view",
                viewParamsKey: "dock:\(host.id)",
                epoch: "epoch-1",
                seq: 100,
                order: "displayOrderKeyAscending",
                rows: [
                    threadCardFixture(host: host, threadID: "bad-delta", title: "Bad delta", updatedAt: 1_200)
                ]
            )
        )

        guard let snapshot = await waitForLoadedSnapshot(
            from: store,
            where: { $0.rows.map(\.threadID) == ["thread-resynced"] }
        ) else {
            return XCTFail("Expected sequence gap to resync, got \(store.state)")
        }
        XCTAssertEqual(snapshot.rows.map(\.title), ["Resynced row"])
    }

    @MainActor
    func testSchemaMismatchRequestsResyncAndKeepsHostRows() async throws {
        let host = makeHost()
        let connection = ScriptedThreadCardTransportConnection(
            subscribeSnapshot: dockStreamSnapshot(
                host: host,
                epoch: "epoch-1",
                seq: 2,
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
        let store = DockStore(host: host, streamClient: ScriptedThreadCardTransportClient(connection: connection))

        await store.load()
        await connection.send(
            ThreadCardStreamUpdateDTO(
                kind: .upsert,
                schemaVersion: CodexDockConstants.Dock.streamSchemaVersion + 1,
                sourceHostID: host.id,
                view: .dock,
                scope: "view",
                viewParamsKey: "dock:\(host.id)",
                epoch: "epoch-1",
                seq: 2,
                order: "displayOrderKeyAscending",
                rows: [
                    threadCardFixture(host: host, threadID: "bad-schema", title: "Bad schema delta", updatedAt: 1_200)
                ]
            )
        )

        guard let snapshot = await waitForLoadedSnapshot(
            from: store,
            where: { $0.rows.map(\.threadID) == ["thread-resynced"] }
        ) else {
            return XCTFail("Expected schema mismatch to resync, got \(store.state)")
        }
        XCTAssertEqual(snapshot.rows.map(\.title), ["Schema resynced row"])
        XCTAssertEqual(snapshot.hostStates.map(\.status), [.loaded(rowCount: 1)])
    }

    @MainActor
    func testInvalidSchemaRequestsResync() async throws {
        let host = makeHost()
        let connection = ScriptedThreadCardTransportConnection(
            subscribeSnapshot: dockStreamSnapshot(
                host: host,
                epoch: "epoch-1",
                seq: 3,
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
                        threadCardFixture(host: host, threadID: "thread-resynced", title: "Invalid schema resynced row", updatedAt: 1_100)
                    ]
                )
            ]
        )
        let store = DockStore(host: host, streamClient: ScriptedThreadCardTransportClient(connection: connection))

        await store.load()
        await connection.send(
            ThreadCardStreamUpdateDTO(
                kind: .upsert,
                schemaVersion: 0,
                sourceHostID: host.id,
                view: .dock,
                scope: "view",
                viewParamsKey: "dock:\(host.id)",
                epoch: "epoch-1",
                seq: 2,
                order: "displayOrderKeyAscending",
                rows: [
                    threadCardFixture(host: host, threadID: "invalid-schema", title: "Invalid schema delta", updatedAt: 1_200)
                ]
            )
        )

        guard let snapshot = await waitForLoadedSnapshot(
            from: store,
            where: { $0.rows.map(\.threadID) == ["thread-resynced"] }
        ) else {
            return XCTFail("Expected invalid schema to resync, got \(store.state)")
        }
        XCTAssertEqual(snapshot.rows.map(\.title), ["Invalid schema resynced row"])
    }

    @MainActor
    func testMalformedProjectionEnvelopeRequestsResync() async throws {
        let host = makeHost()
        let connection = ScriptedThreadCardTransportConnection(
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
                        threadCardFixture(host: host, threadID: "thread-resynced", title: "Projection resynced row", updatedAt: 1_200)
                    ]
                )
            ]
        )
        let store = DockStore(host: host, streamClient: ScriptedThreadCardTransportClient(connection: connection))

        await store.load()
        await connection.send(
            ThreadCardStreamUpdateDTO(
                kind: .upsert,
                schemaVersion: CodexDockConstants.Dock.streamSchemaVersion,
                identityVersion: 1,
                projectionEngineVersion: 1,
                sourceHostID: host.id,
                view: .dock,
                scope: "view",
                viewParamsKey: "dock:\(host.id)",
                epoch: "epoch-1",
                seq: 2,
                order: "displayOrderKeyAscending",
                rows: [
                    threadCardFixture(
                        host: host,
                        threadID: "bad-projection",
                        title: "Bad projection delta",
                        updatedAt: 1_100,
                        projectionID: ""
                    )
                ]
            )
        )

        guard let snapshot = await waitForLoadedSnapshot(
            from: store,
            where: { $0.rows.map(\.threadID) == ["thread-resynced"] }
        ) else {
            return XCTFail("Expected malformed projection envelope to resync, got \(store.state)")
        }
        XCTAssertEqual(snapshot.rows.map(\.title), ["Projection resynced row"])
    }

    @MainActor
    func testDuplicateProjectionSourceIdentityRequestsResync() async throws {
        let host = makeHost()
        let originalSourceRef = "host:\(host.id)/thread:thread-a"
        let connection = ScriptedThreadCardTransportConnection(
            subscribeSnapshot: dockStreamSnapshot(
                host: host,
                epoch: "epoch-1",
                seq: 1,
                cards: [
                    threadCardFixture(host: host, threadID: "thread-a", title: "Initial projection row", updatedAt: 1_000)
                ]
            ),
            resyncSnapshots: [
                dockStreamSnapshot(
                    host: host,
                    epoch: "epoch-2",
                    seq: 1,
                    cards: [
                        threadCardFixture(host: host, threadID: "thread-resynced", title: "Projection source resynced row", updatedAt: 1_200)
                    ]
                )
            ]
        )
        let store = DockStore(host: host, streamClient: ScriptedThreadCardTransportClient(connection: connection))

        await store.load()
        await connection.send(
            ThreadCardStreamUpdateDTO(
                kind: .upsert,
                schemaVersion: CodexDockConstants.Dock.streamSchemaVersion,
                identityVersion: 1,
                projectionEngineVersion: 1,
                sourceHostID: host.id,
                view: .dock,
                scope: "view",
                viewParamsKey: "dock:\(host.id)",
                epoch: "epoch-1",
                seq: 2,
                order: "displayOrderKeyAscending",
                rows: [
                    threadCardFixture(
                        host: host,
                        threadID: "thread-b",
                        title: "Duplicate source identity",
                        updatedAt: 1_100,
                        sourceRef: originalSourceRef
                    )
                ]
            )
        )

        guard let snapshot = await waitForLoadedSnapshot(
            from: store,
            where: { $0.rows.map(\.threadID) == ["thread-resynced"] }
        ) else {
            return XCTFail("Expected duplicate projection source identity to resync, got \(store.state)")
        }
        XCTAssertEqual(snapshot.rows.map(\.title), ["Projection source resynced row"])
    }

    @MainActor
    func testOutOfOrderSequenceRequestsResyncAndDoesNotReplaceRows() async throws {
        let host = makeHost()
        let connection = ScriptedThreadCardTransportConnection(
            subscribeSnapshot: dockStreamSnapshot(
                host: host,
                epoch: "epoch-1",
                seq: 5,
                cards: [
                    threadCardFixture(host: host, threadID: "thread-a", title: "Current row", updatedAt: 1_000)
                ],
            ),
            resyncSnapshots: [
                dockStreamSnapshot(
                    host: host,
                    epoch: "epoch-1",
                    seq: 6,
                    cards: [
                        threadCardFixture(host: host, threadID: "thread-resynced", title: "Resynced after stale generation", updatedAt: 1_200)
                    ],
                )
            ]
        )
        let store = DockStore(host: host, streamClient: ScriptedThreadCardTransportClient(connection: connection))

        await store.load()
        await connection.send(
            ThreadCardStreamUpdateDTO(
                kind: .upsert,
                schemaVersion: CodexDockConstants.Dock.streamSchemaVersion,
                identityVersion: 1,
                projectionEngineVersion: 1,
                sourceHostID: host.id,
                view: .dock,
                scope: "view",
                viewParamsKey: "dock:\(host.id)",
                epoch: "epoch-1",
                seq: 4,
                order: "displayOrderKeyAscending",
                rows: [
                    threadCardFixture(host: host, threadID: "older-generation", title: "Should not render", updatedAt: 1_300)
                ],
                projectionIDs: []
            )
        )

        guard let snapshot = await waitForLoadedSnapshot(
            from: store,
            where: { $0.rows.map(\.threadID) == ["thread-resynced"] }
        ) else {
            return XCTFail("Expected out-of-order seq to resync, got \(store.state)")
        }
        XCTAssertEqual(snapshot.rows.map(\.title), ["Resynced after stale generation"])
    }

    @MainActor
    func testNewEpochSnapshotCanReplacePreviousSequence() async throws {
        let host = makeHost()
        let firstConnection = ScriptedThreadCardTransportConnection(
            subscribeSnapshot: dockStreamSnapshot(
                host: host,
                epoch: "epoch-1",
                seq: 10,
                cards: [
                    threadCardFixture(host: host, threadID: "thread-old", title: "Old epoch row", updatedAt: 1_000)
                ],
            )
        )
        let secondConnection = ScriptedThreadCardTransportConnection(
            subscribeSnapshot: dockStreamSnapshot(
                host: host,
                epoch: "epoch-2",
                seq: 1,
                cards: [
                    threadCardFixture(host: host, threadID: "thread-new", title: "New epoch row", updatedAt: 1_200)
                ],
            )
        )
        let streamClient = SequencedScriptedThreadCardTransportClient(connections: [firstConnection, secondConnection])
        let store = DockStore(
            host: host,
            streamClient: streamClient,
            streamReconnectDelay: .milliseconds(10)
        )

        await store.load()
        await firstConnection.finish()

        guard let snapshot = await waitForLoadedSnapshot(
            from: store,
            where: { $0.rows.map(\.threadID) == ["thread-new"] }
        ) else {
            return XCTFail("Expected new epoch snapshot to replace older high-generation state, got \(store.state)")
        }
        XCTAssertEqual(snapshot.rows.map(\.title), ["New epoch row"])
    }

    @MainActor
    func testHostResyncDoesNotClearOtherHostRows() async throws {
        let amir = makeHost()
        let home = makeHost(url: "ws://100.66.11.7:4510")
        let registry = try HostRegistry(hosts: [amir, home])
        let amirConnection = ScriptedThreadCardTransportConnection(
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
        let homeConnection = ScriptedThreadCardTransportConnection(
            subscribeSnapshot: dockStreamSnapshot(
                host: home,
                epoch: "home-epoch",
                seq: 1,
                cards: [
                    threadCardFixture(host: home, threadID: "home-row", title: "Home row", updatedAt: 1_200)
                ]
            )
        )
        let streamClient = SequencedScriptedThreadCardTransportClient(connections: [amirConnection, homeConnection])
        let store = DockStore(registry: registry, streamClient: streamClient)

        await store.load()
        await amirConnection.send(
            ThreadCardStreamUpdateDTO(
                kind: .upsert,
                schemaVersion: CodexDockConstants.Dock.streamSchemaVersion + 1,
                sourceHostID: amir.id,
                view: .dock,
                scope: "view",
                viewParamsKey: "dock:\(amir.id)",
                epoch: "amir-epoch",
                seq: 2,
                order: "displayOrderKeyAscending",
                rows: [
                    threadCardFixture(host: amir, threadID: "bad-schema", title: "Bad schema delta", updatedAt: 1_400)
                ]
            )
        )

        guard let snapshot = await waitForLoadedSnapshot(
            from: store,
            where: { $0.rows.map(\.threadID) == ["amir-resynced", "home-row"] }
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
        let connection = ScriptedThreadCardTransportConnection(
            subscribeSnapshot: dockStreamSnapshot(
                host: host,
                epoch: "epoch-1",
                seq: 1,
                cards: [
                    threadCardFixture(host: host, threadID: "thread-a", title: "Last good", updatedAt: 1_000)
                ]
            )
        )
        let store = DockStore(host: host, streamClient: ScriptedThreadCardTransportClient(connection: connection))

        await store.load()
        await connection.send(
            ThreadCardStreamUpdateDTO(
                kind: .heartbeat,
                schemaVersion: CodexDockConstants.Dock.streamSchemaVersion,
                identityVersion: 1,
                projectionEngineVersion: 1,
                sourceHostID: host.id,
                view: .dock,
                scope: "view",
                viewParamsKey: "dock:\(host.id)",
                epoch: "epoch-1",
                seq: 1,
                order: "displayOrderKeyAscending",
                freshness: DockStreamFreshnessDTO(status: .stale, lastError: "refresh failed")
            )
        )

        guard let snapshot = await waitForLoadedSnapshot(
            from: store,
            where: { $0.hostStates.map(\.status) == [.degraded(rowCount: 1, message: "refresh failed")] }
        ) else {
            return XCTFail("Expected stale heartbeat to retain rows, got \(store.state)")
        }
        XCTAssertTrue(snapshot.isPartial)
        XCTAssertEqual(snapshot.rows.map(\.threadID), ["thread-a"])
    }

    @MainActor
    func testMissingHeartbeatMarksConnectedHostStaleAndRetainsRows() async throws {
        let host = makeHost()
        let connection = ScriptedThreadCardTransportConnection(
            subscribeSnapshot: dockStreamSnapshot(
                host: host,
                epoch: "epoch-1",
                seq: 1,
                cards: [
                    threadCardFixture(host: host, threadID: "thread-a", title: "Last good", updatedAt: 1_000)
                ]
            )
        )
        let store = DockStore(
            host: host,
            streamClient: ScriptedThreadCardTransportClient(connection: connection),
            streamReconnectDelay: .seconds(1),
            streamHeartbeatTimeout: .milliseconds(20)
        )

        await store.load()

        guard let snapshot = await waitForLoadedSnapshot(
            from: store,
            where: { $0.hostStates.map(\.status) == [.degraded(rowCount: 1, message: "Offline: Projection stream heartbeat timed out.")] }
        ) else {
            return XCTFail("Expected missing heartbeat to retain rows and mark host stale, got \(store.state)")
        }
        XCTAssertTrue(snapshot.isPartial)
        XCTAssertEqual(snapshot.rows.map(\.threadID), ["thread-a"])
    }

    @MainActor
    func testStreamDropsNonHumanCardsFromSnapshotsAndDeltas() async throws {
        let host = makeHost()
        let connection = ScriptedThreadCardTransportConnection(
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
        let store = DockStore(host: host, streamClient: ScriptedThreadCardTransportClient(connection: connection))

        await store.load()

        guard let initialSnapshot = await waitForLoadedSnapshot(
            from: store,
            where: { $0.rows.map(\.threadID) == ["human-initial"] }
        ) else {
            return XCTFail("Expected non-human snapshot cards to be dropped, got \(store.state)")
        }
        XCTAssertEqual(initialSnapshot.hostStates.map(\.status), [.loaded(rowCount: 1)])

        await connection.send(
            ThreadCardStreamUpdateDTO(
                kind: .upsert,
                schemaVersion: CodexDockConstants.Dock.streamSchemaVersion,
                identityVersion: 1,
                projectionEngineVersion: 1,
                sourceHostID: host.id,
                view: .dock,
                scope: "view",
                viewParamsKey: "dock:\(host.id)",
                epoch: "epoch-1",
                seq: 2,
                order: "displayOrderKeyAscending",
                rows: [
                    threadCardFixture(host: host, threadID: "human-delta", title: "Human delta", updatedAt: 1_300),
                    threadCardFixture(host: host, threadID: "agent-delta", title: "Agent delta", updatedAt: 1_400, sourceKind: .automation, lane: .agent)
                ],
                projectionIDs: []
            )
        )

        guard let updatedSnapshot = await waitForLoadedSnapshot(
            from: store,
            where: { $0.rows.map(\.threadID) == ["human-delta", "human-initial"] }
        ) else {
            return XCTFail("Expected non-human delta cards to be dropped, got \(store.state)")
        }
        XCTAssertEqual(updatedSnapshot.hostStates.map(\.status), [.loaded(rowCount: 2)])
    }

    func testTerminalIncompleteWindowStaysLoadedAfterDroppingNonHumanCards() async throws {
        let host = makeHost()
        var projectionState = ThreadCardProjectionState()
        projectionState.reset(hosts: [host])
        let update = dockStreamSnapshot(
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
        try projectionState.apply(threadCardReconcilerSnapshot(update), host: host)
        let snapshot = DockRenderProjector(now: Date.init).snapshot(
            from: projectionState.renderInput(hosts: [host]),
            localMetadata: [:]
        )

        XCTAssertEqual(snapshot.rows.map(\.threadID), ["human-final"])
        XCTAssertEqual(
            snapshot.hostStates.map(\.status),
            [.loaded(rowCount: 1, window: DockHostWindow(visibleRows: 1, totalRows: 2))]
        )
        XCTAssertFalse(snapshot.isPartial)
    }

    @MainActor
    func testWindowedSnapshotIsLoadedWithWindowAnnotation() async throws {
        let host = makeHost()
        let connection = ScriptedThreadCardTransportConnection(
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
        let store = DockStore(host: host, streamClient: ScriptedThreadCardTransportClient(connection: connection))

        await store.load()

        guard let snapshot = await waitForLoadedSnapshot(
            from: store,
            where: {
                $0.hostStates.map(\.status) == [
                    .degraded(rowCount: 1, message: "Refreshing")
                ]
            }
        ) else {
            return XCTFail("Expected windowed snapshot to show catch-up progress, got \(store.state)")
        }
        XCTAssertTrue(snapshot.isPartial)
        XCTAssertEqual(snapshot.rows.map(\.threadID), ["thread-a"])
    }

    @MainActor
    func testWindowedSnapshotCompletesWithStreamedCatchupPages() async throws {
        let host = makeHost()
        let connection = ScriptedThreadCardTransportConnection(
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
        let store = DockStore(host: host, streamClient: ScriptedThreadCardTransportClient(connection: connection))

        await store.load()
        await connection.send(
            ThreadCardStreamUpdateDTO(
                kind: .page,
                schemaVersion: CodexDockConstants.Dock.streamSchemaVersion,
                identityVersion: 1,
                projectionEngineVersion: 1,
                sourceHostID: host.id,
                view: .dock,
                scope: "view",
                viewParamsKey: "dock:\(host.id)",
                complete: false,
                totalRows: 3,
                window: DockStreamWindowDTO(offset: 1, limit: 1, rowCount: 1, nextOffset: 2),
                epoch: "epoch-1",
                seq: 1,
                order: "displayOrderKeyAscending",
                rows: [
                    threadCardFixture(host: host, threadID: "thread-b", title: "Window row B", updatedAt: 900)
                ],
                projectionIDs: []
            )
        )
        await connection.send(
            ThreadCardStreamUpdateDTO(
                kind: .page,
                schemaVersion: CodexDockConstants.Dock.streamSchemaVersion,
                identityVersion: 1,
                projectionEngineVersion: 1,
                sourceHostID: host.id,
                view: .dock,
                scope: "view",
                viewParamsKey: "dock:\(host.id)",
                complete: true,
                totalRows: 3,
                window: DockStreamWindowDTO(offset: 2, limit: 1, rowCount: 1),
                epoch: "epoch-1",
                seq: 1,
                order: "displayOrderKeyAscending",
                rows: [
                    threadCardFixture(host: host, threadID: "thread-c", title: "Window row C", updatedAt: 800)
                ],
                projectionIDs: []
            )
        )

        guard let snapshot = await waitForLoadedSnapshot(
            from: store,
            where: { $0.hostStates.map(\.status) == [.loaded(rowCount: 3)] }
        ) else {
            return XCTFail("Expected streamed catch-up windows to complete the host, got \(store.state)")
        }
        XCTAssertFalse(snapshot.isPartial)
        XCTAssertEqual(snapshot.rows.map(\.threadID), ["thread-a", "thread-b", "thread-c"])
    }

    @MainActor
    func testSnapshotMissingWindowContractRequestsResync() async throws {
        let host = makeHost()
        let connection = ScriptedThreadCardTransportConnection(
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
        let store = DockStore(host: host, streamClient: ScriptedThreadCardTransportClient(connection: connection))

        await store.load()
        await connection.send(
            ThreadCardStreamUpdateDTO(
                kind: .snapshot,
                schemaVersion: CodexDockConstants.Dock.streamSchemaVersion,
                identityVersion: 1,
                projectionEngineVersion: 1,
                sourceHostID: host.id,
                view: .dock,
                scope: "view",
                viewParamsKey: "dock:\(host.id)",
                epoch: "legacy-epoch",
                seq: 2,
                order: "displayOrderKeyAscending",
                freshness: DockStreamFreshnessDTO(status: .fresh),
                rows: [
                    threadCardFixture(host: host, threadID: "legacy-row", title: "Legacy row", updatedAt: 1_100)
                ]
            )
        )

        guard let snapshot = await waitForLoadedSnapshot(
            from: store,
            where: { $0.rows.map(\.threadID) == ["thread-resynced"] }
        ) else {
            return XCTFail("Expected legacy snapshot to trigger resync, got \(store.state)")
        }
        XCTAssertEqual(snapshot.hostStates.map(\.status), [.loaded(rowCount: 1)])
    }

    @MainActor
    func testClosedStreamMarksHostOfflineAndRetainsRows() async throws {
        let host = makeHost()
        let connection = ScriptedThreadCardTransportConnection(
            subscribeSnapshot: dockStreamSnapshot(
                host: host,
                epoch: "epoch-1",
                seq: 1,
                cards: [
                    threadCardFixture(host: host, threadID: "thread-a", title: "Last good", updatedAt: 1_000)
                ]
            )
        )
        let store = DockStore(host: host, streamClient: ScriptedThreadCardTransportClient(connection: connection))

        await store.load()
        await connection.finish()

        guard let snapshot = await waitForLoadedSnapshot(
            from: store,
            where: { $0.hostStates.map(\.status) == [.degraded(rowCount: 1, message: "Offline: Projection stream closed.")] }
        ) else {
            return XCTFail("Expected closed stream to retain rows and mark host offline, got \(store.state)")
        }
        XCTAssertTrue(snapshot.isPartial)
        XCTAssertEqual(snapshot.rows.map(\.threadID), ["thread-a"])
    }

    @MainActor
    func testClosedStreamReconnectsAndReplacesHostRows() async throws {
        let host = makeHost()
        let firstConnection = ScriptedThreadCardTransportConnection(
            subscribeSnapshot: dockStreamSnapshot(
                host: host,
                epoch: "epoch-1",
                seq: 1,
                cards: [
                    threadCardFixture(host: host, threadID: "thread-a", title: "Last good", updatedAt: 1_000)
                ]
            )
        )
        let secondConnection = ScriptedThreadCardTransportConnection(
            subscribeSnapshot: dockStreamSnapshot(
                host: host,
                epoch: "epoch-2",
                seq: 1,
                cards: [
                    threadCardFixture(host: host, threadID: "thread-b", title: "Reconnected row", updatedAt: 1_200)
                ]
            )
        )
        let streamClient = SequencedScriptedThreadCardTransportClient(connections: [firstConnection, secondConnection])
        let store = DockStore(
            host: host,
            streamClient: streamClient,
            streamReconnectDelay: .milliseconds(10)
        )

        await store.load()
        await firstConnection.finish()

        guard let snapshot = await waitForLoadedSnapshot(
            from: store,
            where: { $0.rows.map(\.threadID) == ["thread-b"] }
        ) else {
            return XCTFail("Expected closed stream to reconnect and replace rows, got \(store.state)")
        }
        XCTAssertEqual(snapshot.hostStates.map(\.status), [.loaded(rowCount: 1)])
        XCTAssertEqual(snapshot.rows.map(\.title), ["Reconnected row"])
        let connectCount = await streamClient.connectCount()
        XCTAssertEqual(connectCount, 2)
    }
}

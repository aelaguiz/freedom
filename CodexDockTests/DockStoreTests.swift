import XCTest
@testable import CodexDock

final class DockStoreTests: XCTestCase {
    @MainActor
    func testLoadPublishesRowsGroupedByBranch() async {
        let host = makeHost()
        let now = Date(timeIntervalSince1970: 2_000)
        let fixtures = [
            makeThreadCardFixtureSummary(
                hostID: host.id,
                threadID: "thread-a",
                branch: "feature/dock",
                status: .active(activeFlags: []),
                lastActivity: Date(timeIntervalSince1970: 1_880),
                prompt: "Build the Dock shell"
            ),
            makeThreadCardFixtureSummary(
                hostID: host.id,
                threadID: "thread-b",
                branch: "main",
                status: .active(activeFlags: [.waitingOnUserInput]),
                lastActivity: Date(timeIntervalSince1970: 1_400),
                prompt: "Review the launch proof"
            )
        ]
        let store = DockStore(
            host: host,
            streamClient: LoaderBackedThreadCardStreamClient(
                loader: FakeThreadCardFixtureLoader(mode: .success(ThreadCardFixtureResult(fixtures: fixtures)))
            ),
            now: { now }
        )

        await store.load()

        guard case let .loaded(snapshot) = store.state else {
            return XCTFail("Expected loaded state, got \(store.state)")
        }

        XCTAssertEqual(snapshot.host.displayName, host.displayName)
        XCTAssertEqual(snapshot.rowCount, 2)
        XCTAssertEqual(snapshot.rows.map(\.status), [.running, .needsInput])
        let branchProjection = snapshot.project(options: .init(lens: .branch))
        XCTAssertEqual(branchProjection.groups.map(\.title), ["feature/dock", "main"])
        XCTAssertEqual(branchProjection.groups[0].rows[0].lastActivity, "2m ago")
    }

    @MainActor
    func testLoadOrdersNotLoadedRowsByNewestActivity() async {
        let host = makeHost()
        let fixtures = [
            makeThreadCardFixtureSummary(
                hostID: host.id,
                threadID: "old-history",
                branch: "aaa-old-history",
                status: .notLoaded,
                lastActivity: Date(timeIntervalSince1970: 1_990),
                prompt: "Stored history row"
            ),
            makeThreadCardFixtureSummary(
                hostID: host.id,
                threadID: "live-running",
                branch: "zzz-live-work",
                status: .active(activeFlags: []),
                lastActivity: Date(timeIntervalSince1970: 1_200),
                prompt: "Live running row"
            )
        ]
        let store = DockStore(
            host: host,
            streamClient: LoaderBackedThreadCardStreamClient(
                loader: FakeThreadCardFixtureLoader(mode: .success(ThreadCardFixtureResult(fixtures: fixtures)))
            ),
            now: { Date(timeIntervalSince1970: 2_000) }
        )

        await store.load()

        guard case let .loaded(snapshot) = store.state else {
            return XCTFail("Expected loaded state, got \(store.state)")
        }

        let projection = snapshot.project(options: .init(lens: .newest))
        XCTAssertEqual(projection.rows.map(\.id.threadID), ["old-history", "live-running"])
        XCTAssertEqual(projection.rows.map(\.status), [.dormant, .running])
    }

    @MainActor
    func testRefreshUpdatesLoadedRows() async {
        let host = makeHost()
        let loader = SequencedThreadCardFixtureLoader(results: [
            .success(ThreadCardFixtureResult(fixtures: [
                makeThreadCardFixtureSummary(
                    hostID: host.id,
                    threadID: "thread-a",
                    branch: "main",
                    status: .idle,
                    lastActivity: Date(timeIntervalSince1970: 1_000),
                    prompt: "Initial row"
                )
            ])),
            .success(ThreadCardFixtureResult(fixtures: [
                makeThreadCardFixtureSummary(
                    hostID: host.id,
                    threadID: "thread-b",
                    branch: "feature/refresh",
                    status: .active(activeFlags: []),
                    lastActivity: Date(timeIntervalSince1970: 1_900),
                    prompt: "Refreshed row"
                )
            ]))
        ])
        let store = DockStore(host: host, streamClient: LoaderBackedThreadCardStreamClient(loader: loader))

        await store.load()
        await store.refresh()

        guard case let .loaded(snapshot) = store.state else {
            return XCTFail("Expected loaded state, got \(store.state)")
        }

        let loadCount = await loader.currentLoadCount()
        let recordedViews = await loader.recordedViews()
        XCTAssertEqual(loadCount, 2)
        XCTAssertEqual(recordedViews, [.dock, .dock])
        XCTAssertEqual(snapshot.rows.map(\.branch), ["feature/refresh"])
        XCTAssertEqual(snapshot.rows[0].title, "Refreshed row")
    }

    @MainActor
    func testFailedSubscribeResyncDropsConnectionSoRefreshCanReconnect() async throws {
        let host = makeHost()
        let badConnection = ManualThreadCardStreamConnection(
            subscribeSnapshot: dockStreamSnapshot(
                host: host,
                epoch: "bad-epoch",
                seq: 1,
                cards: [
                    threadCardFixture(host: host, threadID: "bad-row", title: "Bad row", updatedAt: 1_000)
                ],
                schemaVersion: CodexDockConstants.Dock.streamSchemaVersion + 1
            )
        )
        let goodConnection = ManualThreadCardStreamConnection(
            subscribeSnapshot: dockStreamSnapshot(
                host: host,
                epoch: "good-epoch",
                seq: 1,
                cards: [
                    threadCardFixture(host: host, threadID: "recovered-row", title: "Recovered row", updatedAt: 1_200)
                ]
            )
        )
        let streamClient = SequencedManualThreadCardStreamClient(connections: [badConnection, goodConnection])
        let store = DockStore(host: host, streamClient: streamClient)

        await store.load()
        await store.refresh()

        guard let snapshot = await waitForLoadedSnapshot(
            from: store,
            where: { $0.rows.map(\.id.threadID) == ["recovered-row"] }
        ) else {
            return XCTFail("Expected refresh to reconnect after failed subscribe resync, got \(store.state)")
        }
        XCTAssertEqual(snapshot.hostStates.map(\.status), [.loaded(rowCount: 1)])
        let connectCount = await streamClient.connectCount()
        XCTAssertEqual(connectCount, 2)
    }

    @MainActor
    func testEmptyHostPublishesEmptyState() async {
        let host = makeHost()
        let store = DockStore(
            host: host,
            streamClient: LoaderBackedThreadCardStreamClient(
                loader: FakeThreadCardFixtureLoader(mode: .success(ThreadCardFixtureResult(fixtures: [])))
            )
        )

        await store.load()

        guard case let .loaded(snapshot) = store.state else {
            return XCTFail("Expected loaded empty snapshot, got \(store.state)")
        }
        XCTAssertEqual(snapshot.rowCount, 0)
        XCTAssertEqual(snapshot.hostStates.map(\.status), [.empty])
        XCTAssertEqual(snapshot.rows, [])
    }

    @MainActor
    func testOfflineHostPublishesOfflineState() async {
        let host = makeHost()
        let store = DockStore(
            host: host,
            streamClient: LoaderBackedThreadCardStreamClient(
                loader: FakeThreadCardFixtureLoader(mode: .failure(.offline("Connection refused")))
            )
        )

        await store.load()

        guard case let .loaded(snapshot) = store.state else {
            return XCTFail("Expected loaded offline snapshot, got \(store.state)")
        }
        XCTAssertEqual(snapshot.hostStates.map(\.status), [.offline("Connection refused")])
    }

    @MainActor
    func testProtocolErrorPublishesErrorState() async {
        let host = makeHost()
        let store = DockStore(
            host: host,
            streamClient: LoaderBackedThreadCardStreamClient(
                loader: FakeThreadCardFixtureLoader(mode: .failure(.error("Invalid response")))
            )
        )

        await store.load()

        guard case let .loaded(snapshot) = store.state else {
            return XCTFail("Expected loaded error snapshot, got \(store.state)")
        }
        XCTAssertEqual(snapshot.hostStates.map(\.status), [.error("Invalid response")])
    }

    @MainActor
    func testConfigurationErrorDoesNotLoad() async {
        let store = DockStore(
            configurationError: DockHostConfigurationError.missingEndpoint
        )

        await store.load()

        XCTAssertEqual(
            store.state,
            .configurationError(DockHostConfigurationError.missingEndpoint.localizedDescription)
        )
    }

    @MainActor
    func testMultiHostFanOutKeepsLiveHostRowsWhenAnotherHostIsOffline() async throws {
        let amir = makeHost()
        let home = makeHost(url: "ws://100.66.11.7:4510")
        let registry = try HostRegistry(hosts: [amir, home])
        let loader = HostRoutedThreadCardFixtureLoader(results: [
            amir.id: .success(ThreadCardFixtureResult(fixtures: [
                makeThreadCardFixtureSummary(
                    hostID: amir.id,
                    threadID: "live-running",
                    branch: "main",
                    status: .active(activeFlags: []),
                    lastActivity: Date(timeIntervalSince1970: 2_000),
                    prompt: "Live running row"
                )
            ])),
            home.id: .failure(.offline("Home unreachable"))
        ])
        let store = DockStore(registry: registry, streamClient: LoaderBackedThreadCardStreamClient(loader: loader))

        await store.load()

        guard case let .loaded(snapshot) = store.state else {
            return XCTFail("Expected loaded state, got \(store.state)")
        }

        XCTAssertEqual(snapshot.rowCount, 1)
        XCTAssertEqual(snapshot.hostStates.map(\.id), [amir.id, home.id])
        XCTAssertEqual(snapshot.hostStates[0].status, .loaded(rowCount: 1))
        XCTAssertEqual(snapshot.hostStates[1].status, .offline("Home unreachable"))
        XCTAssertEqual(snapshot.rows.map(\.hostDisplayName), [amir.displayName])
        XCTAssertEqual(snapshot.rows[0].status, .running)
        XCTAssertEqual(store.hostConfiguration(for: home.id), home)
    }

    @MainActor
    func testLoadPublishesPartialSnapshotWhileAnotherHostIsChecking() async throws {
        let amir = makeHost()
        let home = makeHost(url: "ws://100.66.11.7:4510")
        let registry = try HostRegistry(hosts: [amir, home])
        let loader = DelayedHostRoutedThreadCardFixtureLoader(
            delayedHostID: home.id,
            results: [
                amir.id: .success(ThreadCardFixtureResult(fixtures: [
                    makeThreadCardFixtureSummary(
                        hostID: amir.id,
                        threadID: "amir-loaded",
                        branch: "main",
                        status: .active(activeFlags: []),
                        lastActivity: Date(timeIntervalSince1970: 2_000),
                        prompt: "Amir loaded first"
                    )
                ])),
                home.id: .success(ThreadCardFixtureResult(fixtures: [
                    makeThreadCardFixtureSummary(
                        hostID: home.id,
                        threadID: "home-delayed",
                        branch: "main",
                        status: .active(activeFlags: []),
                        lastActivity: Date(timeIntervalSince1970: 2_100),
                        prompt: "Home finishes later"
                    )
                ]))
            ]
        )
        let store = DockStore(registry: registry, streamClient: LoaderBackedThreadCardStreamClient(loader: loader))

        let loadTask = Task { await store.load() }
        await loader.waitForDelayedRequests(1)

        guard let partial = await waitForLoadedSnapshot(from: store, where: \.isPartial) else {
            XCTFail("Expected a partial loaded snapshot while \(home.id) was still checking; got \(store.state)")
            await loader.releaseDelayedHost()
            await loadTask.value
            return
        }

        XCTAssertEqual(partial.rows.map(\.id.threadID), ["amir-loaded"])
        XCTAssertEqual(partial.hostStates.map(\.status), [
            .loaded(rowCount: 1),
            .checking
        ])
        let projection = partial.project(options: .init(lens: .newest))
        XCTAssertEqual(projection.rows.map(\.id.threadID), ["amir-loaded"])
        XCTAssertTrue(projection.isPartial)
        XCTAssertEqual(projection.checkingHostCount, 1)

        await loader.releaseDelayedHost()
        await loadTask.value

        guard case let .loaded(finalSnapshot) = store.state else {
            return XCTFail("Expected final loaded state, got \(store.state)")
        }
        XCTAssertFalse(finalSnapshot.isPartial)
        XCTAssertEqual(finalSnapshot.hostStates.map(\.status), [
            .loaded(rowCount: 1),
            .loaded(rowCount: 1)
        ])
    }

    @MainActor
    func testMultiHostGroupingIncludesHostAndBranch() async throws {
        let amir = makeHost()
        let home = makeHost(url: "ws://100.66.11.7:4510")
        let registry = try HostRegistry(hosts: [amir, home])
        let loader = HostRoutedThreadCardFixtureLoader(results: [
            amir.id: .success(ThreadCardFixtureResult(fixtures: [
                makeThreadCardFixtureSummary(
                    hostID: amir.id,
                    threadID: "amir-main",
                    branch: "main",
                    status: .idle,
                    lastActivity: Date(timeIntervalSince1970: 1_900),
                    prompt: "Amir main row"
                )
            ])),
            home.id: .success(ThreadCardFixtureResult(fixtures: [
                makeThreadCardFixtureSummary(
                    hostID: home.id,
                    threadID: "home-main",
                    branch: "main",
                    status: .notLoaded,
                    lastActivity: Date(timeIntervalSince1970: 2_000),
                    prompt: "Home main row"
                )
            ]))
        ])
        let store = DockStore(registry: registry, streamClient: LoaderBackedThreadCardStreamClient(loader: loader))

        await store.load()

        guard case let .loaded(snapshot) = store.state else {
            return XCTFail("Expected loaded state, got \(store.state)")
        }

        XCTAssertEqual(snapshot.hostStates.map(\.status), [
            .loaded(rowCount: 1),
            .loaded(rowCount: 1)
        ])
        let branchProjection = snapshot.project(options: .init(lens: .branch, filters: DockFilterState(showsIdle: true)))
        XCTAssertEqual(branchProjection.groups.map(\.title), ["main"])
        XCTAssertEqual(branchProjection.groups[0].rows.map(\.hostDisplayName), [home.displayName, amir.displayName])
        XCTAssertEqual(branchProjection.groups[0].rows.map(\.status), [.dormant, .idle])

        let hostProjection = snapshot.project(options: .init(lens: .host, filters: DockFilterState(showsIdle: true)))
        XCTAssertEqual(hostProjection.groups.map(\.title), [home.displayName, amir.displayName])
    }

    func testDockStatusVocabularyAndSourceFiltersUseNormalizedRows() {
        XCTAssertEqual(DockRowStatusKind.dormant.label, "Not loaded")
        XCTAssertNil(DockRowStatusKind.dormant.visibleBadgeLabel)
        XCTAssertNil(DockRowStatusKind.idle.visibleBadgeLabel)
        XCTAssertEqual(DockRowStatusKind.running.visibleBadgeLabel, "Running")
        XCTAssertEqual(DockRowStatusKind.needsInput.visibleBadgeLabel, "Needs input")
        XCTAssertEqual(DockRowStatusKind.needsApproval.visibleBadgeLabel, "Needs approval")
        XCTAssertEqual(DockRowStatusKind.error.visibleBadgeLabel, "Error")
        XCTAssertEqual(DockRowStatusKind.allCases, [.running, .needsInput, .needsApproval, .idle, .error, .dormant, .unknown])
        XCTAssertEqual(DockLensID.allCases, [.newest, .host, .branch])
        XCTAssertTrue(DockSourceFilter.any.includes(makeRow(status: .idle).origin))
        XCTAssertTrue(DockSourceFilter.human.includes(makeRow(status: .running).origin))
        XCTAssertTrue(DockSourceFilter.agents.includes(makeRow(status: .idle, origin: .agentOrAutomation(subtype: .exec)).origin))
        XCTAssertTrue(DockSourceFilter.unknown.includes(makeRow(status: .idle, origin: .unknown()).origin))
        XCTAssertFalse(DockSourceFilter.human.includes(makeRow(status: .idle, origin: .agentOrAutomation(subtype: .exec)).origin))
    }

    @MainActor
    func testLocalMetadataDecoratesRowsAndSurvivesReload() async {
        let host = makeHost()
        let metadataStore = InMemoryLocalThreadMetadataStore()
        let loader = FakeThreadCardFixtureLoader(mode: .success(ThreadCardFixtureResult(fixtures: [
            makeThreadCardFixtureSummary(
                hostID: host.id,
                threadID: "thread-a",
                branch: "main",
                status: .idle,
                lastActivity: Date(timeIntervalSince1970: 1_900),
                prompt: "Metadata row"
            )
        ])))
        let store = DockStore(
            host: host,
            streamClient: LoaderBackedThreadCardStreamClient(loader: loader),
            metadataStore: metadataStore
        )
        await store.load()

        guard case let .loaded(initialSnapshot) = store.state else {
            return XCTFail("Expected loaded state, got \(store.state)")
        }

        let row = initialSnapshot.rows[0]
        await store.setLabel("Watch", for: row)
        await store.setRail(.red, for: row)

        let reloaded = DockStore(
            host: host,
            streamClient: LoaderBackedThreadCardStreamClient(loader: loader),
            metadataStore: metadataStore
        )
        await reloaded.load()

        guard case let .loaded(snapshot) = reloaded.state else {
            return XCTFail("Expected loaded state, got \(reloaded.state)")
        }

        XCTAssertEqual(snapshot.rows[0].label, "Watch")
        XCTAssertEqual(snapshot.rows[0].rail, .red)
    }

    @MainActor
    func testSetPinnedPersistsAndReprojectsPinnedRowsAfterReload() async {
        let host = makeHost()
        let metadataStore = InMemoryLocalThreadMetadataStore()
        let loader = FakeThreadCardFixtureLoader(mode: .success(ThreadCardFixtureResult(fixtures: [
            makeThreadCardFixtureSummary(
                hostID: host.id,
                threadID: "thread-pin",
                branch: "main",
                status: .active(activeFlags: []),
                lastActivity: Date(timeIntervalSince1970: 1_900),
                prompt: "Pinned row"
            )
        ])))
        let store = DockStore(
            host: host,
            streamClient: LoaderBackedThreadCardStreamClient(loader: loader),
            metadataStore: metadataStore,
            now: { Date(timeIntervalSince1970: 2_000) }
        )
        await store.load()

        guard case let .loaded(initialSnapshot) = store.state else {
            return XCTFail("Expected loaded state, got \(store.state)")
        }
        await store.setPinned(true, for: initialSnapshot.rows[0])

        let storedValues = await metadataStore.valuesSnapshot()
        let key = initialSnapshot.rows[0].metadataKey
        XCTAssertTrue(storedValues[key]?.isPinned == true)
        XCTAssertEqual(storedValues[key]?.pinnedAt, Date(timeIntervalSince1970: 2_000))
        XCTAssertEqual(storedValues[key]?.pinnedOrder, 0)

        let reloaded = DockStore(
            host: host,
            streamClient: LoaderBackedThreadCardStreamClient(loader: loader),
            metadataStore: metadataStore,
            now: { Date(timeIntervalSince1970: 2_100) }
        )
        await reloaded.load()

        guard case let .loaded(snapshot) = reloaded.state else {
            return XCTFail("Expected loaded state, got \(reloaded.state)")
        }

        let projection = snapshot.project(options: .init(lens: .host))
        XCTAssertEqual(projection.pinnedRows.map(\.id.threadID), ["thread-pin"])
        XCTAssertEqual(projection.groups.flatMap(\.rows), [])
    }

    @MainActor
    func testSetPinnedFalseClearsPinFieldsButPreservesLabelAndRail() async throws {
        let host = makeHost()
        let metadataStore = InMemoryLocalThreadMetadataStore()
        let loader = FakeThreadCardFixtureLoader(mode: .success(ThreadCardFixtureResult(fixtures: [
            makeThreadCardFixtureSummary(
                hostID: host.id,
                threadID: "thread-unpin",
                branch: "main",
                status: .active(activeFlags: []),
                lastActivity: Date(timeIntervalSince1970: 1_900),
                prompt: "Unpin row"
            )
        ])))
        let store = DockStore(
            host: host,
            streamClient: LoaderBackedThreadCardStreamClient(loader: loader),
            metadataStore: metadataStore,
            now: { Date(timeIntervalSince1970: 2_000) }
        )
        await store.load()

        guard case let .loaded(initialSnapshot) = store.state else {
            return XCTFail("Expected loaded state, got \(store.state)")
        }

        let row = initialSnapshot.rows[0]
        await store.setLabel("Watch", for: row)
        await store.setRail(.red, for: row)
        guard case let .loaded(decoratedSnapshot) = store.state else {
            return XCTFail("Expected decorated loaded state, got \(store.state)")
        }
        await store.setPinned(true, for: decoratedSnapshot.rows[0])
        guard case let .loaded(pinnedSnapshot) = store.state else {
            return XCTFail("Expected pinned loaded state, got \(store.state)")
        }
        await store.setPinned(false, for: pinnedSnapshot.rows[0])

        let storedValues = await metadataStore.valuesSnapshot()
        let metadata = try XCTUnwrap(storedValues[row.metadataKey])
        XCTAssertEqual(metadata.label, "Watch")
        XCTAssertEqual(metadata.rail, .red)
        XCTAssertEqual(metadata.isPinned, false)
        XCTAssertNil(metadata.pinnedAt)
        XCTAssertNil(metadata.pinnedOrder)
    }

    @MainActor
    func testSetPinnedAppendsNewPinsAfterExistingPinnedOrder() async throws {
        let host = makeHost()
        let metadataStore = InMemoryLocalThreadMetadataStore()
        let loader = FakeThreadCardFixtureLoader(mode: .success(ThreadCardFixtureResult(fixtures: [
            makeThreadCardFixtureSummary(
                hostID: host.id,
                threadID: "thread-a",
                branch: "main",
                status: .active(activeFlags: []),
                lastActivity: Date(timeIntervalSince1970: 1_900),
                prompt: "Thread A"
            ),
            makeThreadCardFixtureSummary(
                hostID: host.id,
                threadID: "thread-b",
                branch: "main",
                status: .active(activeFlags: []),
                lastActivity: Date(timeIntervalSince1970: 1_800),
                prompt: "Thread B"
            )
        ])))
        let store = DockStore(
            host: host,
            streamClient: LoaderBackedThreadCardStreamClient(loader: loader),
            metadataStore: metadataStore,
            now: { Date(timeIntervalSince1970: 2_000) }
        )
        await store.load()

        guard case let .loaded(initialSnapshot) = store.state else {
            return XCTFail("Expected loaded state, got \(store.state)")
        }
        let rowsByThreadID = Dictionary(uniqueKeysWithValues: initialSnapshot.rows.map { ($0.id.threadID, $0) })
        let threadB = try XCTUnwrap(rowsByThreadID["thread-b"])
        let threadA = try XCTUnwrap(rowsByThreadID["thread-a"])

        await store.setPinned(true, for: threadB)
        await store.setPinned(true, for: threadA)

        let storedValues = await metadataStore.valuesSnapshot()
        XCTAssertEqual(storedValues[threadB.metadataKey]?.pinnedOrder, 0)
        XCTAssertEqual(storedValues[threadA.metadataKey]?.pinnedOrder, 1)
    }

    @MainActor
    func testReorderPinnedRowsPreservesHiddenScopedSlotsAndWritesContiguousOrder() async throws {
        let host = makeHost()
        let metadataStore = InMemoryLocalThreadMetadataStore()
        let loader = FakeThreadCardFixtureLoader(mode: .success(ThreadCardFixtureResult(fixtures: [
            makeThreadCardFixtureSummary(
                hostID: host.id,
                threadID: "thread-a",
                branch: "main",
                status: .active(activeFlags: []),
                lastActivity: Date(timeIntervalSince1970: 1_900),
                prompt: "Thread A"
            ),
            makeThreadCardFixtureSummary(
                hostID: host.id,
                threadID: "thread-b",
                branch: "main",
                status: .active(activeFlags: []),
                lastActivity: Date(timeIntervalSince1970: 1_800),
                prompt: "Thread B"
            ),
            makeThreadCardFixtureSummary(
                hostID: host.id,
                threadID: "thread-c",
                branch: "main",
                status: .active(activeFlags: []),
                lastActivity: Date(timeIntervalSince1970: 1_700),
                prompt: "Thread C"
            )
        ])))
        let store = DockStore(
            host: host,
            streamClient: LoaderBackedThreadCardStreamClient(loader: loader),
            metadataStore: metadataStore,
            now: { Date(timeIntervalSince1970: 2_000) }
        )
        await store.load()

        guard case let .loaded(initialSnapshot) = store.state else {
            return XCTFail("Expected loaded state, got \(store.state)")
        }
        let rowsByThreadID = Dictionary(uniqueKeysWithValues: initialSnapshot.rows.map { ($0.id.threadID, $0) })
        let threadA = try XCTUnwrap(rowsByThreadID["thread-a"])
        let threadB = try XCTUnwrap(rowsByThreadID["thread-b"])
        let threadC = try XCTUnwrap(rowsByThreadID["thread-c"])

        await store.setPinned(true, for: threadA)
        await store.setPinned(true, for: threadB)
        await store.setPinned(true, for: threadC)

        guard case let .loaded(pinnedSnapshot) = store.state else {
            return XCTFail("Expected pinned loaded state, got \(store.state)")
        }
        let pinnedRows = pinnedSnapshot.project(options: .init()).pinnedRows
        let pinnedRowsByThreadID = Dictionary(uniqueKeysWithValues: pinnedRows.map { ($0.id.threadID, $0) })
        await store.reorderPinnedRows([
            try XCTUnwrap(pinnedRowsByThreadID["thread-c"]),
            try XCTUnwrap(pinnedRowsByThreadID["thread-a"])
        ])

        let storedValues = await metadataStore.valuesSnapshot()
        XCTAssertEqual(storedValues[threadC.metadataKey]?.pinnedOrder, 0)
        XCTAssertEqual(storedValues[threadB.metadataKey]?.pinnedOrder, 1)
        XCTAssertEqual(storedValues[threadA.metadataKey]?.pinnedOrder, 2)
    }

    @MainActor
    func testSetPinnedSaveFailureKeepsDockLoadedAndShowsActionError() async {
        let host = makeHost()
        let metadataStore = FailingLocalThreadMetadataStore()
        let loader = FakeThreadCardFixtureLoader(mode: .success(ThreadCardFixtureResult(fixtures: [
            makeThreadCardFixtureSummary(
                hostID: host.id,
                threadID: "thread-fail",
                branch: "main",
                status: .active(activeFlags: []),
                lastActivity: Date(timeIntervalSince1970: 1_900),
                prompt: "Pin failure row"
            )
        ])))
        let store = DockStore(
            host: host,
            streamClient: LoaderBackedThreadCardStreamClient(loader: loader),
            metadataStore: metadataStore
        )
        await store.load()

        guard case let .loaded(initialSnapshot) = store.state else {
            return XCTFail("Expected loaded state, got \(store.state)")
        }
        await store.setPinned(true, for: initialSnapshot.rows[0])

        XCTAssertEqual(store.actionError, "metadata save failed")
        guard case let .loaded(snapshot) = store.state else {
            return XCTFail("Expected failed pin save to keep Dock loaded, got \(store.state)")
        }
        XCTAssertEqual(snapshot.rows.map(\.id.threadID), ["thread-fail"])
        XCTAssertFalse(snapshot.rows[0].isPinned)
    }

    func testLocalMetadataKeyKeepsHostBackendAndThreadIdentity() async throws {
        let store = InMemoryLocalThreadMetadataStore()
        let amirKey = LocalThreadMetadataKey(
            hostID: "Amir-M5",
            backendSessionID: "session-1",
            threadID: "thread-1"
        )
        let homeKey = LocalThreadMetadataKey(
            hostID: "Home",
            backendSessionID: "session-1",
            threadID: "thread-1"
        )

        _ = try await store.save(LocalThreadMetadata(label: "Amir", rail: .blue), for: amirKey)
        let values = try await store.save(LocalThreadMetadata(label: "Home", rail: .green), for: homeKey)

        XCTAssertEqual(values[amirKey], LocalThreadMetadata(label: "Amir", rail: .blue))
        XCTAssertEqual(values[homeKey], LocalThreadMetadata(label: "Home", rail: .green))
    }

    func testFileLocalMetadataStorePersistsValues() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("thread-metadata.json")
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let key = LocalThreadMetadataKey(
            hostID: "Amir-M5",
            backendSessionID: "session-1",
            threadID: "thread-1"
        )
        let store = FileLocalThreadMetadataStore(fileURL: fileURL)
        _ = try await store.save(LocalThreadMetadata(label: "Watch", rail: .red), for: key)

        let reloadedStore = FileLocalThreadMetadataStore(fileURL: fileURL)
        let values = try await reloadedStore.load()

        XCTAssertEqual(values[key], LocalThreadMetadata(label: "Watch", rail: .red))
    }

    func testFileLocalMetadataStoreDecodesLegacyValuesWithoutPinnedFields() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("thread-metadata.json")
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let legacyJSON = """
        [
          {
            "key": {
              "hostID": "Amir-M5",
              "backendSessionID": "session-1",
              "threadID": "thread-1"
            },
            "metadata": {
              "label": "Watch",
              "rail": "red"
            }
          }
        ]
        """
        try Data(legacyJSON.utf8).write(to: fileURL)

        let store = FileLocalThreadMetadataStore(fileURL: fileURL)
        let values = try await store.load()
        let key = LocalThreadMetadataKey(
            hostID: "Amir-M5",
            backendSessionID: "session-1",
            threadID: "thread-1"
        )

        XCTAssertEqual(values[key]?.label, "Watch")
        XCTAssertEqual(values[key]?.rail, .red)
        XCTAssertEqual(values[key]?.isPinned, false)
        XCTAssertNil(values[key]?.pinnedAt)
        XCTAssertNil(values[key]?.pinnedOrder)
    }

    @MainActor
    func testArchiveRemovesDockRowOnlyAfterServerSuccessAndRefresh() async {
        let host = makeHost()
        let loader = SequencedThreadCardFixtureLoader(results: [
            .success(ThreadCardFixtureResult(fixtures: [
                makeThreadCardFixtureSummary(
                    hostID: host.id,
                    threadID: "thread-archive",
                    branch: "main",
                    status: .idle,
                    lastActivity: Date(timeIntervalSince1970: 1_900),
                    prompt: "Archive me"
                )
            ])),
            .success(ThreadCardFixtureResult(fixtures: []))
        ])
        let archiver = RecordingThreadArchiver()
        let store = DockStore(
            host: host,
            streamClient: LoaderBackedThreadCardStreamClient(loader: loader),
            archiver: archiver
        )

        await store.load()
        guard case let .loaded(initialSnapshot) = store.state else {
            return XCTFail("Expected loaded state, got \(store.state)")
        }

        let row = initialSnapshot.rows[0]
        let archived = await store.archive(row)

        XCTAssertTrue(archived)
        let archivedIDs = await archiver.archivedIDs()
        XCTAssertEqual(archivedIDs, ["thread-archive"])
        guard case let .loaded(snapshot) = store.state else {
            return XCTFail("Expected empty loaded snapshot after archive, got \(store.state)")
        }
        XCTAssertEqual(snapshot.rowCount, 0)
        XCTAssertEqual(snapshot.hostStates.map(\.status), [.empty])
    }

    @MainActor
    func testFailedArchiveKeepsDockRowRecoverable() async {
        let host = makeHost()
        let loader = FakeThreadCardFixtureLoader(mode: .success(ThreadCardFixtureResult(fixtures: [
            makeThreadCardFixtureSummary(
                hostID: host.id,
                threadID: "thread-keep",
                branch: "main",
                status: .idle,
                lastActivity: Date(timeIntervalSince1970: 1_900),
                prompt: "Keep me"
            )
        ])))
        let archiver = RecordingThreadArchiver(mode: .failure(.error("archive failed")))
        let store = DockStore(
            host: host,
            streamClient: LoaderBackedThreadCardStreamClient(loader: loader),
            archiver: archiver
        )

        await store.load()
        guard case let .loaded(initialSnapshot) = store.state else {
            return XCTFail("Expected loaded state, got \(store.state)")
        }

        let row = initialSnapshot.rows[0]
        let archived = await store.archive(row)

        XCTAssertFalse(archived)
        XCTAssertEqual(store.actionError, "archive failed")
        guard case let .loaded(snapshot) = store.state else {
            return XCTFail("Expected row to remain loaded, got \(store.state)")
        }
        XCTAssertEqual(snapshot.rows[0].id.threadID, "thread-keep")
    }

    @MainActor
    func testArchiveStoreLoadsArchivedRowsAndRestoreRefreshes() async throws {
        let host = makeHost()
        let registry = try HostRegistry(hosts: [host])
        let loader = RecordingThreadCardFixtureLoader(results: [
            .success(ThreadCardFixtureResult(fixtures: [
                makeThreadCardFixtureSummary(
                    hostID: host.id,
                    threadID: "thread-restore",
                    branch: "main",
                    status: .notLoaded,
                    lastActivity: Date(timeIntervalSince1970: 1_900),
                    prompt: "Restore me"
                )
            ])),
            .success(ThreadCardFixtureResult(fixtures: []))
        ])
        let archiver = RecordingThreadArchiver()
        let store = ArchiveStore(
            registry: registry,
            streamClient: LoaderBackedThreadCardStreamClient(loader: loader, view: .archive),
            archiver: archiver
        )

        await store.load()

        guard case let .loaded(initialSnapshot) = store.state else {
            return XCTFail("Expected archived rows, got \(store.state)")
        }
        let initialViews = await loader.recordedViews()
        XCTAssertEqual(initialViews, [.archive])

        let restored = await store.restore(initialSnapshot.sections[0].rows[0])

        XCTAssertTrue(restored)
        let unarchivedIDs = await archiver.unarchivedIDs()
        let finalViews = await loader.recordedViews()
        XCTAssertEqual(unarchivedIDs, ["thread-restore"])
        XCTAssertEqual(finalViews, [.archive, .archive])
        guard case let .empty(snapshot) = store.state else {
            return XCTFail("Expected empty archive after restore, got \(store.state)")
        }
        XCTAssertEqual(snapshot.rowCount, 0)
    }

    @MainActor
    func testArchiveStoreShowsUnavailableWhenAllHostsFail() async throws {
        let host = makeHost()
        let registry = try HostRegistry(hosts: [host])
        let loader = RecordingThreadCardFixtureLoader(results: [
            .failure(.offline("relay stopped")),
        ])
        let store = ArchiveStore(
            registry: registry,
            streamClient: LoaderBackedThreadCardStreamClient(loader: loader, view: .archive)
        )

        await store.load()

        guard case let .unavailable(snapshot, message) = store.state else {
            return XCTFail("Expected unavailable archive, got \(store.state)")
        }
        XCTAssertEqual(snapshot.rowCount, 0)
        XCTAssertTrue(message.contains("relay stopped"))
    }

    @MainActor
    func testHostSettingsSaveEditAndTestUseSharedRegistry() async throws {
        let host = makeHost()
        let registry = try HostRegistry(hosts: [host])
        let loader = HostRoutedThreadCardFixtureLoader(results: [
            host.id: .success(ThreadCardFixtureResult(fixtures: [
                makeThreadCardFixtureSummary(
                    hostID: host.id,
                    threadID: "thread-live",
                    branch: "main",
                    status: .idle,
                    lastActivity: Date(timeIntervalSince1970: 1_900),
                    prompt: "Live host"
                )
            ])),
            "100.66.11.7:4510": .failure(.offline("Home unreachable"))
        ])
        let configurationStore = InMemoryLocalDockConfigurationStore()
        let store = HostSettingsStore(
            registry: registry,
            tester: loader,
            configurationStore: configurationStore,
            now: { Date(timeIntervalSince1970: 2_000) }
        )

        try await store.saveHost(
            replacing: nil,
            host: "100.66.11.7",
            port: "4510"
        )

        XCTAssertEqual(store.registry?.hosts.map(\.id), [host.id, "100.66.11.7:4510"])
        let savedHomeConfiguration = await configurationStore.savedConfiguration()
        XCTAssertEqual(
            try savedHomeConfiguration?.hostConfigurations.map { $0.endpoint.displayEndpoint },
            [host.id, "100.66.11.7:4510"]
        )

        await store.test("100.66.11.7:4510")
        XCTAssertEqual(
            store.rows.first(where: { $0.id == "100.66.11.7:4510" })?.status,
            .offline("Home unreachable", checkedAt: Date(timeIntervalSince1970: 2_000))
        )

        try await store.saveHost(
            replacing: "100.66.11.7:4510",
            host: "100.66.11.7",
            port: "4520"
        )

        let edited = try XCTUnwrap(store.registry?.hosts.first(where: { $0.id == "100.66.11.7:4520" }))
        XCTAssertEqual(edited.displayName, "100.66.11.7")
        XCTAssertEqual(edited.webSocketURL.absoluteString, "ws://100.66.11.7:4520")
        let savedEditedConfiguration = await configurationStore.savedConfiguration()
        XCTAssertEqual(
            try savedEditedConfiguration?.hostConfigurations.map { $0.endpoint.displayEndpoint },
            [host.id, "100.66.11.7:4520"]
        )
    }

    @MainActor
    func testHostSettingsAddCreatesSeparateHostAndEditReplacesSelectedHost() async throws {
        let host = makeHost(url: "ws://amir-m5.fairy-salmon.ts.net:4510")
        let registry = try HostRegistry(hosts: [host])
        let configurationStore = InMemoryLocalDockConfigurationStore()
        let store = HostSettingsStore(
            registry: registry,
            tester: FakeThreadCardFixtureLoader(mode: .success(ThreadCardFixtureResult(fixtures: []))),
            configurationStore: configurationStore
        )

        try await store.saveHost(
            replacing: nil,
            host: "home.fairy-salmon.ts.net",
            port: "4510"
        )

        XCTAssertEqual(store.registry?.hosts.map(\.id), [
            "amir-m5.fairy-salmon.ts.net:4510",
            "home.fairy-salmon.ts.net:4510"
        ])
        XCTAssertEqual(
            store.rows.map(\.displayHost.endpoint),
            ["amir-m5.fairy-salmon.ts.net:4510", "home.fairy-salmon.ts.net:4510"]
        )
        let savedAddedConfiguration = await configurationStore.savedConfiguration()
        XCTAssertEqual(
            try savedAddedConfiguration?.hostConfigurations.map { $0.endpoint.displayEndpoint },
            ["amir-m5.fairy-salmon.ts.net:4510", "home.fairy-salmon.ts.net:4510"]
        )

        try await store.saveHost(
            replacing: "amir-m5.fairy-salmon.ts.net:4510",
            host: "backup.fairy-salmon.ts.net",
            port: "4510"
        )

        XCTAssertEqual(store.registry?.hosts.map(\.id), [
            "backup.fairy-salmon.ts.net:4510",
            "home.fairy-salmon.ts.net:4510"
        ])
        XCTAssertEqual(
            store.rows.map(\.displayHost.endpoint),
            ["backup.fairy-salmon.ts.net:4510", "home.fairy-salmon.ts.net:4510"]
        )
        let savedEditedConfiguration = await configurationStore.savedConfiguration()
        XCTAssertEqual(
            try savedEditedConfiguration?.hostConfigurations.map { $0.endpoint.displayEndpoint },
            ["backup.fairy-salmon.ts.net:4510", "home.fairy-salmon.ts.net:4510"]
        )
    }

    @MainActor
    func testHostSettingsRejectsCredentialBearingRelayURL() async throws {
        let host = makeHost()
        let registry = try HostRegistry(hosts: [host])
        let store = HostSettingsStore(
            registry: registry,
            tester: FakeThreadCardFixtureLoader(mode: .success(ThreadCardFixtureResult(fixtures: []))),
            configurationStore: InMemoryLocalDockConfigurationStore()
        )

        do {
            try await store.saveHost(
                replacing: nil,
                host: "token@192.168.50.117",
                port: "4510"
            )
            XCTFail("Expected credential-bearing relay host to be rejected")
        } catch {
            XCTAssertEqual(
                error as? HostSettingsError,
                .invalidEndpoint("token@192.168.50.117:4510")
            )
        }
    }

    @MainActor
    func testHostSettingsRejectsRawAppServerPort() async throws {
        let host = makeHost()
        let registry = try HostRegistry(hosts: [host])
        let store = HostSettingsStore(
            registry: registry,
            tester: FakeThreadCardFixtureLoader(mode: .success(ThreadCardFixtureResult(fixtures: []))),
            configurationStore: InMemoryLocalDockConfigurationStore()
        )

        do {
            try await store.saveHost(
                replacing: nil,
                host: "127.0.0.1",
                port: "4500"
            )
            XCTFail("Expected raw app-server relay port to be rejected")
        } catch {
            XCTAssertEqual(
                error as? HostSettingsError,
                .invalidEndpoint("127.0.0.1:4500")
            )
        }
    }
}

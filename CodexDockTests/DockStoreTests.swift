import XCTest
@testable import CodexDock

final class DockStoreTests: XCTestCase {
    @MainActor
    func testLoadPublishesRowsGroupedByBranch() async {
        let host = makeHost()
        let now = Date(timeIntervalSince1970: 2_000)
        let summaries = [
            makeSummary(
                hostID: host.id,
                threadID: "thread-a",
                branch: "feature/dock",
                status: .active(activeFlags: []),
                lastActivity: Date(timeIntervalSince1970: 1_880),
                prompt: "Build the Dock shell"
            ),
            makeSummary(
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
            loader: FakeDockSessionLoader(mode: .success(DockLoadResult(summaries: summaries))),
            now: { now }
        )

        await store.load()

        guard case let .loaded(snapshot) = store.state else {
            return XCTFail("Expected loaded state, got \(store.state)")
        }

        XCTAssertEqual(snapshot.host.displayName, host.displayName)
        XCTAssertEqual(snapshot.rowCount, 2)
        XCTAssertEqual(snapshot.sections.map(\.title), ["main", "feature/dock"])
        XCTAssertEqual(snapshot.sections[0].rows[0].status, .needsMe)
        XCTAssertEqual(snapshot.sections[1].rows[0].status, .running)
        XCTAssertEqual(snapshot.sections[1].rows[0].lastActivity, "2m ago")
    }

    @MainActor
    func testLoadKeepsLiveRowsAheadOfRecentLimitedHistory() async {
        let host = makeHost()
        let summaries = [
            makeSummary(
                hostID: host.id,
                threadID: "old-history",
                branch: "aaa-old-history",
                status: .notLoaded,
                lastActivity: Date(timeIntervalSince1970: 1_990),
                prompt: "Stored history row"
            ),
            makeSummary(
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
            loader: FakeDockSessionLoader(mode: .success(DockLoadResult(summaries: summaries))),
            now: { Date(timeIntervalSince1970: 2_000) }
        )

        await store.load()

        guard case let .loaded(snapshot) = store.state else {
            return XCTFail("Expected loaded state, got \(store.state)")
        }

        XCTAssertEqual(snapshot.sections.map(\.title), ["zzz-live-work", "aaa-old-history"])
        XCTAssertEqual(snapshot.sections[0].rows[0].status, .running)
        XCTAssertEqual(snapshot.sections[1].rows[0].status, .limited)
    }

    @MainActor
    func testRefreshUpdatesLoadedRows() async {
        let host = makeHost()
        let loader = SequencedDockSessionLoader(results: [
            .success(DockLoadResult(summaries: [
                makeSummary(
                    hostID: host.id,
                    threadID: "thread-a",
                    branch: "main",
                    status: .idle,
                    lastActivity: Date(timeIntervalSince1970: 1_000),
                    prompt: "Initial row"
                )
            ])),
            .success(DockLoadResult(summaries: [
                makeSummary(
                    hostID: host.id,
                    threadID: "thread-b",
                    branch: "feature/refresh",
                    status: .active(activeFlags: []),
                    lastActivity: Date(timeIntervalSince1970: 1_900),
                    prompt: "Refreshed row"
                )
            ]))
        ])
        let store = DockStore(host: host, loader: loader)

        await store.load()
        await store.refresh()

        guard case let .loaded(snapshot) = store.state else {
            return XCTFail("Expected loaded state, got \(store.state)")
        }

        let loadCount = await loader.currentLoadCount()
        let recordedQueries = await loader.recordedQueries()
        XCTAssertEqual(loadCount, 4)
        XCTAssertEqual(sortedQueries(recordedQueries), [
            .activeAgents,
            .activeAgents,
            .activeHuman,
            .activeHuman
        ])
        XCTAssertEqual(snapshot.sections.map(\.title), ["feature/refresh"])
        XCTAssertEqual(snapshot.sections[0].rows[0].title, "Refreshed row")
    }

    @MainActor
    func testEmptyHostPublishesEmptyState() async {
        let host = makeHost()
        let store = DockStore(
            host: host,
            loader: FakeDockSessionLoader(mode: .success(DockLoadResult(summaries: [])))
        )

        await store.load()

        guard case let .loaded(snapshot) = store.state else {
            return XCTFail("Expected loaded empty snapshot, got \(store.state)")
        }
        XCTAssertEqual(snapshot.rowCount, 0)
        XCTAssertEqual(snapshot.hostStates.map(\.status), [.empty])
        XCTAssertEqual(snapshot.tabs.map(\.label), [
            "All 0",
            "Needs me 0",
            "Running 0",
            "Limited 0",
            "Agents 0"
        ])
    }

    @MainActor
    func testOfflineHostPublishesOfflineState() async {
        let host = makeHost()
        let store = DockStore(
            host: host,
            loader: FakeDockSessionLoader(mode: .failure(.offline("Connection refused")))
        )

        await store.load()

        XCTAssertEqual(
            store.state,
            .offline(DockHostViewModel(host: host), "Connection refused")
        )
    }

    @MainActor
    func testProtocolErrorPublishesErrorState() async {
        let host = makeHost()
        let store = DockStore(
            host: host,
            loader: FakeDockSessionLoader(mode: .failure(.error("Invalid response")))
        )

        await store.load()

        XCTAssertEqual(
            store.state,
            .error(DockHostViewModel(host: host), "Invalid response")
        )
    }

    @MainActor
    func testConfigurationErrorDoesNotLoad() async {
        let store = DockStore(
            configurationError: DockHostConfigurationError.missingEndpoint,
            loader: FakeDockSessionLoader(mode: .failure(.error("Should not load")))
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
        let home = makeHost(
            id: "Home",
            displayName: "Home",
            url: "ws://100.66.11.7:4510"
        )
        let registry = try HostRegistry(hosts: [amir, home])
        let loader = HostRoutedDockSessionLoader(results: [
            amir.id: .success(DockLoadResult(summaries: [
                makeSummary(
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
        let store = DockStore(registry: registry, loader: loader)

        await store.load()

        guard case let .loaded(snapshot) = store.state else {
            return XCTFail("Expected loaded state, got \(store.state)")
        }

        XCTAssertEqual(snapshot.rowCount, 1)
        XCTAssertEqual(snapshot.hostStates.map(\.id), [amir.id, home.id])
        XCTAssertEqual(snapshot.hostStates[0].status, .loaded(rowCount: 1))
        XCTAssertEqual(snapshot.hostStates[1].status, .offline("Home unreachable"))
        XCTAssertEqual(snapshot.sections.map(\.title), ["\(amir.displayName) / main"])
        XCTAssertEqual(snapshot.sections[0].rows[0].status, .running)
        XCTAssertEqual(store.hostConfiguration(for: home.id), home)
    }

    @MainActor
    func testMultiHostGroupingIncludesHostAndBranch() async throws {
        let amir = makeHost()
        let home = makeHost(
            id: "Home",
            displayName: "Home",
            url: "ws://100.66.11.7:4510"
        )
        let registry = try HostRegistry(hosts: [amir, home])
        let loader = HostRoutedDockSessionLoader(results: [
            amir.id: .success(DockLoadResult(summaries: [
                makeSummary(
                    hostID: amir.id,
                    threadID: "amir-main",
                    branch: "main",
                    status: .idle,
                    lastActivity: Date(timeIntervalSince1970: 1_900),
                    prompt: "Amir main row"
                )
            ])),
            home.id: .success(DockLoadResult(summaries: [
                makeSummary(
                    hostID: home.id,
                    threadID: "home-main",
                    branch: "main",
                    status: .notLoaded,
                    lastActivity: Date(timeIntervalSince1970: 2_000),
                    prompt: "Home main row"
                )
            ]))
        ])
        let store = DockStore(registry: registry, loader: loader)

        await store.load()

        guard case let .loaded(snapshot) = store.state else {
            return XCTFail("Expected loaded state, got \(store.state)")
        }

        XCTAssertEqual(snapshot.hostStates.map(\.status), [
            .loaded(rowCount: 1),
            .loaded(rowCount: 1)
        ])
        XCTAssertEqual(snapshot.sections.map(\.title), ["\(amir.displayName) / main", "\(home.displayName) / main"])
        XCTAssertEqual(snapshot.sections.map(\.rows.count), [1, 1])
        XCTAssertEqual(snapshot.sections[0].rows[0].status, .idle)
        XCTAssertEqual(snapshot.sections[1].rows[0].status, .limited)
    }

    func testDockTabsUseNormalizedRowStatusAndOrigin() {
        XCTAssertTrue(DockTabID.all.includes(makeRow(status: .idle)))
        XCTAssertTrue(DockTabID.needsMe.includes(makeRow(status: .needsMe)))
        XCTAssertTrue(DockTabID.running.includes(makeRow(status: .running)))
        XCTAssertTrue(DockTabID.running.includes(makeRow(status: .idle)))
        XCTAssertTrue(DockTabID.running.includes(makeRow(status: .needsMe)))
        XCTAssertTrue(DockTabID.running.includes(makeRow(status: .failed)))
        XCTAssertTrue(DockTabID.limited.includes(makeRow(status: .limited)))
        XCTAssertTrue(DockTabID.agents.includes(
            makeRow(status: .idle, origin: .agentOrAutomation(subtype: .exec))
        ))
        XCTAssertTrue(DockTabID.agents.includes(
            makeRow(status: .idle, origin: .unknown())
        ))

        XCTAssertFalse(DockTabID.needsMe.includes(makeRow(status: .running)))
        XCTAssertFalse(DockTabID.limited.includes(makeRow(status: .idle)))
        XCTAssertFalse(DockTabID.all.includes(
            makeRow(status: .idle, origin: .agentOrAutomation(subtype: .exec))
        ))
        XCTAssertFalse(DockTabID.running.includes(
            makeRow(status: .running, origin: .unknown())
        ))
    }

    @MainActor
    func testLocalMetadataDecoratesRowsAndSurvivesReload() async {
        let host = makeHost()
        let metadataStore = InMemoryLocalThreadMetadataStore()
        let loader = FakeDockSessionLoader(mode: .success(DockLoadResult(summaries: [
            makeSummary(
                hostID: host.id,
                threadID: "thread-a",
                branch: "main",
                status: .idle,
                lastActivity: Date(timeIntervalSince1970: 1_900),
                prompt: "Metadata row"
            )
        ])))
        let store = DockStore(host: host, loader: loader, metadataStore: metadataStore)
        await store.load()

        guard case let .loaded(initialSnapshot) = store.state else {
            return XCTFail("Expected loaded state, got \(store.state)")
        }

        let row = initialSnapshot.sections[0].rows[0]
        await store.setLabel("Watch", for: row)
        await store.setRail(.red, for: row)

        let reloaded = DockStore(host: host, loader: loader, metadataStore: metadataStore)
        await reloaded.load()

        guard case let .loaded(snapshot) = reloaded.state else {
            return XCTFail("Expected loaded state, got \(reloaded.state)")
        }

        XCTAssertEqual(snapshot.sections[0].rows[0].label, "Watch")
        XCTAssertEqual(snapshot.sections[0].rows[0].rail, .red)
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

    @MainActor
    func testArchiveRemovesDockRowOnlyAfterServerSuccessAndRefresh() async {
        let host = makeHost()
        let loader = SequencedDockSessionLoader(results: [
            .success(DockLoadResult(summaries: [
                makeSummary(
                    hostID: host.id,
                    threadID: "thread-archive",
                    branch: "main",
                    status: .idle,
                    lastActivity: Date(timeIntervalSince1970: 1_900),
                    prompt: "Archive me"
                )
            ])),
            .success(DockLoadResult(summaries: []))
        ])
        let archiver = RecordingDockArchiver()
        let store = DockStore(host: host, loader: loader, archiver: archiver)

        await store.load()
        guard case let .loaded(initialSnapshot) = store.state else {
            return XCTFail("Expected loaded state, got \(store.state)")
        }

        let row = initialSnapshot.sections[0].rows[0]
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
        let loader = FakeDockSessionLoader(mode: .success(DockLoadResult(summaries: [
            makeSummary(
                hostID: host.id,
                threadID: "thread-keep",
                branch: "main",
                status: .idle,
                lastActivity: Date(timeIntervalSince1970: 1_900),
                prompt: "Keep me"
            )
        ])))
        let archiver = RecordingDockArchiver(mode: .failure(.error("archive failed")))
        let store = DockStore(host: host, loader: loader, archiver: archiver)

        await store.load()
        guard case let .loaded(initialSnapshot) = store.state else {
            return XCTFail("Expected loaded state, got \(store.state)")
        }

        let row = initialSnapshot.sections[0].rows[0]
        let archived = await store.archive(row)

        XCTAssertFalse(archived)
        XCTAssertEqual(store.actionError, "archive failed")
        guard case let .loaded(snapshot) = store.state else {
            return XCTFail("Expected row to remain loaded, got \(store.state)")
        }
        XCTAssertEqual(snapshot.sections[0].rows[0].id.threadID, "thread-keep")
    }

    @MainActor
    func testArchiveStoreLoadsArchivedRowsAndRestoreRefreshes() async throws {
        let host = makeHost()
        let registry = try HostRegistry(hosts: [host])
        let loader = RecordingDockSessionLoader(results: [
            .success(DockLoadResult(summaries: [
                makeSummary(
                    hostID: host.id,
                    threadID: "thread-restore",
                    branch: "main",
                    status: .notLoaded,
                    lastActivity: Date(timeIntervalSince1970: 1_900),
                    prompt: "Restore me"
                )
            ])),
            .success(DockLoadResult(summaries: []))
        ])
        let archiver = RecordingDockArchiver()
        let store = ArchiveStore(registry: registry, loader: loader, archiver: archiver)

        await store.load()

        guard case let .loaded(initialSnapshot) = store.state else {
            return XCTFail("Expected archived rows, got \(store.state)")
        }
        let initialQueries = await loader.recordedQueries()
        XCTAssertEqual(initialQueries, [.archivedHuman])

        let restored = await store.restore(initialSnapshot.sections[0].rows[0])

        XCTAssertTrue(restored)
        let unarchivedIDs = await archiver.unarchivedIDs()
        let finalQueries = await loader.recordedQueries()
        XCTAssertEqual(unarchivedIDs, ["thread-restore"])
        XCTAssertEqual(finalQueries, [.archivedHuman, .archivedHuman])
        guard case let .empty(snapshot) = store.state else {
            return XCTFail("Expected empty archive after restore, got \(store.state)")
        }
        XCTAssertEqual(snapshot.rowCount, 0)
    }

    @MainActor
    func testArchiveStoreShowsUnavailableWhenAllHostsFail() async throws {
        let host = makeHost()
        let registry = try HostRegistry(hosts: [host])
        let loader = RecordingDockSessionLoader(results: [
            .failure(.offline("relay stopped")),
        ])
        let store = ArchiveStore(registry: registry, loader: loader)

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
        let loader = HostRoutedDockSessionLoader(results: [
            host.id: .success(DockLoadResult(summaries: [
                makeSummary(
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
            try savedHomeConfiguration?.relayEndpoints.map(\.displayEndpoint),
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
        XCTAssertEqual(edited.displayName, "100.66.11.7:4520")
        XCTAssertEqual(edited.webSocketURL.absoluteString, "ws://100.66.11.7:4520")
        let savedEditedConfiguration = await configurationStore.savedConfiguration()
        XCTAssertEqual(
            try savedEditedConfiguration?.relayEndpoints.map(\.displayEndpoint),
            [host.id, "100.66.11.7:4520"]
        )
    }

    @MainActor
    func testHostSettingsRejectsCredentialBearingRelayURL() async throws {
        let host = makeHost()
        let registry = try HostRegistry(hosts: [host])
        let store = HostSettingsStore(
            registry: registry,
            tester: FakeDockSessionLoader(mode: .success(DockLoadResult(summaries: []))),
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
}

private enum FakeMode: Sendable {
    case success(DockLoadResult)
    case failure(DockLoadFailure)
}

private struct FakeDockSessionLoader: DockSessionLoading {
    private let results: [String: FakeMode]

    init(mode: FakeMode) {
        self.results = Self.results(for: mode)
    }

    func loadSessions(
        for host: DockHostConfiguration,
        query: DockSessionQuery
    ) async throws -> DockLoadResult {
        guard let mode = results[Self.key(query)] else {
            throw DockLoadFailure.error("Unexpected query \(Self.queryLabel(query))")
        }
        switch mode {
        case let .success(result):
            return result
        case let .failure(error):
            throw error
        }
    }

    private static func results(for mode: FakeMode) -> [String: FakeMode] {
        switch mode {
        case .success(let result):
            return [
                key(.activeHuman): .success(result),
                key(.activeAgents): .success(DockLoadResult(summaries: [])),
                key(.archivedHuman): .success(result)
            ]
        case .failure(let error):
            return [
                key(.activeHuman): .failure(error),
                key(.activeAgents): .failure(error),
                key(.archivedHuman): .failure(error)
            ]
        }
    }

    fileprivate static func key(_ query: DockSessionQuery) -> String {
        queryLabel(query)
    }

    fileprivate static func queryLabel(_ query: DockSessionQuery) -> String {
        if query == .activeHuman {
            return "activeHuman"
        }
        if query == .activeAgents {
            return "activeAgents"
        }
        if query == .archivedHuman {
            return "archivedHuman"
        }
        return "\(query.archived)::\(query.sourceKinds?.map(\.rawValue).joined(separator: ",") ?? "nil")"
    }
}

private actor SequencedDockSessionLoader: DockSessionLoading {
    private var resultsByQuery: [String: [FakeMode]]
    private var queries: [DockSessionQuery] = []

    init(results: [FakeMode]) {
        self.resultsByQuery = [
            Self.key(.activeHuman): results,
            Self.key(.activeAgents): Array(
                repeating: .success(DockLoadResult(summaries: [])),
                count: results.count
            )
        ]
    }

    func currentLoadCount() -> Int {
        queries.count
    }

    func recordedQueries() -> [DockSessionQuery] {
        queries
    }

    func loadSessions(
        for host: DockHostConfiguration,
        query: DockSessionQuery
    ) async throws -> DockLoadResult {
        queries.append(query)
        let key = Self.key(query)
        guard var results = resultsByQuery[key] else {
            throw DockLoadFailure.error("Unexpected query \(Self.queryLabel(query))")
        }
        guard !results.isEmpty else {
            throw DockLoadFailure.error("No result configured for query \(Self.queryLabel(query))")
        }
        let result = results.removeFirst()
        resultsByQuery[key] = results

        switch result {
        case let .success(result):
            return result
        case let .failure(error):
            throw error
        }
    }

    private static func key(_ query: DockSessionQuery) -> String {
        FakeDockSessionLoader.queryLabel(query)
    }

    private static func queryLabel(_ query: DockSessionQuery) -> String {
        FakeDockSessionLoader.queryLabel(query)
    }
}

private actor HostRoutedDockSessionLoader: DockSessionLoading {
    private let results: [String: FakeMode]

    init(results: [String: FakeMode]) {
        var scopedResults: [String: FakeMode] = [:]
        for (hostID, mode) in results {
            switch mode {
            case .success(let result):
                scopedResults[Self.key(hostID: hostID, query: .activeHuman)] = .success(result)
                scopedResults[Self.key(hostID: hostID, query: .activeAgents)] = .success(
                    DockLoadResult(summaries: [])
                )
            case .failure(let error):
                scopedResults[Self.key(hostID: hostID, query: .activeHuman)] = .failure(error)
                scopedResults[Self.key(hostID: hostID, query: .activeAgents)] = .failure(error)
            }
        }
        self.results = scopedResults
    }

    func loadSessions(
        for host: DockHostConfiguration,
        query: DockSessionQuery
    ) async throws -> DockLoadResult {
        switch results[Self.key(hostID: host.id, query: query)] {
        case let .success(result):
            return result
        case let .failure(error):
            throw error
        case nil:
            throw DockLoadFailure.error("Unexpected query \(Self.queryLabel(query)) for host \(host.id)")
        }
    }

    private static func key(hostID: String, query: DockSessionQuery) -> String {
        "\(hostID)::\(queryLabel(query))"
    }

    private static func queryLabel(_ query: DockSessionQuery) -> String {
        FakeDockSessionLoader.queryLabel(query)
    }
}

private actor RecordingDockSessionLoader: DockSessionLoading {
    private var results: [FakeMode]
    private var queries: [DockSessionQuery] = []

    init(results: [FakeMode]) {
        self.results = results
    }

    func recordedQueries() -> [DockSessionQuery] {
        queries
    }

    func archivedRequests() -> [Bool] {
        queries.map(\.archived)
    }

    func loadSessions(
        for host: DockHostConfiguration,
        query: DockSessionQuery
    ) async throws -> DockLoadResult {
        queries.append(query)
        guard !results.isEmpty else {
            throw DockLoadFailure.error("No result configured for query \(FakeDockSessionLoader.queryLabel(query))")
        }
        let result = results.removeFirst()

        switch result {
        case let .success(result):
            return result
        case let .failure(error):
            throw error
        }
    }
}

private actor RecordingDockArchiver: DockSessionArchiving {
    private let mode: FakeMode
    private var archived: [String] = []
    private var unarchived: [String] = []

    init(mode: FakeMode = .success(DockLoadResult(summaries: []))) {
        self.mode = mode
    }

    func archivedIDs() -> [String] {
        archived
    }

    func unarchivedIDs() -> [String] {
        unarchived
    }

    func archiveThread(_ threadID: String, on host: DockHostConfiguration) async throws {
        archived.append(threadID)
        try throwIfNeeded()
    }

    func unarchiveThread(_ threadID: String, on host: DockHostConfiguration) async throws {
        unarchived.append(threadID)
        try throwIfNeeded()
    }

    private func throwIfNeeded() throws {
        if case let .failure(error) = mode {
            throw error
        }
    }
}

private actor InMemoryLocalThreadMetadataStore: LocalThreadMetadataStoring {
    private var values: [LocalThreadMetadataKey: LocalThreadMetadata] = [:]

    func load() async throws -> [LocalThreadMetadataKey: LocalThreadMetadata] {
        values
    }

    func save(
        _ metadata: LocalThreadMetadata?,
        for key: LocalThreadMetadataKey
    ) async throws -> [LocalThreadMetadataKey: LocalThreadMetadata] {
        if let metadata, !metadata.isEmpty {
            values[key] = metadata
        } else {
            values.removeValue(forKey: key)
        }
        return values
    }
}

private actor InMemoryLocalDockConfigurationStore: LocalDockConfigurationStoring {
    private var saved: LocalRelayEndpointList?

    init(saved: LocalRelayEndpointList? = nil) {
        self.saved = saved
    }

    func load() async throws -> LocalRelayEndpointList? {
        saved
    }

    func save(_ configuration: LocalRelayEndpointList) async throws {
        saved = configuration
    }

    func savedConfiguration() -> LocalRelayEndpointList? {
        saved
    }
}

private func sortedQueries(_ queries: [DockSessionQuery]) -> [DockSessionQuery] {
    queries.sorted { lhs, rhs in
        querySortKey(lhs) < querySortKey(rhs)
    }
}

private func querySortKey(_ query: DockSessionQuery) -> String {
    if query == .activeAgents {
        return "0-activeAgents"
    }
    if query == .activeHuman {
        return "1-activeHuman"
    }
    if query == .archivedHuman {
        return "2-archivedHuman"
    }
    return "3-\(query.archived)-\(query.sourceKinds?.map(\.rawValue).joined(separator: ",") ?? "nil")"
}

private func makeHost(
    id: String = "Amir-M5",
    displayName: String = "Amir-M5",
    url: String? = nil
) -> DockHostConfiguration {
    let defaultURL = id == "Amir-M5" ? "ws://192.168.50.117:4500" : "ws://\(id):4500"
    let parsedURL = URL(string: url ?? defaultURL)!
    return try! DockHostConfiguration(
        host: parsedURL.host!,
        port: parsedURL.port!
    )
}

private func makeRow(
    status: DockRowStatusKind,
    origin: SessionOrigin = .humanInteractive(subtype: .cli)
) -> DockRowViewModel {
    DockRowViewModel(
        id: HostScopedThreadID(hostID: "Amir-M5", threadID: UUID().uuidString),
        backendSessionID: UUID().uuidString,
        title: "Row",
        repository: "codex-client",
        branch: "main",
        status: status,
        lastActivity: "now",
        lastActivityDate: Date(timeIntervalSince1970: 2_000),
        summary: "Summary",
        rail: .blue,
        label: nil,
        origin: origin
    )
}

private func makeSummary(
    hostID: String,
    threadID: String,
    branch: String,
    status: SessionStatus,
    lastActivity: Date,
    prompt: String,
    origin: SessionOrigin = .humanInteractive(subtype: .cli)
) -> SessionSummary {
    SessionSummary(
        id: HostScopedThreadID(hostID: hostID, threadID: threadID),
        backendSessionID: "\(threadID)-session",
        displayTitle: prompt,
        status: status,
        repository: .known("codex-client"),
        workingDirectory: .known("/Users/aelaguiz/workspace/codex-client"),
        branch: .known(branch),
        lastActivity: lastActivity,
        shortEventSummary: .known("Assistant update for \(prompt)"),
        origin: origin
    )
}

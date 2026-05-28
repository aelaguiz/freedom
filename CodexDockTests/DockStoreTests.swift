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

        XCTAssertEqual(snapshot.host.displayName, "Amir-M5")
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
        XCTAssertEqual(loadCount, 2)
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

        XCTAssertEqual(store.state, .empty(DockHostViewModel(host: host)))
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

    func testHostConfigurationReadsPhoneReachableEndpointAndTokenFile() throws {
        let tokenFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try "test-token\n".write(to: tokenFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tokenFile) }

        let host = try DockHostConfiguration.fromEnvironment([
            "CODEX_DOCK_PHONE_REACHABLE_APP_SERVER_WS": "ws://192.168.50.117:4500",
            "CODEX_DOCK_APP_SERVER_BEARER_TOKEN_FILE": tokenFile.path,
            "CODEX_DOCK_REAL_HOST_ID": "Amir-M5",
            "CODEX_DOCK_REAL_HOST_NAME": "Amir-M5"
        ])

        XCTAssertEqual(host.id, "Amir-M5")
        XCTAssertEqual(host.displayName, "Amir-M5")
        XCTAssertEqual(host.webSocketURL.absoluteString, "ws://192.168.50.117:4500")
        XCTAssertEqual(host.bearerToken, "test-token")
    }

    func testHostConfigurationRejectsMissingEndpoint() {
        XCTAssertThrowsError(
            try DockHostConfiguration.fromEnvironment([
                "CODEX_DOCK_APP_SERVER_BEARER_TOKEN": "test-token"
            ])
        ) { error in
            XCTAssertEqual(error as? DockHostConfigurationError, .missingEndpoint)
        }
    }

    func testHostRegistryReadsScopedMultiHostEnvironment() throws {
        let registry = try HostRegistry.fromEnvironment([
            "CODEX_DOCK_HOSTS": "Amir-M5, Home",
            "CODEX_DOCK_HOST_AMIR_M5_WS": "ws://192.168.50.117:4510",
            "CODEX_DOCK_HOST_AMIR_M5_BEARER_TOKEN": "amir-token",
            "CODEX_DOCK_HOST_AMIR_M5_NAME": "Amir-M5",
            "CODEX_DOCK_HOST_HOME_WS": "ws://100.66.11.7:4510",
            "CODEX_DOCK_HOST_HOME_TOKEN": "home-token",
            "CODEX_DOCK_HOST_HOME_NAME": "Home"
        ])

        XCTAssertEqual(registry.hosts.map(\.id), ["Amir-M5", "Home"])
        XCTAssertEqual(registry.hosts.map(\.displayName), ["Amir-M5", "Home"])
        XCTAssertEqual(registry.hosts.map(\.webSocketURL.absoluteString), [
            "ws://192.168.50.117:4510",
            "ws://100.66.11.7:4510"
        ])
        XCTAssertEqual(registry.hosts.map(\.bearerToken), ["amir-token", "home-token"])
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
        XCTAssertEqual(snapshot.hostStates.map(\.id), ["Amir-M5", "Home"])
        XCTAssertEqual(snapshot.hostStates[0].status, .loaded(rowCount: 1))
        XCTAssertEqual(snapshot.hostStates[1].status, .offline("Home unreachable"))
        XCTAssertEqual(snapshot.sections.map(\.title), ["Amir-M5 / main"])
        XCTAssertEqual(snapshot.sections[0].rows[0].status, .running)
        XCTAssertEqual(store.hostConfiguration(for: "Home"), home)
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
        XCTAssertEqual(snapshot.sections.map(\.title), ["Amir-M5 / main", "Home / main"])
        XCTAssertEqual(snapshot.sections.map(\.rows.count), [1, 1])
        XCTAssertEqual(snapshot.sections[0].rows[0].status, .idle)
        XCTAssertEqual(snapshot.sections[1].rows[0].status, .limited)
    }

    func testDockFiltersUseNormalizedRowStatus() {
        XCTAssertTrue(DockFilter.all.includes(makeRow(status: .idle)))
        XCTAssertTrue(DockFilter.needsMe.includes(makeRow(status: .needsMe)))
        XCTAssertTrue(DockFilter.running.includes(makeRow(status: .running)))
        XCTAssertTrue(DockFilter.running.includes(makeRow(status: .idle)))
        XCTAssertTrue(DockFilter.running.includes(makeRow(status: .needsMe)))
        XCTAssertTrue(DockFilter.running.includes(makeRow(status: .failed)))
        XCTAssertTrue(DockFilter.limited.includes(makeRow(status: .limited)))

        XCTAssertFalse(DockFilter.needsMe.includes(makeRow(status: .running)))
        XCTAssertFalse(DockFilter.limited.includes(makeRow(status: .idle)))
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
        XCTAssertEqual(store.state, .empty(DockHostViewModel(host: host)))
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
        let initialArchiveRequests = await loader.archivedRequests()
        XCTAssertEqual(initialArchiveRequests, [true])

        let restored = await store.restore(initialSnapshot.sections[0].rows[0])

        XCTAssertTrue(restored)
        let unarchivedIDs = await archiver.unarchivedIDs()
        let finalArchiveRequests = await loader.archivedRequests()
        XCTAssertEqual(unarchivedIDs, ["thread-restore"])
        XCTAssertEqual(finalArchiveRequests, [true, true])
        guard case let .empty(snapshot) = store.state else {
            return XCTFail("Expected empty archive after restore, got \(store.state)")
        }
        XCTAssertEqual(snapshot.rowCount, 0)
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
            "Home": .failure(.offline("Home unreachable"))
        ])
        let store = HostSettingsStore(
            registry: registry,
            tester: loader,
            now: { Date(timeIntervalSince1970: 2_000) }
        )

        try store.saveHost(
            replacing: nil,
            id: "Home",
            displayName: "Home",
            webSocketURL: "ws://100.66.11.7:4510",
            bearerToken: "home-token"
        )

        XCTAssertEqual(store.registry?.hosts.map(\.id), ["Amir-M5", "Home"])

        await store.test("Home")
        XCTAssertEqual(
            store.rows.first(where: { $0.id == "Home" })?.status,
            .offline("Home unreachable", checkedAt: Date(timeIntervalSince1970: 2_000))
        )

        try store.saveHost(
            replacing: "Home",
            id: "Home",
            displayName: "Home Server",
            webSocketURL: "ws://100.66.11.7:4520",
            bearerToken: "home-token-2"
        )

        let edited = try XCTUnwrap(store.registry?.hosts.first(where: { $0.id == "Home" }))
        XCTAssertEqual(edited.displayName, "Home Server")
        XCTAssertEqual(edited.webSocketURL.absoluteString, "ws://100.66.11.7:4520")
        XCTAssertEqual(edited.bearerToken, "home-token-2")
    }
}

private enum FakeMode: Sendable {
    case success(DockLoadResult)
    case failure(DockLoadFailure)
}

private struct FakeDockSessionLoader: DockSessionLoading {
    let mode: FakeMode

    func loadSessions(
        for host: DockHostConfiguration,
        archived: Bool
    ) async throws -> DockLoadResult {
        switch mode {
        case let .success(result):
            return result
        case let .failure(error):
            throw error
        }
    }
}

private actor SequencedDockSessionLoader: DockSessionLoading {
    private var results: [FakeMode]
    private(set) var loadCount = 0

    init(results: [FakeMode]) {
        self.results = results
    }

    func currentLoadCount() -> Int {
        loadCount
    }

    func loadSessions(
        for host: DockHostConfiguration,
        archived: Bool
    ) async throws -> DockLoadResult {
        loadCount += 1
        let result = results.isEmpty ? nil : results.removeFirst()

        switch result {
        case let .success(result):
            return result
        case let .failure(error):
            throw error
        case nil:
            return DockLoadResult(summaries: [])
        }
    }
}

private actor HostRoutedDockSessionLoader: DockSessionLoading {
    private let results: [String: FakeMode]

    init(results: [String: FakeMode]) {
        self.results = results
    }

    func loadSessions(
        for host: DockHostConfiguration,
        archived: Bool
    ) async throws -> DockLoadResult {
        switch results[host.id] {
        case let .success(result):
            return result
        case let .failure(error):
            throw error
        case nil:
            return DockLoadResult(summaries: [])
        }
    }
}

private actor RecordingDockSessionLoader: DockSessionLoading {
    private var results: [FakeMode]
    private var archivedFlags: [Bool] = []

    init(results: [FakeMode]) {
        self.results = results
    }

    func archivedRequests() -> [Bool] {
        archivedFlags
    }

    func loadSessions(
        for host: DockHostConfiguration,
        archived: Bool
    ) async throws -> DockLoadResult {
        archivedFlags.append(archived)
        let result = results.isEmpty ? nil : results.removeFirst()

        switch result {
        case let .success(result):
            return result
        case let .failure(error):
            throw error
        case nil:
            return DockLoadResult(summaries: [])
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

private func makeHost(
    id: String = "Amir-M5",
    displayName: String = "Amir-M5",
    url: String = "ws://192.168.50.117:4500"
) -> DockHostConfiguration {
    DockHostConfiguration(
        id: id,
        displayName: displayName,
        webSocketURL: URL(string: url)!,
        bearerToken: "test-token"
    )
}

private func makeRow(status: DockRowStatusKind) -> DockRowViewModel {
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
        label: nil
    )
}

private func makeSummary(
    hostID: String,
    threadID: String,
    branch: String,
    status: SessionStatus,
    lastActivity: Date,
    prompt: String
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
        shortEventSummary: .known("Assistant update for \(prompt)")
    )
}

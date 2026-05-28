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
        XCTAssertEqual(snapshot.sections.map(\.title), ["feature/dock", "main"])
        XCTAssertEqual(snapshot.sections[0].rows[0].status, .running)
        XCTAssertEqual(snapshot.sections[0].rows[0].lastActivity, "2m ago")
        XCTAssertEqual(snapshot.sections[1].rows[0].status, .needsMe)
    }

    @MainActor
    func testLoadKeepsMostRecentRowsAheadOfOlderRunningRows() async {
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

        XCTAssertEqual(snapshot.sections.map(\.title), ["aaa-old-history", "zzz-live-work"])
        XCTAssertEqual(snapshot.sections[0].rows[0].status, .limited)
        XCTAssertEqual(snapshot.sections[1].rows[0].status, .running)
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
        XCTAssertEqual(snapshot.sections.map(\.title), ["Home / main", "Amir-M5 / main"])
        XCTAssertEqual(snapshot.sections.map(\.rows.count), [1, 1])
        XCTAssertEqual(snapshot.sections[0].rows[0].status, .limited)
        XCTAssertEqual(snapshot.sections[1].rows[0].status, .idle)
    }

    func testDockFiltersUseNormalizedRowStatus() {
        XCTAssertTrue(DockFilter.all.includes(makeRow(status: .idle)))
        XCTAssertTrue(DockFilter.needsMe.includes(makeRow(status: .needsMe)))
        XCTAssertTrue(DockFilter.running.includes(makeRow(status: .running)))
        XCTAssertTrue(DockFilter.limited.includes(makeRow(status: .limited)))

        XCTAssertFalse(DockFilter.needsMe.includes(makeRow(status: .running)))
        XCTAssertFalse(DockFilter.running.includes(makeRow(status: .needsMe)))
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
}

private enum FakeMode: Sendable {
    case success(DockLoadResult)
    case failure(DockLoadFailure)
}

private struct FakeDockSessionLoader: DockSessionLoading {
    let mode: FakeMode

    func loadSessions(for host: DockHostConfiguration) async throws -> DockLoadResult {
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

    func loadSessions(for host: DockHostConfiguration) async throws -> DockLoadResult {
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

    func loadSessions(for host: DockHostConfiguration) async throws -> DockLoadResult {
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

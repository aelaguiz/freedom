import XCTest
@testable import CodexDock

final class ArchiveCleanupStoreTests: XCTestCase {
    @MainActor
    func testPreviewUsesFullScanAndAppliesCandidateSafetyRules() async throws {
        let host = makeHost()
        let registry = try HostRegistry(hosts: [host])
        let now = Date(timeIntervalSince1970: 20_000_000)
        let olderThan90Days = now.addingTimeInterval(-91 * 86_400)
        let exactly90Days = now.addingTimeInterval(-90 * 86_400)
        let recent = now.addingTimeInterval(-10 * 86_400)
        let loader = CleanupCardStreamRecordingLoader(results: [
            host.id: .success(
                ThreadCardFixtureResult(
                    fixtures: [
                        makeThreadCardFixtureSummary(
                            hostID: host.id,
                            threadID: "old-idle",
                            branch: "main",
                            status: .idle,
                            lastActivity: olderThan90Days,
                            prompt: "Old idle"
                        ),
                        makeThreadCardFixtureSummary(
                            hostID: host.id,
                            threadID: "old-error",
                            branch: "main",
                            status: .systemError,
                            lastActivity: olderThan90Days,
                            prompt: "Old error"
                        ),
                        makeThreadCardFixtureSummary(
                            hostID: host.id,
                            threadID: "old-pinned",
                            branch: "main",
                            status: .idle,
                            lastActivity: olderThan90Days,
                            prompt: "Old pinned"
                        ),
                        makeThreadCardFixtureSummary(
                            hostID: host.id,
                            threadID: "old-running",
                            branch: "main",
                            status: .active(activeFlags: []),
                            lastActivity: olderThan90Days,
                            prompt: "Old running"
                        ),
                        makeThreadCardFixtureSummary(
                            hostID: host.id,
                            threadID: "old-needs-input",
                            branch: "main",
                            status: .active(activeFlags: [.waitingOnUserInput]),
                            lastActivity: olderThan90Days,
                            prompt: "Old needs input"
                        ),
                        makeThreadCardFixtureSummary(
                            hostID: host.id,
                            threadID: "old-needs-approval",
                            branch: "main",
                            status: .active(activeFlags: [.waitingOnApproval]),
                            lastActivity: olderThan90Days,
                            prompt: "Old needs approval"
                        ),
                        makeThreadCardFixtureSummary(
                            hostID: host.id,
                            threadID: "old-watch",
                            branch: "main",
                            status: .idle,
                            lastActivity: olderThan90Days,
                            prompt: "Old watch"
                        ),
                        makeThreadCardFixtureSummary(
                            hostID: host.id,
                            threadID: "old-agent",
                            branch: "main",
                            status: .idle,
                            lastActivity: olderThan90Days,
                            prompt: "Old agent",
                            origin: .agentOrAutomation(subtype: .exec)
                        ),
                        makeThreadCardFixtureSummary(
                            hostID: host.id,
                            threadID: "exactly-cutoff",
                            branch: "main",
                            status: .idle,
                            lastActivity: exactly90Days,
                            prompt: "Exactly cutoff"
                        ),
                        makeThreadCardFixtureSummary(
                            hostID: host.id,
                            threadID: "recent",
                            branch: "main",
                            status: .idle,
                            lastActivity: recent,
                            prompt: "Recent"
                        )
                    ]
                )
            )
        ])
        let metadataStore = InMemoryLocalThreadMetadataStore(values: [
            metadataKey(hostID: host.id, threadID: "old-pinned"):
                LocalThreadMetadata(isPinned: true, pinnedAt: olderThan90Days),
            metadataKey(hostID: host.id, threadID: "old-watch"):
                LocalThreadMetadata(label: "Watch")
        ])
        let (store, provider) = makeCleanupStore(
            registry: registry,
            streamClient: LoaderBackedThreadCardStreamClient(loader: loader),
            archiver: SelectiveArchiveCleanupArchiver(),
            metadataStore: metadataStore,
            now: { now }
        )

        await store.loadPreview(rule: ArchiveCleanupRule(age: .days90))
        let recordedViews = await loader.recordedViews(for: host.id)

        XCTAssertEqual(recordedViews, [.dock])
        XCTAssertEqual(provider.refreshCount, 1)
        guard case .preview(let snapshot) = store.state else {
            return XCTFail("Expected cleanup preview, got \(store.state)")
        }
        XCTAssertEqual(Set(snapshot.candidates.map(\.threadID)), ["old-idle", "old-error"])
        XCTAssertEqual(store.selectedRowIDs.map(\.threadID).sorted(), ["old-error", "old-idle"])
        XCTAssertEqual(snapshot.hostSummaries.map(\.candidateCount), [2])
        XCTAssertEqual(snapshot.hostSummaries.map(\.excludedCount), [7])
        XCTAssertEqual(
            exclusionReasonsByThreadID(snapshot),
            [
                "exactly-cutoff": .tooRecent,
                "old-needs-approval": .needsApproval,
                "old-needs-input": .needsInput,
                "old-pinned": .pinned,
                "old-running": .running,
                "old-watch": .watchLabel,
                "recent": .tooRecent
            ]
        )
    }

    @MainActor
    func testPreviewUsesCurrentDockStreamStateWithoutOpeningCleanupStream() async throws {
        let host = makeHost()
        let registry = try HostRegistry(hosts: [host])
        let now = Date(timeIntervalSince1970: 20_000_000)
        let olderThan90Days = now.addingTimeInterval(-91 * 86_400)
        let firstCard = threadCardFixture(
            host: host,
            threadID: "old-first",
            title: "Old first",
            status: .idle,
            updatedAt: Int64(olderThan90Days.timeIntervalSince1970)
        )
        let secondCard = threadCardFixture(
            host: host,
            threadID: "old-second",
            title: "Old second",
            status: .idle,
            updatedAt: Int64(olderThan90Days.timeIntervalSince1970 - 1)
        )
        let provider = StaticDockCardStateProvider(
            snapshot: dockSnapshot(
                registry: registry,
                cards: [firstCard, secondCard],
                now: { now }
            )
        )
        let store = ArchiveCleanupStore(
            registry: registry,
            cardStateProvider: provider,
            archiver: SelectiveArchiveCleanupArchiver(),
            now: { now }
        )

        await store.loadPreview(rule: ArchiveCleanupRule(age: .days90))

        guard case .preview(let snapshot) = store.state else {
            return XCTFail("Expected cleanup preview, got \(store.state)")
        }
        XCTAssertEqual(snapshot.candidates.map(\.title), ["Old first", "Old second"])
        XCTAssertEqual(snapshot.hostSummaries.first?.candidateCount, 2)
        XCTAssertEqual(provider.refreshCount, 1)
    }

    @MainActor
    func testPreviewKeepsSuccessfulHostsWhenOneHostFails() async throws {
        let amir = makeHost()
        let home = makeHost(url: "ws://100.66.11.7:4510")
        let registry = try HostRegistry(hosts: [amir, home])
        let now = Date(timeIntervalSince1970: 20_000_000)
        let loader = CleanupCardStreamRecordingLoader(results: [
            amir.id: .success(
                ThreadCardFixtureResult(
                    fixtures: [
                        makeThreadCardFixtureSummary(
                            hostID: amir.id,
                            threadID: "amir-old",
                            branch: "main",
                            status: .idle,
                            lastActivity: now.addingTimeInterval(-91 * 86_400),
                            prompt: "Amir old"
                        )
                    ]
                )
            ),
            home.id: .failure(.offline("relay stopped"))
        ])
        let (store, _) = makeCleanupStore(
            registry: registry,
            streamClient: LoaderBackedThreadCardStreamClient(loader: loader),
            archiver: SelectiveArchiveCleanupArchiver(),
            metadataStore: InMemoryLocalThreadMetadataStore(),
            now: { now }
        )

        await store.loadPreview(rule: ArchiveCleanupRule(age: .days90))

        guard case .preview(let snapshot) = store.state else {
            return XCTFail("Expected partial cleanup preview, got \(store.state)")
        }
        XCTAssertEqual(snapshot.candidates.map(\.threadID), ["amir-old"])
        XCTAssertEqual(snapshot.hostStates.map(\.status), [
            .loaded(rowCount: 1),
            .offline("relay stopped")
        ])
    }

    @MainActor
    func testPreviewFailsWhenEveryHostIsUnavailable() async throws {
        let amir = makeHost()
        let home = makeHost(url: "ws://100.66.11.7:4510")
        let registry = try HostRegistry(hosts: [amir, home])
        let loader = CleanupCardStreamRecordingLoader(results: [
            amir.id: .failure(.offline("relay stopped")),
            home.id: .failure(.error("bad token"))
        ])
        let (store, _) = makeCleanupStore(
            registry: registry,
            streamClient: LoaderBackedThreadCardStreamClient(loader: loader),
            archiver: SelectiveArchiveCleanupArchiver(),
            metadataStore: InMemoryLocalThreadMetadataStore(),
            now: { Date(timeIntervalSince1970: 20_000_000) }
        )

        await store.loadPreview(rule: ArchiveCleanupRule(age: .days90))

        guard case .failed(let message) = store.state else {
            return XCTFail("Expected failed cleanup preview, got \(store.state)")
        }
        XCTAssertTrue(message.contains("relay stopped"))
        XCTAssertTrue(message.contains("bad token"))
        XCTAssertEqual(store.selectedRowIDs, [])
    }

    @MainActor
    func testArchiveSelectedTracksPerRowResultsAndKeepsFailuresSelected() async throws {
        let host = makeHost()
        let registry = try HostRegistry(hosts: [host])
        let now = Date(timeIntervalSince1970: 20_000_000)
        let loader = CleanupCardStreamRecordingLoader(results: [
            host.id: .success(
                ThreadCardFixtureResult(
                    fixtures: [
                        makeThreadCardFixtureSummary(
                            hostID: host.id,
                            threadID: "archive-ok",
                            branch: "main",
                            status: .idle,
                            lastActivity: now.addingTimeInterval(-91 * 86_400),
                            prompt: "Archive ok"
                        ),
                        makeThreadCardFixtureSummary(
                            hostID: host.id,
                            threadID: "archive-fails",
                            branch: "main",
                            status: .idle,
                            lastActivity: now.addingTimeInterval(-91 * 86_400),
                            prompt: "Archive fails"
                        )
                    ]
                )
            )
        ])
        let archiver = SelectiveArchiveCleanupArchiver(failingThreadIDs: ["archive-fails"])
        let (store, _) = makeCleanupStore(
            registry: registry,
            streamClient: LoaderBackedThreadCardStreamClient(loader: loader),
            archiver: archiver,
            metadataStore: InMemoryLocalThreadMetadataStore(),
            now: { now }
        )

        await store.loadPreview(rule: ArchiveCleanupRule(age: .days90))
        let results = await store.archiveSelected()
        let archivedIDs = await archiver.archivedIDs()

        XCTAssertEqual(Set(archivedIDs), ["archive-fails", "archive-ok"])
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: results.map { ($0.row.threadID, $0.status) }),
            [
                "archive-fails": .failed("archive failed"),
                "archive-ok": .archived
            ]
        )
        XCTAssertEqual(store.selectedRowIDs.map(\.threadID).sorted(), ["archive-fails"])
        XCTAssertEqual(store.executionResults, results)
        XCTAssertFalse(store.isExecuting)
    }

    @MainActor
    func testPreviewAndArchiveSelectedResolveLogicalHostRowToEndpointHost() async throws {
        let host = makeHost(url: "ws://amir-m5.fairy-salmon.ts.net:4510")
        let registry = try HostRegistry(hosts: [host])
        let now = Date(timeIntervalSince1970: 20_000_000)
        let loader = CleanupCardStreamRecordingLoader(results: [
            host.id: .success(
                ThreadCardFixtureResult(
                    fixtures: [
                        makeThreadCardFixtureSummary(
                            hostID: "Amir-M5",
                            threadID: "archive-logical",
                            branch: "main",
                            status: .idle,
                            lastActivity: now.addingTimeInterval(-91 * 86_400),
                            prompt: "Archive logical host"
                        )
                    ]
                )
            )
        ])
        let archiver = SelectiveArchiveCleanupArchiver()
        let (store, _) = makeCleanupStore(
            registry: registry,
            streamClient: LoaderBackedThreadCardStreamClient(loader: loader),
            archiver: archiver,
            metadataStore: InMemoryLocalThreadMetadataStore(),
            now: { now }
        )

        await store.loadPreview(rule: ArchiveCleanupRule(age: .days90))
        guard case .preview(let snapshot) = store.state else {
            return XCTFail("Expected cleanup preview, got \(store.state)")
        }
        let row = try XCTUnwrap(snapshot.candidates.first)
        XCTAssertEqual(row.hostID, "Amir-M5")
        XCTAssertEqual(row.sourceHostID, "Amir-M5")
        XCTAssertEqual(snapshot.hostSummaries.map(\.id), [host.id])
        XCTAssertEqual(snapshot.hostSummaries.map(\.candidateCount), [1])
        XCTAssertEqual(store.selectedRowIDs, Set([HostScopedThreadID(hostID: "Amir-M5", threadID: "archive-logical")]))
        XCTAssertTrue(
            snapshot.hostIdentityResolver.contains(
                rowHostID: row.hostID,
                sourceConfiguredHostID: row.sourceHostID,
                in: host.id
            )
        )

        let results = await store.archiveSelected()
        let archivedRequests = await archiver.archivedRequests()

        XCTAssertEqual(results.map(\.status), [.archived])
        XCTAssertEqual(archivedRequests.map(\.threadID), ["archive-logical"])
        XCTAssertEqual(archivedRequests.map(\.hostID), [host.id])
        XCTAssertEqual(store.selectedRowIDs, [])
    }

    @MainActor
    func testArchiveSelectedClearsSelectionAfterAllSuccess() async throws {
        let host = makeHost()
        let registry = try HostRegistry(hosts: [host])
        let now = Date(timeIntervalSince1970: 20_000_000)
        let loader = CleanupCardStreamRecordingLoader(results: [
            host.id: .success(
                ThreadCardFixtureResult(
                    fixtures: [
                        makeThreadCardFixtureSummary(
                            hostID: host.id,
                            threadID: "archive-one",
                            branch: "main",
                            status: .idle,
                            lastActivity: now.addingTimeInterval(-91 * 86_400),
                            prompt: "Archive one"
                        ),
                        makeThreadCardFixtureSummary(
                            hostID: host.id,
                            threadID: "archive-two",
                            branch: "main",
                            status: .idle,
                            lastActivity: now.addingTimeInterval(-91 * 86_400),
                            prompt: "Archive two"
                        )
                    ]
                )
            )
        ])
        let archiver = SelectiveArchiveCleanupArchiver()
        let (store, _) = makeCleanupStore(
            registry: registry,
            streamClient: LoaderBackedThreadCardStreamClient(loader: loader),
            archiver: archiver,
            metadataStore: InMemoryLocalThreadMetadataStore(),
            now: { now }
        )

        await store.loadPreview(rule: ArchiveCleanupRule(age: .days90))
        let results = await store.archiveSelected()
        let archivedIDs = await archiver.archivedIDs()

        XCTAssertEqual(Set(archivedIDs), ["archive-one", "archive-two"])
        XCTAssertEqual(results.map(\.status), [.archived, .archived])
        XCTAssertEqual(store.selectedRowIDs, [])
        XCTAssertEqual(store.executionTotalCount, 2)
        XCTAssertFalse(store.isExecuting)
    }

    @MainActor
    func testArchiveSelectedRetryFailedOnlyRetriesFailedRows() async throws {
        let host = makeHost()
        let registry = try HostRegistry(hosts: [host])
        let now = Date(timeIntervalSince1970: 20_000_000)
        let loader = CleanupCardStreamRecordingLoader(results: [
            host.id: .success(
                ThreadCardFixtureResult(
                    fixtures: [
                        makeThreadCardFixtureSummary(
                            hostID: host.id,
                            threadID: "archive-ok",
                            branch: "main",
                            status: .idle,
                            lastActivity: now.addingTimeInterval(-91 * 86_400),
                            prompt: "Archive ok"
                        ),
                        makeThreadCardFixtureSummary(
                            hostID: host.id,
                            threadID: "retry-me",
                            branch: "main",
                            status: .idle,
                            lastActivity: now.addingTimeInterval(-91 * 86_400),
                            prompt: "Retry me"
                        )
                    ]
                )
            )
        ])
        let archiver = RetryArchiveCleanupArchiver(failuresRemaining: ["retry-me": 1])
        let (store, _) = makeCleanupStore(
            registry: registry,
            streamClient: LoaderBackedThreadCardStreamClient(loader: loader),
            archiver: archiver,
            metadataStore: InMemoryLocalThreadMetadataStore(),
            now: { now }
        )

        await store.loadPreview(rule: ArchiveCleanupRule(age: .days90))
        let firstResults = await store.archiveSelected()
        let retryResults = await store.archiveSelected()
        let archivedIDs = await archiver.archivedIDs()

        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: firstResults.map { ($0.row.threadID, $0.status) }),
            [
                "archive-ok": .archived,
                "retry-me": .failed("archive failed")
            ]
        )
        XCTAssertEqual(retryResults.map(\.row.threadID), ["retry-me"])
        XCTAssertEqual(retryResults.map(\.status), [.archived])
        XCTAssertEqual(archivedIDs, ["archive-ok", "retry-me", "retry-me"])
        XCTAssertEqual(store.selectedRowIDs, [])
    }

    @MainActor
    func testArchiveSelectedStopRemainingSkipsRowsNotStarted() async throws {
        let host = makeHost()
        let registry = try HostRegistry(hosts: [host])
        let now = Date(timeIntervalSince1970: 20_000_000)
        let loader = CleanupCardStreamRecordingLoader(results: [
            host.id: .success(
                ThreadCardFixtureResult(
                    fixtures: [
                        makeThreadCardFixtureSummary(
                            hostID: host.id,
                            threadID: "archive-one",
                            branch: "main",
                            status: .idle,
                            lastActivity: now.addingTimeInterval(-91 * 86_400),
                            prompt: "Archive one"
                        ),
                        makeThreadCardFixtureSummary(
                            hostID: host.id,
                            threadID: "archive-two",
                            branch: "main",
                            status: .idle,
                            lastActivity: now.addingTimeInterval(-92 * 86_400),
                            prompt: "Archive two"
                        ),
                        makeThreadCardFixtureSummary(
                            hostID: host.id,
                            threadID: "archive-three",
                            branch: "main",
                            status: .idle,
                            lastActivity: now.addingTimeInterval(-93 * 86_400),
                            prompt: "Archive three"
                        )
                    ]
                )
            )
        ])
        let box = CleanupStoreBox()
        let archiver = StopAfterFirstArchiveCleanupArchiver {
            box.store?.stopRemaining()
        }
        let (store, _) = makeCleanupStore(
            registry: registry,
            streamClient: LoaderBackedThreadCardStreamClient(loader: loader),
            archiver: archiver,
            metadataStore: InMemoryLocalThreadMetadataStore(),
            now: { now }
        )
        box.store = store

        await store.loadPreview(rule: ArchiveCleanupRule(age: .days90))
        let results = await store.archiveSelected()
        let archivedIDs = await archiver.archivedIDs()

        XCTAssertEqual(archivedIDs, ["archive-one"])
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: results.map { ($0.row.threadID, $0.status) }),
            [
                "archive-one": .archived,
                "archive-two": .skipped,
                "archive-three": .skipped
            ]
        )
        XCTAssertEqual(store.executionResults, results)
        XCTAssertEqual(store.selectedRowIDs.map(\.threadID).sorted(), ["archive-three", "archive-two"])
        XCTAssertFalse(store.isExecuting)
    }

    private func metadataKey(hostID: String, threadID: String) -> LocalThreadMetadataKey {
        LocalThreadMetadataKey(
            hostID: hostID,
            backendSessionID: "\(threadID)-session",
            threadID: threadID
        )
    }

    private func exclusionReasonsByThreadID(
        _ snapshot: ArchiveCleanupPreviewSnapshot
    ) -> [String: ArchiveCleanupExclusionReason] {
        Dictionary(uniqueKeysWithValues: snapshot.excluded.map { excluded in
            (excluded.row.threadID, excluded.reason)
        })
    }

    @MainActor
    private func makeCleanupStore(
        registry: HostRegistry,
        streamClient: any ThreadCardStreamConnecting,
        archiver: any ThreadArchiveCommanding,
        metadataStore: any LocalThreadMetadataStoring,
        now: @escaping @Sendable () -> Date
    ) -> (ArchiveCleanupStore, TestDockCardStateProvider) {
        let dockStore = DockStore(
            registry: registry,
            streamClient: streamClient,
            archiver: archiver,
            metadataStore: metadataStore,
            streamReconnectDelay: .seconds(60),
            streamHeartbeatTimeout: .seconds(60),
            now: now
        )
        let provider = TestDockCardStateProvider(store: dockStore)
        let cleanupStore = ArchiveCleanupStore(
            registry: registry,
            cardStateProvider: provider,
            archiver: archiver,
            now: now
        )
        return (cleanupStore, provider)
    }

    private func dockSnapshot(
        registry: HostRegistry,
        cards: [DockThreadCardDTO],
        now: @escaping @Sendable () -> Date
    ) -> DockSnapshot {
        var table = ThreadCardTable()
        table.reset(hosts: registry.hosts)
        guard let host = registry.hosts.first else {
            return DockRenderProjector(now: now).snapshot(
                from: DockRenderInput(
                    hosts: [],
                    hostStates: [],
                    hostIdentityResolver: DockHostIdentityResolver(hosts: []),
                    cardsByHostID: [:],
                    isPartial: false
                ),
                localMetadata: [:]
            )
        }
        _ = table.applySnapshot(
            dockStreamSnapshot(
                host: host,
                epoch: "cleanup-static",
                seq: 1,
                cards: cards
            ),
            host: host
        )
        return table.snapshot(hosts: registry.hosts, localMetadata: [:], now: now)
    }
}

@MainActor
private final class TestDockCardStateProvider: DockCardStateProviding {
    private let store: DockStore
    private(set) var refreshCount = 0

    init(store: DockStore) {
        self.store = store
    }

    var currentDockSnapshot: DockSnapshot? {
        store.currentDockSnapshot
    }

    func refresh() async {
        refreshCount += 1
        await store.refresh()
    }
}

@MainActor
private final class StaticDockCardStateProvider: DockCardStateProviding {
    private let snapshot: DockSnapshot
    private(set) var refreshCount = 0

    init(snapshot: DockSnapshot) {
        self.snapshot = snapshot
    }

    var currentDockSnapshot: DockSnapshot? {
        snapshot
    }

    func refresh() async {
        refreshCount += 1
    }
}

private actor CleanupCardStreamRecordingLoader: ThreadCardFixtureLoading {
    private let results: [String: FakeMode]
    private var viewsByHost: [String: [ThreadCardStreamView]] = [:]

    init(results: [String: FakeMode]) {
        self.results = results
    }

    func recordedViews(for hostID: String) -> [ThreadCardStreamView] {
        viewsByHost[hostID] ?? []
    }

    func loadFixtures(
        for host: DockHostConfiguration,
        view: ThreadCardStreamView
    ) async throws -> ThreadCardFixtureResult {
        var views = viewsByHost[host.id] ?? []
        views.append(view)
        viewsByHost[host.id] = views

        switch results[host.id] ?? .failure(.error("No result for host \(host.id)")) {
        case .success(let result):
            return result
        case .failure(let failure):
            throw failure
        }
    }
}

private actor SelectiveArchiveCleanupArchiver: ThreadArchiveCommanding {
    private let failingThreadIDs: Set<String>
    private var archived: [(threadID: String, hostID: String)] = []

    init(failingThreadIDs: Set<String> = []) {
        self.failingThreadIDs = failingThreadIDs
    }

    func archivedIDs() -> [String] {
        archived.map(\.threadID)
    }

    func archivedRequests() -> [(threadID: String, hostID: String)] {
        archived
    }

    func archiveThread(_ threadID: String, on host: DockHostConfiguration) async throws {
        archived.append((threadID: threadID, hostID: host.id))
        if failingThreadIDs.contains(threadID) {
            throw DockRequestFailure.error("archive failed")
        }
    }

    func unarchiveThread(_ threadID: String, on host: DockHostConfiguration) async throws {}
}

private actor RetryArchiveCleanupArchiver: ThreadArchiveCommanding {
    private var failuresRemaining: [String: Int]
    private var archived: [String] = []

    init(failuresRemaining: [String: Int]) {
        self.failuresRemaining = failuresRemaining
    }

    func archivedIDs() -> [String] {
        archived
    }

    func archiveThread(_ threadID: String, on host: DockHostConfiguration) async throws {
        archived.append(threadID)
        let remaining = failuresRemaining[threadID] ?? 0
        if remaining > 0 {
            failuresRemaining[threadID] = remaining - 1
            throw DockRequestFailure.error("archive failed")
        }
    }

    func unarchiveThread(_ threadID: String, on host: DockHostConfiguration) async throws {}
}

@MainActor
private final class CleanupStoreBox {
    var store: ArchiveCleanupStore?
}

private actor StopAfterFirstArchiveCleanupArchiver: ThreadArchiveCommanding {
    private let onFirstArchive: @MainActor @Sendable () -> Void
    private var archived: [String] = []

    init(onFirstArchive: @escaping @MainActor @Sendable () -> Void) {
        self.onFirstArchive = onFirstArchive
    }

    func archivedIDs() -> [String] {
        archived
    }

    func archiveThread(_ threadID: String, on host: DockHostConfiguration) async throws {
        archived.append(threadID)
        if archived.count == 1 {
            await onFirstArchive()
        }
    }

    func unarchiveThread(_ threadID: String, on host: DockHostConfiguration) async throws {}
}

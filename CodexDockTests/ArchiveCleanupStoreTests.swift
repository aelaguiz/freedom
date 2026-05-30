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
        let loader = CleanupQueryRecordingLoader(results: [
            host.id: .success(
                DockLoadResult(
                    summaries: [
                        makeSummary(
                            hostID: host.id,
                            threadID: "old-idle",
                            branch: "main",
                            status: .idle,
                            lastActivity: olderThan90Days,
                            prompt: "Old idle"
                        ),
                        makeSummary(
                            hostID: host.id,
                            threadID: "old-error",
                            branch: "main",
                            status: .systemError,
                            lastActivity: olderThan90Days,
                            prompt: "Old error"
                        ),
                        makeSummary(
                            hostID: host.id,
                            threadID: "old-pinned",
                            branch: "main",
                            status: .idle,
                            lastActivity: olderThan90Days,
                            prompt: "Old pinned"
                        ),
                        makeSummary(
                            hostID: host.id,
                            threadID: "old-running",
                            branch: "main",
                            status: .active(activeFlags: []),
                            lastActivity: olderThan90Days,
                            prompt: "Old running"
                        ),
                        makeSummary(
                            hostID: host.id,
                            threadID: "old-needs-input",
                            branch: "main",
                            status: .active(activeFlags: [.waitingOnUserInput]),
                            lastActivity: olderThan90Days,
                            prompt: "Old needs input"
                        ),
                        makeSummary(
                            hostID: host.id,
                            threadID: "old-needs-approval",
                            branch: "main",
                            status: .active(activeFlags: [.waitingOnApproval]),
                            lastActivity: olderThan90Days,
                            prompt: "Old needs approval"
                        ),
                        makeSummary(
                            hostID: host.id,
                            threadID: "old-watch",
                            branch: "main",
                            status: .idle,
                            lastActivity: olderThan90Days,
                            prompt: "Old watch"
                        ),
                        makeSummary(
                            hostID: host.id,
                            threadID: "old-agent",
                            branch: "main",
                            status: .idle,
                            lastActivity: olderThan90Days,
                            prompt: "Old agent",
                            origin: .agentOrAutomation(subtype: .exec)
                        ),
                        makeSummary(
                            hostID: host.id,
                            threadID: "exactly-cutoff",
                            branch: "main",
                            status: .idle,
                            lastActivity: exactly90Days,
                            prompt: "Exactly cutoff"
                        ),
                        makeSummary(
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
        let store = ArchiveCleanupStore(
            registry: registry,
            loader: loader,
            archiver: SelectiveArchiveCleanupArchiver(),
            metadataStore: metadataStore,
            now: { now }
        )

        await store.loadPreview(rule: ArchiveCleanupRule(age: .days90))
        let recordedQueries = await loader.recordedQueries(for: host.id)

        XCTAssertEqual(recordedQueries, [.activeHumanFullScan])
        guard case .preview(let snapshot) = store.state else {
            return XCTFail("Expected cleanup preview, got \(store.state)")
        }
        XCTAssertEqual(Set(snapshot.candidates.map(\.id.threadID)), ["old-idle", "old-error"])
        XCTAssertEqual(store.selectedRowIDs.map(\.threadID).sorted(), ["old-error", "old-idle"])
        XCTAssertEqual(snapshot.hostSummaries.map(\.candidateCount), [2])
        XCTAssertEqual(snapshot.hostSummaries.map(\.excludedCount), [8])
        XCTAssertEqual(
            exclusionReasonsByThreadID(snapshot),
            [
                "exactly-cutoff": .tooRecent,
                "old-agent": .nonHuman,
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
    func testPreviewKeepsSuccessfulHostsWhenOneHostFails() async throws {
        let amir = makeHost()
        let home = makeHost(url: "ws://100.66.11.7:4510")
        let registry = try HostRegistry(hosts: [amir, home])
        let now = Date(timeIntervalSince1970: 20_000_000)
        let loader = CleanupQueryRecordingLoader(results: [
            amir.id: .success(
                DockLoadResult(
                    summaries: [
                        makeSummary(
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
        let store = ArchiveCleanupStore(
            registry: registry,
            loader: loader,
            archiver: SelectiveArchiveCleanupArchiver(),
            metadataStore: InMemoryLocalThreadMetadataStore(),
            now: { now }
        )

        await store.loadPreview(rule: ArchiveCleanupRule(age: .days90))

        guard case .preview(let snapshot) = store.state else {
            return XCTFail("Expected partial cleanup preview, got \(store.state)")
        }
        XCTAssertEqual(snapshot.candidates.map(\.id.threadID), ["amir-old"])
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
        let loader = CleanupQueryRecordingLoader(results: [
            amir.id: .failure(.offline("relay stopped")),
            home.id: .failure(.error("bad token"))
        ])
        let store = ArchiveCleanupStore(
            registry: registry,
            loader: loader,
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
        let loader = CleanupQueryRecordingLoader(results: [
            host.id: .success(
                DockLoadResult(
                    summaries: [
                        makeSummary(
                            hostID: host.id,
                            threadID: "archive-ok",
                            branch: "main",
                            status: .idle,
                            lastActivity: now.addingTimeInterval(-91 * 86_400),
                            prompt: "Archive ok"
                        ),
                        makeSummary(
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
        let store = ArchiveCleanupStore(
            registry: registry,
            loader: loader,
            archiver: archiver,
            metadataStore: InMemoryLocalThreadMetadataStore(),
            now: { now }
        )

        await store.loadPreview(rule: ArchiveCleanupRule(age: .days90))
        let results = await store.archiveSelected()
        let archivedIDs = await archiver.archivedIDs()

        XCTAssertEqual(Set(archivedIDs), ["archive-fails", "archive-ok"])
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: results.map { ($0.row.id.threadID, $0.status) }),
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
    func testArchiveSelectedClearsSelectionAfterAllSuccess() async throws {
        let host = makeHost()
        let registry = try HostRegistry(hosts: [host])
        let now = Date(timeIntervalSince1970: 20_000_000)
        let loader = CleanupQueryRecordingLoader(results: [
            host.id: .success(
                DockLoadResult(
                    summaries: [
                        makeSummary(
                            hostID: host.id,
                            threadID: "archive-one",
                            branch: "main",
                            status: .idle,
                            lastActivity: now.addingTimeInterval(-91 * 86_400),
                            prompt: "Archive one"
                        ),
                        makeSummary(
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
        let store = ArchiveCleanupStore(
            registry: registry,
            loader: loader,
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
        let loader = CleanupQueryRecordingLoader(results: [
            host.id: .success(
                DockLoadResult(
                    summaries: [
                        makeSummary(
                            hostID: host.id,
                            threadID: "archive-ok",
                            branch: "main",
                            status: .idle,
                            lastActivity: now.addingTimeInterval(-91 * 86_400),
                            prompt: "Archive ok"
                        ),
                        makeSummary(
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
        let store = ArchiveCleanupStore(
            registry: registry,
            loader: loader,
            archiver: archiver,
            metadataStore: InMemoryLocalThreadMetadataStore(),
            now: { now }
        )

        await store.loadPreview(rule: ArchiveCleanupRule(age: .days90))
        let firstResults = await store.archiveSelected()
        let retryResults = await store.archiveSelected()
        let archivedIDs = await archiver.archivedIDs()

        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: firstResults.map { ($0.row.id.threadID, $0.status) }),
            [
                "archive-ok": .archived,
                "retry-me": .failed("archive failed")
            ]
        )
        XCTAssertEqual(retryResults.map(\.row.id.threadID), ["retry-me"])
        XCTAssertEqual(retryResults.map(\.status), [.archived])
        XCTAssertEqual(archivedIDs, ["archive-ok", "retry-me", "retry-me"])
        XCTAssertEqual(store.selectedRowIDs, [])
    }

    @MainActor
    func testArchiveSelectedStopRemainingSkipsRowsNotStarted() async throws {
        let host = makeHost()
        let registry = try HostRegistry(hosts: [host])
        let now = Date(timeIntervalSince1970: 20_000_000)
        let loader = CleanupQueryRecordingLoader(results: [
            host.id: .success(
                DockLoadResult(
                    summaries: [
                        makeSummary(
                            hostID: host.id,
                            threadID: "archive-one",
                            branch: "main",
                            status: .idle,
                            lastActivity: now.addingTimeInterval(-91 * 86_400),
                            prompt: "Archive one"
                        ),
                        makeSummary(
                            hostID: host.id,
                            threadID: "archive-two",
                            branch: "main",
                            status: .idle,
                            lastActivity: now.addingTimeInterval(-92 * 86_400),
                            prompt: "Archive two"
                        ),
                        makeSummary(
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
        let store = ArchiveCleanupStore(
            registry: registry,
            loader: loader,
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
            Dictionary(uniqueKeysWithValues: results.map { ($0.row.id.threadID, $0.status) }),
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
            (excluded.row.id.threadID, excluded.reason)
        })
    }
}

private actor CleanupQueryRecordingLoader: DockSessionLoading {
    private let results: [String: FakeMode]
    private var queriesByHost: [String: [DockSessionQuery]] = [:]

    init(results: [String: FakeMode]) {
        self.results = results
    }

    func recordedQueries(for hostID: String) -> [DockSessionQuery] {
        queriesByHost[hostID] ?? []
    }

    func loadSessions(
        for host: DockHostConfiguration,
        query: DockSessionQuery
    ) async throws -> DockLoadResult {
        var queries = queriesByHost[host.id] ?? []
        queries.append(query)
        queriesByHost[host.id] = queries

        guard query == .activeHumanFullScan else {
            throw DockLoadFailure.error("Unexpected query \(query) for host \(host.id)")
        }

        switch results[host.id] ?? .failure(.error("No result for host \(host.id)")) {
        case .success(let result):
            return result
        case .failure(let failure):
            throw failure
        }
    }
}

private actor SelectiveArchiveCleanupArchiver: DockSessionArchiving {
    private let failingThreadIDs: Set<String>
    private var archived: [String] = []

    init(failingThreadIDs: Set<String> = []) {
        self.failingThreadIDs = failingThreadIDs
    }

    func archivedIDs() -> [String] {
        archived
    }

    func archiveThread(_ threadID: String, on host: DockHostConfiguration) async throws {
        archived.append(threadID)
        if failingThreadIDs.contains(threadID) {
            throw DockLoadFailure.error("archive failed")
        }
    }

    func unarchiveThread(_ threadID: String, on host: DockHostConfiguration) async throws {}
}

private actor RetryArchiveCleanupArchiver: DockSessionArchiving {
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
            throw DockLoadFailure.error("archive failed")
        }
    }

    func unarchiveThread(_ threadID: String, on host: DockHostConfiguration) async throws {}
}

@MainActor
private final class CleanupStoreBox {
    var store: ArchiveCleanupStore?
}

private actor StopAfterFirstArchiveCleanupArchiver: DockSessionArchiving {
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

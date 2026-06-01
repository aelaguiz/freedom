import Foundation
@testable import CodexDock

struct ThreadCardFixtureResult: Equatable, Sendable {
    let fixtures: [ThreadCardFixtureSummary]

    init(fixtures: [ThreadCardFixtureSummary]) {
        self.fixtures = fixtures
    }
}

protocol ThreadCardFixtureLoading: Sendable {
    func loadFixtures(
        for host: DockHostConfiguration,
        view: ThreadCardStreamView
    ) async throws -> ThreadCardFixtureResult
}

extension ThreadCardFixtureLoading {
    func testConnectionResult(to host: DockHostConfiguration) async throws -> HostConnectionTestResult {
        let result = try await loadFixtures(for: host, view: .dock)
        return HostConnectionTestResult(rowCount: result.fixtures.count)
    }
}

@MainActor
func waitForLoadedSnapshot(
    from store: DockStore,
    where predicate: (DockSnapshot) -> Bool,
    timeout: TimeInterval = 2
) async -> DockSnapshot? {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if case let .loaded(snapshot) = store.state, predicate(snapshot) {
            return snapshot
        }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    return nil
}

enum FakeMode: Sendable {
    case success(ThreadCardFixtureResult)
    case failure(DockRequestFailure)
}

struct LoaderBackedThreadCardStreamClient: ThreadCardStreamConnecting {
    let loader: any ThreadCardFixtureLoading
    let view: ThreadCardStreamView

    init(loader: any ThreadCardFixtureLoading, view: ThreadCardStreamView = .dock) {
        self.loader = loader
        self.view = view
    }

    func connect(to host: DockHostConfiguration) async throws -> any ThreadCardStreamConnection {
        LoaderBackedThreadCardStreamConnection(host: host, loader: loader, view: view)
    }
}

final class ManualThreadCardStreamClient: ThreadCardStreamConnecting, @unchecked Sendable {
    let connection: ManualThreadCardStreamConnection

    init(connection: ManualThreadCardStreamConnection) {
        self.connection = connection
    }

    func connect(to host: DockHostConfiguration) async throws -> any ThreadCardStreamConnection {
        connection
    }
}

actor SequencedManualThreadCardStreamClient: ThreadCardStreamConnecting {
    private var connections: [ManualThreadCardStreamConnection]
    private var count = 0

    init(connections: [ManualThreadCardStreamConnection]) {
        self.connections = connections
    }

    func connect(to host: DockHostConfiguration) async throws -> any ThreadCardStreamConnection {
        guard !connections.isEmpty else {
            throw DockRequestFailure.offline("No scripted stream connection")
        }
        count += 1
        return connections.removeFirst()
    }

    func connectCount() -> Int {
        count
    }
}

actor ManualThreadCardStreamConnection: ThreadCardStreamConnection {
    private var subscribeSnapshot: ThreadCardStreamUpdateDTO
    private var resyncSnapshots: [ThreadCardStreamUpdateDTO]
    private let updateStream: AsyncThrowingStream<ThreadCardStreamUpdateDTO, Error>
    private let updateContinuation: AsyncThrowingStream<ThreadCardStreamUpdateDTO, Error>.Continuation

    init(
        subscribeSnapshot: ThreadCardStreamUpdateDTO,
        resyncSnapshots: [ThreadCardStreamUpdateDTO] = []
    ) {
        self.subscribeSnapshot = subscribeSnapshot
        self.resyncSnapshots = resyncSnapshots
        let stream = AsyncThrowingStream<ThreadCardStreamUpdateDTO, Error>.makeStream()
        self.updateStream = stream.stream
        self.updateContinuation = stream.continuation
    }

    func subscribe() async throws -> ThreadCardStreamUpdateDTO {
        subscribeSnapshot
    }

    func resync() async throws -> ThreadCardStreamUpdateDTO {
        if resyncSnapshots.isEmpty {
            return subscribeSnapshot
        }
        return resyncSnapshots.removeFirst()
    }

    nonisolated func updates() -> AsyncThrowingStream<ThreadCardStreamUpdateDTO, Error> {
        updateStream
    }

    func send(_ update: ThreadCardStreamUpdateDTO) {
        updateContinuation.yield(update)
    }

    func finish() {
        updateContinuation.finish()
    }

    func close() async {
        updateContinuation.finish()
    }
}

actor LoaderBackedThreadCardStreamConnection: ThreadCardStreamConnection {
    private let host: DockHostConfiguration
    private let loader: any ThreadCardFixtureLoading
    private let view: ThreadCardStreamView
    private var seq: Int64 = 0

    init(host: DockHostConfiguration, loader: any ThreadCardFixtureLoading, view: ThreadCardStreamView) {
        self.host = host
        self.loader = loader
        self.view = view
    }

    func subscribe() async throws -> ThreadCardStreamUpdateDTO {
        try await snapshot()
    }

    func resync() async throws -> ThreadCardStreamUpdateDTO {
        try await snapshot()
    }

    nonisolated func updates() -> AsyncThrowingStream<ThreadCardStreamUpdateDTO, Error> {
        AsyncThrowingStream { _ in }
    }

    func close() async {}

    private func snapshot() async throws -> ThreadCardStreamUpdateDTO {
        seq += 1
        let result = try await loader.loadFixtures(for: host, view: view)
        let archiveState: DockThreadCardArchiveState = view == .archive ? .archived : .active

        return update(
            cards: result.fixtures.map { streamCard(from: $0, archiveState: archiveState) },
            freshness: DockStreamFreshnessDTO(status: .fresh)
        )
    }

    private func update(
        cards: [DockThreadCardDTO],
        freshness: DockStreamFreshnessDTO
    ) -> ThreadCardStreamUpdateDTO {
        let logicalHostID = cards.first?.logicalHostID ?? host.id
        let hostDisplayName = cards.first?.hostDisplayName ?? host.displayName
        return ThreadCardStreamUpdateDTO(
            kind: .snapshot,
            schemaVersion: CodexDockConstants.Dock.streamSchemaVersion,
            view: view,
            complete: true,
            totalRows: cards.count,
            window: DockStreamWindowDTO(offset: 0, limit: cards.count, rowCount: cards.count),
            stateGeneration: seq,
            epoch: host.id,
            seq: seq,
            freshness: freshness,
            hosts: [
                DockStreamHostDTO(
                    id: logicalHostID,
                    logicalHostID: logicalHostID,
                    displayName: hostDisplayName,
                    endpoint: host.endpoint.displayEndpoint
                )
            ],
            cards: cards
        )
    }

    private func streamCard(
        from summary: ThreadCardFixtureSummary,
        archiveState: DockThreadCardArchiveState = .active
    ) -> DockThreadCardDTO {
        let activity = summary.cardActivityDate ?? summary.lastActivity
        let activityAtMs = Int64(activity.timeIntervalSince1970 * 1_000)
        let logicalHostID = summary.id.hostID
        let hostDisplayName = logicalHostID == host.id ? host.displayName : logicalHostID
        let sourceKind = streamSource(from: summary.origin)
        return DockThreadCardDTO(
            id: "\(logicalHostID)::\(summary.id.threadID)",
            logicalHostID: logicalHostID,
            threadID: summary.id.threadID,
            backendSessionID: summary.backendSessionID,
            hostDisplayName: hostDisplayName,
            hostEndpoint: host.endpoint.displayEndpoint,
            orderKey: orderKey(activityAtMs: activityAtMs, threadID: summary.id.threadID),
            activityAt: ISO8601DateFormatter().string(from: activity),
            activityAtMs: activityAtMs,
            displaySummary: string(from: summary.displaySummary) ?? summary.displayTitle,
            title: summary.displayTitle,
            status: streamStatus(from: summary.status),
            sourceKind: sourceKind,
            lane: streamLane(from: summary.origin),
            archiveState: archiveState,
            freshness: .fresh,
            completeness: .complete,
            repository: string(from: summary.repository),
            workingDirectory: string(from: summary.workingDirectory),
            branch: string(from: summary.branch),
            summarySource: "test"
        )
    }

    private func streamStatus(from status: ThreadCardFixtureStatus) -> DockThreadCardStatus {
        switch status {
        case .unknown:
            return .unknown
        case .notLoaded:
            return .dormant
        case .idle:
            return .idle
        case .systemError:
            return .error
        case .active(let activeFlags):
            if activeFlags.contains(.waitingOnApproval) {
                return .needsApproval
            }
            if activeFlags.contains(.waitingOnUserInput) {
                return .needsInput
            }
            return .running
        }
    }

    private func streamSource(from origin: SessionOrigin) -> DockThreadCardSourceKind {
        switch origin.kind {
        case .humanInteractive:
            return .human
        case .agentOrAutomation:
            return .automation
        case .unknown:
            return .unknown
        }
    }

    private func streamLane(from origin: SessionOrigin) -> DockThreadCardLane {
        switch origin.kind {
        case .humanInteractive:
            return .human
        case .agentOrAutomation:
            return .agent
        case .unknown:
            return .unknown
        }
    }

    private func string(from text: ThreadCardFixtureText) -> String? {
        switch text {
        case .known(let value):
            return value
        case .unknown:
            return nil
        }
    }

    private func orderKey(activityAtMs: Int64, threadID: String) -> String {
        String(format: "%019lld:%@", Int64.max - activityAtMs, threadID)
    }
}

struct FakeThreadCardFixtureLoader: ThreadCardFixtureLoading {
    private let mode: FakeMode

    init(mode: FakeMode) {
        self.mode = mode
    }

    func loadFixtures(
        for host: DockHostConfiguration,
        view: ThreadCardStreamView
    ) async throws -> ThreadCardFixtureResult {
        switch mode {
        case let .success(result):
            return result
        case let .failure(error):
            throw error
        }
    }
}

extension FakeThreadCardFixtureLoader: HostConnectionTesting {
    func testConnection(to host: DockHostConfiguration) async throws -> HostConnectionTestResult {
        try await testConnectionResult(to: host)
    }
}

actor SequencedThreadCardFixtureLoader: ThreadCardFixtureLoading {
    private var results: [FakeMode]
    private var requestedViews: [ThreadCardStreamView] = []

    init(results: [FakeMode]) {
        self.results = results
    }

    func currentLoadCount() -> Int {
        requestedViews.count
    }

    func recordedViews() -> [ThreadCardStreamView] {
        requestedViews
    }

    func loadFixtures(
        for host: DockHostConfiguration,
        view: ThreadCardStreamView
    ) async throws -> ThreadCardFixtureResult {
        requestedViews.append(view)
        guard !results.isEmpty else {
            throw DockRequestFailure.error("No result configured for \(view.rawValue) stream")
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

actor HostRoutedThreadCardFixtureLoader: ThreadCardFixtureLoading {
    private let results: [String: FakeMode]

    init(results: [String: FakeMode]) {
        self.results = results
    }

    func loadFixtures(
        for host: DockHostConfiguration,
        view: ThreadCardStreamView
    ) async throws -> ThreadCardFixtureResult {
        switch results[host.id] {
        case let .success(result):
            return result
        case let .failure(error):
            throw error
        case nil:
            throw DockRequestFailure.error("No \(view.rawValue) fixture result for host \(host.id)")
        }
    }
}

extension HostRoutedThreadCardFixtureLoader: HostConnectionTesting {
    func testConnection(to host: DockHostConfiguration) async throws -> HostConnectionTestResult {
        try await testConnectionResult(to: host)
    }
}

actor DelayedHostRoutedThreadCardFixtureLoader: ThreadCardFixtureLoading {
    private let delayedHostID: String
    private let results: [String: FakeMode]
    private var delayedContinuations: [CheckedContinuation<Void, Never>] = []

    init(delayedHostID: String, results: [String: FakeMode]) {
        self.delayedHostID = delayedHostID
        self.results = results
    }

    func waitForDelayedRequests(_ count: Int) async {
        while delayedContinuations.count < count {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    func releaseDelayedHost() {
        let continuations = delayedContinuations
        delayedContinuations = []
        continuations.forEach { $0.resume() }
    }

    func loadFixtures(
        for host: DockHostConfiguration,
        view: ThreadCardStreamView
    ) async throws -> ThreadCardFixtureResult {
        if host.id == delayedHostID {
            await withCheckedContinuation { continuation in
                delayedContinuations.append(continuation)
            }
        }

        switch results[host.id] {
        case let .success(result):
            return result
        case let .failure(error):
            throw error
        case nil:
            throw DockRequestFailure.error("No \(view.rawValue) fixture result for host \(host.id)")
        }
    }
}

actor RecordingThreadCardFixtureLoader: ThreadCardFixtureLoading {
    private var results: [FakeMode]
    private var requestedViews: [ThreadCardStreamView] = []

    init(results: [FakeMode]) {
        self.results = results
    }

    func recordedViews() -> [ThreadCardStreamView] {
        requestedViews
    }

    func archivedRequests() -> [ThreadCardStreamView] {
        requestedViews.filter { $0 == .archive }
    }

    func loadFixtures(
        for host: DockHostConfiguration,
        view: ThreadCardStreamView
    ) async throws -> ThreadCardFixtureResult {
        requestedViews.append(view)
        guard !results.isEmpty else {
            throw DockRequestFailure.error("No result configured for \(view.rawValue) stream")
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

actor RecordingThreadArchiver: ThreadArchiveCommanding {
    private let mode: FakeMode
    private var archived: [String] = []
    private var unarchived: [String] = []

    init(mode: FakeMode = .success(ThreadCardFixtureResult(fixtures: []))) {
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

actor InMemoryLocalThreadMetadataStore: LocalThreadMetadataStoring {
    private var values: [LocalThreadMetadataKey: LocalThreadMetadata]

    init(values: [LocalThreadMetadataKey: LocalThreadMetadata] = [:]) {
        self.values = values
    }

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

    func save(
        _ values: [LocalThreadMetadataKey: LocalThreadMetadata]
    ) async throws -> [LocalThreadMetadataKey: LocalThreadMetadata] {
        let persistedValues = values.filter { !$0.value.isEmpty }
        self.values = persistedValues
        return persistedValues
    }

    func valuesSnapshot() -> [LocalThreadMetadataKey: LocalThreadMetadata] {
        values
    }
}

struct LocalThreadMetadataTestError: LocalizedError {
    var errorDescription: String? {
        "metadata save failed"
    }
}

actor FailingLocalThreadMetadataStore: LocalThreadMetadataStoring {
    private let values: [LocalThreadMetadataKey: LocalThreadMetadata]

    init(values: [LocalThreadMetadataKey: LocalThreadMetadata] = [:]) {
        self.values = values
    }

    func load() async throws -> [LocalThreadMetadataKey: LocalThreadMetadata] {
        values
    }

    func save(
        _ metadata: LocalThreadMetadata?,
        for key: LocalThreadMetadataKey
    ) async throws -> [LocalThreadMetadataKey: LocalThreadMetadata] {
        throw LocalThreadMetadataTestError()
    }

    func save(
        _ values: [LocalThreadMetadataKey: LocalThreadMetadata]
    ) async throws -> [LocalThreadMetadataKey: LocalThreadMetadata] {
        throw LocalThreadMetadataTestError()
    }
}

actor InMemoryLocalDockConfigurationStore: LocalDockConfigurationStoring {
    private var saved: LocalRelayHostList?

    init(saved: LocalRelayHostList? = nil) {
        self.saved = saved
    }

    func load() async throws -> LocalRelayHostList? {
        saved
    }

    func save(_ configuration: LocalRelayHostList) async throws {
        saved = configuration
    }

    func savedConfiguration() -> LocalRelayHostList? {
        saved
    }
}

func makeHost(url: String = "ws://192.168.50.117:4510") -> DockHostConfiguration {
    let parsedURL = URL(string: url)!
    return try! DockHostConfiguration(
        host: parsedURL.host!,
        port: parsedURL.port!
    )
}

func makeRow(
    status: DockRowStatusKind,
    origin: SessionOrigin = .humanInteractive(subtype: .cli)
) -> DockRowViewModel {
    DockRowViewModel(
        id: HostScopedThreadID(hostID: "Amir-M5", threadID: UUID().uuidString),
        backendSessionID: UUID().uuidString,
        title: "Row",
        hostDisplayName: "Amir-M5",
        hostEndpoint: "Amir-M5.local:4510",
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

func makeThreadCardFixtureSummary(
    hostID: String,
    threadID: String,
    branch: String,
    status: ThreadCardFixtureStatus,
    lastActivity: Date,
    prompt: String,
    origin: SessionOrigin = .humanInteractive(subtype: .cli)
) -> ThreadCardFixtureSummary {
    ThreadCardFixtureSummary(
        id: HostScopedThreadID(hostID: hostID, threadID: threadID),
        backendSessionID: "\(threadID)-session",
        displayTitle: prompt,
        status: status,
        repository: .known("codex-client"),
        workingDirectory: .known("/Users/aelaguiz/workspace/codex-client"),
        branch: .known(branch),
        lastActivity: lastActivity,
        displaySummary: .known("Assistant update for \(prompt)"),
        cardActivityDate: lastActivity,
        origin: origin
    )
}

func dockStreamSnapshot(
    host: DockHostConfiguration,
    epoch: String,
    seq: Int64,
    cards: [DockThreadCardDTO],
    view: ThreadCardStreamView = .dock,
    schemaVersion: Int? = CodexDockConstants.Dock.streamSchemaVersion,
    freshness: DockStreamFreshnessDTO = DockStreamFreshnessDTO(status: .fresh),
    complete: Bool = true,
    totalRows: Int? = nil,
    window: DockStreamWindowDTO? = nil,
    stateGeneration: Int64? = nil
) -> ThreadCardStreamUpdateDTO {
    let logicalHostID = cards.first?.logicalHostID ?? host.id
    let hostDisplayName = cards.first?.hostDisplayName ?? host.displayName
    return ThreadCardStreamUpdateDTO(
        kind: .snapshot,
        schemaVersion: schemaVersion,
        view: view,
        complete: complete,
        totalRows: totalRows ?? cards.count,
        window: window ?? DockStreamWindowDTO(
            offset: 0,
            limit: cards.count,
            rowCount: cards.count,
            nextOffset: nil
        ),
        stateGeneration: stateGeneration ?? seq,
        epoch: epoch,
        seq: seq,
        freshness: freshness,
        hosts: [
            DockStreamHostDTO(
                id: logicalHostID,
                logicalHostID: logicalHostID,
                displayName: hostDisplayName,
                endpoint: host.endpoint.displayEndpoint
            )
        ],
        cards: cards
    )
}

func threadCardFixture(
    host: DockHostConfiguration,
    threadID: String,
    title: String,
    status: DockThreadCardStatus = .running,
    updatedAt: Int64,
    logicalHostID: String? = nil,
    hostDisplayName: String? = nil,
    sourceKind: DockThreadCardSourceKind = .human,
    lane: DockThreadCardLane = .human,
    relationship: DockThreadCardRelationship? = nil,
    forkedFromID: String? = nil
) -> DockThreadCardDTO {
    let activityAt = Date(timeIntervalSince1970: TimeInterval(updatedAt))
    let activityAtMs = Int64(activityAt.timeIntervalSince1970 * 1_000)
    let cardLogicalHostID = logicalHostID ?? host.id
    let cardHostDisplayName = hostDisplayName ?? (cardLogicalHostID == host.id ? host.displayName : cardLogicalHostID)
    return DockThreadCardDTO(
        id: "\(cardLogicalHostID)::\(threadID)",
        logicalHostID: cardLogicalHostID,
        threadID: threadID,
        backendSessionID: "\(threadID)-session",
        hostDisplayName: cardHostDisplayName,
        hostEndpoint: host.endpoint.displayEndpoint,
        orderKey: String(format: "%019lld:%@", Int64.max - activityAtMs, threadID),
        activityAt: ISO8601DateFormatter().string(from: activityAt),
        activityAtMs: activityAtMs,
        displaySummary: "Summary for \(title)",
        title: title,
        status: status,
        sourceKind: sourceKind,
        lane: lane,
        relationship: relationship,
        forkedFromID: forkedFromID,
        archiveState: .active,
        freshness: .fresh,
        completeness: .complete,
        repository: "codex-client",
        workingDirectory: "/Users/aelaguiz/workspace/codex-client",
        branch: "main",
        summarySource: "test"
    )
}

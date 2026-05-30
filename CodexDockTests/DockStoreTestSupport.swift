import Foundation
@testable import CodexDock

private enum DockSessionTestScope: String, CaseIterable, Hashable, Sendable {
    case human
    case agents

    var label: String {
        switch self {
        case .human:
            return "Dock"
        case .agents:
            return "Agents"
        }
    }

    var query: DockSessionQuery {
        switch self {
        case .human:
            return .activeHuman
        case .agents:
            return .activeAgents
        }
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
    case success(DockLoadResult)
    case failure(DockLoadFailure)
}

struct LoaderBackedDockStreamClient: DockStreamConnecting {
    let loader: any DockSessionLoading

    func connect(to host: DockHostConfiguration) async throws -> any DockStreamConnection {
        LoaderBackedDockStreamConnection(host: host, loader: loader)
    }
}

final class ManualDockStreamClient: DockStreamConnecting, @unchecked Sendable {
    let connection: ManualDockStreamConnection

    init(connection: ManualDockStreamConnection) {
        self.connection = connection
    }

    func connect(to host: DockHostConfiguration) async throws -> any DockStreamConnection {
        connection
    }
}

actor SequencedManualDockStreamClient: DockStreamConnecting {
    private var connections: [ManualDockStreamConnection]
    private var count = 0

    init(connections: [ManualDockStreamConnection]) {
        self.connections = connections
    }

    func connect(to host: DockHostConfiguration) async throws -> any DockStreamConnection {
        guard !connections.isEmpty else {
            throw DockLoadFailure.offline("No scripted stream connection")
        }
        count += 1
        return connections.removeFirst()
    }

    func connectCount() -> Int {
        count
    }
}

actor ManualDockStreamConnection: DockStreamConnection {
    private var subscribeSnapshot: DockStreamUpdateDTO
    private var resyncSnapshots: [DockStreamUpdateDTO]
    private let updateStream: AsyncThrowingStream<DockStreamUpdateDTO, Error>
    private let updateContinuation: AsyncThrowingStream<DockStreamUpdateDTO, Error>.Continuation

    init(
        subscribeSnapshot: DockStreamUpdateDTO,
        resyncSnapshots: [DockStreamUpdateDTO] = []
    ) {
        self.subscribeSnapshot = subscribeSnapshot
        self.resyncSnapshots = resyncSnapshots
        let stream = AsyncThrowingStream<DockStreamUpdateDTO, Error>.makeStream()
        self.updateStream = stream.stream
        self.updateContinuation = stream.continuation
    }

    func subscribe() async throws -> DockStreamUpdateDTO {
        subscribeSnapshot
    }

    func resync() async throws -> DockStreamUpdateDTO {
        if resyncSnapshots.isEmpty {
            return subscribeSnapshot
        }
        return resyncSnapshots.removeFirst()
    }

    nonisolated func updates() -> AsyncThrowingStream<DockStreamUpdateDTO, Error> {
        updateStream
    }

    func send(_ update: DockStreamUpdateDTO) {
        updateContinuation.yield(update)
    }

    func finish() {
        updateContinuation.finish()
    }

    func close() async {
        updateContinuation.finish()
    }
}

actor LoaderBackedDockStreamConnection: DockStreamConnection {
    private let host: DockHostConfiguration
    private let loader: any DockSessionLoading
    private var seq: Int64 = 0

    init(host: DockHostConfiguration, loader: any DockSessionLoading) {
        self.host = host
        self.loader = loader
    }

    func subscribe() async throws -> DockStreamUpdateDTO {
        try await snapshot()
    }

    func resync() async throws -> DockStreamUpdateDTO {
        try await snapshot()
    }

    nonisolated func updates() -> AsyncThrowingStream<DockStreamUpdateDTO, Error> {
        AsyncThrowingStream { _ in }
    }

    func close() async {}

    private func snapshot() async throws -> DockStreamUpdateDTO {
        seq += 1
        let scopedResults = await loadScopes()
        let successes = scopedResults.compactMap { scope, result -> (DockSessionTestScope, DockLoadResult)? in
            if case .success(let value) = result {
                return (scope, value)
            }
            return nil
        }
        let failures = scopedResults.compactMap { scope, result -> (DockSessionTestScope, DockLoadFailure)? in
            if case .failure(let value) = result {
                return (scope, value)
            }
            return nil
        }

        guard !successes.isEmpty else {
            throw failures.first?.1 ?? DockLoadFailure.error("No stream rows loaded")
        }

        let sessions = deduplicated(successes.flatMap { scope, result in
            result.summaries.map { summary in
                (scope, summary)
            }
        })
        let freshness: DockStreamFreshnessDTO
        if failures.isEmpty {
            freshness = DockStreamFreshnessDTO(status: .fresh)
        } else {
            let message = failures.map { scope, failure in
                "\(scope.label): \(failure.localizedDescription)"
            }.joined(separator: "; ")
            freshness = DockStreamFreshnessDTO(status: .stale, lastError: message)
        }

        return DockStreamUpdateDTO(
            kind: .snapshot,
            schemaVersion: CodexDockConstants.Dock.streamSchemaVersion,
            epoch: host.id,
            seq: seq,
            freshness: freshness,
            hosts: [DockStreamHostDTO(id: host.id, displayName: host.displayName, endpoint: host.endpoint.displayEndpoint)],
            sessions: sessions.map { streamSession(from: $0) }
        )
    }

    private func loadScopes() async -> [(DockSessionTestScope, Result<DockLoadResult, DockLoadFailure>)] {
        let host = self.host
        let loader = self.loader
        return await withTaskGroup(of: (DockSessionTestScope, Result<DockLoadResult, DockLoadFailure>).self) { group in
            for scope in DockSessionTestScope.allCases {
                group.addTask {
                    do {
                        let result = try await loader.loadSessions(for: host, query: scope.query)
                        return (scope, .success(result))
                    } catch {
                        if let failure = error as? DockLoadFailure {
                            return (scope, .failure(failure))
                        }
                        return (scope, .failure(.error(error.localizedDescription)))
                    }
                }
            }
            var results: [(DockSessionTestScope, Result<DockLoadResult, DockLoadFailure>)] = []
            for await result in group {
                results.append(result)
            }
            return results.sorted { lhs, rhs in
                let lhsIndex = DockSessionTestScope.allCases.firstIndex(of: lhs.0) ?? Int.max
                let rhsIndex = DockSessionTestScope.allCases.firstIndex(of: rhs.0) ?? Int.max
                return lhsIndex < rhsIndex
            }
        }
    }

    private func deduplicated(_ summaries: [(DockSessionTestScope, SessionSummary)]) -> [SessionSummary] {
        var orderedIDs: [HostScopedThreadID] = []
        var summariesByID: [HostScopedThreadID: SessionSummary] = [:]
        for (scope, summary) in summaries {
            if summariesByID[summary.id] == nil {
                orderedIDs.append(summary.id)
                summariesByID[summary.id] = summary
                continue
            }
            guard let existing = summariesByID[summary.id] else {
                continue
            }
            if scope == .agents || existing.origin.kind == .unknown {
                summariesByID[summary.id] = summary
            }
        }
        return orderedIDs.compactMap { summariesByID[$0] }
    }

    private func streamSession(from summary: SessionSummary) -> DockStreamSessionDTO {
        DockStreamSessionDTO(
            id: "\(host.id)::\(summary.id.threadID)",
            hostID: host.id,
            threadID: summary.id.threadID,
            backendSessionID: summary.backendSessionID,
            title: summary.displayTitle,
            status: streamStatus(from: summary.status),
            lane: streamLane(from: summary.origin),
            kindLabel: streamKindLabel(from: summary.origin),
            repository: string(from: summary.repository),
            workingDirectory: string(from: summary.workingDirectory),
            branch: string(from: summary.branch),
            updatedAt: Int64(summary.lastActivity.timeIntervalSince1970),
            summary: string(from: summary.shortEventSummary),
            source: DockStreamSourceDTO(kind: streamSource(from: summary.origin))
        )
    }

    private func streamStatus(from status: SessionStatus) -> DockStreamSessionStatus {
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

    private func streamSource(from origin: SessionOrigin) -> DockStreamSourceKind {
        switch origin.kind {
        case .humanInteractive:
            return .human
        case .agentOrAutomation:
            return .automation
        case .unknown:
            return .unknown
        }
    }

    private func streamLane(from origin: SessionOrigin) -> DockStreamLane {
        switch origin.kind {
        case .humanInteractive:
            return .human
        case .agentOrAutomation:
            return .agent
        case .unknown:
            return .unknown
        }
    }

    private func streamKindLabel(from origin: SessionOrigin) -> String {
        switch origin.kind {
        case .humanInteractive:
            return "Human"
        case .agentOrAutomation:
            return "Agent"
        case .unknown:
            return "Unknown"
        }
    }

    private func string(from text: SessionSummaryText) -> String? {
        switch text {
        case .known(let value):
            return value
        case .unknown:
            return nil
        }
    }
}

struct FakeDockSessionLoader: DockSessionLoading {
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

actor SequencedDockSessionLoader: DockSessionLoading {
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

actor HostRoutedDockSessionLoader: DockSessionLoading {
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

actor DelayedHostRoutedDockSessionLoader: DockSessionLoading {
    private let delayedHostID: String
    private let results: [String: FakeMode]
    private var delayedContinuations: [CheckedContinuation<Void, Never>] = []

    init(delayedHostID: String, results: [String: FakeMode]) {
        self.delayedHostID = delayedHostID
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

    func loadSessions(
        for host: DockHostConfiguration,
        query: DockSessionQuery
    ) async throws -> DockLoadResult {
        if host.id == delayedHostID {
            await withCheckedContinuation { continuation in
                delayedContinuations.append(continuation)
            }
        }

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

actor RecordingDockSessionLoader: DockSessionLoading {
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

actor RecordingDockArchiver: DockSessionArchiving {
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

func sortedQueries(_ queries: [DockSessionQuery]) -> [DockSessionQuery] {
    queries.sorted { lhs, rhs in
        querySortKey(lhs) < querySortKey(rhs)
    }
}

func querySortKey(_ query: DockSessionQuery) -> String {
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

func makeSummary(
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

func dockStreamSnapshot(
    host: DockHostConfiguration,
    epoch: String,
    seq: Int64,
    sessions: [DockStreamSessionDTO],
    schemaVersion: Int? = CodexDockConstants.Dock.streamSchemaVersion,
    freshness: DockStreamFreshnessDTO = DockStreamFreshnessDTO(status: .fresh)
) -> DockStreamUpdateDTO {
    DockStreamUpdateDTO(
        kind: .snapshot,
        schemaVersion: schemaVersion,
        epoch: epoch,
        seq: seq,
        freshness: freshness,
        hosts: [DockStreamHostDTO(id: host.id, displayName: host.displayName, endpoint: host.endpoint.displayEndpoint)],
        sessions: sessions
    )
}

func dockStreamSession(
    host: DockHostConfiguration,
    threadID: String,
    title: String,
    status: DockStreamSessionStatus = .running,
    updatedAt: Int64
) -> DockStreamSessionDTO {
    DockStreamSessionDTO(
        id: "\(host.id)::\(threadID)",
        hostID: host.id,
        threadID: threadID,
        backendSessionID: "\(threadID)-session",
        title: title,
        status: status,
        lane: .human,
        kindLabel: "Human",
        repository: "codex-client",
        workingDirectory: "/Users/aelaguiz/workspace/codex-client",
        branch: "main",
        updatedAt: updatedAt,
        summary: "Summary for \(title)",
        source: DockStreamSourceDTO(kind: .human)
    )
}

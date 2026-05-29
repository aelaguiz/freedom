import Foundation
@testable import CodexDock

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

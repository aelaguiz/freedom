import Combine
import Foundation

public struct DockLoadResult: Equatable, Sendable {
    public let summaries: [SessionSummary]
    public let mappingFailures: [SessionSummaryMappingFailure]

    public init(
        summaries: [SessionSummary],
        mappingFailures: [SessionSummaryMappingFailure] = []
    ) {
        self.summaries = summaries
        self.mappingFailures = mappingFailures
    }
}

public struct DockSessionQuery: Equatable, Sendable {
    public let archived: Bool
    public let sourceKinds: [ThreadSourceKind]?

    public init(
        archived: Bool = false,
        sourceKinds: [ThreadSourceKind]? = nil
    ) {
        self.archived = archived
        self.sourceKinds = sourceKinds
    }

    public static let activeHuman = DockSessionQuery(archived: false, sourceKinds: nil)
    public static let archivedHuman = DockSessionQuery(archived: true, sourceKinds: nil)
    public static let activeAgents = DockSessionQuery(
        archived: false,
        sourceKinds: ThreadSourceKind.dockAgentScopeKinds
    )
}

public protocol DockSessionLoading: Sendable {
    func loadSessions(
        for host: DockHostConfiguration,
        query: DockSessionQuery
    ) async throws -> DockLoadResult
}

public protocol DockSessionArchiving: Sendable {
    func archiveThread(_ threadID: String, on host: DockHostConfiguration) async throws
    func unarchiveThread(_ threadID: String, on host: DockHostConfiguration) async throws
}

public enum DockLoadFailure: Error, Equatable, LocalizedError, Sendable {
    case offline(String)
    case error(String)

    public var errorDescription: String? {
        switch self {
        case let .offline(message), let .error(message):
            return message
        }
    }
}

public struct AppServerDockClient: DockSessionLoading, DockSessionArchiving {
    private let sessionPageLimit = 200

    public init() {}

    public func loadSessions(
        for host: DockHostConfiguration,
        query: DockSessionQuery
    ) async throws -> DockLoadResult {
        let startedAt = Date()
        let sourceKinds = query.sourceKinds?.map(\.rawValue).joined(separator: ",")
        DockLog.dock.info("dock client load started host_id=\(host.id, privacy: .public) endpoint=\(DockLog.endpoint(host.webSocketURL), privacy: .public) archived=\(query.archived, privacy: .public) source_kinds=\(DockLog.publicID(sourceKinds), privacy: .public)")
        return try await withClient(for: host) { client in
            let response = try await client.threadList(
                params: ThreadListParams(
                    limit: sessionPageLimit,
                    sortKey: .updatedAt,
                    sortDirection: .desc,
                    modelProviders: [],
                    sourceKinds: query.sourceKinds,
                    archived: query.archived
                ),
                timeout: .seconds(10)
            )
            let mapped = SessionSummaryMapper.map(response: response, hostID: host.id)
            DockLog.dock.info("dock client load finished host_id=\(host.id, privacy: .public) archived=\(query.archived, privacy: .public) rows=\(mapped.summaries.count, privacy: .public) mapping_failures=\(mapped.failures.count, privacy: .public) duration_ms=\(DockLog.milliseconds(since: startedAt), privacy: .public)")

            return DockLoadResult(
                summaries: mapped.summaries,
                mappingFailures: mapped.failures
            )
        }
    }

    public func archiveThread(_ threadID: String, on host: DockHostConfiguration) async throws {
        DockLog.dock.notice("dock archive started host_id=\(host.id, privacy: .public) thread_id=\(DockLog.publicID(threadID), privacy: .public)")
        _ = try await withClient(for: host) { client in
            try await client.threadArchive(
                params: ThreadArchiveParams(threadId: threadID),
                timeout: .seconds(10)
            )
        }
        DockLog.dock.notice("dock archive finished host_id=\(host.id, privacy: .public) thread_id=\(DockLog.publicID(threadID), privacy: .public)")
    }

    public func unarchiveThread(_ threadID: String, on host: DockHostConfiguration) async throws {
        DockLog.archive.notice("archive restore started host_id=\(host.id, privacy: .public) thread_id=\(DockLog.publicID(threadID), privacy: .public)")
        _ = try await withClient(for: host) { client in
            try await client.threadUnarchive(
                params: ThreadUnarchiveParams(threadId: threadID),
                timeout: .seconds(10)
            )
        }
        DockLog.archive.notice("archive restore finished host_id=\(host.id, privacy: .public) thread_id=\(DockLog.publicID(threadID), privacy: .public)")
    }

    private func withClient<Value>(
        for host: DockHostConfiguration,
        operation: (AppServerClient) async throws -> Value
    ) async throws -> Value {
        let client = AppServerClient(
            webSocketURL: host.webSocketURL,
            bearerToken: nil
        )

        do {
            _ = try await client.connectAndInitialize(
                params: .codexDock(version: "0.1.0"),
                timeout: .seconds(5)
            )
            let value = try await operation(client)
            await client.disconnect()
            return value
        } catch {
            await client.disconnect()
            throw mapLoadFailure(error)
        }
    }

    private func mapLoadFailure(_ error: Error) -> DockLoadFailure {
        if let failure = error as? DockLoadFailure {
            return failure
        }

        if let clientError = error as? AppServerClientError {
            switch clientError {
            case .disconnected, .notConnected, .requestTimedOut, .transport:
                return .offline(clientError.localizedDescription)
            case .duplicateRequestID,
                 .malformedMessage,
                 .requestCancelled,
                 .responseDecoding,
                 .server,
                 .unexpectedServerRequest,
                 .unmatchedResponse:
                return .error(clientError.localizedDescription)
            }
        }

        return .error(error.localizedDescription)
    }
}

public enum DockRowStatusKind: String, Equatable, Sendable, CaseIterable {
    case needsMe
    case running
    case idle
    case limited
    case failed
    case unknown

    public var label: String {
        switch self {
        case .needsMe:
            return "Needs me"
        case .running:
            return "Running"
        case .idle:
            return "Idle"
        case .limited:
            return "Limited"
        case .failed:
            return "Error"
        case .unknown:
            return "Unknown"
        }
    }
}

public enum DockRowRail: String, Codable, Equatable, Sendable, CaseIterable {
    case blue
    case green
    case orange
    case red
    case violet
}

public enum DockTabID: String, CaseIterable, Identifiable, Equatable, Sendable {
    case all
    case needsMe
    case running
    case limited
    case agents

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all:
            return "All"
        case .needsMe:
            return "Needs me"
        case .running:
            return "Running"
        case .limited:
            return "Limited"
        case .agents:
            return "Agents"
        }
    }

    public func includes(_ row: DockRowViewModel) -> Bool {
        switch self {
        case .all:
            return row.origin.kind == .humanInteractive
        case .needsMe:
            return row.origin.kind == .humanInteractive && row.status == .needsMe
        case .running:
            return row.origin.kind == .humanInteractive
                && (
                    row.status == .needsMe
                        || row.status == .running
                        || row.status == .idle
                        || row.status == .failed
                )
        case .limited:
            return row.origin.kind == .humanInteractive && row.status == .limited
        case .agents:
            return row.origin.kind != .humanInteractive
        }
    }
}

public struct DockTabViewModel: Equatable, Identifiable, Sendable {
    public let id: DockTabID
    public let title: String
    public let count: Int

    public var label: String {
        "\(title) \(count)"
    }

    public init(id: DockTabID, count: Int) {
        self.id = id
        self.title = id.title
        self.count = count
    }
}

public struct DockRowViewModel: Equatable, Identifiable, Sendable {
    public let id: HostScopedThreadID
    public let backendSessionID: String
    public let title: String
    public let repository: String
    public let branch: String
    public let status: DockRowStatusKind
    public let lastActivity: String
    public let lastActivityDate: Date
    public let summary: String
    public let rail: DockRowRail
    public let label: String?
    public let origin: SessionOrigin

    public var metadataKey: LocalThreadMetadataKey {
        LocalThreadMetadataKey(
            hostID: id.hostID,
            backendSessionID: backendSessionID,
            threadID: id.threadID
        )
    }
}

public struct DockSectionViewModel: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let rows: [DockRowViewModel]
}

public struct DockHostViewModel: Equatable, Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public let endpoint: String

    public init(host: DockHostConfiguration) {
        self.id = host.id
        self.displayName = host.displayName
        self.endpoint = host.endpoint.displayEndpoint
    }
}

public struct DockSnapshot: Equatable, Sendable {
    public let host: DockHostViewModel
    public let hosts: [DockHostViewModel]
    public let hostStates: [DockHostStateViewModel]
    public let sections: [DockSectionViewModel]
    public let tabs: [DockTabViewModel]
    public let scopeLoadFailures: [DockScopeLoadFailureViewModel]
    public let scopeConflicts: [DockScopeConflictViewModel]
    public let mappingFailures: [SessionSummaryMappingFailure]

    public var rowCount: Int {
        sections.reduce(0) { count, section in
            count + section.rows.count
        }
    }

    public func sections(for tab: DockTabID) -> [DockSectionViewModel] {
        sections.compactMap { section in
            let rows = section.rows.filter(tab.includes)
            guard !rows.isEmpty else {
                return nil
            }
            return DockSectionViewModel(id: section.id, title: section.title, rows: rows)
        }
    }
}

public enum DockHostLoadStatus: Equatable, Sendable {
    case loaded(rowCount: Int)
    case partial(rowCount: Int, message: String)
    case empty
    case offline(String)
    case error(String)

    public var subtitle: String {
        switch self {
        case .loaded(let rowCount):
            return "\(rowCount) sessions"
        case .partial(let rowCount, let message):
            return "\(rowCount) sessions, partial: \(message)"
        case .empty:
            return "Online, no sessions"
        case .offline:
            return "Offline"
        case .error:
            return "Error"
        }
    }

    public var isUnavailable: Bool {
        switch self {
        case .offline, .error:
            return true
        case .loaded, .partial, .empty:
            return false
        }
    }

    public var unavailableMessage: String? {
        switch self {
        case .offline(let message), .error(let message):
            return message
        case .loaded, .partial, .empty:
            return nil
        }
    }
}

public struct DockHostStateViewModel: Equatable, Identifiable, Sendable {
    public let id: String
    public let host: DockHostViewModel
    public let status: DockHostLoadStatus

    public init(host: DockHostViewModel, status: DockHostLoadStatus) {
        self.id = host.id
        self.host = host
        self.status = status
    }
}

public enum DockSessionScope: String, CaseIterable, Hashable, Sendable {
    case human
    case agents

    public var label: String {
        switch self {
        case .human:
            return "Dock"
        case .agents:
            return "Agents"
        }
    }

    public var query: DockSessionQuery {
        switch self {
        case .human:
            return .activeHuman
        case .agents:
            return .activeAgents
        }
    }
}

public struct DockScopeLoadFailureViewModel: Equatable, Identifiable, Sendable {
    public let id: String
    public let host: DockHostViewModel
    public let scope: DockSessionScope
    public let message: String

    public init(host: DockHostViewModel, scope: DockSessionScope, message: String) {
        self.id = "\(host.id)::\(scope.rawValue)"
        self.host = host
        self.scope = scope
        self.message = message
    }
}

public struct DockScopeConflictViewModel: Equatable, Identifiable, Sendable {
    public let id: String
    public let threadID: HostScopedThreadID
    public let backendThreadID: String
    public let winningScope: DockSessionScope

    public init(
        threadID: HostScopedThreadID,
        backendThreadID: String,
        winningScope: DockSessionScope
    ) {
        self.id = "\(threadID.hostID)::\(threadID.threadID)"
        self.threadID = threadID
        self.backendThreadID = backendThreadID
        self.winningScope = winningScope
    }
}

public enum DockStoreState: Equatable, Sendable {
    case configurationError(String)
    case idle(DockHostViewModel)
    case loading(DockHostViewModel)
    case loaded(DockSnapshot)
    case offline(DockHostViewModel, String)
    case error(DockHostViewModel, String)
}

@MainActor
public final class DockStore: ObservableObject {
    public static let defaultAutoRefreshInterval: Duration = .seconds(5)

    @Published public private(set) var state: DockStoreState
    @Published public private(set) var actionError: String?

    private var hosts: [DockHostConfiguration]
    private let loader: any DockSessionLoading
    private let archiver: any DockSessionArchiving
    private let metadataStore: any LocalThreadMetadataStoring
    private let now: @Sendable () -> Date
    private var isLoading = false
    private var localMetadata: [LocalThreadMetadataKey: LocalThreadMetadata] = [:]
    private weak var connectivityReporter: (any AppConnectivityReporting)?

    public var hostConfiguration: DockHostConfiguration? {
        hosts.first
    }

    public func hostConfiguration(for hostID: String) -> DockHostConfiguration? {
        hosts.first { $0.id == hostID }
    }

    public init(
        host: DockHostConfiguration,
        loader: any DockSessionLoading = AppServerDockClient(),
        archiver: any DockSessionArchiving = AppServerDockClient(),
        metadataStore: any LocalThreadMetadataStoring = FileLocalThreadMetadataStore(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.hosts = [host]
        self.loader = loader
        self.archiver = archiver
        self.metadataStore = metadataStore
        self.now = now
        self.state = .idle(DockHostViewModel(host: host))
    }

    public init(
        registry: HostRegistry,
        loader: any DockSessionLoading = AppServerDockClient(),
        archiver: any DockSessionArchiving = AppServerDockClient(),
        metadataStore: any LocalThreadMetadataStoring = FileLocalThreadMetadataStore(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.hosts = registry.hosts
        self.loader = loader
        self.archiver = archiver
        self.metadataStore = metadataStore
        self.now = now
        self.state = .idle(DockHostViewModel(host: registry.hosts[0]))
    }

    public init(
        configurationError error: Error,
        loader: any DockSessionLoading = AppServerDockClient(),
        archiver: any DockSessionArchiving = AppServerDockClient(),
        metadataStore: any LocalThreadMetadataStoring = FileLocalThreadMetadataStore(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.hosts = []
        self.loader = loader
        self.archiver = archiver
        self.metadataStore = metadataStore
        self.now = now
        self.state = .configurationError(error.localizedDescription)
    }

    public func updateRegistry(_ registry: HostRegistry) async {
        hosts = registry.hosts
        actionError = nil
        state = .idle(DockHostViewModel(host: registry.hosts[0]))
        connectivityReporter?.reportDockState(state)
        await reload(showLoading: true)
    }

    public func setConnectivityReporter(_ reporter: (any AppConnectivityReporting)?) {
        connectivityReporter = reporter
        reporter?.reportDockState(state)
    }

    public func load() async {
        await reload(showLoading: true)
    }

    public func refresh() async {
        await reload(showLoading: false)
    }

    public func setLabel(_ label: String?, for row: DockRowViewModel) async {
        var metadata = localMetadata[row.metadataKey] ?? LocalThreadMetadata()
        metadata.label = label
        await save(metadata: metadata, for: row.metadataKey)
    }

    public func setRail(_ rail: DockRowRail?, for row: DockRowViewModel) async {
        var metadata = localMetadata[row.metadataKey] ?? LocalThreadMetadata()
        metadata.rail = rail
        await save(metadata: metadata, for: row.metadataKey)
    }

    @discardableResult
    public func archive(_ row: DockRowViewModel) async -> Bool {
        guard let host = hostConfiguration(for: row.id.hostID) else {
            DockLog.dock.error("dock archive skipped missing host_id=\(row.id.hostID, privacy: .public) thread_id=\(DockLog.publicID(row.id.threadID), privacy: .public)")
            actionError = "Host \(row.id.hostID) is no longer configured."
            return false
        }

        do {
            DockLog.dock.notice("dock archive action started host_id=\(host.id, privacy: .public) thread_id=\(DockLog.publicID(row.id.threadID), privacy: .public)")
            try await archiver.archiveThread(row.id.threadID, on: host)
            actionError = nil
            await refresh()
            DockLog.dock.notice("dock archive action finished host_id=\(host.id, privacy: .public) thread_id=\(DockLog.publicID(row.id.threadID), privacy: .public)")
            return true
        } catch {
            DockLog.dock.error("dock archive action failed host_id=\(host.id, privacy: .public) thread_id=\(DockLog.publicID(row.id.threadID), privacy: .public) error=\(DockLog.errorSummary(error), privacy: .public)")
            actionError = error.localizedDescription
            return false
        }
    }

    private func reload(showLoading: Bool) async {
        guard !hosts.isEmpty else {
            DockLog.dock.warning("dock reload skipped reason=no_hosts")
            return
        }
        guard !isLoading else {
            DockLog.dock.debug("dock reload skipped reason=already_loading")
            return
        }

        let startedAt = Date()
        let signpostState = DockSignpost.dock.beginInterval("dock.reload")
        DockLog.dock.notice("dock reload started hosts=\(self.hosts.count, privacy: .public) show_loading=\(showLoading, privacy: .public)")
        isLoading = true
        defer {
            DockSignpost.dock.endInterval("dock.reload", signpostState)
            isLoading = false
        }

        let hostViewModel = DockHostViewModel(host: hosts[0])
        if showLoading {
            state = .loading(hostViewModel)
            connectivityReporter?.reportDockState(state)
        }

        do {
            localMetadata = try await metadataStore.load()
            DockLog.persistence.debug("dock metadata loaded entries=\(self.localMetadata.count, privacy: .public)")
        } catch {
            localMetadata = [:]
            DockLog.persistence.warning("dock metadata load failed error=\(DockLog.errorSummary(error), privacy: .public)")
        }

        let results = await loadAllHosts()
        let snapshot = makeSnapshot(results: results)

        if hosts.count == 1, let first = results.first {
            if let failure = first.completeFailure {
                switch failure {
                case .offline(let message):
                    state = .offline(hostViewModel, message)
                case .error(let message):
                    state = .error(hostViewModel, message)
                }
            } else {
                state = .loaded(snapshot)
            }
        } else {
            state = .loaded(snapshot)
        }
        connectivityReporter?.reportDockState(state)
        DockLog.dock.notice("dock reload finished hosts=\(self.hosts.count, privacy: .public) rows=\(snapshot.rowCount, privacy: .public) mapping_failures=\(snapshot.mappingFailures.count, privacy: .public) scope_failures=\(snapshot.scopeLoadFailures.count, privacy: .public) conflicts=\(snapshot.scopeConflicts.count, privacy: .public) duration_ms=\(DockLog.milliseconds(since: startedAt), privacy: .public)")
    }

    private struct ScopedHostLoadOutcome: Sendable {
        let scope: DockSessionScope
        let result: Result<DockLoadResult, DockLoadFailure>
    }

    private struct ScopedSessionSummary: Sendable {
        let scope: DockSessionScope
        let summary: SessionSummary
    }

    private struct DeduplicatedSummaries: Sendable {
        let summaries: [SessionSummary]
        let conflicts: [DockScopeConflictViewModel]
    }

    private struct HostLoadOutcome: Sendable {
        let host: DockHostConfiguration
        let scopedResults: [ScopedHostLoadOutcome]

        var completeFailure: DockLoadFailure? {
            let failures = scopedResults.compactMap { outcome -> DockLoadFailure? in
                if case .failure(let failure) = outcome.result {
                    return failure
                }
                return nil
            }
            guard !scopedResults.isEmpty, failures.count == scopedResults.count else {
                return nil
            }
            if let error = failures.first(where: { failure in
                if case .error = failure {
                    return true
                }
                return false
            }) {
                return error
            }
            return failures[0]
        }
    }

    private func loadAllHosts() async -> [HostLoadOutcome] {
        await withTaskGroup(of: HostLoadOutcome.self) { group in
            for host in hosts {
                group.addTask { [loader] in
                    let scopedResults = await Self.loadActiveScopes(loader: loader, host: host)
                    return HostLoadOutcome(host: host, scopedResults: scopedResults)
                }
            }

            var outcomes: [HostLoadOutcome] = []
            for await outcome in group {
                outcomes.append(outcome)
            }
            return outcomes.sorted { lhs, rhs in
                hostIndex(lhs.host.id) < hostIndex(rhs.host.id)
            }
        }
    }

    private nonisolated static func loadActiveScopes(
        loader: any DockSessionLoading,
        host: DockHostConfiguration
    ) async -> [ScopedHostLoadOutcome] {
        await withTaskGroup(of: ScopedHostLoadOutcome.self) { group in
            for scope in DockSessionScope.allCases {
                group.addTask { [loader] in
                    ScopedHostLoadOutcome(
                        scope: scope,
                        result: await Self.loadScope(
                            loader: loader,
                            host: host,
                            query: scope.query
                        )
                    )
                }
            }

            var outcomes: [ScopedHostLoadOutcome] = []
            for await outcome in group {
                outcomes.append(outcome)
            }
            return outcomes.sorted { lhs, rhs in
                Self.scopeIndex(lhs.scope) < Self.scopeIndex(rhs.scope)
            }
        }
    }

    private nonisolated static func loadScope(
        loader: any DockSessionLoading,
        host: DockHostConfiguration,
        query: DockSessionQuery
    ) async -> Result<DockLoadResult, DockLoadFailure> {
        let startedAt = Date()
        let scope = DockSessionScope.allCases.first { $0.query == query }?.rawValue ?? "custom"
        DockLog.dock.debug("dock scope load started host_id=\(host.id, privacy: .public) scope=\(scope, privacy: .public)")
        do {
            let result = try await loader.loadSessions(for: host, query: query)
            DockLog.dock.debug("dock scope load finished host_id=\(host.id, privacy: .public) scope=\(scope, privacy: .public) rows=\(result.summaries.count, privacy: .public) mapping_failures=\(result.mappingFailures.count, privacy: .public) duration_ms=\(DockLog.milliseconds(since: startedAt), privacy: .public)")
            return .success(result)
        } catch {
            DockLog.dock.warning("dock scope load failed host_id=\(host.id, privacy: .public) scope=\(scope, privacy: .public) duration_ms=\(DockLog.milliseconds(since: startedAt), privacy: .public) error=\(DockLog.errorSummary(error), privacy: .public)")
            return .failure(mapLoadFailure(error))
        }
    }

    private nonisolated static func mapLoadFailure(_ error: Error) -> DockLoadFailure {
        if let failure = error as? DockLoadFailure {
            return failure
        }
        return .error(error.localizedDescription)
    }

    private func makeSnapshot(results: [HostLoadOutcome]) -> DockSnapshot {
        var summaries: [SessionSummary] = []
        var mappingFailures: [SessionSummaryMappingFailure] = []
        var hostStates: [DockHostStateViewModel] = []
        var scopeLoadFailures: [DockScopeLoadFailureViewModel] = []
        var scopeConflicts: [DockScopeConflictViewModel] = []

        for outcome in results {
            let host = DockHostViewModel(host: outcome.host)
            let hostSummaries = successfulScopedSummaries(from: outcome)
            let deduplicated = deduplicated(hostSummaries)
            let hostDedupedSummaries = deduplicated.summaries
            summaries.append(contentsOf: hostDedupedSummaries)
            scopeConflicts.append(contentsOf: deduplicated.conflicts)
            mappingFailures.append(contentsOf: successfulMappingFailures(from: outcome))

            for scopedOutcome in outcome.scopedResults {
                if case .failure(let failure) = scopedOutcome.result {
                    scopeLoadFailures.append(
                        DockScopeLoadFailureViewModel(
                            host: host,
                            scope: scopedOutcome.scope,
                            message: failure.localizedDescription
                        )
                    )
                }
            }

            if let failure = outcome.completeFailure {
                switch failure {
                case .offline(let message):
                    hostStates.append(DockHostStateViewModel(host: host, status: .offline(message)))
                case .error(let message):
                    hostStates.append(DockHostStateViewModel(host: host, status: .error(message)))
                }
            } else if scopeLoadFailures.contains(where: { $0.host.id == host.id }) {
                let message = scopeLoadFailures
                    .filter { $0.host.id == host.id }
                    .map { "\($0.scope.label): \($0.message)" }
                    .joined(separator: "; ")
                hostStates.append(
                    DockHostStateViewModel(
                        host: host,
                        status: .partial(rowCount: hostDedupedSummaries.count, message: message)
                    )
                )
            } else {
                hostStates.append(
                    DockHostStateViewModel(
                        host: host,
                        status: hostDedupedSummaries.isEmpty
                            ? .empty
                            : .loaded(rowCount: hostDedupedSummaries.count)
                    )
                )
            }
        }

        let sections = SessionRowProjector(
            hosts: hosts,
            localMetadata: localMetadata,
            now: now
        ).sections(from: summaries)
        let allRows = sections.flatMap(\.rows)

        return DockSnapshot(
            host: DockHostViewModel(host: hosts[0]),
            hosts: hosts.map(DockHostViewModel.init),
            hostStates: hostStates,
            sections: sections,
            tabs: DockTabID.allCases.map { tab in
                DockTabViewModel(id: tab, count: allRows.filter(tab.includes).count)
            },
            scopeLoadFailures: scopeLoadFailures,
            scopeConflicts: scopeConflicts,
            mappingFailures: mappingFailures
        )
    }

    private func successfulScopedSummaries(from outcome: HostLoadOutcome) -> [ScopedSessionSummary] {
        var summaries: [ScopedSessionSummary] = []
        for scopedOutcome in outcome.scopedResults {
            if case .success(let result) = scopedOutcome.result {
                summaries.append(
                    contentsOf: result.summaries.map { summary in
                        ScopedSessionSummary(scope: scopedOutcome.scope, summary: summary)
                    }
                )
            }
        }
        return summaries
    }

    private func successfulMappingFailures(from outcome: HostLoadOutcome) -> [SessionSummaryMappingFailure] {
        var failures: [SessionSummaryMappingFailure] = []
        for scopedOutcome in outcome.scopedResults {
            if case .success(let result) = scopedOutcome.result {
                failures.append(contentsOf: result.mappingFailures)
            }
        }
        return failures
    }

    private func deduplicated(_ summaries: [ScopedSessionSummary]) -> DeduplicatedSummaries {
        var orderedIDs: [HostScopedThreadID] = []
        var summariesByID: [HostScopedThreadID: SessionSummary] = [:]
        var scopesByID: [HostScopedThreadID: Set<DockSessionScope>] = [:]
        var conflictIDs: Set<HostScopedThreadID> = []
        var conflicts: [DockScopeConflictViewModel] = []

        for scopedSummary in summaries {
            let summary = scopedSummary.summary
            if summariesByID[summary.id] == nil {
                orderedIDs.append(summary.id)
                summariesByID[summary.id] = summary
                scopesByID[summary.id] = [scopedSummary.scope]
                continue
            }

            guard let existing = summariesByID[summary.id] else {
                continue
            }
            var scopes = scopesByID[summary.id] ?? []
            if !scopes.contains(scopedSummary.scope), !conflictIDs.contains(summary.id) {
                conflictIDs.insert(summary.id)
                let winningScope = preferredScope(candidate: summary, existing: existing)
                conflicts.append(
                    DockScopeConflictViewModel(
                        threadID: summary.id,
                        backendThreadID: summary.backendThreadID,
                        winningScope: winningScope
                    )
                )
            }
            scopes.insert(scopedSummary.scope)
            scopesByID[summary.id] = scopes

            if shouldPrefer(summary, over: existing) {
                summariesByID[summary.id] = summary
            }
        }

        return DeduplicatedSummaries(
            summaries: orderedIDs.compactMap { summariesByID[$0] },
            conflicts: conflicts
        )
    }

    private func shouldPrefer(_ candidate: SessionSummary, over existing: SessionSummary) -> Bool {
        if existing.origin.kind == .humanInteractive,
           candidate.origin.kind != .humanInteractive {
            return true
        }
        if existing.origin.kind == .unknown,
           candidate.origin.kind == .agentOrAutomation {
            return true
        }
        return false
    }

    private func preferredScope(candidate: SessionSummary, existing: SessionSummary) -> DockSessionScope {
        shouldPrefer(candidate, over: existing)
            ? scope(for: candidate.origin)
            : scope(for: existing.origin)
    }

    private func scope(for origin: SessionOrigin) -> DockSessionScope {
        origin.kind == .humanInteractive ? .human : .agents
    }

    private func hostIndex(_ hostID: String) -> Int {
        hosts.firstIndex { $0.id == hostID } ?? Int.max
    }

    private nonisolated static func scopeIndex(_ scope: DockSessionScope) -> Int {
        DockSessionScope.allCases.firstIndex(of: scope) ?? Int.max
    }

    private func save(metadata: LocalThreadMetadata, for key: LocalThreadMetadataKey) async {
        do {
            DockLog.persistence.debug("dock metadata save started host_id=\(key.hostID, privacy: .public) thread_id=\(DockLog.publicID(key.threadID), privacy: .public) has_metadata=\(!metadata.isEmpty, privacy: .public)")
            localMetadata = try await metadataStore.save(metadata.isEmpty ? nil : metadata, for: key)
            await refresh()
            DockLog.persistence.debug("dock metadata save finished host_id=\(key.hostID, privacy: .public) thread_id=\(DockLog.publicID(key.threadID), privacy: .public) entries=\(self.localMetadata.count, privacy: .public)")
        } catch {
            DockLog.persistence.error("dock metadata save failed host_id=\(key.hostID, privacy: .public) thread_id=\(DockLog.publicID(key.threadID), privacy: .public) error=\(DockLog.errorSummary(error), privacy: .public)")
            state = .error(DockHostViewModel(host: hosts[0]), error.localizedDescription)
        }
    }
}

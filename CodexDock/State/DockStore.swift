import Combine
import Foundation

public enum DockRowStatusKind: String, Equatable, Sendable, CaseIterable {
    case running
    case idle
    case notLoaded
    case error
    case unknown

    public var label: String {
        switch self {
        case .running:
            return "Running"
        case .idle:
            return "Idle"
        case .notLoaded:
            return "Not loaded"
        case .error:
            return "Error"
        case .unknown:
            return "Unknown"
        }
    }
}

public enum DockLensID: String, CaseIterable, Identifiable, Equatable, Sendable {
    case newest
    case host
    case branch

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .newest:
            return "Newest"
        case .host:
            return "Host"
        case .branch:
            return "Branch"
        }
    }
}

public enum DockSortOrder: String, CaseIterable, Identifiable, Equatable, Sendable {
    case newestActivity

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .newestActivity:
            return "Newest activity"
        }
    }
}

public enum DockSourceFilter: String, CaseIterable, Identifiable, Equatable, Sendable {
    case any
    case human
    case agents
    case unknown

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .any:
            return "Any"
        case .human:
            return "Human"
        case .agents:
            return "Agents"
        case .unknown:
            return "Unknown"
        }
    }

    public func includes(_ origin: SessionOrigin) -> Bool {
        switch self {
        case .any:
            return true
        case .human:
            return origin.kind == .humanInteractive
        case .agents:
            return origin.kind == .agentOrAutomation
        case .unknown:
            return origin.kind == .unknown
        }
    }
}

extension SessionOrigin {
    var automationKind: String {
        switch kind {
        case .humanInteractive:
            return "human"
        case .agentOrAutomation:
            return "automation"
        case .unknown:
            return "unknown"
        }
    }
}

public struct DockFilterState: Equatable, Sendable {
    public var selectedHostIDs: Set<String>
    public var selectedBranches: Set<String>
    public var statusKinds: Set<DockRowStatusKind>
    public var repositoryQuery: String
    public var selectedRepositories: Set<String>
    public var source: DockSourceFilter
    public var showsIdle: Bool
    public var sortOrder: DockSortOrder

    public init(
        selectedHostIDs: Set<String> = [],
        selectedBranches: Set<String> = [],
        statusKinds: Set<DockRowStatusKind> = Set(DockRowStatusKind.allCases),
        repositoryQuery: String = "",
        selectedRepositories: Set<String> = [],
        source: DockSourceFilter = .any,
        showsIdle: Bool = false,
        sortOrder: DockSortOrder = .newestActivity
    ) {
        self.selectedHostIDs = selectedHostIDs
        self.selectedBranches = selectedBranches
        self.statusKinds = statusKinds
        self.repositoryQuery = repositoryQuery
        self.selectedRepositories = selectedRepositories
        self.source = source
        self.showsIdle = showsIdle
        self.sortOrder = sortOrder
    }

    // Dock V1 deliberately defaults to all loaded source scopes and no archive facet.
    public static let `default` = DockFilterState()

    public var activeFilterCount: Int {
        var count = 0
        if !selectedHostIDs.isEmpty { count += 1 }
        if !selectedBranches.isEmpty { count += 1 }
        if statusKinds != Set(DockRowStatusKind.allCases) { count += 1 }
        if !repositoryQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { count += 1 }
        if !selectedRepositories.isEmpty { count += 1 }
        if source != .any { count += 1 }
        if showsIdle { count += 1 }
        return count
    }

    public var isDefault: Bool {
        self == .default
    }
}

public enum DockRowRail: String, Codable, Equatable, Sendable, CaseIterable {
    case blue
    case green
    case orange
    case red
    case violet
}

public struct DockRowViewModel: Equatable, Identifiable, Sendable {
    public let id: HostScopedThreadID
    public let backendSessionID: String
    public let title: String
    public let hostDisplayName: String
    public let hostEndpoint: String
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

public enum DockProjectionGroupKind: String, Equatable, Sendable {
    case host
    case branch
}

public struct DockProjectionGroupViewModel: Equatable, Identifiable, Sendable {
    public let id: String
    public let kind: DockProjectionGroupKind
    public let title: String
    public let subtitle: String
    public let rows: [DockRowViewModel]
    public let hostIDs: [String]
    public let newestActivityDate: Date?
    public let runningCount: Int
    public let hiddenIdleCount: Int
    public let isUnavailable: Bool
    public let unavailableMessage: String?

    public var count: Int { rows.count }
}

public struct DockProjectionHiddenCounts: Equatable, Sendable {
    public let idle: Int
}

public struct DockProjectionFacets: Equatable, Sendable {
    public let hosts: [DockHostViewModel]
    public let branches: [String]
    public let statuses: [DockRowStatusKind]
    public let repositories: [String]
    public let sources: [DockSourceFilter]
}

public enum DockProjectionEmptyReason: Equatable, Sendable {
    case noData
    case noSearchMatches
    case noFilterMatches
    case idleHidden
    case notLoadedOnly
    case hostUnavailable

    public var title: String {
        switch self {
        case .noData:
            return "No sessions"
        case .noSearchMatches:
            return "No matches"
        case .noFilterMatches:
            return "No filtered sessions"
        case .idleHidden:
            return "Idle hidden"
        case .notLoadedOnly:
            return "No not-loaded sessions"
        case .hostUnavailable:
            return "Host unavailable"
        }
    }

    public var message: String {
        switch self {
        case .noData:
            return "No sessions are loaded on reachable hosts."
        case .noSearchMatches:
            return "No sessions match this search."
        case .noFilterMatches:
            return "No sessions match the active filters."
        case .idleHidden:
            return "Show idle sessions to include matching idle threads."
        case .notLoadedOnly:
            return "These sessions exist in the list, but Dock does not have loaded thread detail for them."
        case .hostUnavailable:
            return "The selected host is unavailable."
        }
    }
}

public struct DockProjectionSummary: Equatable, Sendable {
    public let text: String
    public let activeFilterCount: Int
    public let resultCount: Int
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
    public let rows: [DockRowViewModel]
    public let scopeLoadFailures: [DockScopeLoadFailureViewModel]
    public let scopeConflicts: [DockScopeConflictViewModel]
    public let mappingFailures: [SessionSummaryMappingFailure]
    public let isPartial: Bool

    public var rowCount: Int {
        rows.count
    }

    public init(
        host: DockHostViewModel,
        hosts: [DockHostViewModel],
        hostStates: [DockHostStateViewModel],
        rows: [DockRowViewModel],
        scopeLoadFailures: [DockScopeLoadFailureViewModel],
        scopeConflicts: [DockScopeConflictViewModel],
        mappingFailures: [SessionSummaryMappingFailure],
        isPartial: Bool = false
    ) {
        self.host = host
        self.hosts = hosts
        self.hostStates = hostStates
        self.rows = rows
        self.scopeLoadFailures = scopeLoadFailures
        self.scopeConflicts = scopeConflicts
        self.mappingFailures = mappingFailures
        self.isPartial = isPartial
    }
}

public enum DockHostLoadStatus: Equatable, Sendable {
    case checking
    case loaded(rowCount: Int)
    case partial(rowCount: Int, message: String)
    case empty
    case offline(String)
    case error(String)

    public var subtitle: String {
        switch self {
        case .checking:
            return "Checking"
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
        case .checking, .loaded, .partial, .empty:
            return false
        }
    }

    public var unavailableMessage: String? {
        switch self {
        case .offline(let message), .error(let message):
            return message
        case .checking, .loaded, .partial, .empty:
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
    case idle([DockHostViewModel])
    case loading([DockHostViewModel])
    case loaded(DockSnapshot)
    case offline(DockHostViewModel, String)
    case error(DockHostViewModel, String)
}

@MainActor
public final class DockStore: ObservableObject {
    public static let defaultAutoRefreshInterval: Duration = CodexDockConstants.Dock.autoRefreshInterval

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
        self.state = .idle([DockHostViewModel(host: host)])
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
        self.state = .idle(registry.hosts.map(DockHostViewModel.init))
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
        state = .idle(registry.hosts.map(DockHostViewModel.init))
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

        let hostViewModels = hosts.map(DockHostViewModel.init)
        let primaryHostViewModel = hostViewModels[0]
        if showLoading {
            state = .loading(hostViewModels)
            connectivityReporter?.reportDockState(state)
        }

        do {
            localMetadata = try await metadataStore.load()
            DockLog.persistence.debug("dock metadata loaded entries=\(self.localMetadata.count, privacy: .public)")
        } catch {
            localMetadata = [:]
            DockLog.persistence.warning("dock metadata load failed error=\(DockLog.errorSummary(error), privacy: .public)")
        }

        let results = await loadAllHostsPublishingPartial()
        let snapshot = makeSnapshot(results: results)

        if hosts.count == 1, let first = results.first {
            if let failure = first.completeFailure {
                switch failure {
                case .offline(let message):
                    state = .offline(primaryHostViewModel, message)
                case .error(let message):
                    state = .error(primaryHostViewModel, message)
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

    private func loadAllHostsPublishingPartial() async -> [HostLoadOutcome] {
        await withTaskGroup(of: HostLoadOutcome.self) { group in
            for host in hosts {
                group.addTask { [loader] in
                    let scopedResults = await Self.loadActiveScopes(loader: loader, host: host)
                    return HostLoadOutcome(host: host, scopedResults: scopedResults)
                }
            }

            var outcomes: [HostLoadOutcome] = []
            var checkingHostIDs = Set(hosts.map(\.id))
            for await outcome in group {
                outcomes.append(outcome)
                checkingHostIDs.remove(outcome.host.id)
                outcomes.sort { lhs, rhs in
                    hostIndex(lhs.host.id) < hostIndex(rhs.host.id)
                }
                if !checkingHostIDs.isEmpty {
                    state = .loaded(makeSnapshot(results: outcomes, checkingHostIDs: checkingHostIDs))
                    connectivityReporter?.reportDockState(state)
                }
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

    private func makeSnapshot(
        results: [HostLoadOutcome],
        checkingHostIDs: Set<String> = []
    ) -> DockSnapshot {
        var summaries: [SessionSummary] = []
        var mappingFailures: [SessionSummaryMappingFailure] = []
        var hostStatesByID: [String: DockHostStateViewModel] = [:]
        var scopeLoadFailures: [DockScopeLoadFailureViewModel] = []
        var scopeConflicts: [DockScopeConflictViewModel] = []

        for outcome in results {
            let host = DockHostViewModel(host: outcome.host)
            let hostSummaries = successfulScopedSummaries(from: outcome)
            let deduplicated = deduplicated(hostSummaries)
            let hostDedupedSummaries = deduplicated.summaries
            let overlayMessages = successfulLiveOverlayMessages(from: outcome)
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
                    hostStatesByID[host.id] = DockHostStateViewModel(host: host, status: .offline(message))
                case .error(let message):
                    hostStatesByID[host.id] = DockHostStateViewModel(host: host, status: .error(message))
                }
            } else if scopeLoadFailures.contains(where: { $0.host.id == host.id }) {
                var messages = scopeLoadFailures
                    .filter { $0.host.id == host.id }
                    .map { "\($0.scope.label): \($0.message)" }
                messages.append(contentsOf: overlayMessages)
                hostStatesByID[host.id] =
                    DockHostStateViewModel(
                        host: host,
                        status: .partial(rowCount: hostDedupedSummaries.count, message: messages.joined(separator: "; "))
                    )
            } else if !overlayMessages.isEmpty {
                hostStatesByID[host.id] =
                    DockHostStateViewModel(
                        host: host,
                        status: .partial(
                            rowCount: hostDedupedSummaries.count,
                            message: overlayMessages.joined(separator: "; ")
                        )
                    )
            } else {
                hostStatesByID[host.id] =
                    DockHostStateViewModel(
                        host: host,
                        status: hostDedupedSummaries.isEmpty
                            ? .empty
                            : .loaded(rowCount: hostDedupedSummaries.count)
                    )
            }
        }

        for host in hosts where checkingHostIDs.contains(host.id) {
            let hostViewModel = DockHostViewModel(host: host)
            hostStatesByID[host.id] = DockHostStateViewModel(host: hostViewModel, status: .checking)
        }

        let projector = SessionRowProjector(
            hosts: hosts,
            localMetadata: localMetadata,
            now: now
        )
        let rows = projector.rows(from: summaries)

        return DockSnapshot(
            host: DockHostViewModel(host: hosts[0]),
            hosts: hosts.map(DockHostViewModel.init),
            hostStates: hosts.compactMap { hostStatesByID[$0.id] },
            rows: rows,
            scopeLoadFailures: scopeLoadFailures,
            scopeConflicts: scopeConflicts,
            mappingFailures: mappingFailures,
            isPartial: !checkingHostIDs.isEmpty
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

    private func successfulLiveOverlayMessages(from outcome: HostLoadOutcome) -> [String] {
        var messages: [String] = []
        for scopedOutcome in outcome.scopedResults {
            guard case .success(let result) = scopedOutcome.result,
                  let message = result.liveOverlay?.degradedMessage,
                  !messages.contains(message) else {
                continue
            }
            messages.append(message)
        }
        return messages
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

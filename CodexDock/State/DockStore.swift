import Combine
import Foundation

public enum DockRowStatusKind: String, Equatable, Sendable, CaseIterable {
    case running
    case needsInput
    case needsApproval
    case idle
    case error
    case dormant
    case unknown

    public var label: String {
        switch self {
        case .running:
            return "Running"
        case .needsInput:
            return "Needs input"
        case .needsApproval:
            return "Needs approval"
        case .idle:
            return "Idle"
        case .error:
            return "Error"
        case .dormant:
            return "Not loaded"
        case .unknown:
            return "Unknown"
        }
    }

    public var visibleBadgeLabel: String? {
        switch self {
        case .running, .needsInput, .needsApproval, .error:
            return label
        case .idle, .dormant, .unknown:
            return nil
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
        mappingFailures: [SessionSummaryMappingFailure],
        isPartial: Bool = false
    ) {
        self.host = host
        self.hosts = hosts
        self.hostStates = hostStates
        self.rows = rows
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

    public var isPartial: Bool {
        if case .partial = self {
            return true
        }
        return false
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
    private let streamClient: any DockStreamConnecting
    private let archiver: any DockSessionArchiving
    private let metadataStore: any LocalThreadMetadataStoring
    private let now: @Sendable () -> Date
    private let streamReconnectDelay: Duration
    private var sessionTable = DockSessionTable()
    private var streamConnections: [String: any DockStreamConnection] = [:]
    private var streamTasks: [String: Task<Void, Never>] = [:]
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
        streamClient: any DockStreamConnecting = AppServerDockStreamClient(),
        archiver: any DockSessionArchiving = AppServerDockClient(),
        metadataStore: any LocalThreadMetadataStoring = FileLocalThreadMetadataStore(),
        streamReconnectDelay: Duration = CodexDockConstants.Dock.autoRefreshInterval,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.hosts = [host]
        self.streamClient = streamClient
        self.archiver = archiver
        self.metadataStore = metadataStore
        self.streamReconnectDelay = streamReconnectDelay
        self.now = now
        self.sessionTable.reset(hosts: [host])
        self.state = .idle([DockHostViewModel(host: host)])
    }

    public init(
        registry: HostRegistry,
        streamClient: any DockStreamConnecting = AppServerDockStreamClient(),
        archiver: any DockSessionArchiving = AppServerDockClient(),
        metadataStore: any LocalThreadMetadataStoring = FileLocalThreadMetadataStore(),
        streamReconnectDelay: Duration = CodexDockConstants.Dock.autoRefreshInterval,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.hosts = registry.hosts
        self.streamClient = streamClient
        self.archiver = archiver
        self.metadataStore = metadataStore
        self.streamReconnectDelay = streamReconnectDelay
        self.now = now
        self.sessionTable.reset(hosts: registry.hosts)
        self.state = .idle(registry.hosts.map(DockHostViewModel.init))
    }

    public init(
        configurationError error: Error,
        streamClient: any DockStreamConnecting = AppServerDockStreamClient(),
        archiver: any DockSessionArchiving = AppServerDockClient(),
        metadataStore: any LocalThreadMetadataStoring = FileLocalThreadMetadataStore(),
        streamReconnectDelay: Duration = CodexDockConstants.Dock.autoRefreshInterval,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.hosts = []
        self.streamClient = streamClient
        self.archiver = archiver
        self.metadataStore = metadataStore
        self.streamReconnectDelay = streamReconnectDelay
        self.now = now
        self.state = .configurationError(error.localizedDescription)
    }

    deinit {
        streamTasks.values.forEach { $0.cancel() }
    }

    public func updateRegistry(_ registry: HostRegistry) async {
        await closeStreams()
        hosts = registry.hosts
        sessionTable.reset(hosts: registry.hosts)
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
        DockLog.dock.notice("dock stream reload started hosts=\(self.hosts.count, privacy: .public) show_loading=\(showLoading, privacy: .public)")
        isLoading = true
        defer {
            DockSignpost.dock.endInterval("dock.reload", signpostState)
            isLoading = false
        }

        let hostViewModels = hosts.map(DockHostViewModel.init)
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

        sessionTable.ensureHosts(hosts)
        await synchronizeStreams()
        publishSnapshot()
        if case let .loaded(snapshot) = state {
            DockLog.dock.notice("dock stream reload finished hosts=\(self.hosts.count, privacy: .public) rows=\(snapshot.rowCount, privacy: .public) duration_ms=\(DockLog.milliseconds(since: startedAt), privacy: .public)")
        }
    }

    private func synchronizeStreams() async {
        let validHostIDs = Set(hosts.map(\.id))
        for hostID in streamConnections.keys where !validHostIDs.contains(hostID) {
            streamTasks[hostID]?.cancel()
            streamTasks[hostID] = nil
            let connection = streamConnections.removeValue(forKey: hostID)
            await connection?.close()
        }

        for host in hosts {
            if let connection = streamConnections[host.id] {
                await resync(host: host, connection: connection)
            } else {
                await openStream(host: host)
            }
        }
    }

    private func openStream(host: DockHostConfiguration) async {
        sessionTable.markChecking(host: host)
        publishSnapshot()
        var openedConnection: (any DockStreamConnection)?
        do {
            let connection = try await streamClient.connect(to: host)
            openedConnection = connection
            streamConnections[host.id] = connection
            let snapshot = try await connection.subscribe()
            try await applySubscribedSnapshot(snapshot, host: host, connection: connection)
            startUpdateTask(host: host, connection: connection)
            publishSnapshot()
        } catch {
            streamTasks[host.id]?.cancel()
            streamTasks[host.id] = nil
            streamConnections[host.id] = nil
            await openedConnection?.close()
            DockLog.dock.warning("dock stream open failed host_id=\(host.id, privacy: .public) error=\(DockLog.errorSummary(error), privacy: .public)")
            sessionTable.markFailure(Self.mapLoadFailure(error), host: host)
            publishSnapshot()
        }
    }

    private func resync(host: DockHostConfiguration, connection: any DockStreamConnection) async {
        do {
            let snapshot = try await connection.resync()
            try applyResyncSnapshot(snapshot, host: host)
            publishSnapshot()
            DockLog.dock.notice("dock stream resync finished host_id=\(host.id, privacy: .public) seq=\(snapshot.seq, privacy: .public) rows=\(self.sessionTable.rowCount(for: host), privacy: .public)")
        } catch {
            DockLog.dock.warning("dock stream resync failed host_id=\(host.id, privacy: .public) error=\(DockLog.errorSummary(error), privacy: .public)")
            sessionTable.markFailure(Self.mapLoadFailure(error), host: host)
            publishSnapshot()
        }
    }

    private func startUpdateTask(host: DockHostConfiguration, connection: any DockStreamConnection) {
        streamTasks[host.id]?.cancel()
        streamTasks[host.id] = Task { [weak self, host, connection] in
            do {
                for try await update in connection.updates() {
                    await self?.handleStreamUpdate(update, host: host, connection: connection)
                }
                if !Task.isCancelled {
                    await self?.handleStreamFailure(
                        DockLoadFailure.offline("Relay stream closed"),
                        host: host,
                        connection: connection
                    )
                }
            } catch is CancellationError {
                return
            } catch {
                await self?.handleStreamFailure(error, host: host, connection: connection)
            }
        }
    }

    private func handleStreamUpdate(
        _ update: DockStreamUpdateDTO,
        host: DockHostConfiguration,
        connection: any DockStreamConnection
    ) async {
        let result = sessionTable.applyUpdate(update, host: host)
        if case .needsResync(let reason) = result {
            DockLog.dock.warning("dock stream resync needed host_id=\(host.id, privacy: .public) reason=\(reason.rawValue, privacy: .public) update_kind=\(update.kind.rawValue, privacy: .public) seq=\(update.seq, privacy: .public)")
            await resync(host: host, connection: connection)
        } else {
            publishSnapshot()
            let rowCount = sessionTable.rowCount(for: host)
            DockLog.dock.info("dock stream update applied host_id=\(host.id, privacy: .public) update_kind=\(update.kind.rawValue, privacy: .public) seq=\(update.seq, privacy: .public) rows=\(rowCount, privacy: .public)")
            if let freshness = update.freshness,
               freshness.status != .fresh,
               rowCount > 0 {
                DockLog.dock.notice("dock stream rows retained host_id=\(host.id, privacy: .public) freshness=\(freshness.status.rawValue, privacy: .public) rows=\(rowCount, privacy: .public)")
            }
        }
    }

    private func applySubscribedSnapshot(
        _ snapshot: DockStreamUpdateDTO,
        host: DockHostConfiguration,
        connection: any DockStreamConnection
    ) async throws {
        switch sessionTable.applySnapshot(snapshot, host: host) {
        case .applied:
            return
        case .needsResync(let reason):
            DockLog.dock.warning("dock stream subscribe snapshot rejected host_id=\(host.id, privacy: .public) reason=\(reason.rawValue, privacy: .public) seq=\(snapshot.seq, privacy: .public)")
            let resynced = try await connection.resync()
            try applyResyncSnapshot(resynced, host: host)
        }
    }

    private func applyResyncSnapshot(
        _ snapshot: DockStreamUpdateDTO,
        host: DockHostConfiguration
    ) throws {
        switch sessionTable.applySnapshot(snapshot, host: host) {
        case .applied:
            return
        case .needsResync(let reason):
            throw DockLoadFailure.error("Dock stream resync returned incompatible data (\(reason.rawValue)).")
        }
    }

    private func handleStreamFailure(
        _ error: Error,
        host: DockHostConfiguration,
        connection: any DockStreamConnection
    ) async {
        DockLog.dock.warning("dock stream update failed host_id=\(host.id, privacy: .public) error=\(DockLog.errorSummary(error), privacy: .public)")
        streamConnections[host.id] = nil
        streamTasks[host.id] = nil
        await connection.close()
        sessionTable.markFailure(Self.mapLoadFailure(error), host: host)
        publishSnapshot()
        let rowCount = sessionTable.rowCount(for: host)
        if rowCount > 0 {
            DockLog.dock.notice("dock stream rows retained host_id=\(host.id, privacy: .public) freshness=offline rows=\(rowCount, privacy: .public)")
        }
        scheduleReconnect(host: host)
    }

    private func scheduleReconnect(host: DockHostConfiguration) {
        guard hosts.contains(where: { $0.id == host.id }) else {
            return
        }
        streamTasks[host.id] = Task { [weak self, host] in
            do {
                try await Task.sleep(for: self?.streamReconnectDelay ?? CodexDockConstants.Dock.autoRefreshInterval)
            } catch {
                return
            }
            await self?.openStream(host: host)
        }
    }

    private func closeStreams() async {
        streamTasks.values.forEach { $0.cancel() }
        streamTasks = [:]
        let connections = streamConnections
        streamConnections = [:]
        for connection in connections.values {
            await connection.close()
        }
    }

    private func publishSnapshot() {
        guard !hosts.isEmpty else {
            return
        }
        let snapshot = sessionTable.snapshot(
            hosts: hosts,
            localMetadata: localMetadata,
            now: now
        )
        state = .loaded(snapshot)
        connectivityReporter?.reportDockState(state)
    }

    private nonisolated static func mapLoadFailure(_ error: Error) -> DockLoadFailure {
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

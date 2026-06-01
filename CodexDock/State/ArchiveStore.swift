import Combine
import Foundation

public struct ArchiveSnapshot: Equatable, Sendable {
    public let hosts: [DockHostViewModel]
    public let hostStates: [DockHostStateViewModel]
    public let hostIdentityResolver: DockHostIdentityResolver
    public let sections: [DockSectionViewModel]

    public var rowCount: Int {
        sections.reduce(0) { count, section in
            count + section.rows.count
        }
    }

    public var unavailableMessage: String? {
        guard !hostStates.isEmpty,
              hostStates.allSatisfy(\.status.isUnavailable) else {
            return nil
        }
        return hostStates.map { "\($0.host.displayName): \($0.status.unavailableMessage ?? $0.status.subtitle)" }
            .joined(separator: "; ")
    }
}

public enum ArchiveStoreState: Equatable, Sendable {
    case configurationError(String)
    case idle([DockHostViewModel])
    case loading([DockHostViewModel])
    case loaded(ArchiveSnapshot)
    case empty(ArchiveSnapshot)
    case unavailable(ArchiveSnapshot, String)
}

public enum ArchiveRestoreRowStatus: Equatable, Sendable {
    case restored
    case failed(String)
    case skipped
}

public struct ArchiveRestoreResult: Equatable, Sendable {
    public let row: DockRowViewModel
    public let status: ArchiveRestoreRowStatus

    public init(row: DockRowViewModel, status: ArchiveRestoreRowStatus) {
        self.row = row
        self.status = status
    }
}

@MainActor
public final class ArchiveStore: ObservableObject {
    @Published public private(set) var state: ArchiveStoreState
    @Published public private(set) var actionError: String?

    public let screenStore: ArchiveScreenStore

    private var hosts: [DockHostConfiguration]
    private let commandEngine: ClientCommandEngine
    private var dataEngine: ArchiveDataEngine?
    private var streamLifecycle: ThreadCardStreamLifecycle?
    private var isLoading = false
    private weak var connectivityReporter: (any AppConnectivityReporting)?
    private let connectivityEventSink: ConnectivityEventSink?

    public init(
        registry: HostRegistry,
        streamClient: any ThreadCardStreamConnecting = AppServerThreadCardStreamClient(view: .archive),
        archiver: any ThreadArchiveCommanding = AppServerThreadCommandClient(),
        metadataStore: any LocalThreadMetadataStoring = FileLocalThreadMetadataStore(),
        connectivityEventSink: ConnectivityEventSink? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.hosts = registry.hosts
        self.commandEngine = ClientCommandEngine(archiver: archiver)
        self.connectivityEventSink = connectivityEventSink
        self.dataEngine = ArchiveDataEngine(
            registry: registry,
            metadataStore: metadataStore,
            now: now
        )
        self.streamLifecycle = nil
        let initialState = ArchiveStoreState.idle(registry.hosts.map(DockHostViewModel.init))
        self.state = initialState
        self.screenStore = ArchiveScreenStore(state: initialState)
        self.streamLifecycle = ThreadCardStreamLifecycle(
            view: .archive,
            streamClient: streamClient,
            streamReconnectDelay: CodexDockConstants.Dock.autoRefreshInterval,
            streamHeartbeatTimeout: CodexDockConstants.Dock.streamHeartbeatTimeout,
            logger: DockLog.archive,
            logName: "archive",
            delegate: self
        )
    }

    public init(
        configurationError error: Error,
        archiver: any ThreadArchiveCommanding = AppServerThreadCommandClient(),
        metadataStore: any LocalThreadMetadataStoring = FileLocalThreadMetadataStore(),
        connectivityEventSink: ConnectivityEventSink? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.hosts = []
        self.commandEngine = ClientCommandEngine(archiver: archiver)
        self.connectivityEventSink = connectivityEventSink
        self.dataEngine = nil
        self.streamLifecycle = nil
        let initialState = ArchiveStoreState.configurationError(error.localizedDescription)
        self.state = initialState
        self.screenStore = ArchiveScreenStore(state: initialState)
    }

    public func updateRegistry(_ registry: HostRegistry) async {
        await streamLifecycle?.closeStreams()
        hosts = registry.hosts
        if let dataEngine {
            await dataEngine.updateRegistry(registry)
        }
        setActionError(nil)
        setState(.idle(registry.hosts.map(DockHostViewModel.init)))
        publishConnectivity(for: state)
        await reload(showLoading: true)
    }

    public func setConnectivityReporter(_ reporter: (any AppConnectivityReporting)?) {
        connectivityReporter = reporter
        guard connectivityEventSink == nil else {
            return
        }
        reporter?.reportArchiveState(state)
    }

    public func load() async {
        await reload(showLoading: true)
    }

    public func refresh() async {
        await reload(showLoading: false)
    }

    @discardableResult
    public func restore(_ row: DockRowViewModel) async -> Bool {
        let result = await restoreRow(row)
        switch result.status {
        case .restored:
            await refresh()
            return true
        case .failed:
            return false
        case .skipped:
            return false
        }
    }

    @discardableResult
    public func restoreRows(
        _ rows: [DockRowViewModel],
        shouldStop: @MainActor () -> Bool = { false },
        onProgress: @MainActor ([ArchiveRestoreResult]) -> Void = { _ in }
    ) async -> [ArchiveRestoreResult] {
        guard !rows.isEmpty else {
            return []
        }

        var didRestoreAnyRow = false
        var results: [ArchiveRestoreResult] = []
        for row in rows {
            if shouldStop() {
                results.append(ArchiveRestoreResult(row: row, status: .skipped))
                onProgress(results)
                continue
            }

            let result = await restoreRow(row)
            if case .restored = result.status {
                didRestoreAnyRow = true
            }
            results.append(result)
            onProgress(results)
        }

        if didRestoreAnyRow {
            await refresh()
        }
        return results
    }

    private func restoreRow(_ row: DockRowViewModel) async -> ArchiveRestoreResult {
        guard let host = hostConfiguration(for: row) else {
            DockLog.archive.error("archive restore skipped missing host_id=\(row.id.hostID, privacy: .public) thread_id=\(DockLog.publicID(row.id.threadID), privacy: .public)")
            let message = "Host \(row.id.hostID) is no longer configured."
            setActionError(message)
            return ArchiveRestoreResult(row: row, status: .failed(message))
        }

        do {
            DockLog.archive.notice("archive restore action started host_id=\(host.id, privacy: .public) thread_id=\(DockLog.publicID(row.id.threadID), privacy: .public)")
            try await commandEngine.unarchive(row, on: host)
            setActionError(nil)
            DockLog.archive.notice("archive restore action finished host_id=\(host.id, privacy: .public) thread_id=\(DockLog.publicID(row.id.threadID), privacy: .public)")
            return ArchiveRestoreResult(row: row, status: .restored)
        } catch {
            DockLog.archive.error("archive restore action failed host_id=\(host.id, privacy: .public) thread_id=\(DockLog.publicID(row.id.threadID), privacy: .public) error=\(DockLog.errorSummary(error), privacy: .public)")
            let message = error.localizedDescription
            setActionError(message)
            return ArchiveRestoreResult(row: row, status: .failed(message))
        }
    }

    public func hostConfiguration(for row: DockRowViewModel) -> DockHostConfiguration? {
        if case .loaded(let snapshot) = state,
           let resolved = snapshot.hostIdentityResolver.resolve(
               rowHostID: row.id.hostID,
               sourceConfiguredHostID: row.sourceHostID
           ) {
            return resolved.host
        }
        if case .empty(let snapshot) = state,
           let resolved = snapshot.hostIdentityResolver.resolve(
               rowHostID: row.id.hostID,
               sourceConfiguredHostID: row.sourceHostID
           ) {
            return resolved.host
        }
        if case .unavailable(let snapshot, _) = state,
           let resolved = snapshot.hostIdentityResolver.resolve(
               rowHostID: row.id.hostID,
               sourceConfiguredHostID: row.sourceHostID
           ) {
            return resolved.host
        }
        if let sourceHostID = row.sourceHostID,
           let host = hosts.first(where: { $0.id == sourceHostID }) {
            return host
        }
        return DockHostIdentityResolver(hosts: hosts)
            .resolve(rowHostID: row.id.hostID, sourceConfiguredHostID: row.sourceHostID)?
            .host
    }

    private func reload(showLoading: Bool) async {
        guard !hosts.isEmpty else {
            DockLog.archive.warning("archive reload skipped reason=no_hosts")
            return
        }
        guard !isLoading else {
            DockLog.archive.debug("archive reload skipped reason=already_loading")
            return
        }

        let startedAt = Date()
        let signpostState = DockSignpost.archive.beginInterval("archive.reload")
        DockLog.archive.notice("archive reload started hosts=\(self.hosts.count, privacy: .public) show_loading=\(showLoading, privacy: .public)")
        isLoading = true
        defer {
            DockSignpost.archive.endInterval("archive.reload", signpostState)
            isLoading = false
        }

        if showLoading {
            setState(.loading(hosts.map(DockHostViewModel.init)))
            publishConnectivity(for: state)
        }

        guard let dataEngine else {
            DockLog.archive.warning("archive reload skipped reason=no_data_engine")
            return
        }

        await dataEngine.loadLocalMetadata()
        await dataEngine.ensureHosts()
        await streamLifecycle?.synchronizeStreams(hosts: hosts)
        await dataEngine.migrateMetadataHostAliases()
        await publishSnapshot()
        if let snapshot = await dataEngine.snapshot() {
            DockLog.archive.notice("archive stream reload finished hosts=\(self.hosts.count, privacy: .public) rows=\(snapshot.rowCount, privacy: .public) duration_ms=\(DockLog.milliseconds(since: startedAt), privacy: .public)")
        }
    }

    private func publishSnapshot() async {
        guard let snapshot = await dataEngine?.snapshot() else {
            return
        }
        if snapshot.rowCount == 0, let message = snapshot.unavailableMessage {
            setState(.unavailable(snapshot, message))
        } else {
            setState(snapshot.rowCount == 0 ? .empty(snapshot) : .loaded(snapshot))
        }
        publishConnectivity(for: state)
    }

    private func setState(_ state: ArchiveStoreState) {
        self.state = state
        screenStore.setState(state)
    }

    private func setActionError(_ message: String?) {
        actionError = message
        screenStore.setActionError(message)
    }

    private func publishConnectivity(for state: ArchiveStoreState) {
        if connectivityEventSink == nil {
            connectivityReporter?.reportArchiveState(state)
        }
        recordConnectivityFacts(for: state)
    }

    private func recordConnectivityFacts(for state: ArchiveStoreState) {
        guard let connectivityEventSink else {
            return
        }
        let events = connectivityEvents(for: state)
        guard !events.isEmpty else {
            return
        }
        Task {
            for event in events {
                await connectivityEventSink.record(event)
            }
        }
    }

    private func connectivityEvents(for state: ArchiveStoreState) -> [ConnectivityRuntimeEvent] {
        switch state {
        case .configurationError(let message):
            return [
                ConnectivityRuntimeEvent(
                    source: .archive,
                    hostID: nil,
                    route: "archive/configuration",
                    status: message,
                    phase: .configurationError(message)
                )
            ]
        case .idle(let hosts):
            return hosts.map { host in
                ConnectivityRuntimeEvent(
                    source: .archive,
                    hostID: host.id,
                    route: "archive",
                    status: "idle",
                    phase: .unknown
                )
            }
        case .loading(let hosts):
            return hosts.map { host in
                ConnectivityRuntimeEvent(
                    source: .archive,
                    hostID: host.id,
                    route: "archive/subscribe",
                    status: "checking",
                    phase: .checking
                )
            }
        case .loaded(let snapshot), .empty(let snapshot), .unavailable(let snapshot, _):
            return snapshot.hostStates.map { hostState in
                ConnectivityRuntimeEvent(
                    source: .archive,
                    hostID: hostState.host.id,
                    route: "archive/subscribe",
                    status: hostState.status.subtitle,
                    phase: Self.connectivityPhase(for: hostState.status)
                )
            }
        }
    }

    private nonisolated static func connectivityPhase(
        for status: DockHostLoadStatus
    ) -> HostConnectivityPhase {
        switch status {
        case .checking:
            return .checking
        case .loaded(let rowCount):
            return .online("\(rowCount) sessions")
        case .partial(_, let message):
            return .partial(message)
        case .empty:
            return .online("Online, no sessions")
        case .offline(let message):
            return .offline(message)
        case .error(let message):
            return .error(message)
        }
    }
}

extension ArchiveStore: ThreadCardStreamLifecycleDelegate {
    func cardStreamLifecycleMarkChecking(host: DockHostConfiguration) async {
        await dataEngine?.markChecking(host: host)
    }

    func cardStreamLifecycleMarkFailure(_ failure: DockRequestFailure, host: DockHostConfiguration) async {
        await dataEngine?.markFailure(failure, host: host)
    }

    func cardStreamLifecycleApplySnapshot(
        _ update: ThreadCardStreamUpdateDTO,
        host: DockHostConfiguration
    ) async -> ThreadCardTableApplyResult {
        guard let dataEngine else {
            return .needsResync(.streamContract)
        }
        return await dataEngine.applySnapshot(update, host: host)
    }

    func cardStreamLifecycleApplyUpdate(
        _ update: ThreadCardStreamUpdateDTO,
        host: DockHostConfiguration
    ) async -> ThreadCardTableApplyResult {
        guard let dataEngine else {
            return .needsResync(.streamContract)
        }
        return await dataEngine.applyUpdate(update, host: host)
    }

    func cardStreamLifecycleRowCount(for host: DockHostConfiguration) async -> Int {
        await dataEngine?.rowCount(for: host) ?? 0
    }

    func cardStreamLifecyclePublishSnapshot() async {
        await publishSnapshot()
    }

    func cardStreamLifecycleMigrateMetadataHostAliases() async {
        await dataEngine?.migrateMetadataHostAliases()
    }
}

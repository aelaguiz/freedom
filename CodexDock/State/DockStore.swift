import Combine
import Foundation

@MainActor
public final class DockStore: ObservableObject {
    public static let defaultAutoRefreshInterval: Duration = CodexDockConstants.Dock.autoRefreshInterval

    @Published public private(set) var state: DockStoreState
    @Published public private(set) var actionError: String?

    let screenStore: DockScreenStore

    private var hosts: [DockHostConfiguration]
    private let commandEngine: ClientCommandEngine
    private let metadataEngine: LocalMetadataEngine
    private let streamClient: any ThreadCardStreamConnecting
    private let streamReconnectDelay: Duration
    private let streamHeartbeatTimeout: Duration
    private let now: @Sendable () -> Date
    private var dataEngine: DockDataEngine?
    private var streamReconcilers: [String: StreamReconciler<DockThreadCardDTO>] = [:]
    private var streamTasks: [String: Task<Void, Never>] = [:]
    private var isLoading = false
    private var localMetadata: [LocalThreadMetadataKey: LocalThreadMetadata] = [:]
    private weak var connectivityReporter: (any AppConnectivityReporting)?
    private let connectivityEventSink: ConnectivityEventSink?

    public var hostConfiguration: DockHostConfiguration? {
        hosts.first
    }

    private static func makeCommandEngine(
        archiver: any ThreadArchiveCommanding,
        renamer: (any ThreadRenameCommanding)?
    ) -> ClientCommandEngine {
        guard let renamer else {
            return ClientCommandEngine(archiver: archiver)
        }
        return ClientCommandEngine(archiver: archiver, renamer: renamer)
    }

    public var currentDockSnapshot: DockSnapshot? {
        guard case .loaded(let snapshot) = state else {
            return nil
        }
        return snapshot
    }

    public func hostConfiguration(for hostID: String) -> DockHostConfiguration? {
        if case .loaded(let snapshot) = state,
           let resolved = snapshot.hostIdentityResolver.resolve(rowHostID: hostID) {
            return resolved.host
        }
        return DockHostIdentityResolver(hosts: hosts)
            .resolve(rowHostID: hostID)?
            .host
    }

    public func hostConfiguration(for row: DockRowViewModel) -> DockHostConfiguration? {
        if case .loaded(let snapshot) = state,
           let resolved = snapshot.hostIdentityResolver.resolve(
               rowHostID: row.hostID,
               sourceConfiguredHostID: row.sourceHostID
           ) {
            return resolved.host
        }
        if let sourceHostID = row.sourceHostID,
           let host = hosts.first(where: { $0.id == sourceHostID }) {
            return host
        }
        return hostConfiguration(for: row.hostID)
    }

    public init(
        host: DockHostConfiguration,
        streamClient: any ThreadCardStreamConnecting = AppServerThreadCardStreamClient(),
        archiver: any ThreadArchiveCommanding = AppServerThreadCommandClient(),
        renamer: (any ThreadRenameCommanding)? = nil,
        metadataStore: any LocalThreadMetadataStoring = FileLocalThreadMetadataStore(),
        streamReconnectDelay: Duration = CodexDockConstants.Dock.autoRefreshInterval,
        streamHeartbeatTimeout: Duration = CodexDockConstants.Dock.streamHeartbeatTimeout,
        connectivityEventSink: ConnectivityEventSink? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        let hostViewModels = [DockHostViewModel(host: host)]
        self.hosts = [host]
        self.commandEngine = Self.makeCommandEngine(archiver: archiver, renamer: renamer)
        self.metadataEngine = LocalMetadataEngine(store: metadataStore, now: now)
        self.streamClient = streamClient
        self.streamReconnectDelay = streamReconnectDelay
        self.streamHeartbeatTimeout = streamHeartbeatTimeout
        self.connectivityEventSink = connectivityEventSink
        self.now = now
        self.screenStore = DockScreenStore(hosts: hostViewModels, now: now)
        if let registry = try? HostRegistry(hosts: [host]) {
            self.dataEngine = DockDataEngine(registry: registry)
        } else {
            self.dataEngine = nil
        }
        self.state = .idle(hostViewModels)
        self.screenStore.start()
    }

    public init(
        registry: HostRegistry,
        streamClient: any ThreadCardStreamConnecting = AppServerThreadCardStreamClient(),
        archiver: any ThreadArchiveCommanding = AppServerThreadCommandClient(),
        renamer: (any ThreadRenameCommanding)? = nil,
        metadataStore: any LocalThreadMetadataStoring = FileLocalThreadMetadataStore(),
        streamReconnectDelay: Duration = CodexDockConstants.Dock.autoRefreshInterval,
        streamHeartbeatTimeout: Duration = CodexDockConstants.Dock.streamHeartbeatTimeout,
        connectivityEventSink: ConnectivityEventSink? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        let hostViewModels = registry.hosts.map(DockHostViewModel.init)
        self.hosts = registry.hosts
        self.commandEngine = Self.makeCommandEngine(archiver: archiver, renamer: renamer)
        self.metadataEngine = LocalMetadataEngine(store: metadataStore, now: now)
        self.streamClient = streamClient
        self.streamReconnectDelay = streamReconnectDelay
        self.streamHeartbeatTimeout = streamHeartbeatTimeout
        self.connectivityEventSink = connectivityEventSink
        self.now = now
        self.screenStore = DockScreenStore(hosts: hostViewModels, now: now)
        self.dataEngine = DockDataEngine(registry: registry)
        self.state = .idle(hostViewModels)
        self.screenStore.start()
    }

    public init(
        configurationError error: Error,
        streamClient: any ThreadCardStreamConnecting = AppServerThreadCardStreamClient(),
        archiver: any ThreadArchiveCommanding = AppServerThreadCommandClient(),
        renamer: (any ThreadRenameCommanding)? = nil,
        metadataStore: any LocalThreadMetadataStoring = FileLocalThreadMetadataStore(),
        streamReconnectDelay: Duration = CodexDockConstants.Dock.autoRefreshInterval,
        streamHeartbeatTimeout: Duration = CodexDockConstants.Dock.streamHeartbeatTimeout,
        connectivityEventSink: ConnectivityEventSink? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        let message = error.localizedDescription
        self.hosts = []
        self.commandEngine = Self.makeCommandEngine(archiver: archiver, renamer: renamer)
        self.metadataEngine = LocalMetadataEngine(store: metadataStore, now: now)
        self.streamClient = streamClient
        self.streamReconnectDelay = streamReconnectDelay
        self.streamHeartbeatTimeout = streamHeartbeatTimeout
        self.connectivityEventSink = connectivityEventSink
        self.now = now
        self.screenStore = DockScreenStore(configurationError: message)
        self.dataEngine = nil
        self.state = .configurationError(message)
        self.screenStore.start()
    }

    deinit {
        streamTasks.values.forEach { $0.cancel() }
        let reconcilers = Array(streamReconcilers.values)
        Task {
            for reconciler in reconcilers {
                await reconciler.close()
            }
        }
    }

    public func updateRegistry(_ registry: HostRegistry) async {
        await closeAllReconcilers()
        hosts = registry.hosts
        if let dataEngine {
            await dataEngine.updateRegistry(registry)
        } else {
            dataEngine = DockDataEngine(registry: registry)
        }
        setActionError(nil)
        let hostViewModels = registry.hosts.map(DockHostViewModel.init)
        state = .idle(hostViewModels)
        screenStore.setIdle(hosts: hostViewModels)
        publishConnectivity(for: state)
        await reload(showLoading: true)
    }

    public func setConnectivityReporter(_ reporter: (any AppConnectivityReporting)?) {
        connectivityReporter = reporter
        guard connectivityEventSink == nil else {
            return
        }
        reporter?.reportDockState(state)
    }

    private func setActionError(_ message: String?) {
        actionError = message
        screenStore.setActionError(message)
    }

    public func load() async {
        await reload(showLoading: true)
    }

    public func refresh() async {
        await reload(showLoading: false)
    }

    public func setLabel(_ label: String?, for row: DockRowViewModel) async {
        await persistMetadataChange(
            logLabel: "label",
            hostID: row.hostID,
            threadID: row.threadID
        ) {
            try await metadataEngine.setLabel(label, for: row.metadataKey)
        }
    }

    public func setRail(_ rail: DockRowRail?, for row: DockRowViewModel) async {
        await persistMetadataChange(
            logLabel: "rail",
            hostID: row.hostID,
            threadID: row.threadID
        ) {
            try await metadataEngine.setRail(rail, for: row.metadataKey)
        }
    }

    public func setPinned(_ isPinned: Bool, for row: DockRowViewModel) async {
        await persistMetadataChange(
            logLabel: isPinned ? "pin" : "unpin",
            hostID: row.hostID,
            threadID: row.threadID
        ) {
            try await metadataEngine.setPinned(isPinned, for: row)
        }
    }

    public func reorderPinnedRows(_ visibleRowsInNewOrder: [DockRowViewModel]) async {
        await persistMetadataChange(
            logLabel: "reorder_pinned",
            hostID: nil,
            threadID: nil
        ) {
            try await metadataEngine.reorderPinnedRows(visibleRowsInNewOrder)
        }
    }

    @discardableResult
    public func rename(_ row: DockRowViewModel, to name: String) async -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            setActionError("Thread name cannot be empty.")
            return false
        }

        guard let host = hostConfiguration(for: row) else {
            DockLog.dock.error("dock rename skipped missing host_id=\(row.hostID, privacy: .public) thread_id=\(DockLog.publicID(row.threadID), privacy: .public)")
            setActionError("Host \(row.hostID) is no longer configured.")
            return false
        }

        do {
            DockLog.dock.notice("dock rename action started host_id=\(host.id, privacy: .public) thread_id=\(DockLog.publicID(row.threadID), privacy: .public)")
            try await commandEngine.rename(row, to: trimmedName, on: host)
            setActionError(nil)
            await refresh()
            DockLog.dock.notice("dock rename action finished host_id=\(host.id, privacy: .public) thread_id=\(DockLog.publicID(row.threadID), privacy: .public)")
            return true
        } catch {
            DockLog.dock.error("dock rename action failed host_id=\(host.id, privacy: .public) thread_id=\(DockLog.publicID(row.threadID), privacy: .public) error=\(DockLog.errorSummary(error), privacy: .public)")
            setActionError(error.localizedDescription)
            return false
        }
    }

    @discardableResult
    public func archive(_ row: DockRowViewModel) async -> Bool {
        guard let host = hostConfiguration(for: row) else {
            DockLog.dock.error("dock archive skipped missing host_id=\(row.hostID, privacy: .public) thread_id=\(DockLog.publicID(row.threadID), privacy: .public)")
            setActionError("Host \(row.hostID) is no longer configured.")
            return false
        }

        do {
            DockLog.dock.notice("dock archive action started host_id=\(host.id, privacy: .public) thread_id=\(DockLog.publicID(row.threadID), privacy: .public)")
            try await commandEngine.archive(row, on: host)
            setActionError(nil)
            await refresh()
            DockLog.dock.notice("dock archive action finished host_id=\(host.id, privacy: .public) thread_id=\(DockLog.publicID(row.threadID), privacy: .public)")
            return true
        } catch {
            DockLog.dock.error("dock archive action failed host_id=\(host.id, privacy: .public) thread_id=\(DockLog.publicID(row.threadID), privacy: .public) error=\(DockLog.errorSummary(error), privacy: .public)")
            setActionError(error.localizedDescription)
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
            screenStore.setLoading(hosts: hostViewModels)
            publishConnectivity(for: state)
        }

        do {
            localMetadata = try await metadataEngine.load()
            DockLog.persistence.debug("dock metadata loaded entries=\(self.localMetadata.count, privacy: .public)")
        } catch {
            localMetadata = [:]
            await metadataEngine.replace(localMetadata)
            DockLog.persistence.warning("dock metadata load failed error=\(DockLog.errorSummary(error), privacy: .public)")
        }

        await dataEngine?.updateLocalMetadata(localMetadata)
        await dataEngine?.ensureHosts()
        await synchronizeStreams()
        await migrateMetadataHostAliases()
        await publishSnapshot()
        if case let .loaded(snapshot) = state {
            DockLog.dock.notice("dock stream reload finished hosts=\(self.hosts.count, privacy: .public) rows=\(snapshot.rowCount, privacy: .public) duration_ms=\(DockLog.milliseconds(since: startedAt), privacy: .public)")
        }
    }

    private func synchronizeStreams() async {
        let validHostIDs = Set(hosts.map(\.id))
        for hostID in streamReconcilers.keys where !validHostIDs.contains(hostID) {
            await closeReconciler(hostID: hostID)
        }

        for host in hosts {
            let reconciler = streamReconcilers[host.id] ?? makeReconciler(for: host)
            if streamReconcilers[host.id] == nil {
                streamReconcilers[host.id] = reconciler
                await reconciler.start()
                await startReconcilerObservation(reconciler, host: host)
            } else {
                await reconciler.manualRefresh()
            }
            await dataEngine?.apply(await reconciler.snapshot(), host: host)
            await migrateMetadataHostAliases()
            await publishSnapshot()
        }
    }

    private func makeReconciler(for host: DockHostConfiguration) -> StreamReconciler<DockThreadCardDTO> {
        StreamReconciler(
            viewKey: ProjectionViewKey(
                sourceHostID: nil,
                view: ThreadCardStreamView.dock.rawValue,
                scope: "view",
                viewParamsKey: nil
            ),
            policy: .threadCards(expectedView: .dock),
            connector: ThreadCardProjectionStreamConnector(
                host: host,
                streamClient: streamClient
            ),
            heartbeatTimeout: streamHeartbeatTimeout,
            reconnectDelay: streamReconnectDelay
        )
    }

    private func startReconcilerObservation(
        _ reconciler: StreamReconciler<DockThreadCardDTO>,
        host: DockHostConfiguration
    ) async {
        streamTasks[host.id]?.cancel()
        let snapshots = await reconciler.snapshots()
        streamTasks[host.id] = Task { [weak self, host] in
            for await snapshot in snapshots {
                await self?.handleReconcilerSnapshot(snapshot, host: host)
            }
        }
    }

    private func handleReconcilerSnapshot(
        _ snapshot: StreamReconcilerSnapshot<DockThreadCardDTO>,
        host: DockHostConfiguration
    ) async {
        await dataEngine?.apply(snapshot, host: host)
        await migrateMetadataHostAliases()
        await publishSnapshot()
    }

    private func closeReconciler(hostID: String) async {
        streamTasks[hostID]?.cancel()
        streamTasks[hostID] = nil
        let reconciler = streamReconcilers.removeValue(forKey: hostID)
        await reconciler?.close()
    }

    private func closeAllReconcilers() async {
        let hostIDs = Array(streamReconcilers.keys)
        for hostID in hostIDs {
            await closeReconciler(hostID: hostID)
        }
    }

    private func publishSnapshot() async {
        guard !hosts.isEmpty else {
            return
        }
        guard let snapshot = await dataEngine?.snapshot(now: now) else {
            return
        }
        state = .loaded(snapshot)
        screenStore.publish(snapshot: snapshot)
        publishConnectivity(for: state)
    }

    private func migrateMetadataHostAliases() async {
        guard let resolver = await dataEngine?.hostIdentityResolver() else {
            return
        }
        do {
            let migratedMetadata = try await metadataEngine.migrateHostAliases(using: resolver)
            if migratedMetadata != localMetadata {
                DockLog.persistence.notice("dock metadata host aliases migrated entries=\(migratedMetadata.count, privacy: .public)")
            }
            localMetadata = migratedMetadata
            await dataEngine?.updateLocalMetadata(localMetadata)
        } catch {
            DockLog.persistence.warning("dock metadata host alias migration failed error=\(DockLog.errorSummary(error), privacy: .public)")
        }
    }

    private func publishConnectivity(for state: DockStoreState) {
        if connectivityEventSink == nil {
            connectivityReporter?.reportDockState(state)
        }
        recordConnectivityFacts(for: state)
    }

    private func recordConnectivityFacts(for state: DockStoreState) {
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

    private func connectivityEvents(for state: DockStoreState) -> [ConnectivityRuntimeEvent] {
        switch state {
        case .configurationError(let message):
            return [
                ConnectivityRuntimeEvent(
                    source: .dock,
                    hostID: nil,
                    route: "dock/configuration",
                    status: message,
                    phase: .configurationError(message),
                    recordedAt: now()
                )
            ]
        case .idle(let hosts):
            return hosts.map { host in
                ConnectivityRuntimeEvent(
                    source: .dock,
                    hostID: host.id,
                    route: "dock",
                    status: "idle",
                    phase: .unknown,
                    recordedAt: now()
                )
            }
        case .loading(let hosts):
            return hosts.map { host in
                ConnectivityRuntimeEvent(
                    source: .dock,
                    hostID: host.id,
                    route: "dock/subscribe",
                    status: "checking",
                    phase: .checking,
                    recordedAt: now()
                )
            }
        case .offline(let host, let message):
            return [
                ConnectivityRuntimeEvent(
                    source: .dock,
                    hostID: host.id,
                    route: "dock/subscribe",
                    status: "offline: \(message)",
                    phase: .offline(message),
                    recordedAt: now()
                )
            ]
        case .error(let host, let message):
            return [
                ConnectivityRuntimeEvent(
                    source: .dock,
                    hostID: host.id,
                    route: "dock/subscribe",
                    status: "error: \(message)",
                    phase: .error(message),
                    recordedAt: now()
                )
            ]
        case .loaded(let snapshot):
            return snapshot.hostStates.map { hostState in
                ConnectivityRuntimeEvent(
                    source: .dock,
                    hostID: hostState.host.id,
                    route: "dock/subscribe",
                    status: hostState.status.subtitle,
                    phase: Self.connectivityPhase(for: hostState.status),
                    recordedAt: now()
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
        case .loaded(let rowCount, _):
            return .online("\(rowCount) sessions")
        case .degraded(_, let message):
            return .partial(message)
        case .empty:
            return .online("Online, no sessions")
        case .offline(let message):
            return .offline(message)
        case .error(let message):
            return .error(message)
        }
    }

    private func persistMetadataChange(
        logLabel: String,
        hostID: String?,
        threadID: String?,
        _ operation: () async throws -> [LocalThreadMetadataKey: LocalThreadMetadata]
    ) async {
        do {
            DockLog.persistence.debug("dock metadata action started action=\(logLabel, privacy: .public) host_id=\(DockLog.publicID(hostID), privacy: .public) thread_id=\(DockLog.publicID(threadID), privacy: .public)")
            localMetadata = try await operation()
            await dataEngine?.updateLocalMetadata(localMetadata)
            setActionError(nil)
            await publishSnapshot()
            DockLog.persistence.debug("dock metadata action finished action=\(logLabel, privacy: .public) entries=\(self.localMetadata.count, privacy: .public)")
        } catch {
            DockLog.persistence.error("dock metadata action failed action=\(logLabel, privacy: .public) host_id=\(DockLog.publicID(hostID), privacy: .public) thread_id=\(DockLog.publicID(threadID), privacy: .public) error=\(DockLog.errorSummary(error), privacy: .public)")
            setActionError(error.localizedDescription)
        }
    }

}

extension DockStore: DockCardStateProviding {}

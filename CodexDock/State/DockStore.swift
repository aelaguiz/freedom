import Combine
import Foundation

@MainActor
public final class DockStore: ObservableObject {
    public static let defaultAutoRefreshInterval: Duration = CodexDockConstants.Dock.autoRefreshInterval

    @Published public private(set) var state: DockStoreState
    @Published public private(set) var actionError: String?

    let screenStore: DockScreenStore

    private var hosts: [DockHostConfiguration]
    private let streamClient: any ThreadCardStreamConnecting
    private let commandEngine: ClientCommandEngine
    private let metadataEngine: LocalMetadataEngine
    private let now: @Sendable () -> Date
    private let streamReconnectDelay: Duration
    private var dataEngine: DockDataEngine?
    private var streamConnections: [String: any ThreadCardStreamConnection] = [:]
    private var streamTasks: [String: Task<Void, Never>] = [:]
    private var isLoading = false
    private var localMetadata: [LocalThreadMetadataKey: LocalThreadMetadata] = [:]
    private weak var connectivityReporter: (any AppConnectivityReporting)?
    private let connectivityEventSink: ConnectivityEventSink?

    public var hostConfiguration: DockHostConfiguration? {
        hosts.first
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
               rowHostID: row.id.hostID,
               sourceConfiguredHostID: row.sourceHostID
           ) {
            return resolved.host
        }
        if let sourceHostID = row.sourceHostID,
           let host = hosts.first(where: { $0.id == sourceHostID }) {
            return host
        }
        return hostConfiguration(for: row.id.hostID)
    }

    public init(
        host: DockHostConfiguration,
        streamClient: any ThreadCardStreamConnecting = AppServerThreadCardStreamClient(),
        archiver: any ThreadArchiveCommanding = AppServerThreadCommandClient(),
        metadataStore: any LocalThreadMetadataStoring = FileLocalThreadMetadataStore(),
        streamReconnectDelay: Duration = CodexDockConstants.Dock.autoRefreshInterval,
        connectivityEventSink: ConnectivityEventSink? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        let hostViewModels = [DockHostViewModel(host: host)]
        self.hosts = [host]
        self.streamClient = streamClient
        self.commandEngine = ClientCommandEngine(archiver: archiver)
        self.metadataEngine = LocalMetadataEngine(store: metadataStore, now: now)
        self.streamReconnectDelay = streamReconnectDelay
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
        metadataStore: any LocalThreadMetadataStoring = FileLocalThreadMetadataStore(),
        streamReconnectDelay: Duration = CodexDockConstants.Dock.autoRefreshInterval,
        connectivityEventSink: ConnectivityEventSink? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        let hostViewModels = registry.hosts.map(DockHostViewModel.init)
        self.hosts = registry.hosts
        self.streamClient = streamClient
        self.commandEngine = ClientCommandEngine(archiver: archiver)
        self.metadataEngine = LocalMetadataEngine(store: metadataStore, now: now)
        self.streamReconnectDelay = streamReconnectDelay
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
        metadataStore: any LocalThreadMetadataStoring = FileLocalThreadMetadataStore(),
        streamReconnectDelay: Duration = CodexDockConstants.Dock.autoRefreshInterval,
        connectivityEventSink: ConnectivityEventSink? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        let message = error.localizedDescription
        self.hosts = []
        self.streamClient = streamClient
        self.commandEngine = ClientCommandEngine(archiver: archiver)
        self.metadataEngine = LocalMetadataEngine(store: metadataStore, now: now)
        self.streamReconnectDelay = streamReconnectDelay
        self.connectivityEventSink = connectivityEventSink
        self.now = now
        self.screenStore = DockScreenStore(configurationError: message)
        self.dataEngine = nil
        self.state = .configurationError(message)
        self.screenStore.start()
    }

    deinit {
        streamTasks.values.forEach { $0.cancel() }
    }

    public func updateRegistry(_ registry: HostRegistry) async {
        await closeStreams()
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
            hostID: row.id.hostID,
            threadID: row.id.threadID
        ) {
            try await metadataEngine.setLabel(label, for: row.metadataKey)
        }
    }

    public func setRail(_ rail: DockRowRail?, for row: DockRowViewModel) async {
        await persistMetadataChange(
            logLabel: "rail",
            hostID: row.id.hostID,
            threadID: row.id.threadID
        ) {
            try await metadataEngine.setRail(rail, for: row.metadataKey)
        }
    }

    public func setPinned(_ isPinned: Bool, for row: DockRowViewModel) async {
        await persistMetadataChange(
            logLabel: isPinned ? "pin" : "unpin",
            hostID: row.id.hostID,
            threadID: row.id.threadID
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
    public func archive(_ row: DockRowViewModel) async -> Bool {
        guard let host = hostConfiguration(for: row) else {
            DockLog.dock.error("dock archive skipped missing host_id=\(row.id.hostID, privacy: .public) thread_id=\(DockLog.publicID(row.id.threadID), privacy: .public)")
            setActionError("Host \(row.id.hostID) is no longer configured.")
            return false
        }

        do {
            DockLog.dock.notice("dock archive action started host_id=\(host.id, privacy: .public) thread_id=\(DockLog.publicID(row.id.threadID), privacy: .public)")
            try await commandEngine.archive(row, on: host)
            setActionError(nil)
            await refresh()
            DockLog.dock.notice("dock archive action finished host_id=\(host.id, privacy: .public) thread_id=\(DockLog.publicID(row.id.threadID), privacy: .public)")
            return true
        } catch {
            DockLog.dock.error("dock archive action failed host_id=\(host.id, privacy: .public) thread_id=\(DockLog.publicID(row.id.threadID), privacy: .public) error=\(DockLog.errorSummary(error), privacy: .public)")
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
        guard let dataEngine else {
            return
        }

        await dataEngine.markChecking(host: host)
        await publishSnapshot()
        var openedConnection: (any ThreadCardStreamConnection)?
        do {
            let connection = try await streamClient.connect(to: host)
            openedConnection = connection
            streamConnections[host.id] = connection
            let snapshot = try await connection.subscribe()
            try await applySubscribedSnapshot(snapshot, host: host, connection: connection)
            startUpdateTask(host: host, connection: connection)
            await migrateMetadataHostAliases()
            await publishSnapshot()
        } catch {
            streamTasks[host.id]?.cancel()
            streamTasks[host.id] = nil
            streamConnections[host.id] = nil
            await openedConnection?.close()
            DockLog.dock.warning("dock stream open failed host_id=\(host.id, privacy: .public) error=\(DockLog.errorSummary(error), privacy: .public)")
            await dataEngine.markFailure(Self.mapRequestFailure(error), host: host)
            await publishSnapshot()
        }
    }

    private func resync(host: DockHostConfiguration, connection: any ThreadCardStreamConnection) async {
        guard let dataEngine else {
            return
        }

        do {
            let snapshot = try await connection.resync()
            try await applyResyncSnapshot(snapshot, host: host)
            await migrateMetadataHostAliases()
            await publishSnapshot()
            let rowCount = await dataEngine.rowCount(for: host)
            DockLog.dock.notice("dock stream resync finished host_id=\(host.id, privacy: .public) seq=\(snapshot.seq, privacy: .public) rows=\(rowCount, privacy: .public)")
        } catch {
            DockLog.dock.warning("dock stream resync failed host_id=\(host.id, privacy: .public) error=\(DockLog.errorSummary(error), privacy: .public)")
            await dataEngine.markFailure(Self.mapRequestFailure(error), host: host)
            await publishSnapshot()
        }
    }

    private func startUpdateTask(host: DockHostConfiguration, connection: any ThreadCardStreamConnection) {
        streamTasks[host.id]?.cancel()
        streamTasks[host.id] = Task { [weak self, host, connection] in
            do {
                for try await update in connection.updates() {
                    await self?.handleStreamUpdate(update, host: host, connection: connection)
                }
                if !Task.isCancelled {
                    await self?.handleStreamFailure(
                        DockRequestFailure.offline("Relay stream closed"),
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
        _ update: ThreadCardStreamUpdateDTO,
        host: DockHostConfiguration,
        connection: any ThreadCardStreamConnection
    ) async {
        guard let dataEngine else {
            return
        }

        let result = await dataEngine.applyUpdate(update, host: host)
        if case .needsResync(let reason) = result {
            DockLog.dock.warning("dock stream resync needed host_id=\(host.id, privacy: .public) reason=\(reason.rawValue, privacy: .public) update_kind=\(update.kind.rawValue, privacy: .public) seq=\(update.seq, privacy: .public)")
            await resync(host: host, connection: connection)
        } else {
            await migrateMetadataHostAliases()
            await publishSnapshot()
            let rowCount = await dataEngine.rowCount(for: host)
            DockLog.dock.info("dock stream update applied host_id=\(host.id, privacy: .public) update_kind=\(update.kind.rawValue, privacy: .public) seq=\(update.seq, privacy: .public) rows=\(rowCount, privacy: .public)")
            if let freshness = update.freshness,
               freshness.status != .fresh,
               rowCount > 0 {
                DockLog.dock.notice("dock stream rows retained host_id=\(host.id, privacy: .public) freshness=\(freshness.status.rawValue, privacy: .public) rows=\(rowCount, privacy: .public)")
            }
        }
    }

    private func applySubscribedSnapshot(
        _ snapshot: ThreadCardStreamUpdateDTO,
        host: DockHostConfiguration,
        connection: any ThreadCardStreamConnection
    ) async throws {
        guard let dataEngine else {
            return
        }

        switch await dataEngine.applySnapshot(snapshot, host: host) {
        case .applied:
            return
        case .needsResync(let reason):
            DockLog.dock.warning("dock stream subscribe snapshot rejected host_id=\(host.id, privacy: .public) reason=\(reason.rawValue, privacy: .public) seq=\(snapshot.seq, privacy: .public)")
            let resynced = try await connection.resync()
            try await applyResyncSnapshot(resynced, host: host)
        }
    }

    private func applyResyncSnapshot(
        _ snapshot: ThreadCardStreamUpdateDTO,
        host: DockHostConfiguration
    ) async throws {
        guard let dataEngine else {
            return
        }

        switch await dataEngine.applySnapshot(snapshot, host: host) {
        case .applied:
            return
        case .needsResync(let reason):
            throw DockRequestFailure.error("Dock stream resync returned incompatible data (\(reason.rawValue)).")
        }
    }

    private func handleStreamFailure(
        _ error: Error,
        host: DockHostConfiguration,
        connection: any ThreadCardStreamConnection
    ) async {
        DockLog.dock.warning("dock stream update failed host_id=\(host.id, privacy: .public) error=\(DockLog.errorSummary(error), privacy: .public)")
        streamConnections[host.id] = nil
        streamTasks[host.id] = nil
        await connection.close()
        await dataEngine?.markFailure(Self.mapRequestFailure(error), host: host)
        await publishSnapshot()
        let rowCount = await dataEngine?.rowCount(for: host) ?? 0
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

    private nonisolated static func mapRequestFailure(_ error: Error) -> DockRequestFailure {
        if let failure = error as? DockRequestFailure {
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

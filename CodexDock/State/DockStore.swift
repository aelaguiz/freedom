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
    private var pendingRenameTitles: [HostScopedThreadID: String] = [:]
    private weak var connectivityReporter: (any AppConnectivityReporting)?
    private let connectivityEventSink: ConnectivityEventSink?

    private struct PendingRenameSubmission: Sendable {
        let row: DockRowViewModel
        let host: DockHostConfiguration
        let threadIdentity: HostScopedThreadID
        let title: String
    }

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
        self.screenStore = DockScreenStore(
            hosts: hostViewModels,
            automationSnapshotStore: DockAutomationSnapshotConfiguration.makeIfEnabled(),
            now: now
        )
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
        self.screenStore = DockScreenStore(
            hosts: hostViewModels,
            automationSnapshotStore: DockAutomationSnapshotConfiguration.makeIfEnabled(),
            now: now
        )
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
        guard let submission = beginRename(row, to: name) else {
            return false
        }
        return await finishRename(submission)
    }

    @discardableResult
    public func renameInBackground(_ row: DockRowViewModel, to name: String) -> Bool {
        guard let submission = beginRename(row, to: name) else {
            return false
        }
        Task {
            await finishRename(submission)
        }
        return true
    }

    private func beginRename(_ row: DockRowViewModel, to name: String) -> PendingRenameSubmission? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            setActionError("Thread name cannot be empty.")
            return nil
        }

        guard let host = hostConfiguration(for: row) else {
            DockLog.dock.error("dock rename skipped missing host_id=\(row.hostID, privacy: .public) thread_id=\(DockLog.publicID(row.threadID), privacy: .public)")
            setActionError("Host \(row.hostID) is no longer configured.")
            return nil
        }

        let threadIdentity = row.threadIdentity
        pendingRenameTitles[threadIdentity] = trimmedName
        setActionError(nil)
        publishCurrentSnapshotWithPendingRenames()
        return PendingRenameSubmission(
            row: row,
            host: host,
            threadIdentity: threadIdentity,
            title: trimmedName
        )
    }

    private func finishRename(_ submission: PendingRenameSubmission) async -> Bool {
        do {
            DockLog.dock.notice("dock rename action started host_id=\(submission.host.id, privacy: .public) thread_id=\(DockLog.publicID(submission.row.threadID), privacy: .public)")
            try await commandEngine.rename(submission.row, to: submission.title, on: submission.host)
            setActionError(nil)
            DockLog.dock.notice("dock rename action finished host_id=\(submission.host.id, privacy: .public) thread_id=\(DockLog.publicID(submission.row.threadID), privacy: .public)")
            return true
        } catch {
            if pendingRenameTitles[submission.threadIdentity] == submission.title {
                pendingRenameTitles[submission.threadIdentity] = nil
                await publishSnapshot(context: "renameFailed")
            }
            DockLog.dock.error("dock rename action failed host_id=\(submission.host.id, privacy: .public) thread_id=\(DockLog.publicID(submission.row.threadID), privacy: .public) error=\(DockLog.errorSummary(error), privacy: .public)")
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
        PerformanceProbe.event(
            "dock.reload.started",
            fields: [
                "hosts": "\(hosts.count)",
                "show_loading": "\(showLoading)",
            ]
        )
        isLoading = true
        defer {
            DockSignpost.dock.endInterval("dock.reload", signpostState)
            PerformanceProbe.event(
                "dock.reload.finished",
                fields: [
                    "hosts": "\(hosts.count)",
                    "duration_ms": "\(PerformanceProbe.milliseconds(since: startedAt))",
                ]
            )
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
        await migrateMetadataHostAliases(context: "reload")
        await publishSnapshot(context: "reload")
        if case let .loaded(snapshot) = state {
            DockLog.dock.notice("dock stream reload finished hosts=\(self.hosts.count, privacy: .public) rows=\(snapshot.rowCount, privacy: .public) duration_ms=\(DockLog.milliseconds(since: startedAt), privacy: .public)")
        }
    }

    private func synchronizeStreams() async {
        let startedAt = Date()
        let validHostIDs = Set(hosts.map(\.id))
        for hostID in streamReconcilers.keys where !validHostIDs.contains(hostID) {
            await closeReconciler(hostID: hostID)
        }

        for host in hosts {
            let hostStartedAt = Date()
            let reconciler = streamReconcilers[host.id] ?? makeReconciler(for: host)
            let isNewReconciler = streamReconcilers[host.id] == nil
            if streamReconcilers[host.id] == nil {
                streamReconcilers[host.id] = reconciler
                await reconciler.start()
                await startReconcilerObservation(reconciler, host: host)
            } else {
                await reconciler.manualRefresh()
            }
            let reconcilerSnapshot = await reconciler.snapshot()
            await dataEngine?.apply(reconcilerSnapshot, host: host)
            await migrateMetadataHostAliases(context: "synchronizeStreams")
            await publishSnapshot(context: "synchronizeStreams")
            PerformanceProbe.event(
                "dock.synchronize_streams.host",
                fields: [
                    "host_id": host.id,
                    "new_reconciler": "\(isNewReconciler)",
                    "revision": "\(reconcilerSnapshot.revision)",
                    "rows": "\(reconcilerSnapshot.rows.count)",
                    "freshness": "\(reconcilerSnapshot.freshness)",
                    "duration_ms": "\(PerformanceProbe.milliseconds(since: hostStartedAt))",
                ]
            )
        }
        PerformanceProbe.event(
            "dock.synchronize_streams.finished",
            fields: [
                "hosts": "\(hosts.count)",
                "duration_ms": "\(PerformanceProbe.milliseconds(since: startedAt))",
            ]
        )
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
        let startedAt = Date()
        PerformanceProbe.event(
            "dock.host_snapshot.received",
            fields: [
                "host_id": host.id,
                "revision": "\(snapshot.revision)",
                "rows": "\(snapshot.rows.count)",
                "seq": "\(snapshot.seq)",
                "generation": "\(snapshot.generation)",
                "freshness": "\(snapshot.freshness)",
                "complete": snapshot.complete.map(String.init) ?? "none",
                "total_rows": snapshot.totalRows.map(String.init) ?? "none",
                "buffered": "\(snapshot.bufferedEnvelopeCount)",
            ]
        )
        await dataEngine?.apply(snapshot, host: host)
        await migrateMetadataHostAliases(context: "handleReconcilerSnapshot")
        await publishSnapshot(context: "handleReconcilerSnapshot")
        PerformanceProbe.event(
            "dock.host_snapshot.handled",
            fields: [
                "host_id": host.id,
                "revision": "\(snapshot.revision)",
                "rows": "\(snapshot.rows.count)",
                "duration_ms": "\(PerformanceProbe.milliseconds(since: startedAt))",
            ]
        )
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

    private func publishSnapshot(context: String = "unspecified") async {
        guard !hosts.isEmpty else {
            return
        }
        let startedAt = Date()
        let modelStartedAt = Date()
        guard let snapshot = await dataEngine?.snapshot(now: now) else {
            return
        }
        let modelDurationMilliseconds = PerformanceProbe.milliseconds(since: modelStartedAt)
        let pendingRenameStartedAt = Date()
        let displayedSnapshot = snapshotApplyingPendingRenames(to: snapshot)
        let pendingRenameDurationMilliseconds = PerformanceProbe.milliseconds(since: pendingRenameStartedAt)
        let screenPublishStartedAt = Date()
        let didPublish = publishDisplayedSnapshot(displayedSnapshot, context: context)
        let screenPublishDurationMilliseconds = PerformanceProbe.milliseconds(since: screenPublishStartedAt)
        PerformanceProbe.event(
            "dock.store.publish_snapshot",
            fields: [
                "context": context,
                "published": "\(didPublish)",
                "hosts": "\(displayedSnapshot.hosts.count)",
                "rows": "\(displayedSnapshot.rows.count)",
                "partial": "\(displayedSnapshot.isPartial)",
                "pending_renames": "\(pendingRenameTitles.count)",
                "model_ms": "\(modelDurationMilliseconds)",
                "pending_rename_ms": "\(pendingRenameDurationMilliseconds)",
                "screen_publish_ms": "\(screenPublishDurationMilliseconds)",
                "duration_ms": "\(PerformanceProbe.milliseconds(since: startedAt))",
            ]
        )
    }

    private func publishCurrentSnapshotWithPendingRenames() {
        guard case .loaded(let snapshot) = state else {
            return
        }
        let displayedSnapshot = snapshotApplyingPendingRenames(
            to: snapshot,
            clearsConfirmedPendingRenames: false
        )
        _ = publishDisplayedSnapshot(displayedSnapshot, context: "pendingRename")
    }

    @discardableResult
    private func publishDisplayedSnapshot(
        _ displayedSnapshot: DockSnapshot,
        context: String
    ) -> Bool {
        let newState = DockStoreState.loaded(displayedSnapshot)
        guard state != newState else {
            PerformanceProbe.event(
                "dock.store.publish_snapshot.noop",
                fields: [
                    "context": context,
                    "rows": "\(displayedSnapshot.rows.count)",
                    "hosts": "\(displayedSnapshot.hosts.count)",
                    "partial": "\(displayedSnapshot.isPartial)",
                ]
            )
            return false
        }

        state = newState
        screenStore.publish(snapshot: displayedSnapshot)
        publishConnectivity(for: state)
        return true
    }

    private func snapshotApplyingPendingRenames(
        to snapshot: DockSnapshot,
        clearsConfirmedPendingRenames: Bool = true
    ) -> DockSnapshot {
        guard !pendingRenameTitles.isEmpty else {
            return snapshot
        }

        if clearsConfirmedPendingRenames {
            clearConfirmedPendingRenames(from: snapshot)
        }
        guard !pendingRenameTitles.isEmpty else {
            return snapshot
        }

        var didApplyPendingRename = false
        let rows = snapshot.rows.map { row in
            guard let pendingTitle = pendingRenameTitles[row.threadIdentity],
                  row.title != pendingTitle else {
                return row
            }
            didApplyPendingRename = true
            return row.withTitle(pendingTitle)
        }

        guard didApplyPendingRename else {
            return snapshot
        }
        return DockSnapshot(
            host: snapshot.host,
            hosts: snapshot.hosts,
            hostStates: snapshot.hostStates,
            hostIdentityResolver: snapshot.hostIdentityResolver,
            rows: rows,
            isPartial: snapshot.isPartial
        )
    }

    private func clearConfirmedPendingRenames(from snapshot: DockSnapshot) {
        for row in snapshot.rows where pendingRenameTitles[row.threadIdentity] == row.title {
            pendingRenameTitles[row.threadIdentity] = nil
        }
    }

    private func migrateMetadataHostAliases(context: String = "unspecified") async {
        let startedAt = Date()
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
        PerformanceProbe.event(
            "dock.metadata_alias_migration",
            fields: [
                "context": context,
                "metadata_entries": "\(localMetadata.count)",
                "duration_ms": "\(PerformanceProbe.milliseconds(since: startedAt))",
            ]
        )
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

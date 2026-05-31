import Foundation

public enum ClientRuntimeScreenKind: String, Equatable, Sendable {
    case dock
    case threadDetail
    case archive
    case hosts
    case connectivity
}

public struct ClientRuntimeScreenFactory: Equatable, Sendable {
    public let kind: ClientRuntimeScreenKind
    public let hostCount: Int
    public let usesRuntimeConnectivitySink: Bool

    public init(
        kind: ClientRuntimeScreenKind,
        hostCount: Int,
        usesRuntimeConnectivitySink: Bool
    ) {
        self.kind = kind
        self.hostCount = hostCount
        self.usesRuntimeConnectivitySink = usesRuntimeConnectivitySink
    }
}

public struct ClientRuntime: Sendable {
    public let registry: HostRegistry
    public let connectivityEventSink: ConnectivityEventSink

    private let now: @Sendable () -> Date

    public init(
        registry: HostRegistry,
        connectivityEventSink: ConnectivityEventSink = ConnectivityEventSink(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.registry = registry
        self.connectivityEventSink = connectivityEventSink
        self.now = now
    }

    public func makeDockScreenStoreFactory() -> ClientRuntimeScreenFactory {
        screenFactory(kind: .dock)
    }

    @MainActor
    public func makeDockStore(
        streamClient: any ThreadCardStreamConnecting = AppServerThreadCardStreamClient(),
        archiver: any ThreadArchiveCommanding = AppServerThreadCommandClient(),
        metadataStore: any LocalThreadMetadataStoring = FileLocalThreadMetadataStore(),
        streamReconnectDelay: Duration = CodexDockConstants.Dock.autoRefreshInterval
    ) -> DockStore {
        DockStore(
            registry: registry,
            streamClient: streamClient,
            archiver: archiver,
            metadataStore: metadataStore,
            streamReconnectDelay: streamReconnectDelay,
            connectivityEventSink: connectivityEventSink,
            now: now
        )
    }

    public func makeThreadDetailScreenStoreFactory() -> ClientRuntimeScreenFactory {
        screenFactory(kind: .threadDetail)
    }

    @MainActor
    public func makeThreadDetailStore(
        host: DockHostConfiguration,
        row: DockRowViewModel,
        factory: any ThreadDetailSessionMaking = AppServerThreadDetailSessionFactory(),
        realtimeTranscriptionService: (any RealtimeTranscriptionServicing)? = nil,
        liveVoiceCaptureController: (any LiveVoiceCaptureControlling)? = nil,
        lifecycleCoordinator: AppLifecycleCoordinator? = nil,
        connectivityReporter: (any AppConnectivityReporting)? = nil,
        hostIdentityResolver: DockHostIdentityResolver? = nil
    ) -> ThreadDetailStore {
        ThreadDetailStore(
            host: host,
            row: row,
            factory: factory,
            realtimeTranscriptionService: realtimeTranscriptionService,
            liveVoiceCaptureController: liveVoiceCaptureController,
            lifecycleCoordinator: lifecycleCoordinator,
            connectivityReporter: connectivityReporter,
            connectivityEventSink: connectivityEventSink,
            hostIdentityResolver: hostIdentityResolver,
            now: now
        )
    }

    public func makeArchiveScreenStoreFactory() -> ClientRuntimeScreenFactory {
        screenFactory(kind: .archive)
    }

    @MainActor
    public func makeArchiveStore(
        streamClient: any ThreadCardStreamConnecting = AppServerThreadCardStreamClient(view: .archive),
        archiver: any ThreadArchiveCommanding = AppServerThreadCommandClient(),
        metadataStore: any LocalThreadMetadataStoring = FileLocalThreadMetadataStore()
    ) -> ArchiveStore {
        ArchiveStore(
            registry: registry,
            streamClient: streamClient,
            archiver: archiver,
            metadataStore: metadataStore,
            connectivityEventSink: connectivityEventSink,
            now: now
        )
    }

    public func makeHostSettingsScreenStoreFactory() -> ClientRuntimeScreenFactory {
        screenFactory(kind: .hosts)
    }

    @MainActor
    public func makeHostSettingsStore(
        tester: any HostConnectionTesting = CardStreamHostConnectionTester(),
        configurationStore: any LocalDockConfigurationStoring = FileLocalDockConfigurationStore()
    ) -> HostSettingsStore {
        HostSettingsStore(
            registry: registry,
            tester: tester,
            configurationStore: configurationStore,
            connectivityEventSink: connectivityEventSink,
            now: now
        )
    }

    public func makeConnectivityScreenStoreFactory() -> ClientRuntimeScreenFactory {
        screenFactory(kind: .connectivity)
    }

    @MainActor
    public func makeConnectivityScreenStore() -> ConnectivityScreenStore {
        ConnectivityScreenStore(
            registry: registry,
            eventSink: connectivityEventSink,
            now: now
        )
    }

    public func currentDate() -> Date {
        now()
    }

    private func screenFactory(kind: ClientRuntimeScreenKind) -> ClientRuntimeScreenFactory {
        ClientRuntimeScreenFactory(
            kind: kind,
            hostCount: registry.hosts.count,
            usesRuntimeConnectivitySink: true
        )
    }
}

import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

public struct CodexDockRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var dockStore: DockStore
    @StateObject private var archiveStore: ArchiveStore
    @StateObject private var archiveCleanupStore: ArchiveCleanupStore
    @StateObject private var hostsStore: HostSettingsStore
    @StateObject private var connectivityStore: AppConnectivityStore
    @StateObject private var connectivityScreenStore: ConnectivityScreenStore
    @StateObject private var lifecycleCoordinator: AppLifecycleCoordinator
    private let runtime: ClientRuntime?
    private let usesRuntimeConnectivitySink: Bool
    private let threadDetailFactory: any ThreadDetailSessionMaking
    @State private var foregroundResumeTask: Task<Void, Never>?
    @State private var activeTaskSheet: DockTaskSheet?

    public init(store: DockStore) {
        self.threadDetailFactory = AppServerThreadDetailSessionFactory()
        _dockStore = StateObject(wrappedValue: store)
        if let host = store.hostConfiguration,
           let registry = try? HostRegistry(hosts: [host]) {
            let runtime = ClientRuntime(registry: registry)
            self.runtime = runtime
            self.usesRuntimeConnectivitySink = false
            _archiveStore = StateObject(wrappedValue: ArchiveStore(registry: registry))
            _archiveCleanupStore = StateObject(wrappedValue: ArchiveCleanupStore(registry: registry, cardStateProvider: store))
            _hostsStore = StateObject(wrappedValue: HostSettingsStore(registry: registry))
            _connectivityStore = StateObject(wrappedValue: AppConnectivityStore(registry: registry))
            _connectivityScreenStore = StateObject(
                wrappedValue: runtime.makeConnectivityScreenStore()
            )
        } else {
            self.runtime = nil
            self.usesRuntimeConnectivitySink = false
            let error = DockHostConfigurationError.missingEndpoint
            _archiveStore = StateObject(wrappedValue: ArchiveStore(configurationError: error))
            _archiveCleanupStore = StateObject(wrappedValue: ArchiveCleanupStore(configurationError: error))
            _hostsStore = StateObject(wrappedValue: HostSettingsStore(configurationError: error))
            _connectivityStore = StateObject(wrappedValue: AppConnectivityStore(configurationError: error))
            _connectivityScreenStore = StateObject(
                wrappedValue: ConnectivityScreenStore(configurationError: error)
            )
        }
        _lifecycleCoordinator = StateObject(wrappedValue: AppLifecycleCoordinator())
    }

    public init(
        registry: HostRegistry,
        client: AppServerThreadCommandClient = AppServerThreadCommandClient(),
        streamClient: any ThreadCardStreamConnecting = AppServerThreadCardStreamClient(),
        threadDetailFactory: any ThreadDetailSessionMaking = AppServerThreadDetailSessionFactory(),
        metadataStore: any LocalThreadMetadataStoring = FileLocalThreadMetadataStore(),
        lifecycleCoordinator: AppLifecycleCoordinator = AppLifecycleCoordinator(),
        connectivityStore: AppConnectivityStore? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.init(
            runtime: ClientRuntime(registry: registry, now: now),
            client: client,
            streamClient: streamClient,
            threadDetailFactory: threadDetailFactory,
            metadataStore: metadataStore,
            lifecycleCoordinator: lifecycleCoordinator,
            connectivityStore: connectivityStore
        )
    }

    public init(
        runtime: ClientRuntime,
        client: AppServerThreadCommandClient = AppServerThreadCommandClient(),
        streamClient: any ThreadCardStreamConnecting = AppServerThreadCardStreamClient(),
        threadDetailFactory: any ThreadDetailSessionMaking = AppServerThreadDetailSessionFactory(),
        metadataStore: any LocalThreadMetadataStoring = FileLocalThreadMetadataStore(),
        lifecycleCoordinator: AppLifecycleCoordinator = AppLifecycleCoordinator(),
        connectivityStore: AppConnectivityStore? = nil
    ) {
        let registry = runtime.registry
        self.runtime = runtime
        self.usesRuntimeConnectivitySink = true
        self.threadDetailFactory = threadDetailFactory
        let connectivityStore = connectivityStore ?? AppConnectivityStore(registry: registry, now: runtime.currentDate)
        let dockStore = runtime.makeDockStore(
            streamClient: streamClient,
            archiver: client,
            metadataStore: metadataStore
        )
        _dockStore = StateObject(
            wrappedValue: dockStore
        )
        _archiveStore = StateObject(
            wrappedValue: runtime.makeArchiveStore(
                streamClient: AppServerThreadCardStreamClient(view: .archive),
                archiver: client,
                metadataStore: metadataStore
            )
        )
        _archiveCleanupStore = StateObject(
            wrappedValue: ArchiveCleanupStore(
                registry: registry,
                cardStateProvider: dockStore,
                archiver: client,
                now: runtime.currentDate
            )
        )
        _hostsStore = StateObject(
            wrappedValue: runtime.makeHostSettingsStore()
        )
        _connectivityStore = StateObject(wrappedValue: connectivityStore)
        _connectivityScreenStore = StateObject(wrappedValue: runtime.makeConnectivityScreenStore())
        _lifecycleCoordinator = StateObject(wrappedValue: lifecycleCoordinator)
    }

    public init(configurationError error: Error) {
        self.runtime = nil
        self.usesRuntimeConnectivitySink = false
        self.threadDetailFactory = AppServerThreadDetailSessionFactory()
        _dockStore = StateObject(wrappedValue: DockStore(configurationError: error))
        _archiveStore = StateObject(wrappedValue: ArchiveStore(configurationError: error))
        _archiveCleanupStore = StateObject(wrappedValue: ArchiveCleanupStore(configurationError: error))
        _hostsStore = StateObject(wrappedValue: HostSettingsStore(configurationError: error))
        _connectivityStore = StateObject(wrappedValue: AppConnectivityStore(configurationError: error))
        _connectivityScreenStore = StateObject(
            wrappedValue: ConnectivityScreenStore(configurationError: error)
        )
        _lifecycleCoordinator = StateObject(wrappedValue: AppLifecycleCoordinator())
    }

    public var body: some View {
        DockView(
            store: dockStore,
            lifecycleCoordinator: lifecycleCoordinator,
            connectivityReporter: connectivityStore,
            connectivityStore: connectivityStore,
            runtime: runtime,
            threadDetailFactory: threadDetailFactory,
            onOpenArchiveCleanup: {
                activeTaskSheet = .archiveCleanup
            },
            onOpenArchivedThreads: {
                activeTaskSheet = .archivedThreads
            },
            onOpenSystemHealth: {
                activeTaskSheet = .systemHealth
            },
            onOpenRelaySettings: {
                activeTaskSheet = .relaySettings
            },
            onArchiveSucceeded: {
                await archiveStore.refresh()
            }
        )
        .tint(.blue)
        .accessibilityElement(children: .contain)
        .codexAutomationID(AutomationID.App.root)
        .accessibilityValue(activeTaskSheet?.rawValue ?? "dock")
        .sheet(item: $activeTaskSheet) { sheet in
            taskSheet(sheet)
                .dockTaskSheetPresentation()
        }
        .task {
            if usesRuntimeConnectivitySink {
                connectivityScreenStore.start(mirroring: connectivityStore)
            }
            bindConnectivity()
            await runDockRefreshLoop()
        }
        .onChange(of: scenePhase) { _, scenePhase in
            handleScenePhase(scenePhase)
        }
        .onChange(of: hostsStore.registry) { _, registry in
            guard let registry else {
                return
            }
            Task {
                connectivityStore.configure(registry)
                await connectivityScreenStore.configure(registry)
                await dockStore.updateRegistry(registry)
                await archiveStore.updateRegistry(registry)
                await archiveCleanupStore.updateRegistry(registry)
            }
        }
    }

    @ViewBuilder
    private func taskSheet(_ sheet: DockTaskSheet) -> some View {
        switch sheet {
        case .archiveCleanup:
            ArchiveCleanupView(
                store: archiveCleanupStore,
                onOpenArchivedThreads: {
                    activeTaskSheet = .archivedThreads
                },
                onArchiveSucceeded: {
                    await dockStore.refresh()
                    await archiveStore.refresh()
                },
                onClose: {
                    activeTaskSheet = nil
                }
            )
        case .archivedThreads:
            ArchiveView(
                store: archiveStore,
                title: "Archived Threads",
                threadDetailFactory: threadDetailFactory,
                onClose: {
                    activeTaskSheet = nil
                },
                onRestoreSucceeded: {
                    await dockStore.refresh()
                }
            )
        case .systemHealth:
            SystemHealthView(
                store: connectivityStore,
                onOpenRelaySettings: {
                    activeTaskSheet = .relaySettings
                },
                relaySettingsDestination: {
                    HostsView(
                        store: hostsStore,
                        title: "Relay Settings",
                        hidesEditorUntilRequested: true,
                        usesNavigationStack: false
                    )
                },
                onClose: {
                    activeTaskSheet = nil
                }
            )
        case .relaySettings:
            HostsView(
                store: hostsStore,
                title: "Relay Settings",
                hidesEditorUntilRequested: true,
                onClose: {
                    activeTaskSheet = nil
                }
            )
        }
    }

    private func bindConnectivity() {
        guard !usesRuntimeConnectivitySink else {
            return
        }
        dockStore.setConnectivityReporter(connectivityStore)
        archiveStore.setConnectivityReporter(connectivityStore)
        hostsStore.setConnectivityReporter(connectivityStore)
    }

    private func runDockRefreshLoop() async {
        while !Task.isCancelled, !lifecycleCoordinator.allowsForegroundWork {
            do {
                try await Task.sleep(for: CodexDockConstants.AppServer.foregroundPollInterval)
            } catch {
                return
            }
        }

        await dockStore.load()
    }

    private func handleScenePhase(_ scenePhase: ScenePhase) {
        lifecycleCoordinator.handle(appScenePhase(from: scenePhase))
        connectivityStore.reportLifecycle(lifecycleCoordinator.snapshot)

        guard lifecycleCoordinator.snapshot.phase == .foregroundResuming else {
            return
        }

        foregroundResumeTask?.cancel()
        foregroundResumeTask = Task {
            await resumeForegroundWork()
        }
    }

    private func resumeForegroundWork() async {
        guard lifecycleCoordinator.snapshot.phase == .foregroundResuming else {
            return
        }

        await dockStore.refresh()
        await archiveStore.refresh()
        lifecycleCoordinator.finishForegroundResume()
        connectivityStore.reportLifecycle(lifecycleCoordinator.snapshot)
    }

    private func appScenePhase(from scenePhase: ScenePhase) -> AppScenePhase {
        switch scenePhase {
        case .active:
            return .active
        case .inactive:
            return .inactive
        case .background:
            return .background
        @unknown default:
            return .inactive
        }
    }
}

public struct DockView: View {
    @ObservedObject private var screenStore: DockScreenStore
    private let store: DockStore
    private let lifecycleCoordinator: AppLifecycleCoordinator?
    private let connectivityReporter: (any AppConnectivityReporting)?
    private let connectivityStore: AppConnectivityStore?
    private let runtime: ClientRuntime?
    private let threadDetailFactory: any ThreadDetailSessionMaking
    private let onOpenArchiveCleanup: @MainActor () -> Void
    private let onOpenArchivedThreads: @MainActor () -> Void
    private let onOpenSystemHealth: @MainActor () -> Void
    private let onOpenRelaySettings: @MainActor () -> Void
    private let onArchiveSucceeded: @MainActor () async -> Void
    @State private var isFilterSurfacePresented = false
    @State private var isPinnedCollapsed = false
    @State private var selectedDetailRow: DockRowViewModel?
    @State private var collapsedHostGroupIDs: Set<String> = []
    @State private var collapsedBranchGroupIDs: Set<String> = []
    @FocusState private var isSearchFocused: Bool

    public init(
        store: DockStore,
        lifecycleCoordinator: AppLifecycleCoordinator? = nil,
        connectivityReporter: (any AppConnectivityReporting)? = nil,
        connectivityStore: AppConnectivityStore? = nil,
        runtime: ClientRuntime? = nil,
        threadDetailFactory: any ThreadDetailSessionMaking = AppServerThreadDetailSessionFactory(),
        onOpenArchiveCleanup: @escaping @MainActor () -> Void = {},
        onOpenArchivedThreads: @escaping @MainActor () -> Void = {},
        onOpenSystemHealth: @escaping @MainActor () -> Void = {},
        onOpenRelaySettings: @escaping @MainActor () -> Void = {},
        onArchiveSucceeded: @escaping @MainActor () async -> Void = {}
    ) {
        self.store = store
        _screenStore = ObservedObject(wrappedValue: store.screenStore)
        self.lifecycleCoordinator = lifecycleCoordinator
        self.connectivityReporter = connectivityReporter
        self.connectivityStore = connectivityStore
        self.runtime = runtime
        self.threadDetailFactory = threadDetailFactory
        self.onOpenArchiveCleanup = onOpenArchiveCleanup
        self.onOpenArchivedThreads = onOpenArchivedThreads
        self.onOpenSystemHealth = onOpenSystemHealth
        self.onOpenRelaySettings = onOpenRelaySettings
        self.onArchiveSucceeded = onArchiveSucceeded
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    controls
                    content
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 104)
            }
            .background(dockBackgroundColor)
            .dockNavigationChrome()
            .refreshable {
                await store.refresh()
            }
            .navigationDestination(isPresented: detailNavigationBinding) {
                selectedDetailDestination
            }
        }
        .sheet(isPresented: $isFilterSurfacePresented) {
            DockFilterSurfaceView(
                filters: filtersBinding,
                projection: currentProjection
            )
        }
    }

    private var selectedLens: DockLensID {
        screenStore.options.lens
    }

    private var searchText: String {
        screenStore.searchText
    }

    private var filterState: DockFilterState {
        screenStore.options.filters
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Text("Dock")
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityValue(dockScreenValue)
                    .codexAutomationID(AutomationID.Dock.root)

                Spacer(minLength: 12)

                if let connectivityStore {
                    GlobalConnectivityIndicatorView(
                        store: connectivityStore,
                        onOpenSystemHealth: onOpenSystemHealth
                    )
                        .fixedSize(horizontal: true, vertical: false)
                }

                DockTaskMenuView(
                    onOpenArchiveCleanup: onOpenArchiveCleanup,
                    onOpenArchivedThreads: onOpenArchivedThreads,
                    onOpenSystemHealth: onOpenSystemHealth,
                    onOpenRelaySettings: onOpenRelaySettings
                )
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            searchControl
            lensControls
            activeFilterSummary
        }
    }

    private var searchControl: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            searchField
            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    screenStore.setSearchText("")
                    isSearchFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
                .codexAutomationID(AutomationID.Dock.clearSearchButton)
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var lensControls: some View {
        HStack(spacing: 8) {
            ForEach(DockLensID.allCases) { lens in
                Button {
                    screenStore.setLens(lens)
                } label: {
                    Text(lens.title)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                }
                .buttonStyle(.plain)
                .foregroundStyle(selectedLens == lens ? .white : .primary)
                .background(
                    selectedLens == lens ? Color.blue : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: selectedLens == lens ? 0 : 1)
                }
                .accessibilityAddTraits(selectedLens == lens ? .isSelected : [])
                .codexAutomationID(AutomationID.Dock.lensButton(lens.rawValue))
            }

            Button {
                isFilterSurfacePresented = true
            } label: {
                Image(systemName: filterState.isDefault ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    .frame(width: 42, height: 38)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Filters")
            .accessibilityValue(filterState.activeFilterCount == 0 ? "No active filters" : "\(filterState.activeFilterCount) active filters")
            .accessibilityAddTraits(isFilterSurfacePresented ? .isSelected : [])
            .codexAutomationID(AutomationID.Dock.filterButton)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Dock lenses")
        .accessibilityValue(selectedLens.title)
        .codexAutomationID(AutomationID.Dock.lensPicker)
    }

    private var activeFilterSummary: some View {
        HStack(spacing: 8) {
            Text(activeSummaryText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .layoutPriority(1)

            Spacer(minLength: 8)

            if !filterState.isDefault {
                Button("Clear") {
                    screenStore.setFilters(.default)
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .codexAutomationID(AutomationID.Dock.clearFiltersButton)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(activeSummaryText)
        .codexAutomationID(AutomationID.Dock.activeFilterSummary)
    }

    @ViewBuilder
    private var searchField: some View {
        #if os(iOS)
        TextField("Search sessions, repo, branch, host", text: searchTextBinding)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($isSearchFocused)
            .codexAutomationID(AutomationID.Dock.searchField)
        #else
        TextField("Search sessions, repo, branch, host", text: searchTextBinding)
            .codexAutomationID(AutomationID.Dock.searchField)
        #endif
    }

    private var dockBackgroundColor: Color {
        #if os(iOS)
        Color(uiColor: .systemGroupedBackground)
        #elseif os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(.background)
        #endif
    }

    private var searchTextBinding: Binding<String> {
        Binding(
            get: { screenStore.searchText },
            set: { screenStore.setSearchText($0) }
        )
    }

    private var filtersBinding: Binding<DockFilterState> {
        Binding(
            get: { screenStore.options.filters },
            set: { screenStore.setFilters($0) }
        )
    }

    private var currentProjection: DockCardProjection? {
        if case .loaded(let renderSnapshot) = screenStore.state {
            return renderSnapshot.projection
        }
        return nil
    }

    private var currentSnapshot: DockSnapshot? {
        if case .loaded(let renderSnapshot) = screenStore.state {
            return renderSnapshot.snapshot
        }
        return nil
    }

    private var detailNavigationBinding: Binding<Bool> {
        Binding(
            get: {
                selectedDetailRow != nil
            },
            set: { isPresented in
                if !isPresented {
                    selectedDetailRow = nil
                }
            }
        )
    }

    @ViewBuilder
    private var selectedDetailDestination: some View {
        if let selectedDetailRow,
           let host = store.hostConfiguration(for: selectedDetailRow) {
            SessionDetailView(
                store: makeThreadDetailStore(
                    host: host,
                    row: selectedDetailRow,
                    hostIdentityResolver: currentSnapshot?.hostIdentityResolver
                )
            )
        } else {
            DockMessageView(
                icon: "exclamationmark.triangle",
                title: "Thread unavailable",
                message: "This thread's host is no longer configured."
            )
        }
    }

    private func makeThreadDetailStore(
        host: DockHostConfiguration,
        row: DockRowViewModel,
        hostIdentityResolver: DockHostIdentityResolver?
    ) -> ThreadDetailStore {
        if let runtime {
            return runtime.makeThreadDetailStore(
                host: host,
                row: row,
                factory: threadDetailFactory,
                lifecycleCoordinator: lifecycleCoordinator,
                connectivityReporter: connectivityReporter,
                hostIdentityResolver: hostIdentityResolver
            )
        }
        return ThreadDetailStore(
            host: host,
            row: row,
            factory: threadDetailFactory,
            lifecycleCoordinator: lifecycleCoordinator,
            connectivityReporter: connectivityReporter,
            hostIdentityResolver: hostIdentityResolver
        )
    }

    private var activeSummaryText: String {
        currentProjection?.summary.text ?? "0 shown · Hosts: Any · Branches: Any · Status: Any · Repo: Any · Source: Any"
    }

    @ViewBuilder
    private var content: some View {
        switch screenStore.state {
        case let .configurationError(message):
            DockMessageView(
                icon: "exclamationmark.triangle",
                title: "Relay not configured",
                message: message,
                automationID: AutomationID.Dock.state(.configurationError)
            )
        case let .idle(hosts):
            hostStatusList(hosts.map { DockHostStateViewModel(host: $0, status: .empty) }, stateTitle: "Ready")
        case let .loading(hosts):
            hostStatusList(hosts.map { DockHostStateViewModel(host: $0, status: .checking) }, stateTitle: "Sessions not loaded yet")
        case let .loaded(renderSnapshot):
            loadedContent(renderSnapshot)
        }
    }

    private func loadedContent(_ renderSnapshot: DockRenderSnapshot) -> some View {
        let snapshot = renderSnapshot.snapshot
        let projection = renderSnapshot.projection

        return VStack(alignment: .leading, spacing: 16) {
            if let actionError = screenStore.actionError {
                ActionErrorBanner(
                    message: actionError,
                    automationID: AutomationID.Dock.state(.actionError)
                )
            }

            if let emptyReason = projection.emptyReason {
                if shouldShowPinnedHiddenHint(projection) {
                    DockPinnedHiddenHintView(projection: projection, searchText: searchText)
                }
                DockMessageView(
                    icon: "line.3.horizontal.decrease.circle",
                    title: emptyReason.title,
                    message: emptyReason.message,
                    automationID: AutomationID.Dock.state(.empty)
                )
                let hostStates = contextualHostStates(in: snapshot)
                if !hostStates.isEmpty {
                    hostStatusList(hostStates, stateTitle: "Host status")
                }
            } else {
                projectedContent(
                    projection,
                    snapshot: snapshot,
                    revision: renderSnapshot.revision
                )
            }
        }
    }

    @ViewBuilder
    private func projectedContent(
        _ projection: DockCardProjection,
        snapshot: DockSnapshot,
        revision: RenderRevision
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !projection.pinnedRows.isEmpty {
                DockPinnedSectionView(
                    projection: projection,
                    isCollapsed: $isPinnedCollapsed,
                    onMove: { rows in Task { await store.reorderPinnedRows(rows) } },
                    onUnpin: { row in Task { await store.setPinned(false, for: row) } },
                    onOpen: { row in selectedDetailRow = row },
                    rowContent: { row in dockPinnedRow(row) }
                )
                if shouldShowPinnedBodyDivider(projection, snapshot: snapshot) {
                    Divider()
                        .codexAutomationID(AutomationID.Dock.pinnedBodyDivider)
                }
            } else if shouldShowPinnedHiddenHint(projection) {
                DockPinnedHiddenHintView(projection: projection, searchText: searchText)
                if shouldShowPinnedBodyDivider(projection, snapshot: snapshot) {
                    Divider()
                        .codexAutomationID(AutomationID.Dock.pinnedBodyDivider)
                }
            }

            switch selectedLens {
            case .newest:
                LazyVStack(spacing: 10) {
                    ForEach(projection.rows) { row in
                        dockRow(row, resetToken: revision)
                    }
                    ForEach(contextualHostStates(in: snapshot)) { hostState in
                        hostContextRow(
                            hostState,
                            automationID: AutomationID.Dock.hostSummary(hostID: hostState.host.id)
                        )
                    }
                }
            case .host:
                LazyVStack(spacing: 12) {
                    ForEach(projection.groups) { group in
                        projectionGroup(
                            group,
                            collapsedIDs: $collapsedHostGroupIDs,
                            resetToken: revision
                        )
                    }
                }
            case .branch:
                LazyVStack(spacing: 12) {
                    ForEach(projection.groups) { group in
                        projectionGroup(
                            group,
                            collapsedIDs: $collapsedBranchGroupIDs,
                            resetToken: revision
                        )
                    }
                    ForEach(contextualHostStates(in: snapshot)) { hostState in
                        hostContextRow(
                            hostState,
                            automationID: AutomationID.Dock.hostSummary(hostID: hostState.host.id)
                        )
                    }
                }
            }
        }
    }

    private func shouldShowPinnedHiddenHint(_ projection: DockCardProjection) -> Bool {
        projection.pinnedRows.isEmpty && projection.pinnedSummary.hiddenByScopeCount > 0
    }

    private func shouldShowPinnedBodyDivider(
        _ projection: DockCardProjection,
        snapshot: DockSnapshot
    ) -> Bool {
        if !contextualHostStates(in: snapshot).isEmpty {
            return true
        }
        switch selectedLens {
        case .newest:
            return !projection.rows.isEmpty
        case .host, .branch:
            return projection.groups.contains { !$0.rows.isEmpty || $0.isUnavailable }
        }
    }

    private var dockScreenValue: String {
        switch screenStore.state {
        case .configurationError:
            return "configuration-error"
        case .idle(let hosts):
            return "idle; hosts=\(hosts.count); lens=\(selectedLens.rawValue); filters=\(filterState.activeFilterCount)"
        case .loading(let hosts):
            return "loading; hosts=\(hosts.count); lens=\(selectedLens.rawValue); filters=\(filterState.activeFilterCount)"
        case .loaded(let renderSnapshot):
            let snapshot = renderSnapshot.snapshot
            let pinnedCount = renderSnapshot.projection.pinnedRows.count
            return "loaded; rows=\(snapshot.rowCount); pinned=\(pinnedCount); lens=\(selectedLens.rawValue); search=\(!searchText.isEmpty); filters=\(filterState.activeFilterCount); \(activeSummaryText)"
        }
    }

    private func dockRow(
        _ row: DockRowViewModel,
        showsPinIndicator: Bool = false,
        resetToken: RenderRevision = .zero
    ) -> some View {
        DockSwipeActionRow(
            row: row,
            actionID: AutomationID.Dock.rowAction(
                hostID: row.id.hostID,
                threadID: row.id.threadID,
                action: row.isPinned ? .unpin : .pin
            ),
            resetToken: resetToken,
            onTogglePinned: {
                Task {
                    await store.setPinned(!row.isPinned, for: row)
                }
            },
            canOpen: store.hostConfiguration(for: row) != nil,
            onOpen: {
                selectedDetailRow = row
            }
        ) {
            dockRowContent(row, showsPinIndicator: showsPinIndicator)
        }
        .accessibilityAction(named: Text(row.isPinned ? "Unpin thread" : "Pin thread")) {
            Task {
                await store.setPinned(!row.isPinned, for: row)
            }
        }
    }

    private func dockPinnedRow(_ row: DockRowViewModel) -> some View {
        dockRowContent(
            row,
            showsPinIndicator: true,
            automationID: AutomationID.Dock.row(hostID: row.id.hostID, threadID: row.id.threadID),
            showsContextMenu: false
        )
        .accessibilityAction(named: Text("Unpin thread")) {
            Task {
                await store.setPinned(false, for: row)
            }
        }
    }

    @ViewBuilder
    private func dockRowContent(
        _ row: DockRowViewModel,
        showsPinIndicator: Bool,
        automationID: AutomationID? = nil,
        showsContextMenu: Bool = true
    ) -> some View {
        let content = DockRowView(row: row, showsPinIndicator: showsPinIndicator, automationID: automationID)
            .accessibilityValue(row.automationValue)

        if showsContextMenu {
            content
                .contextMenu {
                    rowContextMenu(row)
                }
        } else {
            content
        }
    }

    private func projectionGroup(
        _ group: DockProjectionGroupViewModel,
        collapsedIDs: Binding<Set<String>>,
        resetToken: RenderRevision
    ) -> some View {
        let isCollapsed = collapsedIDs.wrappedValue.contains(group.id)
        let groupAutomationID = group.kind == .host
            ? AutomationID.Dock.hostGroup(group.id)
            : AutomationID.Dock.branchGroup(group.id)
        let toggleAutomationID = group.kind == .host
            ? AutomationID.Dock.hostToggle(group.id)
            : AutomationID.Dock.branchToggle(group.id)

        return VStack(alignment: .leading, spacing: 8) {
            Button {
                if isCollapsed {
                    collapsedIDs.wrappedValue.remove(group.id)
                } else {
                    collapsedIDs.wrappedValue.insert(group.id)
                }
            } label: {
                DockGroupHeaderView(group: group, isCollapsed: isCollapsed)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(isCollapsed ? "Collapsed" : "Expanded")
            .codexAutomationID(toggleAutomationID)

            if group.isUnavailable,
               let hostID = group.hostIDs.first,
               let hostState = currentHostState(hostID: hostID) {
                hostFailureRow(hostState, automationID: groupAutomationID)
            } else if let hostID = group.hostIDs.first,
                      let hostState = currentHostState(hostID: hostID),
                      hostState.status == .checking {
                HostLoadingRow(hostState: hostState)
                    .codexAutomationID(groupAutomationID)
            } else if !isCollapsed {
                LazyVStack(spacing: 10) {
                    ForEach(group.rows) { row in
                        dockRow(row, resetToken: resetToken)
                    }
                }
            }
        }
        .codexAutomationID(groupAutomationID)
    }

    private func currentHostState(hostID: String) -> DockHostStateViewModel? {
        guard case .loaded(let renderSnapshot) = screenStore.state else {
            return nil
        }
        return renderSnapshot.snapshot.hostStates.first { $0.host.id == hostID }
            ?? renderSnapshot.snapshot.hostIdentityResolver.state(
                forAlias: hostID,
                in: renderSnapshot.snapshot.hostStates
            )
    }

    private func contextualHostStates(in snapshot: DockSnapshot) -> [DockHostStateViewModel] {
        snapshot.hostStates.filter { hostState in
            hostState.status == .checking || hostState.status.isPartial || hostState.status.isUnavailable
        }
    }

    private func hostStatusList(
        _ hostStates: [DockHostStateViewModel],
        stateTitle: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(stateTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            LazyVStack(spacing: 10) {
                ForEach(hostStates) { hostState in
                    hostContextRow(
                        hostState,
                        automationID: AutomationID.Dock.hostSummary(hostID: hostState.host.id)
                    )
                }
            }
            if hostStates.contains(where: { $0.status == .checking }) {
                Text("Waiting for relay response")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .codexAutomationID(AutomationID.Dock.state(.loading))
            }
        }
    }

    @ViewBuilder
    private func hostContextRow(
        _ hostState: DockHostStateViewModel,
        automationID: AutomationID? = nil
    ) -> some View {
        if hostState.status.isUnavailable {
            hostFailureRow(hostState, automationID: automationID)
        } else {
            HostLoadingRow(hostState: hostState)
                .codexAutomationID(automationID)
        }
    }

    private func hostFailureRow(
        _ hostState: DockHostStateViewModel,
        automationID: AutomationID? = nil
    ) -> some View {
        HostFailureRow(
            hostState: hostState,
            onRetry: {
                Task {
                    await store.refresh()
                }
            },
            onOpenRelaySettings: onOpenRelaySettings
        )
        .codexAutomationID(automationID)
    }

    @ViewBuilder
    private func rowContextMenu(_ row: DockRowViewModel) -> some View {
        DockRowContextMenu(
            row: row,
            store: store,
            onArchiveSucceeded: onArchiveSucceeded
        )
    }

}

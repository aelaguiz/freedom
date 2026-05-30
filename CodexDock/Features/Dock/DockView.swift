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
    @StateObject private var hostsStore: HostSettingsStore
    @StateObject private var connectivityStore: AppConnectivityStore
    @StateObject private var lifecycleCoordinator: AppLifecycleCoordinator
    @State private var foregroundResumeTask: Task<Void, Never>?
    @State private var selectedRootTab: AutomationID.RootTab = .dock

    public init(store: DockStore) {
        _dockStore = StateObject(wrappedValue: store)
        if let host = store.hostConfiguration,
           let registry = try? HostRegistry(hosts: [host]) {
            _archiveStore = StateObject(wrappedValue: ArchiveStore(registry: registry))
            _hostsStore = StateObject(wrappedValue: HostSettingsStore(registry: registry))
            _connectivityStore = StateObject(wrappedValue: AppConnectivityStore(registry: registry))
        } else {
            let error = DockHostConfigurationError.missingEndpoint
            _archiveStore = StateObject(wrappedValue: ArchiveStore(configurationError: error))
            _hostsStore = StateObject(wrappedValue: HostSettingsStore(configurationError: error))
            _connectivityStore = StateObject(wrappedValue: AppConnectivityStore(configurationError: error))
        }
        _lifecycleCoordinator = StateObject(wrappedValue: AppLifecycleCoordinator())
    }

    public init(
        registry: HostRegistry,
        client: AppServerDockClient = AppServerDockClient(),
        streamClient: any DockStreamConnecting = AppServerDockStreamClient(),
        metadataStore: any LocalThreadMetadataStoring = FileLocalThreadMetadataStore(),
        lifecycleCoordinator: AppLifecycleCoordinator = AppLifecycleCoordinator(),
        connectivityStore: AppConnectivityStore? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        let connectivityStore = connectivityStore ?? AppConnectivityStore(registry: registry, now: now)
        _dockStore = StateObject(
            wrappedValue: DockStore(
                registry: registry,
                streamClient: streamClient,
                archiver: client,
                metadataStore: metadataStore,
                now: now
            )
        )
        _archiveStore = StateObject(
            wrappedValue: ArchiveStore(
                registry: registry,
                loader: client,
                archiver: client,
                metadataStore: metadataStore,
                now: now
            )
        )
        _hostsStore = StateObject(
            wrappedValue: HostSettingsStore(
                registry: registry,
                tester: client,
                now: now
            )
        )
        _connectivityStore = StateObject(wrappedValue: connectivityStore)
        _lifecycleCoordinator = StateObject(wrappedValue: lifecycleCoordinator)
    }

    public init(configurationError error: Error) {
        _dockStore = StateObject(wrappedValue: DockStore(configurationError: error))
        _archiveStore = StateObject(wrappedValue: ArchiveStore(configurationError: error))
        _hostsStore = StateObject(wrappedValue: HostSettingsStore(configurationError: error))
        _connectivityStore = StateObject(wrappedValue: AppConnectivityStore(configurationError: error))
        _lifecycleCoordinator = StateObject(wrappedValue: AppLifecycleCoordinator())
    }

    public var body: some View {
        TabView(selection: $selectedRootTab) {
            DockView(
                store: dockStore,
                lifecycleCoordinator: lifecycleCoordinator,
                connectivityReporter: connectivityStore,
                connectivityStore: connectivityStore,
                onOpenRelaySettings: {
                    selectedRootTab = .relay
                },
                onArchiveSucceeded: {
                    await archiveStore.refresh()
                }
            )
                .tabItem {
                    Label("Dock", systemImage: "rectangle.stack")
                        .codexAutomationID(AutomationID.Root.tab(.dock))
                }
                .tag(AutomationID.RootTab.dock)

            ArchiveView(
                store: archiveStore,
                onRestoreSucceeded: {
                    await dockStore.refresh()
                }
            )
                .tabItem {
                    Label("Archive", systemImage: "archivebox")
                        .codexAutomationID(AutomationID.Root.tab(.archive))
                }
                .tag(AutomationID.RootTab.archive)

            HostsView(store: hostsStore)
                .tabItem {
                    Label("Relay", systemImage: "desktopcomputer")
                        .codexAutomationID(AutomationID.Root.tab(.relay))
                }
                .tag(AutomationID.RootTab.relay)
        }
        .tint(.blue)
        .accessibilityElement(children: .contain)
        .codexAutomationID(AutomationID.Root.tabs)
        .accessibilityValue(selectedRootTab.rawValue)
        .task {
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
                await dockStore.updateRegistry(registry)
                await archiveStore.updateRegistry(registry)
            }
        }
    }

    private func bindConnectivity() {
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
    @ObservedObject private var store: DockStore
    private let lifecycleCoordinator: AppLifecycleCoordinator?
    private let connectivityReporter: (any AppConnectivityReporting)?
    private let connectivityStore: AppConnectivityStore?
    private let onOpenRelaySettings: @MainActor () -> Void
    private let onArchiveSucceeded: @MainActor () async -> Void
    @State private var selectedLens: DockLensID = .newest
    @State private var searchText = ""
    @State private var filterState = DockFilterState.default
    @State private var isFilterSurfacePresented = false
    @State private var collapsedHostGroupIDs: Set<String> = []
    @State private var collapsedBranchGroupIDs: Set<String> = []

    public init(
        store: DockStore,
        lifecycleCoordinator: AppLifecycleCoordinator? = nil,
        connectivityReporter: (any AppConnectivityReporting)? = nil,
        connectivityStore: AppConnectivityStore? = nil,
        onOpenRelaySettings: @escaping @MainActor () -> Void = {},
        onArchiveSucceeded: @escaping @MainActor () async -> Void = {}
    ) {
        self.store = store
        self.lifecycleCoordinator = lifecycleCoordinator
        self.connectivityReporter = connectivityReporter
        self.connectivityStore = connectivityStore
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
                .padding(.bottom, 24)
            }
            .background(dockBackgroundColor)
            .dockNavigationChrome()
            .refreshable {
                await store.refresh()
            }
        }
        .sheet(isPresented: $isFilterSurfacePresented) {
            DockFilterSurfaceView(
                filters: $filterState,
                projection: currentProjection
            )
        }
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
                    GlobalConnectivityIndicatorView(store: connectivityStore)
                        .fixedSize(horizontal: true, vertical: false)
                }
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
                    searchText = ""
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
                    selectedLens = lens
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
                    filterState = .default
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
        TextField("Search sessions, repo, branch, host", text: $searchText)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .codexAutomationID(AutomationID.Dock.searchField)
        #else
        TextField("Search sessions, repo, branch, host", text: $searchText)
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

    private var currentProjection: DockSessionProjection? {
        if case .loaded(let snapshot) = store.state {
            return snapshot.project(options: projectionOptions)
        }
        return nil
    }

    private var activeSummaryText: String {
        currentProjection?.summary.text ?? "0 shown · Hosts: Any · Branches: Any · Status: Any · Repo: Any · Source: Any · Idle hidden"
    }

    @ViewBuilder
    private var content: some View {
        switch store.state {
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
        case let .offline(host, message):
            hostFailureRow(
                DockHostStateViewModel(host: host, status: .offline(message)),
                automationID: AutomationID.Dock.state(.offline)
            )
        case let .error(host, message):
            hostFailureRow(
                DockHostStateViewModel(host: host, status: .error(message)),
                automationID: AutomationID.Dock.state(.error)
            )
        case let .loaded(snapshot):
            loadedContent(snapshot)
        }
    }

    private func loadedContent(_ snapshot: DockSnapshot) -> some View {
        let projection = snapshot.project(options: projectionOptions)

        return VStack(alignment: .leading, spacing: 16) {
            if let actionError = store.actionError {
                ActionErrorBanner(
                    message: actionError,
                    automationID: AutomationID.Dock.state(.actionError)
                )
            }

            if !snapshot.mappingFailures.isEmpty {
                MappingFailureBanner(
                    count: snapshot.mappingFailures.count,
                    automationID: AutomationID.Dock.state(.mappingFailure)
                )
            }

            if let emptyReason = projection.emptyReason {
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
                projectedContent(projection, snapshot: snapshot)
            }
        }
    }

    @ViewBuilder
    private func projectedContent(
        _ projection: DockSessionProjection,
        snapshot: DockSnapshot
    ) -> some View {
        switch selectedLens {
        case .newest:
            LazyVStack(spacing: 10) {
                ForEach(projection.rows) { row in
                    dockRow(row)
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
                    projectionGroup(group, collapsedIDs: $collapsedHostGroupIDs)
                }
            }
        case .branch:
            LazyVStack(spacing: 12) {
                ForEach(projection.groups) { group in
                    projectionGroup(group, collapsedIDs: $collapsedBranchGroupIDs)
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

    private var projectionOptions: DockProjectionOptions {
        DockProjectionOptions(
            lens: selectedLens,
            searchText: searchText,
            filters: filterState
        )
    }

    private var dockScreenValue: String {
        switch store.state {
        case .configurationError:
            return "configuration-error"
        case .idle(let hosts):
            return "idle; hosts=\(hosts.count); lens=\(selectedLens.rawValue); filters=\(filterState.activeFilterCount)"
        case .loading(let hosts):
            return "loading; hosts=\(hosts.count); lens=\(selectedLens.rawValue); filters=\(filterState.activeFilterCount)"
        case .loaded(let snapshot):
            return "loaded; rows=\(snapshot.rowCount); lens=\(selectedLens.rawValue); search=\(!searchText.isEmpty); filters=\(filterState.activeFilterCount); \(activeSummaryText)"
        case .offline(let host, _):
            return "offline; host=\(host.id); lens=\(selectedLens.rawValue); filters=\(filterState.activeFilterCount)"
        case .error(let host, _):
            return "error; host=\(host.id); lens=\(selectedLens.rawValue); filters=\(filterState.activeFilterCount)"
        }
    }

    private func dockRow(_ row: DockRowViewModel) -> some View {
        Group {
            if let host = store.hostConfiguration(for: row.id.hostID) {
                NavigationLink {
                    SessionDetailView(
                        store: ThreadDetailStore(
                            host: host,
                            row: row,
                            lifecycleCoordinator: lifecycleCoordinator,
                            connectivityReporter: connectivityReporter
                        )
                    )
                } label: {
                    DockRowView(row: row)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .codexAutomationID(AutomationID.Dock.row(hostID: row.id.hostID, threadID: row.id.threadID))
                .accessibilityValue(row.automationValue)
                .contextMenu {
                    rowContextMenu(row)
                }
            } else {
                DockRowView(
                    row: row,
                    automationID: AutomationID.Dock.row(hostID: row.id.hostID, threadID: row.id.threadID)
                )
                .accessibilityValue(row.automationValue)
                .contextMenu {
                    rowContextMenu(row)
                }
            }
        }
    }

    private func projectionGroup(
        _ group: DockProjectionGroupViewModel,
        collapsedIDs: Binding<Set<String>>
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
                        dockRow(row)
                    }
                }
            }
        }
        .codexAutomationID(groupAutomationID)
    }

    private func currentHostState(hostID: String) -> DockHostStateViewModel? {
        guard case .loaded(let snapshot) = store.state else {
            return nil
        }
        return snapshot.hostStates.first { $0.host.id == hostID }
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
        rowActions(row)
    }

    @ViewBuilder
    private func rowActions(_ row: DockRowViewModel) -> some View {
        Button {
            Task {
                await store.setLabel("Watch", for: row)
            }
        } label: {
            Label("Mark Watch", systemImage: "tag")
        }
        .codexAutomationID(
            AutomationID.Dock.rowAction(
                hostID: row.id.hostID,
                threadID: row.id.threadID,
                action: .markWatch
            )
        )

        Button {
            Task {
                await store.setLabel(nil, for: row)
            }
        } label: {
            Label("Clear Label", systemImage: "tag.slash")
        }
        .codexAutomationID(
            AutomationID.Dock.rowAction(
                hostID: row.id.hostID,
                threadID: row.id.threadID,
                action: .clearLabel
            )
        )

        Button(role: .destructive) {
            Task {
                if await store.archive(row) {
                    await onArchiveSucceeded()
                }
            }
        } label: {
            Label("Archive", systemImage: "archivebox")
        }
        .codexAutomationID(
            AutomationID.Dock.rowAction(
                hostID: row.id.hostID,
                threadID: row.id.threadID,
                action: .archive
            )
        )

        Menu {
            ForEach(DockRowRail.allCases, id: \.self) { rail in
                Button {
                    Task {
                        await store.setRail(rail, for: row)
                    }
                } label: {
                    Label(rail.label, systemImage: rail.systemImage)
                }
                .codexAutomationID(
                    AutomationID.Dock.rowColorAction(
                        hostID: row.id.hostID,
                        threadID: row.id.threadID,
                        rail: rail.rawValue
                    )
                )
            }

            Button {
                Task {
                    await store.setRail(nil, for: row)
                }
            } label: {
                Label("Clear Color", systemImage: "circle.slash")
            }
            .codexAutomationID(
                AutomationID.Dock.rowAction(
                    hostID: row.id.hostID,
                    threadID: row.id.threadID,
                    action: .clearColor
                )
            )
        } label: {
            Label("Color", systemImage: "paintpalette")
        }
        .codexAutomationID(
            AutomationID.Dock.rowAction(
                hostID: row.id.hostID,
                threadID: row.id.threadID,
                action: .color
            )
        )
    }

}

#Preview {
    let host = try! DockHostConfiguration(host: "preview.invalid", port: 4500)
    return CodexDockRootView(
        store: DockStore(host: host, streamClient: PreviewDockStreamClient())
    )
}

private struct PreviewDockStreamClient: DockStreamConnecting {
    func connect(to host: DockHostConfiguration) async throws -> any DockStreamConnection {
        PreviewDockStreamConnection(host: host)
    }
}

private struct PreviewDockStreamConnection: DockStreamConnection {
    let host: DockHostConfiguration

    func subscribe() async throws -> DockStreamUpdateDTO {
        snapshot()
    }

    func resync() async throws -> DockStreamUpdateDTO {
        snapshot()
    }

    func updates() -> AsyncThrowingStream<DockStreamUpdateDTO, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func close() async {}

    private func snapshot() -> DockStreamUpdateDTO {
        DockStreamUpdateDTO(
            kind: .snapshot,
            epoch: "preview",
            seq: 1,
            freshness: DockStreamFreshnessDTO(status: .fresh),
            hosts: [DockStreamHostDTO(id: host.id, displayName: host.displayName, endpoint: host.endpoint.displayEndpoint)],
            sessions: [
                DockStreamSessionDTO(
                    id: "\(host.id)::preview-running",
                    hostID: host.id,
                    threadID: "preview-running",
                    backendSessionID: "preview-session-running",
                    title: "Wire the iPhone shell to the real host",
                    status: .running,
                    lane: .human,
                    kindLabel: "Human",
                    repository: "codex-client",
                    workingDirectory: "/Users/aelaguiz/workspace/codex-client",
                    branch: "main",
                    updatedAt: Int64(Date(timeIntervalSinceNow: -180).timeIntervalSince1970),
                    summary: "Generated the app target and Dock store.",
                    source: DockStreamSourceDTO(kind: .human)
                ),
                DockStreamSessionDTO(
                    id: "\(host.id)::preview-review",
                    hostID: host.id,
                    threadID: "preview-review",
                    backendSessionID: "preview-session-review",
                    title: "Review the live-host launch proof",
                    status: .needsInput,
                    lane: .human,
                    kindLabel: "Human",
                    repository: "codex",
                    workingDirectory: "/Users/aelaguiz/workspace/codex",
                    branch: "app-server",
                    updatedAt: Int64(Date(timeIntervalSinceNow: -4_800).timeIntervalSince1970),
                    summary: "The simulator is connected to a reachable app-server.",
                    source: DockStreamSourceDTO(kind: .human)
                ),
                DockStreamSessionDTO(
                    id: "\(host.id)::preview-agent",
                    hostID: host.id,
                    threadID: "preview-agent",
                    backendSessionID: "preview-session-agent",
                    title: "Audit the Dock snapshot model",
                    status: .idle,
                    lane: .agent,
                    kindLabel: "Agent",
                    repository: "codex-client",
                    workingDirectory: "/Users/aelaguiz/workspace/codex-client",
                    branch: "feature/agents",
                    updatedAt: Int64(Date(timeIntervalSinceNow: -900).timeIntervalSince1970),
                    summary: "Sub-agent returned a focused review.",
                    source: DockStreamSourceDTO(kind: .automation)
                )
            ]
        )
    }
}

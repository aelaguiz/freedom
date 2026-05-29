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
        metadataStore: any LocalThreadMetadataStoring = FileLocalThreadMetadataStore(),
        lifecycleCoordinator: AppLifecycleCoordinator = AppLifecycleCoordinator(),
        connectivityStore: AppConnectivityStore? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        let connectivityStore = connectivityStore ?? AppConnectivityStore(registry: registry, now: now)
        _dockStore = StateObject(
            wrappedValue: DockStore(
                registry: registry,
                loader: client,
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

        while !Task.isCancelled {
            do {
                try await Task.sleep(for: DockStore.defaultAutoRefreshInterval)
            } catch {
                return
            }

            guard lifecycleCoordinator.allowsForegroundWork else {
                continue
            }
            await dockStore.refresh()
        }
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
    private let onArchiveSucceeded: @MainActor () async -> Void
    @State private var selectedTab: DockTabID = .all
    @State private var searchText = ""
    @State private var sortMode: DockSessionSortMode = .branch
    @State private var showsIdle = false

    public init(
        store: DockStore,
        lifecycleCoordinator: AppLifecycleCoordinator? = nil,
        connectivityReporter: (any AppConnectivityReporting)? = nil,
        connectivityStore: AppConnectivityStore? = nil,
        onArchiveSucceeded: @escaping @MainActor () async -> Void = {}
    ) {
        self.store = store
        self.lifecycleCoordinator = lifecycleCoordinator
        self.connectivityReporter = connectivityReporter
        self.connectivityStore = connectivityStore
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
        .accessibilityElement(children: .contain)
        .codexAutomationID(AutomationID.Dock.root)
        .accessibilityValue(dockScreenValue)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Dock")
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(.primary)

            Spacer(minLength: 12)

            if let connectivityStore {
                GlobalConnectivityIndicatorView(store: connectivityStore)
                    .fixedSize(horizontal: true, vertical: false)
            }

            Button {
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(true)
            .accessibilityLabel("Add host")
            .codexAutomationID(AutomationID.Dock.addHostButton)
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Picker("Filter", selection: $selectedTab) {
                ForEach(currentTabs) { tab in
                    Text(tab.label)
                        .codexAutomationID(AutomationID.Dock.filterTab(tab.id.rawValue))
                        .tag(tab.id)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityValue(selectedTab.rawValue)
            .codexAutomationID(AutomationID.Dock.filterPicker)

            ViewThatFits(in: .horizontal) {
                sessionControlsRow
                VStack(alignment: .leading, spacing: 8) {
                    searchControl
                    HStack(spacing: 8) {
                        sortControl
                        idleToggle
                    }
                }
            }
        }
    }

    private var sessionControlsRow: some View {
        HStack(spacing: 6) {
            searchControl
                .frame(width: 154)
            sortControl
                .frame(width: 116)
            idleToggle
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var searchControl: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            searchField
        }
        .font(.subheadline)
        .padding(.horizontal, 10)
        .frame(height: 40)
        .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var sortControl: some View {
        Picker("Sort", selection: $sortMode) {
            ForEach(DockSessionSortMode.allCases) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Sort sessions")
        .accessibilityValue(sortMode.rawValue)
        .codexAutomationID(AutomationID.Dock.sortPicker)
    }

    private var idleToggle: some View {
        Button {
            showsIdle.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: showsIdle ? "checkmark.square.fill" : "square")
                    .font(.system(size: 17, weight: .semibold))
                Text("Idle")
            }
            .font(.subheadline.weight(.medium))
            .frame(height: 40)
            .padding(.horizontal, 8)
            .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show idle threads")
        .accessibilityValue(showsIdle ? "On" : "Off")
        .accessibilityHint("Shows idle threads when enabled.")
        .accessibilityAddTraits(showsIdle ? .isSelected : [])
        .codexAutomationID(AutomationID.Dock.idleToggle)
    }

    @ViewBuilder
    private var searchField: some View {
        #if os(iOS)
        TextField("Search sessions", text: $searchText)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .codexAutomationID(AutomationID.Dock.searchField)
        #else
        TextField("Search sessions", text: $searchText)
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

    private var currentTabs: [DockTabViewModel] {
        if case .loaded(let snapshot) = store.state {
            return snapshot.project(options: projectionOptions).tabs
        }
        return DockTabID.allCases.map { DockTabViewModel(id: $0, count: 0) }
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
        case let .idle(host):
            HostSummaryView(
                host: host,
                subtitle: "Ready",
                automationID: AutomationID.Dock.hostSummary(hostID: host.id)
            )
        case let .loading(host):
            HostSummaryView(
                host: host,
                subtitle: "Loading",
                automationID: AutomationID.Dock.hostSummary(hostID: host.id)
            )
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 120)
                .codexAutomationID(AutomationID.Dock.state(.loading))
        case let .offline(host, message):
            HostSummaryView(
                host: host,
                subtitle: "Offline",
                automationID: AutomationID.Dock.hostSummary(hostID: host.id)
            )
            DockMessageView(
                icon: "wifi.exclamationmark",
                title: "Host offline",
                message: message,
                automationID: AutomationID.Dock.state(.offline)
            )
        case let .error(host, message):
            HostSummaryView(
                host: host,
                subtitle: "Error",
                automationID: AutomationID.Dock.hostSummary(hostID: host.id)
            )
            DockMessageView(
                icon: "exclamationmark.octagon",
                title: "Dock error",
                message: message,
                automationID: AutomationID.Dock.state(.error)
            )
        case let .loaded(snapshot):
            loadedContent(snapshot)
        }
    }

    private func loadedContent(_ snapshot: DockSnapshot) -> some View {
        let projection = snapshot.project(options: projectionOptions)
        let sections = projection.sections

        return VStack(alignment: .leading, spacing: 16) {
            ForEach(snapshot.hostStates) { hostState in
                HostSummaryView(
                    hostState: hostState,
                    automationID: AutomationID.Dock.hostSummary(hostID: hostState.host.id)
                )
            }

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

            ForEach(snapshot.scopeConflicts) { conflict in
                ScopeConflictBanner(
                    conflict: conflict,
                    automationID: AutomationID.Dock.scopeConflict(
                        hostID: conflict.threadID.hostID,
                        threadID: conflict.threadID.threadID
                    )
                )
            }

            ForEach(snapshot.scopeLoadFailures) { failure in
                ScopeLoadFailureBanner(
                    failure: failure,
                    automationID: AutomationID.Dock.scopeLoadFailure(
                        hostID: failure.host.id,
                        scopeID: failure.scope.rawValue
                    )
                )
            }

            if sections.isEmpty {
                DockMessageView(
                    icon: "line.3.horizontal.decrease.circle",
                    title: emptyStateTitle(hasHiddenIdleMatches: projection.hiddenIdleMatchCount > 0),
                    message: emptyStateMessage(hasHiddenIdleMatches: projection.hiddenIdleMatchCount > 0),
                    automationID: AutomationID.Dock.state(.empty)
                )
            } else {
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .codexAutomationID(AutomationID.Dock.section(section.id))

                        VStack(spacing: 10) {
                            ForEach(section.rows) { row in
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
                                        automationID: AutomationID.Dock.row(
                                            hostID: row.id.hostID,
                                            threadID: row.id.threadID
                                        )
                                    )
                                    .accessibilityValue(row.automationValue)
                                    .contextMenu {
                                        rowContextMenu(row)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var projectionOptions: DockSessionProjectionOptions {
        DockSessionProjectionOptions(
            selectedTab: selectedTab,
            searchText: searchText,
            sortMode: sortMode,
            showsIdle: showsIdle
        )
    }

    private var dockScreenValue: String {
        switch store.state {
        case .configurationError:
            return "configuration-error"
        case .idle(let host):
            return "idle; host=\(host.id); filter=\(selectedTab.rawValue); sort=\(sortMode.rawValue); idle=\(showsIdle)"
        case .loading(let host):
            return "loading; host=\(host.id); filter=\(selectedTab.rawValue); sort=\(sortMode.rawValue); idle=\(showsIdle)"
        case .loaded(let snapshot):
            return "loaded; rows=\(snapshot.rowCount); filter=\(selectedTab.rawValue); sort=\(sortMode.rawValue); idle=\(showsIdle)"
        case .offline(let host, _):
            return "offline; host=\(host.id); filter=\(selectedTab.rawValue); sort=\(sortMode.rawValue); idle=\(showsIdle)"
        case .error(let host, _):
            return "error; host=\(host.id); filter=\(selectedTab.rawValue); sort=\(sortMode.rawValue); idle=\(showsIdle)"
        }
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

    private func emptyStateTitle(hasHiddenIdleMatches: Bool) -> String {
        if hasHiddenIdleMatches {
            return "Idle hidden"
        }

        let hasSearch = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasSearch {
            return "No matches"
        }

        switch selectedTab {
        case .all:
            return "No sessions"
        case .needsMe:
            return "Nothing needs you"
        case .running:
            return "Nothing running"
        case .agents:
            return "No agent sessions"
        }
    }

    private func emptyStateMessage(hasHiddenIdleMatches: Bool) -> String {
        if hasHiddenIdleMatches {
            return "Enable Idle to show matching idle threads."
        }

        let hasSearch = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasSearch {
            return "No sessions match this filter and search."
        }

        switch selectedTab {
        case .all:
            return "No human sessions are loaded on reachable hosts."
        case .needsMe:
            return "No sessions are waiting for approval or input."
        case .running:
            return "No live sessions are loaded on reachable hosts."
        case .agents:
            return "No agent or automation sessions are loaded on reachable hosts."
        }
    }
}

#Preview {
    let host = try! DockHostConfiguration(host: "preview.invalid", port: 4500)
    return CodexDockRootView(
        store: DockStore(host: host, loader: PreviewDockSessionLoader())
    )
}

private struct PreviewDockSessionLoader: DockSessionLoading {
    func loadSessions(
        for host: DockHostConfiguration,
        query: DockSessionQuery
    ) async throws -> DockLoadResult {
        if query.archived {
            return DockLoadResult(summaries: [])
        }
        if query == .activeAgents {
            return DockLoadResult(
                summaries: [
                    SessionSummary(
                        id: HostScopedThreadID(hostID: host.id, threadID: "preview-agent"),
                        backendSessionID: "preview-session-agent",
                        displayTitle: "Audit the Dock snapshot model",
                        status: .idle,
                        repository: .known("codex-client"),
                        workingDirectory: .known("/Users/aelaguiz/workspace/codex-client"),
                        branch: .known("feature/agents"),
                        lastActivity: Date(timeIntervalSinceNow: -900),
                        shortEventSummary: .known("Sub-agent returned a focused review."),
                        origin: .agentOrAutomation(
                            subtype: .subAgentReview,
                            evidence: SessionOriginEvidence(sourceKind: .subAgentReview)
                        )
                    )
                ]
            )
        }
        return DockLoadResult(
            summaries: [
                SessionSummary(
                    id: HostScopedThreadID(hostID: host.id, threadID: "preview-running"),
                    backendSessionID: "preview-session-running",
                    displayTitle: "Wire the iPhone shell to the real host",
                    status: .active(activeFlags: []),
                    repository: .known("codex-client"),
                    workingDirectory: .known("/Users/aelaguiz/workspace/codex-client"),
                    branch: .known("main"),
                    lastActivity: Date(timeIntervalSinceNow: -180),
                    shortEventSummary: .known("Generated the app target and Dock store."),
                    origin: .humanInteractive(subtype: .cli)
                ),
                SessionSummary(
                    id: HostScopedThreadID(hostID: host.id, threadID: "preview-needs-me"),
                    backendSessionID: "preview-session-needs-me",
                    displayTitle: "Review the live-host launch proof",
                    status: .active(activeFlags: [.waitingOnUserInput]),
                    repository: .known("codex"),
                    workingDirectory: .known("/Users/aelaguiz/workspace/codex"),
                    branch: .known("app-server"),
                    lastActivity: Date(timeIntervalSinceNow: -4_800),
                    shortEventSummary: .known("The simulator is connected to a reachable app-server."),
                    origin: .humanInteractive(subtype: .cli)
                )
            ]
        )
    }
}

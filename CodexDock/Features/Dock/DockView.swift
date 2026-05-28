import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

public struct CodexDockRootView: View {
    @StateObject private var dockStore: DockStore
    @StateObject private var archiveStore: ArchiveStore
    @StateObject private var hostsStore: HostSettingsStore

    public init(store: DockStore) {
        _dockStore = StateObject(wrappedValue: store)
        if let host = store.hostConfiguration,
           let registry = try? HostRegistry(hosts: [host]) {
            _archiveStore = StateObject(wrappedValue: ArchiveStore(registry: registry))
            _hostsStore = StateObject(wrappedValue: HostSettingsStore(registry: registry))
        } else {
            let error = DockHostConfigurationError.missingEndpoint
            _archiveStore = StateObject(wrappedValue: ArchiveStore(configurationError: error))
            _hostsStore = StateObject(wrappedValue: HostSettingsStore(configurationError: error))
        }
    }

    public init(
        registry: HostRegistry,
        client: AppServerDockClient = AppServerDockClient(),
        metadataStore: any LocalThreadMetadataStoring = FileLocalThreadMetadataStore(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
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
    }

    public init(configurationError error: Error) {
        _dockStore = StateObject(wrappedValue: DockStore(configurationError: error))
        _archiveStore = StateObject(wrappedValue: ArchiveStore(configurationError: error))
        _hostsStore = StateObject(wrappedValue: HostSettingsStore(configurationError: error))
    }

    public var body: some View {
        TabView {
            DockView(
                store: dockStore,
                onArchiveSucceeded: {
                    await archiveStore.refresh()
                }
            )
                .tabItem {
                    Label("Dock", systemImage: "rectangle.stack")
                }

            ArchiveView(
                store: archiveStore,
                onRestoreSucceeded: {
                    await dockStore.refresh()
                }
            )
                .tabItem {
                    Label("Archive", systemImage: "archivebox")
                }

            HostsView(store: hostsStore)
                .tabItem {
                    Label("Relay", systemImage: "desktopcomputer")
                }
        }
        .tint(.blue)
        .onChange(of: hostsStore.registry) { _, registry in
            guard let registry else {
                return
            }
            Task {
                await dockStore.updateRegistry(registry)
                await archiveStore.updateRegistry(registry)
            }
        }
    }
}

public struct DockView: View {
    @ObservedObject private var store: DockStore
    private let onArchiveSucceeded: @MainActor () async -> Void
    @State private var selectedTab: DockTabID = .all
    @State private var searchText = ""

    public init(
        store: DockStore,
        onArchiveSucceeded: @escaping @MainActor () async -> Void = {}
    ) {
        self.store = store
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
            .task {
                await runRefreshLoop()
            }
            .refreshable {
                await store.refresh()
            }
        }
    }

    private func runRefreshLoop() async {
        await store.load()

        while !Task.isCancelled {
            do {
                try await Task.sleep(for: DockStore.defaultAutoRefreshInterval)
            } catch {
                return
            }

            await store.refresh()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Dock")
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(.primary)

            Spacer(minLength: 12)

            Button {
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(true)
            .accessibilityLabel("Add host")
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Picker("Filter", selection: $selectedTab) {
                ForEach(currentTabs) { tab in
                    Text(tab.label).tag(tab.id)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                searchField
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    @ViewBuilder
    private var searchField: some View {
        #if os(iOS)
        TextField("Search sessions", text: $searchText)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        TextField("Search sessions", text: $searchText)
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
            return snapshot.tabs
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
                message: message
            )
        case let .idle(host):
            HostSummaryView(host: host, subtitle: "Ready")
        case let .loading(host):
            HostSummaryView(host: host, subtitle: "Loading")
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 120)
        case let .offline(host, message):
            HostSummaryView(host: host, subtitle: "Offline")
            DockMessageView(
                icon: "wifi.exclamationmark",
                title: "Host offline",
                message: message
            )
        case let .error(host, message):
            HostSummaryView(host: host, subtitle: "Error")
            DockMessageView(
                icon: "exclamationmark.octagon",
                title: "Dock error",
                message: message
            )
        case let .loaded(snapshot):
            loadedContent(snapshot)
        }
    }

    private func loadedContent(_ snapshot: DockSnapshot) -> some View {
        let sections = filteredSections(snapshot.sections(for: selectedTab))

        return VStack(alignment: .leading, spacing: 16) {
            ForEach(snapshot.hostStates) { hostState in
                HostSummaryView(hostState: hostState)
            }

            if let actionError = store.actionError {
                ActionErrorBanner(message: actionError)
            }

            if !snapshot.mappingFailures.isEmpty {
                MappingFailureBanner(count: snapshot.mappingFailures.count)
            }

            ForEach(snapshot.scopeConflicts) { conflict in
                ScopeConflictBanner(conflict: conflict)
            }

            ForEach(snapshot.scopeLoadFailures) { failure in
                ScopeLoadFailureBanner(failure: failure)
            }

            if sections.isEmpty {
                DockMessageView(
                    icon: "line.3.horizontal.decrease.circle",
                    title: emptyStateTitle,
                    message: emptyStateMessage
                )
            } else {
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        VStack(spacing: 10) {
                            ForEach(section.rows) { row in
                                if let host = store.hostConfiguration(for: row.id.hostID) {
                                    NavigationLink {
                                        SessionDetailView(
                                            store: ThreadDetailStore(host: host, row: row)
                                        )
                                    } label: {
                                        DockRowView(row: row)
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        rowContextMenu(row)
                                    }
                                } else {
                                    DockRowView(row: row)
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

    @ViewBuilder
    private func rowContextMenu(_ row: DockRowViewModel) -> some View {
        Button {
            Task {
                await store.setLabel("Watch", for: row)
            }
        } label: {
            Label("Mark Watch", systemImage: "tag")
        }

        Button {
            Task {
                await store.setLabel(nil, for: row)
            }
        } label: {
            Label("Clear Label", systemImage: "tag.slash")
        }

        Button(role: .destructive) {
            Task {
                if await store.archive(row) {
                    await onArchiveSucceeded()
                }
            }
        } label: {
            Label("Archive", systemImage: "archivebox")
        }

        Menu {
            ForEach(DockRowRail.allCases, id: \.self) { rail in
                Button {
                    Task {
                        await store.setRail(rail, for: row)
                    }
                } label: {
                    Label(rail.label, systemImage: rail.systemImage)
                }
            }

            Button {
                Task {
                    await store.setRail(nil, for: row)
                }
            } label: {
                Label("Clear Color", systemImage: "circle.slash")
            }
        } label: {
            Label("Color", systemImage: "paintpalette")
        }
    }

    private func filteredSections(_ sections: [DockSectionViewModel]) -> [DockSectionViewModel] {
        sections.compactMap { section in
            let rows = section.rows.filter { row in
                matchesSearch(row)
            }
            guard !rows.isEmpty else {
                return nil
            }
            return DockSectionViewModel(id: section.id, title: section.title, rows: rows)
        }
    }

    private func matchesSearch(_ row: DockRowViewModel) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return true
        }

        return [row.title, row.repository, row.branch, row.summary, row.status.label]
            .contains { value in
                value.localizedCaseInsensitiveContains(query)
            }
    }

    private var emptyStateTitle: String {
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
        case .limited:
            return "No limited rows"
        case .agents:
            return "No agent sessions"
        }
    }

    private var emptyStateMessage: String {
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
        case .limited:
            return "No limited history rows are visible."
        case .agents:
            return "No agent or automation sessions are loaded on reachable hosts."
        }
    }
}

struct HostSummaryView: View {
    let host: DockHostViewModel
    let subtitle: String

    init(host: DockHostViewModel, subtitle: String) {
        self.host = host
        self.subtitle = subtitle
    }

    init(hostState: DockHostStateViewModel) {
        self.host = hostState.host
        switch hostState.status {
        case .loaded, .partial, .empty:
            self.subtitle = hostState.status.subtitle
        case .offline(let message), .error(let message):
            self.subtitle = "\(hostState.status.subtitle): \(message)"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 24))
                .foregroundStyle(.blue)
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(host.displayName)
                    .font(.headline)
                Text("\(host.endpoint) · \(subtitle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            Text("Codex")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.blue.opacity(0.12), in: Capsule())
                .fixedSize()
        }
        .padding(.vertical, 4)
    }
}

struct MappingFailureBanner: View {
    let count: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text("\(count) sessions could not be normalized.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(12)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct ActionErrorBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(.red)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Spacer()
        }
        .padding(12)
        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct ScopeLoadFailureBanner: View {
    let failure: DockScopeLoadFailureViewModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                .foregroundStyle(.orange)
            Text("\(failure.host.displayName) \(failure.scope.label) load failed: \(failure.message)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Spacer()
        }
        .padding(12)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct ScopeConflictBanner: View {
    let conflict: DockScopeConflictViewModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.branch")
                .foregroundStyle(.orange)
            Text("Thread \(conflict.backendThreadID) appeared in multiple source scopes; showing it in \(conflict.winningScope.label).")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Spacer()
        }
        .padding(12)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct DockMessageView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct DockRowView: View {
    let row: DockRowViewModel

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(railColor)
                .frame(width: 5)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .top, spacing: 8) {
                    Text(row.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)

                    Spacer(minLength: 8)

                    Text(row.status.label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(statusColor.opacity(0.12), in: Capsule())
                }

                Text("\(row.repository) · \(row.branch)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let label = row.label {
                    Label(label, systemImage: "tag")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(row.summary)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Image(systemName: "clock")
                    Text(row.lastActivity)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var railColor: Color {
        switch row.rail {
        case .blue:
            return .blue
        case .green:
            return .green
        case .orange:
            return .orange
        case .red:
            return .red
        case .violet:
            return .purple
        }
    }

    private var statusColor: Color {
        switch row.status {
        case .needsMe:
            return .orange
        case .running:
            return .green
        case .idle:
            return .blue
        case .limited:
            return .purple
        case .failed:
            return .red
        case .unknown:
            return .secondary
        }
    }
}

private extension DockRowRail {
    var label: String {
        switch self {
        case .blue:
            return "Blue"
        case .green:
            return "Green"
        case .orange:
            return "Orange"
        case .red:
            return "Red"
        case .violet:
            return "Violet"
        }
    }

    var systemImage: String {
        switch self {
        case .blue:
            return "circle.fill"
        case .green:
            return "circle.fill"
        case .orange:
            return "circle.fill"
        case .red:
            return "circle.fill"
        case .violet:
            return "circle.fill"
        }
    }
}

extension View {
    @ViewBuilder
    func dockNavigationChrome() -> some View {
        #if os(iOS)
        self.navigationBarHidden(true)
        #else
        self
        #endif
    }
}

#Preview {
    let host = DockHostConfiguration(
        id: "preview",
        displayName: "Preview",
        webSocketURL: URL(string: "ws://preview.invalid:4500")!,
        bearerToken: "preview"
    )
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

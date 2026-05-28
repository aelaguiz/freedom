import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

public enum DockFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case needsMe = "Needs me"
    case running = "Running"
    case limited = "Limited"

    public var id: String { rawValue }

    fileprivate func includes(_ row: DockRowViewModel) -> Bool {
        switch self {
        case .all:
            return true
        case .needsMe:
            return row.status == .needsMe
        case .running:
            return row.status == .running
        case .limited:
            return row.status == .limited
        }
    }
}

public struct CodexDockRootView: View {
    @StateObject private var store: DockStore

    public init(store: DockStore) {
        _store = StateObject(wrappedValue: store)
    }

    public var body: some View {
        TabView {
            DockView(store: store)
                .tabItem {
                    Label("Dock", systemImage: "rectangle.stack")
                }

            ContentUnavailableView("Archive", systemImage: "archivebox")
                .tabItem {
                    Label("Archive", systemImage: "archivebox")
                }

            ContentUnavailableView("Hosts", systemImage: "desktopcomputer")
                .tabItem {
                    Label("Hosts", systemImage: "desktopcomputer")
                }
        }
        .tint(.blue)
    }
}

public struct DockView: View {
    @ObservedObject private var store: DockStore
    @State private var filter: DockFilter = .all
    @State private var searchText = ""

    public init(store: DockStore) {
        self.store = store
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
                Label("Host", systemImage: "plus")
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .disabled(true)
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Picker("Filter", selection: $filter) {
                ForEach(DockFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
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

    @ViewBuilder
    private var content: some View {
        switch store.state {
        case let .configurationError(message):
            DockMessageView(
                icon: "exclamationmark.triangle",
                title: "Host not configured",
                message: message
            )
        case let .idle(host):
            HostSummaryView(host: host, subtitle: "Ready")
        case let .loading(host):
            HostSummaryView(host: host, subtitle: "Loading")
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 120)
        case let .empty(host):
            HostSummaryView(host: host, subtitle: "Online")
            DockMessageView(
                icon: "tray",
                title: "No sessions",
                message: "This host returned no Codex sessions."
            )
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
        let sections = filteredSections(snapshot.sections)

        return VStack(alignment: .leading, spacing: 16) {
            HostSummaryView(
                host: snapshot.host,
                subtitle: "\(snapshot.rowCount) sessions"
            )

            if !snapshot.mappingFailures.isEmpty {
                MappingFailureBanner(count: snapshot.mappingFailures.count)
            }

            if sections.isEmpty {
                DockMessageView(
                    icon: "line.3.horizontal.decrease.circle",
                    title: "No matches",
                    message: "No sessions match the current filter."
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
                                if let host = store.hostConfiguration {
                                    NavigationLink {
                                        SessionDetailView(
                                            store: ThreadDetailStore(host: host, row: row)
                                        )
                                    } label: {
                                        DockRowView(row: row)
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    DockRowView(row: row)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func filteredSections(_ sections: [DockSectionViewModel]) -> [DockSectionViewModel] {
        sections.compactMap { section in
            let rows = section.rows.filter { row in
                filter.includes(row) && matchesSearch(row)
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
}

private struct HostSummaryView: View {
    let host: DockHostViewModel
    let subtitle: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "desktopcomputer")
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(host.displayName)
                    .font(.headline)
                Text("\(host.endpoint) · \(subtitle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text("Codex")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.blue.opacity(0.12), in: Capsule())
        }
        .padding(.vertical, 4)
    }
}

private struct MappingFailureBanner: View {
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

private struct DockMessageView: View {
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

private struct DockRowView: View {
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

private extension View {
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
    func loadSessions(for host: DockHostConfiguration) async throws -> DockLoadResult {
        DockLoadResult(
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
                    shortEventSummary: .known("Generated the app target and Dock store.")
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
                    shortEventSummary: .known("The simulator is connected to a reachable app-server.")
                )
            ]
        )
    }
}

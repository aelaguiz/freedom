import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

public struct ArchiveView: View {
    @ObservedObject private var screenStore: ArchiveScreenStore
    private let store: ArchiveStore
    private let onRestoreSucceeded: @MainActor () async -> Void

    public init(
        store: ArchiveStore,
        onRestoreSucceeded: @escaping @MainActor () async -> Void = {}
    ) {
        self.store = store
        _screenStore = ObservedObject(wrappedValue: store.screenStore)
        self.onRestoreSucceeded = onRestoreSucceeded
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    content
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 24)
            }
            .background(archiveBackgroundColor)
            .dockNavigationChrome()
            .task {
                await store.load()
            }
            .refreshable {
                await store.refresh()
            }
        }
        .accessibilityElement(children: .contain)
        .codexAutomationID(AutomationID.Archive.root)
        .accessibilityValue(archiveScreenValue)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Archive")
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(.primary)

            Spacer(minLength: 12)

            Button {
                Task {
                    await store.refresh()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Refresh archive")
            .codexAutomationID(AutomationID.Archive.refreshButton)
        }
    }

    private var archiveBackgroundColor: Color {
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
        switch screenStore.state {
        case let .configurationError(message):
            DockMessageView(
                icon: "exclamationmark.triangle",
                title: "Relay not configured",
                message: message,
                automationID: AutomationID.Archive.state(.configurationError)
            )
        case let .idle(hosts):
            hostList(hosts, subtitle: "Ready")
        case let .loading(hosts):
            hostList(hosts, subtitle: "Loading")
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 120)
                .codexAutomationID(AutomationID.Archive.state(.loading))
        case let .empty(snapshot):
            snapshotContent(snapshot)
            DockMessageView(
                icon: "archivebox",
                title: "Archive empty",
                message: "Archived sessions from configured hosts will appear here.",
                automationID: AutomationID.Archive.state(.empty)
            )
        case let .unavailable(snapshot, message):
            snapshotContent(snapshot)
            DockMessageView(
                icon: "wifi.exclamationmark",
                title: "Archive unavailable",
                message: message,
                automationID: AutomationID.Archive.state(.unavailable)
            )
        case let .loaded(snapshot):
            snapshotContent(snapshot)
        }
    }

    private func hostList(_ hosts: [DockHostViewModel], subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(hosts) { host in
                HostSummaryView(
                    host: host,
                    subtitle: subtitle,
                    automationID: AutomationID.Archive.hostSummary(hostID: host.id)
                )
            }
        }
    }

    private func snapshotContent(_ snapshot: ArchiveSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(snapshot.hostStates) { hostState in
                HostSummaryView(
                    hostState: hostState,
                    automationID: AutomationID.Archive.hostSummary(hostID: hostState.host.id)
                )
            }

            if let actionError = screenStore.actionError {
                ActionErrorBanner(
                    message: actionError,
                    automationID: AutomationID.Archive.state(.actionError)
                )
            }

            if !snapshot.mappingFailures.isEmpty {
                MappingFailureBanner(
                    count: snapshot.mappingFailures.count,
                    automationID: AutomationID.Archive.state(.mappingFailure)
                )
            }

            ForEach(snapshot.sections) { section in
                VStack(alignment: .leading, spacing: 8) {
                    Text(section.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .codexAutomationID(AutomationID.Archive.section(section.id))

                    VStack(spacing: 10) {
                        ForEach(section.rows) { row in
                            archiveRow(row)
                        }
                    }
                }
            }
        }
    }

    private func archiveRow(_ row: DockRowViewModel) -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            DockRowView(
                row: row,
                automationID: AutomationID.Archive.row(hostID: row.id.hostID, threadID: row.id.threadID)
            )
                .accessibilityValue(row.automationValue)

            Button {
                Task {
                    if await store.restore(row) {
                        await onRestoreSucceeded()
                    }
                }
            } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .codexAutomationID(AutomationID.Archive.restoreButton(hostID: row.id.hostID, threadID: row.id.threadID))
        }
        .contextMenu {
            Button {
                Task {
                    if await store.restore(row) {
                        await onRestoreSucceeded()
                    }
                }
            } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }
            .codexAutomationID(AutomationID.Archive.restoreButton(hostID: row.id.hostID, threadID: row.id.threadID))
        }
    }

    private var archiveScreenValue: String {
        switch screenStore.state {
        case .configurationError:
            return "configuration-error"
        case .idle(let hosts):
            return "idle; hosts=\(hosts.count)"
        case .loading(let hosts):
            return "loading; hosts=\(hosts.count)"
        case .loaded(let snapshot):
            return "loaded; rows=\(snapshot.rowCount)"
        case .empty(let snapshot):
            return "empty; rows=\(snapshot.rowCount)"
        case .unavailable(let snapshot, _):
            return "unavailable; rows=\(snapshot.rowCount)"
        }
    }
}

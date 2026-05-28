import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

public struct ArchiveView: View {
    @ObservedObject private var store: ArchiveStore
    private let onRestoreSucceeded: @MainActor () async -> Void

    public init(
        store: ArchiveStore,
        onRestoreSucceeded: @escaping @MainActor () async -> Void = {}
    ) {
        self.store = store
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
        switch store.state {
        case let .configurationError(message):
            DockMessageView(
                icon: "exclamationmark.triangle",
                title: "Host not configured",
                message: message
            )
        case let .idle(hosts):
            hostList(hosts, subtitle: "Ready")
        case let .loading(hosts):
            hostList(hosts, subtitle: "Loading")
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 120)
        case let .empty(snapshot):
            snapshotContent(snapshot)
            DockMessageView(
                icon: "archivebox",
                title: "Archive empty",
                message: "Archived sessions from configured hosts will appear here."
            )
        case let .loaded(snapshot):
            snapshotContent(snapshot)
        }
    }

    private func hostList(_ hosts: [DockHostViewModel], subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(hosts) { host in
                HostSummaryView(host: host, subtitle: subtitle)
            }
        }
    }

    private func snapshotContent(_ snapshot: ArchiveSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(snapshot.hostStates) { hostState in
                HostSummaryView(hostState: hostState)
            }

            if let actionError = store.actionError {
                ActionErrorBanner(message: actionError)
            }

            if !snapshot.mappingFailures.isEmpty {
                MappingFailureBanner(count: snapshot.mappingFailures.count)
            }

            ForEach(snapshot.sections) { section in
                VStack(alignment: .leading, spacing: 8) {
                    Text(section.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

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
            DockRowView(row: row)

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
        }
    }
}

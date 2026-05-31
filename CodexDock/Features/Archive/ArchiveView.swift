import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

public struct ArchiveView: View {
    private enum DateFilter: String, CaseIterable, Identifiable {
        case all
        case last30
        case last90

        var id: String { rawValue }

        var label: String {
            switch self {
            case .all:
                return "All dates"
            case .last30:
                return "Last 30d"
            case .last90:
                return "Last 90d"
            }
        }

        func includes(_ row: DockRowViewModel, now: Date) -> Bool {
            switch self {
            case .all:
                return true
            case .last30:
                return now.timeIntervalSince(row.lastActivityDate) <= 30 * 86_400
            case .last90:
                return now.timeIntervalSince(row.lastActivityDate) <= 90 * 86_400
            }
        }
    }

    @ObservedObject private var screenStore: ArchiveScreenStore
    private let store: ArchiveStore
    private let title: String
    private let onClose: (@MainActor () -> Void)?
    private let onRestoreSucceeded: @MainActor () async -> Void
    @State private var searchText = ""
    @State private var selectedHostID: String?
    @State private var dateFilter: DateFilter = .all
    @State private var isSelectionMode = false
    @State private var selectedRowIDs: Set<HostScopedThreadID> = []
    @State private var isBatchRestoring = false
    @State private var stopBatchRestoreRequested = false
    @State private var batchProgress: (completed: Int, total: Int)?
    @State private var batchResults: [ArchiveRestoreResult] = []

    public init(
        store: ArchiveStore,
        title: String = "Archive",
        onClose: (@MainActor () -> Void)? = nil,
        onRestoreSucceeded: @escaping @MainActor () async -> Void = {}
    ) {
        self.store = store
        self.title = title
        self.onClose = onClose
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
            .toolbar {
                if let onClose {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", action: onClose)
                    }
                }
            }
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
            Text(title)
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(.primary)

            Spacer(minLength: 12)

            if isSelectionMode {
                Button("Cancel") {
                    isSelectionMode = false
                    selectedRowIDs = []
                }
                .buttonStyle(.bordered)
                .codexAutomationID(AutomationID.Archive.cancelSelectionButton)
            } else {
                Button("Select") {
                    isSelectionMode = true
                    selectedRowIDs = []
                }
                .buttonStyle(.bordered)
                .codexAutomationID(AutomationID.Archive.selectButton)
            }

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
        let sections = filteredSections(from: snapshot)
        let visibleRows = sections.flatMap(\.rows)

        return VStack(alignment: .leading, spacing: 16) {
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

            archiveControls(snapshot: snapshot, visibleRows: visibleRows)

            if let batchProgress {
                batchProgressView(batchProgress)
            }

            if batchFailedRows.isEmpty == false {
                ActionErrorBanner(
                    message: "\(batchFailedRows.count) restores failed.",
                    automationID: AutomationID.Archive.state(.actionError)
                )
            }

            if sections.isEmpty {
                DockMessageView(
                    icon: "line.3.horizontal.decrease.circle",
                    title: "No archived rows match",
                    message: "Try a different search, host, or date filter.",
                    automationID: AutomationID.Archive.state(.noRowsMatch)
                )
            }

            ForEach(sections) { section in
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
            if isSelectionMode {
                Button {
                    toggleSelection(row)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: selectedRowIDs.contains(row.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedRowIDs.contains(row.id) ? .blue : .secondary)
                        DockRowView(
                            row: row,
                            automationID: AutomationID.Archive.row(hostID: row.id.hostID, threadID: row.id.threadID)
                        )
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(row.title)
                .accessibilityValue(selectedRowIDs.contains(row.id) ? "Selected" : "Not selected")
                .codexAutomationID(AutomationID.Archive.selectionToggle(hostID: row.id.hostID, threadID: row.id.threadID))
            } else {
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

    private func archiveControls(
        snapshot: ArchiveSnapshot,
        visibleRows: [DockRowViewModel]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search archived threads", text: $searchText)
                    .codexAutomationID(AutomationID.Archive.searchField)
            }
            .font(.subheadline)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip("All hosts", selected: selectedHostID == nil) {
                        selectedHostID = nil
                    }
                    ForEach(snapshot.hosts) { host in
                        filterChip(host.displayName, selected: selectedHostID == host.id) {
                            selectedHostID = host.id
                        }
                    }
                    ForEach(DateFilter.allCases) { filter in
                        filterChip(filter.label, selected: dateFilter == filter) {
                            dateFilter = filter
                        }
                    }
                }
            }

            if isSelectionMode {
                HStack(spacing: 8) {
                    Text("\(selectedRowIDs.count) selected")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        Task {
                            await restoreSelected(from: visibleRows)
                        }
                    } label: {
                        Label("Restore selected", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedRowIDs.isEmpty || isBatchRestoring)
                    .codexAutomationID(AutomationID.Archive.restoreSelectedButton)
                }
                .codexAutomationID(AutomationID.Archive.selectionToolbar)
            }
        }
    }

    private func batchProgressView(_ progress: (completed: Int, total: Int)) -> some View {
        let restoredCount = batchResults.filter {
            if case .restored = $0.status { return true }
            return false
        }.count
        let failedCount = batchFailedRows.count
        let skippedCount = batchResults.filter {
            if case .skipped = $0.status { return true }
            return false
        }.count

        return VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: Double(progress.completed), total: Double(max(progress.total, 1)))
            HStack {
                Text(isBatchRestoring ? "Restored \(progress.completed) of \(progress.total)" : "Restored \(restoredCount). Failed \(failedCount). Skipped \(skippedCount).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if isBatchRestoring {
                    Button("Stop remaining") {
                        stopBatchRestoreRequested = true
                    }
                    .buttonStyle(.bordered)
                    .codexAutomationID(AutomationID.Archive.stopRemainingButton)
                }
            }
            if failedCount > 0, !isBatchRestoring {
                ForEach(batchFailedRows.prefix(6)) { row in
                    Text(row.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Retry failed") {
                    Task {
                        await restoreBatch(batchFailedRows)
                    }
                }
                .buttonStyle(.bordered)
                .codexAutomationID(AutomationID.Archive.retryFailedButton)
            }
            if !isBatchRestoring, progress.completed >= progress.total {
                Button("Done") {
                    batchProgress = nil
                    batchResults = []
                }
                .buttonStyle(.borderedProminent)
                .codexAutomationID(AutomationID.Archive.doneButton)
            }
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .codexAutomationID(AutomationID.Archive.batchProgress)
    }

    private func filterChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(selected ? .white : .primary)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(selected ? Color.blue : Color.clear, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color.secondary.opacity(0.25), lineWidth: selected ? 0 : 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .codexAutomationID(AutomationID.Archive.filterChip(title))
    }

    private func filteredSections(from snapshot: ArchiveSnapshot) -> [DockSectionViewModel] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let now = Date()
        return snapshot.sections.compactMap { section in
            let rows = section.rows.filter { row in
                if let selectedHostID,
                   !snapshot.hostIdentityResolver.contains(
                       rowHostID: row.id.hostID,
                       sourceConfiguredHostID: row.sourceHostID,
                       in: selectedHostID
                   ) {
                    return false
                }
                if !dateFilter.includes(row, now: now) {
                    return false
                }
                if !query.isEmpty {
                    let haystack = [
                        row.title,
                        row.repository,
                        row.branch,
                        row.summary,
                        row.hostDisplayName,
                        row.id.threadID
                    ].joined(separator: " ").lowercased()
                    if !haystack.contains(query) {
                        return false
                    }
                }
                return true
            }
            guard !rows.isEmpty else {
                return nil
            }
            return DockSectionViewModel(id: section.id, title: section.title, rows: rows)
        }
    }

    private func toggleSelection(_ row: DockRowViewModel) {
        if selectedRowIDs.contains(row.id) {
            selectedRowIDs.remove(row.id)
        } else {
            selectedRowIDs.insert(row.id)
        }
    }

    private func restoreSelected(from visibleRows: [DockRowViewModel]) async {
        let rows = visibleRows.filter { selectedRowIDs.contains($0.id) }
        await restoreBatch(rows)
    }

    private func restoreBatch(_ rows: [DockRowViewModel]) async {
        guard !rows.isEmpty else {
            return
        }

        isBatchRestoring = true
        stopBatchRestoreRequested = false
        batchResults = []
        batchProgress = (completed: 0, total: rows.count)
        defer {
            isBatchRestoring = false
        }

        let results = await store.restoreRows(
            rows,
            shouldStop: { stopBatchRestoreRequested },
            onProgress: { partialResults in
                batchResults = partialResults
                batchProgress = (completed: partialResults.count, total: rows.count)
            }
        )

        batchResults = results
        batchProgress = (completed: results.count, total: rows.count)
        if results.contains(where: { result in
            if case .restored = result.status { return true }
            return false
        }) {
            await onRestoreSucceeded()
        }
        for result in results {
            if case .restored = result.status {
                selectedRowIDs.remove(result.row.id)
            }
        }
        if selectedRowIDs.isEmpty {
            isSelectionMode = false
        }
    }

    private var batchFailedRows: [DockRowViewModel] {
        batchResults.compactMap { result in
            if case .failed = result.status {
                return result.row
            }
            return nil
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

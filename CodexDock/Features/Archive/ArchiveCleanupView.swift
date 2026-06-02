import SwiftUI

public struct ArchiveCleanupView: View {
    @ObservedObject private var store: ArchiveCleanupStore
    private let onOpenArchivedThreads: @MainActor () -> Void
    private let onArchiveSucceeded: @MainActor () async -> Void
    private let onClose: @MainActor () -> Void
    @State private var rule = ArchiveCleanupRule()
    @State private var customDaysText = "180"
    @State private var isConfirmingArchive = false

    public init(
        store: ArchiveCleanupStore,
        onOpenArchivedThreads: @escaping @MainActor () -> Void = {},
        onArchiveSucceeded: @escaping @MainActor () async -> Void = {},
        onClose: @escaping @MainActor () -> Void = {}
    ) {
        self.store = store
        self.onOpenArchivedThreads = onOpenArchivedThreads
        self.onArchiveSucceeded = onArchiveSucceeded
        self.onClose = onClose
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ruleControls
                    content
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 24)
            }
            .dockNavigationChrome()
            .navigationTitle("Archive Cleanup")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onClose)
                        .codexAutomationID(AutomationID.ArchiveCleanup.closeButton)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task {
                            await store.loadPreview(rule: rule)
                        }
                    } label: {
                        Label("Run preview", systemImage: "arrow.clockwise")
                    }
                    .codexAutomationID(AutomationID.ArchiveCleanup.previewButton)
                }
            }
            .task {
                await store.loadPreview(rule: rule)
            }
            .confirmationDialog(
                "Archive \(store.selectedRowIDs.count) threads?",
                isPresented: $isConfirmingArchive,
                titleVisibility: .visible
            ) {
                Button("Archive \(store.selectedRowIDs.count)", role: .destructive) {
                    Task {
                        await archiveSelected()
                    }
                }
                .codexAutomationID(AutomationID.ArchiveCleanup.confirmArchiveButton)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will archive active human sessions older than \(rule.age.days) days with the current exclusions applied across \(confirmationHostSummary). You can restore them from Archived Threads. Failed rows stay in Dock.")
            }
        }
        .accessibilityElement(children: .contain)
        .codexAutomationID(AutomationID.ArchiveCleanup.root)
    }

    private var ruleControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preview before anything moves")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Older than")
                .font(.headline)
            HStack(spacing: 8) {
                ageButton(.days30)
                ageButton(.days90)
                ageButton(.year1)
                customAgeLink
            }

            Toggle("Exclude pinned", isOn: ruleBinding(\.excludesPinned))
            Toggle("Exclude running", isOn: ruleBinding(\.excludesRunning))
            Toggle("Exclude needs input/approval", isOn: ruleBinding(\.excludesNeedsInput))
            Toggle("Exclude Watch label", isOn: ruleBinding(\.excludesWatchLabel))
        }
    }

    private var customAgeLink: some View {
        NavigationLink {
            ArchiveCleanupCustomAgeView(daysText: $customDaysText) { days in
                customDaysText = String(days)
                rule.age = .custom(days: days)
                Task {
                    await store.loadPreview(rule: rule)
                }
            }
        } label: {
            segmentedAgeLabel(customAgeTitle, selected: isCustomAgeSelected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isCustomAgeSelected ? .isSelected : [])
        .codexAutomationID(AutomationID.ArchiveCleanup.ageButton("custom"))
    }

    @ViewBuilder
    private var content: some View {
        switch store.state {
        case .configurationError(let message):
            DockMessageView(
                icon: "exclamationmark.triangle",
                title: "Relay not configured",
                message: message,
                automationID: AutomationID.ArchiveCleanup.state(.configurationError)
            )
        case .idle:
            DockMessageView(
                icon: "archivebox",
                title: "Preview not loaded",
                message: "Run preview to find cleanup candidates.",
                automationID: AutomationID.ArchiveCleanup.state(.idle)
            )
        case .loading:
            ProgressView("Loading cleanup preview")
                .frame(maxWidth: .infinity, minHeight: 140)
                .codexAutomationID(AutomationID.ArchiveCleanup.state(.loading))
        case .failed(let message):
            DockMessageView(
                icon: "exclamationmark.triangle",
                title: "Preview failed",
                message: message,
                automationID: AutomationID.ArchiveCleanup.state(.error)
            )
        case .preview(let snapshot):
            previewContent(snapshot)
        }
    }

    private func previewContent(_ snapshot: ArchiveCleanupPreviewSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(snapshot.candidateCount) threads older than \(rule.age.days) days")
                    .font(.title3.weight(.semibold))
                Text("\(snapshot.hostSummaries.count) hosts. \(snapshot.excludedCount) excluded by safety rules.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .codexAutomationID(AutomationID.ArchiveCleanup.summary)

            if snapshot.candidateCount == 0 {
                DockMessageView(
                    icon: "archivebox",
                    title: "No threads match this cleanup rule",
                    message: "Change the age or exclusions to preview more rows.",
                    automationID: AutomationID.ArchiveCleanup.state(.empty)
                )
            }

            ForEach(snapshot.hostStates) { hostState in
                if hostState.status.isUnavailable {
                    HostSummaryView(
                        hostState: hostState,
                        automationID: AutomationID.ArchiveCleanup.hostSummary(hostID: hostState.host.id)
                    )
                }
            }

            Text("By host")
                .font(.headline)
            ForEach(snapshot.hostSummaries) { host in
                NavigationLink {
                    ArchiveCleanupReviewList(
                        store: store,
                        snapshot: snapshot,
                        rule: rule,
                        initialHostID: host.id,
                        onArchive: requestArchive
                    )
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(host.displayName)
                                .font(.subheadline.weight(.semibold))
                            Text("\(host.excludedCount) excluded")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(host.candidateCount)")
                            .font(.subheadline.weight(.semibold))
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .codexAutomationID(AutomationID.ArchiveCleanup.hostSummary(hostID: host.id))
            }

            if !snapshot.candidates.isEmpty {
                HStack {
                    Text("Preview")
                        .font(.headline)
                    Text("(\(min(6, snapshot.candidates.count)) of \(snapshot.candidates.count))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    NavigationLink("View all") {
                        ArchiveCleanupReviewList(
                            store: store,
                            snapshot: snapshot,
                            rule: rule,
                            onArchive: requestArchive
                        )
                    }
                    .font(.caption.weight(.semibold))
                    .codexAutomationID(AutomationID.ArchiveCleanup.viewAllButton)
                }

                ForEach(snapshot.candidates.prefix(6)) { row in
                    DockRowView(
                        row: row,
                        automationID: AutomationID.ArchiveCleanup.row(hostID: row.hostID, threadID: row.threadID)
                    )
                }
            }

            if store.isExecuting || !store.executionResults.isEmpty {
                executionProgress
            }

            NavigationLink {
                ArchiveCleanupReviewList(
                    store: store,
                    snapshot: snapshot,
                    rule: rule,
                    onArchive: requestArchive
                )
            } label: {
                Label("Review list", systemImage: "list.bullet")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .codexAutomationID(AutomationID.ArchiveCleanup.reviewListButton)

            Button {
                requestArchive()
            } label: {
                Label("Archive \(store.selectedRowIDs.count)", systemImage: "archivebox")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.selectedRowIDs.isEmpty || store.isExecuting)
            .codexAutomationID(AutomationID.ArchiveCleanup.archiveButton)

            Button {
                onOpenArchivedThreads()
            } label: {
                Label("Restore from Archived Threads", systemImage: "arrow.uturn.backward")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .codexAutomationID(AutomationID.ArchiveCleanup.openArchivedThreadsButton)
        }
    }

    private var executionProgress: some View {
        let archived = store.executionResults.filter {
            if case .archived = $0.status { return true }
            return false
        }.count
        let failed = store.executionResults.filter {
            if case .failed = $0.status { return true }
            return false
        }.count
        let total = max(max(store.executionTotalCount, store.executionResults.count), 1)
        return VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: Double(store.executionResults.count), total: Double(total))
            Text(store.isExecuting ? "Archiving \(store.executionResults.count) of \(total)" : "Archived \(archived). Failed \(failed).")
                .font(.caption)
                .foregroundStyle(.secondary)
            if store.isExecuting {
                Button("Stop remaining") {
                    store.stopRemaining()
                }
                .buttonStyle(.bordered)
                .codexAutomationID(AutomationID.ArchiveCleanup.stopRemainingButton)
            }
            if failed > 0 {
                ForEach(store.executionResults.filter(\.isFailed), id: \.row.id) { result in
                    Text("\(result.row.title): \(result.failureMessage ?? "Archive failed")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Retry failed") {
                    Task {
                        await archiveFailedResults()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(store.isExecuting || store.selectedRowIDs.isEmpty)
                .codexAutomationID(AutomationID.ArchiveCleanup.retryFailedButton)
            }
            if !store.isExecuting, !store.executionResults.isEmpty {
                HStack(spacing: 8) {
                    Button("View archived") {
                        onOpenArchivedThreads()
                    }
                    .buttonStyle(.bordered)
                    .codexAutomationID(AutomationID.ArchiveCleanup.viewArchivedButton)

                    if failed == 0 {
                        doneButton(prominent: true)
                    } else {
                        doneButton(prominent: false)
                    }
                }
            }
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .codexAutomationID(AutomationID.ArchiveCleanup.progress)
    }

    @ViewBuilder
    private func doneButton(prominent: Bool) -> some View {
        let button = Button("Done") {
            onClose()
        }
        .codexAutomationID(AutomationID.ArchiveCleanup.doneButton)
        if prominent {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    private func ageButton(_ age: ArchiveCleanupAge) -> some View {
        Button {
            rule.age = age
            Task {
                await store.loadPreview(rule: rule)
            }
        } label: {
            segmentedAgeLabel(age.label, selected: rule.age == age)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(rule.age == age ? .isSelected : [])
        .codexAutomationID(AutomationID.ArchiveCleanup.ageButton(age.label))
    }

    private func segmentedAgeLabel(_ title: String, selected: Bool) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(selected ? .white : .primary)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(selected ? Color.blue : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: selected ? 0 : 1)
            }
    }

    private var isCustomAgeSelected: Bool {
        if case .custom = rule.age {
            return true
        }
        return false
    }

    private var customAgeTitle: String {
        if case .custom(let days) = rule.age {
            return "Custom: \(days)d"
        }
        return "Custom"
    }

    private var customDays: Int {
        Int(customDaysText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    private var confirmationHostSummary: String {
        guard case .preview(let snapshot) = store.state else {
            return "the selected hosts"
        }
        let selectedRows = snapshot.candidates.filter { row in
            store.selectedRowIDs.contains(row.threadIdentity)
        }
        let selectedCountsByHost = Dictionary(
            uniqueKeysWithValues: snapshot.hostSummaries.map { summary in
                let count = selectedRows.filter { row in
                    snapshot.hostIdentityResolver.contains(
                        rowHostID: row.hostID,
                        sourceConfiguredHostID: row.sourceHostID,
                        in: summary.id
                    )
                }.count
                return (summary.id, count)
            }
        )
        let hosts = snapshot.hostSummaries.filter { summary in
            (selectedCountsByHost[summary.id] ?? 0) > 0
        }
        guard !hosts.isEmpty else {
            return "the selected hosts"
        }
        return hosts
            .map { "\($0.displayName): \(selectedCountsByHost[$0.id] ?? 0)" }
            .joined(separator: ", ")
    }

    private func ruleBinding(_ keyPath: WritableKeyPath<ArchiveCleanupRule, Bool>) -> Binding<Bool> {
        Binding(
            get: { rule[keyPath: keyPath] },
            set: { value in
                rule[keyPath: keyPath] = value
                Task {
                    await store.loadPreview(rule: rule)
                }
            }
        )
    }

    private func archiveSelected() async {
        let results = await store.archiveSelected()
        await finishArchiveAttempt(results)
    }

    private func archiveFailedResults() async {
        let results = await store.archiveFailedResults()
        await finishArchiveAttempt(results)
    }

    private func finishArchiveAttempt(_ results: [ArchiveCleanupExecutionResult]) async {
        if results.contains(where: { result in
            if case .archived = result.status { return true }
            return false
        }) {
            await onArchiveSucceeded()
        }
    }

    @MainActor
    private func requestArchive() {
        guard !store.selectedRowIDs.isEmpty, !store.isExecuting else {
            return
        }
        if store.selectedRowIDs.count > CodexDockConstants.ArchiveCleanup.confirmationThreshold {
            isConfirmingArchive = true
        } else {
            Task {
                await archiveSelected()
            }
        }
    }
}

private struct ArchiveCleanupCustomAgeView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var daysText: String
    let onApply: @MainActor (Int) -> Void

    var body: some View {
        Form {
            Section("Archive sessions older than") {
                customAgeField
                if !isValid {
                    Text("Enter 1-3650 days.")
                        .foregroundStyle(.red)
                } else {
                    Text("Enter a number from 1 to 3650.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Custom Age")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Apply") {
                    onApply(days)
                    dismiss()
                }
                .disabled(!isValid)
                .codexAutomationID(AutomationID.ArchiveCleanup.customAgeApplyButton)
            }
        }
    }

    @ViewBuilder
    private var customAgeField: some View {
        #if os(iOS)
        TextField("Days", text: $daysText)
            .keyboardType(.numberPad)
            .codexAutomationID(AutomationID.ArchiveCleanup.customAgeField)
        #else
        TextField("Days", text: $daysText)
            .codexAutomationID(AutomationID.ArchiveCleanup.customAgeField)
        #endif
    }

    private var days: Int {
        Int(daysText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    private var isValid: Bool {
        (1...3650).contains(days)
    }
}

private struct ArchiveCleanupReviewList: View {
    @ObservedObject var store: ArchiveCleanupStore
    let snapshot: ArchiveCleanupPreviewSnapshot
    let rule: ArchiveCleanupRule
    let onArchive: @MainActor () -> Void
    @State private var searchText = ""
    @State private var selectedHostID: String?
    @State private var selectedStatusRawValue: String?
    @State private var selectedBranch: String?
    @State private var showsExcluded = false

    init(
        store: ArchiveCleanupStore,
        snapshot: ArchiveCleanupPreviewSnapshot,
        rule: ArchiveCleanupRule,
        initialHostID: String? = nil,
        onArchive: @escaping @MainActor () -> Void
    ) {
        self.store = store
        self.snapshot = snapshot
        self.rule = rule
        self.onArchive = onArchive
        _selectedHostID = State(initialValue: initialHostID)
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    Text("\(store.selectedRowIDs.count) candidates selected")
                        .font(.headline)
                        .codexAutomationID(AutomationID.ArchiveCleanup.selectedCount)
                    TextField("Search candidates", text: $searchText)
                        .codexAutomationID(AutomationID.ArchiveCleanup.reviewSearchField)
                    filters
                    Toggle("Show excluded", isOn: $showsExcluded)
                        .codexAutomationID(AutomationID.ArchiveCleanup.showExcludedToggle)
                    Text("Older than \(rule.age.days) days - exclusions applied")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            Section("Candidates") {
                ForEach(filteredCandidates) { row in
                    Toggle(isOn: selectionBinding(row.threadIdentity)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.title)
                                .font(.subheadline.weight(.semibold))
                            Text("\(row.repository) - \(row.branch) - \(row.status.label)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(row.hostDisplayName) - \(row.lastActivity) - \(row.threadID)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .codexAutomationID(AutomationID.ArchiveCleanup.selectionToggle(hostID: row.hostID, threadID: row.threadID))
                }
            }

            if showsExcluded, !filteredExcluded.isEmpty {
                Section("Excluded") {
                    ForEach(filteredExcluded.prefix(100)) { excluded in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(excluded.row.title)
                                .font(.subheadline)
                            Text(excluded.reason.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            }
            Divider()
            HStack(spacing: 12) {
                Text("\(store.selectedRowIDs.count) selected")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .codexAutomationID(AutomationID.ArchiveCleanup.selectedCount)
                Spacer()
                Button {
                    onArchive()
                } label: {
                    Label("Archive \(store.selectedRowIDs.count)", systemImage: "archivebox")
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.selectedRowIDs.isEmpty || store.isExecuting)
                .codexAutomationID(AutomationID.ArchiveCleanup.reviewArchiveButton)
            }
            .padding(12)
            .background(.bar)
        }
        .navigationTitle("Review List")
        .codexAutomationID(AutomationID.ArchiveCleanup.reviewList)
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip("All statuses", selected: selectedStatusRawValue == nil) {
                        selectedStatusRawValue = nil
                    }
                    ForEach(statusFilterValues, id: \.rawValue) { status in
                        filterChip(status.label, selected: selectedStatusRawValue == status.rawValue) {
                            selectedStatusRawValue = status.rawValue
                        }
                    }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip("All branches", selected: selectedBranch == nil) {
                        selectedBranch = nil
                    }
                    ForEach(branchFilterValues, id: \.self) { branch in
                        filterChip(branch, selected: selectedBranch == branch) {
                            selectedBranch = branch
                        }
                    }
                }
            }
        }
    }

    private func filterChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(selected ? .white : .primary)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(selected ? Color.blue : Color.clear, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color.secondary.opacity(0.25), lineWidth: selected ? 0 : 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .codexAutomationID(AutomationID.ArchiveCleanup.filterChip(title))
    }

    private var filteredCandidates: [DockRowViewModel] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return snapshot.candidates.filter { row in
            matchesFilters(row) && matchesSearch(row, query: query)
        }
    }

    private var filteredExcluded: [ArchiveCleanupExcludedRow] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return snapshot.excluded.filter { excluded in
            matchesFilters(excluded.row) && matchesSearch(excluded.row, query: query)
        }
    }

    private var statusFilterValues: [DockRowStatusKind] {
        let values = Set(snapshot.candidates.map(\.status.rawValue))
        return DockRowStatusKind.allCases.filter { values.contains($0.rawValue) }
    }

    private var branchFilterValues: [String] {
        Array(Set(snapshot.candidates.map(\.branch))).sorted()
    }

    private func matchesFilters(_ row: DockRowViewModel) -> Bool {
        if let selectedHostID,
           !snapshot.hostIdentityResolver.contains(
               rowHostID: row.hostID,
               sourceConfiguredHostID: row.sourceHostID,
               in: selectedHostID
           ) {
            return false
        }
        if let selectedStatusRawValue, row.status.rawValue != selectedStatusRawValue {
            return false
        }
        if let selectedBranch, row.branch != selectedBranch {
            return false
        }
        return true
    }

    private func matchesSearch(_ row: DockRowViewModel, query: String) -> Bool {
        guard !query.isEmpty else {
            return true
        }
        return [
            row.title,
            row.summary,
            row.repository,
            row.branch,
            row.hostDisplayName,
            row.threadID
        ]
        .joined(separator: " ")
        .lowercased()
        .contains(query)
    }

    private func selectionBinding(_ rowID: HostScopedThreadID) -> Binding<Bool> {
        Binding(
            get: { store.selectedRowIDs.contains(rowID) },
            set: { store.setSelected($0, rowID: rowID) }
        )
    }
}

private extension ArchiveCleanupExecutionResult {
    var isFailed: Bool {
        if case .failed = status {
            return true
        }
        return false
    }

    var failureMessage: String? {
        if case .failed(let message) = status {
            return message
        }
        return nil
    }
}

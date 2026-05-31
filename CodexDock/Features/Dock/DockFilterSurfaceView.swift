import SwiftUI

struct DockFilterSurfaceView: View {
    @Binding var filters: DockFilterState
    let projection: DockCardProjection?
    @State private var branchQuery = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    resultSummary
                    hostSection
                    branchSection
                    statusSection
                    repoSection
                    sourceSection
                    idleSection
                    sortSection
                }
                .padding(16)
            }
            .navigationTitle("Filters")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Clear") {
                        filters = .default
                    }
                    .codexAutomationID(AutomationID.Dock.clearFiltersButton)
                }
            }
            .codexAutomationID(AutomationID.Dock.filterSurface)
        }
    }

    private var resultSummary: some View {
        Text(projection?.summary.text ?? "0 shown")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .codexAutomationID(AutomationID.Dock.filterResultSummary)
    }

    private var hostSection: some View {
        filterSection("Host") {
            chip(
                title: "Any",
                isSelected: filters.selectedHostIDs.isEmpty,
                automationID: AutomationID.Dock.filterHostAny
            ) {
                filters.selectedHostIDs = []
            }
            ForEach(projection?.availableFacets.hosts ?? []) { host in
                chip(
                    title: host.displayName,
                    isSelected: filters.selectedHostIDs.contains(host.id),
                    automationID: AutomationID.Dock.filterHost(hostID: host.id)
                ) {
                    toggle(host.id, in: &filters.selectedHostIDs)
                }
            }
        }
    }

    private var branchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Branch")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("Search branches", text: $branchQuery)
                .codexAutomationID(AutomationID.Dock.filterBranchSearch)
            chipWrap {
                ForEach(filteredBranches, id: \.self) { branch in
                    chip(
                        title: branch,
                        isSelected: filters.selectedBranches.contains(branch),
                        automationID: AutomationID.Dock.filterBranch(branch)
                    ) {
                        toggle(branch, in: &filters.selectedBranches)
                    }
                }
            }
        }
    }

    private var statusSection: some View {
        filterSection("Status") {
            chip(
                title: "Any",
                isSelected: filters.statusKinds == Set(DockRowStatusKind.allCases),
                automationID: AutomationID.Dock.filterStatusAny
            ) {
                filters.statusKinds = Set(DockRowStatusKind.allCases)
            }
            ForEach(statusOptions, id: \.self) { status in
                chip(
                    title: status.label,
                    isSelected: filters.statusKinds != Set(DockRowStatusKind.allCases) && filters.statusKinds.contains(status),
                    automationID: AutomationID.Dock.filterStatus(status.rawValue)
                ) {
                    toggleStatus(status)
                }
            }
        }
    }

    private var repoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Repo")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("Find repo or workspace", text: $filters.repositoryQuery)
                .codexAutomationID(AutomationID.Dock.filterRepoQuery)
            chipWrap {
                chip(
                    title: "Any",
                    isSelected: filters.selectedRepositories.isEmpty && filters.repositoryQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    automationID: nil
                ) {
                    filters.selectedRepositories = []
                    filters.repositoryQuery = ""
                }
                ForEach(projection?.availableFacets.repositories ?? [], id: \.self) { repo in
                    chip(
                        title: repo,
                        isSelected: filters.selectedRepositories.contains(repo),
                        automationID: AutomationID.Dock.filterRepo(repo)
                    ) {
                        toggle(repo, in: &filters.selectedRepositories)
                    }
                }
            }
        }
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Source")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Picker("Source", selection: $filters.source) {
                ForEach(sourceOptions) { source in
                    Text(source.label).tag(source)
                }
            }
            .pickerStyle(.segmented)
            .codexAutomationID(AutomationID.Dock.filterSourcePicker)
        }
    }

    private var idleSection: some View {
        Toggle("Show idle", isOn: $filters.showsIdle)
            .codexAutomationID(AutomationID.Dock.filterIdleToggle)
    }

    private var sortSection: some View {
        filterSection("Sort") {
            chip(title: DockSortOrder.newestActivity.label, isSelected: true, automationID: nil) {
                filters.sortOrder = .newestActivity
            }
        }
    }

    private var filteredBranches: [String] {
        let branches = projection?.availableFacets.branches ?? []
        let query = branchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return branches
        }
        return branches.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    private var statusOptions: [DockRowStatusKind] {
        let present = Set(projection?.availableFacets.statuses ?? DockRowStatusKind.allCases)
        let selected = filters.statusKinds == Set(DockRowStatusKind.allCases) ? [] : filters.statusKinds
        let alwaysAvailable: [DockRowStatusKind] = [.running, .needsInput, .needsApproval, .idle]
        return orderedUnique(alwaysAvailable + DockRowStatusKind.allCases.filter { present.contains($0) } + selected)
    }

    private var sourceOptions: [DockSourceFilter] {
        let present = projection?.availableFacets.sources ?? DockSourceFilter.allCases
        return orderedUnique([.any] + present + [filters.source])
    }

    private func filterSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            chipWrap {
                content()
            }
        }
    }

    private func chipWrap<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], alignment: .leading, spacing: 8) {
            content()
        }
    }

    private func chip(
        title: String,
        isSelected: Bool,
        automationID: AutomationID?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? .white : .primary)
        .background(
            isSelected ? Color.blue : Color.secondary.opacity(0.12),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .codexAutomationID(automationID)
    }

    private func toggle(_ value: String, in set: inout Set<String>) {
        if set.contains(value) {
            set.remove(value)
        } else {
            set.insert(value)
        }
    }

    private func toggleStatus(_ status: DockRowStatusKind) {
        if filters.statusKinds == Set(DockRowStatusKind.allCases) {
            filters.statusKinds = [status]
            return
        }
        if filters.statusKinds.contains(status) {
            filters.statusKinds.remove(status)
            if filters.statusKinds.isEmpty {
                filters.statusKinds = Set(DockRowStatusKind.allCases)
            }
        } else {
            filters.statusKinds.insert(status)
        }
    }

    private func orderedUnique<Value: Hashable>(_ values: [Value]) -> [Value] {
        var seen: Set<Value> = []
        return values.filter { seen.insert($0).inserted }
    }
}

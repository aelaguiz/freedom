import Foundation

struct DockProjectionOptions: Equatable, Sendable {
    let lens: DockLensID
    let searchText: String
    let filters: DockFilterState

    init(
        lens: DockLensID = .newest,
        searchText: String = "",
        filters: DockFilterState = .default
    ) {
        self.lens = lens
        self.searchText = searchText
        self.filters = filters
    }
}

struct DockSessionProjection: Equatable, Sendable {
    let lens: DockLensID
    let rows: [DockRowViewModel]
    let groups: [DockProjectionGroupViewModel]
    let summary: DockProjectionSummary
    let hiddenCounts: DockProjectionHiddenCounts
    let availableFacets: DockProjectionFacets
    let emptyReason: DockProjectionEmptyReason?
    let isPartial: Bool
    let checkingHostCount: Int
}

extension DockSnapshot {
    func project(options: DockProjectionOptions) -> DockSessionProjection {
        DockSessionProjectionProjector(snapshot: self, options: options).project()
    }
}

private struct DockSessionProjectionProjector {
    let snapshot: DockSnapshot
    let options: DockProjectionOptions

    func project() -> DockSessionProjection {
        let searchedRows = snapshot.rows.filter(matchesSearch)
        let filteredIgnoringIdle = searchedRows.filter(matchesNonIdleFilters)
        let hiddenIdleRows = options.filters.showsIdle
            ? []
            : filteredIgnoringIdle.filter { $0.status == .idle }
        let hiddenIdleCount = hiddenIdleRows.count
        let visibleRows = filteredIgnoringIdle
            .filter { options.filters.showsIdle || $0.status != .idle }
            .sorted(by: rowPrecedesByRecency)
        let groups = groups(for: visibleRows, hiddenIdleRows: hiddenIdleRows)
        let emptyReason = visibleRows.isEmpty ? emptyReason(searchedRows: searchedRows, hiddenIdleCount: hiddenIdleCount) : nil

        return DockSessionProjection(
            lens: options.lens,
            rows: options.lens == .newest ? visibleRows : [],
            groups: groups,
            summary: summary(for: visibleRows),
            hiddenCounts: DockProjectionHiddenCounts(idle: hiddenIdleCount),
            availableFacets: availableFacets(),
            emptyReason: emptyReason,
            isPartial: snapshot.isPartial,
            checkingHostCount: snapshot.hostStates.filter { $0.status == .checking }.count
        )
    }

    private func groups(
        for rows: [DockRowViewModel],
        hiddenIdleRows: [DockRowViewModel]
    ) -> [DockProjectionGroupViewModel] {
        switch options.lens {
        case .newest:
            return []
        case .host:
            return hostGroups(for: rows, hiddenIdleRows: hiddenIdleRows)
        case .branch:
            return branchGroups(for: rows, hiddenIdleRows: hiddenIdleRows)
        }
    }

    private func hostGroups(
        for rows: [DockRowViewModel],
        hiddenIdleRows: [DockRowViewModel]
    ) -> [DockProjectionGroupViewModel] {
        let rowsByHost = Dictionary(grouping: rows, by: \.id.hostID)
        let hiddenIdleRowsByHost = Dictionary(grouping: hiddenIdleRows, by: \.id.hostID)
        let stateByHost = Dictionary(uniqueKeysWithValues: snapshot.hostStates.map { ($0.host.id, $0) })
        return snapshot.hosts.compactMap { host in
            if !options.filters.selectedHostIDs.isEmpty,
               !options.filters.selectedHostIDs.contains(host.id) {
                return nil
            }

            let hostRows = (rowsByHost[host.id] ?? []).sorted(by: rowPrecedesByRecency)
            let hiddenIdleCount = hiddenIdleRowsByHost[host.id]?.count ?? 0
            let hostState = stateByHost[host.id]
            let isUnavailable = hostState?.status.isUnavailable ?? false
            guard !hostRows.isEmpty || hiddenIdleCount > 0 || isUnavailable || hostState?.status == .checking else {
                return nil
            }

            return DockProjectionGroupViewModel(
                id: "host::\(host.id)",
                kind: .host,
                title: host.displayName,
                subtitle: hostState?.status.subtitle ?? "\(hostRows.count) sessions",
                rows: hostRows,
                hostIDs: [host.id],
                newestActivityDate: hostRows.map(\.lastActivityDate).max(),
                runningCount: hostRows.filter { $0.status == .running }.count,
                hiddenIdleCount: hiddenIdleCount,
                isUnavailable: isUnavailable,
                unavailableMessage: hostState?.status.unavailableMessage
            )
        }
        .sorted(by: groupPrecedes)
    }

    private func branchGroups(
        for rows: [DockRowViewModel],
        hiddenIdleRows: [DockRowViewModel]
    ) -> [DockProjectionGroupViewModel] {
        let groupedRows = Dictionary(grouping: rows, by: \.branch)
        let hiddenIdleCountsByBranch = Dictionary(grouping: hiddenIdleRows, by: \.branch)
            .mapValues(\.count)
        return groupedRows.map { branch, rows in
            let sortedRows = rows.sorted(by: rowPrecedesByRecency)
            let hostNames = Set(sortedRows.map(\.hostDisplayName)).sorted()
            return DockProjectionGroupViewModel(
                id: "branch::\(branch)",
                kind: .branch,
                title: branch,
                subtitle: "\(sortedRows.count) sessions · \(hostNames.joined(separator: ", "))",
                rows: sortedRows,
                hostIDs: Set(sortedRows.map(\.id.hostID)).sorted(),
                newestActivityDate: sortedRows.map(\.lastActivityDate).max(),
                runningCount: sortedRows.filter { $0.status == .running }.count,
                hiddenIdleCount: hiddenIdleCountsByBranch[branch] ?? 0,
                isUnavailable: false,
                unavailableMessage: nil
            )
        }
        .sorted(by: groupPrecedes)
    }

    private func summary(for rows: [DockRowViewModel]) -> DockProjectionSummary {
        var parts: [String] = ["\(rows.count.formatted()) shown"]
        parts.append(hostSummaryText)
        parts.append(branchSummaryText)
        parts.append(statusSummaryText)
        parts.append(repositorySummaryText)
        parts.append("Source: \(options.filters.source.label)")
        parts.append(options.filters.showsIdle ? "Idle shown" : "Idle hidden")

        let query = normalizedQuery(options.searchText)
        if !query.isEmpty {
            parts.append("Search: \(query)")
        }
        if snapshot.isPartial {
            parts.append("Partial")
        }

        return DockProjectionSummary(
            text: parts.joined(separator: " · "),
            activeFilterCount: options.filters.activeFilterCount + (query.isEmpty ? 0 : 1),
            resultCount: rows.count
        )
    }

    private var hostSummaryText: String {
        guard !options.filters.selectedHostIDs.isEmpty else {
            return "Hosts: Any"
        }
        if options.filters.selectedHostIDs.count == 1,
           let hostID = options.filters.selectedHostIDs.first {
            return "Host: \(hostName(for: hostID))"
        }
        return "Hosts: \(options.filters.selectedHostIDs.count)"
    }

    private var branchSummaryText: String {
        guard !options.filters.selectedBranches.isEmpty else {
            return "Branches: Any"
        }
        if options.filters.selectedBranches.count == 1,
           let branch = options.filters.selectedBranches.first {
            return "Branch: \(branch)"
        }
        return "Branches: \(options.filters.selectedBranches.count)"
    }

    private var statusSummaryText: String {
        let allStatuses = Set(DockRowStatusKind.allCases)
        guard options.filters.statusKinds != allStatuses else {
            return "Status: Any"
        }
        if options.filters.statusKinds.count == 1,
           let status = options.filters.statusKinds.first {
            return "Status: \(status.label)"
        }
        return "Statuses: \(options.filters.statusKinds.count)"
    }

    private var repositorySummaryText: String {
        let query = normalizedQuery(options.filters.repositoryQuery)
        let selectedCount = options.filters.selectedRepositories.count
        if selectedCount == 0, query.isEmpty {
            return "Repo: Any"
        }
        if selectedCount == 1,
           query.isEmpty,
           let repository = options.filters.selectedRepositories.first {
            return "Repo: \(repository)"
        }
        if selectedCount == 0 {
            return "Repo search: \(query)"
        }
        if query.isEmpty {
            return "Repos: \(selectedCount)"
        }
        return "Repos: \(selectedCount), search: \(query)"
    }

    private func availableFacets() -> DockProjectionFacets {
        DockProjectionFacets(
            hosts: snapshot.hosts,
            branches: uniqueSorted(snapshot.rows.map(\.branch)),
            statuses: DockRowStatusKind.allCases.filter { status in
                snapshot.rows.contains { $0.status == status }
            },
            repositories: uniqueSorted(snapshot.rows.map(\.repository)),
            sources: DockSourceFilter.allCases.filter { source in
                source == .any || snapshot.rows.contains { source.includes($0.origin) }
            }
        )
    }

    private func hostName(for hostID: String) -> String {
        snapshot.hosts.first { $0.id == hostID }?.displayName ?? hostID
    }

    private func emptyReason(
        searchedRows: [DockRowViewModel],
        hiddenIdleCount: Int
    ) -> DockProjectionEmptyReason {
        if snapshot.rows.isEmpty {
            return .noData
        }
        if hiddenIdleCount > 0 {
            return .idleHidden
        }
        if !normalizedQuery(options.searchText).isEmpty, searchedRows.isEmpty {
            return .noSearchMatches
        }
        if selectedHostsAreUnavailable {
            return .hostUnavailable
        }
        return .noFilterMatches
    }

    private var selectedHostsAreUnavailable: Bool {
        guard !options.filters.selectedHostIDs.isEmpty else {
            return false
        }
        let states = snapshot.hostStates.filter { options.filters.selectedHostIDs.contains($0.host.id) }
        return !states.isEmpty && states.allSatisfy(\.status.isUnavailable)
    }

    private func matchesNonIdleFilters(_ row: DockRowViewModel) -> Bool {
        if !options.filters.selectedHostIDs.isEmpty,
           !options.filters.selectedHostIDs.contains(row.id.hostID) {
            return false
        }
        if !options.filters.selectedBranches.isEmpty,
           !options.filters.selectedBranches.contains(where: { selected in
               row.branch.compare(selected, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
           }) {
            return false
        }
        if !options.filters.statusKinds.contains(row.status) {
            return false
        }
        if !options.filters.selectedRepositories.isEmpty,
           !options.filters.selectedRepositories.contains(row.repository) {
            return false
        }
        let repositoryQuery = normalizedQuery(options.filters.repositoryQuery)
        if !repositoryQuery.isEmpty,
           !row.repository.localizedCaseInsensitiveContains(repositoryQuery) {
            return false
        }
        return options.filters.source.includes(row.origin)
    }

    private func matchesSearch(_ row: DockRowViewModel) -> Bool {
        let query = normalizedQuery(options.searchText)
        guard !query.isEmpty else {
            return true
        }

        return searchableValues(for: row).contains { value in
            value.localizedCaseInsensitiveContains(query)
        }
    }

    private func searchableValues(for row: DockRowViewModel) -> [String] {
        [
            row.title,
            row.hostDisplayName,
            row.id.hostID,
            row.repository,
            row.branch,
            row.summary,
            row.status.label,
            row.label,
            row.origin.automationKind,
            row.id.threadID
        ].compactMap { $0 }
    }

    private func groupPrecedes(_ lhs: DockProjectionGroupViewModel, _ rhs: DockProjectionGroupViewModel) -> Bool {
        let lhsDate = lhs.newestActivityDate ?? Date.distantPast
        let rhsDate = rhs.newestActivityDate ?? Date.distantPast
        if lhsDate != rhsDate {
            return lhsDate > rhsDate
        }

        let titleOrder = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
        if titleOrder != .orderedSame {
            return titleOrder == .orderedAscending
        }
        return lhs.id < rhs.id
    }

    private func rowPrecedesByRecency(_ lhs: DockRowViewModel, _ rhs: DockRowViewModel) -> Bool {
        if lhs.lastActivityDate != rhs.lastActivityDate {
            return lhs.lastActivityDate > rhs.lastActivityDate
        }

        let titleOrder = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
        if titleOrder != .orderedSame {
            return titleOrder == .orderedAscending
        }

        return "\(lhs.id.hostID)::\(lhs.id.threadID)" < "\(rhs.id.hostID)::\(rhs.id.threadID)"
    }

    private func normalizedQuery(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func uniqueSorted(_ values: [String]) -> [String] {
        Set(values).sorted { lhs, rhs in
            lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }
}

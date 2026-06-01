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

struct DockCardProjection: Equatable, Sendable {
    let lens: DockLensID
    let pinnedRows: [DockRowViewModel]
    let allPinnedRows: [DockRowViewModel]
    let pinnedSummary: DockPinnedSummary
    let rows: [DockRowViewModel]
    let groups: [DockProjectionGroupViewModel]
    let summary: DockProjectionSummary
    let availableFacets: DockProjectionFacets
    let emptyReason: DockProjectionEmptyReason?
    let isPartial: Bool
    let checkingHostCount: Int
}

extension DockSnapshot {
    func project(options: DockProjectionOptions) -> DockCardProjection {
        DockCardProjectionProjector(snapshot: self, options: options).project()
    }
}

private struct DockCardProjectionProjector {
    let snapshot: DockSnapshot
    let options: DockProjectionOptions

    func project() -> DockCardProjection {
        let searchedRows = snapshot.rows.filter(matchesSearch)
        // Idle is a normal status facet. Do not add a second visibility gate.
        let filteredRows = searchedRows.filter(matchesFilters)
        let pinnedRows = filteredRows.filter(\.isPinned).sorted(by: pinnedRowPrecedes)
        let bodyRows = filteredRows
            .filter { !$0.isPinned }
            .sorted(by: rowPrecedesByRelayOrder)
        let visibleRows = (pinnedRows + bodyRows).sorted(by: rowPrecedesByRelayOrder)
        let allPinnedRows = snapshot.rows.filter(\.isPinned).sorted(by: pinnedRowPrecedes)
        let groups = groups(for: bodyRows)
        let emptyReason = visibleRows.isEmpty ? emptyReason(searchedRows: searchedRows) : nil

        return DockCardProjection(
            lens: options.lens,
            pinnedRows: pinnedRows,
            allPinnedRows: allPinnedRows,
            pinnedSummary: DockPinnedSummary(
                visibleCount: pinnedRows.count,
                totalCount: allPinnedRows.count,
                hiddenByScopeCount: max(0, allPinnedRows.count - pinnedRows.count)
            ),
            rows: options.lens == .newest ? bodyRows : [],
            groups: groups,
            summary: summary(for: visibleRows),
            availableFacets: availableFacets(),
            emptyReason: emptyReason,
            isPartial: snapshot.isPartial,
            checkingHostCount: snapshot.hostStates.filter { $0.status == .checking }.count
        )
    }

    private func groups(
        for rows: [DockRowViewModel]
    ) -> [DockProjectionGroupViewModel] {
        switch options.lens {
        case .newest:
            return []
        case .host:
            return hostGroups(for: rows)
        case .branch:
            return branchGroups(for: rows)
        }
    }

    private func hostGroups(
        for rows: [DockRowViewModel]
    ) -> [DockProjectionGroupViewModel] {
        let stateByHost = Dictionary(uniqueKeysWithValues: snapshot.hostStates.map { ($0.host.id, $0) })
        return snapshot.hosts.compactMap { host in
            if !options.filters.selectedHostIDs.isEmpty,
               !options.filters.selectedHostIDs.contains(host.id) {
                return nil
            }

            let hostRows = rows
                .filter { rowBelongs($0, to: host.id) }
                .sorted(by: rowPrecedesByRelayOrder)
            let hostState = stateByHost[host.id]
            let isUnavailable = hostState?.status.isUnavailable ?? false
            guard !hostRows.isEmpty || isUnavailable || hostState?.status == .checking else {
                return nil
            }

            return DockProjectionGroupViewModel(
                id: "host::\(host.id)",
                kind: .host,
                title: host.displayName,
                subtitle: hostState?.status.subtitle ?? "\(hostRows.count) sessions",
                rows: hostRows,
                hostIDs: [host.id],
                orderKey: hostRows.first?.orderKey,
                newestActivityDate: hostRows.map(\.lastActivityDate).max(),
                runningCount: hostRows.filter { $0.status == .running }.count,
                isUnavailable: isUnavailable,
                unavailableMessage: hostState?.status.unavailableMessage
            )
        }
        .sorted(by: groupPrecedes)
    }

    private func branchGroups(
        for rows: [DockRowViewModel]
    ) -> [DockProjectionGroupViewModel] {
        let groupedRows = Dictionary(grouping: rows, by: \.branch)
        return groupedRows.map { branch, rows in
            let sortedRows = rows.sorted(by: rowPrecedesByRelayOrder)
            let hostNames = Set(sortedRows.map(\.hostDisplayName)).sorted()
            return DockProjectionGroupViewModel(
                id: "branch::\(branch)",
                kind: .branch,
                title: branch,
                subtitle: "\(sortedRows.count) sessions · \(hostNames.joined(separator: ", "))",
                rows: sortedRows,
                hostIDs: Set(sortedRows.map(hostIDForGroup)).sorted(),
                orderKey: sortedRows.first?.orderKey,
                newestActivityDate: sortedRows.map(\.lastActivityDate).max(),
                runningCount: sortedRows.filter { $0.status == .running }.count,
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
        searchedRows: [DockRowViewModel]
    ) -> DockProjectionEmptyReason {
        if snapshot.rows.isEmpty {
            return .noData
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

    private func matchesFilters(_ row: DockRowViewModel) -> Bool {
        if !options.filters.selectedHostIDs.isEmpty,
           !options.filters.selectedHostIDs.contains(where: { selectedHostID in
               rowBelongs(row, to: selectedHostID)
           }) {
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

    private func rowBelongs(_ row: DockRowViewModel, to configuredHostID: String) -> Bool {
        snapshot.hostIdentityResolver.contains(
            rowHostID: row.id.hostID,
            sourceConfiguredHostID: row.sourceHostID,
            in: configuredHostID
        )
            || row.sourceHostID == configuredHostID
    }

    private func hostIDForGroup(_ row: DockRowViewModel) -> String {
        snapshot.hostIdentityResolver.resolve(
            rowHostID: row.id.hostID,
            sourceConfiguredHostID: row.sourceHostID
        )?.host.id
            ?? row.sourceHostID
            ?? row.id.hostID
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
        if let lhsOrderKey = lhs.orderKey,
           let rhsOrderKey = rhs.orderKey,
           lhsOrderKey != rhsOrderKey {
            return lhsOrderKey < rhsOrderKey
        }
        if lhs.orderKey != nil {
            return true
        }
        if rhs.orderKey != nil {
            return false
        }

        let titleOrder = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
        if titleOrder != .orderedSame {
            return titleOrder == .orderedAscending
        }
        return lhs.id < rhs.id
    }

    private func rowPrecedesByRelayOrder(_ lhs: DockRowViewModel, _ rhs: DockRowViewModel) -> Bool {
        // The relay owns card ordering. Swift may filter and group rows, but it
        // must not rebuild recency from timestamps or local status.
        if let lhsOrderKey = lhs.orderKey,
           let rhsOrderKey = rhs.orderKey {
            if lhsOrderKey == rhsOrderKey {
                return stableRowID(lhs) < stableRowID(rhs)
            }
            return lhsOrderKey < rhsOrderKey
        }
        if lhs.orderKey != nil {
            return true
        }
        if rhs.orderKey != nil {
            return false
        }

        let titleOrder = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
        if titleOrder != .orderedSame {
            return titleOrder == .orderedAscending
        }

        return stableRowID(lhs) < stableRowID(rhs)
    }

    private func pinnedRowPrecedes(_ lhs: DockRowViewModel, _ rhs: DockRowViewModel) -> Bool {
        if let lhsOrder = lhs.pinnedOrder,
           let rhsOrder = rhs.pinnedOrder,
           lhsOrder != rhsOrder {
            return lhsOrder < rhsOrder
        }
        if lhs.pinnedOrder != nil {
            return true
        }
        if rhs.pinnedOrder != nil {
            return false
        }

        let lhsPinnedAt = lhs.pinnedAt ?? Date.distantPast
        let rhsPinnedAt = rhs.pinnedAt ?? Date.distantPast
        if lhsPinnedAt != rhsPinnedAt {
            return lhsPinnedAt < rhsPinnedAt
        }

        return stableRowID(lhs) < stableRowID(rhs)
    }

    private func stableRowID(_ row: DockRowViewModel) -> String {
        "\(row.id.hostID)::\(row.id.threadID)"
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

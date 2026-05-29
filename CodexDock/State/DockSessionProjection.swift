import Foundation

enum DockSessionSortMode: String, CaseIterable, Identifiable, Sendable {
    case branch
    case newest

    var id: String { rawValue }

    var label: String {
        switch self {
        case .branch:
            return "Branch"
        case .newest:
            return "Newest"
        }
    }
}

struct DockSessionProjectionOptions: Equatable, Sendable {
    let selectedTab: DockTabID
    let searchText: String
    let sortMode: DockSessionSortMode
    let showsIdle: Bool

    init(
        selectedTab: DockTabID,
        searchText: String = "",
        sortMode: DockSessionSortMode = .branch,
        showsIdle: Bool = false
    ) {
        self.selectedTab = selectedTab
        self.searchText = searchText
        self.sortMode = sortMode
        self.showsIdle = showsIdle
    }
}

struct DockSessionProjection: Equatable, Sendable {
    let tabs: [DockTabViewModel]
    let sections: [DockSectionViewModel]
    let hiddenIdleMatchCount: Int
}

extension DockSnapshot {
    func project(options: DockSessionProjectionOptions) -> DockSessionProjection {
        DockSessionProjectionProjector(
            baseSections: sections,
            hostNameByID: Dictionary(uniqueKeysWithValues: hosts.map { ($0.id, $0.displayName) }),
            options: options
        ).project()
    }
}

private struct DockSessionProjectionProjector {
    let baseSections: [DockSectionViewModel]
    let hostNameByID: [String: String]
    let options: DockSessionProjectionOptions

    func project() -> DockSessionProjection {
        let allRows = baseSections.flatMap(\.rows)
        let searchedRows = allRows.filter(matchesSearch)
        let visibleRowsForCounts = searchedRows.filter(isIdleVisible)
        let tabRows = visibleRowsForCounts.filter(options.selectedTab.includes)

        return DockSessionProjection(
            tabs: DockTabID.allCases.map { tab in
                DockTabViewModel(id: tab, count: visibleRowsForCounts.filter(tab.includes).count)
            },
            sections: sections(for: tabRows),
            hiddenIdleMatchCount: hiddenIdleMatchCount(in: searchedRows)
        )
    }

    private func sections(for rows: [DockRowViewModel]) -> [DockSectionViewModel] {
        switch options.sortMode {
        case .branch:
            return branchSections(for: rows)
        case .newest:
            let sortedRows = rows.sorted(by: rowPrecedesByRecency)
            guard !sortedRows.isEmpty else {
                return []
            }
            return [
                DockSectionViewModel(id: "newest", title: "Newest", rows: sortedRows)
            ]
        }
    }

    private func branchSections(for rows: [DockRowViewModel]) -> [DockSectionViewModel] {
        let visibleIDs = Set(rows.map(\.id))
        return baseSections
            .compactMap { section in
                let sectionRows = section.rows
                    .filter { row in visibleIDs.contains(row.id) }
                    .sorted(by: rowPrecedesByRecency)
                guard !sectionRows.isEmpty else {
                    return nil
                }
                return DockSectionViewModel(id: section.id, title: section.title, rows: sectionRows)
            }
            .sorted(by: sectionPrecedesByRecency)
    }

    private func hiddenIdleMatchCount(in searchedRows: [DockRowViewModel]) -> Int {
        guard !options.showsIdle else {
            return 0
        }

        return searchedRows.filter { row in
            options.selectedTab.includes(row) && row.status == .idle
        }.count
    }

    private func isIdleVisible(_ row: DockRowViewModel) -> Bool {
        options.showsIdle || row.status != .idle
    }

    private func matchesSearch(_ row: DockRowViewModel) -> Bool {
        let query = options.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
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
            row.repository,
            row.branch,
            row.summary,
            row.status.label,
            row.label,
            hostNameByID[row.id.hostID],
            row.id.hostID,
            row.id.threadID
        ].compactMap { $0 }
    }

    private func sectionPrecedesByRecency(_ lhs: DockSectionViewModel, _ rhs: DockSectionViewModel) -> Bool {
        let lhsDate = lhs.rows.map(\.lastActivityDate).max() ?? Date.distantPast
        let rhsDate = rhs.rows.map(\.lastActivityDate).max() ?? Date.distantPast
        if lhsDate != rhsDate {
            return lhsDate > rhsDate
        }

        let lhsPriority = lhs.rows.map { SessionRowProjector.statusPriority($0.status) }.min() ?? Int.max
        let rhsPriority = rhs.rows.map { SessionRowProjector.statusPriority($0.status) }.min() ?? Int.max
        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
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

        let lhsPriority = SessionRowProjector.statusPriority(lhs.status)
        let rhsPriority = SessionRowProjector.statusPriority(rhs.status)
        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
        }

        let titleOrder = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
        if titleOrder != .orderedSame {
            return titleOrder == .orderedAscending
        }

        return stableID(lhs) < stableID(rhs)
    }

    private func stableID(_ row: DockRowViewModel) -> String {
        "\(row.id.hostID)::\(row.id.threadID)"
    }
}

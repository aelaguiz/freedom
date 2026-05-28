import Foundation

struct SessionRowProjector {
    let hosts: [DockHostConfiguration]
    let localMetadata: [LocalThreadMetadataKey: LocalThreadMetadata]
    let now: @Sendable () -> Date

    func sections(from summaries: [SessionSummary]) -> [DockSectionViewModel] {
        let rows = summaries.map(makeRow)
        let groupedRows = Dictionary(grouping: rows, by: sectionID(for:))
        return groupedRows
            .map { sectionID, rows in
                DockSectionViewModel(
                    id: sectionID,
                    title: sectionTitle(for: rows[0]),
                    rows: rows.sorted(by: rowPrecedes)
                )
            }
            .sorted(by: sectionPrecedes)
    }

    func makeRow(summary: SessionSummary) -> DockRowViewModel {
        let metadata = localMetadata[
            LocalThreadMetadataKey(
                hostID: summary.id.hostID,
                backendSessionID: summary.backendSessionID,
                threadID: summary.id.threadID
            )
        ]
        return DockRowViewModel(
            id: summary.id,
            backendSessionID: summary.backendSessionID,
            title: title(for: summary),
            repository: repository(for: summary),
            branch: text(summary.branch, fallback: "No branch"),
            status: status(for: summary),
            lastActivity: relativeTime(since: summary.lastActivity),
            lastActivityDate: summary.lastActivity,
            summary: latestSummary(for: summary),
            rail: metadata?.rail ?? rail(for: summary),
            label: metadata?.label
        )
    }

    private func sectionID(for row: DockRowViewModel) -> String {
        hosts.count > 1 ? "\(row.id.hostID)::\(row.branch)" : row.branch
    }

    private func sectionTitle(for row: DockRowViewModel) -> String {
        guard hosts.count > 1 else {
            return row.branch
        }
        let hostName = hosts.first { $0.id == row.id.hostID }?.displayName ?? row.id.hostID
        return "\(hostName) / \(row.branch)"
    }

    private func sectionPrecedes(_ lhs: DockSectionViewModel, _ rhs: DockSectionViewModel) -> Bool {
        let lhsPriority = lhs.rows.map { Self.statusPriority($0.status) }.min() ?? Int.max
        let rhsPriority = rhs.rows.map { Self.statusPriority($0.status) }.min() ?? Int.max
        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
        }

        let lhsDate = lhs.rows.map(\.lastActivityDate).max() ?? Date.distantPast
        let rhsDate = rhs.rows.map(\.lastActivityDate).max() ?? Date.distantPast
        if lhsDate != rhsDate {
            return lhsDate > rhsDate
        }

        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private func rowPrecedes(_ lhs: DockRowViewModel, _ rhs: DockRowViewModel) -> Bool {
        let lhsPriority = Self.statusPriority(lhs.status)
        let rhsPriority = Self.statusPriority(rhs.status)
        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
        }

        if lhs.lastActivityDate != rhs.lastActivityDate {
            return lhs.lastActivityDate > rhs.lastActivityDate
        }

        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    static func statusPriority(_ status: DockRowStatusKind) -> Int {
        switch status {
        case .needsMe:
            return 0
        case .running:
            return 1
        case .failed:
            return 2
        case .idle:
            return 3
        case .unknown:
            return 4
        case .limited:
            return 5
        }
    }

    private func title(for summary: SessionSummary) -> String {
        nonEmpty(summary.displayTitle) ?? summary.id.threadID
    }

    private func repository(for summary: SessionSummary) -> String {
        if let repo = nonEmpty(text(summary.repository, fallback: "")) {
            return repo
        }

        return text(summary.workingDirectory, fallback: "Unknown workspace")
    }

    private func latestSummary(for summary: SessionSummary) -> String {
        if let eventSummary = nonEmpty(text(summary.shortEventSummary, fallback: "")) {
            return eventSummary
        }

        return summary.displayTitle
    }

    private func status(for summary: SessionSummary) -> DockRowStatusKind {
        switch summary.status {
        case .idle:
            return .idle
        case .active(let activeFlags):
            return activeFlags.contains(.waitingOnApproval) || activeFlags.contains(.waitingOnUserInput)
                ? .needsMe
                : .running
        case .notLoaded:
            return .limited
        case .systemError:
            return .failed
        case .unknown:
            return .unknown
        }
    }

    private func relativeTime(since date: Date) -> String {
        let seconds = max(0, Int(now().timeIntervalSince(date)))

        switch seconds {
        case 0..<60:
            return "now"
        case 60..<3_600:
            return "\(seconds / 60)m ago"
        case 3_600..<86_400:
            return "\(seconds / 3_600)h ago"
        default:
            return "\(seconds / 86_400)d ago"
        }
    }

    private func rail(for summary: SessionSummary) -> DockRowRail {
        let rails = DockRowRail.allCases
        let checksum = summary.id.threadID.utf8.reduce(UInt64(0)) { partial, byte in
            (partial &* 31) &+ UInt64(byte)
        }
        return rails[Int(checksum % UInt64(rails.count))]
    }

    private func text(_ value: SessionSummaryText, fallback: String) -> String {
        switch value {
        case let .known(text):
            return nonEmpty(text) ?? fallback
        case .unknown:
            return fallback
        }
    }

    private func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            return trimmed
        }
        return nil
    }
}

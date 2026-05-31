import Foundation

struct ArchiveThreadCardProjector {
    let hosts: [DockHostConfiguration]
    let hostIdentityResolver: DockHostIdentityResolver
    let localMetadata: [LocalThreadMetadataKey: LocalThreadMetadata]
    let now: @Sendable () -> Date

    func sections(from cardBatches: [(hostID: String, cards: [DockThreadCardDTO])]) -> [DockSectionViewModel] {
        let rowProjector = ThreadCardRowProjector(
            hosts: hosts,
            hostIdentityResolver: hostIdentityResolver,
            localMetadata: localMetadata,
            now: now
        )
        let rows = cardBatches.flatMap { batch in
            rowProjector.rows(from: batch.cards, sourceHostID: batch.hostID)
        }
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

    private func sectionID(for row: DockRowViewModel) -> String {
        hosts.count > 1 ? "\(row.id.hostID)::\(row.branch)" : row.branch
    }

    private func sectionTitle(for row: DockRowViewModel) -> String {
        guard hosts.count > 1 else {
            return row.branch
        }
        return "\(row.hostDisplayName) / \(row.branch)"
    }

    private func sectionPrecedes(_ lhs: DockSectionViewModel, _ rhs: DockSectionViewModel) -> Bool {
        if let lhsOrderKey = sectionOrderKey(lhs),
           let rhsOrderKey = sectionOrderKey(rhs),
           lhsOrderKey != rhsOrderKey {
            return lhsOrderKey < rhsOrderKey
        }

        let lhsDate = lhs.rows.map(\.lastActivityDate).max() ?? Date.distantPast
        let rhsDate = rhs.rows.map(\.lastActivityDate).max() ?? Date.distantPast
        if lhsDate != rhsDate {
            return lhsDate > rhsDate
        }

        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private func sectionOrderKey(_ section: DockSectionViewModel) -> String? {
        section.rows.compactMap(\.orderKey).min()
    }

    private func rowPrecedes(_ lhs: DockRowViewModel, _ rhs: DockRowViewModel) -> Bool {
        if let lhsOrderKey = lhs.orderKey,
           let rhsOrderKey = rhs.orderKey,
           lhsOrderKey != rhsOrderKey {
            return lhsOrderKey < rhsOrderKey
        }

        if lhs.lastActivityDate != rhs.lastActivityDate {
            return lhs.lastActivityDate > rhs.lastActivityDate
        }

        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }
}

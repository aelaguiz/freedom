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
            rowProjector.rows(from: batch.cards)
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
        hosts.count > 1 ? "\(row.hostID)::\(row.branch)" : row.branch
    }

    private func sectionTitle(for row: DockRowViewModel) -> String {
        guard hosts.count > 1 else {
            return row.branch
        }
        return "\(row.hostDisplayName) / \(row.branch)"
    }

    private func sectionPrecedes(_ lhs: DockSectionViewModel, _ rhs: DockSectionViewModel) -> Bool {
        // Archive ordering follows relay displayOrderKey only. Do not rebuild
        // recency locally from timestamps.
        if let lhsOrderKey = sectionOrderKey(lhs),
           let rhsOrderKey = sectionOrderKey(rhs),
           lhsOrderKey != rhsOrderKey {
            return lhsOrderKey < rhsOrderKey
        }

        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private func sectionOrderKey(_ section: DockSectionViewModel) -> String? {
        section.rows.map(\.displayOrderKey).min()
    }

    private func rowPrecedes(_ lhs: DockRowViewModel, _ rhs: DockRowViewModel) -> Bool {
        // The relay owns card recency. Archive may group rows, but row order is
        // still relay displayOrderKey, then projectionID.
        if lhs.displayOrderKey != rhs.displayOrderKey {
            return lhs.displayOrderKey < rhs.displayOrderKey
        }

        return lhs.id < rhs.id
    }
}

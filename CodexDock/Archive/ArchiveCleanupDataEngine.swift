import Foundation

actor ArchiveCleanupDataEngine {
    private let now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    func makePreview(
        from snapshot: DockSnapshot,
        rule: ArchiveCleanupRule
    ) -> ArchiveCleanupPreviewSnapshot {
        let rows = snapshot.rows

        var candidates: [DockRowViewModel] = []
        var excluded: [ArchiveCleanupExcludedRow] = []
        for row in rows {
            if let reason = exclusionReason(for: row, rule: rule) {
                excluded.append(ArchiveCleanupExcludedRow(row: row, reason: reason))
            } else {
                candidates.append(row)
            }
        }

        let hostSummaries = snapshot.hosts.map { host in
            ArchiveCleanupHostSummary(
                id: host.id,
                displayName: host.displayName,
                candidateCount: candidates.filter { row in
                    snapshot.hostIdentityResolver.contains(
                        rowHostID: row.hostID,
                        sourceConfiguredHostID: row.sourceHostID,
                        in: host.id
                    )
                }.count,
                excludedCount: excluded.filter { excludedRow in
                    snapshot.hostIdentityResolver.contains(
                        rowHostID: excludedRow.row.hostID,
                        sourceConfiguredHostID: excludedRow.row.sourceHostID,
                        in: host.id
                    )
                }.count
            )
        }

        return ArchiveCleanupPreviewSnapshot(
            hosts: snapshot.hosts,
            hostStates: snapshot.hostStates,
            hostIdentityResolver: snapshot.hostIdentityResolver,
            hostSummaries: hostSummaries,
            candidates: candidates.sorted(by: rowPrecedes),
            excluded: excluded.sorted { lhs, rhs in
                rowPrecedes(lhs.row, rhs.row)
            }
        )
    }

    private func rowPrecedes(_ lhs: DockRowViewModel, _ rhs: DockRowViewModel) -> Bool {
        // Cleanup previews use relay displayOrderKey, then projectionID.
        if lhs.displayOrderKey != rhs.displayOrderKey {
            return lhs.displayOrderKey < rhs.displayOrderKey
        }
        return lhs.id < rhs.id
    }

    private func exclusionReason(
        for row: DockRowViewModel,
        rule: ArchiveCleanupRule
    ) -> ArchiveCleanupExclusionReason? {
        let cutoff = now().addingTimeInterval(-Double(rule.age.days) * 86_400)
        if row.lastActivityDate >= cutoff {
            return .tooRecent
        }
        if row.origin.kind != .humanInteractive {
            return .nonHuman
        }
        if rule.excludesPinned, row.isPinned {
            return .pinned
        }
        if rule.excludesRunning, row.status == .running {
            return .running
        }
        if rule.excludesNeedsInput, row.status == .needsInput {
            return .needsInput
        }
        if rule.excludesNeedsInput, row.status == .needsApproval {
            return .needsApproval
        }
        if rule.excludesWatchLabel, row.label?.localizedCaseInsensitiveCompare("Watch") == .orderedSame {
            return .watchLabel
        }
        return nil
    }
}

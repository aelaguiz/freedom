import Foundation

actor ArchiveCleanupDataEngine {
    private var hosts: [DockHostConfiguration]
    private let streamClient: any ThreadCardStreamConnecting
    private let metadataStore: any LocalThreadMetadataStoring
    private let now: @Sendable () -> Date
    private var localMetadata: [LocalThreadMetadataKey: LocalThreadMetadata] = [:]

    init(
        registry: HostRegistry,
        streamClient: any ThreadCardStreamConnecting,
        metadataStore: any LocalThreadMetadataStoring,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.hosts = registry.hosts
        self.streamClient = streamClient
        self.metadataStore = metadataStore
        self.now = now
    }

    func updateRegistry(_ registry: HostRegistry) {
        hosts = registry.hosts
    }

    func loadPreview(rule: ArchiveCleanupRule) async -> ArchiveCleanupPreviewSnapshot {
        do {
            localMetadata = try await metadataStore.load()
        } catch {
            localMetadata = [:]
            DockLog.persistence.warning("archive cleanup metadata load failed error=\(DockLog.errorSummary(error), privacy: .public)")
        }

        let outcomes = await loadAllHosts()
        return makePreview(outcomes: outcomes, rule: rule)
    }

    private func loadAllHosts() async -> [ThreadCardHostLoadOutcome] {
        await ThreadCardHostSnapshotLoader(
            streamClient: streamClient,
            expectedView: .dock,
            operation: "archive cleanup"
        ).loadAll(hosts: hosts)
    }

    private func makePreview(
        outcomes: [ThreadCardHostLoadOutcome],
        rule: ArchiveCleanupRule
    ) -> ArchiveCleanupPreviewSnapshot {
        var cards: [DockThreadCardDTO] = []
        var hostStates: [DockHostStateViewModel] = []

        for outcome in outcomes {
            let host = DockHostViewModel(host: outcome.host)
            switch outcome.result {
            case .success(let hostCards):
                cards.append(contentsOf: hostCards)
                hostStates.append(
                    DockHostStateViewModel(
                        host: host,
                        status: hostCards.isEmpty ? .empty : .loaded(rowCount: hostCards.count)
                    )
                )
            case .failure(let failure):
                switch failure {
                case .offline(let message):
                    hostStates.append(DockHostStateViewModel(host: host, status: .offline(message)))
                case .error(let message):
                    hostStates.append(DockHostStateViewModel(host: host, status: .error(message)))
                }
            }
        }

        let rows = ThreadCardRowProjector(
            hosts: hosts,
            localMetadata: localMetadata,
            now: now
        ).rows(from: cards)

        var candidates: [DockRowViewModel] = []
        var excluded: [ArchiveCleanupExcludedRow] = []
        for row in rows {
            if let reason = exclusionReason(for: row, rule: rule) {
                excluded.append(ArchiveCleanupExcludedRow(row: row, reason: reason))
            } else {
                candidates.append(row)
            }
        }

        let groupedCandidates = Dictionary(grouping: candidates, by: \.id.hostID)
        let groupedExcluded = Dictionary(grouping: excluded, by: { $0.row.id.hostID })
        let hostSummaries = hosts.map { host in
            ArchiveCleanupHostSummary(
                id: host.id,
                displayName: host.displayName,
                candidateCount: countRows(groupedCandidates, for: host),
                excludedCount: countExcluded(groupedExcluded, for: host)
            )
        }

        return ArchiveCleanupPreviewSnapshot(
            hosts: hosts.map(DockHostViewModel.init),
            hostStates: hostStates,
            hostSummaries: hostSummaries,
            candidates: candidates.sorted(by: rowPrecedes),
            excluded: excluded.sorted { lhs, rhs in
                rowPrecedes(lhs.row, rhs.row)
            }
        )
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
        return "\(lhs.id.hostID)::\(lhs.id.threadID)" < "\(rhs.id.hostID)::\(rhs.id.threadID)"
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

    private func countRows(
        _ grouped: [String: [DockRowViewModel]],
        for host: DockHostConfiguration
    ) -> Int {
        hostAliases(host).reduce(0) { count, alias in
            count + (grouped[alias]?.count ?? 0)
        }
    }

    private func countExcluded(
        _ grouped: [String: [ArchiveCleanupExcludedRow]],
        for host: DockHostConfiguration
    ) -> Int {
        hostAliases(host).reduce(0) { count, alias in
            count + (grouped[alias]?.count ?? 0)
        }
    }

    private func hostAliases(_ host: DockHostConfiguration) -> Set<String> {
        [host.id, host.displayName, host.endpoint.displayEndpoint]
    }
}

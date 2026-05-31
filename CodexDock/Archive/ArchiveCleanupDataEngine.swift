import Foundation

actor ArchiveCleanupDataEngine {
    private var hosts: [DockHostConfiguration]
    private let streamClient: any ThreadCardStreamConnecting
    private let metadataEngine: LocalMetadataEngine
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
        self.metadataEngine = LocalMetadataEngine(store: metadataStore, now: now)
        self.now = now
    }

    func updateRegistry(_ registry: HostRegistry) {
        hosts = registry.hosts
    }

    func loadPreview(rule: ArchiveCleanupRule) async -> ArchiveCleanupPreviewSnapshot {
        do {
            localMetadata = try await metadataEngine.load()
        } catch {
            localMetadata = [:]
            await metadataEngine.replace(localMetadata)
            DockLog.persistence.warning("archive cleanup metadata load failed error=\(DockLog.errorSummary(error), privacy: .public)")
        }

        let outcomes = await loadAllHosts()
        let resolver = hostIdentityResolver(outcomes: outcomes)
        await migrateMetadataHostAliases(using: resolver)
        return makePreview(outcomes: outcomes, rule: rule, resolver: resolver)
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
        rule: ArchiveCleanupRule,
        resolver: DockHostIdentityResolver
    ) -> ArchiveCleanupPreviewSnapshot {
        var cardBatches: [(hostID: String, cards: [DockThreadCardDTO])] = []
        var hostStates: [DockHostStateViewModel] = []

        for outcome in outcomes {
            let host = DockHostViewModel(host: outcome.host)
            switch outcome.result {
            case .success(let collection):
                cardBatches.append((hostID: outcome.host.id, cards: collection.cards))
                hostStates.append(
                    DockHostStateViewModel(
                        host: host,
                        status: collection.hostLoadStatus
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

        let rowProjector = ThreadCardRowProjector(
            hosts: hosts,
            hostIdentityResolver: resolver,
            localMetadata: localMetadata,
            now: now
        )
        let rows = cardBatches.flatMap { batch in
            rowProjector.rows(from: batch.cards, sourceHostID: batch.hostID)
        }

        var candidates: [DockRowViewModel] = []
        var excluded: [ArchiveCleanupExcludedRow] = []
        for row in rows {
            if let reason = exclusionReason(for: row, rule: rule) {
                excluded.append(ArchiveCleanupExcludedRow(row: row, reason: reason))
            } else {
                candidates.append(row)
            }
        }

        let hostSummaries = hosts.map { host in
            ArchiveCleanupHostSummary(
                id: host.id,
                displayName: host.displayName,
                candidateCount: candidates.filter { row in
                    resolver.contains(
                        rowHostID: row.id.hostID,
                        sourceConfiguredHostID: row.sourceHostID,
                        in: host.id
                    )
                }.count,
                excludedCount: excluded.filter { excludedRow in
                    resolver.contains(
                        rowHostID: excludedRow.row.id.hostID,
                        sourceConfiguredHostID: excludedRow.row.sourceHostID,
                        in: host.id
                    )
                }.count
            )
        }

        return ArchiveCleanupPreviewSnapshot(
            hosts: hosts.map(DockHostViewModel.init),
            hostStates: hostStates,
            hostIdentityResolver: resolver,
            hostSummaries: hostSummaries,
            candidates: candidates.sorted(by: rowPrecedes),
            excluded: excluded.sorted { lhs, rhs in
                rowPrecedes(lhs.row, rhs.row)
            }
        )
    }

    private func rowPrecedes(_ lhs: DockRowViewModel, _ rhs: DockRowViewModel) -> Bool {
        // Cleanup previews use relay orderKey for card recency. Missing
        // orderKey falls back only to a stable identity order, never timestamps.
        if let lhsOrderKey = lhs.orderKey,
           let rhsOrderKey = rhs.orderKey,
           lhsOrderKey != rhsOrderKey {
            return lhsOrderKey < rhsOrderKey
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

    private func hostIdentityResolver(outcomes: [ThreadCardHostLoadOutcome]) -> DockHostIdentityResolver {
        let statuses = Dictionary(
            uniqueKeysWithValues: outcomes.map { outcome in
                let status: DockHostLoadStatus
                switch outcome.result {
                case .success(let collection):
                    status = collection.cards.isEmpty ? .empty : .loaded(rowCount: collection.cards.count)
                case .failure(let failure):
                    switch failure {
                    case .offline(let message):
                        status = .offline(message)
                    case .error(let message):
                        status = .error(message)
                    }
                }
                return (outcome.host.id, status)
            }
        )
        return DockHostIdentityResolver(
            hosts: hosts,
            observations: outcomes.flatMap { outcome in
                guard case .success(let collection) = outcome.result else {
                    return [DockHostIdentityObservation]()
                }
                return collection.hosts.map {
                    DockHostIdentityObservation(configuredHostID: outcome.host.id, streamHost: $0)
                } + collection.cards.map {
                    DockHostIdentityObservation(configuredHostID: outcome.host.id, card: $0)
                }
            },
            hostStatuses: statuses
        )
    }

    private func migrateMetadataHostAliases(using resolver: DockHostIdentityResolver) async {
        do {
            localMetadata = try await metadataEngine.migrateHostAliases(using: resolver)
        } catch {
            DockLog.persistence.warning("archive cleanup metadata host alias migration failed error=\(DockLog.errorSummary(error), privacy: .public)")
        }
    }
}

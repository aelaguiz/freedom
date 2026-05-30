import Foundation

actor ArchiveCleanupDataEngine {
    private struct HostLoadOutcome: Sendable {
        let host: DockHostConfiguration
        let result: Result<DockLoadResult, DockLoadFailure>
    }

    private var hosts: [DockHostConfiguration]
    private let loader: any DockSessionLoading
    private let metadataStore: any LocalThreadMetadataStoring
    private let now: @Sendable () -> Date
    private var localMetadata: [LocalThreadMetadataKey: LocalThreadMetadata] = [:]

    init(
        registry: HostRegistry,
        loader: any DockSessionLoading,
        metadataStore: any LocalThreadMetadataStoring,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.hosts = registry.hosts
        self.loader = loader
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

    private func loadAllHosts() async -> [HostLoadOutcome] {
        let hosts = self.hosts
        return await withTaskGroup(of: HostLoadOutcome.self) { group in
            for host in hosts {
                group.addTask { [loader] in
                    do {
                        let result = try await loader.loadSessions(for: host, query: .activeHumanFullScan)
                        return HostLoadOutcome(host: host, result: .success(result))
                    } catch {
                        return HostLoadOutcome(host: host, result: .failure(Self.mapLoadFailure(error)))
                    }
                }
            }

            var outcomes: [HostLoadOutcome] = []
            for await outcome in group {
                outcomes.append(outcome)
            }
            return outcomes.sorted { lhs, rhs in
                Self.hostIndex(lhs.host.id, hosts: hosts) < Self.hostIndex(rhs.host.id, hosts: hosts)
            }
        }
    }

    private func makePreview(
        outcomes: [HostLoadOutcome],
        rule: ArchiveCleanupRule
    ) -> ArchiveCleanupPreviewSnapshot {
        var summaries: [SessionSummary] = []
        var mappingFailures: [SessionSummaryMappingFailure] = []
        var hostStates: [DockHostStateViewModel] = []

        for outcome in outcomes {
            let host = DockHostViewModel(host: outcome.host)
            switch outcome.result {
            case .success(let result):
                summaries.append(contentsOf: result.summaries)
                mappingFailures.append(contentsOf: result.mappingFailures)
                hostStates.append(
                    DockHostStateViewModel(
                        host: host,
                        status: result.summaries.isEmpty ? .empty : .loaded(rowCount: result.summaries.count)
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

        let rows = SessionRowProjector(
            hosts: hosts,
            localMetadata: localMetadata,
            now: now,
            activityMode: .raw
        ).rows(from: summaries)

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
                candidateCount: groupedCandidates[host.id]?.count ?? 0,
                excludedCount: groupedExcluded[host.id]?.count ?? 0
            )
        }

        return ArchiveCleanupPreviewSnapshot(
            hosts: hosts.map(DockHostViewModel.init),
            hostStates: hostStates,
            hostSummaries: hostSummaries,
            candidates: candidates.sorted { $0.lastActivityDate > $1.lastActivityDate },
            excluded: excluded.sorted { $0.row.lastActivityDate > $1.row.lastActivityDate },
            mappingFailures: mappingFailures
        )
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

    private nonisolated static func mapLoadFailure(_ error: Error) -> DockLoadFailure {
        if let failure = error as? DockLoadFailure {
            return failure
        }
        return .error(error.localizedDescription)
    }

    private nonisolated static func hostIndex(
        _ hostID: String,
        hosts: [DockHostConfiguration]
    ) -> Int {
        hosts.firstIndex { $0.id == hostID } ?? Int.max
    }
}

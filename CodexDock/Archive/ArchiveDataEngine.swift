import Foundation

actor ArchiveDataEngine {
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

    func loadSnapshot() async -> ArchiveSnapshot {
        do {
            localMetadata = try await metadataStore.load()
            DockLog.persistence.debug("archive metadata loaded entries=\(self.localMetadata.count, privacy: .public)")
        } catch {
            localMetadata = [:]
            DockLog.persistence.warning("archive metadata load failed error=\(DockLog.errorSummary(error), privacy: .public)")
        }

        let results = await loadAllHosts()
        return makeSnapshot(results: results)
    }

    private func loadAllHosts() async -> [HostLoadOutcome] {
        let hosts = self.hosts
        return await withTaskGroup(of: HostLoadOutcome.self) { group in
            for host in hosts {
                group.addTask { [loader] in
                    let startedAt = Date()
                    DockLog.archive.debug("archive host load started host_id=\(host.id, privacy: .public)")
                    do {
                        let result = try await loader.loadSessions(for: host, query: .archivedHuman)
                        DockLog.archive.debug("archive host load finished host_id=\(host.id, privacy: .public) rows=\(result.summaries.count, privacy: .public) mapping_failures=\(result.mappingFailures.count, privacy: .public) duration_ms=\(DockLog.milliseconds(since: startedAt), privacy: .public)")
                        return HostLoadOutcome(host: host, result: .success(result))
                    } catch {
                        DockLog.archive.warning("archive host load failed host_id=\(host.id, privacy: .public) duration_ms=\(DockLog.milliseconds(since: startedAt), privacy: .public) error=\(DockLog.errorSummary(error), privacy: .public)")
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

    private func makeSnapshot(results: [HostLoadOutcome]) -> ArchiveSnapshot {
        var summaries: [SessionSummary] = []
        var mappingFailures: [SessionSummaryMappingFailure] = []
        var hostStates: [DockHostStateViewModel] = []

        for outcome in results {
            let host = DockHostViewModel(host: outcome.host)
            switch outcome.result {
            case .success(let result):
                summaries.append(contentsOf: result.summaries)
                mappingFailures.append(contentsOf: result.mappingFailures)
                hostStates.append(
                    DockHostStateViewModel(
                        host: host,
                        status: result.summaries.isEmpty
                            ? .empty
                            : .loaded(rowCount: result.summaries.count)
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

        let sections = ArchiveSessionProjector(
            hosts: hosts,
            localMetadata: localMetadata,
            now: now
        ).sections(from: summaries)

        return ArchiveSnapshot(
            hosts: hosts.map(DockHostViewModel.init),
            hostStates: hostStates,
            sections: sections,
            mappingFailures: mappingFailures
        )
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

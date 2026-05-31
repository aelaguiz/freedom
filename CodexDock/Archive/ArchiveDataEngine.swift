import Foundation

actor ArchiveDataEngine {
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

    func loadSnapshot() async -> ArchiveSnapshot {
        do {
            localMetadata = try await metadataEngine.load()
            DockLog.persistence.debug("archive metadata loaded entries=\(self.localMetadata.count, privacy: .public)")
        } catch {
            localMetadata = [:]
            await metadataEngine.replace(localMetadata)
            DockLog.persistence.warning("archive metadata load failed error=\(DockLog.errorSummary(error), privacy: .public)")
        }

        let results = await loadAllHosts()
        let resolver = hostIdentityResolver(results: results)
        await migrateMetadataHostAliases(using: resolver)
        return makeSnapshot(results: results, resolver: resolver)
    }

    private func loadAllHosts() async -> [ThreadCardHostLoadOutcome] {
        await ThreadCardHostSnapshotLoader(
            streamClient: streamClient,
            expectedView: .archive,
            operation: "archive"
        ).loadAll(hosts: hosts)
    }

    private func makeSnapshot(
        results: [ThreadCardHostLoadOutcome],
        resolver: DockHostIdentityResolver
    ) -> ArchiveSnapshot {
        var cardBatches: [(hostID: String, cards: [DockThreadCardDTO])] = []
        var hostStates: [DockHostStateViewModel] = []

        for outcome in results {
            let host = DockHostViewModel(host: outcome.host)
            switch outcome.result {
            case .success(let collection):
                cardBatches.append((hostID: outcome.host.id, cards: collection.cards))
                hostStates.append(
                    DockHostStateViewModel(
                        host: host,
                        status: collection.cards.isEmpty
                            ? .empty
                            : .loaded(rowCount: collection.cards.count)
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

        let sections = ArchiveThreadCardProjector(
            hosts: hosts,
            hostIdentityResolver: resolver,
            localMetadata: localMetadata,
            now: now
        ).sections(from: cardBatches)

        return ArchiveSnapshot(
            hosts: hosts.map(DockHostViewModel.init),
            hostStates: hostStates,
            hostIdentityResolver: resolver,
            sections: sections
        )
    }

    private func hostIdentityResolver(results: [ThreadCardHostLoadOutcome]) -> DockHostIdentityResolver {
        let statuses = Dictionary(
            uniqueKeysWithValues: results.map { outcome in
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
            observations: results.flatMap { outcome in
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
            DockLog.persistence.warning("archive metadata host alias migration failed error=\(DockLog.errorSummary(error), privacy: .public)")
        }
    }

}

import Foundation

actor ArchiveDataEngine {
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

    private func loadAllHosts() async -> [ThreadCardHostLoadOutcome] {
        await ThreadCardHostSnapshotLoader(
            streamClient: streamClient,
            expectedView: .archive,
            operation: "archive"
        ).loadAll(hosts: hosts)
    }

    private func makeSnapshot(results: [ThreadCardHostLoadOutcome]) -> ArchiveSnapshot {
        var cards: [DockThreadCardDTO] = []
        var hostStates: [DockHostStateViewModel] = []

        for outcome in results {
            let host = DockHostViewModel(host: outcome.host)
            switch outcome.result {
            case .success(let hostCards):
                cards.append(contentsOf: hostCards)
                hostStates.append(
                    DockHostStateViewModel(
                        host: host,
                        status: hostCards.isEmpty
                            ? .empty
                            : .loaded(rowCount: hostCards.count)
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
            localMetadata: localMetadata,
            now: now
        ).sections(from: cards)

        return ArchiveSnapshot(
            hosts: hosts.map(DockHostViewModel.init),
            hostStates: hostStates,
            sections: sections
        )
    }

}

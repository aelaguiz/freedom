import Foundation

actor DockDataEngine {
    private var hosts: [DockHostConfiguration]
    private var cardTable = ThreadCardTable()
    private var localMetadata: [LocalThreadMetadataKey: LocalThreadMetadata]

    init(
        registry: HostRegistry,
        localMetadata: [LocalThreadMetadataKey: LocalThreadMetadata] = [:]
    ) {
        self.hosts = registry.hosts
        self.localMetadata = localMetadata
        self.cardTable.reset(hosts: registry.hosts)
    }

    func updateRegistry(_ registry: HostRegistry) {
        hosts = registry.hosts
        cardTable.reset(hosts: registry.hosts)
    }

    func updateLocalMetadata(_ values: [LocalThreadMetadataKey: LocalThreadMetadata]) {
        localMetadata = values
    }

    func ensureHosts() {
        cardTable.ensureHosts(hosts)
    }

    func markChecking(host: DockHostConfiguration) {
        cardTable.markChecking(host: host)
    }

    func markFailure(_ failure: DockRequestFailure, host: DockHostConfiguration) {
        cardTable.markFailure(failure, host: host)
    }

    func applySnapshot(
        _ update: ThreadCardStreamUpdateDTO,
        host: DockHostConfiguration
    ) -> ThreadCardTableApplyResult {
        cardTable.applySnapshot(update, host: host)
    }

    func applyUpdate(
        _ update: ThreadCardStreamUpdateDTO,
        host: DockHostConfiguration
    ) -> ThreadCardTableApplyResult {
        cardTable.applyUpdate(update, host: host)
    }

    func rowCount(for host: DockHostConfiguration) -> Int {
        cardTable.rowCount(for: host)
    }

    func snapshot(now: @escaping @Sendable () -> Date = Date.init) -> DockSnapshot? {
        guard !hosts.isEmpty else {
            return nil
        }
        return DockRenderProjector(now: now).snapshot(
            from: cardTable.renderInput(hosts: hosts),
            localMetadata: localMetadata
        )
    }
}

import Foundation

actor DockDataEngine {
    private var hosts: [DockHostConfiguration]
    private var sessionTable = DockSessionTable()
    private var localMetadata: [LocalThreadMetadataKey: LocalThreadMetadata]

    init(
        registry: HostRegistry,
        localMetadata: [LocalThreadMetadataKey: LocalThreadMetadata] = [:]
    ) {
        self.hosts = registry.hosts
        self.localMetadata = localMetadata
        self.sessionTable.reset(hosts: registry.hosts)
    }

    func updateRegistry(_ registry: HostRegistry) {
        hosts = registry.hosts
        sessionTable.reset(hosts: registry.hosts)
    }

    func updateLocalMetadata(_ values: [LocalThreadMetadataKey: LocalThreadMetadata]) {
        localMetadata = values
    }

    func ensureHosts() {
        sessionTable.ensureHosts(hosts)
    }

    func markChecking(host: DockHostConfiguration) {
        sessionTable.markChecking(host: host)
    }

    func markFailure(_ failure: DockLoadFailure, host: DockHostConfiguration) {
        sessionTable.markFailure(failure, host: host)
    }

    func applySnapshot(
        _ update: DockStreamUpdateDTO,
        host: DockHostConfiguration
    ) -> DockSessionTableApplyResult {
        sessionTable.applySnapshot(update, host: host)
    }

    func applyUpdate(
        _ update: DockStreamUpdateDTO,
        host: DockHostConfiguration
    ) -> DockSessionTableApplyResult {
        sessionTable.applyUpdate(update, host: host)
    }

    func rowCount(for host: DockHostConfiguration) -> Int {
        sessionTable.rowCount(for: host)
    }

    func snapshot(now: @escaping @Sendable () -> Date = Date.init) -> DockSnapshot? {
        guard !hosts.isEmpty else {
            return nil
        }
        return DockRenderProjector(now: now).snapshot(
            from: sessionTable.renderInput(hosts: hosts),
            localMetadata: localMetadata
        )
    }
}

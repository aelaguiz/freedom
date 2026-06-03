import Foundation

actor DockDataEngine {
    private var hosts: [DockHostConfiguration]
    private var projectionState = ThreadCardProjectionState()
    private var localMetadata: [LocalThreadMetadataKey: LocalThreadMetadata]

    init(
        registry: HostRegistry,
        localMetadata: [LocalThreadMetadataKey: LocalThreadMetadata] = [:]
    ) {
        self.hosts = registry.hosts
        self.localMetadata = localMetadata
        self.projectionState.reset(hosts: registry.hosts)
    }

    func updateRegistry(_ registry: HostRegistry) {
        hosts = registry.hosts
        projectionState.reset(hosts: registry.hosts)
    }

    func updateLocalMetadata(_ values: [LocalThreadMetadataKey: LocalThreadMetadata]) {
        localMetadata = values
    }

    func ensureHosts() {
        projectionState.ensureHosts(hosts)
    }

    func apply(
        _ snapshot: StreamReconcilerSnapshot<DockThreadCardDTO>,
        host: DockHostConfiguration
    ) {
        projectionState.apply(snapshot, host: host)
    }

    func rowCount(for host: DockHostConfiguration) -> Int {
        projectionState.rowCount(for: host)
    }

    func hostIdentityResolver() -> DockHostIdentityResolver {
        projectionState.hostIdentityResolver(hosts: hosts)
    }

    func snapshot(now: @escaping @Sendable () -> Date = Date.init) -> DockSnapshot? {
        guard !hosts.isEmpty else {
            return nil
        }
        return DockRenderProjector(now: now).snapshot(
            from: projectionState.renderInput(hosts: hosts),
            localMetadata: localMetadata
        )
    }
}

import Foundation

actor ArchiveDataEngine {
    private var hosts: [DockHostConfiguration]
    private var projectionState = ThreadCardProjectionState()
    private let metadataEngine: LocalMetadataEngine
    private let now: @Sendable () -> Date
    private var localMetadata: [LocalThreadMetadataKey: LocalThreadMetadata] = [:]

    init(
        registry: HostRegistry,
        metadataStore: any LocalThreadMetadataStoring,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.hosts = registry.hosts
        self.metadataEngine = LocalMetadataEngine(store: metadataStore, now: now)
        self.now = now
        self.projectionState.reset(hosts: registry.hosts)
    }

    func updateRegistry(_ registry: HostRegistry) {
        hosts = registry.hosts
        projectionState.reset(hosts: registry.hosts)
    }

    func loadLocalMetadata() async {
        do {
            localMetadata = try await metadataEngine.load()
            DockLog.persistence.debug("archive metadata loaded entries=\(self.localMetadata.count, privacy: .public)")
        } catch {
            localMetadata = [:]
            await metadataEngine.replace(localMetadata)
            DockLog.persistence.warning("archive metadata load failed error=\(DockLog.errorSummary(error), privacy: .public)")
        }
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

    func migrateMetadataHostAliases() async {
        let resolver = projectionState.hostIdentityResolver(hosts: hosts)
        do {
            localMetadata = try await metadataEngine.migrateHostAliases(using: resolver)
        } catch {
            DockLog.persistence.warning("archive metadata host alias migration failed error=\(DockLog.errorSummary(error), privacy: .public)")
        }
    }

    func snapshot() -> ArchiveSnapshot? {
        guard !hosts.isEmpty else {
            return nil
        }

        let input = projectionState.renderInput(hosts: hosts)
        let sections = ArchiveThreadCardProjector(
            hosts: hosts,
            hostIdentityResolver: input.hostIdentityResolver,
            localMetadata: localMetadata,
            now: now
        ).sections(
            from: hosts.map { host in
                (hostID: host.id, cards: input.cardsByHostID[host.id] ?? [])
            }
        )

        return ArchiveSnapshot(
            hosts: input.hosts.map(DockHostViewModel.init),
            hostStates: input.hostStates,
            hostIdentityResolver: input.hostIdentityResolver,
            sections: sections
        )
    }
}

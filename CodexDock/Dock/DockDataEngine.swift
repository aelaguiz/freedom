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
        PerformanceProbe.event(
            "dock.data_engine.update_registry",
            fields: [
                "hosts": "\(registry.hosts.count)",
            ]
        )
        hosts = registry.hosts
        projectionState.reset(hosts: registry.hosts)
    }

    func updateLocalMetadata(_ values: [LocalThreadMetadataKey: LocalThreadMetadata]) {
        PerformanceProbe.event(
            "dock.data_engine.update_metadata",
            fields: [
                "metadata_entries": "\(values.count)",
            ]
        )
        localMetadata = values
    }

    func ensureHosts() {
        let startedAt = Date()
        projectionState.ensureHosts(hosts)
        PerformanceProbe.event(
            "dock.data_engine.ensure_hosts",
            fields: [
                "hosts": "\(hosts.count)",
                "duration_ms": "\(PerformanceProbe.milliseconds(since: startedAt))",
            ]
        )
    }

    func apply(
        _ snapshot: StreamReconcilerSnapshot<DockThreadCardDTO>,
        host: DockHostConfiguration
    ) {
        let startedAt = Date()
        projectionState.apply(snapshot, host: host)
        PerformanceProbe.event(
            "dock.data_engine.apply",
            fields: [
                "host_id": host.id,
                "revision": "\(snapshot.revision)",
                "rows": "\(snapshot.rows.count)",
                "seq": "\(snapshot.seq)",
                "generation": "\(snapshot.generation)",
                "complete": snapshot.complete.map(String.init) ?? "none",
                "total_rows": snapshot.totalRows.map(String.init) ?? "none",
                "buffered": "\(snapshot.bufferedEnvelopeCount)",
                "duration_ms": "\(PerformanceProbe.milliseconds(since: startedAt))",
            ]
        )
    }

    func rowCount(for host: DockHostConfiguration) -> Int {
        projectionState.rowCount(for: host)
    }

    func hostIdentityResolver() -> DockHostIdentityResolver {
        let startedAt = Date()
        defer {
            PerformanceProbe.event(
                "dock.data_engine.host_identity_resolver",
                fields: [
                    "hosts": "\(hosts.count)",
                    "duration_ms": "\(PerformanceProbe.milliseconds(since: startedAt))",
                ]
            )
        }
        return projectionState.hostIdentityResolver(hosts: hosts)
    }

    func snapshot(now: @escaping @Sendable () -> Date = Date.init) -> DockSnapshot? {
        guard !hosts.isEmpty else {
            return nil
        }
        let startedAt = Date()
        let snapshot = DockRenderProjector(now: now).snapshot(
            from: projectionState.renderInput(hosts: hosts),
            localMetadata: localMetadata
        )
        PerformanceProbe.event(
            "dock.data_engine.snapshot",
            fields: [
                "hosts": "\(hosts.count)",
                "rows": "\(snapshot.rows.count)",
                "metadata_entries": "\(localMetadata.count)",
                "partial": "\(snapshot.isPartial)",
                "duration_ms": "\(PerformanceProbe.milliseconds(since: startedAt))",
            ]
        )
        return snapshot
    }
}

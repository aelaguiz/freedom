import Foundation

struct DockRenderProjector: Sendable {
    let now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    func snapshot(
        from input: DockRenderInput,
        localMetadata: [LocalThreadMetadataKey: LocalThreadMetadata]
    ) -> DockSnapshot {
        let rowProjector = ThreadCardRowProjector(
            hosts: input.hosts,
            hostIdentityResolver: input.hostIdentityResolver,
            localMetadata: localMetadata,
            now: now
        )
        let liveRows = input.hosts.flatMap { host in
            rowProjector.rows(
                from: input.cardsByHostID[host.id] ?? [],
                sourceHostID: host.id
            )
        }
        // Local metadata may decorate relay rows, but it must never create card
        // rows. The relay is the single source of truth for card existence and order.

        return DockSnapshot(
            host: DockHostViewModel(host: input.hosts[0]),
            hosts: input.hosts.map(DockHostViewModel.init),
            hostStates: input.hostStates,
            hostIdentityResolver: input.hostIdentityResolver,
            rows: liveRows,
            isPartial: input.isPartial
        )
    }

    func render(
        snapshot: DockSnapshot,
        options: DockProjectionOptions,
        revision: RenderRevision
    ) -> DockRenderSnapshot {
        DockRenderSnapshot(
            revision: revision,
            snapshot: snapshot,
            projection: snapshot.project(options: options)
        )
    }
}

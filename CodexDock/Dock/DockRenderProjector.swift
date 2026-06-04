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
        let startedAt = Date()
        let rowProjector = ThreadCardRowProjector(
            hosts: input.hosts,
            hostIdentityResolver: input.hostIdentityResolver,
            localMetadata: localMetadata,
            now: now
        )
        let liveRows = input.hosts.flatMap { host in
            rowProjector.rows(
                from: input.cardsByHostID[host.id] ?? [],
                configuredHostID: host.id
            )
        }
        // Local metadata may decorate relay rows, but it must never create card
        // rows. The relay is the single source of truth for card existence and order.

        let snapshot = DockSnapshot(
            host: DockHostViewModel(host: input.hosts[0]),
            hosts: input.hosts.map(DockHostViewModel.init),
            hostStates: input.hostStates,
            hostIdentityResolver: input.hostIdentityResolver,
            rows: liveRows,
            isPartial: input.isPartial
        )
        if PerformanceProbe.isEnabled {
            let hostCardCounts = input.hosts
                .map { "\($0.id):\(input.cardsByHostID[$0.id]?.count ?? 0)" }
                .joined(separator: ",")
            PerformanceProbe.event(
                "dock.snapshot.project",
                fields: [
                    "hosts": "\(input.hosts.count)",
                    "host_cards": hostCardCounts,
                    "rows": "\(snapshot.rows.count)",
                    "metadata_entries": "\(localMetadata.count)",
                    "partial": "\(snapshot.isPartial)",
                    "duration_ms": "\(PerformanceProbe.milliseconds(since: startedAt))",
                ]
            )
        }
        return snapshot
    }

    func render(
        snapshot: DockSnapshot,
        options: DockProjectionOptions,
        revision: RenderRevision
    ) -> DockRenderSnapshot {
        let startedAt = Date()
        let renderSnapshot = DockRenderSnapshot(
            revision: revision,
            snapshot: snapshot,
            options: options,
            projection: snapshot.project(options: options)
        )
        if PerformanceProbe.isEnabled {
            PerformanceProbe.event(
                "dock.render.project",
                fields: [
                    "revision": "\(revision.rawValue)",
                    "rows": "\(snapshot.rows.count)",
                    "hosts": "\(snapshot.hosts.count)",
                    "lens": options.lens.rawValue,
                    "search": options.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "false" : "true",
                    "filters": "\(options.filters.activeFilterCount)",
                    "duration_ms": "\(PerformanceProbe.milliseconds(since: startedAt))",
                ]
            )
        }
        return renderSnapshot
    }
}

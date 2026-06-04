import Foundation

struct DockRenderInput: Equatable, Sendable {
    let hosts: [DockHostConfiguration]
    let hostStates: [DockHostStateViewModel]
    let hostIdentityResolver: DockHostIdentityResolver
    let cardsByHostID: [String: [DockThreadCardDTO]]
    let isPartial: Bool

    init(
        hosts: [DockHostConfiguration],
        hostStates: [DockHostStateViewModel],
        hostIdentityResolver: DockHostIdentityResolver? = nil,
        cardsByHostID: [String: [DockThreadCardDTO]],
        isPartial: Bool
    ) {
        self.hosts = hosts
        self.hostStates = hostStates
        self.hostIdentityResolver = hostIdentityResolver ?? DockHostIdentityResolver(hosts: hosts)
        self.cardsByHostID = cardsByHostID
        self.isPartial = isPartial
    }
}

struct DockRenderSnapshot: Equatable, Sendable {
    let revision: RenderRevision
    let snapshot: DockSnapshot
    let options: DockProjectionOptions
    let projection: DockCardProjection
    let rowByID: [String: DockRowViewModel]
    let automationSnapshot: DockAutomationSnapshotMetadata?

    init(
        revision: RenderRevision,
        snapshot: DockSnapshot,
        options: DockProjectionOptions,
        projection: DockCardProjection,
        automationSnapshot: DockAutomationSnapshotMetadata? = nil
    ) {
        self.revision = revision
        self.snapshot = snapshot
        self.options = options
        self.projection = projection
        self.rowByID = Dictionary(uniqueKeysWithValues: snapshot.rows.map { ($0.id, $0) })
        self.automationSnapshot = automationSnapshot
    }

    func withAutomationSnapshot(_ metadata: DockAutomationSnapshotMetadata?) -> DockRenderSnapshot {
        DockRenderSnapshot(
            revision: revision,
            snapshot: snapshot,
            options: options,
            projection: projection,
            automationSnapshot: metadata
        )
    }
}

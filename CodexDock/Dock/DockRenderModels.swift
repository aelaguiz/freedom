import Foundation

struct DockRenderInput: Equatable, Sendable {
    let hosts: [DockHostConfiguration]
    let hostStates: [DockHostStateViewModel]
    let cardsByHostID: [String: [DockThreadCardDTO]]
    let isPartial: Bool

    init(
        hosts: [DockHostConfiguration],
        hostStates: [DockHostStateViewModel],
        cardsByHostID: [String: [DockThreadCardDTO]],
        isPartial: Bool
    ) {
        self.hosts = hosts
        self.hostStates = hostStates
        self.cardsByHostID = cardsByHostID
        self.isPartial = isPartial
    }
}

struct DockRenderSnapshot: Equatable, Sendable {
    let revision: RenderRevision
    let snapshot: DockSnapshot
    let projection: DockCardProjection
}

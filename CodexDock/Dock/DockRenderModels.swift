import Foundation

struct DockRenderInput: Equatable, Sendable {
    let hosts: [DockHostConfiguration]
    let hostStates: [DockHostStateViewModel]
    let sessionsByHostID: [String: [DockStreamSessionDTO]]
    let isPartial: Bool

    init(
        hosts: [DockHostConfiguration],
        hostStates: [DockHostStateViewModel],
        sessionsByHostID: [String: [DockStreamSessionDTO]],
        isPartial: Bool
    ) {
        self.hosts = hosts
        self.hostStates = hostStates
        self.sessionsByHostID = sessionsByHostID
        self.isPartial = isPartial
    }
}

struct DockRenderSnapshot: Equatable, Sendable {
    let revision: RenderRevision
    let snapshot: DockSnapshot
    let projection: DockSessionProjection
}

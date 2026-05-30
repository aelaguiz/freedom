import Foundation

public struct ConnectivityRenderSnapshot: Equatable, Sendable {
    public let revision: RenderRevision
    public let hosts: [HostConnectivitySnapshot]
    public let overallStatus: AppConnectivityOverallStatus

    public init(
        revision: RenderRevision,
        hosts: [HostConnectivitySnapshot],
        overallStatus: AppConnectivityOverallStatus
    ) {
        self.revision = revision
        self.hosts = hosts
        self.overallStatus = overallStatus
    }
}

struct ConnectivityHostRecord: Equatable, Sendable {
    let id: String
    var displayName: String
    var endpoint: String
    var phase: HostConnectivityPhase
    var lastCheckedAt: Date?
    var lastSuccessAt: Date?
    var routeDiagnostics: [RouteDiagnosticSnapshot]
}

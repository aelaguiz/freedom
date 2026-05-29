import Foundation

public struct HostRegistry: Equatable, Sendable {
    public let hosts: [DockHostConfiguration]

    public init(hosts: [DockHostConfiguration]) throws {
        guard !hosts.isEmpty else {
            DockLog.hostConfiguration.error("host registry creation failed reason=no_hosts")
            throw DockHostConfigurationError.missingEndpoint
        }
        var seenHostIDs: Set<String> = []
        for host in hosts {
            guard seenHostIDs.insert(host.id).inserted else {
                DockLog.hostConfiguration.error("host registry creation failed reason=duplicate_endpoint endpoint=\(host.id, privacy: .public)")
                throw DockHostConfigurationError.duplicateHostID(host.id)
            }
        }
        self.hosts = hosts
        DockLog.hostConfiguration.notice("host registry created hosts=\(hosts.count, privacy: .public)")
    }
}

public extension HostRegistry {
    static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> HostRegistry {
        let endpoints = try DockRelayEndpoint.parseList(environment["CODEX_DOCK_HOSTS"])
        try endpoints.forEach { try $0.validateAppFacingRelayEndpoint() }
        let hosts = endpoints.map(DockHostConfiguration.init(endpoint:))
        let registry = try HostRegistry(hosts: hosts)
        DockLog.hostConfiguration.notice("host registry loaded from environment hosts=\(registry.hosts.count, privacy: .public)")
        return registry
    }
}

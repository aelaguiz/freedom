import Foundation

public struct HostRegistry: Equatable, Sendable {
    public let hosts: [DockHostConfiguration]

    public init(hosts: [DockHostConfiguration]) throws {
        guard !hosts.isEmpty else {
            throw DockHostConfigurationError.missingEndpoint
        }
        self.hosts = hosts
    }
}

public extension HostRegistry {
    static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> HostRegistry {
        let hostIDs = hostIDs(from: environment["CODEX_DOCK_HOSTS"])
        guard !hostIDs.isEmpty else {
            return try HostRegistry(hosts: [DockHostConfiguration.fromEnvironment(environment)])
        }

        let hosts = try hostIDs.map { hostID in
            try hostConfiguration(hostID: hostID, environment: environment)
        }
        return try HostRegistry(hosts: hosts)
    }

    private static func hostIDs(from value: String?) -> [String] {
        value?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
    }

    private static func hostConfiguration(
        hostID: String,
        environment: [String: String]
    ) throws -> DockHostConfiguration {
        let key = envKeyComponent(hostID)
        var scopedEnvironment = environment

        scopedEnvironment["CODEX_DOCK_PHONE_REACHABLE_APP_SERVER_WS"] = firstNonEmpty(
            environment["CODEX_DOCK_HOST_\(key)_WS"],
            environment["CODEX_DOCK_HOST_\(key)_APP_SERVER_WS"]
        )
        scopedEnvironment["CODEX_DOCK_APP_SERVER_BEARER_TOKEN"] = firstNonEmpty(
            environment["CODEX_DOCK_HOST_\(key)_BEARER_TOKEN"],
            environment["CODEX_DOCK_HOST_\(key)_TOKEN"]
        )
        scopedEnvironment["CODEX_DOCK_APP_SERVER_BEARER_TOKEN_FILE"] = firstNonEmpty(
            environment["CODEX_DOCK_HOST_\(key)_BEARER_TOKEN_FILE"],
            environment["CODEX_DOCK_HOST_\(key)_TOKEN_FILE"]
        )
        scopedEnvironment["CODEX_DOCK_REAL_HOST_ID"] = hostID
        scopedEnvironment["CODEX_DOCK_REAL_HOST_NAME"] = firstNonEmpty(
            environment["CODEX_DOCK_HOST_\(key)_NAME"],
            hostID
        )

        return try DockHostConfiguration.fromEnvironment(scopedEnvironment)
    }

    private static func envKeyComponent(_ value: String) -> String {
        let scalars = value.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar)
                ? String(scalar).uppercased()
                : "_"
        }
        return scalars.joined()
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        for value in values {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed, !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }
}

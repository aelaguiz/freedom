import Foundation

public struct DockRelayEndpoint: Codable, Equatable, Sendable, Identifiable {
    public let host: String
    public let port: Int

    public var id: String { serializedEndpoint }

    public var serializedEndpoint: String {
        "\(serializedHost):\(port)"
    }

    public var displayEndpoint: String {
        serializedEndpoint
    }

    public var webSocketURL: URL {
        // URL is transport-only. App config and persistence stay host+port.
        URL(string: "ws://\(serializedEndpoint)")!
    }

    public var statusURL: URL {
        URL(string: "http://\(serializedEndpoint)/statusz")!
    }

    private var serializedHost: String {
        host.contains(":") ? "[\(host)]" : host
    }

    public init(host rawHost: String, port: Int) throws {
        let host = try Self.normalizedHost(rawHost)
        guard (1...65_535).contains(port) else {
            throw DockHostConfigurationError.invalidPort(String(port))
        }
        self.host = host
        self.port = port
    }

    public static func parse(_ rawValue: String) throws -> DockRelayEndpoint {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            throw DockHostConfigurationError.missingEndpoint
        }

        let host: String
        let portText: String
        if value.hasPrefix("[") {
            guard let closeIndex = value.firstIndex(of: "]") else {
                throw DockHostConfigurationError.invalidEndpoint(value)
            }
            let afterClose = value.index(after: closeIndex)
            guard afterClose < value.endIndex, value[afterClose] == ":" else {
                throw DockHostConfigurationError.invalidEndpoint(value)
            }
            host = String(value[value.index(after: value.startIndex)..<closeIndex])
            portText = String(value[value.index(after: afterClose)...])
        } else {
            let parts = value.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2 else {
                throw DockHostConfigurationError.invalidEndpoint(value)
            }
            host = String(parts[0])
            portText = String(parts[1])
        }

        guard let port = Int(portText) else {
            throw DockHostConfigurationError.invalidPort(portText)
        }
        return try DockRelayEndpoint(host: host, port: port)
    }

    public static func parseList(_ rawValue: String?) throws -> [DockRelayEndpoint] {
        let endpoints = rawValue?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
        guard !endpoints.isEmpty else {
            throw DockHostConfigurationError.missingEndpoint
        }

        var seen: Set<String> = []
        return try endpoints.map { value in
            let endpoint = try DockRelayEndpoint.parse(value)
            guard seen.insert(endpoint.id).inserted else {
                throw DockHostConfigurationError.duplicateHostID(endpoint.id)
            }
            return endpoint
        }
    }

    public func validateAppFacingRelayEndpoint() throws {
        if port == 4_500 {
            throw DockHostConfigurationError.rawAppServerEndpoint(displayEndpoint)
        }
    }

    private static func normalizedHost(_ rawHost: String) throws -> String {
        var host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
        if host.hasPrefix("[") && host.hasSuffix("]") {
            host.removeFirst()
            host.removeLast()
        }
        while host.hasSuffix(".") {
            host.removeLast()
        }

        guard !host.isEmpty,
              !host.contains("://"),
              !host.contains("/"),
              !host.contains("?"),
              !host.contains("#"),
              !host.contains("@"),
              host.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
        else {
            throw DockHostConfigurationError.invalidHost(rawHost)
        }
        return host
    }
}

public struct DockHostConfiguration: Equatable, Sendable, Identifiable {
    public let endpoints: [DockRelayEndpoint]
    public let relayInstanceID: String?

    public var endpoint: DockRelayEndpoint { endpoints[0] }
    public var id: String { relayInstanceID ?? endpoint.id }
    public var displayName: String { relayInstanceID ?? endpoint.displayEndpoint }
    public var webSocketURL: URL { endpoint.webSocketURL }
    public var webSocketURLs: [URL] { endpoints.map(\.webSocketURL) }
    public var displayEndpointList: String {
        endpoints.map(\.displayEndpoint).joined(separator: ", ")
    }

    public init(endpoint: DockRelayEndpoint, relayInstanceID: String? = nil) {
        self.endpoints = [endpoint]
        self.relayInstanceID = Self.normalizedRelayInstanceID(relayInstanceID)
    }

    public init(endpoints: [DockRelayEndpoint], relayInstanceID: String? = nil) throws {
        guard let first = endpoints.first else {
            throw DockHostConfigurationError.missingEndpoint
        }
        let normalizedRelayInstanceID = Self.normalizedRelayInstanceID(relayInstanceID)
        var seen: Set<String> = []
        var unique: [DockRelayEndpoint] = []
        for endpoint in [first] + Array(endpoints.dropFirst()) {
            guard seen.insert(endpoint.id).inserted else {
                continue
            }
            unique.append(endpoint)
        }
        guard unique.count == 1 || normalizedRelayInstanceID != nil else {
            throw DockHostConfigurationError.missingRelayInstanceIDForEndpointAliases
        }
        self.endpoints = unique
        self.relayInstanceID = normalizedRelayInstanceID
    }

    public init(host: String, port: Int) throws {
        self.endpoints = [try DockRelayEndpoint(host: host, port: port)]
        self.relayInstanceID = nil
    }

    private static func normalizedRelayInstanceID(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    public func validateRelayInstanceID(_ actual: String?) throws {
        guard let expected = relayInstanceID else {
            return
        }
        guard let actual = Self.normalizedRelayInstanceID(actual) else {
            throw DockHostConfigurationError.relayInstanceMismatch(expected: expected, actual: "<missing>")
        }
        guard actual == expected else {
            throw DockHostConfigurationError.relayInstanceMismatch(expected: expected, actual: actual)
        }
    }
}

public enum DockHostConfigurationError: Error, Equatable, LocalizedError, Sendable {
    case missingEndpoint
    case invalidEndpoint(String)
    case invalidHost(String)
    case invalidPort(String)
    case duplicateHostID(String)
    case unsupportedLegacyURL(String)
    case relayInstanceMismatch(expected: String, actual: String)
    case rawAppServerEndpoint(String)
    case missingRelayInstanceIDForEndpointAliases

    public var errorDescription: String? {
        switch self {
        case .missingEndpoint:
            return "Set CODEX_DOCK_HOSTS to one or more relay endpoints like 192.168.50.117:4510."
        case let .invalidEndpoint(value):
            return "Codex Dock relay endpoint must be host:port with no scheme, path, query, username, or password: \(value)"
        case let .invalidHost(value):
            return "Codex Dock relay host must not include a scheme, path, query, username, password, or whitespace: \(value)"
        case let .invalidPort(value):
            return "Codex Dock relay port must be an integer from 1 to 65535: \(value)"
        case let .duplicateHostID(hostID):
            return "CODEX_DOCK_HOSTS must not include the same endpoint more than once: \(hostID)"
        case let .unsupportedLegacyURL(value):
            return "Saved relay URL could not be migrated. Re-enter it as host and port: \(value)"
        case let .relayInstanceMismatch(expected, actual):
            return "Relay identity mismatch. Expected \(expected), but endpoint reported \(actual)."
        case let .rawAppServerEndpoint(value):
            return "Codex Dock app-facing hosts must point at the Dock relay on :4510, not the raw Codex app-server on :4500: \(value)"
        case .missingRelayInstanceIDForEndpointAliases:
            return "CODEX_DOCK_RELAY_INSTANCE_ID is required when CODEX_DOCK_HOSTS contains multiple endpoints for the same relay."
        }
    }
}

public extension DockHostConfiguration {
    static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> DockHostConfiguration {
        let endpoints = try DockRelayEndpoint.parseList(environment["CODEX_DOCK_HOSTS"])
        try endpoints.forEach { try $0.validateAppFacingRelayEndpoint() }
        let configuration = try DockHostConfiguration(
            endpoints: endpoints,
            relayInstanceID: environment["CODEX_DOCK_RELAY_INSTANCE_ID"]
        )
        DockLog.hostConfiguration.notice("host configuration loaded host_id=\(configuration.id, privacy: .public) endpoints=\(configuration.endpoints.count, privacy: .public) first_endpoint=\(DockLog.endpoint(configuration.webSocketURL), privacy: .public)")
        return configuration
    }
}

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
    public let endpoint: DockRelayEndpoint

    public var id: String { endpoint.id }
    public var displayName: String { endpoint.displayEndpoint }
    public var webSocketURL: URL { endpoint.webSocketURL }

    public init(endpoint: DockRelayEndpoint) {
        self.endpoint = endpoint
    }

    public init(host: String, port: Int) throws {
        self.endpoint = try DockRelayEndpoint(host: host, port: port)
    }
}

public enum DockHostConfigurationError: Error, Equatable, LocalizedError, Sendable {
    case missingEndpoint
    case invalidEndpoint(String)
    case invalidHost(String)
    case invalidPort(String)
    case duplicateHostID(String)
    case unsupportedLegacyURL(String)

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
        }
    }
}

public extension DockHostConfiguration {
    static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> DockHostConfiguration {
        guard let first = try DockRelayEndpoint.parseList(environment["CODEX_DOCK_HOSTS"]).first else {
            throw DockHostConfigurationError.missingEndpoint
        }
        let configuration = DockHostConfiguration(endpoint: first)
        DockLog.hostConfiguration.notice("host configuration loaded host_id=\(configuration.id, privacy: .public) endpoint=\(DockLog.endpoint(configuration.webSocketURL), privacy: .public)")
        return configuration
    }
}

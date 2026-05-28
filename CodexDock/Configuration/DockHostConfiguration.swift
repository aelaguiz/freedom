import Foundation

public struct DockHostConfiguration: Equatable, Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let webSocketURL: URL
    public let bearerToken: String?

    public init(
        id: String,
        displayName: String,
        webSocketURL: URL,
        bearerToken: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.webSocketURL = webSocketURL
        self.bearerToken = Self.normalized(bearerToken)
    }

    static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            return trimmed
        }
        return nil
    }
}

public enum DockHostConfigurationError: Error, Equatable, LocalizedError, Sendable {
    case missingEndpoint
    case invalidEndpoint(String)
    case missingBearerToken
    case tokenFileReadFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingEndpoint:
            return "Set CODEX_DOCK_PHONE_REACHABLE_APP_SERVER_WS to a ws:// or wss:// Codex app-server URL."
        case let .invalidEndpoint(value):
            return "Codex Dock WebSocket URL must be ws:// or wss://, include a host, and not include username/password credentials: \(value)"
        case .missingBearerToken:
            return "Bearer auth is optional for the local relay path."
        case let .tokenFileReadFailed(path):
            return "Could not read CODEX_DOCK_APP_SERVER_BEARER_TOKEN_FILE at \(path)."
        }
    }
}

public extension DockHostConfiguration {
    static func validatedWebSocketURL(_ rawValue: String) throws -> URL {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let webSocketURL = URL(string: value),
              let scheme = webSocketURL.scheme?.lowercased(),
              scheme == "ws" || scheme == "wss",
              webSocketURL.host?.isEmpty == false,
              webSocketURL.user == nil,
              webSocketURL.password == nil
        else {
            throw DockHostConfigurationError.invalidEndpoint(value)
        }
        return webSocketURL
    }

    static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> DockHostConfiguration {
        let endpoint = firstNonEmpty(
            environment["CODEX_DOCK_PHONE_REACHABLE_APP_SERVER_WS"],
            environment["CODEX_DOCK_APP_SERVER_WS"]
        )

        guard let endpoint else {
            throw DockHostConfigurationError.missingEndpoint
        }

        let webSocketURL = try validatedWebSocketURL(endpoint)

        let bearerToken: String?
        if let token = firstNonEmpty(environment["CODEX_DOCK_APP_SERVER_BEARER_TOKEN"]) {
            bearerToken = token
        } else if let tokenFile = firstNonEmpty(environment["CODEX_DOCK_APP_SERVER_BEARER_TOKEN_FILE"]) {
            do {
                bearerToken = try String(contentsOfFile: tokenFile, encoding: .utf8)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                throw DockHostConfigurationError.tokenFileReadFailed(tokenFile)
            }
        } else {
            bearerToken = nil
        }

        let hostID = firstNonEmpty(
            environment["CODEX_DOCK_REAL_HOST_ID"],
            environment["CODEX_DOCK_SINGLE_HOST_ID"],
            webSocketURL.host
        ) ?? "codex-host"
        let displayName = firstNonEmpty(environment["CODEX_DOCK_REAL_HOST_NAME"], hostID) ?? hostID

        return DockHostConfiguration(
            id: hostID,
            displayName: displayName,
            webSocketURL: webSocketURL,
            bearerToken: bearerToken
        )
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

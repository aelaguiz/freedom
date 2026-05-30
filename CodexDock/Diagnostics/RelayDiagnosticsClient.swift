import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum RelayDiagnosticsClientError: Error, Equatable, LocalizedError, Sendable {
    case invalidStatusURL(URL)
    case requestFailed(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidStatusURL(let url):
            return "Relay diagnostics status URL must end in /statusz: \(url.absoluteString)"
        case .requestFailed(let statusCode):
            return "Relay diagnostics request failed with HTTP \(statusCode)"
        }
    }
}

public struct RelayDiagnosticsRoutesResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let routes: [RelayRouteHealthDTO]
}

public struct RelayRouteHealthDTO: Codable, Equatable, Sendable {
    public struct Attempt: Codable, Equatable, Sendable {
        public let operationID: String?
        public let at: Date?
    }

    public let configuredHostID: String?
    public let relayHostID: String?
    public let route: String
    public let routeStatus: ObservabilityRouteStatus
    public let statusReasons: [RouteStatusReason]
    public let lastAttempt: Attempt?
    public let lastSuccess: Attempt?
    public let lastFailure: Attempt?
    public let appCritical: Bool
    public let appImpact: String?

    public func snapshot(fallbackConfiguredHostID: String) -> RouteDiagnosticSnapshot {
        RouteDiagnosticSnapshot(
            configuredHostID: configuredHostID ?? fallbackConfiguredHostID,
            relayHostID: relayHostID,
            route: route,
            operationID: lastAttempt?.operationID,
            routeStatus: routeStatus,
            statusReasons: statusReasons,
            lastAttemptAt: lastAttempt?.at,
            lastSuccessAt: lastSuccess?.at,
            lastFailureAt: lastFailure?.at,
            appCritical: appCritical,
            appImpact: appImpact
        )
    }
}

public struct RelayDiagnosticsClient: Sendable {
    private let session: URLSession
    private let decoder: JSONDecoder

    public init(session: URLSession = .shared) {
        self.session = session
        self.decoder = RelayDiagnosticsDate.decoder()
    }

    public func diagnosticsURL(for endpoint: DockRelayEndpoint, path requestedPath: String) throws -> URL {
        let baseURL = endpoint.statusURL
        guard baseURL.path == "/statusz" else {
            throw RelayDiagnosticsClientError.invalidStatusURL(baseURL)
        }
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = requestedPath.hasPrefix("/") ? requestedPath : "/\(requestedPath)"
        components?.query = nil
        components?.fragment = nil
        guard let url = components?.url else {
            throw RelayDiagnosticsClientError.invalidStatusURL(baseURL)
        }
        return url
    }

    public func fetchRoutes(for endpoint: DockRelayEndpoint) async throws -> [RouteDiagnosticSnapshot] {
        let url = try diagnosticsURL(for: endpoint, path: "/routesz")
        let response: RelayDiagnosticsRoutesResponse = try await fetch(url)
        return response.routes.map { $0.snapshot(fallbackConfiguredHostID: endpoint.id) }
    }

    public func fetchStatus(for endpoint: DockRelayEndpoint) async throws -> JSONValue {
        try await fetchJSONValue(try diagnosticsURL(for: endpoint, path: "/statusz"))
    }

    public func fetchTrace(operationID: String, for endpoint: DockRelayEndpoint) async throws -> JSONValue {
        let encoded = operationID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? operationID
        return try await fetchJSONValue(try diagnosticsURL(for: endpoint, path: "/tracesz/\(encoded)"))
    }

    private func fetch<Response: Decodable>(_ url: URL) async throws -> Response {
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw RelayDiagnosticsClientError.requestFailed((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return try decoder.decode(Response.self, from: data)
    }

    private func fetchJSONValue(_ url: URL) async throws -> JSONValue {
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw RelayDiagnosticsClientError.requestFailed((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return try decoder.decode(JSONValue.self, from: data)
    }
}

private enum RelayDiagnosticsDate {
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            if let date = parse(rawValue) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid relay diagnostics timestamp: \(rawValue)"
            )
        }
        return decoder
    }

    private static func parse(_ rawValue: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: rawValue) {
            return date
        }

        let standardFormatter = ISO8601DateFormatter()
        standardFormatter.formatOptions = [.withInternetDateTime]
        return standardFormatter.date(from: rawValue)
    }
}

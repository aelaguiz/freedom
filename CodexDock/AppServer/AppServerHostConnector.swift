import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct AppServerHostConnection: Sendable {
    public let host: DockHostConfiguration
    public let endpoint: DockRelayEndpoint
    public let initializeResponse: InitializeResponse
    public let client: AppServerClient

    public func disconnect() async {
        await client.disconnect()
    }
}

public struct AppServerHostConnector: Sendable {
    private let makeClient: @Sendable (DockRelayEndpoint) -> AppServerClient

    public init(
        makeClient: @escaping @Sendable (DockRelayEndpoint) -> AppServerClient = {
            AppServerClient(webSocketURL: $0.webSocketURL, bearerToken: nil)
        }
    ) {
        self.makeClient = makeClient
    }

    public func connectAndInitialize(
        for host: DockHostConfiguration,
        params: InitializeParams = .codexDock(version: "0.1.0"),
        timeout: Duration = .seconds(5)
    ) async throws -> AppServerHostConnection {
        var lastFailure: Error?
        for endpoint in host.endpoints {
            let client = makeClient(endpoint)

            do {
                return try await connectSingleEndpoint(
                    host: host,
                    endpoint: endpoint,
                    client: client,
                    params: params,
                    timeout: timeout
                )
            } catch {
                if Self.shouldRetryNextEndpoint(after: error) {
                    lastFailure = error
                    continue
                }
                throw error
            }
        }
        throw lastFailure ?? DockHostConfigurationError.missingEndpoint
    }

    public func withConnectedClient<Value>(
        for host: DockHostConfiguration,
        params: InitializeParams = .codexDock(version: "0.1.0"),
        timeout: Duration = .seconds(5),
        operation: @Sendable (AppServerHostConnection) async throws -> Value
    ) async throws -> Value {
        var lastFailure: Error?
        for endpoint in host.endpoints {
            let client = makeClient(endpoint)

            do {
                let connection = try await connectSingleEndpoint(
                    host: host,
                    endpoint: endpoint,
                    client: client,
                    params: params,
                    timeout: timeout
                )
                do {
                    let value = try await operation(connection)
                    await connection.disconnect()
                    return value
                } catch {
                    await connection.disconnect()
                    throw error
                }
            } catch {
                if Self.shouldRetryNextEndpoint(after: error) {
                    lastFailure = error
                    continue
                }
                throw error
            }
        }
        throw lastFailure ?? DockHostConfigurationError.missingEndpoint
    }

    public func retainConnectedClient<Value>(
        for host: DockHostConfiguration,
        params: InitializeParams = .codexDock(version: "0.1.0"),
        timeout: Duration = .seconds(5),
        operation: @Sendable (AppServerHostConnection) async throws -> Value
    ) async throws -> (connection: AppServerHostConnection, value: Value) {
        var lastFailure: Error?
        for endpoint in host.endpoints {
            let client = makeClient(endpoint)

            do {
                let connection = try await connectSingleEndpoint(
                    host: host,
                    endpoint: endpoint,
                    client: client,
                    params: params,
                    timeout: timeout
                )
                do {
                    let value = try await operation(connection)
                    return (connection, value)
                } catch {
                    await connection.disconnect()
                    throw error
                }
            } catch {
                if Self.shouldRetryNextEndpoint(after: error) {
                    lastFailure = error
                    continue
                }
                throw error
            }
        }
        throw lastFailure ?? DockHostConfigurationError.missingEndpoint
    }

    public static func shouldRetryNextEndpoint(after error: Error) -> Bool {
        if let clientError = error as? AppServerClientError {
            switch clientError {
            case .disconnected, .notConnected, .requestTimedOut, .transport:
                return true
            case .duplicateRequestID,
                 .malformedMessage,
                 .requestCancelled,
                 .responseDecoding,
                 .server,
                 .unexpectedServerRequest,
                 .unmatchedResponse:
                return false
            }
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotConnectToHost,
                 .cannotFindHost,
                 .dnsLookupFailed,
                 .internationalRoamingOff,
                 .networkConnectionLost,
                 .notConnectedToInternet,
                 .timedOut:
                return true
            default:
                return false
            }
        }

        return false
    }

    private func connectSingleEndpoint(
        host: DockHostConfiguration,
        endpoint: DockRelayEndpoint,
        client: AppServerClient,
        params: InitializeParams,
        timeout: Duration
    ) async throws -> AppServerHostConnection {
        let startedAt = Date()
        DockLog.appServer.notice("logical host connect started host_id=\(host.id, privacy: .public) endpoint=\(DockLog.endpoint(endpoint.webSocketURL), privacy: .public)")
        do {
            let initialize = try await client.connectAndInitialize(params: params, timeout: timeout)
            try host.validateRelayInstanceID(initialize.relayInstanceID)
            try await validateRelayStatusIfAvailable(for: host, endpoint: endpoint)
            DockLog.appServer.notice("logical host connect finished host_id=\(host.id, privacy: .public) endpoint=\(DockLog.endpoint(endpoint.webSocketURL), privacy: .public) duration_ms=\(DockLog.milliseconds(since: startedAt), privacy: .public)")
            return AppServerHostConnection(
                host: host,
                endpoint: endpoint,
                initializeResponse: initialize,
                client: client
            )
        } catch {
            DockLog.appServer.warning("logical host connect failed host_id=\(host.id, privacy: .public) endpoint=\(DockLog.endpoint(endpoint.webSocketURL), privacy: .public) duration_ms=\(DockLog.milliseconds(since: startedAt), privacy: .public) error=\(DockLog.errorSummary(error), privacy: .public)")
            await client.disconnect()
            throw error
        }
    }

    private func validateRelayStatusIfAvailable(
        for host: DockHostConfiguration,
        endpoint: DockRelayEndpoint
    ) async throws {
        guard host.relayInstanceID != nil else {
            return
        }

        var request = URLRequest(url: endpoint.statusURL)
        request.timeoutInterval = 2
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode)
            else {
                return
            }
            let snapshot = try JSONDecoder().decode(RelayStatusSnapshotDTO.self, from: data)
            let actual = snapshot.host?.relayInstanceID ?? snapshot.host?.id
            try host.validateRelayInstanceID(actual)
        } catch let error as DockHostConfigurationError {
            throw error
        } catch {
            DockLog.appServer.debug("relay status identity check skipped host_id=\(host.id, privacy: .public) endpoint=\(DockLog.endpoint(endpoint.webSocketURL), privacy: .public) error=\(DockLog.errorSummary(error), privacy: .public)")
        }
    }
}

private struct RelayStatusSnapshotDTO: Decodable {
    let host: HostDTO?

    struct HostDTO: Decodable {
        let id: String?
        let relayInstanceID: String?
    }
}

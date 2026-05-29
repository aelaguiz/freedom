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
        let endpoint = host.endpoint
        let client = makeClient(endpoint)
        return try await connectSingleEndpoint(
            host: host,
            endpoint: endpoint,
            client: client,
            params: params,
            timeout: timeout
        )
    }

    public func withConnectedClient<Value>(
        for host: DockHostConfiguration,
        params: InitializeParams = .codexDock(version: "0.1.0"),
        timeout: Duration = .seconds(5),
        operation: @Sendable (AppServerHostConnection) async throws -> Value
    ) async throws -> Value {
        let connection = try await connectAndInitialize(
            for: host,
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
    }

    public func retainConnectedClient<Value>(
        for host: DockHostConfiguration,
        params: InitializeParams = .codexDock(version: "0.1.0"),
        timeout: Duration = .seconds(5),
        operation: @Sendable (AppServerHostConnection) async throws -> Value
    ) async throws -> (connection: AppServerHostConnection, value: Value) {
        let connection = try await connectAndInitialize(
            for: host,
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
}

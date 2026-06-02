import Foundation

public struct AppServerThreadDetailSessionFactory: ThreadDetailSessionMaking {
    private let makeClient: @Sendable (
        DockRelayEndpoint,
        (any AppForegroundWorkGating)?
    ) -> AppServerClient

    public init() {
        self.makeClient = { endpoint, foregroundWorkGate in
            AppServerClient(
                webSocketURL: endpoint.webSocketURL,
                bearerToken: nil,
                connectionPolicy: .liveDetail,
                foregroundWorkGate: foregroundWorkGate
            )
        }
    }

    public init(makeClient: @escaping @Sendable (DockRelayEndpoint) -> AppServerClient) {
        self.makeClient = { endpoint, _ in
            makeClient(endpoint)
        }
    }

    public func makeSession(for host: DockHostConfiguration) -> any ThreadDetailSession {
        makeSession(for: host, foregroundWorkGate: nil)
    }

    public func makeSession(
        for host: DockHostConfiguration,
        foregroundWorkGate: (any AppForegroundWorkGating)?
    ) -> any ThreadDetailSession {
        let makeClient = self.makeClient
        return AppServerThreadDetailSession(
            host: host,
            makeClient: { endpoint in
                makeClient(endpoint, foregroundWorkGate)
            }
        )
    }
}

private actor AppServerThreadDetailSession: ThreadDetailSession {
    nonisolated let connectionStates: AsyncStream<AppServerConnectionState>
    nonisolated let notifications: AsyncStream<JSONRPCNotification>

    private let host: DockHostConfiguration
    private let makeClient: @Sendable (DockRelayEndpoint) -> AppServerClient
    private let connectionStateContinuation: AsyncStream<AppServerConnectionState>.Continuation
    private let notificationContinuation: AsyncStream<JSONRPCNotification>.Continuation
    private var client: AppServerClient?
    private var connectionStateTask: Task<Void, Never>?
    private var notificationTask: Task<Void, Never>?

    init(
        host: DockHostConfiguration,
        makeClient: @escaping @Sendable (DockRelayEndpoint) -> AppServerClient
    ) {
        self.host = host
        self.makeClient = makeClient
        let connectionStates = AsyncStream.makeStream(of: AppServerConnectionState.self)
        let notifications = AsyncStream.makeStream(of: JSONRPCNotification.self)
        self.connectionStates = connectionStates.stream
        self.connectionStateContinuation = connectionStates.continuation
        self.notifications = notifications.stream
        self.notificationContinuation = notifications.continuation
        self.connectionStateContinuation.yield(.idle)
    }

    deinit {
        connectionStateTask?.cancel()
        notificationTask?.cancel()
        connectionStateContinuation.finish()
        notificationContinuation.finish()
    }

    func connectAndInitialize(
        params: InitializeParams,
        timeout: Duration
    ) async throws -> InitializeResponse {
        connectionStateContinuation.yield(.connecting)
        let connection = try await AppServerHostConnector(makeClient: makeClient)
            .connectAndInitialize(for: host, params: params, timeout: timeout)
        client = connection.client
        startForwarding(from: connection.client)
        connectionStateContinuation.yield(.connected)
        return connection.initializeResponse
    }

    func threadDetailSubscribe(
        params: ThreadDetailParams,
        timeout: Duration
    ) async throws -> ThreadDetailSnapshotDTO {
        try await requireClient().threadDetailSubscribe(
            params: params,
            timeout: timeout,
            observabilityContext: context(for: AppServerMethods.threadDetailSubscribe)
        )
    }

    func threadDetailResync(
        params: ThreadDetailParams,
        timeout: Duration
    ) async throws -> ThreadDetailSnapshotDTO {
        try await requireClient().threadDetailResync(
            params: params,
            timeout: timeout,
            observabilityContext: context(for: AppServerMethods.threadDetailResync)
        )
    }

    func turnStart(params: TurnStartParams, timeout: Duration) async throws -> TurnStartResponseDTO {
        try await requireClient().turnStart(
            params: params,
            timeout: timeout,
            observabilityContext: context(for: AppServerMethods.turnStart)
        )
    }

    func turnSteer(params: TurnSteerParams, timeout: Duration) async throws -> TurnSteerResponseDTO {
        try await requireClient().turnSteer(
            params: params,
            timeout: timeout,
            observabilityContext: context(for: AppServerMethods.turnSteer)
        )
    }

    func sendResponse(id: JSONRPCRequestID, result: JSONValue) async throws {
        try await requireClient().sendResponse(id: id, result: result)
    }

    func disconnect() async {
        connectionStateTask?.cancel()
        notificationTask?.cancel()
        let client = client
        self.client = nil
        await client?.disconnect()
        connectionStateContinuation.finish()
        notificationContinuation.finish()
    }

    private func startForwarding(from client: AppServerClient) {
        connectionStateTask?.cancel()
        notificationTask?.cancel()

        let connectionStateContinuation = connectionStateContinuation
        connectionStateTask = Task { [client] in
            for await state in client.connectionStates {
                connectionStateContinuation.yield(state)
            }
        }

        let notificationContinuation = notificationContinuation
        notificationTask = Task { [client] in
            for await notification in client.notifications {
                notificationContinuation.yield(notification)
            }
        }

    }

    private func requireClient() throws -> AppServerClient {
        guard let client else {
            throw AppServerClientError.notConnected(.idle)
        }
        return client
    }

    private func context(for route: String) -> AppServerRequestObservabilityContext {
        AppServerRequestObservabilityContext(
            configuredHostID: host.id,
            route: route,
            store: .shared
        )
    }
}

import Foundation

public protocol DockStreamConnection: Sendable {
    func subscribe() async throws -> DockStreamUpdateDTO
    func resync() async throws -> DockStreamUpdateDTO
    func updates() -> AsyncThrowingStream<DockStreamUpdateDTO, Error>
    func close() async
}

public protocol DockStreamConnecting: Sendable {
    func connect(to host: DockHostConfiguration) async throws -> any DockStreamConnection
}

public struct AppServerDockStreamClient: DockStreamConnecting {
    private let makeClient: @Sendable (DockRelayEndpoint) -> AppServerClient
    private let observabilityStore: ClientObservabilityStore

    public init(
        observabilityStore: ClientObservabilityStore = .shared,
        makeClient: @escaping @Sendable (DockRelayEndpoint) -> AppServerClient = {
            AppServerClient(webSocketURL: $0.webSocketURL, bearerToken: nil, connectionPolicy: .liveDetail)
        }
    ) {
        self.observabilityStore = observabilityStore
        self.makeClient = makeClient
    }

    public func connect(to host: DockHostConfiguration) async throws -> any DockStreamConnection {
        let client = makeClient(host.endpoint)
        _ = try await client.connectAndInitialize(timeout: CodexDockConstants.AppServer.connectInitializeTimeout)
        return AppServerDockStreamConnection(
            client: client,
            host: host,
            observabilityStore: observabilityStore
        )
    }
}

public final class AppServerDockStreamConnection: DockStreamConnection, @unchecked Sendable {
    private let client: AppServerClient
    private let host: DockHostConfiguration
    private let observabilityStore: ClientObservabilityStore
    private let updateStream: AsyncThrowingStream<DockStreamUpdateDTO, Error>
    private let updateContinuation: AsyncThrowingStream<DockStreamUpdateDTO, Error>.Continuation
    private var notificationTask: Task<Void, Never>?

    init(
        client: AppServerClient,
        host: DockHostConfiguration,
        observabilityStore: ClientObservabilityStore = .shared
    ) {
        self.client = client
        self.host = host
        self.observabilityStore = observabilityStore
        let stream = AsyncThrowingStream<DockStreamUpdateDTO, Error>.makeStream()
        self.updateStream = stream.stream
        self.updateContinuation = stream.continuation
        self.notificationTask = Task { [client, updateContinuation, host, observabilityStore] in
            for await notification in client.notifications {
                guard notification.method == AppServerMethods.dockUpdate else {
                    continue
                }
                await observabilityStore.recordPassive(
                    route: AppServerMethods.dockUpdate,
                    configuredHostID: host.id,
                    relayHostID: nil
                )
                do {
                    guard let params = notification.params else {
                        continue
                    }
                    updateContinuation.yield(try params.decoded(as: DockStreamUpdateDTO.self))
                } catch {
                    updateContinuation.finish(throwing: AppServerClientError.responseDecoding(error.localizedDescription))
                    return
                }
            }
            updateContinuation.finish()
        }
    }

    deinit {
        notificationTask?.cancel()
        updateContinuation.finish()
    }

    public func subscribe() async throws -> DockStreamUpdateDTO {
        DockLog.dock.notice("dock stream subscribe started host_id=\(self.host.id, privacy: .public)")
        let context = AppServerRequestObservabilityContext(
            configuredHostID: host.id,
            route: AppServerMethods.dockSubscribe,
            store: observabilityStore
        )
        let response = try await client.sendRequest(
            method: AppServerMethods.dockSubscribe,
            timeout: CodexDockConstants.AppServer.defaultRequestTimeout,
            observabilityContext: context,
            as: DockStreamUpdateDTO.self
        )
        DockLog.dock.notice("dock stream subscribe finished host_id=\(self.host.id, privacy: .public) seq=\(response.seq, privacy: .public)")
        return response
    }

    public func resync() async throws -> DockStreamUpdateDTO {
        let context = AppServerRequestObservabilityContext(
            configuredHostID: host.id,
            route: AppServerMethods.dockResync,
            store: observabilityStore
        )
        return try await client.sendRequest(
            method: AppServerMethods.dockResync,
            timeout: CodexDockConstants.AppServer.defaultRequestTimeout,
            observabilityContext: context,
            as: DockStreamUpdateDTO.self
        )
    }

    public func updates() -> AsyncThrowingStream<DockStreamUpdateDTO, Error> {
        updateStream
    }

    public func close() async {
        notificationTask?.cancel()
        updateContinuation.finish()
        await client.disconnect()
    }
}

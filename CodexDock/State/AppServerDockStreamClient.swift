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

    public init(
        makeClient: @escaping @Sendable (DockRelayEndpoint) -> AppServerClient = {
            AppServerClient(webSocketURL: $0.webSocketURL, bearerToken: nil, connectionPolicy: .liveDetail)
        }
    ) {
        self.makeClient = makeClient
    }

    public func connect(to host: DockHostConfiguration) async throws -> any DockStreamConnection {
        let client = makeClient(host.endpoint)
        _ = try await client.connectAndInitialize(timeout: CodexDockConstants.AppServer.connectInitializeTimeout)
        return AppServerDockStreamConnection(client: client, host: host)
    }
}

public final class AppServerDockStreamConnection: DockStreamConnection, @unchecked Sendable {
    private let client: AppServerClient
    private let host: DockHostConfiguration
    private let updateStream: AsyncThrowingStream<DockStreamUpdateDTO, Error>
    private let updateContinuation: AsyncThrowingStream<DockStreamUpdateDTO, Error>.Continuation
    private var notificationTask: Task<Void, Never>?

    init(client: AppServerClient, host: DockHostConfiguration) {
        self.client = client
        self.host = host
        let stream = AsyncThrowingStream<DockStreamUpdateDTO, Error>.makeStream()
        self.updateStream = stream.stream
        self.updateContinuation = stream.continuation
        self.notificationTask = Task { [client, updateContinuation] in
            for await notification in client.notifications {
                guard notification.method == AppServerMethods.dockUpdate else {
                    continue
                }
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
        let response = try await client.sendRequest(
            method: AppServerMethods.dockSubscribe,
            timeout: CodexDockConstants.AppServer.defaultRequestTimeout,
            as: DockStreamUpdateDTO.self
        )
        DockLog.dock.notice("dock stream subscribe finished host_id=\(self.host.id, privacy: .public) seq=\(response.seq, privacy: .public)")
        return response
    }

    public func resync() async throws -> DockStreamUpdateDTO {
        try await client.sendRequest(
            method: AppServerMethods.dockResync,
            timeout: CodexDockConstants.AppServer.defaultRequestTimeout,
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

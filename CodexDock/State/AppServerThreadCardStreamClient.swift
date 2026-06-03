import Foundation

public protocol ThreadCardStreamConnection: Sendable {
    func subscribe() async throws -> ThreadCardStreamUpdateDTO
    func resync() async throws -> ThreadCardStreamUpdateDTO
    func updates() -> AsyncThrowingStream<ThreadCardStreamUpdateDTO, Error>
    func close() async
}

public protocol ThreadCardStreamConnecting: Sendable {
    func connect(to host: DockHostConfiguration) async throws -> any ThreadCardStreamConnection
}

struct ThreadCardProjectionStreamConnector: ProjectionStreamConnecting {
    private let host: DockHostConfiguration
    private let streamClient: any ThreadCardStreamConnecting

    init(
        host: DockHostConfiguration,
        streamClient: any ThreadCardStreamConnecting
    ) {
        self.host = host
        self.streamClient = streamClient
    }

    func connect() async throws -> any ProjectionStreamConnection<DockThreadCardDTO> {
        let connection = try await streamClient.connect(to: host)
        return ThreadCardProjectionStreamConnection(connection: connection)
    }
}

private actor ThreadCardProjectionStreamConnection: ProjectionStreamConnection {
    private let connection: any ThreadCardStreamConnection
    private let updateStream: AsyncThrowingStream<ProjectionEnvelope<DockThreadCardDTO>, Error>
    private let updateContinuation: AsyncThrowingStream<ProjectionEnvelope<DockThreadCardDTO>, Error>.Continuation
    private var updateTask: Task<Void, Never>?

    init(connection: any ThreadCardStreamConnection) {
        self.connection = connection
        let stream = AsyncThrowingStream<ProjectionEnvelope<DockThreadCardDTO>, Error>.makeStream()
        self.updateStream = stream.stream
        self.updateContinuation = stream.continuation
        self.updateTask = Task { [connection, updateContinuation] in
            do {
                for try await update in connection.updates() {
                    updateContinuation.yield(ProjectionEnvelope(update))
                }
                updateContinuation.finish()
            } catch {
                updateContinuation.finish(throwing: error)
            }
        }
    }

    deinit {
        updateTask?.cancel()
        updateContinuation.finish()
    }

    func subscribe() async throws -> ProjectionEnvelope<DockThreadCardDTO> {
        ProjectionEnvelope(try await connection.subscribe())
    }

    func resync(reason _: StreamReconcilerRecoveryReason) async throws -> ProjectionEnvelope<DockThreadCardDTO> {
        ProjectionEnvelope(try await connection.resync())
    }

    nonisolated func updates() -> AsyncThrowingStream<ProjectionEnvelope<DockThreadCardDTO>, Error> {
        updateStream
    }

    func close() async {
        updateTask?.cancel()
        updateContinuation.finish()
        await connection.close()
    }
}

public struct AppServerThreadCardStreamClient: ThreadCardStreamConnecting {
    private let view: ThreadCardStreamView
    private let makeClient: @Sendable (DockRelayEndpoint) -> AppServerClient
    private let observabilityStore: ClientObservabilityStore

    public init(
        view: ThreadCardStreamView = .dock,
        observabilityStore: ClientObservabilityStore = .shared,
        makeClient: @escaping @Sendable (DockRelayEndpoint) -> AppServerClient = {
            AppServerClient(webSocketURL: $0.webSocketURL, bearerToken: nil, connectionPolicy: .liveDetail)
        }
    ) {
        self.view = view
        self.observabilityStore = observabilityStore
        self.makeClient = makeClient
    }

    public func connect(to host: DockHostConfiguration) async throws -> any ThreadCardStreamConnection {
        let client = makeClient(host.endpoint)
        _ = try await client.connectAndInitialize(timeout: CodexDockConstants.AppServer.connectInitializeTimeout)
        return AppServerThreadCardStreamConnection(
            client: client,
            view: view,
            host: host,
            observabilityStore: observabilityStore
        )
    }
}

public actor AppServerThreadCardStreamConnection: ThreadCardStreamConnection {
    private let client: AppServerClient
    private let view: ThreadCardStreamView
    private let host: DockHostConfiguration
    private let observabilityStore: ClientObservabilityStore
    private let updateStream: AsyncThrowingStream<ThreadCardStreamUpdateDTO, Error>
    private let updateContinuation: AsyncThrowingStream<ThreadCardStreamUpdateDTO, Error>.Continuation
    private var notificationTask: Task<Void, Never>?

    init(
        client: AppServerClient,
        view: ThreadCardStreamView = .dock,
        host: DockHostConfiguration,
        observabilityStore: ClientObservabilityStore = .shared
    ) {
        self.client = client
        self.view = view
        self.host = host
        self.observabilityStore = observabilityStore
        let stream = AsyncThrowingStream<ThreadCardStreamUpdateDTO, Error>.makeStream()
        self.updateStream = stream.stream
        self.updateContinuation = stream.continuation
        let updateRoute = Self.updateRoute(for: view)
        self.notificationTask = Task { [client, updateContinuation, host, observabilityStore, updateRoute] in
            for await notification in client.notifications {
                guard notification.method == updateRoute else {
                    continue
                }
                await observabilityStore.recordPassive(
                    route: updateRoute,
                    configuredHostID: host.id,
                    relayHostID: nil
                )
                do {
                    guard let params = notification.params else {
                        continue
                    }
                    updateContinuation.yield(try params.decoded(as: ThreadCardStreamUpdateDTO.self))
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

    public func subscribe() async throws -> ThreadCardStreamUpdateDTO {
        let route = Self.subscribeRoute(for: view)
        DockLog.dock.notice("thread card stream subscribe started view=\(self.view.rawValue, privacy: .public) host_id=\(self.host.id, privacy: .public)")
        let context = AppServerRequestObservabilityContext(
            configuredHostID: host.id,
            route: route,
            store: observabilityStore
        )
        let response = try await client.sendRequest(
            method: route,
            timeout: CodexDockConstants.AppServer.defaultRequestTimeout,
            observabilityContext: context,
            as: ThreadCardStreamUpdateDTO.self
        )
        DockLog.dock.notice("thread card stream subscribe finished view=\(self.view.rawValue, privacy: .public) host_id=\(self.host.id, privacy: .public) seq=\(response.seq, privacy: .public)")
        return response
    }

    public func resync() async throws -> ThreadCardStreamUpdateDTO {
        let route = Self.resyncRoute(for: view)
        let context = AppServerRequestObservabilityContext(
            configuredHostID: host.id,
            route: route,
            store: observabilityStore
        )
        return try await client.sendRequest(
            method: route,
            timeout: CodexDockConstants.AppServer.defaultRequestTimeout,
            observabilityContext: context,
            as: ThreadCardStreamUpdateDTO.self
        )
    }

    public nonisolated func updates() -> AsyncThrowingStream<ThreadCardStreamUpdateDTO, Error> {
        updateStream
    }

    public func close() async {
        notificationTask?.cancel()
        updateContinuation.finish()
        await client.disconnect()
    }

    private static func subscribeRoute(for view: ThreadCardStreamView) -> String {
        switch view {
        case .dock:
            return AppServerMethods.dockSubscribe
        case .archive:
            return AppServerMethods.archiveSubscribe
        }
    }

    private static func updateRoute(for view: ThreadCardStreamView) -> String {
        switch view {
        case .dock:
            return AppServerMethods.dockUpdate
        case .archive:
            return AppServerMethods.archiveUpdate
        }
    }

    private static func resyncRoute(for view: ThreadCardStreamView) -> String {
        switch view {
        case .dock:
            return AppServerMethods.dockResync
        case .archive:
            return AppServerMethods.archiveResync
        }
    }
}

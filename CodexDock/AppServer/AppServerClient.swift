import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol AppServerTransport: Sendable {
    func connect() async throws
    func send(_ text: String) async throws
    func receive() async throws -> String?
    func disconnect() async
}

public enum AppServerConnectionState: Equatable, Sendable {
    case idle
    case connecting
    case connected
    case reconnecting(attempt: Int, reason: String)
    case offline(reason: String)
    case error(message: String)
    case closed(reason: String)
}

public struct AppServerConnectionPolicy: Sendable, Equatable {
    public let reconnect: AppServerReconnectPolicy?

    public init(reconnect: AppServerReconnectPolicy? = nil) {
        self.reconnect = reconnect
    }

    public static let oneShot = AppServerConnectionPolicy()

    public static let liveDetail = AppServerConnectionPolicy(
        reconnect: AppServerReconnectPolicy(
            maxAttempts: 3,
            initialDelayMilliseconds: 500,
            maxDelayMilliseconds: 5_000,
            jitterRatio: 0.2
        )
    )
}

public struct AppServerReconnectPolicy: Sendable, Equatable {
    public let maxAttempts: Int
    public let initialDelayMilliseconds: Int
    public let maxDelayMilliseconds: Int
    public let jitterRatio: Double

    public init(
        maxAttempts: Int,
        initialDelayMilliseconds: Int,
        maxDelayMilliseconds: Int,
        jitterRatio: Double = 0.0
    ) {
        precondition(maxAttempts > 0, "Reconnect attempts must be positive")
        precondition(initialDelayMilliseconds >= 0, "Initial reconnect delay cannot be negative")
        precondition(maxDelayMilliseconds >= initialDelayMilliseconds, "Max reconnect delay must cover initial delay")
        precondition(jitterRatio >= 0, "Reconnect jitter cannot be negative")
        self.maxAttempts = maxAttempts
        self.initialDelayMilliseconds = initialDelayMilliseconds
        self.maxDelayMilliseconds = maxDelayMilliseconds
        self.jitterRatio = jitterRatio
    }

    func delay(for attempt: Int) -> Duration {
        let exponent = max(0, min(attempt - 1, 20))
        let multiplier = 1 << exponent
        let baseDelay = min(maxDelayMilliseconds, initialDelayMilliseconds * multiplier)
        let jitterWindow = Int(Double(baseDelay) * jitterRatio)
        let jitter = jitterWindow > 0 ? Int.random(in: -jitterWindow...jitterWindow) : 0
        return .milliseconds(max(0, baseDelay + jitter))
    }
}

public enum AppServerClientError: Error, Equatable, LocalizedError, Sendable {
    case duplicateRequestID(JSONRPCRequestID)
    case disconnected(String)
    case malformedMessage(String)
    case notConnected(AppServerConnectionState)
    case requestCancelled(JSONRPCRequestID)
    case requestTimedOut(JSONRPCRequestID)
    case responseDecoding(String)
    case server(JSONRPCErrorObject)
    case transport(String)
    case unexpectedServerRequest(method: String)
    case unmatchedResponse(JSONRPCRequestID)

    public var errorDescription: String? {
        switch self {
        case .duplicateRequestID(let id):
            "Duplicate JSON-RPC request id `\(id)`"
        case .disconnected(let reason):
            "App-server disconnected: \(reason)"
        case .malformedMessage(let message):
            "Malformed app-server JSON-RPC message: \(message)"
        case .notConnected(let state):
            "Cannot send app-server request while connection state is `\(state)`"
        case .requestCancelled(let id):
            "JSON-RPC request `\(id)` was cancelled"
        case .requestTimedOut(let id):
            "Timed out waiting for JSON-RPC response to request `\(id)`"
        case .responseDecoding(let message):
            "Could not decode app-server response: \(message)"
        case .server(let error):
            "App-server rejected request: \(error.message)"
        case .transport(let message):
            "App-server transport failed: \(message)"
        case .unexpectedServerRequest(let method):
            "Unsupported app-server request from server: \(method)"
        case .unmatchedResponse(let id):
            "App-server sent response for unknown request id `\(id)`"
        }
    }
}

public actor AppServerClient {
    private enum TransportOpenMode: Equatable {
        case initial
        case reconnecting

        var logDescription: String {
            switch self {
            case .initial:
                return "initial"
            case .reconnecting:
                return "reconnecting"
            }
        }
    }

    private struct PendingRequest {
        let method: String
        let startedAt: Date
        let continuation: CheckedContinuation<JSONValue, Error>
        let timeoutTask: Task<Void, Never>
    }

    public private(set) var state: AppServerConnectionState = .idle
    public private(set) var serverInfo: InitializeResponse?
    public nonisolated let connectionStates: AsyncStream<AppServerConnectionState>
    public nonisolated let notifications: AsyncStream<JSONRPCNotification>
    public nonisolated let serverRequests: AsyncStream<JSONRPCRequest>

    private let connectionStateContinuation: AsyncStream<AppServerConnectionState>.Continuation
    private let notificationContinuation: AsyncStream<JSONRPCNotification>.Continuation
    private let serverRequestContinuation: AsyncStream<JSONRPCRequest>.Continuation
    private let transport: any AppServerTransport
    private let connectionPolicy: AppServerConnectionPolicy
    private let foregroundWorkGate: (any AppForegroundWorkGating)?
    private var nextRequestNumber: Int64 = 1
    private var pendingRequests: [JSONRPCRequestID: PendingRequest] = [:]
    private var retiredRequestIDs: Set<JSONRPCRequestID> = []
    private var receiveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var initializeParams: InitializeParams?
    private var initializeTimeout: Duration = .seconds(10)
    private var isExplicitlyDisconnected = false

    public init(
        transport: any AppServerTransport,
        connectionPolicy: AppServerConnectionPolicy = .oneShot,
        foregroundWorkGate: (any AppForegroundWorkGating)? = nil
    ) {
        let connectionStates = AsyncStream.makeStream(of: AppServerConnectionState.self)
        let notifications = AsyncStream.makeStream(of: JSONRPCNotification.self)
        let serverRequests = AsyncStream.makeStream(of: JSONRPCRequest.self)
        self.connectionStates = connectionStates.stream
        self.connectionStateContinuation = connectionStates.continuation
        self.notifications = notifications.stream
        self.notificationContinuation = notifications.continuation
        self.serverRequests = serverRequests.stream
        self.serverRequestContinuation = serverRequests.continuation
        self.transport = transport
        self.connectionPolicy = connectionPolicy
        self.foregroundWorkGate = foregroundWorkGate
        self.connectionStateContinuation.yield(.idle)
    }

    public init(
        webSocketURL: URL,
        bearerToken: String? = nil,
        session: URLSession = .shared,
        connectionPolicy: AppServerConnectionPolicy = .oneShot,
        foregroundWorkGate: (any AppForegroundWorkGating)? = nil
    ) {
        self.init(
            transport: URLSessionWebSocketAppServerTransport(
                url: webSocketURL,
                bearerToken: bearerToken,
                session: session
            ),
            connectionPolicy: connectionPolicy,
            foregroundWorkGate: foregroundWorkGate
        )
    }

    deinit {
        receiveTask?.cancel()
        reconnectTask?.cancel()
        connectionStateContinuation.finish()
        notificationContinuation.finish()
        serverRequestContinuation.finish()
    }

    public func connectAndInitialize(
        params: InitializeParams = .codexDock(),
        timeout: Duration = .seconds(10)
    ) async throws -> InitializeResponse {
        let startedAt = Date()
        let signpostState = DockSignpost.appServer.beginInterval("app-server.connectAndInitialize")
        DockLog.appServer.notice("app-server connect initialize started")
        isExplicitlyDisconnected = false
        reconnectTask?.cancel()
        reconnectTask = nil
        initializeParams = params
        initializeTimeout = timeout

        do {
            try await openTransport(mode: .initial)
            let response = try await completeInitializeHandshake(params: params, timeout: timeout)
            DockSignpost.appServer.endInterval("app-server.connectAndInitialize", signpostState)
            DockLog.appServer.notice("app-server connect initialize finished duration_ms=\(DockLog.milliseconds(since: startedAt), privacy: .public) user_agent=\(DockLog.redacted(response.userAgent), privacy: .public)")
            return response
        } catch {
            let clientError = errorFrom(error)
            DockSignpost.appServer.endInterval("app-server.connectAndInitialize", signpostState)
            DockLog.appServer.error("app-server connect initialize failed duration_ms=\(DockLog.milliseconds(since: startedAt), privacy: .public) error=\(DockLog.errorSummary(clientError), privacy: .public)")
            if clientError.isOfflineConnectionFailure {
                markOffline(clientError.localizedDescription)
            } else {
                await failConnection(clientError)
            }
            throw clientError
        }
    }

    public func sendRequest(
        method: String,
        params: JSONValue? = nil,
        timeout: Duration = .seconds(10)
    ) async throws -> JSONValue {
        try await sendRequest(
            id: allocateRequestID(),
            method: method,
            params: params,
            timeout: timeout,
            allowsConnecting: false
        )
    }

    public func sendRequest<Response: Decodable>(
        method: String,
        params: JSONValue? = nil,
        timeout: Duration = .seconds(10),
        as responseType: Response.Type
    ) async throws -> Response {
        let result = try await sendRequest(method: method, params: params, timeout: timeout)
        return try decodeResponse(result, as: responseType)
    }

    public func sendNotification(method: String, params: JSONValue? = nil) async throws {
        try await sendNotification(method: method, params: params, allowsConnecting: false)
    }

    public func sendResponse(id: JSONRPCRequestID, result: JSONValue) async throws {
        try ensureCanSend(allowsConnecting: false)
        try await send(.response(JSONRPCResponse(id: id, result: result)))
    }

    public func threadList(
        params: ThreadListParams = ThreadListParams(),
        timeout: Duration = .seconds(10)
    ) async throws -> ThreadListResponseDTO {
        try await sendRequest(
            method: AppServerMethods.threadList,
            params: try JSONValue.encoded(params),
            timeout: timeout,
            as: ThreadListResponseDTO.self
        )
    }

    public func threadRead(
        params: ThreadReadParams,
        timeout: Duration = .seconds(10)
    ) async throws -> ThreadReadResponseDTO {
        try await sendRequest(
            method: AppServerMethods.threadRead,
            params: try JSONValue.encoded(params),
            timeout: timeout,
            as: ThreadReadResponseDTO.self
        )
    }

    public func threadTurnsList(
        params: ThreadTurnsListParams,
        timeout: Duration = .seconds(10)
    ) async throws -> ThreadTurnsListResponseDTO {
        try await sendRequest(
            method: AppServerMethods.threadTurnsList,
            params: try JSONValue.encoded(params),
            timeout: timeout,
            as: ThreadTurnsListResponseDTO.self
        )
    }

    public func threadResume(
        params: ThreadResumeParams,
        timeout: Duration = .seconds(10)
    ) async throws -> ThreadResumeResponseDTO {
        try await sendRequest(
            method: AppServerMethods.threadResume,
            params: try JSONValue.encoded(params),
            timeout: timeout,
            as: ThreadResumeResponseDTO.self
        )
    }

    public func threadArchive(
        params: ThreadArchiveParams,
        timeout: Duration = .seconds(10)
    ) async throws -> ThreadArchiveResponseDTO {
        try await sendRequest(
            method: AppServerMethods.threadArchive,
            params: try JSONValue.encoded(params),
            timeout: timeout,
            as: ThreadArchiveResponseDTO.self
        )
    }

    public func threadUnarchive(
        params: ThreadUnarchiveParams,
        timeout: Duration = .seconds(10)
    ) async throws -> ThreadUnarchiveResponseDTO {
        try await sendRequest(
            method: AppServerMethods.threadUnarchive,
            params: try JSONValue.encoded(params),
            timeout: timeout,
            as: ThreadUnarchiveResponseDTO.self
        )
    }

    public func turnStart(
        params: TurnStartParams,
        timeout: Duration = .seconds(10)
    ) async throws -> TurnStartResponseDTO {
        try await sendRequest(
            method: AppServerMethods.turnStart,
            params: try JSONValue.encoded(params),
            timeout: timeout,
            as: TurnStartResponseDTO.self
        )
    }

    public func turnSteer(
        params: TurnSteerParams,
        timeout: Duration = .seconds(10)
    ) async throws -> TurnSteerResponseDTO {
        try await sendRequest(
            method: AppServerMethods.turnSteer,
            params: try JSONValue.encoded(params),
            timeout: timeout,
            as: TurnSteerResponseDTO.self
        )
    }

    public func audioTranscriptionStart(
        params: AudioTranscriptionStartParams = AudioTranscriptionStartParams(),
        timeout: Duration = .seconds(10)
    ) async throws -> AudioTranscriptionStartResponseDTO {
        try await sendRequest(
            method: AppServerMethods.audioTranscriptionStart,
            params: try JSONValue.encoded(params),
            timeout: timeout,
            as: AudioTranscriptionStartResponseDTO.self
        )
    }

    public func audioTranscriptionAppend(
        params: AudioTranscriptionAppendParams,
        timeout: Duration = .seconds(10)
    ) async throws -> AudioTranscriptionAppendResponseDTO {
        try await sendRequest(
            method: AppServerMethods.audioTranscriptionAppend,
            params: try JSONValue.encoded(params),
            timeout: timeout,
            as: AudioTranscriptionAppendResponseDTO.self
        )
    }

    public func audioTranscriptionCommit(
        params: AudioTranscriptionCommitParams,
        timeout: Duration = .seconds(10)
    ) async throws -> AudioTranscriptionCommitResponseDTO {
        try await sendRequest(
            method: AppServerMethods.audioTranscriptionCommit,
            params: try JSONValue.encoded(params),
            timeout: timeout,
            as: AudioTranscriptionCommitResponseDTO.self
        )
    }

    public func audioTranscriptionCancel(
        params: AudioTranscriptionCancelParams,
        timeout: Duration = .seconds(10)
    ) async throws -> AudioTranscriptionCancelResponseDTO {
        try await sendRequest(
            method: AppServerMethods.audioTranscriptionCancel,
            params: try JSONValue.encoded(params),
            timeout: timeout,
            as: AudioTranscriptionCancelResponseDTO.self
        )
    }

    private func sendNotification(
        method: String,
        params: JSONValue? = nil,
        allowsConnecting: Bool
    ) async throws {
        try ensureCanSend(allowsConnecting: allowsConnecting)
        let message = JSONRPCMessage.notification(
            JSONRPCNotification(method: method, params: params)
        )
        try await send(message)
    }

    public func disconnect() async {
        DockLog.appServer.notice("app-server disconnect requested state=\(self.state.logDescription, privacy: .public) pending=\(self.pendingRequests.count, privacy: .public)")
        isExplicitlyDisconnected = true
        reconnectTask?.cancel()
        reconnectTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        failAllPending(with: .disconnected("client disconnected"))
        await transport.disconnect()
        setState(.closed(reason: "client disconnected"))
        connectionStateContinuation.finish()
        notificationContinuation.finish()
        serverRequestContinuation.finish()
    }

    private func openTransport(mode: TransportOpenMode) async throws {
        DockLog.appServer.info("app-server transport open started mode=\(mode.logDescription, privacy: .public)")
        if mode == .initial {
            setState(.connecting)
        }

        do {
            try await transport.connect()
            startReceiveLoop()
            DockLog.appServer.info("app-server transport open finished mode=\(mode.logDescription, privacy: .public)")
        } catch {
            let wrapped = AppServerClientError.transport(error.localizedDescription)
            if mode == .initial {
                setState(.offline(reason: wrapped.localizedDescription))
            }
            DockLog.appServer.error("app-server transport open failed mode=\(mode.logDescription, privacy: .public) error=\(DockLog.errorSummary(wrapped), privacy: .public)")
            throw wrapped
        }
    }

    private func completeInitializeHandshake(
        params: InitializeParams,
        timeout: Duration
    ) async throws -> InitializeResponse {
        let response = try await initialize(params: params, timeout: timeout)
        try await sendNotification(method: AppServerMethods.initialized, allowsConnecting: true)
        serverInfo = response
        setState(.connected)
        return response
    }

    private func initialize(
        params: InitializeParams,
        timeout: Duration
    ) async throws -> InitializeResponse {
        let paramsValue = try JSONValue.encoded(params)
        let result = try await sendRequest(
            id: .string("initialize"),
            method: AppServerMethods.initialize,
            params: paramsValue,
            timeout: timeout,
            allowsConnecting: true
        )
        return try decodeResponse(result, as: InitializeResponse.self)
    }

    private func sendRequest(
        id: JSONRPCRequestID,
        method: String,
        params: JSONValue?,
        timeout: Duration,
        allowsConnecting: Bool
    ) async throws -> JSONValue {
        try ensureCanSend(allowsConnecting: allowsConnecting)

        guard pendingRequests[id] == nil else {
            DockLog.appServer.error("app-server request duplicate method=\(method, privacy: .public) request_id=\(DockLog.publicID(id), privacy: .public)")
            throw AppServerClientError.duplicateRequestID(id)
        }

        let request = JSONRPCRequest(id: id, method: method, params: params)
        let text = try JSONRPCMessage.request(request).jsonString()
        DockLog.appServer.info("app-server request started method=\(method, privacy: .public) request_id=\(DockLog.publicID(id), privacy: .public)")

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let timeoutTask = Task { [weak self] in
                    do {
                        try await Task.sleep(for: timeout)
                        await self?.finishPending(
                            id: id,
                            result: .failure(AppServerClientError.requestTimedOut(id))
                        )
                    } catch {
                        return
                    }
                }

                pendingRequests[id] = PendingRequest(
                    method: method,
                    startedAt: Date(),
                    continuation: continuation,
                    timeoutTask: timeoutTask
                )

                Task { [weak self] in
                    do {
                        try await self?.sendRaw(text)
                    } catch {
                        await self?.finishPending(
                            id: id,
                            result: .failure(AppServerClientError.transport(error.localizedDescription))
                        )
                        await self?.handleConnectedSendFailure(error.localizedDescription)
                    }
                }
            }
        } onCancel: {
            Task { [weak self] in
                await self?.finishPending(
                    id: id,
                    result: .failure(AppServerClientError.requestCancelled(id))
                )
            }
        }
    }

    private func allocateRequestID() -> JSONRPCRequestID {
        let id = JSONRPCRequestID.integer(nextRequestNumber)
        nextRequestNumber += 1
        return id
    }

    private func send(_ message: JSONRPCMessage) async throws {
        let text = try message.jsonString()
        try await sendRaw(text)
    }

    private func sendRaw(_ text: String) async throws {
        do {
            try await transport.send(text)
        } catch {
            throw AppServerClientError.transport(error.localizedDescription)
        }
    }

    private func startReceiveLoop() {
        receiveTask?.cancel()
        receiveTask = Task { [weak self, transport] in
            await self?.logReceiveLoopStarted()
            while !Task.isCancelled {
                do {
                    guard let text = try await transport.receive() else {
                        await self?.handleTransportLoss("transport closed")
                        return
                    }

                    let message: JSONRPCMessage
                    do {
                        message = try JSONRPCMessage.decode(from: text)
                    } catch {
                        DockLog.appServer.error("app-server received malformed message error=\(DockLog.errorSummary(error), privacy: .public)")
                        await self?.failConnection(.malformedMessage(error.localizedDescription))
                        return
                    }

                    await self?.handleIncoming(message)
                } catch is CancellationError {
                    await self?.logReceiveLoopEnded(reason: "cancelled")
                    return
                } catch {
                    await self?.handleTransportLoss(error.localizedDescription)
                    return
                }
            }
        }
    }

    private func handleTransportLoss(_ reason: String) async {
        DockLog.appServer.warning("app-server transport lost reason=\(DockLog.redacted(reason), privacy: .public) reconnect_enabled=\((self.connectionPolicy.reconnect != nil), privacy: .public)")
        receiveTask = nil
        failAllPending(with: .disconnected(reason))
        await transport.disconnect()

        guard connectionPolicy.reconnect != nil,
              initializeParams != nil,
              !isExplicitlyDisconnected else {
            markOffline(reason)
            return
        }

        startReconnect(reason: reason)
    }

    private func startReconnect(reason: String) {
        guard reconnectTask == nil else {
            return
        }
        DockLog.appServer.warning("app-server reconnect loop scheduled reason=\(DockLog.redacted(reason), privacy: .public)")
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            await self?.runReconnectLoop(reason: reason)
        }
    }

    private func runReconnectLoop(reason: String) async {
        guard let reconnect = connectionPolicy.reconnect,
              let params = initializeParams else {
            markOffline(reason)
            return
        }

        var lastErrorReason = reason
        for attempt in 1...reconnect.maxAttempts {
            guard !Task.isCancelled, !isExplicitlyDisconnected else {
                return
            }
            guard await waitForForegroundWorkIfNeeded() else {
                return
            }

            setState(.reconnecting(attempt: attempt, reason: lastErrorReason))
            DockLog.appServer.notice("app-server reconnect attempt started attempt=\(attempt, privacy: .public) max_attempts=\(reconnect.maxAttempts, privacy: .public)")

            do {
                try await Task.sleep(for: reconnect.delay(for: attempt))
            } catch {
                return
            }

            guard !Task.isCancelled, !isExplicitlyDisconnected else {
                return
            }
            guard await waitForForegroundWorkIfNeeded() else {
                return
            }

            do {
                try await openTransport(mode: .reconnecting)
                _ = try await completeInitializeHandshake(params: params, timeout: initializeTimeout)
                reconnectTask = nil
                DockLog.appServer.notice("app-server reconnect attempt succeeded attempt=\(attempt, privacy: .public)")
                return
            } catch {
                lastErrorReason = errorFrom(error).localizedDescription
                DockLog.appServer.warning("app-server reconnect attempt failed attempt=\(attempt, privacy: .public) error=\(DockLog.redacted(lastErrorReason), privacy: .public)")
                failAllPending(with: .disconnected(lastErrorReason))
                await transport.disconnect()
            }
        }

        reconnectTask = nil
        DockLog.appServer.error("app-server reconnect exhausted attempts=\(reconnect.maxAttempts, privacy: .public) last_error=\(DockLog.redacted(lastErrorReason), privacy: .public)")
        markOffline("Reconnect failed after \(reconnect.maxAttempts) attempts: \(lastErrorReason)")
    }

    private func waitForForegroundWorkIfNeeded() async -> Bool {
        guard let foregroundWorkGate else {
            return true
        }

        while !Task.isCancelled, !isExplicitlyDisconnected {
            if await foregroundWorkGate.allowsForegroundWork {
                return true
            }
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return false
            }
        }
        return false
    }

    private func handleConnectedSendFailure(_ reason: String) async {
        guard state == .connected else {
            return
        }
        DockLog.appServer.warning("app-server connected send failed reason=\(DockLog.redacted(reason), privacy: .public)")
        await handleTransportLoss(reason)
    }

    private func handleIncoming(_ message: JSONRPCMessage) async {
        switch message {
        case .response(let response):
            if finishPending(id: response.id, result: .success(response.result)) {
                return
            }
            if retiredRequestIDs.remove(response.id) != nil {
                return
            }
            await failConnection(.unmatchedResponse(response.id))
        case .error(let error):
            if finishPending(id: error.id, result: .failure(AppServerClientError.server(error.error))) {
                return
            }
            if retiredRequestIDs.remove(error.id) != nil {
                return
            }
            await failConnection(.unmatchedResponse(error.id))
        case .notification(let notification):
            notificationContinuation.yield(notification)
        case .request(let request):
            serverRequestContinuation.yield(request)
        }
    }

    @discardableResult
    private func finishPending(
        id: JSONRPCRequestID,
        result: Result<JSONValue, Error>
    ) -> Bool {
        guard let pending = pendingRequests.removeValue(forKey: id) else {
            return false
        }

        pending.timeoutTask.cancel()
        let duration = DockLog.milliseconds(since: pending.startedAt)
        switch result {
        case .success(let value):
            DockLog.appServer.info("app-server request finished method=\(pending.method, privacy: .public) request_id=\(DockLog.publicID(id), privacy: .public) duration_ms=\(duration, privacy: .public)")
            pending.continuation.resume(returning: value)
        case .failure(let error):
            DockLog.appServer.warning("app-server request failed method=\(pending.method, privacy: .public) request_id=\(DockLog.publicID(id), privacy: .public) duration_ms=\(duration, privacy: .public) error=\(DockLog.errorSummary(error), privacy: .public)")
            if shouldRetireRequestID(for: error) {
                retiredRequestIDs.insert(id)
            }
            pending.continuation.resume(throwing: error)
        }
        return true
    }

    private func shouldRetireRequestID(for error: Error) -> Bool {
        guard let clientError = error as? AppServerClientError else {
            return false
        }
        switch clientError {
        case .requestCancelled, .requestTimedOut:
            return true
        default:
            return false
        }
    }

    private func failAllPending(with error: AppServerClientError) {
        let pending = pendingRequests
        pendingRequests.removeAll()

        for (_, request) in pending {
            request.timeoutTask.cancel()
            request.continuation.resume(throwing: error)
        }
    }

    private func markOffline(_ reason: String) {
        DockLog.appServer.warning("app-server marked offline reason=\(DockLog.redacted(reason), privacy: .public)")
        failAllPending(with: .disconnected(reason))
        setState(.offline(reason: reason))
        notificationContinuation.finish()
        serverRequestContinuation.finish()
    }

    private func failConnection(_ error: AppServerClientError) async {
        DockLog.appServer.error("app-server connection failed error=\(DockLog.errorSummary(error), privacy: .public)")
        receiveTask?.cancel()
        receiveTask = nil
        failAllPending(with: error)
        await transport.disconnect()
        setState(.error(message: error.localizedDescription))
        notificationContinuation.finish()
        serverRequestContinuation.finish()
    }

    private func setState(_ state: AppServerConnectionState) {
        DockLog.appServer.debug("app-server state transition from=\(self.state.logDescription, privacy: .public) to=\(state.logDescription, privacy: .public)")
        self.state = state
        connectionStateContinuation.yield(state)
    }

    private func logReceiveLoopStarted() {
        DockLog.appServer.debug("app-server receive loop started")
    }

    private func logReceiveLoopEnded(reason: String) {
        DockLog.appServer.debug("app-server receive loop ended reason=\(DockLog.redacted(reason), privacy: .public)")
    }

    private func ensureCanSend(allowsConnecting: Bool) throws {
        switch state {
        case .connected:
            return
        case .connecting where allowsConnecting:
            return
        case .reconnecting where allowsConnecting:
            return
        case .idle, .connecting, .reconnecting, .offline, .error, .closed:
            throw AppServerClientError.notConnected(state)
        }
    }

    private func decodeResponse<Response: Decodable>(
        _ value: JSONValue,
        as responseType: Response.Type
    ) throws -> Response {
        do {
            return try value.decoded(as: responseType)
        } catch {
            throw AppServerClientError.responseDecoding(error.localizedDescription)
        }
    }

    private func errorFrom(_ error: Error) -> AppServerClientError {
        if let clientError = error as? AppServerClientError {
            return clientError
        }
        return .transport(error.localizedDescription)
    }
}

private extension AppServerConnectionState {
    var logDescription: String {
        switch self {
        case .idle:
            return "idle"
        case .connecting:
            return "connecting"
        case .connected:
            return "connected"
        case .reconnecting(let attempt, let reason):
            return "reconnecting(attempt=\(attempt),reason=\(DockLog.redacted(reason)))"
        case .offline(let reason):
            return "offline(reason=\(DockLog.redacted(reason)))"
        case .error(let message):
            return "error(message=\(DockLog.redacted(message)))"
        case .closed(let reason):
            return "closed(reason=\(DockLog.redacted(reason)))"
        }
    }
}

private extension AppServerClientError {
    var isOfflineConnectionFailure: Bool {
        switch self {
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
}

public final class URLSessionWebSocketAppServerTransport: AppServerTransport, @unchecked Sendable {
    public static let defaultMaximumMessageSize = 8 * 1024 * 1024

    private let url: URL
    private let bearerToken: String?
    private let session: URLSession
    let maximumMessageSize: Int
    private let lock = NSLock()
    private var task: URLSessionWebSocketTask?

    public init(
        url: URL,
        bearerToken: String? = nil,
        session: URLSession = .shared,
        maximumMessageSize: Int = URLSessionWebSocketAppServerTransport.defaultMaximumMessageSize
    ) {
        self.url = url
        self.bearerToken = bearerToken
        self.session = session
        self.maximumMessageSize = maximumMessageSize
    }

    var urlRequest: URLRequest {
        var request = URLRequest(url: url)
        if let bearerToken, !bearerToken.isEmpty {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    public func connect() async throws {
        let task = session.webSocketTask(with: urlRequest)
        task.maximumMessageSize = maximumMessageSize
        setTask(task)
        task.resume()
    }

    public func send(_ text: String) async throws {
        guard let task = currentTask() else {
            throw AppServerClientError.disconnected("websocket task is not connected")
        }
        try await task.send(.string(text))
    }

    public func receive() async throws -> String? {
        guard let task = currentTask() else {
            throw AppServerClientError.disconnected("websocket task is not connected")
        }

        let message = try await task.receive()
        switch message {
        case .string(let text):
            return text
        case .data(let data):
            guard let text = String(data: data, encoding: .utf8) else {
                throw AppServerClientError.malformedMessage("binary websocket frame is not UTF-8")
            }
            return text
        @unknown default:
            throw AppServerClientError.malformedMessage("unknown websocket frame type")
        }
    }

    public func disconnect() async {
        let task = takeTask()
        task?.cancel(with: .normalClosure, reason: nil)
    }

    private func currentTask() -> URLSessionWebSocketTask? {
        lock.lock()
        defer { lock.unlock() }
        return task
    }

    private func setTask(_ task: URLSessionWebSocketTask?) {
        lock.lock()
        self.task = task
        lock.unlock()
    }

    private func takeTask() -> URLSessionWebSocketTask? {
        lock.lock()
        defer { lock.unlock() }
        let task = self.task
        self.task = nil
        return task
    }
}

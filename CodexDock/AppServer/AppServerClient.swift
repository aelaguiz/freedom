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
    case offline(reason: String)
    case error(message: String)
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
    private struct PendingRequest {
        let continuation: CheckedContinuation<JSONValue, Error>
        let timeoutTask: Task<Void, Never>
    }

    public private(set) var state: AppServerConnectionState = .idle
    public private(set) var serverInfo: InitializeResponse?
    public nonisolated let notifications: AsyncStream<JSONRPCNotification>

    private let notificationContinuation: AsyncStream<JSONRPCNotification>.Continuation
    private let transport: any AppServerTransport
    private var nextRequestNumber: Int64 = 1
    private var pendingRequests: [JSONRPCRequestID: PendingRequest] = [:]
    private var receiveTask: Task<Void, Never>?

    public init(transport: any AppServerTransport) {
        let stream = AsyncStream.makeStream(of: JSONRPCNotification.self)
        self.notifications = stream.stream
        self.notificationContinuation = stream.continuation
        self.transport = transport
    }

    public init(
        webSocketURL: URL,
        bearerToken: String? = nil,
        session: URLSession = .shared
    ) {
        self.init(
            transport: URLSessionWebSocketAppServerTransport(
                url: webSocketURL,
                bearerToken: bearerToken,
                session: session
            )
        )
    }

    deinit {
        receiveTask?.cancel()
        notificationContinuation.finish()
    }

    public func connectAndInitialize(
        params: InitializeParams = .codexDock(),
        timeout: Duration = .seconds(10)
    ) async throws -> InitializeResponse {
        try await openTransport()

        do {
            let response = try await initialize(params: params, timeout: timeout)
            try await sendNotification(method: AppServerMethods.initialized, allowsConnecting: true)
            serverInfo = response
            state = .connected
            return response
        } catch {
            let clientError = errorFrom(error)
            await failConnection(clientError)
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
        receiveTask?.cancel()
        receiveTask = nil
        failAllPending(with: .disconnected("client disconnected"))
        await transport.disconnect()
        state = .offline(reason: "client disconnected")
        notificationContinuation.finish()
    }

    private func openTransport() async throws {
        state = .connecting

        do {
            try await transport.connect()
            startReceiveLoop()
        } catch {
            let wrapped = AppServerClientError.transport(error.localizedDescription)
            state = .offline(reason: wrapped.localizedDescription)
            throw wrapped
        }
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
            throw AppServerClientError.duplicateRequestID(id)
        }

        let request = JSONRPCRequest(id: id, method: method, params: params)
        let text = try JSONRPCMessage.request(request).jsonString()

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
                    continuation: continuation,
                    timeoutTask: timeoutTask
                )

                Task { [weak self, transport] in
                    do {
                        try await transport.send(text)
                    } catch {
                        await self?.finishPending(
                            id: id,
                            result: .failure(AppServerClientError.transport(error.localizedDescription))
                        )
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
        do {
            try await transport.send(text)
        } catch {
            throw AppServerClientError.transport(error.localizedDescription)
        }
    }

    private func startReceiveLoop() {
        receiveTask?.cancel()
        receiveTask = Task { [weak self, transport] in
            while !Task.isCancelled {
                do {
                    guard let text = try await transport.receive() else {
                        await self?.markOffline("transport closed")
                        return
                    }

                    let message: JSONRPCMessage
                    do {
                        message = try JSONRPCMessage.decode(from: text)
                    } catch {
                        await self?.failConnection(.malformedMessage(error.localizedDescription))
                        return
                    }

                    await self?.handleIncoming(message)
                } catch is CancellationError {
                    return
                } catch {
                    await self?.failConnection(.transport(error.localizedDescription))
                    return
                }
            }
        }
    }

    private func handleIncoming(_ message: JSONRPCMessage) async {
        switch message {
        case .response(let response):
            if !finishPending(id: response.id, result: .success(response.result)) {
                await failConnection(.unmatchedResponse(response.id))
            }
        case .error(let error):
            if !finishPending(id: error.id, result: .failure(AppServerClientError.server(error.error))) {
                await failConnection(.unmatchedResponse(error.id))
            }
        case .notification(let notification):
            notificationContinuation.yield(notification)
        case .request(let request):
            await failConnection(.unexpectedServerRequest(method: request.method))
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
        switch result {
        case .success(let value):
            pending.continuation.resume(returning: value)
        case .failure(let error):
            pending.continuation.resume(throwing: error)
        }
        return true
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
        failAllPending(with: .disconnected(reason))
        state = .offline(reason: reason)
    }

    private func failConnection(_ error: AppServerClientError) async {
        receiveTask?.cancel()
        receiveTask = nil
        failAllPending(with: error)
        await transport.disconnect()
        state = .error(message: error.localizedDescription)
    }

    private func ensureCanSend(allowsConnecting: Bool) throws {
        switch state {
        case .connected:
            return
        case .connecting where allowsConnecting:
            return
        case .idle, .connecting, .offline, .error:
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

public final class URLSessionWebSocketAppServerTransport: AppServerTransport, @unchecked Sendable {
    private let url: URL
    private let bearerToken: String?
    private let session: URLSession
    private var task: URLSessionWebSocketTask?

    public init(
        url: URL,
        bearerToken: String? = nil,
        session: URLSession = .shared
    ) {
        self.url = url
        self.bearerToken = bearerToken
        self.session = session
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
        self.task = task
        task.resume()
    }

    public func send(_ text: String) async throws {
        guard let task else {
            throw AppServerClientError.disconnected("websocket task is not connected")
        }
        try await task.send(.string(text))
    }

    public func receive() async throws -> String? {
        guard let task else {
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
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
    }
}

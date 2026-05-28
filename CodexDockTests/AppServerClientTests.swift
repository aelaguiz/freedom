import XCTest
@testable import CodexDock

final class AppServerClientTests: XCTestCase {
    func testRequestEncodingOmitsJSONRPCVersionAndKeepsExplicitID() throws {
        let message = JSONRPCMessage.request(
            JSONRPCRequest(
                id: .integer(7),
                method: "initialize",
                params: .object([
                    "clientInfo": .object([
                        "name": .string("codex_dock"),
                        "title": .string("Codex Dock"),
                        "version": .string("0.1.0"),
                    ]),
                ])
            )
        )

        let value = try jsonObject(from: message)

        XCTAssertEqual(value["id"] as? Int, 7)
        XCTAssertEqual(value["method"] as? String, "initialize")
        XCTAssertNil(value["jsonrpc"])
        XCTAssertNotNil(value["params"])
    }

    func testResponseDecodingAllowsUnknownFields() throws {
        let message = try JSONRPCMessage.decode(
            from: """
            {
              "id": "initialize",
              "result": {
                "userAgent": "codex/1.2.3",
                "codexHome": "/Users/aelaguiz/.codex",
                "platformFamily": "unix",
                "platformOs": "macos"
              },
              "ignored": true
            }
            """
        )

        guard case .response(let response) = message else {
            return XCTFail("Expected a response")
        }

        XCTAssertEqual(response.id, .string("initialize"))
        let initializeResponse = try response.result.decoded(as: InitializeResponse.self)
        XCTAssertEqual(initializeResponse.userAgent, "codex/1.2.3")
        XCTAssertEqual(initializeResponse.platformOs, "macos")
    }

    func testNotificationDecoding() throws {
        let message = try JSONRPCMessage.decode(
            from: """
            {
              "method": "thread/started",
              "params": {
                "threadId": "thread-1"
              }
            }
            """
        )

        XCTAssertEqual(
            message,
            .notification(
                JSONRPCNotification(
                    method: "thread/started",
                    params: .object(["threadId": .string("thread-1")])
                )
            )
        )
    }

    func testErrorResponseDecodingKeepsIDAndErrorObject() throws {
        let message = try JSONRPCMessage.decode(
            from: """
            {
              "id": 5,
              "error": {
                "code": -32601,
                "message": "method not found",
                "data": {
                  "method": "missing/method"
                }
              }
            }
            """
        )

        XCTAssertEqual(
            message,
            .error(
                JSONRPCErrorResponse(
                    error: JSONRPCErrorObject(
                        code: -32601,
                        message: "method not found",
                        data: .object(["method": .string("missing/method")])
                    ),
                    id: .integer(5)
                )
            )
        )
    }

    func testMalformedPayloadFailsLoudly() {
        XCTAssertThrowsError(try JSONRPCMessage.decode(from: #"{"id": 1}"#))
        XCTAssertThrowsError(try JSONRPCMessage.decode(from: #"{"id": 1, "result": }"#))
    }

    func testMultipleInFlightRequestIDsResolveToMatchingResponses() async throws {
        let transport = ScriptedAppServerTransport()
        let client = AppServerClient(transport: transport)
        try await completeHandshake(client: client, transport: transport)

        let firstTask = Task {
            try await client.sendRequest(method: "first", timeout: .seconds(1))
        }
        let secondTask = Task {
            try await client.sendRequest(method: "second", timeout: .seconds(1))
        }

        let sentRequests = [
            try await transport.nextSentRequest(),
            try await transport.nextSentRequest(),
        ]
        let firstRequest = try XCTUnwrap(sentRequests.first { $0.method == "first" })
        let secondRequest = try XCTUnwrap(sentRequests.first { $0.method == "second" })

        await transport.enqueue(
            .response(
                JSONRPCResponse(
                    id: secondRequest.id,
                    result: .object(["value": .string("second-result")])
                )
            )
        )
        await transport.enqueue(
            .response(
                JSONRPCResponse(
                    id: firstRequest.id,
                    result: .object(["value": .string("first-result")])
                )
            )
        )

        let first = try await firstTask.value
        let second = try await secondTask.value

        XCTAssertEqual(first, .object(["value": .string("first-result")]))
        XCTAssertEqual(second, .object(["value": .string("second-result")]))
    }

    func testReceiveLoopContinuesAfterResponseAndDeliversNotifications() async throws {
        let transport = ScriptedAppServerTransport()
        let client = AppServerClient(transport: transport)
        try await completeHandshake(client: client, transport: transport)

        let notificationTask = Task {
            var iterator = client.notifications.makeAsyncIterator()
            return await iterator.next()
        }
        let requestTask = Task {
            try await client.sendRequest(method: "ping", timeout: .seconds(1))
        }

        let request = try await transport.nextSentRequest()
        await transport.enqueue(.response(JSONRPCResponse(id: request.id, result: .string("pong"))))
        await transport.enqueue(
            .notification(
                JSONRPCNotification(
                    method: "server/event",
                    params: .object(["ok": .bool(true)])
                )
            )
        )

        let requestValue = try await requestTask.value
        XCTAssertEqual(requestValue, .string("pong"))
        let notification = try await valueWithinOneSecond {
            await notificationTask.value
        }

        XCTAssertEqual(notification?.method, "server/event")
        XCTAssertEqual(notification?.params, .object(["ok": .bool(true)]))
    }

    func testOfflineAndMalformedResponsePathsSurfaceExplicitState() async throws {
        let offlineTransport = ScriptedAppServerTransport(connectError: TestTransportError.offline)
        let offlineClient = AppServerClient(transport: offlineTransport)

        await XCTAssertThrowsAsyncError(try await offlineClient.connectAndInitialize())
        guard case .offline(let reason) = await offlineClient.state else {
            return XCTFail("Expected offline state")
        }
        XCTAssertTrue(reason.contains("offline"))

        let malformedTransport = ScriptedAppServerTransport()
        let malformedClient = AppServerClient(transport: malformedTransport)
        try await completeHandshake(client: malformedClient, transport: malformedTransport)
        await malformedTransport.enqueueRaw("{ definitely not json")

        try await waitUntil {
            if case .error(let message) = await malformedClient.state {
                return message.contains("Malformed app-server JSON-RPC message")
            }
            return false
        }
    }

    func testRequestTimeoutFailsVisibly() async throws {
        let transport = ScriptedAppServerTransport()
        let client = AppServerClient(transport: transport)
        try await completeHandshake(client: client, transport: transport)

        do {
            _ = try await client.sendRequest(method: "never-responds", timeout: .milliseconds(50))
            XCTFail("Expected timeout")
        } catch AppServerClientError.requestTimedOut {
            // Expected.
        } catch {
            XCTFail("Expected request timeout, got \(error)")
        }
    }

    func testServerErrorResponseFailsMatchingRequest() async throws {
        let transport = ScriptedAppServerTransport()
        let client = AppServerClient(transport: transport)
        try await completeHandshake(client: client, transport: transport)

        let task = Task {
            try await client.sendRequest(method: "missing/method", timeout: .seconds(1))
        }
        let request = try await transport.nextSentRequest()
        await transport.enqueue(
            .error(
                JSONRPCErrorResponse(
                    error: JSONRPCErrorObject(code: -32601, message: "method not found"),
                    id: request.id
                )
            )
        )

        do {
            _ = try await task.value
            XCTFail("Expected server error")
        } catch AppServerClientError.server(let error) {
            XCTAssertEqual(error.code, -32601)
            XCTAssertEqual(error.message, "method not found")
        } catch {
            XCTFail("Expected server error, got \(error)")
        }
    }

    func testRequestCancellationFailsVisibly() async throws {
        let transport = ScriptedAppServerTransport()
        let client = AppServerClient(transport: transport)
        try await completeHandshake(client: client, transport: transport)

        let task = Task {
            try await client.sendRequest(method: "cancel-me", timeout: .seconds(1))
        }
        _ = try await transport.nextSentRequest()
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch AppServerClientError.requestCancelled {
            // Expected.
        } catch {
            XCTFail("Expected request cancellation, got \(error)")
        }
    }

    func testInitializeHandshakeSendsInitializedAfterInitializeResponse() async throws {
        let transport = ScriptedAppServerTransport()
        let client = AppServerClient(transport: transport)

        let handshakeTask = Task {
            try await client.connectAndInitialize(
                params: .codexDock(version: "0.1.0"),
                timeout: .seconds(1)
            )
        }

        let initializeRequest = try await transport.nextSentRequest()
        XCTAssertEqual(initializeRequest.id, .string("initialize"))
        XCTAssertEqual(initializeRequest.method, AppServerMethods.initialize)

        await transport.enqueue(
            .response(
                JSONRPCResponse(
                    id: initializeRequest.id,
                    result: .object([
                        "userAgent": .string("codex/1.2.3"),
                        "codexHome": .string("/Users/aelaguiz/.codex"),
                        "platformFamily": .string("unix"),
                        "platformOs": .string("macos"),
                    ])
                )
            )
        )

        let initializedNotification = try await transport.nextSentNotification()
        XCTAssertEqual(initializedNotification.method, AppServerMethods.initialized)
        XCTAssertNil(initializedNotification.params)

        let response = try await handshakeTask.value
        XCTAssertEqual(response.userAgent, "codex/1.2.3")
        XCTAssertEqual(response.codexHome, "/Users/aelaguiz/.codex")
        let serverInfo = await client.serverInfo
        let state = await client.state
        XCTAssertEqual(serverInfo, response)
        XCTAssertEqual(state, .connected)
    }

    func testWebSocketTransportAddsBearerAuthorizationHeader() throws {
        let url = try XCTUnwrap(URL(string: "ws://192.0.2.1:4500"))
        let transport = URLSessionWebSocketAppServerTransport(
            url: url,
            bearerToken: "secret-token"
        )

        XCTAssertEqual(
            transport.urlRequest.value(forHTTPHeaderField: "Authorization"),
            "Bearer secret-token"
        )
    }

    func testWebSocketTransportOmitsAuthorizationHeaderWithoutToken() throws {
        let url = try XCTUnwrap(URL(string: "ws://192.0.2.1:4500"))
        let transport = URLSessionWebSocketAppServerTransport(url: url)

        XCTAssertNil(transport.urlRequest.value(forHTTPHeaderField: "Authorization"))
    }

    func testLoopbackRealHostInitializeHandshakeWhenEndpointIsProvided() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let endpoint = environment["CODEX_DOCK_LOOPBACK_APP_SERVER_WS"], !endpoint.isEmpty else {
            throw XCTSkip(
                "Set CODEX_DOCK_LOOPBACK_APP_SERVER_WS to run the loopback real-host smoke test"
            )
        }
        let url = try XCTUnwrap(URL(string: endpoint))
        XCTAssertTrue(
            ["ws", "wss"].contains(url.scheme?.lowercased()),
            "Loopback handshake endpoint must be a WebSocket URL"
        )
        XCTAssertTrue(
            isLoopbackHost(url.host),
            "Loopback smoke endpoint must be localhost, 127.0.0.1, or ::1"
        )

        try await assertRealHostHandshakeSucceeds(
            url: url,
            bearerToken: try appServerBearerToken(from: environment),
            timeout: .seconds(5)
        )
    }

    func testPhoneReachableRealHostInitializeHandshakeWhenEndpointIsProvided() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let endpoint = environment["CODEX_DOCK_PHONE_REACHABLE_APP_SERVER_WS"], !endpoint.isEmpty else {
            throw XCTSkip(
                "Set CODEX_DOCK_PHONE_REACHABLE_APP_SERVER_WS to run the phone-reachable real-host handshake test"
            )
        }
        let url = try XCTUnwrap(URL(string: endpoint))
        XCTAssertTrue(
            ["ws", "wss"].contains(url.scheme?.lowercased()),
            "Phone-reachable handshake endpoint must be a WebSocket URL"
        )
        XCTAssertFalse(
            isLoopbackHost(url.host),
            "Phone-reachable handshake endpoint cannot be localhost, 127.0.0.1, or ::1"
        )
        let bearerToken = try XCTUnwrap(
            try appServerBearerToken(from: environment),
            "Set CODEX_DOCK_APP_SERVER_BEARER_TOKEN or CODEX_DOCK_APP_SERVER_BEARER_TOKEN_FILE for the phone-reachable authenticated app-server"
        )

        try await assertRealHostHandshakeSucceeds(
            url: url,
            bearerToken: bearerToken,
            timeout: .seconds(5)
        )
    }
}

private func assertRealHostHandshakeSucceeds(
    url: URL,
    bearerToken: String?,
    timeout: Duration
) async throws {
    let client = AppServerClient(webSocketURL: url, bearerToken: bearerToken)

    let response = try await client.connectAndInitialize(
        params: .codexDock(version: "0.1.0"),
        timeout: timeout
    )

    XCTAssertFalse(response.userAgent.isEmpty)
    XCTAssertFalse(response.codexHome.isEmpty)
    XCTAssertFalse(response.platformFamily.isEmpty)
    XCTAssertFalse(response.platformOs.isEmpty)
    let state = await client.state
    XCTAssertEqual(state, .connected)
    await client.disconnect()
}

private func appServerBearerToken(from environment: [String: String]) throws -> String? {
    if let token = environment["CODEX_DOCK_APP_SERVER_BEARER_TOKEN"], !token.isEmpty {
        return token
    }

    guard let tokenFile = environment["CODEX_DOCK_APP_SERVER_BEARER_TOKEN_FILE"], !tokenFile.isEmpty else {
        return nil
    }

    let token = try String(contentsOfFile: tokenFile, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return token.isEmpty ? nil : token
}

private func isLoopbackHost(_ host: String?) -> Bool {
    guard let host = host?.lowercased() else {
        return false
    }
    return ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)
}

private actor ScriptedAppServerTransport: AppServerTransport {
    private enum SentWaiter {
        case message(CheckedContinuation<JSONRPCMessage, Error>)
    }

    private let connectError: Error?
    private var inbound: [Result<String?, Error>] = []
    private var inboundWaiters: [CheckedContinuation<String?, Error>] = []
    private var sentMessages: [JSONRPCMessage] = []
    private var sentWaiters: [SentWaiter] = []
    private var connected = false

    init(connectError: Error? = nil) {
        self.connectError = connectError
    }

    func connect() async throws {
        if let connectError {
            throw connectError
        }
        connected = true
    }

    func send(_ text: String) async throws {
        guard connected else {
            throw TestTransportError.offline
        }

        let message = try JSONRPCMessage.decode(from: text)
        if sentWaiters.isEmpty {
            sentMessages.append(message)
        } else {
            let waiter = sentWaiters.removeFirst()
            switch waiter {
            case .message(let continuation):
                continuation.resume(returning: message)
            }
        }
    }

    func receive() async throws -> String? {
        if !inbound.isEmpty {
            return try inbound.removeFirst().get()
        }

        return try await withCheckedThrowingContinuation { continuation in
            inboundWaiters.append(continuation)
        }
    }

    func disconnect() async {
        connected = false
        let waiters = inboundWaiters
        inboundWaiters.removeAll()
        for waiter in waiters {
            waiter.resume(returning: nil)
        }
    }

    func enqueue(_ message: JSONRPCMessage) async {
        await enqueueRaw(try! message.jsonString())
    }

    func enqueueRaw(_ text: String) async {
        enqueueResult(.success(text))
    }

    func nextSentRequest() async throws -> JSONRPCRequest {
        let message = try await nextSentMessage()
        guard case .request(let request) = message else {
            throw TestTransportError.unexpectedSentMessage
        }
        return request
    }

    func nextSentNotification() async throws -> JSONRPCNotification {
        let message = try await nextSentMessage()
        guard case .notification(let notification) = message else {
            throw TestTransportError.unexpectedSentMessage
        }
        return notification
    }

    private func enqueueResult(_ result: Result<String?, Error>) {
        if inboundWaiters.isEmpty {
            inbound.append(result)
        } else {
            let waiter = inboundWaiters.removeFirst()
            waiter.resume(with: result)
        }
    }

    private func nextSentMessage() async throws -> JSONRPCMessage {
        if !sentMessages.isEmpty {
            return sentMessages.removeFirst()
        }

        return try await withCheckedThrowingContinuation { continuation in
            sentWaiters.append(.message(continuation))
        }
    }
}

private enum TestTransportError: Error, LocalizedError {
    case offline
    case unexpectedSentMessage

    var errorDescription: String? {
        switch self {
        case .offline:
            "offline"
        case .unexpectedSentMessage:
            "unexpected sent message"
        }
    }
}

private func completeHandshake(
    client: AppServerClient,
    transport: ScriptedAppServerTransport
) async throws {
    let handshakeTask = Task {
        try await client.connectAndInitialize(
            params: .codexDock(version: "0.1.0"),
            timeout: .seconds(1)
        )
    }

    let initializeRequest = try await transport.nextSentRequest()
    await transport.enqueue(
        .response(
            JSONRPCResponse(
                id: initializeRequest.id,
                result: .object([
                    "userAgent": .string("codex/1.2.3"),
                    "codexHome": .string("/Users/aelaguiz/.codex"),
                    "platformFamily": .string("unix"),
                    "platformOs": .string("macos"),
                ])
            )
        )
    )
    _ = try await transport.nextSentNotification()
    _ = try await handshakeTask.value
}

private func jsonObject(from message: JSONRPCMessage) throws -> [String: Any] {
    let data = try message.jsonData()
    let object = try JSONSerialization.jsonObject(with: data)
    return try XCTUnwrap(object as? [String: Any])
}

private func valueWithinOneSecond<T: Sendable>(
    _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(for: .seconds(1))
            throw TestTimeoutError()
        }

        guard let value = try await group.next() else {
            throw TestTimeoutError()
        }
        group.cancelAll()
        return value
    }
}

private func waitUntil(
    timeout: Duration = .seconds(1),
    _ predicate: @escaping @Sendable () async -> Bool
) async throws {
    let start = ContinuousClock.now
    while start.duration(to: .now) < timeout {
        if await predicate() {
            return
        }
        try await Task.sleep(for: .milliseconds(10))
    }
    throw TestTimeoutError()
}

private func XCTAssertThrowsAsyncError(
    _ expression: @autoclosure () async throws -> some Any,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected async expression to throw", file: file, line: line)
    } catch {
        return
    }
}

private struct TestTimeoutError: Error {}

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
                "platformOs": "macos",
                "relayInstanceID": "Amir-M5"
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
        XCTAssertEqual(initializeResponse.relayInstanceID, "Amir-M5")
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

    func testConnectionStatesEmitConnectingConnectedAndOfflineOnMidstreamClose() async throws {
        let transport = ScriptedAppServerTransport()
        let client = AppServerClient(transport: transport)
        let stateTask = Task {
            var iterator = client.connectionStates.makeAsyncIterator()
            var states: [AppServerConnectionState] = []
            while states.count < 4, let state = await iterator.next() {
                states.append(state)
            }
            return states
        }

        try await completeHandshake(client: client, transport: transport)
        await transport.closeInbound()

        let states = try await valueWithinOneSecond {
            await stateTask.value
        }
        XCTAssertEqual(states, [
            .idle,
            .connecting,
            .connected,
            .offline(reason: "transport closed"),
        ])
    }

    func testExplicitDisconnectFinishesConnectionNotificationAndRequestStreams() async throws {
        let transport = ScriptedAppServerTransport()
        let client = AppServerClient(transport: transport)
        try await completeHandshake(client: client, transport: transport)

        let connectionTask = Task {
            var iterator = client.connectionStates.makeAsyncIterator()
            var states: [AppServerConnectionState] = []
            while let state = await iterator.next() {
                states.append(state)
            }
            return states
        }

        await client.disconnect()

        let states = try await valueWithinOneSecond {
            await connectionTask.value
        }
        XCTAssertEqual(states.last, .closed(reason: "client disconnected"))

        let notification = try await valueWithinOneSecond {
            var iterator = client.notifications.makeAsyncIterator()
            return await iterator.next()
        }
        XCTAssertNil(notification)

        let serverRequest = try await valueWithinOneSecond {
            var iterator = client.serverRequests.makeAsyncIterator()
            return await iterator.next()
        }
        XCTAssertNil(serverRequest)
    }

    func testLateTimedOutResponseIsIgnoredAndConnectionStaysUsable() async throws {
        let transport = ScriptedAppServerTransport()
        let client = AppServerClient(transport: transport)
        try await completeHandshake(client: client, transport: transport)

        let timedOutTask = Task {
            try await client.sendRequest(method: "never-responds", timeout: .milliseconds(50))
        }
        let timedOutRequest = try await transport.nextSentRequest()

        do {
            _ = try await timedOutTask.value
            XCTFail("Expected timeout")
        } catch AppServerClientError.requestTimedOut {
            // Expected.
        } catch {
            XCTFail("Expected request timeout, got \(error)")
        }

        await transport.enqueue(
            .response(
                JSONRPCResponse(
                    id: timedOutRequest.id,
                    result: .string("late")
                )
            )
        )

        let followUpTask = Task {
            try await client.sendRequest(method: "after-timeout", timeout: .seconds(1))
        }
        let followUpRequest = try await valueWithinOneSecond {
            try await transport.nextSentRequest()
        }
        XCTAssertEqual(followUpRequest.method, "after-timeout")
        await transport.enqueue(
            .response(
                JSONRPCResponse(
                    id: followUpRequest.id,
                    result: .string("ok")
                )
            )
        )

        let followUp = try await followUpTask.value
        XCTAssertEqual(followUp, .string("ok"))
        let state = await client.state
        XCTAssertEqual(state, .connected)
    }

    func testLateCancelledResponseIsIgnoredAndConnectionStaysUsable() async throws {
        let transport = ScriptedAppServerTransport()
        let client = AppServerClient(transport: transport)
        try await completeHandshake(client: client, transport: transport)

        let cancelledTask = Task {
            try await client.sendRequest(method: "cancel-me", timeout: .seconds(1))
        }
        let cancelledRequest = try await transport.nextSentRequest()
        cancelledTask.cancel()

        do {
            _ = try await cancelledTask.value
            XCTFail("Expected cancellation")
        } catch AppServerClientError.requestCancelled {
            // Expected.
        } catch {
            XCTFail("Expected request cancellation, got \(error)")
        }

        await transport.enqueue(
            .response(
                JSONRPCResponse(
                    id: cancelledRequest.id,
                    result: .string("late")
                )
            )
        )

        let followUpTask = Task {
            try await client.sendRequest(method: "after-cancel", timeout: .seconds(1))
        }
        let followUpRequest = try await valueWithinOneSecond {
            try await transport.nextSentRequest()
        }
        XCTAssertEqual(followUpRequest.method, "after-cancel")
        await transport.enqueue(
            .response(
                JSONRPCResponse(
                    id: followUpRequest.id,
                    result: .string("ok")
                )
            )
        )

        let followUp = try await followUpTask.value
        XCTAssertEqual(followUp, .string("ok"))
        let state = await client.state
        XCTAssertEqual(state, .connected)
    }

    func testNeverIssuedResponseStillFailsConnection() async throws {
        let transport = ScriptedAppServerTransport()
        let client = AppServerClient(transport: transport)
        try await completeHandshake(client: client, transport: transport)

        await transport.enqueue(
            .response(
                JSONRPCResponse(
                    id: .integer(999),
                    result: .string("unexpected")
                )
            )
        )

        try await waitUntil {
            if case .error(let message) = await client.state {
                return message.contains("unknown request id `999`")
            }
            return false
        }
    }

    func testReconnectEnabledClientTransitionsConnectedReconnectingConnectedAfterTransportClose() async throws {
        let transport = ScriptedAppServerTransport()
        let client = AppServerClient(
            transport: transport,
            connectionPolicy: AppServerConnectionPolicy(
                reconnect: AppServerReconnectPolicy(
                    maxAttempts: 1,
                    initialDelayMilliseconds: 0,
                    maxDelayMilliseconds: 0
                )
            )
        )
        let stateTask = Task {
            var iterator = client.connectionStates.makeAsyncIterator()
            var states: [AppServerConnectionState] = []
            while states.count < 5, let state = await iterator.next() {
                states.append(state)
            }
            return states
        }

        try await completeHandshake(client: client, transport: transport)
        await transport.closeInbound()

        let reconnectInitialize = try await valueWithinOneSecond {
            try await transport.nextSentRequest()
        }
        XCTAssertEqual(reconnectInitialize.id, .string("initialize"))
        XCTAssertEqual(reconnectInitialize.method, AppServerMethods.initialize)
        await transport.enqueue(
            .response(
                JSONRPCResponse(
                    id: reconnectInitialize.id,
                    result: initializeResult()
                )
            )
        )
        let initializedNotification = try await valueWithinOneSecond {
            try await transport.nextSentNotification()
        }
        XCTAssertEqual(initializedNotification.method, AppServerMethods.initialized)

        let states = try await valueWithinOneSecond {
            await stateTask.value
        }
        XCTAssertEqual(states, [
            .idle,
            .connecting,
            .connected,
            .reconnecting(attempt: 1, reason: "transport closed"),
            .connected,
        ])
    }

    func testReconnectExhaustionStopsAndFinishesDataStreams() async throws {
        let transport = ScriptedAppServerTransport()
        let client = AppServerClient(
            transport: transport,
            connectionPolicy: AppServerConnectionPolicy(
                reconnect: AppServerReconnectPolicy(
                    maxAttempts: 2,
                    initialDelayMilliseconds: 0,
                    maxDelayMilliseconds: 0
                )
            )
        )
        try await completeHandshake(client: client, transport: transport)
        await transport.enqueueConnectFailure(TestTransportError.offline)
        await transport.enqueueConnectFailure(TestTransportError.offline)

        let notificationTask = Task {
            var iterator = client.notifications.makeAsyncIterator()
            return await iterator.next()
        }
        let requestTask = Task {
            var iterator = client.serverRequests.makeAsyncIterator()
            return await iterator.next()
        }

        await transport.closeInbound()

        try await waitUntil {
            if case .offline(let reason) = await client.state {
                return reason.contains("Reconnect failed after 2 attempts")
            }
            return false
        }
        let notification = try await valueWithinOneSecond {
            await notificationTask.value
        }
        let serverRequest = try await valueWithinOneSecond {
            await requestTask.value
        }
        XCTAssertNil(notification)
        XCTAssertNil(serverRequest)
    }

    func testExplicitDisconnectCancelsScheduledReconnect() async throws {
        let transport = ScriptedAppServerTransport()
        let client = AppServerClient(
            transport: transport,
            connectionPolicy: AppServerConnectionPolicy(
                reconnect: AppServerReconnectPolicy(
                    maxAttempts: 1,
                    initialDelayMilliseconds: 250,
                    maxDelayMilliseconds: 250
                )
            )
        )
        try await completeHandshake(client: client, transport: transport)

        await transport.closeInbound()
        try await waitUntil {
            if case .reconnecting = await client.state {
                return true
            }
            return false
        }

        await client.disconnect()
        try await Task.sleep(for: .milliseconds(300))

        let connectCount = await transport.connectCountSnapshot()
        let state = await client.state
        XCTAssertEqual(connectCount, 1)
        XCTAssertEqual(state, .closed(reason: "client disconnected"))
    }

    func testReconnectWaitsForForegroundBeforeConsumingAttempt() async throws {
        let lifecycle = await MainActor.run {
            AppLifecycleCoordinator()
        }
        let transport = ScriptedAppServerTransport()
        let client = AppServerClient(
            transport: transport,
            connectionPolicy: AppServerConnectionPolicy(
                reconnect: AppServerReconnectPolicy(
                    maxAttempts: 1,
                    initialDelayMilliseconds: 0,
                    maxDelayMilliseconds: 0
                )
            ),
            foregroundWorkGate: lifecycle
        )
        try await completeHandshake(client: client, transport: transport)

        await MainActor.run {
            lifecycle.handle(.background)
        }
        await transport.closeInbound()
        try await Task.sleep(for: .milliseconds(100))

        let backgroundConnectCount = await transport.connectCountSnapshot()
        XCTAssertEqual(backgroundConnectCount, 1)

        await MainActor.run {
            lifecycle.handle(.active)
        }
        let reconnectInitialize = try await valueWithinOneSecond {
            try await transport.nextSentRequest()
        }
        XCTAssertEqual(reconnectInitialize.method, AppServerMethods.initialize)
        await transport.enqueue(
            .response(
                JSONRPCResponse(
                    id: reconnectInitialize.id,
                    result: initializeResult()
                )
            )
        )
        _ = try await transport.nextSentNotification()

        try await waitUntil {
            await client.state == .connected
        }
        let resumedConnectCount = await transport.connectCountSnapshot()
        XCTAssertEqual(resumedConnectCount, 2)
    }

    func testReconnectDoesNotOpenIfAppBackgroundsDuringBackoffSleep() async throws {
        let lifecycle = await MainActor.run {
            AppLifecycleCoordinator()
        }
        let transport = ScriptedAppServerTransport()
        let client = AppServerClient(
            transport: transport,
            connectionPolicy: AppServerConnectionPolicy(
                reconnect: AppServerReconnectPolicy(
                    maxAttempts: 1,
                    initialDelayMilliseconds: 200,
                    maxDelayMilliseconds: 200
                )
            ),
            foregroundWorkGate: lifecycle
        )
        try await completeHandshake(client: client, transport: transport)

        await transport.closeInbound()
        try await waitUntil {
            if case .reconnecting = await client.state {
                return true
            }
            return false
        }
        await MainActor.run {
            lifecycle.handle(.background)
        }
        try await Task.sleep(for: .milliseconds(250))

        let backgroundConnectCount = await transport.connectCountSnapshot()
        XCTAssertEqual(backgroundConnectCount, 1)

        await MainActor.run {
            lifecycle.handle(.active)
        }
        let reconnectInitialize = try await valueWithinOneSecond {
            try await transport.nextSentRequest()
        }
        XCTAssertEqual(reconnectInitialize.method, AppServerMethods.initialize)
        await transport.enqueue(
            .response(
                JSONRPCResponse(
                    id: reconnectInitialize.id,
                    result: initializeResult()
                )
            )
        )
        _ = try await transport.nextSentNotification()
        try await waitUntil {
            await client.state == .connected
        }
    }

    func testTransportFailureFailsInFlightRequestAndDoesNotReplayAfterReconnect() async throws {
        let transport = ScriptedAppServerTransport()
        let client = AppServerClient(
            transport: transport,
            connectionPolicy: AppServerConnectionPolicy(
                reconnect: AppServerReconnectPolicy(
                    maxAttempts: 1,
                    initialDelayMilliseconds: 0,
                    maxDelayMilliseconds: 0
                )
            )
        )
        try await completeHandshake(client: client, transport: transport)

        let task = Task {
            try await client.sendRequest(method: "turn/start", timeout: .seconds(1))
        }
        let request = try await transport.nextSentRequest()
        XCTAssertEqual(request.method, "turn/start")

        await transport.closeInbound()

        do {
            _ = try await task.value
            XCTFail("Expected in-flight request to fail on transport loss")
        } catch AppServerClientError.disconnected(let reason) {
            XCTAssertEqual(reason, "transport closed")
        } catch {
            XCTFail("Expected disconnected error, got \(error)")
        }

        let reconnectInitialize = try await valueWithinOneSecond {
            try await transport.nextSentRequest()
        }
        XCTAssertEqual(reconnectInitialize.method, AppServerMethods.initialize)
        await transport.enqueue(
            .response(
                JSONRPCResponse(
                    id: reconnectInitialize.id,
                    result: initializeResult()
                )
            )
        )
        _ = try await transport.nextSentNotification()

        try await waitUntil {
            await client.state == .connected
        }
        let sentMethods = await transport.sentMethodsSnapshot()
        XCTAssertEqual(sentMethods.filter { $0 == "turn/start" }.count, 1)
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

    func testWebSocketTransportUsesExplicitReceiveLimit() throws {
        let url = try XCTUnwrap(URL(string: "ws://192.0.2.1:4500"))
        let defaultTransport = URLSessionWebSocketAppServerTransport(url: url)
        let customTransport = URLSessionWebSocketAppServerTransport(
            url: url,
            maximumMessageSize: 16 * 1024 * 1024
        )

        XCTAssertEqual(
            defaultTransport.maximumMessageSize,
            URLSessionWebSocketAppServerTransport.defaultMaximumMessageSize
        )
        XCTAssertEqual(customTransport.maximumMessageSize, 16 * 1024 * 1024)
    }

    func testThreadListSendsTypedRequestAndDecodesResponse() async throws {
        let transport = ScriptedAppServerTransport()
        let client = AppServerClient(transport: transport)
        try await completeHandshake(client: client, transport: transport)

        let task = Task {
            try await client.threadList(
                params: ThreadListParams(
                    limit: 2,
                    sortKey: .updatedAt,
                    sortDirection: .desc
                ),
                timeout: .seconds(1)
            )
        }
        let request = try await transport.nextSentRequest()
        XCTAssertEqual(request.method, AppServerMethods.threadList)

        guard case .object(let params) = try XCTUnwrap(request.params) else {
            return XCTFail("Expected object params")
        }
        XCTAssertEqual(params["limit"], .integer(2))
        XCTAssertEqual(params["sortKey"], .string("updated_at"))
        XCTAssertEqual(params["sortDirection"], .string("desc"))

        await transport.enqueue(
            .response(
                JSONRPCResponse(
                    id: request.id,
                    result: try JSONValue.encoded(
                        ThreadListResponseDTO(
                            data: [
                                ThreadDTO(
                                    id: "thread-1",
                                    sessionId: "session-1",
                                    preview: "Build the Dock",
                                    createdAt: 1_790_000_000,
                                    updatedAt: 1_790_000_010,
                                    status: .idle,
                                    cwd: "/Users/aelaguiz/workspace/codex-client",
                                    source: .string("cli"),
                                    gitInfo: ThreadGitInfoDTO(branch: "main"),
                                    turns: []
                                ),
                            ],
                            nextCursor: nil,
                            backwardsCursor: "before-1",
                            liveOverlay: ThreadListLiveOverlayDTO(
                                ok: false,
                                state: "disabled",
                                ageMs: nil
                            )
                        )
                    )
                )
            )
        )

        let response = try await task.value
        XCTAssertEqual(response.data.map(\.id), ["thread-1"])
        XCTAssertEqual(response.data.first?.status, .idle)
        XCTAssertEqual(response.backwardsCursor, "before-1")
        XCTAssertEqual(response.liveOverlay?.degradedMessage, "Live status disabled")
    }

    func testAppServerDockClientLoadsCursorContinuationAndLiveOverlay() async throws {
        let transport = ScriptedAppServerTransport()
        let client = AppServerClient(transport: transport)
        try await completeHandshake(client: client, transport: transport)

        let dockClient = AppServerDockClient()
        let task = Task {
            try await dockClient.loadSessions(
                using: client,
                hostID: "Amir-M5",
                query: .activeHuman
            )
        }

        let firstRequest = try await transport.nextSentRequest()
        XCTAssertEqual(firstRequest.method, AppServerMethods.threadList)
        guard case .object(let firstParams) = try XCTUnwrap(firstRequest.params) else {
            return XCTFail("Expected first thread/list params")
        }
        XCTAssertEqual(firstParams["limit"], .integer(100))
        XCTAssertEqual(firstParams["cursor"], nil)

        await transport.enqueue(
            .response(
                JSONRPCResponse(
                    id: firstRequest.id,
                    result: try JSONValue.encoded(
                        ThreadListResponseDTO(
                            data: [
                                threadListRow(id: "thread-1", updatedAt: 1_790_000_001),
                            ],
                            nextCursor: "cursor-1",
                            backwardsCursor: "before-1",
                            liveOverlay: ThreadListLiveOverlayDTO(ok: false, state: "disabled")
                        )
                    )
                )
            )
        )

        let secondRequest = try await transport.nextSentRequest()
        XCTAssertEqual(secondRequest.method, AppServerMethods.threadList)
        guard case .object(let secondParams) = try XCTUnwrap(secondRequest.params) else {
            return XCTFail("Expected second thread/list params")
        }
        XCTAssertEqual(secondParams["limit"], .integer(100))
        XCTAssertEqual(secondParams["cursor"], .string("cursor-1"))

        await transport.enqueue(
            .response(
                JSONRPCResponse(
                    id: secondRequest.id,
                    result: try JSONValue.encoded(
                        ThreadListResponseDTO(
                            data: [
                                threadListRow(id: "thread-2", updatedAt: 1_790_000_000),
                            ],
                            nextCursor: nil,
                            backwardsCursor: nil,
                            liveOverlay: ThreadListLiveOverlayDTO(ok: true, state: "ready")
                        )
                    )
                )
            )
        )

        let result = try await task.value
        XCTAssertEqual(result.summaries.map(\.id.threadID), ["thread-1", "thread-2"])
        XCTAssertEqual(result.nextCursor, nil)
        XCTAssertEqual(result.backwardsCursor, "before-1")
        XCTAssertEqual(result.liveOverlay, ThreadListLiveOverlayDTO(ok: true, state: "ready"))
        await client.disconnect()
    }

    func testAppServerDockClientUsesBoundedPageLimitForAgents() async throws {
        let transport = ScriptedAppServerTransport()
        let client = AppServerClient(transport: transport)
        try await completeHandshake(client: client, transport: transport)

        let dockClient = AppServerDockClient()
        let task = Task {
            try await dockClient.loadSessions(
                using: client,
                hostID: "Amir-M5",
                query: .activeAgents
            )
        }

        let request = try await transport.nextSentRequest()
        XCTAssertEqual(request.method, AppServerMethods.threadList)
        guard case .object(let params) = try XCTUnwrap(request.params) else {
            return XCTFail("Expected thread/list params")
        }
        XCTAssertEqual(params["limit"], .integer(50))
        XCTAssertEqual(
            params["sourceKinds"],
            .array(
                ThreadSourceKind.dockAgentScopeKinds.map { .string($0.rawValue) }
            )
        )

        await transport.enqueue(
            .response(
                JSONRPCResponse(
                    id: request.id,
                    result: try JSONValue.encoded(ThreadListResponseDTO(data: []))
                )
            )
        )

        let result = try await task.value
        XCTAssertEqual(result.summaries, [])
        await client.disconnect()
    }

    func testThreadListEncodesSourceKinds() async throws {
        let transport = ScriptedAppServerTransport()
        let client = AppServerClient(transport: transport)
        try await completeHandshake(client: client, transport: transport)

        let task = Task {
            try await client.threadList(
                params: ThreadListParams(
                    sourceKinds: [
                        .exec,
                        .appServer,
                        .subAgentReview,
                        .unknown
                    ],
                    archived: false
                ),
                timeout: .seconds(1)
            )
        }
        let request = try await transport.nextSentRequest()
        XCTAssertEqual(request.method, AppServerMethods.threadList)

        guard case .object(let params) = try XCTUnwrap(request.params) else {
            return XCTFail("Expected object params")
        }
        XCTAssertEqual(
            params["sourceKinds"],
            .array([
                .string("exec"),
                .string("appServer"),
                .string("subAgentReview"),
                .string("unknown")
            ])
        )
        XCTAssertEqual(params["archived"], .bool(false))

        await transport.enqueue(
            .response(
                JSONRPCResponse(
                    id: request.id,
                    result: try JSONValue.encoded(ThreadListResponseDTO(data: []))
                )
            )
        )

        let response = try await task.value
        XCTAssertEqual(response.data, [])
    }

    func testThreadListMethodFailureSurfacesServerError() async throws {
        let transport = ScriptedAppServerTransport()
        let client = AppServerClient(transport: transport)
        try await completeHandshake(client: client, transport: transport)

        let task = Task {
            try await client.threadList(timeout: .seconds(1))
        }
        let request = try await transport.nextSentRequest()
        XCTAssertEqual(request.method, AppServerMethods.threadList)

        await transport.enqueue(
            .error(
                JSONRPCErrorResponse(
                    error: JSONRPCErrorObject(
                        code: -32602,
                        message: "invalid thread/list params"
                    ),
                    id: request.id
                )
            )
        )

        do {
            _ = try await task.value
            XCTFail("Expected server error")
        } catch AppServerClientError.server(let error) {
            XCTAssertEqual(error.code, -32602)
            XCTAssertEqual(error.message, "invalid thread/list params")
        } catch {
            XCTFail("Expected server error, got \(error)")
        }
    }

    func testThreadReadAndResumeSendTypedRequests() async throws {
        let transport = ScriptedAppServerTransport()
        let client = AppServerClient(transport: transport)
        try await completeHandshake(client: client, transport: transport)

        let readTask = Task {
            try await client.threadRead(
                params: ThreadReadParams(threadId: "thread-1", includeTurns: true),
                timeout: .seconds(1)
            )
        }
        let readRequest = try await transport.nextSentRequest()
        XCTAssertEqual(readRequest.method, AppServerMethods.threadRead)
        guard case .object(let readParams) = try XCTUnwrap(readRequest.params) else {
            return XCTFail("Expected object params")
        }
        XCTAssertEqual(readParams["threadId"], .string("thread-1"))
        XCTAssertEqual(readParams["includeTurns"], .bool(true))

        await transport.enqueue(
            .response(
                JSONRPCResponse(
                    id: readRequest.id,
                    result: try JSONValue.encoded(
                        ThreadReadResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))
                    )
                )
            )
        )

        let readResponse = try await readTask.value
        XCTAssertEqual(readResponse.thread.id, "thread-1")

        let turnsListTask = Task {
            try await client.threadTurnsList(
                params: ThreadTurnsListParams(threadId: "thread-1", limit: 10),
                timeout: .seconds(1)
            )
        }
        let turnsListRequest = try await transport.nextSentRequest()
        XCTAssertEqual(turnsListRequest.method, AppServerMethods.threadTurnsList)
        guard case .object(let turnsListParams) = try XCTUnwrap(turnsListRequest.params) else {
            return XCTFail("Expected object params")
        }
        XCTAssertEqual(turnsListParams["threadId"], .string("thread-1"))
        XCTAssertEqual(turnsListParams["limit"], .integer(10))

        await transport.enqueue(
            .response(
                JSONRPCResponse(
                    id: turnsListRequest.id,
                    result: try JSONValue.encoded(
                        ThreadTurnsListResponseDTO(data: [])
                    )
                )
            )
        )

        let turnsListResponse = try await turnsListTask.value
        XCTAssertEqual(turnsListResponse.data, [])

        let resumeTask = Task {
            try await client.threadResume(
                params: ThreadResumeParams(threadId: "thread-1", excludeTurns: true),
                timeout: .seconds(1)
            )
        }
        let resumeRequest = try await transport.nextSentRequest()
        XCTAssertEqual(resumeRequest.method, AppServerMethods.threadResume)
        guard case .object(let resumeParams) = try XCTUnwrap(resumeRequest.params) else {
            return XCTFail("Expected object params")
        }
        XCTAssertEqual(resumeParams["threadId"], .string("thread-1"))
        XCTAssertEqual(resumeParams["excludeTurns"], .bool(true))

        await transport.enqueue(
            .response(
                JSONRPCResponse(
                    id: resumeRequest.id,
                    result: try JSONValue.encoded(
                        ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))
                    )
                )
            )
        )

        let resumeResponse = try await resumeTask.value
        XCTAssertEqual(resumeResponse.thread.id, "thread-1")
    }

    func testThreadArchiveAndUnarchiveSendTypedRequests() async throws {
        let transport = ScriptedAppServerTransport()
        let client = AppServerClient(transport: transport)
        try await completeHandshake(client: client, transport: transport)

        let archiveTask = Task {
            try await client.threadArchive(
                params: ThreadArchiveParams(threadId: "thread-1"),
                timeout: .seconds(1)
            )
        }
        let archiveRequest = try await transport.nextSentRequest()
        XCTAssertEqual(archiveRequest.method, AppServerMethods.threadArchive)
        guard case .object(let archiveParams) = try XCTUnwrap(archiveRequest.params) else {
            return XCTFail("Expected object params")
        }
        XCTAssertEqual(archiveParams["threadId"], .string("thread-1"))

        await transport.enqueue(
            .response(
                JSONRPCResponse(
                    id: archiveRequest.id,
                    result: try JSONValue.encoded(ThreadArchiveResponseDTO())
                )
            )
        )
        _ = try await archiveTask.value

        let unarchiveTask = Task {
            try await client.threadUnarchive(
                params: ThreadUnarchiveParams(threadId: "thread-1"),
                timeout: .seconds(1)
            )
        }
        let unarchiveRequest = try await transport.nextSentRequest()
        XCTAssertEqual(unarchiveRequest.method, AppServerMethods.threadUnarchive)
        guard case .object(let unarchiveParams) = try XCTUnwrap(unarchiveRequest.params) else {
            return XCTFail("Expected object params")
        }
        XCTAssertEqual(unarchiveParams["threadId"], .string("thread-1"))

        await transport.enqueue(
            .response(
                JSONRPCResponse(
                    id: unarchiveRequest.id,
                    result: try JSONValue.encoded(
                        ThreadUnarchiveResponseDTO(
                            thread: ThreadDTO(id: "thread-1", sessionId: "session-1", turns: [])
                        )
                    )
                )
            )
        )

        let unarchiveResponse = try await unarchiveTask.value
        XCTAssertEqual(unarchiveResponse.thread.id, "thread-1")
    }

    func testServerRequestStreamReceivesRequestsWithoutFailingConnection() async throws {
        let transport = ScriptedAppServerTransport()
        let client = AppServerClient(transport: transport)
        try await completeHandshake(client: client, transport: transport)

        let requestTask = Task {
            var iterator = client.serverRequests.makeAsyncIterator()
            return await iterator.next()
        }

        await transport.enqueue(
            .request(
                JSONRPCRequest(
                    id: .string("approval-1"),
                    method: "item/commandExecution/requestApproval",
                    params: .object([
                        "threadId": .string("thread-1"),
                        "command": .array([.string("make"), .string("test")]),
                    ])
                )
            )
        )

        let request = try await valueWithinOneSecond {
            await requestTask.value
        }
        XCTAssertEqual(request?.id, .string("approval-1"))
        XCTAssertEqual(request?.method, "item/commandExecution/requestApproval")
        let state = await client.state
        XCTAssertEqual(state, .connected)
    }

    func testTurnStartAndSteerSendTypedTextInput() async throws {
        let transport = ScriptedAppServerTransport()
        let client = AppServerClient(transport: transport)
        try await completeHandshake(client: client, transport: transport)

        let startTask = Task {
            try await client.turnStart(
                params: .text(threadId: "thread-1", text: "Do the thing"),
                timeout: .seconds(1)
            )
        }
        let startRequest = try await transport.nextSentRequest()
        XCTAssertEqual(startRequest.method, AppServerMethods.turnStart)
        guard case .object(let startParams) = try XCTUnwrap(startRequest.params),
              case .array(let startInput) = try XCTUnwrap(startParams["input"]),
              case .object(let textInput) = try XCTUnwrap(startInput.first) else {
            return XCTFail("Expected turn/start text input params")
        }
        XCTAssertEqual(startParams["threadId"], .string("thread-1"))
        XCTAssertEqual(textInput["type"], .string("text"))
        XCTAssertEqual(textInput["text"], .string("Do the thing"))
        XCTAssertEqual(textInput["text_elements"], .array([]))

        await transport.enqueue(
            .response(
                JSONRPCResponse(
                    id: startRequest.id,
                    result: .object([
                        "turn": .object([
                            "id": .string("turn-1"),
                            "status": .string("inProgress"),
                        ]),
                    ])
                )
            )
        )
        let startResponse = try await startTask.value
        XCTAssertEqual(startResponse.turn.objectValue?["id"], .string("turn-1"))

        let steerTask = Task {
            try await client.turnSteer(
                params: .text(
                    threadId: "thread-1",
                    text: "Add this too",
                    expectedTurnId: "turn-1"
                ),
                timeout: .seconds(1)
            )
        }
        let steerRequest = try await transport.nextSentRequest()
        XCTAssertEqual(steerRequest.method, AppServerMethods.turnSteer)
        guard case .object(let steerParams) = try XCTUnwrap(steerRequest.params) else {
            return XCTFail("Expected turn/steer params")
        }
        XCTAssertEqual(steerParams["threadId"], .string("thread-1"))
        XCTAssertEqual(steerParams["expectedTurnId"], .string("turn-1"))

        await transport.enqueue(
            .response(
                JSONRPCResponse(
                    id: steerRequest.id,
                    result: .object(["turnId": .string("turn-1")])
                )
            )
        )
        let steerResponse = try await steerTask.value
        XCTAssertEqual(steerResponse.turnId, "turn-1")
    }

    func testRealtimeTranscriptionMethodsSendTypedRequestsWithoutProviderConfig() async throws {
        let transport = ScriptedAppServerTransport()
        let client = AppServerClient(transport: transport)
        try await completeHandshake(client: client, transport: transport)

        let startTask = Task {
            try await client.audioTranscriptionStart(
                params: AudioTranscriptionStartParams(language: "en", delay: "low"),
                timeout: .seconds(1)
            )
        }
        let startRequest = try await transport.nextSentRequest()
        XCTAssertEqual(startRequest.method, AppServerMethods.audioTranscriptionStart)
        guard case .object(let startParams) = try XCTUnwrap(startRequest.params) else {
            return XCTFail("Expected audio/transcription/start params")
        }
        XCTAssertEqual(startParams["language"], .string("en"))
        XCTAssertEqual(startParams["delay"], .string("low"))
        XCTAssertNil(startParams["model"])
        XCTAssertNil(startParams["endpoint"])
        XCTAssertNil(startParams["headers"])
        XCTAssertNil(startParams["apiKey"])
        await transport.enqueue(
            .response(
                JSONRPCResponse(
                    id: startRequest.id,
                    result: try JSONValue.encoded(
                        AudioTranscriptionStartResponseDTO(
                            sessionId: "transcription-1",
                            format: "audio/pcm",
                            sampleRate: 24_000,
                            model: "gpt-realtime-whisper",
                            language: "en",
                            delay: "low"
                        )
                    )
                )
            )
        )
        let startResponse = try await startTask.value
        XCTAssertEqual(startResponse.sessionId, "transcription-1")

        let appendTask = Task {
            try await client.audioTranscriptionAppend(
                params: AudioTranscriptionAppendParams(
                    sessionId: "transcription-1",
                    sequence: 1,
                    base64Audio: "AQID"
                ),
                timeout: .seconds(1)
            )
        }
        let appendRequest = try await transport.nextSentRequest()
        XCTAssertEqual(appendRequest.method, AppServerMethods.audioTranscriptionAppend)
        guard case .object(let appendParams) = try XCTUnwrap(appendRequest.params) else {
            return XCTFail("Expected audio/transcription/append params")
        }
        XCTAssertEqual(appendParams["sessionId"], .string("transcription-1"))
        XCTAssertEqual(appendParams["sequence"], .integer(1))
        XCTAssertEqual(appendParams["base64Audio"], .string("AQID"))
        XCTAssertNil(appendParams["model"])
        XCTAssertNil(appendParams["endpoint"])
        XCTAssertNil(appendParams["headers"])
        XCTAssertNil(appendParams["apiKey"])
        await transport.enqueue(
            .response(
                JSONRPCResponse(
                    id: appendRequest.id,
                    result: try JSONValue.encoded(
                        AudioTranscriptionAppendResponseDTO(
                            sessionId: "transcription-1",
                            acceptedSequence: 1
                        )
                    )
                )
            )
        )
        _ = try await appendTask.value

        let commitTask = Task {
            try await client.audioTranscriptionCommit(
                params: AudioTranscriptionCommitParams(sessionId: "transcription-1"),
                timeout: .seconds(1)
            )
        }
        let commitRequest = try await transport.nextSentRequest()
        XCTAssertEqual(commitRequest.method, AppServerMethods.audioTranscriptionCommit)
        await transport.enqueue(
            .response(
                JSONRPCResponse(
                    id: commitRequest.id,
                    result: try JSONValue.encoded(
                        AudioTranscriptionCommitResponseDTO(
                            sessionId: "transcription-1",
                            committed: true
                        )
                    )
                )
            )
        )
        _ = try await commitTask.value

        let cancelTask = Task {
            try await client.audioTranscriptionCancel(
                params: AudioTranscriptionCancelParams(sessionId: "transcription-1"),
                timeout: .seconds(1)
            )
        }
        let cancelRequest = try await transport.nextSentRequest()
        XCTAssertEqual(cancelRequest.method, AppServerMethods.audioTranscriptionCancel)
        await transport.enqueue(
            .response(
                JSONRPCResponse(
                    id: cancelRequest.id,
                    result: try JSONValue.encoded(
                        AudioTranscriptionCancelResponseDTO(
                            sessionId: "transcription-1",
                            canceled: true
                        )
                    )
                )
            )
        )
        _ = try await cancelTask.value
    }

    @MainActor
    func testThreadDetailSessionFactoryFallsBackAcrossRelayEndpoints() async throws {
        let primary = try DockRelayEndpoint(host: "127.0.0.1", port: 4511)
        let fallback = try DockRelayEndpoint(host: "127.0.0.1", port: 4512)
        let host = try DockHostConfiguration(
            endpoints: [primary, fallback],
            relayInstanceID: "Amir-M5"
        )
        let primaryTransport = ScriptedAppServerTransport(connectError: TestTransportError.offline)
        let fallbackTransport = ScriptedAppServerTransport()
        let clientFactory = EndpointRecordingClientFactory(clients: [
            primary.id: AppServerClient(transport: primaryTransport),
            fallback.id: AppServerClient(transport: fallbackTransport),
        ])
        let session = AppServerThreadDetailSessionFactory { endpoint in
            clientFactory.client(for: endpoint)
        }.makeSession(for: host)

        let connectTask = Task {
            try await session.connectAndInitialize(
                params: .codexDock(version: "0.1.0"),
                timeout: .seconds(1)
            )
        }
        try await respondToInitialize(transport: fallbackTransport, relayInstanceID: "Amir-M5")
        let initialize = try await connectTask.value

        XCTAssertEqual(initialize.relayInstanceID, "Amir-M5")
        XCTAssertEqual(clientFactory.endpointIDsSnapshot(), [primary.id, fallback.id])
        let primaryConnectCount = await primaryTransport.connectCountSnapshot()
        let primaryDisconnectCount = await primaryTransport.disconnectCountSnapshot()
        let fallbackConnectCount = await fallbackTransport.connectCountSnapshot()
        XCTAssertEqual(primaryConnectCount, 1)
        XCTAssertEqual(primaryDisconnectCount, 1)
        XCTAssertEqual(fallbackConnectCount, 1)
        await session.disconnect()
        let fallbackDisconnectCount = await fallbackTransport.disconnectCountSnapshot()
        XCTAssertEqual(fallbackDisconnectCount, 1)
    }

    @MainActor
    func testRelayRealtimeTranscriptionClientFallsBackAcrossRelayEndpoints() async throws {
        let primary = try DockRelayEndpoint(host: "127.0.0.1", port: 4511)
        let fallback = try DockRelayEndpoint(host: "127.0.0.1", port: 4512)
        let host = try DockHostConfiguration(
            endpoints: [primary, fallback],
            relayInstanceID: "Amir-M5"
        )
        let primaryTransport = ScriptedAppServerTransport(connectError: TestTransportError.offline)
        let fallbackTransport = ScriptedAppServerTransport()
        let clientFactory = EndpointRecordingClientFactory(clients: [
            primary.id: AppServerClient(transport: primaryTransport),
            fallback.id: AppServerClient(transport: fallbackTransport),
        ])
        let service = RelayRealtimeTranscriptionClient(host: host) { endpoint in
            clientFactory.client(for: endpoint)
        }

        let startTask = Task {
            try await service.startSession()
        }
        try await respondToInitialize(transport: fallbackTransport, relayInstanceID: "Amir-M5")
        let startRequest = try await fallbackTransport.nextSentRequest()
        XCTAssertEqual(startRequest.method, AppServerMethods.audioTranscriptionStart)
        await fallbackTransport.enqueue(
            .response(
                JSONRPCResponse(
                    id: startRequest.id,
                    result: try JSONValue.encoded(
                        AudioTranscriptionStartResponseDTO(
                            sessionId: "transcription-fallback",
                            format: "audio/pcm",
                            sampleRate: 24_000,
                            model: "gpt-realtime-whisper"
                        )
                    )
                )
            )
        )
        let session = try await startTask.value

        XCTAssertEqual(clientFactory.endpointIDsSnapshot(), [primary.id, fallback.id])
        let primaryConnectCount = await primaryTransport.connectCountSnapshot()
        let primaryDisconnectCount = await primaryTransport.disconnectCountSnapshot()
        let fallbackConnectCount = await fallbackTransport.connectCountSnapshot()
        XCTAssertEqual(primaryConnectCount, 1)
        XCTAssertEqual(primaryDisconnectCount, 1)
        XCTAssertEqual(fallbackConnectCount, 1)

        let cancelTask = Task {
            await session.cancel()
        }
        let cancelRequest = try await fallbackTransport.nextSentRequest()
        XCTAssertEqual(cancelRequest.method, AppServerMethods.audioTranscriptionCancel)
        await fallbackTransport.enqueue(
            .response(
                JSONRPCResponse(
                    id: cancelRequest.id,
                    result: try JSONValue.encoded(
                        AudioTranscriptionCancelResponseDTO(
                            sessionId: "transcription-fallback",
                            canceled: true
                        )
                    )
                )
            )
        )
        await cancelTask.value
        let fallbackDisconnectCount = await fallbackTransport.disconnectCountSnapshot()
        XCTAssertEqual(fallbackDisconnectCount, 1)
    }

    @MainActor
    func testRelayRealtimeTranscriptionClientMapsRelayNotificationsAndClosesConnection() async throws {
        let transport = ScriptedAppServerTransport()
        let appServerClient = AppServerClient(transport: transport)
        let host = makeRealtimeRelayHost()
        let service = RelayRealtimeTranscriptionClient(host: host) { _ in
            appServerClient
        }

        let startTask = Task {
            try await service.startSession()
        }
        try await respondToInitialize(transport: transport)
        let startRequest = try await transport.nextSentRequest()
        XCTAssertEqual(startRequest.method, AppServerMethods.audioTranscriptionStart)
        await transport.enqueue(
            .response(
                JSONRPCResponse(
                    id: startRequest.id,
                    result: try JSONValue.encoded(
                        AudioTranscriptionStartResponseDTO(
                            sessionId: "transcription-1",
                            format: "audio/pcm",
                            sampleRate: 24_000,
                            model: "gpt-realtime-whisper"
                        )
                    )
                )
            )
        )
        let session = try await startTask.value
        let events = RealtimeEventProbe(session.events)
        let startedEvent = await events.next()
        XCTAssertEqual(startedEvent, .some(.started(sessionID: "transcription-1")))

        let appendTask = Task {
            try await session.appendAudio(Data([1, 2, 3]), sequence: 1)
        }
        let appendRequest = try await transport.nextSentRequest()
        XCTAssertEqual(appendRequest.method, AppServerMethods.audioTranscriptionAppend)
        guard case .object(let appendParams) = try XCTUnwrap(appendRequest.params) else {
            return XCTFail("Expected audio/transcription/append params")
        }
        XCTAssertEqual(appendParams["sessionId"], .string("transcription-1"))
        XCTAssertEqual(appendParams["sequence"], .integer(1))
        XCTAssertEqual(appendParams["base64Audio"], .string(Data([1, 2, 3]).base64EncodedString()))
        await transport.enqueue(
            .response(
                JSONRPCResponse(
                    id: appendRequest.id,
                    result: try JSONValue.encoded(
                        AudioTranscriptionAppendResponseDTO(
                            sessionId: "transcription-1",
                            acceptedSequence: 1
                        )
                    )
                )
            )
        )
        try await appendTask.value

        await transport.enqueue(
            .notification(
                JSONRPCNotification(
                    method: AppServerMethods.audioTranscriptionDelta,
                    params: try JSONValue.encoded(
                        AudioTranscriptionDeltaNotificationDTO(
                            sessionId: "other-session",
                            itemId: "item-1",
                            contentIndex: 0,
                            deltaText: "wrong",
                            partialText: "wrong"
                        )
                    )
                )
            )
        )
        try await Task.sleep(for: .milliseconds(20))
        let ignoredEventCount = await events.bufferedCount()
        XCTAssertEqual(ignoredEventCount, 0)

        await transport.enqueue(
            .notification(
                JSONRPCNotification(
                    method: AppServerMethods.audioTranscriptionDelta,
                    params: try JSONValue.encoded(
                        AudioTranscriptionDeltaNotificationDTO(
                            sessionId: "transcription-1",
                            itemId: "item-1",
                            contentIndex: 0,
                            deltaText: "Check",
                            partialText: "Check"
                        )
                    )
                )
            )
        )
        let deltaEvent = try await valueWithinOneSecond {
            await events.next()
        }
        XCTAssertEqual(
            deltaEvent,
            .some(.delta(
                sessionID: "transcription-1",
                itemID: "item-1",
                sequence: 0,
                deltaText: "Check",
                partialText: "Check"
            ))
        )

        let commitTask = Task {
            try await session.commit()
        }
        let commitRequest = try await transport.nextSentRequest()
        XCTAssertEqual(commitRequest.method, AppServerMethods.audioTranscriptionCommit)
        await transport.enqueue(
            .response(
                JSONRPCResponse(
                    id: commitRequest.id,
                    result: try JSONValue.encoded(
                        AudioTranscriptionCommitResponseDTO(
                            sessionId: "transcription-1",
                            committed: true
                        )
                    )
                )
            )
        )
        try await commitTask.value

        await transport.enqueue(
            .notification(
                JSONRPCNotification(
                    method: AppServerMethods.audioTranscriptionCompleted,
                    params: try JSONValue.encoded(
                        AudioTranscriptionCompletedNotificationDTO(
                            sessionId: "transcription-1",
                            itemId: "item-1",
                            contentIndex: 0,
                            transcript: "Check relay"
                        )
                    )
                )
            )
        )
        let completedEvent = try await valueWithinOneSecond {
            await events.next()
        }
        XCTAssertEqual(
            completedEvent,
            .some(.completed(sessionID: "transcription-1", itemID: "item-1", text: "Check relay"))
        )
        try await waitUntil {
            await transport.disconnectCountSnapshot() >= 1
        }
    }

    @MainActor
    func testRelayRealtimeTranscriptionClientRejectsInvalidChunksBeforeSending() async throws {
        let transport = ScriptedAppServerTransport()
        let appServerClient = AppServerClient(transport: transport)
        let host = makeRealtimeRelayHost()
        let service = RelayRealtimeTranscriptionClient(
            host: host,
            maxChunkBytes: 3
        ) { _ in
            appServerClient
        }

        let session = try await startRealtimeSession(service: service, transport: transport)

        do {
            try await session.appendAudio(Data(), sequence: 1)
            XCTFail("Expected empty chunk rejection")
        } catch RelayRealtimeTranscriptionClientError.emptyAudioChunk {
            // Expected.
        } catch {
            XCTFail("Expected empty chunk rejection, got \(error)")
        }

        do {
            try await session.appendAudio(Data([1, 2, 3, 4]), sequence: 1)
            XCTFail("Expected oversized chunk rejection")
        } catch RelayRealtimeTranscriptionClientError.audioChunkTooLarge(maxBytes: 3) {
            // Expected.
        } catch {
            XCTFail("Expected oversized chunk rejection, got \(error)")
        }

        let sentMethods = await transport.sentMethodsSnapshot()
        XCTAssertEqual(
            sentMethods.filter { $0 == AppServerMethods.audioTranscriptionAppend }.count,
            0
        )
    }

    @MainActor
    func testRelayRealtimeTranscriptionClientCommitTimeoutFailsAndCloses() async throws {
        let transport = ScriptedAppServerTransport()
        let appServerClient = AppServerClient(transport: transport)
        let host = makeRealtimeRelayHost()
        let service = RelayRealtimeTranscriptionClient(
            host: host,
            completionTimeout: .milliseconds(50)
        ) { _ in
            appServerClient
        }

        let session = try await startRealtimeSession(service: service, transport: transport)
        let events = RealtimeEventProbe(session.events)
        let startedEvent = await events.next()
        XCTAssertEqual(startedEvent, .some(.started(sessionID: "transcription-1")))

        let commitTask = Task {
            try await session.commit()
        }
        let commitRequest = try await transport.nextSentRequest()
        XCTAssertEqual(commitRequest.method, AppServerMethods.audioTranscriptionCommit)
        await transport.enqueue(
            .response(
                JSONRPCResponse(
                    id: commitRequest.id,
                    result: try JSONValue.encoded(
                        AudioTranscriptionCommitResponseDTO(
                            sessionId: "transcription-1",
                            committed: true
                        )
                    )
                )
            )
        )
        try await commitTask.value

        let failedEvent = try await valueWithinOneSecond {
            await events.next()
        }
        XCTAssertEqual(
            failedEvent,
            .some(.failed(
                sessionID: "transcription-1",
                code: "commit_timeout",
                message: "Realtime transcription timed out."
            ))
        )
        try await waitUntil {
            await transport.disconnectCountSnapshot() >= 1
        }
    }

    @MainActor
    func testRelayRealtimeTranscriptionClientCancelSendsTypedRequestAndCloses() async throws {
        let transport = ScriptedAppServerTransport()
        let appServerClient = AppServerClient(transport: transport)
        let host = makeRealtimeRelayHost()
        let service = RelayRealtimeTranscriptionClient(host: host) { _ in
            appServerClient
        }

        let session = try await startRealtimeSession(service: service, transport: transport)
        let events = RealtimeEventProbe(session.events)
        let startedEvent = await events.next()
        XCTAssertEqual(startedEvent, .some(.started(sessionID: "transcription-1")))

        let cancelTask = Task {
            await session.cancel()
        }
        let cancelRequest = try await transport.nextSentRequest()
        XCTAssertEqual(cancelRequest.method, AppServerMethods.audioTranscriptionCancel)
        await transport.enqueue(
            .response(
                JSONRPCResponse(
                    id: cancelRequest.id,
                    result: try JSONValue.encoded(
                        AudioTranscriptionCancelResponseDTO(
                            sessionId: "transcription-1",
                            canceled: true
                        )
                    )
                )
            )
        )
        await cancelTask.value

        let canceledEvent = try await valueWithinOneSecond {
            await events.next()
        }
        XCTAssertEqual(
            canceledEvent,
            .some(.canceled(sessionID: "transcription-1"))
        )
        try await waitUntil {
            await transport.disconnectCountSnapshot() >= 1
        }
    }

    func testSendResponseSendsJsonRPCResponseForServerRequestID() async throws {
        let transport = ScriptedAppServerTransport()
        let client = AppServerClient(transport: transport)
        try await completeHandshake(client: client, transport: transport)

        try await client.sendResponse(
            id: .string("approval-1"),
            result: .object(["decision": .string("accept")])
        )

        let response = try await transport.nextSentResponse()
        XCTAssertEqual(response.id, .string("approval-1"))
        XCTAssertEqual(response.result, .object(["decision": .string("accept")]))
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
        let url = try configuredRelayURL(from: environment, label: "phone-reachable handshake")
        try await assertRealHostHandshakeSucceeds(
            url: url,
            bearerToken: nil,
            timeout: .seconds(5)
        )
    }

    func testPhoneReachableRealHostThreadListWhenEndpointIsProvided() async throws {
        let environment = ProcessInfo.processInfo.environment
        let url = try configuredRelayURL(from: environment, label: "phone-reachable thread/list")
        let client = AppServerClient(webSocketURL: url, bearerToken: nil)
        _ = try await client.connectAndInitialize(
            params: .codexDock(version: "0.1.0"),
            timeout: .seconds(5)
        )
        let response = try await client.threadList(
            params: ThreadListParams(limit: 5, sortKey: .updatedAt, sortDirection: .desc),
            timeout: .seconds(5)
        )
        let hostID = environment["CODEX_DOCK_REAL_HOST_ID"] ?? url.host ?? "real-host"
        let mapping = SessionSummaryMapper.map(response: response, hostID: hostID)

        XCTAssertLessThanOrEqual(response.data.count, 5)
        for thread in response.data {
            XCTAssertFalse(thread.id?.isEmpty ?? true)
            XCTAssertFalse(thread.sessionId?.isEmpty ?? true)
        }
        XCTAssertEqual(mapping.failures, [])
        XCTAssertEqual(mapping.summaries.count, response.data.count)
        for summary in mapping.summaries {
            XCTAssertEqual(summary.id.hostID, hostID)
        }
        await client.disconnect()
    }

    func testPhoneReachableRealHostThreadReadAndResumeWhenEndpointIsProvided() async throws {
        let environment = ProcessInfo.processInfo.environment
        let url = try configuredRelayURL(from: environment, label: "phone-reachable thread detail")
        let client = AppServerClient(webSocketURL: url, bearerToken: nil)
        _ = try await client.connectAndInitialize(
            params: .codexDock(version: "0.1.0"),
            timeout: .seconds(5)
        )
        let list = try await client.threadList(
            params: ThreadListParams(limit: 50, sortKey: .updatedAt, sortDirection: .desc),
            timeout: .seconds(10)
        )
        let thread = try XCTUnwrap(
            list.data.first(where: canOpenThreadDetail),
            "Real-host detail smoke test requires at least one loaded thread"
        )
        let threadID = try XCTUnwrap(thread.id)

        let read = try await client.threadRead(
            params: ThreadReadParams(threadId: threadID, includeTurns: false),
            timeout: .seconds(10)
        )
        let turns = try await client.threadTurnsList(
            params: ThreadTurnsListParams(threadId: threadID, limit: 10),
            timeout: .seconds(10)
        )
        let resumed = try await client.threadResume(
            params: ThreadResumeParams(threadId: threadID, excludeTurns: true),
            timeout: .seconds(10)
        )

        XCTAssertEqual(read.thread.id, threadID)
        XCTAssertEqual(resumed.thread.id, threadID)
        XCTAssertNotNil(read.thread.turns)
        XCTAssertNotNil(resumed.thread.turns)
        XCTAssertLessThanOrEqual(turns.data.count, 10)
        await client.disconnect()
    }

    func testPhoneReachableRealHostArchiveUnarchiveRoundTripWhenExplicitlyEnabled() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["CODEX_DOCK_RUN_ARCHIVE_ROUND_TRIP"] == "1" else {
            throw XCTSkip(
                "Set CODEX_DOCK_RUN_ARCHIVE_ROUND_TRIP=1 to run the reversible real-host archive smoke test"
            )
        }
        let url = try configuredRelayURL(from: environment, label: "phone-reachable archive")
        let client = AppServerClient(webSocketURL: url, bearerToken: nil)
        _ = try await client.connectAndInitialize(
            params: .codexDock(version: "0.1.0"),
            timeout: .seconds(5)
        )
        var archivedThreadID: String?

        do {
            let list = try await client.threadList(
                params: ThreadListParams(
                    limit: 100,
                    sortKey: .updatedAt,
                    sortDirection: .desc,
                    archived: false
                ),
                timeout: .seconds(10)
            )
            let thread = try XCTUnwrap(
                list.data.first { thread in
                    thread.status == .notLoaded && thread.id?.isEmpty == false
                },
                "Real-host archive smoke test requires one notLoaded thread"
            )
            let threadID = try XCTUnwrap(thread.id)

            _ = try await client.threadArchive(
                params: ThreadArchiveParams(threadId: threadID),
                timeout: .seconds(10)
            )
            archivedThreadID = threadID

            let archived = try await client.threadList(
                params: ThreadListParams(
                    limit: 100,
                    sortKey: .updatedAt,
                    sortDirection: .desc,
                    archived: true
                ),
                timeout: .seconds(10)
            )
            XCTAssertTrue(
                archived.data.contains { $0.id == threadID },
                "Archived list should include \(threadID) after thread/archive"
            )

            let restored = try await client.threadUnarchive(
                params: ThreadUnarchiveParams(threadId: threadID),
                timeout: .seconds(10)
            )
            archivedThreadID = nil
            XCTAssertEqual(restored.thread.id, threadID)

            let unarchived = try await client.threadList(
                params: ThreadListParams(
                    limit: 100,
                    sortKey: .updatedAt,
                    sortDirection: .desc,
                    archived: false
                ),
                timeout: .seconds(10)
            )
            XCTAssertTrue(
                unarchived.data.contains { $0.id == threadID },
                "Default list should include \(threadID) after thread/unarchive"
            )
        } catch {
            if let archivedThreadID {
                _ = try? await client.threadUnarchive(
                    params: ThreadUnarchiveParams(threadId: archivedThreadID),
                    timeout: .seconds(10)
                )
            }
            await client.disconnect()
            throw error
        }

        await client.disconnect()
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
    if let token = environment["CODEX_DOCK_TEST_APP_SERVER_BEARER_TOKEN"], !token.isEmpty {
        return token
    }

    let tokenFile = environment["CODEX_DOCK_TEST_APP_SERVER_BEARER_TOKEN_FILE"]
        ?? environment["CODEX_DOCK_APP_SERVER_BEARER_TOKEN_FILE"]
    guard let tokenFile, !tokenFile.isEmpty else {
        return nil
    }

    let token = try String(contentsOfFile: tokenFile, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return token.isEmpty ? nil : token
}

private func makeRealtimeRelayHost() -> DockHostConfiguration {
    try! DockHostConfiguration(host: "192.168.50.117", port: 4510)
}

private func configuredRelayURL(from environment: [String: String], label: String) throws -> URL {
    guard let endpoints = environment["CODEX_DOCK_HOSTS"],
          let endpointText = endpoints.split(separator: ",").first?.trimmingCharacters(in: .whitespacesAndNewlines),
          !endpointText.isEmpty
    else {
        throw XCTSkip("Set CODEX_DOCK_HOSTS=<host>:<port> to run the \(label) real-host test")
    }
    let endpoint = try DockRelayEndpoint.parse(endpointText)
    let url = endpoint.webSocketURL
    XCTAssertFalse(
        isLoopbackHost(url.host),
        "\(label) endpoint cannot be localhost, 127.0.0.1, or ::1"
    )
    return url
}

private func isLoopbackHost(_ host: String?) -> Bool {
    guard let host = host?.lowercased() else {
        return false
    }
    return ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)
}

private func canOpenThreadDetail(_ thread: ThreadDTO) -> Bool {
    switch thread.status {
    case .notLoaded, nil:
        return false
    case .idle, .systemError, .active, .unknown:
        return thread.id?.isEmpty == false
    }
}

actor ScriptedAppServerTransport: AppServerTransport {
    private enum SentWaiter {
        case message(CheckedContinuation<JSONRPCMessage, Error>)
    }

    private var connectResults: [Result<Void, Error>]
    private var inbound: [Result<String?, Error>] = []
    private var inboundWaiters: [CheckedContinuation<String?, Error>] = []
    private var sentMessages: [JSONRPCMessage] = []
    private var allSentMessages: [JSONRPCMessage] = []
    private var sentWaiters: [SentWaiter] = []
    private var connected = false
    private var connectCount = 0
    private var disconnectCount = 0

    init(connectError: Error? = nil) {
        if let connectError {
            self.connectResults = [.failure(connectError)]
        } else {
            self.connectResults = []
        }
    }

    func connect() async throws {
        connectCount += 1
        if !connectResults.isEmpty {
            try connectResults.removeFirst().get()
        }
        connected = true
    }

    func send(_ text: String) async throws {
        guard connected else {
            throw TestTransportError.offline
        }

        let message = try JSONRPCMessage.decode(from: text)
        allSentMessages.append(message)
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
        disconnectCount += 1
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

    func closeInbound() {
        enqueueResult(.success(nil))
    }

    func failInbound(_ error: Error) {
        enqueueResult(.failure(error))
    }

    func enqueueConnectFailure(_ error: Error) {
        connectResults.append(.failure(error))
    }

    func enqueueConnectSuccess() {
        connectResults.append(.success(()))
    }

    func connectCountSnapshot() -> Int {
        connectCount
    }

    func disconnectCountSnapshot() -> Int {
        disconnectCount
    }

    func sentMethodsSnapshot() -> [String] {
        allSentMessages.compactMap { message in
            switch message {
            case .request(let request):
                return request.method
            case .notification(let notification):
                return notification.method
            case .response, .error:
                return nil
            }
        }
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

    func nextSentResponse() async throws -> JSONRPCResponse {
        let message = try await nextSentMessage()
        guard case .response(let response) = message else {
            throw TestTransportError.unexpectedSentMessage
        }
        return response
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

private final class EndpointRecordingClientFactory: @unchecked Sendable {
    private let clients: [String: AppServerClient]
    private var endpointIDs: [String] = []

    init(clients: [String: AppServerClient]) {
        self.clients = clients
    }

    func client(for endpoint: DockRelayEndpoint) -> AppServerClient {
        endpointIDs.append(endpoint.id)
        guard let client = clients[endpoint.id] else {
            XCTFail("No client configured for endpoint \(endpoint.id)")
            return AppServerClient(transport: ScriptedAppServerTransport(connectError: TestTransportError.offline))
        }
        return client
    }

    func endpointIDsSnapshot() -> [String] {
        endpointIDs
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
                result: initializeResult()
            )
        )
    )
    _ = try await transport.nextSentNotification()
    _ = try await handshakeTask.value
}

private func respondToInitialize(
    transport: ScriptedAppServerTransport,
    relayInstanceID: String? = nil
) async throws {
    let initializeRequest = try await transport.nextSentRequest()
    XCTAssertEqual(initializeRequest.method, AppServerMethods.initialize)
    await transport.enqueue(
        .response(
            JSONRPCResponse(
                id: initializeRequest.id,
                result: initializeResult(relayInstanceID: relayInstanceID)
            )
        )
    )
    let initializedNotification = try await transport.nextSentNotification()
    XCTAssertEqual(initializedNotification.method, AppServerMethods.initialized)
}

private func threadListRow(id: String, updatedAt: Int64) -> ThreadDTO {
    ThreadDTO(
        id: id,
        sessionId: "session-\(id)",
        preview: "Preview \(id)",
        createdAt: updatedAt - 10,
        updatedAt: updatedAt,
        status: .idle,
        cwd: "/Users/aelaguiz/workspace/codex-client",
        source: .string("cli"),
        gitInfo: ThreadGitInfoDTO(branch: "main"),
        turns: []
    )
}

@MainActor
private func startRealtimeSession(
    service: RelayRealtimeTranscriptionClient,
    transport: ScriptedAppServerTransport
) async throws -> any RealtimeTranscriptionSession {
    let startTask = Task {
        try await service.startSession()
    }
    try await respondToInitialize(transport: transport)
    let startRequest = try await transport.nextSentRequest()
    XCTAssertEqual(startRequest.method, AppServerMethods.audioTranscriptionStart)
    await transport.enqueue(
        .response(
            JSONRPCResponse(
                id: startRequest.id,
                result: try JSONValue.encoded(
                    AudioTranscriptionStartResponseDTO(
                        sessionId: "transcription-1",
                        format: "audio/pcm",
                        sampleRate: 24_000,
                        model: "gpt-realtime-whisper"
                    )
                )
            )
        )
    )
    return try await startTask.value
}

private func initializeResult(relayInstanceID: String? = nil) -> JSONValue {
    var result: [String: JSONValue] = [
        "userAgent": .string("codex/1.2.3"),
        "codexHome": .string("/Users/aelaguiz/.codex"),
        "platformFamily": .string("unix"),
        "platformOs": .string("macos"),
    ]
    if let relayInstanceID {
        result["relayInstanceID"] = .string(relayInstanceID)
    }
    return .object(result)
}

private actor RealtimeEventProbe {
    private var buffered: [RealtimeTranscriptionEvent] = []
    private var waiters: [CheckedContinuation<RealtimeTranscriptionEvent?, Never>] = []
    private var isFinished = false

    init(_ events: AsyncStream<RealtimeTranscriptionEvent>) {
        Task { [events] in
            for await event in events {
                await self.enqueue(event)
            }
            await self.finish()
        }
    }

    func next() async -> RealtimeTranscriptionEvent? {
        if !buffered.isEmpty {
            return buffered.removeFirst()
        }
        if isFinished {
            return nil
        }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func bufferedCount() -> Int {
        buffered.count
    }

    private func enqueue(_ event: RealtimeTranscriptionEvent) {
        if waiters.isEmpty {
            buffered.append(event)
        } else {
            waiters.removeFirst().resume(returning: event)
        }
    }

    private func finish() {
        isFinished = true
        let waiters = waiters
        self.waiters.removeAll()
        for waiter in waiters {
            waiter.resume(returning: nil)
        }
    }
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

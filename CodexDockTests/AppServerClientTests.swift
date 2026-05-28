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
                            backwardsCursor: "before-1"
                        )
                    )
                )
            )
        )

        let response = try await task.value
        XCTAssertEqual(response.data.map(\.id), ["thread-1"])
        XCTAssertEqual(response.data.first?.status, .idle)
        XCTAssertEqual(response.backwardsCursor, "before-1")
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

    func testAudioTranscribeSendsTypedRelayRequestWithoutModel() async throws {
        let transport = ScriptedAppServerTransport()
        let client = AppServerClient(transport: transport)
        try await completeHandshake(client: client, transport: transport)

        let task = Task {
            try await client.audioTranscribe(
                params: AudioTranscribeParams(
                    mimeType: "audio/mp4",
                    base64Audio: "ZmFrZSBhdWRpbw=="
                ),
                timeout: .seconds(1)
            )
        }
        let request = try await transport.nextSentRequest()
        XCTAssertEqual(request.method, AppServerMethods.audioTranscribe)
        guard case .object(let params) = try XCTUnwrap(request.params) else {
            return XCTFail("Expected audio/transcribe params")
        }
        XCTAssertEqual(params["mimeType"], .string("audio/mp4"))
        XCTAssertEqual(params["base64Audio"], .string("ZmFrZSBhdWRpbw=="))
        XCTAssertNil(params["model"])

        await transport.enqueue(
            .response(
                JSONRPCResponse(
                    id: request.id,
                    result: try JSONValue.encoded(AudioTranscribeResponseDTO(text: "Check relay status"))
                )
            )
        )

        let response = try await task.value
        XCTAssertEqual(response.text, "Check relay status")
    }

    func testRelayTranscriptionClientSendsAudioThroughRelayWithoutOpenAIKeyOrModel() async throws {
        let transport = ScriptedAppServerTransport()
        let appServerClient = AppServerClient(transport: transport)
        let host = DockHostConfiguration(
            id: "Amir-M5",
            displayName: "Amir-M5",
            webSocketURL: URL(string: "ws://192.168.50.117:4510")!,
            bearerToken: nil
        )
        let service = RelayTranscriptionClient(host: host) { _ in
            appServerClient
        }
        let audioFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try Data("relay audio".utf8).write(to: audioFile)
        defer { try? FileManager.default.removeItem(at: audioFile) }

        let task = Task {
            try await service.transcribe(audioFile: audioFile)
        }

        let initializeRequest = try await transport.nextSentRequest()
        XCTAssertEqual(initializeRequest.method, AppServerMethods.initialize)
        await transport.enqueue(
            .response(
                JSONRPCResponse(
                    id: initializeRequest.id,
                    result: .object([
                        "userAgent": .string("codex-test"),
                        "codexHome": .string("/tmp/codex"),
                        "platformFamily": .string("unix"),
                        "platformOs": .string("macos"),
                    ])
                )
            )
        )
        let initializedNotification = try await transport.nextSentNotification()
        XCTAssertEqual(initializedNotification.method, AppServerMethods.initialized)

        let request = try await transport.nextSentRequest()
        XCTAssertEqual(request.method, AppServerMethods.audioTranscribe)
        guard case .object(let params) = try XCTUnwrap(request.params) else {
            return XCTFail("Expected audio/transcribe params")
        }
        XCTAssertEqual(params["mimeType"], .string("audio/mp4"))
        XCTAssertEqual(params["base64Audio"], .string(Data("relay audio".utf8).base64EncodedString()))
        XCTAssertNil(params["model"])

        await transport.enqueue(
            .response(
                JSONRPCResponse(
                    id: request.id,
                    result: try JSONValue.encoded(AudioTranscribeResponseDTO(text: "  relay transcript  "))
                )
            )
        )

        let transcript = try await task.value
        XCTAssertEqual(transcript, "relay transcript")
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
        try await assertRealHostHandshakeSucceeds(
            url: url,
            bearerToken: nil,
            timeout: .seconds(5)
        )
    }

    func testPhoneReachableRealHostThreadListWhenEndpointIsProvided() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let endpoint = environment["CODEX_DOCK_PHONE_REACHABLE_APP_SERVER_WS"], !endpoint.isEmpty else {
            throw XCTSkip(
                "Set CODEX_DOCK_PHONE_REACHABLE_APP_SERVER_WS to run the phone-reachable real-host thread/list test"
            )
        }
        let url = try XCTUnwrap(URL(string: endpoint))
        XCTAssertTrue(
            ["ws", "wss"].contains(url.scheme?.lowercased()),
            "Phone-reachable thread/list endpoint must be a WebSocket URL"
        )
        XCTAssertFalse(
            isLoopbackHost(url.host),
            "Phone-reachable thread/list endpoint cannot be localhost, 127.0.0.1, or ::1"
        )
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
        guard let endpoint = environment["CODEX_DOCK_PHONE_REACHABLE_APP_SERVER_WS"], !endpoint.isEmpty else {
            throw XCTSkip(
                "Set CODEX_DOCK_PHONE_REACHABLE_APP_SERVER_WS to run the phone-reachable real-host thread detail test"
            )
        }
        let url = try XCTUnwrap(URL(string: endpoint))
        XCTAssertTrue(
            ["ws", "wss"].contains(url.scheme?.lowercased()),
            "Phone-reachable thread detail endpoint must be a WebSocket URL"
        )
        XCTAssertFalse(
            isLoopbackHost(url.host),
            "Phone-reachable thread detail endpoint cannot be localhost, 127.0.0.1, or ::1"
        )
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
        let endpoint = try XCTUnwrap(environment["CODEX_DOCK_PHONE_REACHABLE_APP_SERVER_WS"])
        let url = try XCTUnwrap(URL(string: endpoint))
        XCTAssertTrue(
            ["ws", "wss"].contains(url.scheme?.lowercased()),
            "Phone-reachable archive endpoint must be a WebSocket URL"
        )
        XCTAssertFalse(
            isLoopbackHost(url.host),
            "Phone-reachable archive endpoint cannot be localhost, 127.0.0.1, or ::1"
        )
        let client = AppServerClient(webSocketURL: url, bearerToken: nil)
        _ = try await client.connectAndInitialize(
            params: .codexDock(version: "0.1.0"),
            timeout: .seconds(5)
        )
        var archivedThreadID: String?

        do {
            let list = try await client.threadList(
                params: ThreadListParams(
                    limit: 200,
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
                    limit: 200,
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
                    limit: 200,
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

private func canOpenThreadDetail(_ thread: ThreadDTO) -> Bool {
    switch thread.status {
    case .notLoaded, nil:
        return false
    case .idle, .systemError, .active, .unknown:
        return thread.id?.isEmpty == false
    }
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

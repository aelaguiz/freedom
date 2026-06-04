import XCTest
@testable import CodexDock

final class ClientCommandEngineTests: XCTestCase {
    func testThreadCommandsUseCommandActor() async throws {
        let host = makeHost()
        let projectionID = "host:\(host.id)/thread:thread-a/row:threadCard"
        let row = DockRowViewModel(
            threadIdentity: HostScopedThreadID(hostID: host.id, threadID: "thread-a"),
            projectionID: projectionID,
            backendSessionID: "backend-thread-a",
            title: "Thread A",
            hostDisplayName: host.displayName,
            hostEndpoint: host.endpoint.displayEndpoint,
            repository: "codex-client",
            branch: "main",
            status: .running,
            lastActivity: "now",
            lastActivityDate: Date(timeIntervalSince1970: 1_000),
            displayOrderKey: "9999999999000000|0001|\(projectionID)",
            summary: "summary",
            rail: .blue,
            label: nil,
            origin: .humanInteractive(subtype: .cli)
        )
        let archiver = RecordingThreadArchiver()
        let renamer = RecordingThreadRenamer()
        let engine = ClientCommandEngine(archiver: archiver, renamer: renamer)

        try await engine.archive(row, on: host)
        try await engine.unarchive(row, on: host)
        try await engine.rename(row, to: "Renamed thread", on: host)

        let archivedIDs = await archiver.archivedIDs()
        let unarchivedIDs = await archiver.unarchivedIDs()
        let renamedRequests = await renamer.renamedRequests()
        XCTAssertEqual(archivedIDs, ["thread-a"])
        XCTAssertEqual(unarchivedIDs, ["thread-a"])
        XCTAssertEqual(
            renamedRequests,
            [RecordedThreadRename(threadID: "thread-a", name: "Renamed thread", hostID: host.id)]
        )
    }

    func testThreadUserMessageCommandSubmitsIdempotentRelayCommandThroughSession() async throws {
        let session = makeThreadSession()
        let engine = ClientCommandEngine()
        let clientID = ClientUserMessageID(rawValue: "dock-msg:test-command")

        let response = try await engine.sendUserMessage(
            "Start work",
            threadID: "thread-a",
            clientUserMessageID: clientID,
            session: session
        )

        let messageParams = session.threadMessageSendParamsSnapshot()
        XCTAssertEqual(response.clientUserMessageId, "dock-msg:test-command")
        XCTAssertEqual(response.state, "submittedUpstream")
        XCTAssertEqual(messageParams, [
            ThreadMessageSendParams.text(
                threadId: "thread-a",
                clientUserMessageId: "dock-msg:test-command",
                text: "Start work"
            ),
        ])
        XCTAssertEqual(session.turnStartParamsSnapshot(), [])
        XCTAssertEqual(session.turnSteerParamsSnapshot(), [])
    }

    func testThreadRequestResponseCommandSendsPayloadThroughSession() async throws {
        let session = makeThreadSession()
        let engine = ClientCommandEngine()

        try await engine.respondToServerRequest(
            requestID: .string("approval-1"),
            payload: .bool(true),
            session: session
        )

        let sentResponses = session.sentResponsesSnapshot()
        XCTAssertEqual(sentResponses, [
            SentServerResponse(id: .string("approval-1"), result: .bool(true))
        ])
    }

    private func makeThreadSession() -> FakeThreadDetailSession {
        FakeThreadDetailSession(
            detailSubscribeResult: .success(.thread("thread-a")),
            detailResyncResult: .success(.thread("thread-a"))
        )
    }
}

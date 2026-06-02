import XCTest
@testable import CodexDock

final class ClientCommandEngineTests: XCTestCase {
    func testArchiveAndUnarchiveCommandsUseArchiverActor() async throws {
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
        let engine = ClientCommandEngine(archiver: archiver)

        try await engine.archive(row, on: host)
        try await engine.unarchive(row, on: host)

        let archivedIDs = await archiver.archivedIDs()
        let unarchivedIDs = await archiver.unarchivedIDs()
        XCTAssertEqual(archivedIDs, ["thread-a"])
        XCTAssertEqual(unarchivedIDs, ["thread-a"])
    }

    func testThreadDraftCommandStartsOrSteersTurnThroughSession() async throws {
        let session = makeThreadSession()
        let engine = ClientCommandEngine()

        let startedTurnID = try await engine.sendDraft(
            "Start work",
            threadID: "thread-a",
            activeTurnID: nil,
            session: session
        )
        let steeredTurnID = try await engine.sendDraft(
            "Keep going",
            threadID: "thread-a",
            activeTurnID: "turn-started",
            session: session
        )

        let startParams = session.turnStartParamsSnapshot()
        let steerParams = session.turnSteerParamsSnapshot()
        XCTAssertEqual(startedTurnID, "turn-started")
        XCTAssertEqual(steeredTurnID, "turn-started")
        XCTAssertEqual(startParams.map(\.threadId), ["thread-a"])
        XCTAssertEqual(steerParams.map(\.expectedTurnId), ["turn-started"])
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
            readResult: .success(
                ThreadReadResponseDTO(thread: ThreadDTO(id: "thread-a", turns: []))
            ),
            resumeResult: .success(
                ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-a", turns: []))
            )
        )
    }
}

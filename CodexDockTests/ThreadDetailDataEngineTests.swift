import XCTest
@testable import CodexDock

final class ThreadDetailDataEngineTests: XCTestCase {
    func testEngineNormalizesAndSortsThreadEventsOffMain() async throws {
        let engine = ThreadDetailDataEngine()
        let thread = ThreadDTO(
            id: "thread-1",
            turns: [
                makeDetailTurn(id: "old-turn", startedAt: 1_000, text: "Old"),
                makeDetailTurn(id: "new-turn", startedAt: 2_000, text: "New"),
            ]
        )

        let snapshot = try await engine.replace(
            from: thread,
            expectedThreadID: "thread-1"
        )

        XCTAssertEqual(snapshot.events.map(\.body), ["New", "Old"])
        XCTAssertNil(snapshot.activeTurnID)
    }

    func testEngineShowsCompletedAgentReplyAboveEarlierUserPromptInSameTurn() async throws {
        let engine = ThreadDetailDataEngine()
        let thread = ThreadDTO(
            id: "thread-1",
            turns: [
                .object([
                    "id": .string("turn-1"),
                    "startedAt": .integer(1_000),
                    "completedAt": .integer(2_000),
                    "items": .array([
                        .object([
                            "id": .string("user-1"),
                            "type": .string("userMessage"),
                            "content": .array([.object(["text": .string("Older prompt")])]),
                        ]),
                        .object([
                            "id": .string("agent-1"),
                            "type": .string("agentMessage"),
                            "text": .string("Newer answer"),
                        ]),
                    ]),
                ]),
            ]
        )

        let snapshot = try await engine.replace(
            from: thread,
            expectedThreadID: "thread-1"
        )

        XCTAssertEqual(snapshot.events.map(\.body), ["Newer answer", "Older prompt"])
    }

    func testEngineMergesStreamingDeltasByTurnAndItem() async throws {
        let engine = ThreadDetailDataEngine()
        _ = try await engine.replace(
            from: ThreadDTO(id: "thread-1", turns: []),
            expectedThreadID: "thread-1"
        )

        _ = await engine.apply(
            notification: delta("hello "),
            expectedThreadID: "thread-1",
            now: Date(timeIntervalSince1970: 3_000)
        )
        let snapshot = await engine.apply(
            notification: delta("world"),
            expectedThreadID: "thread-1",
            now: Date(timeIntervalSince1970: 3_001)
        )

        XCTAssertEqual(snapshot?.events.map(\.body), ["hello world"])
    }

    func testEngineUpdatesStreamingDeltaRecencyWhenMerging() async throws {
        let engine = ThreadDetailDataEngine()
        _ = try await engine.replace(
            from: ThreadDTO(id: "thread-1", turns: []),
            expectedThreadID: "thread-1"
        )

        _ = await engine.apply(
            notification: delta("hello "),
            expectedThreadID: "thread-1",
            now: Date(timeIntervalSince1970: 3_000)
        )
        _ = await engine.apply(
            request: JSONRPCRequest(
                id: .string("approval-1"),
                method: "item/commandExecution/requestApproval",
                params: .object([
                    "threadId": .string("thread-1"),
                    "command": .string("make test"),
                ])
            ),
            expectedThreadID: "thread-1",
            now: Date(timeIntervalSince1970: 3_000.5)
        )
        let snapshot = await engine.apply(
            notification: delta("world"),
            expectedThreadID: "thread-1",
            now: Date(timeIntervalSince1970: 3_001)
        )

        XCTAssertEqual(snapshot?.events.map(\.body), ["hello world", "make test"])
        XCTAssertEqual(snapshot?.events.first?.activityDate, Date(timeIntervalSince1970: 3_001))
    }

    func testEngineTracksActiveTurnWithoutMainActorStoreMergeWork() async throws {
        let engine = ThreadDetailDataEngine()
        let thread = ThreadDTO(
            id: "thread-1",
            turns: [
                .object([
                    "id": .string("turn-active"),
                    "status": .string("inProgress"),
                    "items": .array([])
                ])
            ]
        )

        let loaded = try await engine.replace(
            from: thread,
            expectedThreadID: "thread-1"
        )
        XCTAssertEqual(loaded.activeTurnID, "turn-active")

        let completed = await engine.apply(
            notification: JSONRPCNotification(
                method: "turn/completed",
                params: .object([
                    "threadId": .string("thread-1"),
                    "turn": .object(["id": .string("turn-active")])
                ])
            ),
            expectedThreadID: "thread-1",
            now: Date(timeIntervalSince1970: 3_000)
        )
        XCTAssertNil(completed?.activeTurnID)
    }

    private func delta(_ body: String) -> JSONRPCNotification {
        JSONRPCNotification(
            method: "item/agentMessage/delta",
            params: .object([
                "threadId": .string("thread-1"),
                "turnId": .string("turn-1"),
                "itemId": .string("agent-1"),
                "delta": .string(body),
            ])
        )
    }
}

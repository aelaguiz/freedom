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

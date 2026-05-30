import XCTest
@testable import CodexDock

final class ThreadDetailStreamingMergeTests: XCTestCase {
    @MainActor
    func testCompletedAgentMessageReplacesLiveDeltaInsteadOfDuplicating() async throws {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let session = FakeThreadDetailSession(
            readResult: .success(ThreadReadResponseDTO(thread: ThreadDTO(id: "thread-1", turns: []))),
            resumeResult: .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-1", turns: [])))
        )
        let store = ThreadDetailStore(
            host: host,
            row: row,
            factory: FakeThreadDetailSessionFactory(session: session),
            now: { Date(timeIntervalSince1970: 3_000) }
        )

        await store.load()
        await session.emitNotification(
            JSONRPCNotification(
                method: "item/agentMessage/delta",
                params: .object([
                    "threadId": .string("thread-1"),
                    "turnId": .string("turn-live"),
                    "itemId": .string("agent-live"),
                    "delta": .string("Partial answer"),
                ])
            )
        )
        await session.emitNotification(
            JSONRPCNotification(
                method: "item/completed",
                params: .object([
                    "threadId": .string("thread-1"),
                    "turnId": .string("turn-live"),
                    "item": .object([
                        "id": .string("agent-live"),
                        "type": .string("agentMessage"),
                        "text": .string("Partial answer with the full ending."),
                    ]),
                ])
            )
        )

        try await waitForDetailStore {
            guard case let .loaded(snapshot) = store.state else {
                return false
            }
            return snapshot.events.map(\.body) == ["Partial answer with the full ending."]
        }
    }
}

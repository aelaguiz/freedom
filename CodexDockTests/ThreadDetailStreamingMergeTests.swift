import XCTest
@testable import CodexDock

final class ThreadDetailStreamingMergeTests: XCTestCase {
    @MainActor
    func testCompletedAgentMessageReplacesLiveDeltaInsteadOfDuplicating() async throws {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let session = FakeThreadDetailSession(
            detailSubscribeResult: .success(.thread("thread-1")),
            detailResyncResult: .success(.thread("thread-1"))
        )
        let store = ThreadDetailStore(
            host: host,
            row: row,
            factory: FakeThreadDetailSessionFactory(session: session),
            now: { Date(timeIntervalSince1970: 3_000) }
        )

        await store.load()
        await session.emitProjectedAgentDelta(
            turnID: "turn-live",
            itemID: "agent-live",
            text: "Partial answer"
        )
        await session.emitProjectedAgentCompleted(
            turnID: "turn-live",
            itemID: "agent-live",
            text: "Partial answer with the full ending."
        )

        try await waitForDetailStore {
            guard case let .loaded(snapshot) = store.state else {
                return false
            }
            return snapshot.events.map(\.body) == ["Partial answer with the full ending."]
        }
    }
}

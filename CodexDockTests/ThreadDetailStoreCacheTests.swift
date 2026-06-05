import XCTest
@testable import CodexDock

final class ThreadDetailStoreCacheTests: XCTestCase {
    @MainActor
    func testCacheReturnsRetainedStoreForSameThreadIdentityAndUpdatesRow() {
        let host = makeDetailHost()
        let initialRow = makeDetailRow(
            hostID: host.id,
            threadID: "thread-1",
            lastActivityDate: Date(timeIntervalSince1970: 1_000),
            displayOrderKey: "1000"
        )
        let updatedRow = makeDetailRow(
            hostID: host.id,
            threadID: "thread-1",
            lastActivityDate: Date(timeIntervalSince1970: 2_000),
            displayOrderKey: "2000"
        )
        let session = FakeThreadDetailSession()
        let cache = ThreadDetailStoreCache(capacity: 2)
        var makeCount = 0

        let firstStore = cache.store(for: initialRow) {
            makeCount += 1
            return ThreadDetailStore(
                host: host,
                row: initialRow,
                factory: FakeThreadDetailSessionFactory(session: session)
            )
        }
        let secondStore = cache.store(for: updatedRow) {
            makeCount += 1
            return ThreadDetailStore(
                host: host,
                row: updatedRow,
                factory: FakeThreadDetailSessionFactory(session: session)
            )
        }

        XCTAssertTrue(firstStore === secondStore)
        XCTAssertEqual(makeCount, 1)
        XCTAssertEqual(cache.count, 1)
        XCTAssertEqual(secondStore.row.lastActivityDate, Date(timeIntervalSince1970: 2_000))
    }

    @MainActor
    func testCacheHitReattachesLoadedStoreAndStartsRetainedRefresh() async throws {
        let host = makeDetailHost()
        let row = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let session = FakeThreadDetailSession(
            detailSubscribeResult: .success(.thread("thread-1")),
            detailResyncResult: .success(.thread("thread-1")),
            detailResyncDelay: .milliseconds(100),
            projectionRowsResults: [
                .success([
                    makeProjectedDetailEvent(
                        threadID: "thread-1",
                        turnID: "turn-initial",
                        startedAt: 1_000,
                        text: "Initial"
                    ),
                ]),
                .success([
                    makeProjectedDetailEvent(
                        threadID: "thread-1",
                        turnID: "turn-updated",
                        startedAt: 2_000,
                        text: "Updated"
                    ),
                    makeProjectedDetailEvent(
                        threadID: "thread-1",
                        turnID: "turn-initial",
                        startedAt: 1_000,
                        text: "Initial"
                    ),
                ]),
            ]
        )
        let cache = ThreadDetailStoreCache(capacity: 2)

        let firstStore = cache.store(for: row) {
            ThreadDetailStore(
                host: host,
                row: row,
                factory: FakeThreadDetailSessionFactory(session: session)
            )
        }
        await firstStore.load()
        firstStore.detachView()

        let reopenedStore = cache.store(for: row) {
            XCTFail("Cache hit should not create a second ThreadDetailStore.")
            return ThreadDetailStore(
                host: host,
                row: row,
                factory: FakeThreadDetailSessionFactory(session: session)
            )
        }

        XCTAssertTrue(firstStore === reopenedStore)
        try await waitForDetailStore {
            session.detailResyncParamsSnapshot().count == 1
        }
        guard case let .loaded(updatingSnapshot) = reopenedStore.state else {
            return XCTFail("Expected loaded updating state after retained cache hit, got \(reopenedStore.state)")
        }
        XCTAssertEqual(updatingSnapshot.liveState, .updating)
        XCTAssertEqual(updatingSnapshot.events.map(\.body), ["Initial"])

        try await waitForDetailStore {
            guard case let .loaded(snapshot) = reopenedStore.state else {
                return false
            }
            return snapshot.liveState == .live
                && snapshot.events.map(\.body) == ["Updated", "Initial"]
        }
    }

    @MainActor
    func testCacheEvictsOldestStoreAndClosesIt() async throws {
        let host = makeDetailHost()
        let row1 = makeDetailRow(hostID: host.id, threadID: "thread-1")
        let row2 = makeDetailRow(hostID: host.id, threadID: "thread-2")
        let session1 = FakeThreadDetailSession(
            projectionRowsResult: .success([
                makeProjectedDetailEvent(threadID: "thread-1", text: "First thread"),
            ])
        )
        let session2 = FakeThreadDetailSession(
            detailSubscribeResult: .success(.thread("thread-2")),
            projectionRowsResult: .success([
                makeProjectedDetailEvent(threadID: "thread-2", text: "Second thread"),
            ])
        )
        let cache = ThreadDetailStoreCache(capacity: 1)

        let firstStore = cache.store(for: row1) {
            ThreadDetailStore(
                host: host,
                row: row1,
                factory: FakeThreadDetailSessionFactory(session: session1)
            )
        }
        await firstStore.load()

        _ = cache.store(for: row2) {
            ThreadDetailStore(
                host: host,
                row: row2,
                factory: FakeThreadDetailSessionFactory(session: session2)
            )
        }

        try await waitForDetailStore {
            session1.disconnectCallCountSnapshot() == 1
        }
        XCTAssertEqual(cache.count, 1)
    }
}

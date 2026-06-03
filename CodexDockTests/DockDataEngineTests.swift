import XCTest
@testable import CodexDock

final class DockDataEngineTests: XCTestCase {
    func testEngineAppliesSnapshotAndBuildsRenderSnapshotOffMain() async throws {
        let host = makeHost()
        let registry = try HostRegistry(hosts: [host])
        let engine = DockDataEngine(registry: registry)
        let update = dockStreamSnapshot(
            host: host,
            epoch: "epoch-a",
            seq: 1,
            cards: [
                threadCardFixture(
                    host: host,
                    threadID: "thread-a",
                    title: "Thread A",
                    updatedAt: 2_000
                )
            ]
        )

        try await engine.apply(threadCardReconcilerSnapshot(update), host: host)
        let snapshot = await engine.snapshot(now: { Date(timeIntervalSince1970: 2_000) })

        XCTAssertEqual(snapshot?.rows.map(\.title), ["Thread A"])
        XCTAssertEqual(snapshot?.hostStates.map(\.status), [.loaded(rowCount: 1)])
    }

    func testEngineAppliesLocalMetadataToRelayRowsBeforeProjection() async throws {
        let host = makeHost()
        let registry = try HostRegistry(hosts: [host])
        let key = LocalThreadMetadataKey(
            hostID: host.id,
            backendSessionID: "thread-a-session",
            threadID: "thread-a"
        )
        let metadata = LocalThreadMetadata(
            label: nil,
            rail: .violet,
            isPinned: true,
            pinnedAt: Date(timeIntervalSince1970: 10),
            pinnedOrder: 0
        )
        let engine = DockDataEngine(
            registry: registry,
            localMetadata: [key: metadata]
        )
        let update = dockStreamSnapshot(
            host: host,
            epoch: "epoch-a",
            seq: 1,
            cards: [
                threadCardFixture(
                    host: host,
                    threadID: "thread-a",
                    title: "Thread A",
                    updatedAt: 2_000
                )
            ]
        )

        try await engine.apply(threadCardReconcilerSnapshot(update), host: host)
        let snapshot = await engine.snapshot(now: { Date(timeIntervalSince1970: 2_000) })
        let rows = snapshot?.rows ?? []

        XCTAssertEqual(rows.map(\.threadID), ["thread-a"])
        XCTAssertEqual(rows.map(\.isPinned), [true])
        XCTAssertEqual(rows.map(\.rail), [.violet])
    }
}

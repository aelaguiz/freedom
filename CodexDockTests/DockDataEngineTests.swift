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

        let result = await engine.applySnapshot(update, host: host)
        let snapshot = await engine.snapshot(now: { Date(timeIntervalSince1970: 2_000) })

        XCTAssertEqual(result, .applied)
        XCTAssertEqual(snapshot?.rows.map(\.title), ["Thread A"])
        XCTAssertEqual(snapshot?.hostStates.map(\.status), [.loaded(rowCount: 1)])
    }

    func testEngineKeepsStaleUpdateOutAndRequestsResync() async throws {
        let host = makeHost()
        let registry = try HostRegistry(hosts: [host])
        let engine = DockDataEngine(registry: registry)
        let snapshot = dockStreamSnapshot(
            host: host,
            epoch: "epoch-a",
            seq: 2,
            cards: [
                threadCardFixture(
                    host: host,
                    threadID: "thread-a",
                    title: "Thread A",
                    updatedAt: 2_000
                )
            ]
        )
        let staleDelta = ThreadCardStreamUpdateDTO(
            kind: .upsert,
            schemaVersion: CodexDockConstants.Dock.streamSchemaVersion,
            identityVersion: 1,
                projectionEngineVersion: 1,
                sourceHostID: host.id,
                view: .dock,
            scope: "view",
                viewParamsKey: "dock:\(host.id)",
                complete: nil,
            totalRows: nil,
            window: nil,
            epoch: "epoch-a",
            seq: 4,
            order: "displayOrderKeyAscending",
                rows: [],
            projectionIDs: []
        )

        _ = await engine.applySnapshot(snapshot, host: host)
        let result = await engine.applyUpdate(staleDelta, host: host)
        let rowCount = await engine.rowCount(for: host)

        XCTAssertEqual(result, ThreadCardTableApplyResult.needsResync(.sequenceGap))
        XCTAssertEqual(rowCount, 1)
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

        _ = await engine.applySnapshot(update, host: host)
        let snapshot = await engine.snapshot(now: { Date(timeIntervalSince1970: 2_000) })
        let rows = snapshot?.rows ?? []

        XCTAssertEqual(rows.map(\.threadID), ["thread-a"])
        XCTAssertEqual(rows.map(\.isPinned), [true])
        XCTAssertEqual(rows.map(\.rail), [.violet])
    }
}

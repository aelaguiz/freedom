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
            sessions: [
                dockStreamSession(
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
            sessions: [
                dockStreamSession(
                    host: host,
                    threadID: "thread-a",
                    title: "Thread A",
                    updatedAt: 2_000
                )
            ]
        )
        let staleDelta = DockStreamUpdateDTO(
            kind: .delta,
            schemaVersion: CodexDockConstants.Dock.streamSchemaVersion,
            view: "dock",
            complete: nil,
            totalRows: nil,
            window: nil,
            stateGeneration: 3,
            epoch: "epoch-a",
            baseSeq: 1,
            seq: 3,
            upsertSessions: [],
            deleteSessionIDs: []
        )

        _ = await engine.applySnapshot(snapshot, host: host)
        let result = await engine.applyUpdate(staleDelta, host: host)
        let rowCount = await engine.rowCount(for: host)

        XCTAssertEqual(result, DockSessionTableApplyResult.needsResync(.sequenceGap))
        XCTAssertEqual(rowCount, 1)
    }

    func testEngineAppliesLocalMetadataBeforeSnapshotProjection() async throws {
        let host = makeHost()
        let registry = try HostRegistry(hosts: [host])
        let key = LocalThreadMetadataKey(
            hostID: host.id,
            backendSessionID: "cached-session",
            threadID: "cached-thread"
        )
        let metadata = LocalThreadMetadata(
            label: nil,
            rail: .violet,
            isPinned: true,
            pinnedAt: Date(timeIntervalSince1970: 10),
            pinnedOrder: 0,
            lastKnownPinnedDisplay: nil
        )
        let engine = DockDataEngine(
            registry: registry,
            localMetadata: [key: metadata]
        )

        let snapshot = await engine.snapshot(now: { Date(timeIntervalSince1970: 2_000) })
        let rows = snapshot?.rows ?? []

        XCTAssertEqual(rows.map(\.id.threadID), ["cached-thread"])
        XCTAssertEqual(rows.map(\.isPinned), [true])
        XCTAssertEqual(rows.map(\.rail), [.violet])
    }
}

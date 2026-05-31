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
            kind: .delta,
            schemaVersion: CodexDockConstants.Dock.streamSchemaVersion,
            view: .dock,
            complete: nil,
            totalRows: nil,
            window: nil,
            stateGeneration: 3,
            epoch: "epoch-a",
            baseSeq: 1,
            seq: 3,
            upsertCards: [],
            deleteCardIDs: []
        )

        _ = await engine.applySnapshot(snapshot, host: host)
        let result = await engine.applyUpdate(staleDelta, host: host)
        let rowCount = await engine.rowCount(for: host)

        XCTAssertEqual(result, ThreadCardTableApplyResult.needsResync(.sequenceGap))
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
            lastKnownPinnedDisplay: LocalPinnedDisplaySnapshot(
                title: "Cached pinned",
                hostDisplayName: host.displayName,
                hostEndpoint: host.endpoint.displayEndpoint,
                repository: "codex-client",
                branch: "main",
                status: .dormant,
                lastActivity: "5m ago",
                lastActivityDate: Date(timeIntervalSince1970: 1_700),
                summary: "Cached summary",
                rail: .blue,
                label: nil,
                originKind: .human
            )
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

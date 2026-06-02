import XCTest
@testable import CodexDock

final class DockRenderProjectorTests: XCTestCase {
    func testProjectorBuildsSnapshotRowsAndProjectionOffMain() async throws {
        let host = makeHost()
        let input = DockRenderInput(
            hosts: [host],
            hostStates: [
                DockHostStateViewModel(
                    host: DockHostViewModel(host: host),
                    status: .loaded(rowCount: 1)
                )
            ],
            cardsByHostID: [
                host.id: [
                    threadCardFixture(
                        host: host,
                        threadID: "thread-a",
                        title: "Active row",
                        updatedAt: 2_000
                    )
                ]
            ],
            isPartial: false
        )
        let projector = DockRenderProjector(now: { Date(timeIntervalSince1970: 2_000) })

        let snapshot = projector.snapshot(from: input, localMetadata: [:])
        let render = await Task.detached {
            projector.render(
                snapshot: snapshot,
                options: DockProjectionOptions(lens: .newest),
                revision: RenderRevision(rawValue: 7)
            )
        }.value

        XCTAssertEqual(render.revision, RenderRevision(rawValue: 7))
        XCTAssertEqual(render.snapshot.rows.map(\.title), ["Active row"])
        XCTAssertEqual(render.projection.rows.map(\.title), ["Active row"])
        XCTAssertEqual(render.snapshot.hostStates.map(\.status), [.loaded(rowCount: 1)])
    }

    func testProjectorDoesNotCreateRowsFromPinnedLocalMetadata() async {
        let host = makeHost()
        let key = LocalThreadMetadataKey(
            hostID: host.id,
            backendSessionID: "cached-session",
            threadID: "cached-thread"
        )
        let metadata = LocalThreadMetadata(
            label: "Pinned",
            rail: .green,
            isPinned: true,
            pinnedAt: Date(timeIntervalSince1970: 10),
            pinnedOrder: 0
        )
        let input = DockRenderInput(
            hosts: [host],
            hostStates: [
                DockHostStateViewModel(
                    host: DockHostViewModel(host: host),
                    status: .empty
                )
            ],
            cardsByHostID: [host.id: []],
            isPartial: false
        )
        let projector = DockRenderProjector(now: { Date(timeIntervalSince1970: 2_000) })

        let snapshot = await Task.detached {
            projector.snapshot(from: input, localMetadata: [key: metadata])
        }.value

        XCTAssertEqual(snapshot.rows, [])
    }

    func testProjectorDropsNonHumanStreamCards() async {
        let host = makeHost()
        let input = DockRenderInput(
            hosts: [host],
            hostStates: [
                DockHostStateViewModel(
                    host: DockHostViewModel(host: host),
                    status: .loaded(rowCount: 1)
                )
            ],
            cardsByHostID: [
                host.id: [
                    threadCardFixture(host: host, threadID: "human-row", title: "Human row", updatedAt: 2_000),
                    threadCardFixture(host: host, threadID: "agent-row", title: "Agent row", updatedAt: 2_100, sourceKind: .automation, lane: .agent)
                ]
            ],
            isPartial: false
        )
        let projector = DockRenderProjector(now: { Date(timeIntervalSince1970: 2_000) })

        let snapshot = await Task.detached {
            projector.snapshot(from: input, localMetadata: [:])
        }.value

        XCTAssertEqual(snapshot.rows.map(\.threadID), ["human-row"])
    }

    func testProjectorAppliesPinnedMetadataOnlyToDeliveredRows() async {
        let host = makeHost()
        let humanKey = LocalThreadMetadataKey(
            hostID: host.id,
            backendSessionID: "human-thread-session",
            threadID: "human-thread"
        )
        let input = DockRenderInput(
            hosts: [host],
            hostStates: [
                DockHostStateViewModel(
                    host: DockHostViewModel(host: host),
                    status: .empty
                )
            ],
            cardsByHostID: [
                host.id: [
                    threadCardFixture(
                        host: host,
                        threadID: "human-thread",
                        title: "Delivered row",
                        updatedAt: 2_000
                    )
                ]
            ],
            isPartial: false
        )
        let projector = DockRenderProjector(now: { Date(timeIntervalSince1970: 2_000) })

        let snapshot = projector.snapshot(
            from: input,
            localMetadata: [
                humanKey: LocalThreadMetadata(
                    isPinned: true,
                    pinnedAt: Date(timeIntervalSince1970: 10)
                )
            ]
        )

        XCTAssertEqual(snapshot.rows.map(\.threadID), ["human-thread"])
        XCTAssertTrue(snapshot.rows[0].isPinned)
    }
}

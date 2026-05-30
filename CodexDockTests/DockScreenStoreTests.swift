import XCTest
@testable import CodexDock

final class DockScreenStoreTests: XCTestCase {
    @MainActor
    func testDockStorePublishesLoadedSnapshotsIntoScreenStore() async throws {
        let host = makeHost()
        let store = DockStore(
            host: host,
            streamClient: LoaderBackedDockStreamClient(
                loader: FakeDockSessionLoader(
                    mode: .success(
                        DockLoadResult(
                            summaries: [
                                makeSummary(
                                    hostID: host.id,
                                    threadID: "thread-a",
                                    branch: "main",
                                    status: .active(activeFlags: []),
                                    lastActivity: Date(timeIntervalSince1970: 2_000),
                                    prompt: "Thread A"
                                )
                            ]
                        )
                    )
                )
            ),
            now: { Date(timeIntervalSince1970: 2_000) }
        )

        await store.load()

        let render = await waitForLoadedRender(
            in: store.screenStore,
            where: { $0.projection.rows.map(\.title) == ["Thread A"] }
        )
        XCTAssertEqual(render?.snapshot.rows.map(\.title), ["Thread A"])

        store.screenStore.setSearchText("missing")
        let filteredRender = await waitForLoadedRender(
            in: store.screenStore,
            where: { $0.revision.rawValue > (render?.revision.rawValue ?? 0) }
        )
        XCTAssertEqual(filteredRender?.projection.rows, [])
        XCTAssertEqual(filteredRender?.projection.emptyReason, .noSearchMatches)
    }

    @MainActor
    func testScreenStorePublishesProjectedRenderSnapshotFromCoalescedStream() async throws {
        let host = makeHost()
        let store = DockScreenStore(
            hosts: [DockHostViewModel(host: host)],
            now: { Date(timeIntervalSince1970: 2_000) }
        )
        let snapshot = makeSnapshot(host: host)

        store.start()
        store.publish(snapshot: snapshot)

        let render = await waitForLoadedRender(in: store)
        XCTAssertEqual(render?.projection.rows.map(\.title), ["Thread A"])
        XCTAssertEqual(render?.revision, RenderRevision(rawValue: 1))
    }

    @MainActor
    func testScreenStoreReprojectsWhenOptionsChange() async throws {
        let host = makeHost()
        let store = DockScreenStore(
            hosts: [DockHostViewModel(host: host)],
            now: { Date(timeIntervalSince1970: 2_000) }
        )
        let snapshot = makeSnapshot(host: host)

        store.start()
        store.publish(snapshot: snapshot)
        _ = await waitForLoadedRender(in: store)
        store.updateOptions(DockProjectionOptions(searchText: "missing"))

        let render = await waitForLoadedRender(
            in: store,
            where: { $0.revision == RenderRevision(rawValue: 2) }
        )
        XCTAssertEqual(render?.projection.rows, [])
        XCTAssertEqual(render?.projection.emptyReason, .noSearchMatches)
    }

    @MainActor
    func testSearchTextIsDisplayedImmediatelyButProjectionIsDebounced() async throws {
        let host = makeHost()
        let store = DockScreenStore(
            hosts: [DockHostViewModel(host: host)],
            now: { Date(timeIntervalSince1970: 2_000) }
        )
        let snapshot = makeSnapshot(host: host)

        store.start()
        store.publish(snapshot: snapshot)
        let firstRender = await waitForLoadedRender(in: store)

        store.setSearchText("missing")

        XCTAssertEqual(store.searchText, "missing")
        XCTAssertEqual(store.options.searchText, "")
        if case .loaded(let render) = store.state {
            XCTAssertEqual(render.revision, firstRender?.revision)
        }

        try await Task.sleep(
            for: .milliseconds(CodexDockConstants.Rendering.searchDebounceMilliseconds + 40)
        )

        let debouncedRender = await waitForLoadedRender(
            in: store,
            where: { $0.revision.rawValue > (firstRender?.revision.rawValue ?? 0) }
        )
        XCTAssertEqual(store.options.searchText, "missing")
        XCTAssertEqual(debouncedRender?.projection.rows, [])
        XCTAssertEqual(debouncedRender?.projection.emptyReason, .noSearchMatches)
    }

    @MainActor
    private func waitForLoadedRender(
        in store: DockScreenStore,
        where predicate: @escaping (DockRenderSnapshot) -> Bool = { _ in true },
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> DockRenderSnapshot? {
        for _ in 0..<50 {
            if case .loaded(let render) = store.state,
               predicate(render) {
                return render
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for Dock render snapshot", file: file, line: line)
        return nil
    }

    private func makeSnapshot(host: DockHostConfiguration) -> DockSnapshot {
        let input = DockRenderInput(
            hosts: [host],
            hostStates: [
                DockHostStateViewModel(
                    host: DockHostViewModel(host: host),
                    status: .loaded(rowCount: 1)
                )
            ],
            sessionsByHostID: [
                host.id: [
                    dockStreamSession(
                        host: host,
                        threadID: "thread-a",
                        title: "Thread A",
                        updatedAt: 2_000
                    )
                ]
            ],
            isPartial: false
        )
        return DockRenderProjector(
            now: { Date(timeIntervalSince1970: 2_000) }
        ).snapshot(from: input, localMetadata: [:])
    }
}

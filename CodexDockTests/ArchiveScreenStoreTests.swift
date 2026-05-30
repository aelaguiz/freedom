import XCTest
@testable import CodexDock

final class ArchiveScreenStoreTests: XCTestCase {
    @MainActor
    func testArchiveStorePublishesRenderStateThroughScreenStore() async throws {
        let host = makeHost()
        let registry = try HostRegistry(hosts: [host])
        let loader = RecordingDockSessionLoader(results: [
            .success(
                DockLoadResult(
                    summaries: [
                        makeSummary(
                            hostID: host.id,
                            threadID: "thread-a",
                            branch: "main",
                            status: .notLoaded,
                            lastActivity: Date(timeIntervalSince1970: 2_000),
                            prompt: "Archived row"
                        )
                    ]
                )
            )
        ])
        let store = ArchiveStore(registry: registry, loader: loader)

        await store.load()

        guard case .loaded(let snapshot) = store.screenStore.state else {
            return XCTFail("Expected loaded archive screen state, got \(store.screenStore.state)")
        }
        XCTAssertEqual(snapshot.rowCount, 1)
        XCTAssertEqual(snapshot.sections[0].rows.map(\.title), ["Archived row"])
    }
}

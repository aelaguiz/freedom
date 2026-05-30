import XCTest
@testable import CodexDock

final class ArchiveDataEngineTests: XCTestCase {
    func testEngineLoadsArchivedRowsAndBuildsSortedSectionsOffMain() async throws {
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
        let engine = ArchiveDataEngine(
            registry: registry,
            loader: loader,
            metadataStore: InMemoryLocalThreadMetadataStore(),
            now: { Date(timeIntervalSince1970: 2_000) }
        )

        let snapshot = await engine.loadSnapshot()
        let archivedRequests = await loader.archivedRequests()

        XCTAssertEqual(snapshot.rowCount, 1)
        XCTAssertEqual(snapshot.sections.map(\.title), ["main"])
        XCTAssertEqual(snapshot.sections[0].rows.map(\.title), ["Archived row"])
        XCTAssertEqual(snapshot.hostStates.map(\.status), [.loaded(rowCount: 1)])
        XCTAssertEqual(archivedRequests, [true])
    }
}

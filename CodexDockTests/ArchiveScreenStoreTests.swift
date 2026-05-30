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

    @MainActor
    func testArchiveStoreBatchRestoreTracksPartialFailureWithoutFalseSuccess() async throws {
        let host = makeHost()
        let registry = try HostRegistry(hosts: [host])
        let loader = RecordingDockSessionLoader(results: [
            .success(
                DockLoadResult(
                    summaries: [
                        makeSummary(
                            hostID: host.id,
                            threadID: "restore-ok",
                            branch: "main",
                            status: .notLoaded,
                            lastActivity: Date(timeIntervalSince1970: 3_000),
                            prompt: "Restore ok"
                        ),
                        makeSummary(
                            hostID: host.id,
                            threadID: "restore-fails",
                            branch: "main",
                            status: .notLoaded,
                            lastActivity: Date(timeIntervalSince1970: 2_000),
                            prompt: "Restore fails"
                        )
                    ]
                )
            ),
            .success(
                DockLoadResult(
                    summaries: [
                        makeSummary(
                            hostID: host.id,
                            threadID: "restore-fails",
                            branch: "main",
                            status: .notLoaded,
                            lastActivity: Date(timeIntervalSince1970: 2_000),
                            prompt: "Restore fails"
                        )
                    ]
                )
            )
        ])
        let archiver = SelectiveRestoreArchiver(failingThreadIDs: ["restore-fails"])
        let store = ArchiveStore(registry: registry, loader: loader, archiver: archiver)

        await store.load()
        guard case .loaded(let snapshot) = store.state else {
            return XCTFail("Expected loaded archive state, got \(store.state)")
        }

        let rows = snapshot.sections.flatMap(\.rows)
        let results = await store.restoreRows(rows)
        let statuses = Dictionary(uniqueKeysWithValues: results.map { ($0.row.id.threadID, $0.status) })

        XCTAssertEqual(statuses["restore-ok"], .restored)
        XCTAssertEqual(statuses["restore-fails"], .failed("restore failed"))
        let unarchivedIDs = await archiver.unarchivedIDs()
        let archivedRequests = await loader.archivedRequests()
        XCTAssertEqual(Set(unarchivedIDs), ["restore-ok", "restore-fails"])
        XCTAssertEqual(archivedRequests, [true, true])
    }

    @MainActor
    func testArchiveStoreBatchRestoreStopRemainingSkipsRowsNotStarted() async throws {
        let host = makeHost()
        let registry = try HostRegistry(hosts: [host])
        let loader = RecordingDockSessionLoader(results: [
            .success(
                DockLoadResult(
                    summaries: [
                        makeSummary(
                            hostID: host.id,
                            threadID: "restore-one",
                            branch: "main",
                            status: .notLoaded,
                            lastActivity: Date(timeIntervalSince1970: 4_000),
                            prompt: "Restore one"
                        ),
                        makeSummary(
                            hostID: host.id,
                            threadID: "restore-two",
                            branch: "main",
                            status: .notLoaded,
                            lastActivity: Date(timeIntervalSince1970: 3_000),
                            prompt: "Restore two"
                        ),
                        makeSummary(
                            hostID: host.id,
                            threadID: "restore-three",
                            branch: "main",
                            status: .notLoaded,
                            lastActivity: Date(timeIntervalSince1970: 2_000),
                            prompt: "Restore three"
                        )
                    ]
                )
            ),
            .success(DockLoadResult(summaries: []))
        ])
        let archiver = SelectiveRestoreArchiver()
        let store = ArchiveStore(registry: registry, loader: loader, archiver: archiver)

        await store.load()
        guard case .loaded(let snapshot) = store.state else {
            return XCTFail("Expected loaded archive state, got \(store.state)")
        }

        var shouldStop = false
        let rows = snapshot.sections.flatMap(\.rows)
        let results = await store.restoreRows(
            rows,
            shouldStop: { shouldStop },
            onProgress: { partialResults in
                if partialResults.count == 1 {
                    shouldStop = true
                }
            }
        )

        XCTAssertEqual(results.map(\.status), [.restored, .skipped, .skipped])
        let unarchivedIDs = await archiver.unarchivedIDs()
        let archivedRequests = await loader.archivedRequests()
        XCTAssertEqual(unarchivedIDs, ["restore-one"])
        XCTAssertEqual(archivedRequests, [true, true])
    }
}

private actor SelectiveRestoreArchiver: DockSessionArchiving {
    private let failingThreadIDs: Set<String>
    private var unarchived: [String] = []

    init(failingThreadIDs: Set<String> = []) {
        self.failingThreadIDs = failingThreadIDs
    }

    func unarchivedIDs() -> [String] {
        unarchived
    }

    func archiveThread(_ threadID: String, on host: DockHostConfiguration) async throws {}

    func unarchiveThread(_ threadID: String, on host: DockHostConfiguration) async throws {
        unarchived.append(threadID)
        if failingThreadIDs.contains(threadID) {
            throw DockLoadFailure.error("restore failed")
        }
    }
}

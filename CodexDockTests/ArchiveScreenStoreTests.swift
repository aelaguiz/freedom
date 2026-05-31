import XCTest
@testable import CodexDock

final class ArchiveScreenStoreTests: XCTestCase {
    @MainActor
    func testArchiveStorePublishesRenderStateThroughScreenStore() async throws {
        let host = makeHost()
        let registry = try HostRegistry(hosts: [host])
        let loader = RecordingThreadCardFixtureLoader(results: [
            .success(
                ThreadCardFixtureResult(
                    fixtures: [
                        makeThreadCardFixtureSummary(
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
        let store = ArchiveStore(registry: registry, streamClient: LoaderBackedThreadCardStreamClient(loader: loader, view: .archive))

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
        let loader = RecordingThreadCardFixtureLoader(results: [
            .success(
                ThreadCardFixtureResult(
                    fixtures: [
                        makeThreadCardFixtureSummary(
                            hostID: host.id,
                            threadID: "restore-ok",
                            branch: "main",
                            status: .notLoaded,
                            lastActivity: Date(timeIntervalSince1970: 3_000),
                            prompt: "Restore ok"
                        ),
                        makeThreadCardFixtureSummary(
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
                ThreadCardFixtureResult(
                    fixtures: [
                        makeThreadCardFixtureSummary(
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
        let store = ArchiveStore(registry: registry, streamClient: LoaderBackedThreadCardStreamClient(loader: loader, view: .archive), archiver: archiver)

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
        XCTAssertEqual(archivedRequests, [.archive, .archive])
    }

    @MainActor
    func testArchiveStoreRestoreResolvesLogicalHostRowToEndpointHost() async throws {
        let host = makeHost(url: "ws://amir-m5.fairy-salmon.ts.net:4510")
        let registry = try HostRegistry(hosts: [host])
        let loader = RecordingThreadCardFixtureLoader(results: [
            .success(
                ThreadCardFixtureResult(
                    fixtures: [
                        makeThreadCardFixtureSummary(
                            hostID: "Amir-M5",
                            threadID: "restore-logical",
                            branch: "main",
                            status: .notLoaded,
                            lastActivity: Date(timeIntervalSince1970: 3_000),
                            prompt: "Restore logical host"
                        )
                    ]
                )
            ),
            .success(ThreadCardFixtureResult(fixtures: []))
        ])
        let archiver = SelectiveRestoreArchiver()
        let store = ArchiveStore(
            registry: registry,
            streamClient: LoaderBackedThreadCardStreamClient(loader: loader, view: .archive),
            archiver: archiver
        )

        await store.load()
        guard case .loaded(let snapshot) = store.state else {
            return XCTFail("Expected loaded archive state, got \(store.state)")
        }
        let row = try XCTUnwrap(snapshot.sections.first?.rows.first)
        XCTAssertEqual(row.id.hostID, "Amir-M5")
        XCTAssertEqual(row.sourceHostID, host.id)
        XCTAssertTrue(
            snapshot.hostIdentityResolver.contains(
                rowHostID: row.id.hostID,
                sourceConfiguredHostID: row.sourceHostID,
                in: host.id
            )
        )

        let results = await store.restoreRows([row])
        let unarchivedRequests = await archiver.unarchivedRequests()

        XCTAssertEqual(results.map(\.status), [.restored])
        XCTAssertEqual(unarchivedRequests.map(\.threadID), ["restore-logical"])
        XCTAssertEqual(unarchivedRequests.map(\.hostID), [host.id])
    }

    @MainActor
    func testArchiveStoreBatchRestoreStopRemainingSkipsRowsNotStarted() async throws {
        let host = makeHost()
        let registry = try HostRegistry(hosts: [host])
        let loader = RecordingThreadCardFixtureLoader(results: [
            .success(
                ThreadCardFixtureResult(
                    fixtures: [
                        makeThreadCardFixtureSummary(
                            hostID: host.id,
                            threadID: "restore-one",
                            branch: "main",
                            status: .notLoaded,
                            lastActivity: Date(timeIntervalSince1970: 4_000),
                            prompt: "Restore one"
                        ),
                        makeThreadCardFixtureSummary(
                            hostID: host.id,
                            threadID: "restore-two",
                            branch: "main",
                            status: .notLoaded,
                            lastActivity: Date(timeIntervalSince1970: 3_000),
                            prompt: "Restore two"
                        ),
                        makeThreadCardFixtureSummary(
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
            .success(ThreadCardFixtureResult(fixtures: []))
        ])
        let archiver = SelectiveRestoreArchiver()
        let store = ArchiveStore(registry: registry, streamClient: LoaderBackedThreadCardStreamClient(loader: loader, view: .archive), archiver: archiver)

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
        XCTAssertEqual(archivedRequests, [.archive, .archive])
    }
}

private actor SelectiveRestoreArchiver: ThreadArchiveCommanding {
    private let failingThreadIDs: Set<String>
    private var unarchived: [(threadID: String, hostID: String)] = []

    init(failingThreadIDs: Set<String> = []) {
        self.failingThreadIDs = failingThreadIDs
    }

    func unarchivedIDs() -> [String] {
        unarchived.map(\.threadID)
    }

    func unarchivedRequests() -> [(threadID: String, hostID: String)] {
        unarchived
    }

    func archiveThread(_ threadID: String, on host: DockHostConfiguration) async throws {}

    func unarchiveThread(_ threadID: String, on host: DockHostConfiguration) async throws {
        unarchived.append((threadID: threadID, hostID: host.id))
        if failingThreadIDs.contains(threadID) {
            throw DockRequestFailure.error("restore failed")
        }
    }
}

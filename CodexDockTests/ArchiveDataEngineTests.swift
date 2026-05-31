import XCTest
@testable import CodexDock

final class ArchiveDataEngineTests: XCTestCase {
    func testEngineLoadsArchivedRowsAndBuildsSortedSectionsOffMain() async throws {
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
        let engine = ArchiveDataEngine(
            registry: registry,
            streamClient: LoaderBackedThreadCardStreamClient(loader: loader, view: .archive),
            metadataStore: InMemoryLocalThreadMetadataStore(),
            now: { Date(timeIntervalSince1970: 2_000) }
        )

        let snapshot = await engine.loadSnapshot()
        let archivedRequests = await loader.archivedRequests()

        XCTAssertEqual(snapshot.rowCount, 1)
        XCTAssertEqual(snapshot.sections.map(\.title), ["main"])
        XCTAssertEqual(snapshot.sections[0].rows.map(\.title), ["Archived row"])
        XCTAssertEqual(snapshot.hostStates.map(\.status), [.loaded(rowCount: 1)])
        XCTAssertEqual(archivedRequests, [.archive])
    }

    func testEngineBuildsResolverForLogicalHostRowsLoadedFromEndpointHost() async throws {
        let host = makeHost(url: "ws://amir-m5.fairy-salmon.ts.net:4510")
        let registry = try HostRegistry(hosts: [host])
        let loader = RecordingThreadCardFixtureLoader(results: [
            .success(
                ThreadCardFixtureResult(
                    fixtures: [
                        makeThreadCardFixtureSummary(
                            hostID: "Amir-M5",
                            threadID: "thread-logical",
                            branch: "main",
                            status: .notLoaded,
                            lastActivity: Date(timeIntervalSince1970: 2_000),
                            prompt: "Archived logical row"
                        )
                    ]
                )
            )
        ])
        let engine = ArchiveDataEngine(
            registry: registry,
            streamClient: LoaderBackedThreadCardStreamClient(loader: loader, view: .archive),
            metadataStore: InMemoryLocalThreadMetadataStore(),
            now: { Date(timeIntervalSince1970: 2_000) }
        )

        let snapshot = await engine.loadSnapshot()
        let row = try XCTUnwrap(snapshot.sections.first?.rows.first)

        XCTAssertEqual(row.id.hostID, "Amir-M5")
        XCTAssertEqual(row.sourceHostID, host.id)
        XCTAssertEqual(row.hostDisplayName, "Amir-M5")
        XCTAssertEqual(row.hostEndpoint, host.endpoint.displayEndpoint)
        XCTAssertTrue(
            snapshot.hostIdentityResolver.contains(
                rowHostID: row.id.hostID,
                sourceConfiguredHostID: row.sourceHostID,
                in: host.id
            )
        )
    }

    func testEngineCollectsArchiveCatchupWindowsBeforeBuildingSnapshot() async throws {
        let host = makeHost()
        let registry = try HostRegistry(hosts: [host])
        let firstCard = threadCardFixture(
            host: host,
            threadID: "thread-a",
            title: "Archived first",
            updatedAt: 2_000
        )
        let secondCard = threadCardFixture(
            host: host,
            threadID: "thread-b",
            title: "Archived second",
            updatedAt: 1_000
        )
        let connection = ManualThreadCardStreamConnection(
            subscribeSnapshot: dockStreamSnapshot(
                host: host,
                epoch: "archive-catchup",
                seq: 1,
                cards: [firstCard],
                view: .archive,
                complete: false,
                totalRows: 2,
                window: DockStreamWindowDTO(offset: 0, limit: 1, rowCount: 1, nextOffset: 1)
            )
        )
        let engine = ArchiveDataEngine(
            registry: registry,
            streamClient: ManualThreadCardStreamClient(connection: connection),
            metadataStore: InMemoryLocalThreadMetadataStore(),
            now: { Date(timeIntervalSince1970: 2_000) }
        )

        let loadTask = Task {
            await engine.loadSnapshot()
        }
        await Task.yield()
        await connection.send(
            ThreadCardStreamUpdateDTO(
                kind: .delta,
                schemaVersion: CodexDockConstants.Dock.streamSchemaVersion,
                view: .archive,
                complete: true,
                totalRows: 2,
                window: DockStreamWindowDTO(offset: 1, limit: 1, rowCount: 1),
                stateGeneration: 2,
                epoch: "archive-catchup",
                baseSeq: 1,
                seq: 2,
                freshness: DockStreamFreshnessDTO(status: .fresh),
                upsertCards: [secondCard]
            )
        )

        let snapshot = await loadTask.value

        XCTAssertEqual(snapshot.rowCount, 2)
        XCTAssertEqual(snapshot.sections.flatMap(\.rows).map(\.title), ["Archived first", "Archived second"])
        XCTAssertEqual(snapshot.hostStates.map(\.status), [.loaded(rowCount: 2)])
    }
}

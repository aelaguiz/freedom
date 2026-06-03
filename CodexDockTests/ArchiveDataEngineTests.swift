import XCTest
@testable import CodexDock

final class ArchiveDataEngineTests: XCTestCase {
    func testEngineBuildsArchivedSectionsFromSharedStreamTable() async throws {
        let host = makeHost()
        let registry = try HostRegistry(hosts: [host])
        let engine = ArchiveDataEngine(
            registry: registry,
            metadataStore: InMemoryLocalThreadMetadataStore(),
            now: { Date(timeIntervalSince1970: 2_000) }
        )
        let card = threadCardFixture(
            host: host,
            threadID: "thread-a",
            title: "Archived row",
            status: .dormant,
            updatedAt: 2_000,
            view: .archive
        )

        await engine.loadLocalMetadata()
        await engine.ensureHosts()
        try await engine.apply(
            threadCardReconcilerSnapshot(dockStreamSnapshot(
                host: host,
                epoch: "archive-engine",
                seq: 1,
                cards: [card],
                view: .archive
            )),
            host: host
        )
        await engine.migrateMetadataHostAliases()
        let loadedSnapshot = await engine.snapshot()
        let snapshot = try XCTUnwrap(loadedSnapshot)

        XCTAssertEqual(snapshot.rowCount, 1)
        XCTAssertEqual(snapshot.sections.map(\.title), ["main"])
        XCTAssertEqual(snapshot.sections[0].rows.map(\.title), ["Archived row"])
        XCTAssertEqual(snapshot.hostStates.map(\.status), [.loaded(rowCount: 1)])
    }

    func testFreshWindowedArchiveSnapshotIsLoadedWithWindowAnnotation() async throws {
        let host = makeHost()
        let registry = try HostRegistry(hosts: [host])
        let engine = ArchiveDataEngine(
            registry: registry,
            metadataStore: InMemoryLocalThreadMetadataStore(),
            now: { Date(timeIntervalSince1970: 2_000) }
        )
        let card = threadCardFixture(
            host: host,
            threadID: "thread-windowed",
            title: "Archived windowed row",
            status: .dormant,
            updatedAt: 2_000,
            view: .archive
        )

        await engine.loadLocalMetadata()
        await engine.ensureHosts()
        try await engine.apply(
            threadCardReconcilerSnapshot(dockStreamSnapshot(
                host: host,
                epoch: "archive-windowed",
                seq: 1,
                cards: [card],
                view: .archive,
                complete: false,
                totalRows: 2,
                window: DockStreamWindowDTO(offset: 0, limit: 1, rowCount: 1, nextOffset: 1)
            )),
            host: host
        )

        let loadedSnapshot = await engine.snapshot()
        let snapshot = try XCTUnwrap(loadedSnapshot)

        XCTAssertEqual(snapshot.rowCount, 1)
        XCTAssertEqual(snapshot.hostStates.map(\.status), [.loaded(rowCount: 1, window: DockHostWindow(visibleRows: 1, totalRows: 2))])
    }

    func testEngineBuildsResolverForLogicalHostRowsLoadedFromEndpointHost() async throws {
        let host = makeHost(url: "ws://amir-m5.fairy-salmon.ts.net:4510")
        let registry = try HostRegistry(hosts: [host])
        let engine = ArchiveDataEngine(
            registry: registry,
            metadataStore: InMemoryLocalThreadMetadataStore(),
            now: { Date(timeIntervalSince1970: 2_000) }
        )
        let card = threadCardFixture(
            host: host,
            threadID: "thread-logical",
            title: "Archived logical row",
            status: .dormant,
            updatedAt: 2_000,
            logicalHostID: "Amir-M5",
            view: .archive
        )

        await engine.loadLocalMetadata()
        await engine.ensureHosts()
        try await engine.apply(
            threadCardReconcilerSnapshot(dockStreamSnapshot(
                host: host,
                epoch: "archive-logical",
                seq: 1,
                cards: [card],
                view: .archive
            )),
            host: host
        )
        let loadedSnapshot = await engine.snapshot()
        let snapshot = try XCTUnwrap(loadedSnapshot)
        let row = try XCTUnwrap(snapshot.sections.first?.rows.first)

        XCTAssertEqual(row.hostID, "Amir-M5")
        XCTAssertEqual(row.sourceHostID, "Amir-M5")
        XCTAssertEqual(row.hostDisplayName, "Amir-M5")
        XCTAssertEqual(row.hostEndpoint, host.endpoint.displayEndpoint)
        XCTAssertTrue(
            snapshot.hostIdentityResolver.contains(
                rowHostID: row.hostID,
                sourceConfiguredHostID: row.sourceHostID,
                in: host.id
            )
        )
    }

    func testEngineAppliesArchiveCatchupWindowsBeforeBuildingSnapshot() async throws {
        let host = makeHost()
        let registry = try HostRegistry(hosts: [host])
        let firstCard = threadCardFixture(
            host: host,
            threadID: "thread-a",
            title: "Archived first",
            updatedAt: 2_000,
            view: .archive
        )
        let secondCard = threadCardFixture(
            host: host,
            threadID: "thread-b",
            title: "Archived second",
            updatedAt: 1_000,
            view: .archive
        )
        let engine = ArchiveDataEngine(
            registry: registry,
            metadataStore: InMemoryLocalThreadMetadataStore(),
            now: { Date(timeIntervalSince1970: 2_000) }
        )

        await engine.loadLocalMetadata()
        await engine.ensureHosts()
        try await engine.apply(
            threadCardReconcilerSnapshot(dockStreamSnapshot(
                host: host,
                epoch: "archive-catchup",
                seq: 1,
                cards: [firstCard],
                view: .archive,
                complete: false,
                totalRows: 2,
                window: DockStreamWindowDTO(offset: 0, limit: 1, rowCount: 1, nextOffset: 1)
            )),
            host: host
        )
        try await engine.apply(
            threadCardReconcilerSnapshot(dockStreamSnapshot(
                host: host,
                epoch: "archive-catchup",
                seq: 2,
                cards: [firstCard, secondCard],
                view: .archive
            )),
            host: host
        )

        let loadedSnapshot = await engine.snapshot()
        let snapshot = try XCTUnwrap(loadedSnapshot)

        XCTAssertEqual(snapshot.rowCount, 2)
        XCTAssertEqual(snapshot.sections.flatMap(\.rows).map(\.title), ["Archived first", "Archived second"])
        XCTAssertEqual(snapshot.hostStates.map(\.status), [.loaded(rowCount: 2)])
    }
}

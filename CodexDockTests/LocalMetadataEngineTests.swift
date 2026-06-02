import XCTest
@testable import CodexDock

final class LocalMetadataEngineTests: XCTestCase {
    func testEnginePersistsPinnedMetadataAndReordersVisibleRows() async throws {
        let store = InMemoryLocalThreadMetadataStore()
        let engine = LocalMetadataEngine(
            store: store,
            now: { Date(timeIntervalSince1970: 1_000) }
        )
        let rowA = makeRow(threadID: "thread-a", title: "Thread A")
        let rowB = makeRow(threadID: "thread-b", title: "Thread B")

        _ = try await engine.setPinned(true, for: rowA)
        _ = try await engine.setPinned(true, for: rowB)
        let reordered = try await engine.reorderPinnedRows([rowB, rowA])

        XCTAssertEqual(reordered[rowB.metadataKey]?.pinnedOrder, 0)
        XCTAssertEqual(reordered[rowA.metadataKey]?.pinnedOrder, 1)
        let storedValues = await store.valuesSnapshot()
        XCTAssertEqual(storedValues, reordered)
    }

    func testEngineRemovesEmptyMetadataAfterClearingLabelAndRail() async throws {
        let row = makeRow(threadID: "thread-a", title: "Thread A")
        let store = InMemoryLocalThreadMetadataStore(values: [
            row.metadataKey: LocalThreadMetadata(label: "Watch", rail: .red)
        ])
        let engine = LocalMetadataEngine(store: store)

        _ = try await engine.load()
        _ = try await engine.setLabel(nil, for: row.metadataKey)
        let values = try await engine.setRail(nil, for: row.metadataKey)
        let storedValues = await store.valuesSnapshot()

        XCTAssertNil(values[row.metadataKey])
        XCTAssertNil(storedValues[row.metadataKey])
    }

    func testMigrateHostAliasesMovesEndpointMetadataToLogicalHostID() async throws {
        let host = try DockHostConfiguration(host: "amir-m5.fairy-salmon.ts.net", port: 4510)
        let oldKey = LocalThreadMetadataKey(
            hostID: host.id,
            backendSessionID: "backend-thread-a",
            threadID: "thread-a"
        )
        let newKey = LocalThreadMetadataKey(
            hostID: "Amir-M5",
            backendSessionID: "backend-thread-a",
            threadID: "thread-a"
        )
        let store = InMemoryLocalThreadMetadataStore(values: [
            oldKey: LocalThreadMetadata(label: "Watch", rail: .red)
        ])
        let resolver = DockHostIdentityResolver(
            hosts: [host],
            observations: [
                DockHostIdentityObservation(
                    configuredHostID: host.id,
                    streamHostID: "Amir-M5",
                    logicalHostID: "Amir-M5",
                    displayName: "Amir-M5",
                    endpoint: host.endpoint.displayEndpoint
                )
            ]
        )
        let engine = LocalMetadataEngine(store: store)

        _ = try await engine.load()
        let values = try await engine.migrateHostAliases(using: resolver)

        XCTAssertNil(values[oldKey])
        XCTAssertEqual(values[newKey]?.label, "Watch")
        XCTAssertEqual(values[newKey]?.rail, .red)
        let storedValues = await store.valuesSnapshot()
        XCTAssertEqual(storedValues, values)
    }

    func testMigrateHostAliasesPreservesLogicalMetadataOnCollision() async throws {
        let host = try DockHostConfiguration(host: "alpha.local", port: 4510)
        let oldKey = LocalThreadMetadataKey(
            hostID: host.id,
            backendSessionID: "backend-thread-a",
            threadID: "thread-a"
        )
        let logicalKey = LocalThreadMetadataKey(
            hostID: "zeta",
            backendSessionID: "backend-thread-a",
            threadID: "thread-a"
        )
        let store = InMemoryLocalThreadMetadataStore(values: [
            oldKey: LocalThreadMetadata(
                label: "Old endpoint label",
                rail: .red,
                isPinned: true,
                pinnedAt: Date(timeIntervalSince1970: 200),
                pinnedOrder: 4
            ),
            logicalKey: LocalThreadMetadata(
                label: "Logical label",
                rail: .green,
                isPinned: true,
                pinnedAt: Date(timeIntervalSince1970: 100),
                pinnedOrder: 2
            )
        ])
        let resolver = DockHostIdentityResolver(
            hosts: [host],
            observations: [
                DockHostIdentityObservation(
                    configuredHostID: host.id,
                    streamHostID: "zeta",
                    logicalHostID: "zeta",
                    displayName: "Zeta",
                    endpoint: host.endpoint.displayEndpoint
                )
            ]
        )
        let engine = LocalMetadataEngine(store: store)

        _ = try await engine.load()
        let values = try await engine.migrateHostAliases(using: resolver)

        XCTAssertNil(values[oldKey])
        XCTAssertEqual(values[logicalKey]?.label, "Logical label")
        XCTAssertEqual(values[logicalKey]?.rail, .green)
        XCTAssertEqual(values[logicalKey]?.pinnedAt, Date(timeIntervalSince1970: 100))
        XCTAssertEqual(values[logicalKey]?.pinnedOrder, 0)
    }

    func testMigrateHostAliasesDoesNotGuessWithoutObservedLogicalHostID() async throws {
        let host = try DockHostConfiguration(host: "amir-m5.fairy-salmon.ts.net", port: 4510)
        let endpointKey = LocalThreadMetadataKey(
            hostID: host.id,
            backendSessionID: "backend-endpoint-thread",
            threadID: "endpoint-thread"
        )
        let displayKey = LocalThreadMetadataKey(
            hostID: host.displayName,
            backendSessionID: "backend-display-thread",
            threadID: "display-thread"
        )
        let initialValues = [
            endpointKey: LocalThreadMetadata(label: "Endpoint", rail: .red),
            displayKey: LocalThreadMetadata(label: "Display", rail: .green)
        ]
        let store = InMemoryLocalThreadMetadataStore(values: initialValues)
        let resolver = DockHostIdentityResolver(hosts: [host])
        let engine = LocalMetadataEngine(store: store)

        _ = try await engine.load()
        let values = try await engine.migrateHostAliases(using: resolver)

        XCTAssertEqual(values, initialValues)
        let storedValues = await store.valuesSnapshot()
        XCTAssertEqual(storedValues, initialValues)
    }

    private func makeRow(
        threadID: String,
        title: String
    ) -> DockRowViewModel {
        let projectionID = "host:host-a/thread:\(threadID)/row:threadCard"
        return DockRowViewModel(
            threadIdentity: HostScopedThreadID(hostID: "host-a", threadID: threadID),
            projectionID: projectionID,
            backendSessionID: "backend-\(threadID)",
            title: title,
            hostDisplayName: "Host A",
            hostEndpoint: "127.0.0.1:4510",
            repository: "codex-client",
            branch: "main",
            status: .running,
            lastActivity: "now",
            lastActivityDate: Date(timeIntervalSince1970: 1_000),
            displayOrderKey: "9999999999000000|0001|\(projectionID)",
            summary: "summary",
            rail: .blue,
            label: nil,
            origin: .humanInteractive(subtype: .cli)
        )
    }
}

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
        XCTAssertEqual(reordered[rowA.metadataKey]?.lastKnownPinnedDisplay?.title, "Thread A")
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

    private func makeRow(
        threadID: String,
        title: String
    ) -> DockRowViewModel {
        DockRowViewModel(
            id: HostScopedThreadID(hostID: "host-a", threadID: threadID),
            backendSessionID: "backend-\(threadID)",
            title: title,
            hostDisplayName: "Host A",
            hostEndpoint: "127.0.0.1:4510",
            repository: "codex-client",
            branch: "main",
            status: .running,
            lastActivity: "now",
            lastActivityDate: Date(timeIntervalSince1970: 1_000),
            summary: "summary",
            rail: .blue,
            label: nil,
            origin: .humanInteractive(subtype: .cli)
        )
    }
}

import XCTest
@testable import CodexDock

final class ThreadDetailDataEngineTests: XCTestCase {
    func testReplaceUsesRelayProjectionOrder() async throws {
        let engine = ThreadDetailDataEngine()
        let snapshot = projectionSnapshot(rows: [
            projectionRow(id: "old", body: "Old", order: "002"),
            projectionRow(id: "new", body: "New", order: "001"),
        ])

        let loaded = try await engine.replace(from: snapshot, expectedThreadID: "thread-1")

        XCTAssertEqual(loaded.events.map(\.body), ["New", "Old"])
        XCTAssertNil(loaded.activeTurnID)
    }

    func testUpsertReplacesSameProjectionID() async throws {
        let engine = ThreadDetailDataEngine()
        _ = try await engine.replace(
            from: projectionSnapshot(rows: [projectionRow(id: "agent-1", body: "hello", order: "001")]),
            expectedThreadID: "thread-1"
        )

        let updated = try await engine.apply(
            update: projectionUpdate(
                seq: 2,
                rows: [projectionRow(id: "agent-1", body: "hello world", order: "001", revision: 2)]
            ),
            expectedThreadID: "thread-1"
        )

        XCTAssertEqual(updated.events.map(\.body), ["hello world"])
    }

    func testDeleteRemovesProjectionID() async throws {
        let engine = ThreadDetailDataEngine()
        _ = try await engine.replace(
            from: projectionSnapshot(rows: [
                projectionRow(id: "keep", body: "Keep", order: "001"),
                projectionRow(id: "delete", body: "Delete", order: "002"),
            ]),
            expectedThreadID: "thread-1"
        )

        let updated = try await engine.apply(
            update: projectionUpdate(kind: .delete, seq: 2, projectionIDs: [
                "host:test-host/thread:thread-1/turn:turn-1/item:delete/row:agentMessage",
            ]),
            expectedThreadID: "thread-1"
        )

        XCTAssertEqual(updated.events.map(\.body), ["Keep"])
    }

    func testSequenceGapThrowsInsteadOfGuessing() async throws {
        let engine = ThreadDetailDataEngine()
        _ = try await engine.replace(from: projectionSnapshot(rows: []), expectedThreadID: "thread-1")

        await XCTAssertThrowsErrorAsync(
            try await engine.apply(
                update: projectionUpdate(seq: 3, rows: [projectionRow(id: "agent-1", body: "Late", order: "001")]),
                expectedThreadID: "thread-1"
            )
        )
    }

    func testResyncRequiredThrowsInsteadOfMutatingRows() async throws {
        let engine = ThreadDetailDataEngine()
        _ = try await engine.replace(from: projectionSnapshot(rows: []), expectedThreadID: "thread-1")

        await XCTAssertThrowsErrorAsync(
            try await engine.apply(
                update: projectionUpdate(kind: .resyncRequired, seq: 2, reason: "gap"),
                expectedThreadID: "thread-1"
            )
        )
    }

    func testReplaceRejectsMissingDisplayOrderKey() async throws {
        let engine = ThreadDetailDataEngine()

        await XCTAssertThrowsErrorAsync(
            try await engine.replace(
                from: projectionSnapshot(rows: [projectionRow(id: "agent-1", body: "Bad", order: "")]),
                expectedThreadID: "thread-1"
            )
        )
    }

    func testUpdateRejectsDifferentViewParamsKey() async throws {
        let engine = ThreadDetailDataEngine()
        _ = try await engine.replace(from: projectionSnapshot(rows: []), expectedThreadID: "thread-1")

        await XCTAssertThrowsErrorAsync(
            try await engine.apply(
                update: projectionUpdate(seq: 2, rows: [
                    projectionRow(id: "agent-1", body: "Bad", order: "001"),
                ], viewParamsKey: "different-view"),
                expectedThreadID: "thread-1"
            )
        )
    }

    func testReplaceRejectsProjectionEngineVersionDrift() async throws {
        let engine = ThreadDetailDataEngine()

        await XCTAssertThrowsErrorAsync(
            try await engine.replace(
                from: projectionSnapshot(rows: [], projectionEngineVersion: 2),
                expectedThreadID: "thread-1"
            )
        )
    }

    func testUpdateRejectsProjectionEngineVersionDrift() async throws {
        let engine = ThreadDetailDataEngine()
        _ = try await engine.replace(from: projectionSnapshot(rows: []), expectedThreadID: "thread-1")

        await XCTAssertThrowsErrorAsync(
            try await engine.apply(
                update: projectionUpdate(seq: 2, projectionEngineVersion: 2),
                expectedThreadID: "thread-1"
            )
        )
    }

    func testReplaceRejectsRowProjectionEngineVersionDrift() async throws {
        let engine = ThreadDetailDataEngine()

        await XCTAssertThrowsErrorAsync(
            try await engine.replace(
                from: projectionSnapshot(rows: [
                    projectionRow(
                        id: "agent-1",
                        body: "Bad row",
                        order: "001",
                        projectionEngineVersion: 2
                    ),
                ]),
                expectedThreadID: "thread-1"
            )
        )
    }

    func testReplaceRejectsDuplicateSourceIdentityWithDifferentProjectionIDs() async throws {
        let engine = ThreadDetailDataEngine()
        let sourceRef = "host:test-host/thread:thread-1/turn:turn-1/item:shared-source"

        await XCTAssertThrowsErrorAsync(
            try await engine.replace(
                from: projectionSnapshot(rows: [
                    projectionRow(id: "agent-1", body: "first", order: "001", sourceRef: sourceRef),
                    projectionRow(id: "agent-2", body: "duplicate", order: "002", sourceRef: sourceRef),
                ]),
                expectedThreadID: "thread-1"
            )
        )
    }

    func testUpsertRejectsStaleRevisionForSameProjectionID() async throws {
        let engine = ThreadDetailDataEngine()
        _ = try await engine.replace(
            from: projectionSnapshot(rows: [
                projectionRow(id: "agent-1", body: "newer", order: "001", revision: 3),
            ]),
            expectedThreadID: "thread-1"
        )

        await XCTAssertThrowsErrorAsync(
            try await engine.apply(
                update: projectionUpdate(
                    seq: 2,
                    rows: [projectionRow(id: "agent-1", body: "older", order: "001", revision: 2)]
                ),
                expectedThreadID: "thread-1"
            )
        )
    }

    func testUpsertRejectsSameRevisionWithDifferentContent() async throws {
        let engine = ThreadDetailDataEngine()
        _ = try await engine.replace(
            from: projectionSnapshot(rows: [
                projectionRow(id: "agent-1", body: "first", order: "001", revision: 3),
            ]),
            expectedThreadID: "thread-1"
        )

        await XCTAssertThrowsErrorAsync(
            try await engine.apply(
                update: projectionUpdate(
                    seq: 2,
                    rows: [projectionRow(id: "agent-1", body: "changed", order: "001", revision: 3)]
                ),
                expectedThreadID: "thread-1"
            )
        )
    }

    func testUpsertRejectsDuplicateSourceIdentityWithDifferentProjectionID() async throws {
        let engine = ThreadDetailDataEngine()
        let sourceRef = "host:test-host/thread:thread-1/turn:turn-1/item:shared-source"
        _ = try await engine.replace(
            from: projectionSnapshot(rows: [
                projectionRow(id: "agent-1", body: "first", order: "001", sourceRef: sourceRef),
            ]),
            expectedThreadID: "thread-1"
        )

        await XCTAssertThrowsErrorAsync(
            try await engine.apply(
                update: projectionUpdate(
                    seq: 2,
                    rows: [projectionRow(id: "agent-2", body: "duplicate", order: "002", sourceRef: sourceRef)]
                ),
                expectedThreadID: "thread-1"
            )
        )
    }

    func testUpsertRejectsImmutableSourceRefDriftForSameProjectionID() async throws {
        let engine = ThreadDetailDataEngine()
        _ = try await engine.replace(
            from: projectionSnapshot(rows: [
                projectionRow(id: "agent-1", body: "first", order: "001", revision: 3),
            ]),
            expectedThreadID: "thread-1"
        )

        await XCTAssertThrowsErrorAsync(
            try await engine.apply(
                update: projectionUpdate(
                    seq: 2,
                    rows: [
                        projectionRow(
                            id: "agent-1",
                            body: "changed",
                            order: "001",
                            revision: 4,
                            sourceRef: "host:test-host/thread:thread-1/turn:other/item:agent-1"
                        ),
                    ]
                ),
                expectedThreadID: "thread-1"
            )
        )
    }

    private func projectionSnapshot(
        rows: [ThreadDetailEventDTO],
        activeTurnID: String? = nil,
        projectionEngineVersion: Int = 1
    ) -> ThreadDetailSnapshotDTO {
        ThreadDetailSnapshotDTO(
            projectionEngineVersion: projectionEngineVersion,
            sourceHostID: "test-host",
            threadID: "thread-1",
            epoch: "epoch-1",
            seq: 1,
            viewParamsKey: "default-view",
            activeTurnID: activeTurnID,
            order: "displayOrderKeyAscending",
            rows: rows
        )
    }

    private func projectionUpdate(
        kind: ThreadDetailUpdateKind = .upsert,
        seq: Int64,
        rows: [ThreadDetailEventDTO] = [],
        projectionIDs: [String] = [],
        activeTurnID: String? = nil,
        reason: String? = nil,
        viewParamsKey: String = "default-view",
        projectionEngineVersion: Int = 1
    ) -> ThreadDetailUpdateDTO {
        ThreadDetailUpdateDTO(
            kind: kind,
            projectionEngineVersion: projectionEngineVersion,
            sourceHostID: "test-host",
            threadID: "thread-1",
            epoch: "epoch-1",
            seq: seq,
            viewParamsKey: viewParamsKey,
            order: "displayOrderKeyAscending",
            rows: rows,
            projectionIDs: projectionIDs,
            activeTurnID: activeTurnID,
            reason: reason
        )
    }

    private func projectionRow(
        id: String,
        body: String,
        order: String,
        projectionEngineVersion: Int = 1,
        revision: Int = 1,
        sourceRef: String? = nil
    ) -> ThreadDetailEventDTO {
        let projectionID = "host:test-host/thread:thread-1/turn:turn-1/item:\(id)/row:agentMessage"
        return ThreadDetailEventDTO(
            projectionEngineVersion: projectionEngineVersion,
            sourceHostID: "test-host",
            threadID: "thread-1",
            projectionID: projectionID,
            sourceRef: sourceRef ?? "host:test-host/thread:thread-1/turn:turn-1/item:\(id)",
            itemType: "agentMessage",
            rowRole: "agentMessage",
            visibility: .message,
            renderKind: .agentMessage,
            displayOrderKey: order,
            title: "Agent message",
            body: body,
            eventTime: "2026-06-01T00:00:00.000Z",
            activityTime: "2026-06-01T00:00:00.000Z",
            turnID: "turn-1",
            itemID: id,
            turnOrder: 0,
            itemOrder: 0,
            rowOrder: 0,
            revision: revision,
            renderState: .settled
        )
    }
}

func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {}
}

import XCTest
@testable import CodexDock

final class ProjectionReducerTests: XCTestCase {
    func testSnapshotLoadsRowsInRelayOrder() throws {
        var reducer = ProjectionReducer<ThreadDetailEventDTO>()

        try reducer.apply(snapshot(rows: [
            row("old", body: "Old", order: "002"),
            row("new", body: "New", order: "001"),
        ]), policy: policy)

        XCTAssertEqual(reducer.seq, 1)
        XCTAssertEqual(reducer.sortedRows(policy: policy).map(\.body), ["New", "Old"])
    }

    func testPageExtendsCatchupWindowWithoutAdvancingSequence() throws {
        var reducer = ProjectionReducer<ThreadDetailEventDTO>()

        try reducer.apply(snapshot(rows: [
            row("new", body: "New", order: "001"),
        ], complete: false, totalRows: 2, window: window(offset: 0, rowCount: 1, nextOffset: 1)), policy: policy)
        try reducer.apply(page(rows: [
            row("old", body: "Old", order: "002"),
        ], totalRows: 2, window: window(offset: 1, rowCount: 1)), policy: policy)

        XCTAssertEqual(reducer.seq, 1)
        XCTAssertEqual(reducer.sortedRows(policy: policy).map(\.body), ["New", "Old"])
    }

    func testUpsertDeleteHeartbeatAndResyncRequiredUseOneEnvelopeLaw() throws {
        var reducer = ProjectionReducer<ThreadDetailEventDTO>()
        try reducer.apply(snapshot(rows: [
            row("message", body: "Draft", order: "001", revision: 1),
        ]), policy: policy)

        try reducer.apply(update(seq: 2, rows: [
            row("message", body: "Final", order: "001", revision: 2),
        ]), policy: policy)
        XCTAssertEqual(reducer.sortedRows(policy: policy).map(\.body), ["Final"])

        try reducer.apply(delete(seq: 3, ids: [projectionID("message")]), policy: policy)
        XCTAssertEqual(reducer.rowCount, 0)

        try reducer.apply(heartbeat(seq: 3), policy: policy)
        XCTAssertEqual(reducer.seq, 3)

        XCTAssertEqual(
            projectionError {
                try reducer.apply(resyncRequired(seq: 3, reason: "forced"), policy: policy)
            },
            .resyncRequired("forced")
        )
    }

    func testRejectsEpochChange() throws {
        var reducer = try seededReducer()

        XCTAssertEqual(
            projectionError {
                try reducer.apply(update(epoch: "epoch-2", seq: 2), policy: policy)
            },
            .epochMismatch(expected: "epoch-1", actual: "epoch-2")
        )
    }

    func testRejectsSequenceGap() throws {
        var reducer = try seededReducer()

        XCTAssertEqual(
            projectionError {
                try reducer.apply(update(seq: 3), policy: policy)
            },
            .sequenceGap(expected: 2, actual: 3)
        )
    }

    func testRejectsDuplicateProjectionID() {
        var reducer = ProjectionReducer<ThreadDetailEventDTO>()

        XCTAssertStreamContract {
            try reducer.apply(snapshot(rows: [
                row("same", body: "First", order: "001", sourceRef: "source-a"),
                row("same", body: "Second", order: "002", sourceRef: "source-b"),
            ]), policy: policy)
        }
    }

    func testRejectsDuplicateSourceIdentity() {
        var reducer = ProjectionReducer<ThreadDetailEventDTO>()

        XCTAssertStreamContract {
            try reducer.apply(snapshot(rows: [
                row("first", body: "First", order: "001", sourceRef: "shared-source"),
                row("second", body: "Second", order: "002", sourceRef: "shared-source"),
            ]), policy: policy)
        }
    }

    func testRejectsImmutableIdentityChangeForExistingProjectionID() throws {
        var reducer = try seededReducer()

        XCTAssertStreamContract {
            try reducer.apply(update(seq: 2, rows: [
                row("seed", body: "Changed", order: "001", revision: 2, sourceRef: "different-source"),
            ]), policy: policy)
        }
    }

    func testRejectsStaleRevision() throws {
        var reducer = ProjectionReducer<ThreadDetailEventDTO>()
        try reducer.apply(snapshot(rows: [
            row("seed", body: "Newer", order: "001", revision: 3),
        ]), policy: policy)

        XCTAssertStreamContract {
            try reducer.apply(update(seq: 2, rows: [
                row("seed", body: "Older", order: "001", revision: 2),
            ]), policy: policy)
        }
    }

    func testRejectsWrongSourceHost() throws {
        var reducer = try seededReducer()

        XCTAssertStreamContract {
            try reducer.apply(update(sourceHostID: "other-host", seq: 2), policy: policy)
        }
    }

    func testRejectsWrongView() {
        var reducer = ProjectionReducer<ThreadDetailEventDTO>()

        XCTAssertStreamContract {
            try reducer.apply(snapshot(view: "thread.other", rows: []), policy: policy)
        }
    }

    func testRejectsWrongViewParamsKey() throws {
        var reducer = try seededReducer()

        XCTAssertStreamContract {
            try reducer.apply(update(viewParamsKey: "different-view", seq: 2), policy: policy)
        }
    }

    func testRejectsWrongOrder() {
        var reducer = ProjectionReducer<ThreadDetailEventDTO>()

        XCTAssertStreamContract {
            try reducer.apply(snapshot(order: "updatedAtDescending", rows: []), policy: policy)
        }
    }

    func testRejectsMalformedWindow() throws {
        var reducer = try seededReducer()

        XCTAssertStreamContract {
            try reducer.apply(page(
                rows: [row("old", body: "Old", order: "002")],
                totalRows: 2,
                window: window(offset: 1, rowCount: 2)
            ), policy: policy)
        }
    }

    private var policy: ProjectionReducerPolicy<ThreadDetailEventDTO> {
        .threadDetail(threadID: "thread-1")
    }

    private func seededReducer() throws -> ProjectionReducer<ThreadDetailEventDTO> {
        var reducer = ProjectionReducer<ThreadDetailEventDTO>()
        try reducer.apply(snapshot(rows: [
            row("seed", body: "Seed", order: "001", revision: 1),
        ]), policy: policy)
        return reducer
    }

    private func snapshot(
        sourceHostID: String = "test-host",
        view: String = "thread.detail",
        viewParamsKey: String = "thread:thread-1",
        order: String = "displayOrderKeyAscending",
        epoch: String = "epoch-1",
        seq: Int64 = 1,
        rows: [ThreadDetailEventDTO],
        complete: Bool = true,
        totalRows: Int? = nil,
        window: ProjectionWindow? = nil
    ) -> ProjectionEnvelope<ThreadDetailEventDTO> {
        ProjectionEnvelope(
            kind: .snapshot,
            schemaVersion: ThreadDetailProjectionContract.schemaVersion,
            identityVersion: ThreadDetailProjectionContract.identityVersion,
            projectionEngineVersion: ThreadDetailProjectionContract.projectionEngineVersion,
            sourceHostID: sourceHostID,
            view: view,
            threadID: "thread-1",
            scope: "thread",
            viewParamsKey: viewParamsKey,
            order: order,
            epoch: epoch,
            seq: seq,
            generation: 1,
            rows: rows,
            projectionIDs: [],
            complete: complete,
            totalRows: totalRows ?? rows.count,
            window: window ?? ProjectionWindow(offset: 0, limit: rows.count, rowCount: rows.count, nextOffset: nil),
            reason: nil
        )
    }

    private func page(
        sourceHostID: String = "test-host",
        viewParamsKey: String = "thread:thread-1",
        epoch: String = "epoch-1",
        seq: Int64 = 1,
        rows: [ThreadDetailEventDTO],
        totalRows: Int,
        window: ProjectionWindow
    ) -> ProjectionEnvelope<ThreadDetailEventDTO> {
        ProjectionEnvelope(
            kind: .page,
            schemaVersion: ThreadDetailProjectionContract.schemaVersion,
            identityVersion: ThreadDetailProjectionContract.identityVersion,
            projectionEngineVersion: ThreadDetailProjectionContract.projectionEngineVersion,
            sourceHostID: sourceHostID,
            view: ThreadDetailProjectionContract.view,
            threadID: "thread-1",
            scope: "thread",
            viewParamsKey: viewParamsKey,
            order: ThreadDetailProjectionContract.order,
            epoch: epoch,
            seq: seq,
            generation: 1,
            rows: rows,
            projectionIDs: [],
            complete: true,
            totalRows: totalRows,
            window: window,
            reason: nil
        )
    }

    private func update(
        sourceHostID: String = "test-host",
        viewParamsKey: String = "thread:thread-1",
        epoch: String = "epoch-1",
        seq: Int64,
        rows: [ThreadDetailEventDTO] = []
    ) -> ProjectionEnvelope<ThreadDetailEventDTO> {
        ProjectionEnvelope(
            kind: .upsert,
            schemaVersion: ThreadDetailProjectionContract.schemaVersion,
            identityVersion: ThreadDetailProjectionContract.identityVersion,
            projectionEngineVersion: ThreadDetailProjectionContract.projectionEngineVersion,
            sourceHostID: sourceHostID,
            view: ThreadDetailProjectionContract.view,
            threadID: "thread-1",
            scope: "thread",
            viewParamsKey: viewParamsKey,
            order: ThreadDetailProjectionContract.order,
            epoch: epoch,
            seq: seq,
            generation: 1,
            rows: rows,
            projectionIDs: [],
            complete: nil,
            totalRows: nil,
            window: nil,
            reason: nil
        )
    }

    private func delete(seq: Int64, ids: [String]) -> ProjectionEnvelope<ThreadDetailEventDTO> {
        ProjectionEnvelope(
            kind: .delete,
            schemaVersion: ThreadDetailProjectionContract.schemaVersion,
            identityVersion: ThreadDetailProjectionContract.identityVersion,
            projectionEngineVersion: ThreadDetailProjectionContract.projectionEngineVersion,
            sourceHostID: "test-host",
            view: ThreadDetailProjectionContract.view,
            threadID: "thread-1",
            scope: "thread",
            viewParamsKey: "thread:thread-1",
            order: ThreadDetailProjectionContract.order,
            epoch: "epoch-1",
            seq: seq,
            generation: 1,
            rows: [],
            projectionIDs: ids,
            complete: nil,
            totalRows: nil,
            window: nil,
            reason: nil
        )
    }

    private func heartbeat(seq: Int64) -> ProjectionEnvelope<ThreadDetailEventDTO> {
        ProjectionEnvelope(
            kind: .heartbeat,
            schemaVersion: ThreadDetailProjectionContract.schemaVersion,
            identityVersion: ThreadDetailProjectionContract.identityVersion,
            projectionEngineVersion: ThreadDetailProjectionContract.projectionEngineVersion,
            sourceHostID: "test-host",
            view: ThreadDetailProjectionContract.view,
            threadID: "thread-1",
            scope: "thread",
            viewParamsKey: "thread:thread-1",
            order: ThreadDetailProjectionContract.order,
            epoch: "epoch-1",
            seq: seq,
            generation: 1,
            rows: [],
            projectionIDs: [],
            complete: nil,
            totalRows: nil,
            window: nil,
            reason: nil
        )
    }

    private func resyncRequired(seq: Int64, reason: String) -> ProjectionEnvelope<ThreadDetailEventDTO> {
        ProjectionEnvelope(
            kind: .resyncRequired,
            schemaVersion: ThreadDetailProjectionContract.schemaVersion,
            identityVersion: ThreadDetailProjectionContract.identityVersion,
            projectionEngineVersion: ThreadDetailProjectionContract.projectionEngineVersion,
            sourceHostID: "test-host",
            view: ThreadDetailProjectionContract.view,
            threadID: "thread-1",
            scope: "thread",
            viewParamsKey: "thread:thread-1",
            order: ThreadDetailProjectionContract.order,
            epoch: "epoch-1",
            seq: seq,
            generation: 1,
            rows: [],
            projectionIDs: [],
            complete: nil,
            totalRows: nil,
            window: nil,
            reason: reason
        )
    }

    private func row(
        _ id: String,
        body: String,
        order: String,
        revision: Int = 1,
        sourceRef: String? = nil
    ) -> ThreadDetailEventDTO {
        ThreadDetailEventDTO(
            sourceHostID: "test-host",
            threadID: "thread-1",
            projectionID: projectionID(id),
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

    private func projectionID(_ id: String) -> String {
        "host:test-host/thread:thread-1/turn:turn-1/item:\(id)/row:agentMessage"
    }

    private func window(offset: Int, rowCount: Int, nextOffset: Int? = nil) -> ProjectionWindow {
        ProjectionWindow(offset: offset, limit: rowCount, rowCount: rowCount, nextOffset: nextOffset)
    }
}

private func projectionError(_ body: () throws -> Void) -> ProjectionReducerError? {
    do {
        try body()
        return nil
    } catch let error as ProjectionReducerError {
        return error
    } catch {
        XCTFail("Expected ProjectionReducerError, got \(error)")
        return nil
    }
}

private func XCTAssertStreamContract(
    _ body: () throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard case .streamContract = projectionError(body) else {
        XCTFail("Expected stream contract error", file: file, line: line)
        return
    }
}

import Foundation
import XCTest
@testable import CodexDock

final class ProjectionRuntimeTests: XCTestCase {
    func testInitialSubscribePublishesLiveRows() async throws {
        let fixture = RuntimeFixture()
        let reconciler = fixture.reconciler(
            subscribe: fixture.snapshot(rows: [
                fixture.row("old", body: "Old", order: "002"),
                fixture.row("new", body: "New", order: "001"),
            ])
        )

        await reconciler.start()
        let snapshot = await reconciler.snapshot()

        XCTAssertEqual(snapshot.freshness, .live)
        XCTAssertEqual(snapshot.rows.map(\.body), ["New", "Old"])
        XCTAssertEqual(snapshot.seq, 1)
    }

    func testManualRefreshUsesCanonicalResyncPath() async throws {
        let fixture = RuntimeFixture()
        let connection = fixture.connection(
            subscribe: fixture.snapshot(rows: []),
            resyncs: [
                fixture.snapshot(seq: 2, rows: [
                    fixture.row("manual", body: "Manual", order: "001"),
                ]),
            ]
        )
        let reconciler = fixture.reconciler(connection: connection)

        await reconciler.start()
        await reconciler.manualRefresh()

        let refreshed = await reconciler.snapshot()
        let resyncReasons = await connection.resyncReasons()
        XCTAssertEqual(resyncReasons, [.manualRefresh])
        XCTAssertEqual(refreshed.rows.map(\.body), ["Manual"])
    }

    func testForegroundResumeUsesCanonicalResyncPath() async throws {
        let fixture = RuntimeFixture()
        let connection = fixture.connection(
            subscribe: fixture.snapshot(rows: []),
            resyncs: [fixture.snapshot(seq: 2, rows: [])]
        )
        let reconciler = fixture.reconciler(connection: connection)

        await reconciler.start()
        await reconciler.foregroundResumed()

        let resyncReasons = await connection.resyncReasons()
        XCTAssertEqual(resyncReasons, [.foregroundResume])
    }

    func testTransportReconnectIntentDoesNotMakeViewLiveWithoutResync() async throws {
        let fixture = RuntimeFixture()
        let connection = fixture.connection(
            subscribe: fixture.snapshot(rows: []),
            resyncs: [
                fixture.snapshot(seq: 2, rows: [
                    fixture.row("reconnected", body: "Reconnected", order: "001"),
                ]),
            ]
        )
        let reconciler = fixture.reconciler(connection: connection)

        await reconciler.start()
        await reconciler.transportDisconnected("Socket down")
        let offlineSnapshot = await reconciler.snapshot()
        XCTAssertEqual(offlineSnapshot.freshness, .offline("Socket down"))

        await reconciler.transportReconnected()
        let reconnectedSnapshot = await reconciler.snapshot()

        let resyncReasons = await connection.resyncReasons()
        XCTAssertEqual(resyncReasons, [.transportReconnect])
        XCTAssertEqual(reconnectedSnapshot.freshness, .live)
        XCTAssertEqual(reconnectedSnapshot.rows.map(\.body), ["Reconnected"])
    }

    func testHeartbeatTimeoutMarksViewOfflineWithoutResyncingStaleConnection() async throws {
        let fixture = RuntimeFixture()
        let connection = fixture.connection(
            subscribe: fixture.snapshot(rows: []),
            resyncs: [fixture.snapshot(seq: 2, rows: [])]
        )
        let reconciler = fixture.reconciler(connection: connection)

        await reconciler.start()
        await reconciler.heartbeatTimedOut()

        let snapshot = await reconciler.snapshot()
        let resyncReasons = await connection.resyncReasons()
        let isClosed = await connection.isClosed()
        XCTAssertEqual(snapshot.freshness, .offline("Projection stream heartbeat timed out."))
        XCTAssertTrue(isClosed)
        XCTAssertEqual(resyncReasons, [])
    }

    func testSequenceGapForcesOneCanonicalResync() async throws {
        let fixture = RuntimeFixture()
        let connection = fixture.connection(
            subscribe: fixture.snapshot(rows: [
                fixture.row("seed", body: "Seed", order: "001"),
            ]),
            resyncs: [
                fixture.snapshot(seq: 3, rows: [
                    fixture.row("resynced", body: "Resynced", order: "001"),
                ]),
            ]
        )
        let reconciler = fixture.reconciler(connection: connection)

        await reconciler.start()
        await reconciler.receive(fixture.update(seq: 3, rows: [
            fixture.row("gap", body: "Gap", order: "001"),
        ]))

        let snapshot = await reconciler.snapshot()
        let resyncReasons = await connection.resyncReasons()
        XCTAssertEqual(resyncReasons, [.sequenceGap])
        XCTAssertEqual(snapshot.rows.map(\.body), ["Resynced"])
    }

    func testStalePartialResyncDoesNotTrapLaterRecoveryUpdateInCatchup() async throws {
        let fixture = RuntimeFixture()
        let connection = fixture.connection(
            subscribe: fixture.snapshot(seq: 3, rows: [
                fixture.row("cached", body: "Cached", order: "001"),
            ]),
            resyncs: [
                fixture.snapshot(
                    seq: 4,
                    rows: [fixture.row("cached", body: "Cached", order: "001")],
                    complete: false,
                    totalRows: 1,
                    window: fixture.window(offset: 0, rowCount: 1),
                    freshnessStatus: "stale",
                    freshnessError: "controlled source refresh failure"
                ),
                fixture.snapshot(seq: 6, rows: [
                    fixture.row("recovered", body: "Recovered", order: "001"),
                ]),
            ]
        )
        let reconciler = fixture.reconciler(connection: connection)

        await reconciler.start()
        await reconciler.manualRefresh()

        let staleSnapshot = await reconciler.snapshot()
        XCTAssertEqual(staleSnapshot.freshness, .stale("controlled source refresh failure"))
        XCTAssertEqual(staleSnapshot.rows.map(\.body), ["Cached"])

        await reconciler.receive(fixture.update(seq: 6, rows: [
            fixture.row("recovered", body: "Recovered", order: "001"),
        ]))

        let snapshot = await reconciler.snapshot()
        let resyncReasons = await connection.resyncReasons()
        XCTAssertEqual(resyncReasons, [.manualRefresh, .sequenceGap])
        XCTAssertEqual(snapshot.freshness, .live)
        XCTAssertEqual(snapshot.rows.map(\.body), ["Recovered"])
    }

    func testRelayResyncRequiredForcesCanonicalResync() async throws {
        let fixture = RuntimeFixture()
        let connection = fixture.connection(
            subscribe: fixture.snapshot(rows: []),
            resyncs: [fixture.snapshot(seq: 2, rows: [])]
        )
        let reconciler = fixture.reconciler(connection: connection)

        await reconciler.start()
        await reconciler.receive(fixture.resyncRequired(seq: 1, reason: "relay says so"))

        let resyncReasons = await connection.resyncReasons()
        XCTAssertEqual(resyncReasons, [.relayResyncRequired])
    }

    func testBufferOverflowForcesCanonicalResync() async throws {
        let fixture = RuntimeFixture()
        let connection = fixture.connection(
            subscribe: fixture.snapshot(
                rows: [fixture.row("first", body: "First", order: "001")],
                complete: false,
                totalRows: 3,
                window: fixture.window(offset: 0, rowCount: 1, nextOffset: 1)
            ),
            resyncs: [
                fixture.snapshot(seq: 4, rows: [
                    fixture.row("resynced", body: "Resynced", order: "001"),
                ]),
            ]
        )
        let reconciler = fixture.reconciler(connection: connection, maxBufferedEnvelopeCount: 1)

        await reconciler.start()
        await reconciler.receive(fixture.update(seq: 2, rows: [
            fixture.row("second", body: "Second", order: "002"),
        ]))
        await reconciler.receive(fixture.update(seq: 3, rows: [
            fixture.row("third", body: "Third", order: "003"),
        ]))

        let snapshot = await reconciler.snapshot()
        let resyncReasons = await connection.resyncReasons()
        XCTAssertEqual(resyncReasons, [.bufferOverflow])
        XCTAssertEqual(snapshot.rows.map(\.body), ["Resynced"])
    }

    func testCommandCompletionInvalidatesThroughProjectionResync() async throws {
        let fixture = RuntimeFixture()
        let connection = fixture.connection(
            subscribe: fixture.snapshot(rows: []),
            resyncs: [
                fixture.snapshot(seq: 2, rows: [
                    fixture.row("command", body: "Command output", order: "001"),
                ]),
            ]
        )
        let reconciler = fixture.reconciler(connection: connection)

        await reconciler.start()
        await reconciler.commandCompletedInvalidation()

        let snapshot = await reconciler.snapshot()
        let resyncReasons = await connection.resyncReasons()
        XCTAssertEqual(resyncReasons, [.commandCompletedInvalidation])
        XCTAssertEqual(snapshot.rows.map(\.body), ["Command output"])
    }

    func testStaleDeadlineMarksViewStaleWithoutClaimingLive() async throws {
        let fixture = RuntimeFixture()
        let reconciler = fixture.reconciler(subscribe: fixture.snapshot(rows: []))

        await reconciler.start()
        await reconciler.staleDeadlineExceeded("Render projector did not catch up")

        let snapshot = await reconciler.snapshot()
        XCTAssertEqual(snapshot.freshness, .stale("Render projector did not catch up"))
    }

    func testReplayBuffersLiveUpdatesUntilFiniteCatchupCompletes() async throws {
        let fixture = RuntimeFixture()
        let reconciler = fixture.reconciler(
            subscribe: fixture.snapshot(
                rows: [
                    fixture.row("first", body: "First", order: "001"),
                ],
                complete: false,
                totalRows: 2,
                window: fixture.window(offset: 0, rowCount: 1, nextOffset: 1)
            )
        )

        await reconciler.start()
        let catchingUpSnapshot = await reconciler.snapshot()
        XCTAssertEqual(catchingUpSnapshot.freshness, .catchingUp(.manualRefresh))

        await reconciler.receive(fixture.update(seq: 2, rows: [
            fixture.row("live", body: "Live", order: "003"),
        ]))
        let bufferedSnapshot = await reconciler.snapshot()
        XCTAssertEqual(bufferedSnapshot.bufferedEnvelopeCount, 1)

        await reconciler.receive(fixture.page(
            seq: 1,
            rows: [
                fixture.row("second", body: "Second", order: "002"),
            ],
            totalRows: 2,
            window: fixture.window(offset: 1, rowCount: 1)
        ))

        let snapshot = await reconciler.snapshot()
        XCTAssertEqual(snapshot.freshness, .live)
        XCTAssertEqual(snapshot.bufferedEnvelopeCount, 0)
        XCTAssertEqual(snapshot.rows.map(\.body), ["First", "Second", "Live"])
        XCTAssertEqual(snapshot.seq, 2)
    }

    func testCloseCancelsConnectionAndIgnoresLaterUpdates() async throws {
        let fixture = RuntimeFixture()
        let connection = fixture.connection(
            subscribe: fixture.snapshot(rows: [
                fixture.row("seed", body: "Seed", order: "001"),
            ])
        )
        let reconciler = fixture.reconciler(connection: connection)

        await reconciler.start()
        await reconciler.close()
        await reconciler.receive(fixture.update(seq: 2, rows: [
            fixture.row("late", body: "Late", order: "001"),
        ]))

        let snapshot = await reconciler.snapshot()
        let isClosed = await connection.isClosed()
        XCTAssertTrue(isClosed)
        XCTAssertEqual(snapshot.freshness, .closed)
        XCTAssertEqual(snapshot.rows.map(\.body), ["Seed"])
    }
}

private final class RuntimeFixture {
    let viewKey = ProjectionViewKey(
        sourceHostID: "test-host",
        view: ThreadDetailProjectionContract.view,
        scope: "thread",
        viewParamsKey: "thread:thread-1"
    )

    var policy: ProjectionReducerPolicy<ThreadDetailEventDTO> {
        .threadDetail(threadID: "thread-1")
    }

    func reconciler(
        subscribe: ProjectionEnvelope<ThreadDetailEventDTO>,
        maxBufferedEnvelopeCount: Int = 128
    ) -> StreamReconciler<ThreadDetailEventDTO> {
        reconciler(
            connection: connection(subscribe: subscribe),
            maxBufferedEnvelopeCount: maxBufferedEnvelopeCount
        )
    }

    func reconciler(
        connection: RecordingProjectionConnection<ThreadDetailEventDTO>,
        maxBufferedEnvelopeCount: Int = 128
    ) -> StreamReconciler<ThreadDetailEventDTO> {
        StreamReconciler(
            viewKey: viewKey,
            policy: policy,
            connector: StaticProjectionConnector(connection: connection),
            maxBufferedEnvelopeCount: maxBufferedEnvelopeCount
        )
    }

    func connection(
        subscribe: ProjectionEnvelope<ThreadDetailEventDTO>,
        resyncs: [ProjectionEnvelope<ThreadDetailEventDTO>] = []
    ) -> RecordingProjectionConnection<ThreadDetailEventDTO> {
        RecordingProjectionConnection(subscribe: subscribe, resyncs: resyncs)
    }

    func snapshot(
        sourceHostID: String = "test-host",
        epoch: String = "epoch-1",
        seq: Int64 = 1,
        generation: Int = 1,
        rows: [ThreadDetailEventDTO],
        complete: Bool = true,
        totalRows: Int? = nil,
        window: ProjectionWindow? = nil,
        freshnessStatus: String? = nil,
        freshnessError: String? = nil
    ) -> ProjectionEnvelope<ThreadDetailEventDTO> {
        ProjectionEnvelope(
            kind: .snapshot,
            schemaVersion: ThreadDetailProjectionContract.schemaVersion,
            identityVersion: ThreadDetailProjectionContract.identityVersion,
            projectionEngineVersion: ThreadDetailProjectionContract.projectionEngineVersion,
            sourceHostID: sourceHostID,
            view: ThreadDetailProjectionContract.view,
            threadID: "thread-1",
            scope: "thread",
            viewParamsKey: "thread:thread-1",
            order: ThreadDetailProjectionContract.order,
            epoch: epoch,
            seq: seq,
            generation: generation,
            rows: rows,
            projectionIDs: [],
            complete: complete,
            totalRows: totalRows ?? rows.count,
            window: window ?? ProjectionWindow(offset: 0, limit: rows.count, rowCount: rows.count, nextOffset: nil),
            reason: nil,
            freshnessStatus: freshnessStatus,
            freshnessError: freshnessError
        )
    }

    func page(
        seq: Int64,
        rows: [ThreadDetailEventDTO],
        totalRows: Int,
        window: ProjectionWindow
    ) -> ProjectionEnvelope<ThreadDetailEventDTO> {
        ProjectionEnvelope(
            kind: .page,
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
            rows: rows,
            projectionIDs: [],
            complete: true,
            totalRows: totalRows,
            window: window,
            reason: nil
        )
    }

    func update(
        seq: Int64,
        rows: [ThreadDetailEventDTO]
    ) -> ProjectionEnvelope<ThreadDetailEventDTO> {
        ProjectionEnvelope(
            kind: .upsert,
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
            rows: rows,
            projectionIDs: [],
            complete: nil,
            totalRows: nil,
            window: nil,
            reason: nil
        )
    }

    func resyncRequired(seq: Int64, reason: String) -> ProjectionEnvelope<ThreadDetailEventDTO> {
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

    func row(
        _ id: String,
        body: String,
        order: String,
        revision: Int = 1
    ) -> ThreadDetailEventDTO {
        ThreadDetailEventDTO(
            sourceHostID: "test-host",
            threadID: "thread-1",
            projectionID: projectionID(id),
            sourceRef: "host:test-host/thread:thread-1/turn:turn-1/item:\(id)",
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

    func window(offset: Int, rowCount: Int, nextOffset: Int? = nil) -> ProjectionWindow {
        ProjectionWindow(offset: offset, limit: rowCount, rowCount: rowCount, nextOffset: nextOffset)
    }

    private func projectionID(_ id: String) -> String {
        "host:test-host/thread:thread-1/turn:turn-1/item:\(id)/row:agentMessage"
    }
}

private struct StaticProjectionConnector<Row: Equatable & Sendable>: ProjectionStreamConnecting {
    let connection: RecordingProjectionConnection<Row>

    func connect() async throws -> any ProjectionStreamConnection<Row> {
        connection
    }
}

private actor RecordingProjectionConnection<Row: Equatable & Sendable>: ProjectionStreamConnection {
    private let subscribeEnvelope: ProjectionEnvelope<Row>
    private var pendingResyncs: [ProjectionEnvelope<Row>]
    private var recordedResyncReasons: [StreamReconcilerRecoveryReason] = []
    private var closed = false
    private let updateStream: AsyncThrowingStream<ProjectionEnvelope<Row>, Error>
    private let updateContinuation: AsyncThrowingStream<ProjectionEnvelope<Row>, Error>.Continuation

    init(
        subscribe: ProjectionEnvelope<Row>,
        resyncs: [ProjectionEnvelope<Row>] = []
    ) {
        self.subscribeEnvelope = subscribe
        self.pendingResyncs = resyncs
        let stream = AsyncThrowingStream<ProjectionEnvelope<Row>, Error>.makeStream()
        self.updateStream = stream.stream
        self.updateContinuation = stream.continuation
    }

    func subscribe() async throws -> ProjectionEnvelope<Row> {
        subscribeEnvelope
    }

    func resync(reason: StreamReconcilerRecoveryReason) async throws -> ProjectionEnvelope<Row> {
        recordedResyncReasons.append(reason)
        if pendingResyncs.isEmpty {
            return subscribeEnvelope
        }
        return pendingResyncs.removeFirst()
    }

    nonisolated func updates() -> AsyncThrowingStream<ProjectionEnvelope<Row>, Error> {
        updateStream
    }

    func close() async {
        closed = true
        updateContinuation.finish()
    }

    func resyncReasons() -> [StreamReconcilerRecoveryReason] {
        recordedResyncReasons
    }

    func isClosed() -> Bool {
        closed
    }
}

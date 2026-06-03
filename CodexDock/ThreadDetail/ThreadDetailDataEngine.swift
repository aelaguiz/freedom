import Foundation

public struct ThreadDetailDataSnapshot: Equatable, Sendable {
    public let events: [ThreadEvent]
    public let activeTurnID: String?

    public init(events: [ThreadEvent], activeTurnID: String?) {
        self.events = events
        self.activeTurnID = activeTurnID
    }
}

public actor ThreadDetailDataEngine {
    private var reducer = ProjectionReducer<ThreadDetailEventDTO>()
    private var activeTurnID: String?

    public init() {}

    public func replace(
        from snapshot: ThreadDetailSnapshotDTO,
        expectedThreadID: String,
        expectedSourceHostID: String? = nil
    ) throws -> ThreadDetailDataSnapshot {
        try validate(threadID: snapshot.threadID, expectedThreadID: expectedThreadID)
        if let expectedSourceHostID, snapshot.sourceHostID != expectedSourceHostID {
            throw ThreadDetailStoreError.invalidProjectionEnvelope("Thread Detail projection sourceHostID \(snapshot.sourceHostID) does not match \(expectedSourceHostID).")
        }
        do {
            // Relay projection owns visible detail identity, order, revision,
            // freshness, and catch-up semantics. Thread Detail only renders it.
            try reducer.apply(
                ProjectionEnvelope(snapshot: snapshot),
                policy: .threadDetail(threadID: expectedThreadID)
            )
        } catch {
            throw Self.map(error)
        }
        activeTurnID = snapshot.activeTurnID
        return self.snapshot(expectedThreadID: expectedThreadID)
    }

    public func apply(
        update: ThreadDetailUpdateDTO,
        expectedThreadID: String
    ) throws -> ThreadDetailDataSnapshot {
        try validate(threadID: update.threadID, expectedThreadID: expectedThreadID)
        do {
            try reducer.apply(
                ProjectionEnvelope(update: update),
                policy: .threadDetail(threadID: expectedThreadID)
            )
        } catch {
            throw Self.map(error)
        }
        activeTurnID = update.activeTurnID
        return snapshot(expectedThreadID: expectedThreadID)
    }

    public func setActiveTurnID(_ activeTurnID: String?) {
        self.activeTurnID = activeTurnID
    }

    public func currentSnapshot(expectedThreadID: String) -> ThreadDetailDataSnapshot {
        snapshot(expectedThreadID: expectedThreadID)
    }

    private func snapshot(expectedThreadID: String) -> ThreadDetailDataSnapshot {
        ThreadDetailDataSnapshot(
            events: ThreadEventDisplayOrder.newestFirst(
                reducer
                    .sortedRows(policy: .threadDetail(threadID: expectedThreadID))
                    .map(ThreadEvent.init(detailEvent:))
            ),
            activeTurnID: activeTurnID
        )
    }

    private func validate(threadID: String, expectedThreadID: String) throws {
        guard threadID == expectedThreadID else {
            throw ThreadDetailStoreError.threadMismatch(
                expected: expectedThreadID,
                actual: threadID
            )
        }
    }

    private static func map(_ error: Error) -> ThreadDetailStoreError {
        guard let error = error as? ProjectionReducerError else {
            return .invalidProjectionEnvelope(error.localizedDescription)
        }
        switch error {
        case .schemaMismatch, .streamContract:
            return .invalidProjectionEnvelope(error.localizedDescription)
        case .epochMismatch(let expected, let actual):
            return .projectionEpochMismatch(expected: expected, actual: actual)
        case .sequenceGap(let expected, let actual):
            return .projectionSequenceGap(expected: expected, actual: actual)
        case .resyncRequired(let reason):
            return .projectionResyncRequired(reason)
        }
    }
}

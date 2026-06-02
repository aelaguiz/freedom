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
    private var index = ThreadEventIndex()
    private var activeTurnID: String?
    private var sourceHostID: String?
    private var viewParamsKey: String?
    private var epoch: String?
    private var lastSeq: Int64?

    public init() {}

    public func replace(
        from snapshot: ThreadDetailSnapshotDTO,
        expectedThreadID: String,
        expectedSourceHostID: String? = nil
    ) throws -> ThreadDetailDataSnapshot {
        try validateSnapshot(snapshot, expectedThreadID: expectedThreadID, expectedSourceHostID: expectedSourceHostID)
        // Thread Detail display identity is relay-owned. The client keys and
        // orders only by the relay projection envelope; raw Codex payloads are
        // never normalized into production rows here.
        index.replace(with: snapshot.rows)
        activeTurnID = snapshot.activeTurnID
        sourceHostID = snapshot.sourceHostID
        viewParamsKey = snapshot.viewParamsKey
        epoch = snapshot.epoch
        lastSeq = snapshot.seq
        return self.snapshot()
    }

    public func apply(
        update: ThreadDetailUpdateDTO,
        expectedThreadID: String
    ) throws -> ThreadDetailDataSnapshot {
        try validate(threadID: update.threadID, expectedThreadID: expectedThreadID)
        if isAlreadyCovered(update) {
            return snapshot()
        }
        try validateUpdate(update)
        try validateContinuity(update)

        switch update.kind {
        case .snapshot:
            index.replace(with: update.rows)
        case .upsert:
            for row in update.rows {
                try index.upsert(row)
            }
        case .delete:
            for projectionID in update.projectionIDs {
                index.remove(id: projectionID)
            }
        case .heartbeat:
            break
        case .resyncRequired:
            throw ThreadDetailStoreError.projectionResyncRequired(update.reason ?? "Detail resync required.")
        }

        activeTurnID = update.activeTurnID
        lastSeq = update.seq
        return snapshot()
    }

    public func setActiveTurnID(_ activeTurnID: String?) {
        self.activeTurnID = activeTurnID
    }

    public func currentSnapshot() -> ThreadDetailDataSnapshot {
        snapshot()
    }

    private func snapshot() -> ThreadDetailDataSnapshot {
        ThreadDetailDataSnapshot(
            events: index.eventsNewestFirst(),
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

    private func validateSnapshot(
        _ snapshot: ThreadDetailSnapshotDTO,
        expectedThreadID: String,
        expectedSourceHostID: String?
    ) throws {
        try validate(threadID: snapshot.threadID, expectedThreadID: expectedThreadID)
        try validateBaseEnvelope(
            schemaVersion: snapshot.schemaVersion,
            identityVersion: snapshot.identityVersion,
            projectionEngineVersion: snapshot.projectionEngineVersion,
            sourceHostID: snapshot.sourceHostID,
            expectedSourceHostID: expectedSourceHostID,
            view: snapshot.view,
            order: snapshot.order,
            viewParamsKey: snapshot.viewParamsKey
        )
        try validateRows(
            snapshot.rows,
            sourceHostID: snapshot.sourceHostID,
            view: snapshot.view,
            threadID: snapshot.threadID
        )
    }

    private func validateUpdate(_ update: ThreadDetailUpdateDTO) throws {
        try validateBaseEnvelope(
            schemaVersion: update.schemaVersion,
            identityVersion: update.identityVersion,
            projectionEngineVersion: update.projectionEngineVersion,
            sourceHostID: update.sourceHostID,
            expectedSourceHostID: sourceHostID,
            view: update.view,
            order: update.order,
            viewParamsKey: update.viewParamsKey
        )
        guard update.viewParamsKey == viewParamsKey else {
            throw ThreadDetailStoreError.invalidProjectionEnvelope("Thread Detail update viewParamsKey does not match the active view.")
        }
        try validateRows(
            update.rows,
            sourceHostID: update.sourceHostID,
            view: update.view,
            threadID: update.threadID
        )
        try validateProjectionIDs(update.projectionIDs)
    }

    private func validateBaseEnvelope(
        schemaVersion: Int,
        identityVersion: Int,
        projectionEngineVersion: Int,
        sourceHostID: String,
        expectedSourceHostID: String?,
        view: String,
        order: String?,
        viewParamsKey: String?
    ) throws {
        guard schemaVersion == ThreadDetailProjectionContract.schemaVersion else {
            throw ThreadDetailStoreError.invalidProjectionEnvelope("Unsupported Thread Detail schemaVersion \(schemaVersion).")
        }
        guard identityVersion == ThreadDetailProjectionContract.identityVersion else {
            throw ThreadDetailStoreError.invalidProjectionEnvelope("Unsupported Thread Detail identityVersion \(identityVersion).")
        }
        guard projectionEngineVersion == ThreadDetailProjectionContract.projectionEngineVersion else {
            throw ThreadDetailStoreError.invalidProjectionEnvelope("Unsupported Thread Detail projectionEngineVersion \(projectionEngineVersion).")
        }
        guard !sourceHostID.isEmpty else {
            throw ThreadDetailStoreError.invalidProjectionEnvelope("Thread Detail projection sourceHostID is empty.")
        }
        if let expectedSourceHostID, sourceHostID != expectedSourceHostID {
            throw ThreadDetailStoreError.invalidProjectionEnvelope("Thread Detail projection sourceHostID \(sourceHostID) does not match \(expectedSourceHostID).")
        }
        guard view == ThreadDetailProjectionContract.view else {
            throw ThreadDetailStoreError.invalidProjectionEnvelope("Thread Detail projection view \(view) is not \(ThreadDetailProjectionContract.view).")
        }
        guard order == ThreadDetailProjectionContract.order else {
            throw ThreadDetailStoreError.invalidProjectionEnvelope("Thread Detail projection order is missing or unsupported.")
        }
        guard let viewParamsKey, !viewParamsKey.isEmpty else {
            throw ThreadDetailStoreError.invalidProjectionEnvelope("Thread Detail projection viewParamsKey is missing.")
        }
    }

    private func validateRows(
        _ rows: [ThreadDetailEventDTO],
        sourceHostID: String,
        view: String,
        threadID: String
    ) throws {
        var seenProjectionIDs = Set<String>()
        var seenSourceKeys = Set<ThreadDetailProjectionSourceKey>()
        for row in rows {
            guard row.schemaVersion == ThreadDetailProjectionContract.schemaVersion else {
                throw ThreadDetailStoreError.invalidProjectionEnvelope("Unsupported Thread Detail row schemaVersion \(row.schemaVersion).")
            }
            guard row.identityVersion == ThreadDetailProjectionContract.identityVersion else {
                throw ThreadDetailStoreError.invalidProjectionEnvelope("Unsupported Thread Detail row identityVersion \(row.identityVersion).")
            }
            guard row.projectionEngineVersion == ThreadDetailProjectionContract.projectionEngineVersion else {
                throw ThreadDetailStoreError.invalidProjectionEnvelope("Unsupported Thread Detail row projectionEngineVersion \(row.projectionEngineVersion).")
            }
            guard row.sourceHostID == sourceHostID else {
                throw ThreadDetailStoreError.invalidProjectionEnvelope("Thread Detail row sourceHostID does not match its snapshot.")
            }
            guard row.view == view else {
                throw ThreadDetailStoreError.invalidProjectionEnvelope("Thread Detail row view does not match its snapshot.")
            }
            guard row.threadID == threadID else {
                throw ThreadDetailStoreError.invalidProjectionEnvelope("Thread Detail row threadID does not match its snapshot.")
            }
            guard !row.projectionID.isEmpty else {
                throw ThreadDetailStoreError.invalidProjectionEnvelope("Thread Detail row projectionID is empty.")
            }
            guard !row.sourceRef.isEmpty else {
                throw ThreadDetailStoreError.invalidProjectionEnvelope("Thread Detail row sourceRef is empty.")
            }
            guard !row.rowRole.isEmpty else {
                throw ThreadDetailStoreError.invalidProjectionEnvelope("Thread Detail row rowRole is empty.")
            }
            guard !row.displayOrderKey.isEmpty else {
                throw ThreadDetailStoreError.invalidProjectionEnvelope("Thread Detail row displayOrderKey is missing.")
            }
            guard seenProjectionIDs.insert(row.projectionID).inserted else {
                throw ThreadDetailStoreError.invalidProjectionEnvelope("Thread Detail snapshot contains duplicate projectionID \(row.projectionID).")
            }
            let sourceKey = ThreadDetailProjectionSourceKey(row)
            guard seenSourceKeys.insert(sourceKey).inserted else {
                throw ThreadDetailStoreError.invalidProjectionEnvelope("Thread Detail snapshot contains duplicate projection source identity \(row.sourceRef) \(row.rowRole).")
            }
        }
    }

    private func validateProjectionIDs(_ projectionIDs: [String]) throws {
        for projectionID in projectionIDs where projectionID.isEmpty {
            throw ThreadDetailStoreError.invalidProjectionEnvelope("Thread Detail delete projectionID is empty.")
        }
    }

    private func validateContinuity(_ update: ThreadDetailUpdateDTO) throws {
        guard let epoch else {
            throw ThreadDetailStoreError.projectionEpochMismatch(expected: "none", actual: update.epoch)
        }
        guard update.epoch == epoch else {
            throw ThreadDetailStoreError.projectionEpochMismatch(expected: epoch, actual: update.epoch)
        }
        guard let lastSeq else {
            throw ThreadDetailStoreError.projectionSequenceGap(expected: update.seq, actual: update.seq)
        }
        guard update.seq == lastSeq + 1 else {
            throw ThreadDetailStoreError.projectionSequenceGap(expected: lastSeq + 1, actual: update.seq)
        }
    }

    private func isAlreadyCovered(_ update: ThreadDetailUpdateDTO) -> Bool {
        guard let epoch, let lastSeq else {
            return false
        }
        return update.epoch == epoch && update.seq <= lastSeq
    }
}

private enum ThreadDetailProjectionContract {
    static let schemaVersion = 1
    static let identityVersion = 1
    static let projectionEngineVersion = 1
    static let view = "thread.detail"
    static let order = "displayOrderKeyAscending"
}

struct ThreadEventIndex: Sendable {
    private var rowsByProjectionID: [String: ThreadDetailEventDTO] = [:]
    private var projectionIDsBySourceKey: [ThreadDetailProjectionSourceKey: String] = [:]

    mutating func replace(with rows: [ThreadDetailEventDTO]) {
        rowsByProjectionID = Dictionary(
            uniqueKeysWithValues: rows.map { row in
                (row.projectionID, row)
            }
        )
        projectionIDsBySourceKey = Dictionary(
            uniqueKeysWithValues: rows.map { row in
                (ThreadDetailProjectionSourceKey(row), row.projectionID)
            }
        )
    }

    mutating func upsert(_ row: ThreadDetailEventDTO) throws {
        let sourceKey = ThreadDetailProjectionSourceKey(row)
        if let existingProjectionID = projectionIDsBySourceKey[sourceKey],
           existingProjectionID != row.projectionID {
            throw ThreadDetailStoreError.invalidProjectionEnvelope(
                "Thread Detail upsert reused projection source identity \(row.sourceRef) \(row.rowRole) under \(row.projectionID); existing projectionID is \(existingProjectionID)."
            )
        }
        if let existing = rowsByProjectionID[row.projectionID] {
            guard existing.hasSameProjectionIdentity(as: row) else {
                throw ThreadDetailStoreError.invalidProjectionEnvelope(
                    "Thread Detail upsert changed immutable projection identity for \(row.projectionID)."
                )
            }
            guard row.revision >= existing.revision else {
                throw ThreadDetailStoreError.invalidProjectionEnvelope(
                    "Thread Detail upsert carried stale revision \(row.revision) for \(row.projectionID)."
                )
            }
            guard row.revision > existing.revision || row == existing else {
                throw ThreadDetailStoreError.invalidProjectionEnvelope(
                    "Thread Detail upsert changed row content without increasing revision for \(row.projectionID)."
                )
            }
        }
        rowsByProjectionID[row.projectionID] = row
        projectionIDsBySourceKey[sourceKey] = row.projectionID
    }

    mutating func remove(id: String) {
        if let existing = rowsByProjectionID.removeValue(forKey: id) {
            projectionIDsBySourceKey.removeValue(forKey: ThreadDetailProjectionSourceKey(existing))
        }
    }

    func eventsNewestFirst() -> [ThreadEvent] {
        ThreadEventDisplayOrder.newestFirst(rowsByProjectionID.values.map(ThreadEvent.init(detailEvent:)))
    }
}

private struct ThreadDetailProjectionSourceKey: Hashable, Sendable {
    let sourceHostID: String
    let view: String
    let threadID: String
    let sourceRef: String
    let rowRole: String

    init(_ row: ThreadDetailEventDTO) {
        sourceHostID = row.sourceHostID
        view = row.view
        threadID = row.threadID
        sourceRef = row.sourceRef
        rowRole = row.rowRole
    }
}

private extension ThreadDetailEventDTO {
    func hasSameProjectionIdentity(as other: ThreadDetailEventDTO) -> Bool {
        schemaVersion == other.schemaVersion
            && identityVersion == other.identityVersion
            && projectionEngineVersion == other.projectionEngineVersion
            && sourceHostID == other.sourceHostID
            && view == other.view
            && threadID == other.threadID
            && projectionID == other.projectionID
            && sourceRef == other.sourceRef
            && rowRole == other.rowRole
    }
}

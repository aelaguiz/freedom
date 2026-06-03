import Foundation

enum ProjectionUpdateKind: String, Equatable, Sendable {
    case snapshot
    case page
    case upsert
    case delete
    case heartbeat
    case resyncRequired
}

struct ProjectionWindow: Equatable, Sendable {
    let offset: Int
    let limit: Int
    let rowCount: Int
    let nextOffset: Int?

    init(offset: Int, limit: Int, rowCount: Int, nextOffset: Int?) {
        self.offset = offset
        self.limit = limit
        self.rowCount = rowCount
        self.nextOffset = nextOffset
    }
}

struct ProjectionEnvelope<Row: Equatable & Sendable>: Equatable, Sendable {
    let kind: ProjectionUpdateKind
    let schemaVersion: Int
    let identityVersion: Int
    let projectionEngineVersion: Int
    let sourceHostID: String
    let view: String
    let threadID: String?
    let scope: String?
    let viewParamsKey: String?
    let order: String?
    let epoch: String
    let seq: Int64
    let generation: Int
    let rows: [Row]
    let projectionIDs: [String]
    let complete: Bool?
    let totalRows: Int?
    let window: ProjectionWindow?
    let reason: String?
    let activeTurnID: String?
    let liveState: String?
    let freshnessStatus: String?
    let freshnessError: String?

    init(
        kind: ProjectionUpdateKind,
        schemaVersion: Int,
        identityVersion: Int,
        projectionEngineVersion: Int,
        sourceHostID: String,
        view: String,
        threadID: String? = nil,
        scope: String?,
        viewParamsKey: String?,
        order: String?,
        epoch: String,
        seq: Int64,
        generation: Int,
        rows: [Row],
        projectionIDs: [String],
        complete: Bool?,
        totalRows: Int?,
        window: ProjectionWindow?,
        reason: String?,
        activeTurnID: String? = nil,
        liveState: String? = nil,
        freshnessStatus: String? = nil,
        freshnessError: String? = nil
    ) {
        self.kind = kind
        self.schemaVersion = schemaVersion
        self.identityVersion = identityVersion
        self.projectionEngineVersion = projectionEngineVersion
        self.sourceHostID = sourceHostID
        self.view = view
        self.threadID = threadID
        self.scope = scope
        self.viewParamsKey = viewParamsKey
        self.order = order
        self.epoch = epoch
        self.seq = seq
        self.generation = generation
        self.rows = rows
        self.projectionIDs = projectionIDs
        self.complete = complete
        self.totalRows = totalRows
        self.window = window
        self.reason = reason
        self.activeTurnID = activeTurnID
        self.liveState = liveState
        self.freshnessStatus = freshnessStatus
        self.freshnessError = freshnessError
    }
}

struct ProjectionReducerPolicy<Row: Equatable & Sendable>: Sendable {
    let expectedSchemaVersion: Int
    let expectedIdentityVersion: Int
    let expectedProjectionEngineVersion: Int
    let expectedView: String
    let expectedScope: String?
    let expectedOrder: String
    let requiredThreadID: String?
    let isStoredRow: @Sendable (Row) -> Bool
    let rowSchemaVersion: @Sendable (Row) -> Int
    let rowIdentityVersion: @Sendable (Row) -> Int
    let rowProjectionEngineVersion: @Sendable (Row) -> Int
    let projectionID: @Sendable (Row) -> String
    let sourceHostID: @Sendable (Row) -> String
    let view: @Sendable (Row) -> String
    let threadID: @Sendable (Row) -> String?
    let sourceKey: @Sendable (Row) -> String
    let displayOrderKey: @Sendable (Row) -> String
    let revision: @Sendable (Row) -> Int?
    let hasSameImmutableIdentity: @Sendable (Row, Row) -> Bool
}

enum ProjectionReducerError: Error, Equatable, LocalizedError, Sendable {
    case schemaMismatch
    case streamContract(String)
    case epochMismatch(expected: String, actual: String)
    case sequenceGap(expected: Int64, actual: Int64)
    case resyncRequired(String)

    var errorDescription: String? {
        switch self {
        case .schemaMismatch:
            return "Projection schema version is unsupported."
        case .streamContract(let message):
            return message
        case .epochMismatch(let expected, let actual):
            return "Projection epoch changed from \(expected) to \(actual)."
        case .sequenceGap(let expected, let actual):
            return "Projection sequence gap: expected \(expected), got \(actual)."
        case .resyncRequired(let reason):
            return reason
        }
    }
}

struct ProjectionReducer<Row: Equatable & Sendable>: Equatable, Sendable {
    private(set) var epoch: String?
    private(set) var seq: Int64 = 0
    private(set) var generation: Int = 0
    private(set) var sourceHostID: String?
    private(set) var viewParamsKey: String?
    private var rowsByProjectionID: [String: Row] = [:]
    private var projectionIDsBySourceKey: [String: String] = [:]

    init() {}

    var rowCount: Int {
        rowsByProjectionID.count
    }

    var rows: [Row] {
        Array(rowsByProjectionID.values)
    }

    mutating func reset() {
        epoch = nil
        seq = 0
        generation = 0
        sourceHostID = nil
        viewParamsKey = nil
        rowsByProjectionID = [:]
        projectionIDsBySourceKey = [:]
    }

    mutating func apply(
        _ envelope: ProjectionEnvelope<Row>,
        policy: ProjectionReducerPolicy<Row>
    ) throws {
        try validateBaseEnvelope(envelope, policy: policy)
        try validateRows(envelope.rows, envelope: envelope, policy: policy)
        try validateDeleteIDs(envelope.projectionIDs)

        switch envelope.kind {
        case .snapshot:
            try applySnapshot(envelope, policy: policy)
        case .page:
            try applyPage(envelope, policy: policy)
        case .upsert:
            try applyLiveMutation(envelope, policy: policy)
        case .delete:
            try applyLiveMutation(envelope, policy: policy)
        case .heartbeat:
            try applyHeartbeat(envelope)
        case .resyncRequired:
            throw ProjectionReducerError.resyncRequired(envelope.reason ?? "Projection resync required.")
        }
    }

    func sortedRows(policy: ProjectionReducerPolicy<Row>) -> [Row] {
        rows.sorted { lhs, rhs in
            let leftOrder = policy.displayOrderKey(lhs)
            let rightOrder = policy.displayOrderKey(rhs)
            if leftOrder != rightOrder {
                return leftOrder < rightOrder
            }
            return policy.projectionID(lhs) < policy.projectionID(rhs)
        }
    }

    private mutating func applySnapshot(
        _ envelope: ProjectionEnvelope<Row>,
        policy: ProjectionReducerPolicy<Row>
    ) throws {
        guard envelope.window != nil, envelope.totalRows != nil, envelope.complete != nil else {
            throw ProjectionReducerError.streamContract("Projection snapshot is missing its window contract.")
        }
        let storedRows = envelope.rows.filter(policy.isStoredRow)
        rowsByProjectionID = Dictionary(
            uniqueKeysWithValues: storedRows.map { row in
                (policy.projectionID(row), row)
            }
        )
        projectionIDsBySourceKey = Dictionary(
            uniqueKeysWithValues: storedRows.map { row in
                (policy.sourceKey(row), policy.projectionID(row))
            }
        )
        epoch = envelope.epoch
        seq = envelope.seq
        generation = envelope.generation
        sourceHostID = envelope.sourceHostID
        viewParamsKey = envelope.viewParamsKey
    }

    private mutating func applyPage(
        _ envelope: ProjectionEnvelope<Row>,
        policy: ProjectionReducerPolicy<Row>
    ) throws {
        try validateOpenStream(envelope)
        guard envelope.seq == seq else {
            throw ProjectionReducerError.sequenceGap(expected: seq, actual: envelope.seq)
        }
        guard let window = envelope.window,
              let totalRows = envelope.totalRows,
              envelope.complete != nil,
              window.offset >= 0,
              window.limit >= 0,
              window.rowCount == envelope.rows.count,
              totalRows >= window.rowCount else {
            throw ProjectionReducerError.streamContract("Projection page is missing its catch-up window contract.")
        }
        try upsertRows(envelope.rows.filter(policy.isStoredRow), policy: policy)
    }

    private mutating func applyLiveMutation(
        _ envelope: ProjectionEnvelope<Row>,
        policy: ProjectionReducerPolicy<Row>
    ) throws {
        try validateOpenStream(envelope)
        if envelope.complete == false || (envelope.window?.offset ?? 0) > 0 {
            throw ProjectionReducerError.streamContract("Projection catch-up windows must use page updates, not live mutations.")
        }
        guard envelope.seq == seq + 1 else {
            throw ProjectionReducerError.sequenceGap(expected: seq + 1, actual: envelope.seq)
        }
        for projectionID in envelope.projectionIDs {
            remove(projectionID: projectionID, policy: policy)
        }
        if envelope.kind == .upsert {
            try upsertRows(envelope.rows.filter(policy.isStoredRow), policy: policy)
        }
        seq = envelope.seq
    }

    private func applyHeartbeat(_ envelope: ProjectionEnvelope<Row>) throws {
        try validateOpenStream(envelope)
        guard envelope.seq == seq else {
            throw ProjectionReducerError.sequenceGap(expected: seq, actual: envelope.seq)
        }
        guard envelope.rows.isEmpty, envelope.projectionIDs.isEmpty else {
            throw ProjectionReducerError.streamContract("Projection heartbeat must not mutate rows.")
        }
    }

    private func validateBaseEnvelope(
        _ envelope: ProjectionEnvelope<Row>,
        policy: ProjectionReducerPolicy<Row>
    ) throws {
        guard envelope.schemaVersion == policy.expectedSchemaVersion else {
            throw ProjectionReducerError.schemaMismatch
        }
        guard envelope.identityVersion == policy.expectedIdentityVersion,
              envelope.projectionEngineVersion == policy.expectedProjectionEngineVersion,
              !envelope.sourceHostID.isEmpty,
              envelope.view == policy.expectedView,
              envelope.order == policy.expectedOrder,
              let viewParamsKey = envelope.viewParamsKey,
              !viewParamsKey.isEmpty,
              !envelope.epoch.isEmpty,
              envelope.generation > 0 else {
            throw ProjectionReducerError.streamContract("Projection envelope does not match the expected stream contract.")
        }
        if let expectedScope = policy.expectedScope,
           envelope.scope != expectedScope {
            throw ProjectionReducerError.streamContract("Projection envelope scope does not match the expected stream contract.")
        }
        if let requiredThreadID = policy.requiredThreadID,
           envelope.threadID != requiredThreadID {
            throw ProjectionReducerError.streamContract(
                "Projection envelope threadID \(envelope.threadID ?? "<missing>") does not match expected \(requiredThreadID)."
            )
        }
    }

    private func validateOpenStream(_ envelope: ProjectionEnvelope<Row>) throws {
        guard let epoch else {
            throw ProjectionReducerError.epochMismatch(expected: "none", actual: envelope.epoch)
        }
        guard envelope.epoch == epoch else {
            throw ProjectionReducerError.epochMismatch(expected: epoch, actual: envelope.epoch)
        }
        guard envelope.sourceHostID == sourceHostID,
              envelope.viewParamsKey == viewParamsKey,
              envelope.generation == generation else {
            throw ProjectionReducerError.streamContract("Projection update does not match the active view generation.")
        }
    }

    private func validateRows(
        _ rows: [Row],
        envelope: ProjectionEnvelope<Row>,
        policy: ProjectionReducerPolicy<Row>
    ) throws {
        var seenProjectionIDs = Set<String>()
        var seenSourceKeys = Set<String>()
        for row in rows {
            let projectionID = policy.projectionID(row)
            let sourceKey = policy.sourceKey(row)
            guard policy.rowSchemaVersion(row) == policy.expectedSchemaVersion,
                  policy.rowIdentityVersion(row) == policy.expectedIdentityVersion,
                  policy.rowProjectionEngineVersion(row) == policy.expectedProjectionEngineVersion,
                  policy.sourceHostID(row) == envelope.sourceHostID,
                  policy.view(row) == envelope.view,
                  policy.threadID(row) == policy.requiredThreadID,
                  !projectionID.isEmpty,
                  !sourceKey.isEmpty,
                  !policy.displayOrderKey(row).isEmpty else {
                throw ProjectionReducerError.streamContract("Projection row does not match its envelope.")
            }
            guard seenProjectionIDs.insert(projectionID).inserted else {
                throw ProjectionReducerError.streamContract("Projection payload contains duplicate projectionID \(projectionID).")
            }
            guard seenSourceKeys.insert(sourceKey).inserted else {
                throw ProjectionReducerError.streamContract("Projection payload contains duplicate source identity \(sourceKey).")
            }
        }
    }

    private func validateDeleteIDs(_ projectionIDs: [String]) throws {
        for projectionID in projectionIDs where projectionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ProjectionReducerError.streamContract("Projection delete ID is empty.")
        }
    }

    private mutating func upsertRows(
        _ rows: [Row],
        policy: ProjectionReducerPolicy<Row>
    ) throws {
        for row in rows {
            let projectionID = policy.projectionID(row)
            let sourceKey = policy.sourceKey(row)
            if let existingProjectionID = projectionIDsBySourceKey[sourceKey],
               existingProjectionID != projectionID {
                throw ProjectionReducerError.streamContract(
                    "Projection upsert reused source identity \(sourceKey) under \(projectionID); existing projectionID is \(existingProjectionID)."
                )
            }
            if let existing = rowsByProjectionID[projectionID] {
                guard policy.hasSameImmutableIdentity(existing, row) else {
                    throw ProjectionReducerError.streamContract("Projection upsert changed immutable identity for \(projectionID).")
                }
                if let existingRevision = policy.revision(existing),
                   let nextRevision = policy.revision(row) {
                    guard nextRevision >= existingRevision else {
                        throw ProjectionReducerError.streamContract("Projection upsert carried stale revision \(nextRevision) for \(projectionID).")
                    }
                    guard nextRevision > existingRevision || row == existing else {
                        throw ProjectionReducerError.streamContract("Projection upsert changed row content without increasing revision for \(projectionID).")
                    }
                }
            }
            rowsByProjectionID[projectionID] = row
            projectionIDsBySourceKey[sourceKey] = projectionID
        }
    }

    private mutating func remove(
        projectionID: String,
        policy: ProjectionReducerPolicy<Row>
    ) {
        if let existing = rowsByProjectionID.removeValue(forKey: projectionID) {
            projectionIDsBySourceKey.removeValue(forKey: policy.sourceKey(existing))
        }
    }
}

extension ProjectionEnvelope where Row == DockThreadCardDTO {
    init(_ update: ThreadCardStreamUpdateDTO) {
        self.init(
            kind: ProjectionUpdateKind(update.kind),
            schemaVersion: update.schemaVersion,
            identityVersion: update.identityVersion,
            projectionEngineVersion: update.projectionEngineVersion,
            sourceHostID: update.sourceHostID,
            view: update.view.rawValue,
            threadID: nil,
            scope: update.scope,
            viewParamsKey: update.viewParamsKey,
            order: update.order,
            epoch: update.epoch,
            seq: update.seq,
            generation: update.generation,
            rows: update.rows ?? [],
            projectionIDs: update.projectionIDs ?? [],
            complete: update.complete,
            totalRows: update.totalRows,
            window: update.window.map(ProjectionWindow.init),
            reason: update.reason,
            liveState: nil,
            freshnessStatus: update.freshness.status.rawValue,
            freshnessError: update.freshness.lastError
        )
    }
}

extension ProjectionEnvelope where Row == ThreadDetailEventDTO {
    init(snapshot: ThreadDetailSnapshotDTO) {
        self.init(
            kind: .snapshot,
            schemaVersion: snapshot.schemaVersion,
            identityVersion: snapshot.identityVersion,
            projectionEngineVersion: snapshot.projectionEngineVersion,
            sourceHostID: snapshot.sourceHostID,
            view: snapshot.view,
            threadID: snapshot.threadID,
            scope: snapshot.scope,
            viewParamsKey: snapshot.viewParamsKey,
            order: snapshot.order,
            epoch: snapshot.epoch,
            seq: snapshot.seq,
            generation: snapshot.generation,
            rows: snapshot.rows,
            projectionIDs: [],
            complete: snapshot.complete,
            totalRows: snapshot.rows.count,
            window: ProjectionWindow(offset: 0, limit: snapshot.rows.count, rowCount: snapshot.rows.count, nextOffset: nil),
            reason: nil,
            activeTurnID: snapshot.activeTurnID,
            liveState: nil,
            freshnessStatus: snapshot.freshness?.state,
            freshnessError: nil
        )
    }

    init(update: ThreadDetailUpdateDTO) {
        self.init(
            kind: ProjectionUpdateKind(update.kind),
            schemaVersion: update.schemaVersion,
            identityVersion: update.identityVersion,
            projectionEngineVersion: update.projectionEngineVersion,
            sourceHostID: update.sourceHostID,
            view: update.view,
            threadID: update.threadID,
            scope: update.scope,
            viewParamsKey: update.viewParamsKey,
            order: update.order,
            epoch: update.epoch,
            seq: update.seq,
            generation: update.generation,
            rows: update.rows,
            projectionIDs: update.projectionIDs,
            complete: nil,
            totalRows: nil,
            window: nil,
            reason: update.reason,
            activeTurnID: update.activeTurnID,
            liveState: update.liveState,
            freshnessStatus: update.freshness?.state,
            freshnessError: nil
        )
    }
}

extension ProjectionReducerPolicy where Row == DockThreadCardDTO {
    static func threadCards(expectedView: ThreadCardStreamView) -> Self {
        ProjectionReducerPolicy(
            expectedSchemaVersion: CodexDockConstants.Dock.streamSchemaVersion,
            expectedIdentityVersion: 1,
            expectedProjectionEngineVersion: 1,
            expectedView: expectedView.rawValue,
            expectedScope: "view",
            expectedOrder: "displayOrderKeyAscending",
            requiredThreadID: nil,
            isStoredRow: { $0.isAppFacingHumanThreadCard },
            rowSchemaVersion: { $0.schemaVersion },
            rowIdentityVersion: { $0.identityVersion },
            rowProjectionEngineVersion: { $0.projectionEngineVersion },
            projectionID: { $0.projectionStorageKey },
            sourceHostID: { $0.sourceHostID },
            view: { $0.view },
            threadID: { _ in nil },
            sourceKey: { "\($0.sourceHostID)|\($0.view)|\($0.sourceRef)|\($0.rowRole)" },
            displayOrderKey: { $0.displayOrderKey },
            revision: { _ in nil },
            hasSameImmutableIdentity: { lhs, rhs in
                lhs.schemaVersion == rhs.schemaVersion
                    && lhs.identityVersion == rhs.identityVersion
                    && lhs.projectionEngineVersion == rhs.projectionEngineVersion
                    && lhs.sourceHostID == rhs.sourceHostID
                    && lhs.view == rhs.view
                    && lhs.projectionStorageKey == rhs.projectionStorageKey
                    && lhs.sourceRef == rhs.sourceRef
                    && lhs.rowRole == rhs.rowRole
            }
        )
    }
}

extension ProjectionReducerPolicy where Row == ThreadDetailEventDTO {
    static func threadDetail(threadID: String) -> Self {
        ProjectionReducerPolicy(
            expectedSchemaVersion: ThreadDetailProjectionContract.schemaVersion,
            expectedIdentityVersion: ThreadDetailProjectionContract.identityVersion,
            expectedProjectionEngineVersion: ThreadDetailProjectionContract.projectionEngineVersion,
            expectedView: ThreadDetailProjectionContract.view,
            expectedScope: "thread",
            expectedOrder: ThreadDetailProjectionContract.order,
            requiredThreadID: threadID,
            isStoredRow: { _ in true },
            rowSchemaVersion: { $0.schemaVersion },
            rowIdentityVersion: { $0.identityVersion },
            rowProjectionEngineVersion: { $0.projectionEngineVersion },
            projectionID: { $0.projectionID },
            sourceHostID: { $0.sourceHostID },
            view: { $0.view },
            threadID: { $0.threadID },
            sourceKey: { "\($0.sourceHostID)|\($0.view)|\($0.threadID)|\($0.sourceRef)|\($0.rowRole)" },
            displayOrderKey: { $0.displayOrderKey },
            revision: { $0.revision },
            hasSameImmutableIdentity: { lhs, rhs in
                lhs.schemaVersion == rhs.schemaVersion
                    && lhs.identityVersion == rhs.identityVersion
                    && lhs.projectionEngineVersion == rhs.projectionEngineVersion
                    && lhs.sourceHostID == rhs.sourceHostID
                    && lhs.view == rhs.view
                    && lhs.threadID == rhs.threadID
                    && lhs.projectionID == rhs.projectionID
                    && lhs.sourceRef == rhs.sourceRef
                    && lhs.rowRole == rhs.rowRole
            }
        )
    }
}

private extension ProjectionWindow {
    init(_ window: DockStreamWindowDTO) {
        self.init(
            offset: window.offset,
            limit: window.limit,
            rowCount: window.rowCount,
            nextOffset: window.nextOffset
        )
    }
}

private extension ProjectionUpdateKind {
    init(_ kind: DockStreamKind) {
        switch kind {
        case .snapshot:
            self = .snapshot
        case .page:
            self = .page
        case .upsert:
            self = .upsert
        case .delete:
            self = .delete
        case .heartbeat:
            self = .heartbeat
        case .resyncRequired:
            self = .resyncRequired
        }
    }

    init(_ kind: ThreadDetailUpdateKind) {
        switch kind {
        case .snapshot:
            self = .snapshot
        case .page:
            self = .page
        case .upsert:
            self = .upsert
        case .delete:
            self = .delete
        case .heartbeat:
            self = .heartbeat
        case .resyncRequired:
            self = .resyncRequired
        }
    }
}

enum ThreadDetailProjectionContract {
    static let schemaVersion = 1
    static let identityVersion = 1
    static let projectionEngineVersion = 1
    static let view = "thread.detail"
    static let order = "displayOrderKeyAscending"
}

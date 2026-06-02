import Foundation

enum ThreadCardTableResyncReason: String, Equatable, Sendable {
    case schemaMismatch
    case streamContract
    case epochMismatch
    case sequenceGap
    case staleGeneration
}

enum ThreadCardTableApplyResult: Equatable, Sendable {
    case applied
    case needsResync(ThreadCardTableResyncReason)
}

struct ThreadCardTable: Equatable, Sendable {
    private enum ProjectionEnvelope {
        static let schemaVersion = 1
        static let identityVersion = 1
        static let engineVersion = 1
        static let rowRole = "threadCard"
        static let scope = "view"
        static let order = "displayOrderKeyAscending"
    }

    private struct HostStreamState: Equatable, Sendable {
        var epoch: String?
        var seq: Int64
        var sourceHostID: String?
        var status: DockHostLoadStatus
        var freshness: DockStreamFreshnessDTO?
        var complete: Bool
        var totalRows: Int?
        var window: DockStreamWindowDTO?
        var cardsByID: [String: DockThreadCardDTO]

        init(status: DockHostLoadStatus = .checking) {
            self.epoch = nil
            self.seq = 0
            self.status = status
            self.freshness = nil
            self.complete = false
            self.totalRows = nil
            self.window = nil
            self.cardsByID = [:]
        }
    }

    private let expectedView: ThreadCardStreamView
    private var statesByHostID: [String: HostStreamState] = [:]

    init(expectedView: ThreadCardStreamView = .dock) {
        self.expectedView = expectedView
    }

    mutating func reset(hosts: [DockHostConfiguration]) {
        statesByHostID = Dictionary(
            uniqueKeysWithValues: hosts.map { host in
                (host.id, HostStreamState())
            }
        )
    }

    mutating func ensureHosts(_ hosts: [DockHostConfiguration]) {
        let validHostIDs = Set(hosts.map(\.id))
        statesByHostID = statesByHostID.filter { validHostIDs.contains($0.key) }
        for host in hosts where statesByHostID[host.id] == nil {
            statesByHostID[host.id] = HostStreamState()
        }
    }

    mutating func markChecking(host: DockHostConfiguration) {
        var state = statesByHostID[host.id] ?? HostStreamState()
        let rowCount = state.cardsByID.count
        state.status = rowCount > 0
            ? .degraded(rowCount: rowCount, message: "Reconnecting")
            : .checking
        statesByHostID[host.id] = state
    }

    mutating func markFailure(_ failure: DockRequestFailure, host: DockHostConfiguration) {
        var state = statesByHostID[host.id] ?? HostStreamState()
        let message = failure.localizedDescription
        let rowCount = state.cardsByID.count
        switch failure {
        case .offline:
            state.status = rowCount > 0 ? .degraded(rowCount: rowCount, message: "Offline: \(message)") : .offline(message)
            state.freshness = DockStreamFreshnessDTO(status: .offline, lastError: message)
        case .error:
            state.status = rowCount > 0 ? .degraded(rowCount: rowCount, message: message) : .error(message)
            state.freshness = DockStreamFreshnessDTO(status: .error, lastError: message)
        }
        statesByHostID[host.id] = state
    }

    mutating func applySnapshot(_ update: ThreadCardStreamUpdateDTO, host: DockHostConfiguration) -> ThreadCardTableApplyResult {
        guard acceptsSchemaVersion(update.schemaVersion) else {
            return .needsResync(.schemaMismatch)
        }
        guard acceptsStreamContract(update) else {
            return .needsResync(.streamContract)
        }

        var state = statesByHostID[host.id] ?? HostStreamState()
        if state.epoch == nil || state.epoch == update.epoch {
        }
        state.epoch = update.epoch
        state.seq = update.seq
        state.sourceHostID = update.sourceHostID
        state.freshness = update.freshness
        state.complete = update.complete ?? false
        state.totalRows = update.totalRows
        state.window = update.window
        state.cardsByID = Dictionary(
            uniqueKeysWithValues: (update.rows ?? [])
                .filter(\.isAppFacingHumanThreadCard)
                .map { card in
                    (card.projectionStorageKey, card)
                }
        )
        state.status = hostStatus(
            freshness: update.freshness,
            rowCount: state.cardsByID.count,
            complete: state.complete,
            totalRows: state.totalRows,
            window: state.window
        )
        statesByHostID[host.id] = state
        return .applied
    }

    mutating func applyUpdate(_ update: ThreadCardStreamUpdateDTO, host: DockHostConfiguration) -> ThreadCardTableApplyResult {
        guard update.kind != .snapshot else {
            return applySnapshot(update, host: host)
        }

        guard acceptsSchemaVersion(update.schemaVersion) else {
            return .needsResync(.schemaMismatch)
        }
        guard var state = statesByHostID[host.id],
              state.epoch == update.epoch else {
            return .needsResync(.epochMismatch)
        }
        guard acceptsStreamContract(update, expectedSourceHostID: state.sourceHostID) else {
            return .needsResync(.streamContract)
        }
        guard acceptsProjectionSourceContinuity(update.rows ?? [], existingCardsByID: state.cardsByID) else {
            return .needsResync(.streamContract)
        }
        switch update.kind {
        case .heartbeat:
            guard state.seq == update.seq else {
                return .needsResync(.sequenceGap)
            }
        case .upsert, .delete:
            guard update.seq == state.seq + 1 else {
                return .needsResync(.sequenceGap)
            }
            for projectionID in update.projectionIDs ?? [] {
                state.cardsByID.removeValue(forKey: projectionID)
            }
            for card in (update.rows ?? []).filter(\.isAppFacingHumanThreadCard) {
                state.cardsByID[card.projectionStorageKey] = card
            }
            state.seq = update.seq
        case .resyncRequired:
            return .needsResync(.streamContract)
        case .snapshot:
            break
        }

        state.freshness = update.freshness
        state.complete = update.complete ?? state.complete
        state.totalRows = update.totalRows ?? state.totalRows
        state.window = update.window ?? state.window
        state.status = hostStatus(
            freshness: state.freshness,
            rowCount: state.cardsByID.count,
            complete: state.complete,
            totalRows: state.totalRows,
            window: state.window
        )
        statesByHostID[host.id] = state
        return .applied
    }

    private func acceptsSchemaVersion(_ schemaVersion: Int) -> Bool {
        return schemaVersion == CodexDockConstants.Dock.streamSchemaVersion
    }

    private func acceptsStreamContract(
        _ update: ThreadCardStreamUpdateDTO,
        expectedSourceHostID: String? = nil
    ) -> Bool {
        guard let sourceHostID = nonEmpty(update.sourceHostID),
              update.identityVersion == ProjectionEnvelope.identityVersion,
              update.projectionEngineVersion == ProjectionEnvelope.engineVersion,
              update.scope == ProjectionEnvelope.scope,
              nonEmpty(update.viewParamsKey) != nil,
              update.order == ProjectionEnvelope.order else {
            return false
        }
        if let expectedSourceHostID,
           expectedSourceHostID != sourceHostID {
            return false
        }
        guard update.view == expectedView else {
            return false
        }
        switch update.kind {
        case .snapshot:
            guard let complete = update.complete,
                  let totalRows = update.totalRows,
                  let window = update.window else {
                return false
            }
            return acceptsWindowContract(
                complete: complete,
                totalRows: totalRows,
                window: window,
                    cardCount: update.rows?.count ?? 0
            )
                && acceptsProjectionEnvelope(update.rows ?? [], sourceHostID: sourceHostID)
        case .upsert, .delete, .heartbeat, .resyncRequired:
            guard acceptsProjectionEnvelope(update.rows ?? [], sourceHostID: sourceHostID),
                  acceptsDeleteIDs(update.projectionIDs ?? []) else {
                return false
            }
            if update.complete == false {
                guard let totalRows = update.totalRows,
                      let window = update.window else {
                    return false
                }
                return acceptsWindowContract(
                    complete: false,
                    totalRows: totalRows,
                    window: window,
                    cardCount: update.rows?.count ?? 0
                )
            }
            return true
        }
    }

    private func acceptsWindowContract(
        complete: Bool,
        totalRows: Int,
        window: DockStreamWindowDTO,
        cardCount: Int
    ) -> Bool {
        guard totalRows >= 0,
              window.offset >= 0,
              window.limit >= 0,
              window.rowCount >= 0,
              window.rowCount == cardCount else {
            return false
        }
        if let nextOffset = window.nextOffset,
           nextOffset <= window.offset {
            return false
        }
        return complete || window.rowCount <= totalRows
    }

    private func acceptsProjectionEnvelope(_ cards: [DockThreadCardDTO], sourceHostID expectedSourceHostID: String) -> Bool {
        var seenProjectionIDs = Set<String>()
        var seenSourceKeys = Set<ThreadCardProjectionSourceKey>()
        for card in cards {
            guard let sourceHostID = nonEmpty(card.sourceHostID) else {
                return false
            }
            guard card.schemaVersion == ProjectionEnvelope.schemaVersion
                && card.identityVersion == ProjectionEnvelope.identityVersion
                && card.projectionEngineVersion == ProjectionEnvelope.engineVersion
                && sourceHostID == expectedSourceHostID
                && card.logicalHostID == sourceHostID
                && card.view == expectedView.rawValue
                && nonEmpty(card.projectionID) != nil
                && card.id == card.projectionID
                && nonEmpty(card.sourceRef) != nil
                && card.rowRole == ProjectionEnvelope.rowRole
                && nonEmpty(card.displayOrderKey) != nil else {
                return false
            }
            guard seenProjectionIDs.insert(card.projectionID).inserted else {
                return false
            }
            guard seenSourceKeys.insert(ThreadCardProjectionSourceKey(card)).inserted else {
                return false
            }
        }
        return true
    }

    private func acceptsProjectionSourceContinuity(
        _ cards: [DockThreadCardDTO],
        existingCardsByID: [String: DockThreadCardDTO]
    ) -> Bool {
        var existingProjectionIDsBySourceKey = [ThreadCardProjectionSourceKey: String]()
        for card in existingCardsByID.values {
            let sourceKey = ThreadCardProjectionSourceKey(card)
            if existingProjectionIDsBySourceKey.updateValue(card.projectionStorageKey, forKey: sourceKey) != nil {
                return false
            }
        }
        for card in cards {
            let sourceKey = ThreadCardProjectionSourceKey(card)
            if let existing = existingCardsByID[card.projectionStorageKey],
               ThreadCardProjectionSourceKey(existing) != sourceKey {
                return false
            }
            if let existingProjectionID = existingProjectionIDsBySourceKey[sourceKey],
               existingProjectionID != card.projectionStorageKey {
                return false
            }
        }
        return true
    }

    private func acceptsDeleteIDs(_ ids: [String]) -> Bool {
        ids.allSatisfy { nonEmpty($0) != nil }
    }

    private func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    func snapshot(
        hosts: [DockHostConfiguration],
        localMetadata: [LocalThreadMetadataKey: LocalThreadMetadata],
        now: @escaping @Sendable () -> Date
    ) -> DockSnapshot {
        DockRenderProjector(now: now).snapshot(
            from: renderInput(hosts: hosts),
            localMetadata: localMetadata
        )
    }

    func renderInput(hosts: [DockHostConfiguration]) -> DockRenderInput {
        let hostStates = hosts.map { host in
            DockHostStateViewModel(
                host: DockHostViewModel(host: host),
                status: statesByHostID[host.id]?.status ?? .checking
            )
        }
        let statuses = Dictionary(
            uniqueKeysWithValues: hostStates.map { ($0.host.id, $0.status) }
        )
        return DockRenderInput(
            hosts: hosts,
            hostStates: hostStates,
            hostIdentityResolver: DockHostIdentityResolver(
                hosts: hosts,
                observations: identityObservations(hosts: hosts),
                hostStatuses: statuses
            ),
            cardsByHostID: Dictionary(
                uniqueKeysWithValues: hosts.map { host in
                    (host.id, sortedCards(for: host))
                }
            ),
            isPartial: hosts.contains(where: needsProgressContext)
        )
    }

    func rowCount(for host: DockHostConfiguration) -> Int {
        statesByHostID[host.id]?.cardsByID.count ?? 0
    }

    func hostIdentityResolver(hosts: [DockHostConfiguration]) -> DockHostIdentityResolver {
        DockHostIdentityResolver(
            hosts: hosts,
            observations: identityObservations(hosts: hosts),
            hostStatuses: Dictionary(
                uniqueKeysWithValues: hosts.map { host in
                    (host.id, statesByHostID[host.id]?.status ?? .checking)
                }
            )
        )
    }

    private func sortedCards(for host: DockHostConfiguration) -> [DockThreadCardDTO] {
        guard let state = statesByHostID[host.id] else {
            return []
        }
        return Array(state.cardsByID.values)
            .sorted { lhs, rhs in
                if lhs.displayOrderKey != rhs.displayOrderKey {
                    return lhs.displayOrderKey < rhs.displayOrderKey
                }
                return lhs.projectionStorageKey < rhs.projectionStorageKey
            }
    }

    private func identityObservations(hosts: [DockHostConfiguration]) -> [DockHostIdentityObservation] {
        hosts.flatMap { host in
            guard let state = statesByHostID[host.id] else {
                return [DockHostIdentityObservation]()
            }
            var observations = [DockHostIdentityObservation(
                configuredHostID: host.id,
                streamHostID: state.sourceHostID
            )]
            let cardObservations = state.cardsByID.values.map { card in
                DockHostIdentityObservation(configuredHostID: host.id, card: card)
            }
            observations.append(contentsOf: cardObservations)
            return observations
        }
    }

    private func needsProgressContext(_ host: DockHostConfiguration) -> Bool {
        let status = statesByHostID[host.id]?.status
        if case .checking = status {
            return true
        }
        return status?.isDegraded == true
    }

    private func hostStatus(
        freshness: DockStreamFreshnessDTO?,
        rowCount: Int,
        complete: Bool,
        totalRows: Int?,
        window: DockStreamWindowDTO?
    ) -> DockHostLoadStatus {
        let loadedWindow = hostWindow(rowCount: rowCount, complete: complete, totalRows: totalRows, window: window)
        guard let freshness else {
            return rowCount == 0 && loadedWindow == nil ? .checking : .loaded(rowCount: rowCount, window: loadedWindow)
        }
        switch freshness.status {
        case .fresh:
            if rowCount == 0, loadedWindow == nil {
                return .empty
            }
            return .loaded(rowCount: rowCount, window: loadedWindow)
        case .stale:
            return .degraded(rowCount: rowCount, message: freshness.lastError ?? "Stale")
        case .offline:
            let message = freshness.lastError ?? "Offline"
            return rowCount > 0 ? .degraded(rowCount: rowCount, message: "Offline: \(message)") : .offline(message)
        case .error:
            let message = freshness.lastError ?? "Error"
            return rowCount > 0 ? .degraded(rowCount: rowCount, message: message) : .error(message)
        case .unknown:
            return rowCount == 0 ? .checking : .loaded(rowCount: rowCount, window: loadedWindow)
        }
    }

    private func hostWindow(
        rowCount: Int,
        complete: Bool,
        totalRows: Int?,
        window: DockStreamWindowDTO?
    ) -> DockHostWindow? {
        guard !complete else {
            return nil
        }
        let visibleRows = rowCount
        let knownTotal = max(totalRows ?? window?.rowCount ?? visibleRows, visibleRows)
        return DockHostWindow(visibleRows: visibleRows, totalRows: knownTotal)
    }
}

private struct ThreadCardProjectionSourceKey: Hashable, Sendable {
    let sourceHostID: String
    let view: String
    let sourceRef: String
    let rowRole: String

    init(_ card: DockThreadCardDTO) {
        sourceHostID = card.sourceHostID
        view = card.view
        sourceRef = card.sourceRef
        rowRole = card.rowRole
    }
}

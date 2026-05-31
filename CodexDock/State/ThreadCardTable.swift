import Foundation

enum ThreadCardTableResyncReason: String, Equatable, Sendable {
    case schemaMismatch
    case streamContract
    case epochMismatch
    case sequenceGap
}

enum ThreadCardTableApplyResult: Equatable, Sendable {
    case applied
    case needsResync(ThreadCardTableResyncReason)
}

struct ThreadCardTable: Equatable, Sendable {
    private struct HostStreamState: Equatable, Sendable {
        var epoch: String?
        var seq: Int64
        var status: DockHostLoadStatus
        var freshness: DockStreamFreshnessDTO?
        var complete: Bool
        var totalRows: Int?
        var window: DockStreamWindowDTO?
        var streamHosts: [DockStreamHostDTO]
        var cardsByID: [String: DockThreadCardDTO]

        init(status: DockHostLoadStatus = .checking) {
            self.epoch = nil
            self.seq = 0
            self.status = status
            self.freshness = nil
            self.complete = false
            self.totalRows = nil
            self.window = nil
            self.streamHosts = []
            self.cardsByID = [:]
        }
    }

    private var statesByHostID: [String: HostStreamState] = [:]

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
            ? .partial(rowCount: rowCount, message: "Reconnecting")
            : .checking
        statesByHostID[host.id] = state
    }

    mutating func markFailure(_ failure: DockRequestFailure, host: DockHostConfiguration) {
        var state = statesByHostID[host.id] ?? HostStreamState()
        let message = failure.localizedDescription
        let rowCount = state.cardsByID.count
        switch failure {
        case .offline:
            state.status = rowCount > 0 ? .partial(rowCount: rowCount, message: "Offline: \(message)") : .offline(message)
            state.freshness = DockStreamFreshnessDTO(status: .offline, lastError: message)
        case .error:
            state.status = rowCount > 0 ? .partial(rowCount: rowCount, message: message) : .error(message)
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
        state.epoch = update.epoch
        state.seq = update.seq
        state.freshness = update.freshness
        state.complete = update.complete ?? false
        state.totalRows = update.totalRows
        state.window = update.window
        state.streamHosts = update.hosts ?? []
        state.cardsByID = Dictionary(
            uniqueKeysWithValues: (update.cards ?? [])
                .filter(\.isAppFacingHumanThreadCard)
                .map { card in
                    (card.id, card)
                }
        )
        state.status = hostStatus(
            freshness: update.freshness,
            rowCount: state.cardsByID.count,
            complete: state.complete,
            totalRows: state.totalRows
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
        guard acceptsStreamContract(update) else {
            return .needsResync(.streamContract)
        }

        guard var state = statesByHostID[host.id],
              state.epoch == update.epoch else {
            return .needsResync(.epochMismatch)
        }

        switch update.kind {
        case .heartbeat:
            guard state.seq == update.seq else {
                return .needsResync(.sequenceGap)
            }
        case .delta:
            guard update.baseSeq == state.seq else {
                return .needsResync(.sequenceGap)
            }
            for host in update.upsertHosts ?? [] {
                state.streamHosts.removeAll { $0.id == host.id }
                state.streamHosts.append(host)
            }
            for card in (update.upsertCards ?? []).filter(\.isAppFacingHumanThreadCard) {
                state.cardsByID[card.id] = card
            }
            for cardID in update.deleteCardIDs ?? [] {
                state.cardsByID.removeValue(forKey: cardID)
            }
            state.seq = update.seq
        case .snapshot:
            break
        }

        state.freshness = update.freshness ?? state.freshness
        state.complete = update.complete ?? state.complete
        state.totalRows = update.totalRows ?? state.totalRows
        state.window = update.window ?? state.window
        state.status = hostStatus(
            freshness: state.freshness,
            rowCount: state.cardsByID.count,
            complete: state.complete,
            totalRows: state.totalRows
        )
        statesByHostID[host.id] = state
        return .applied
    }

    private func acceptsSchemaVersion(_ schemaVersion: Int?) -> Bool {
        guard let schemaVersion else {
            return false
        }
        return schemaVersion == CodexDockConstants.Dock.streamSchemaVersion
    }

    private func acceptsStreamContract(_ update: ThreadCardStreamUpdateDTO) -> Bool {
        guard update.view == .dock else {
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
                cardCount: update.cards?.count ?? 0
            )
        case .delta, .heartbeat:
            if update.complete == false {
                guard let totalRows = update.totalRows,
                      let window = update.window else {
                    return false
                }
                return acceptsWindowContract(
                    complete: false,
                    totalRows: totalRows,
                    window: window,
                    cardCount: update.upsertCards?.count ?? 0
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
            isPartial: hosts.contains(where: isCheckingOrPartial)
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
                if lhs.orderKey != rhs.orderKey {
                    return lhs.orderKey < rhs.orderKey
                }
                return lhs.id < rhs.id
            }
    }

    private func identityObservations(hosts: [DockHostConfiguration]) -> [DockHostIdentityObservation] {
        hosts.flatMap { host in
            guard let state = statesByHostID[host.id] else {
                return [DockHostIdentityObservation]()
            }
            let hostObservations = state.streamHosts.map { streamHost in
                DockHostIdentityObservation(configuredHostID: host.id, streamHost: streamHost)
            }
            let cardObservations = state.cardsByID.values.map { card in
                DockHostIdentityObservation(configuredHostID: host.id, card: card)
            }
            return hostObservations + cardObservations
        }
    }

    private func isCheckingOrPartial(_ host: DockHostConfiguration) -> Bool {
        let status = statesByHostID[host.id]?.status
        if case .checking = status {
            return true
        }
        return status?.isPartial == true
    }

    private func hostStatus(
        freshness: DockStreamFreshnessDTO?,
        rowCount: Int,
        complete: Bool,
        totalRows: Int?
    ) -> DockHostLoadStatus {
        if !complete {
            let visibleRows = rowCount
            let knownTotal = max(totalRows ?? visibleRows, visibleRows)
            let message = knownTotal > visibleRows
                ? "Showing \(visibleRows) of \(knownTotal)"
                : "Partial window"
            return .partial(rowCount: visibleRows, message: message)
        }
        guard let freshness else {
            return rowCount == 0 ? .checking : .loaded(rowCount: rowCount)
        }
        switch freshness.status {
        case .fresh:
            return rowCount == 0 ? .empty : .loaded(rowCount: rowCount)
        case .stale:
            return .partial(rowCount: rowCount, message: freshness.lastError ?? "Stale")
        case .offline:
            let message = freshness.lastError ?? "Offline"
            return rowCount > 0 ? .partial(rowCount: rowCount, message: "Offline: \(message)") : .offline(message)
        case .error:
            let message = freshness.lastError ?? "Error"
            return rowCount > 0 ? .partial(rowCount: rowCount, message: message) : .error(message)
        case .unknown:
            return rowCount == 0 ? .checking : .partial(rowCount: rowCount, message: "Refreshing")
        }
    }

}

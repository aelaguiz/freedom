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

struct ThreadCardTable: Sendable {
    private struct HostStreamState: Sendable {
        var projection = ProjectionReducer<DockThreadCardDTO>()
        var status: DockHostLoadStatus = .checking
        var freshness: DockStreamFreshnessDTO?
        var complete = false
        var totalRows: Int?
        var window: DockStreamWindowDTO?
    }

    private let expectedView: ThreadCardStreamView
    private var statesByHostID: [String: HostStreamState] = [:]
    private var policy: ProjectionReducerPolicy<DockThreadCardDTO> {
        .threadCards(expectedView: expectedView)
    }

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
        let rowCount = state.projection.rowCount
        state.status = rowCount > 0
            ? .degraded(rowCount: rowCount, message: "Reconnecting")
            : .checking
        statesByHostID[host.id] = state
    }

    mutating func markFailure(_ failure: DockRequestFailure, host: DockHostConfiguration) {
        var state = statesByHostID[host.id] ?? HostStreamState()
        let message = failure.localizedDescription
        let rowCount = state.projection.rowCount
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
        guard update.kind == .snapshot else {
            return .needsResync(.streamContract)
        }
        return apply(update, host: host)
    }

    mutating func applyUpdate(_ update: ThreadCardStreamUpdateDTO, host: DockHostConfiguration) -> ThreadCardTableApplyResult {
        guard update.kind != .snapshot else {
            return applySnapshot(update, host: host)
        }
        return apply(update, host: host)
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
        statesByHostID[host.id]?.projection.rowCount ?? 0
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

    private mutating func apply(_ update: ThreadCardStreamUpdateDTO, host: DockHostConfiguration) -> ThreadCardTableApplyResult {
        var state = statesByHostID[host.id] ?? HostStreamState()
        do {
            // Relay projection owns visible card identity, order, revision, and
            // catch-up semantics. Stores and render projectors decorate only.
            try state.projection.apply(ProjectionEnvelope(update), policy: policy)
        } catch let error as ProjectionReducerError {
            return .needsResync(Self.map(error))
        } catch {
            return .needsResync(.streamContract)
        }

        state.freshness = update.freshness
        state.complete = update.complete ?? state.complete
        state.totalRows = update.totalRows ?? state.totalRows
        state.window = update.window ?? state.window
        state.status = hostStatus(
            freshness: state.freshness,
            rowCount: state.projection.rowCount,
            complete: state.complete,
            totalRows: state.totalRows,
            window: state.window
        )
        statesByHostID[host.id] = state
        return .applied
    }

    private static func map(_ error: ProjectionReducerError) -> ThreadCardTableResyncReason {
        switch error {
        case .schemaMismatch:
            return .schemaMismatch
        case .streamContract, .resyncRequired:
            return .streamContract
        case .epochMismatch:
            return .epochMismatch
        case .sequenceGap:
            return .sequenceGap
        }
    }

    private func sortedCards(for host: DockHostConfiguration) -> [DockThreadCardDTO] {
        statesByHostID[host.id]?.projection.sortedRows(policy: policy) ?? []
    }

    private func identityObservations(hosts: [DockHostConfiguration]) -> [DockHostIdentityObservation] {
        hosts.flatMap { host in
            guard let state = statesByHostID[host.id] else {
                return [DockHostIdentityObservation]()
            }
            var observations = [DockHostIdentityObservation(
                configuredHostID: host.id,
                streamHostID: state.projection.sourceHostID
            )]
            let cardObservations = state.projection.rows.map { card in
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

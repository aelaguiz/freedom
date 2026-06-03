import Foundation

struct ThreadCardProjectionState: Sendable {
    private struct HostProjection: Sendable {
        var sourceHostID: String?
        var cards: [DockThreadCardDTO] = []
        var freshness: StreamReconcilerFreshnessState = .connecting
        var complete: Bool?
        var totalRows: Int?
        var window: ProjectionWindow?
    }

    private var statesByHostID: [String: HostProjection] = [:]

    mutating func reset(hosts: [DockHostConfiguration]) {
        statesByHostID = Dictionary(
            uniqueKeysWithValues: hosts.map { ($0.id, HostProjection()) }
        )
    }

    mutating func ensureHosts(_ hosts: [DockHostConfiguration]) {
        let validHostIDs = Set(hosts.map(\.id))
        statesByHostID = statesByHostID.filter { validHostIDs.contains($0.key) }
        for host in hosts where statesByHostID[host.id] == nil {
            statesByHostID[host.id] = HostProjection()
        }
    }

    mutating func apply(
        _ snapshot: StreamReconcilerSnapshot<DockThreadCardDTO>,
        host: DockHostConfiguration
    ) {
        var state = statesByHostID[host.id] ?? HostProjection()
        state.sourceHostID = snapshot.viewKey.sourceHostID ?? state.sourceHostID
        state.cards = snapshot.rows
        state.freshness = snapshot.freshness
        state.complete = snapshot.complete ?? state.complete
        state.totalRows = snapshot.totalRows ?? state.totalRows
        state.window = snapshot.window ?? state.window
        statesByHostID[host.id] = state
    }

    func rowCount(for host: DockHostConfiguration) -> Int {
        statesByHostID[host.id]?.cards.count ?? 0
    }

    func renderInput(hosts: [DockHostConfiguration]) -> DockRenderInput {
        let hostStates = hosts.map { host in
            DockHostStateViewModel(
                host: DockHostViewModel(host: host),
                status: hostStatus(for: host)
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
                    (host.id, statesByHostID[host.id]?.cards ?? [])
                }
            ),
            isPartial: hosts.contains(where: needsProgressContext)
        )
    }

    func hostIdentityResolver(hosts: [DockHostConfiguration]) -> DockHostIdentityResolver {
        DockHostIdentityResolver(
            hosts: hosts,
            observations: identityObservations(hosts: hosts),
            hostStatuses: Dictionary(
                uniqueKeysWithValues: hosts.map { ($0.id, hostStatus(for: $0)) }
            )
        )
    }

    private func hostStatus(for host: DockHostConfiguration) -> DockHostLoadStatus {
        guard let state = statesByHostID[host.id] else {
            return .checking
        }
        let rowCount = state.cards.count
        let loadedWindow = hostWindow(
            rowCount: rowCount,
            complete: state.complete,
            totalRows: state.totalRows,
            window: state.window
        )
        switch state.freshness {
        case .connecting, .subscribing:
            return rowCount > 0 ? .degraded(rowCount: rowCount, message: "Reconnecting") : .checking
        case .catchingUp(let reason):
            let message = reason == .manualRefresh ? "Refreshing" : "Reconnecting"
            return rowCount > 0 ? .degraded(rowCount: rowCount, message: message) : .checking
        case .live:
            if rowCount == 0, loadedWindow == nil {
                return .empty
            }
            return .loaded(rowCount: rowCount, window: loadedWindow)
        case .stale(let message):
            return .degraded(rowCount: rowCount, message: message)
        case .offline(let message):
            return rowCount > 0 ? .degraded(rowCount: rowCount, message: "Offline: \(message)") : .offline(message)
        case .failed(let message):
            return rowCount > 0 ? .degraded(rowCount: rowCount, message: message) : .error(message)
        case .closed:
            return rowCount == 0 ? .empty : .loaded(rowCount: rowCount, window: loadedWindow)
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
            observations.append(contentsOf: state.cards.map {
                DockHostIdentityObservation(configuredHostID: host.id, card: $0)
            })
            return observations
        }
    }

    private func needsProgressContext(_ host: DockHostConfiguration) -> Bool {
        let status = hostStatus(for: host)
        if case .checking = status {
            return true
        }
        return status.isDegraded
    }

    private func hostWindow(
        rowCount: Int,
        complete: Bool?,
        totalRows: Int?,
        window: ProjectionWindow?
    ) -> DockHostWindow? {
        guard complete != true else {
            return nil
        }
        let visibleRows = rowCount
        let knownTotal = max(totalRows ?? window?.rowCount ?? visibleRows, visibleRows)
        guard knownTotal > visibleRows else {
            return nil
        }
        return DockHostWindow(visibleRows: visibleRows, totalRows: knownTotal)
    }
}

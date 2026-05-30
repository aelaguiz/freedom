import Foundation

enum DockSessionTableResyncReason: String, Equatable, Sendable {
    case schemaMismatch
    case streamContract
    case epochMismatch
    case sequenceGap
}

enum DockSessionTableApplyResult: Equatable, Sendable {
    case applied
    case needsResync(DockSessionTableResyncReason)
}

struct DockSessionTable: Equatable, Sendable {
    private struct HostStreamState: Equatable, Sendable {
        var epoch: String?
        var seq: Int64
        var status: DockHostLoadStatus
        var freshness: DockStreamFreshnessDTO?
        var complete: Bool
        var totalRows: Int?
        var window: DockStreamWindowDTO?
        var sessionsByID: [String: DockStreamSessionDTO]

        init(status: DockHostLoadStatus = .checking) {
            self.epoch = nil
            self.seq = 0
            self.status = status
            self.freshness = nil
            self.complete = false
            self.totalRows = nil
            self.window = nil
            self.sessionsByID = [:]
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
        let rowCount = state.sessionsByID.count
        state.status = rowCount > 0
            ? .partial(rowCount: rowCount, message: "Reconnecting")
            : .checking
        statesByHostID[host.id] = state
    }

    mutating func markFailure(_ failure: DockLoadFailure, host: DockHostConfiguration) {
        var state = statesByHostID[host.id] ?? HostStreamState()
        let message = failure.localizedDescription
        let rowCount = state.sessionsByID.count
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

    mutating func applySnapshot(_ update: DockStreamUpdateDTO, host: DockHostConfiguration) -> DockSessionTableApplyResult {
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
        state.sessionsByID = Dictionary(
            uniqueKeysWithValues: (update.sessions ?? []).map { session in
                (session.id, session)
            }
        )
        state.status = hostStatus(
            freshness: update.freshness,
            rowCount: state.sessionsByID.count,
            complete: state.complete,
            totalRows: state.totalRows,
            window: state.window
        )
        statesByHostID[host.id] = state
        return .applied
    }

    mutating func applyUpdate(_ update: DockStreamUpdateDTO, host: DockHostConfiguration) -> DockSessionTableApplyResult {
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
            for session in update.upsertSessions ?? [] {
                state.sessionsByID[session.id] = session
            }
            for sessionID in update.deleteSessionIDs ?? [] {
                state.sessionsByID.removeValue(forKey: sessionID)
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
            rowCount: state.sessionsByID.count,
            complete: state.complete,
            totalRows: state.totalRows,
            window: state.window
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

    private func acceptsStreamContract(_ update: DockStreamUpdateDTO) -> Bool {
        guard update.view == "dock" else {
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
                sessionCount: update.sessions?.count ?? 0
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
                    sessionCount: update.upsertSessions?.count ?? 0
                )
            }
            return true
        }
    }

    private func acceptsWindowContract(
        complete: Bool,
        totalRows: Int,
        window: DockStreamWindowDTO,
        sessionCount: Int
    ) -> Bool {
        guard totalRows >= 0,
              window.offset >= 0,
              window.limit >= 0,
              window.rowCount >= 0,
              window.rowCount == sessionCount || !complete else {
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
        let summaries = hosts.flatMap { host in
            sortedSessions(for: host).map { session in
                summary(from: session, host: host)
            }
        }
        let projector = SessionRowProjector(
            hosts: hosts,
            localMetadata: localMetadata,
            now: now
        )
        let liveRows = projector.rows(from: summaries)
        let loadedKeys = Set(liveRows.map(\.metadataKey))
        let rows = liveRows + projector.cachedPinnedRows(excluding: loadedKeys)
        return DockSnapshot(
            host: DockHostViewModel(host: hosts[0]),
            hosts: hosts.map(DockHostViewModel.init),
            hostStates: hosts.map { host in
                DockHostStateViewModel(
                    host: DockHostViewModel(host: host),
                    status: statesByHostID[host.id]?.status ?? .checking
                )
            },
            rows: rows,
            mappingFailures: [],
            isPartial: hosts.contains(where: isCheckingOrPartial)
        )
    }

    func rowCount(for host: DockHostConfiguration) -> Int {
        statesByHostID[host.id]?.sessionsByID.count ?? 0
    }

    private func sortedSessions(for host: DockHostConfiguration) -> [DockStreamSessionDTO] {
        guard let state = statesByHostID[host.id] else {
            return []
        }
        return Array(state.sessionsByID.values)
            .sorted { lhs, rhs in
                let lhsUpdated = lhs.messageUpdatedAt ?? Int64.min
                let rhsUpdated = rhs.messageUpdatedAt ?? Int64.min
                if lhsUpdated != rhsUpdated {
                    return lhsUpdated > rhsUpdated
                }
                return lhs.id < rhs.id
            }
    }

    private func isCheckingOrPartial(_ host: DockHostConfiguration) -> Bool {
        let status = statesByHostID[host.id]?.status
        if case .checking = status {
            return true
        }
        return status?.isPartial == true
    }

    private func summary(from session: DockStreamSessionDTO, host: DockHostConfiguration) -> SessionSummary {
        let threadID = nonEmpty(session.threadID) ?? session.id
        return SessionSummary(
            id: HostScopedThreadID(hostID: host.id, threadID: threadID),
            backendSessionID: nonEmpty(session.backendSessionID) ?? threadID,
            displayTitle: nonEmpty(session.title) ?? "Thread \(shortThreadID(threadID))",
            status: sessionStatus(from: session.status),
            repository: text(from: session.repository),
            workingDirectory: text(from: session.workingDirectory),
            branch: text(from: session.branch),
            lastActivity: Date(timeIntervalSince1970: TimeInterval(session.updatedAt ?? 0)),
            shortEventSummary: text(from: session.messageSummary),
            messageActivityDate: session.messageUpdatedAt.map {
                Date(timeIntervalSince1970: TimeInterval($0))
            },
            origin: origin(from: session)
        )
    }

    private func hostStatus(
        freshness: DockStreamFreshnessDTO?,
        rowCount: Int,
        complete: Bool,
        totalRows: Int?,
        window: DockStreamWindowDTO?
    ) -> DockHostLoadStatus {
        if !complete {
            let visibleRows = window?.rowCount ?? rowCount
            let knownTotal = totalRows ?? visibleRows
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

    private func sessionStatus(from status: DockStreamSessionStatus) -> SessionStatus {
        switch status {
        case .running:
            return .active(activeFlags: [])
        case .needsInput:
            return .active(activeFlags: [.waitingOnUserInput])
        case .needsApproval:
            return .active(activeFlags: [.waitingOnApproval])
        case .idle:
            return .idle
        case .error:
            return .systemError
        case .dormant:
            return .notLoaded
        case .unknown:
            return .unknown
        }
    }

    private func origin(from session: DockStreamSessionDTO) -> SessionOrigin {
        switch session.lane {
        case .human:
            return .humanInteractive(subtype: .cli)
        case .agent:
            return .agentOrAutomation(subtype: .exec)
        case .unknown:
            return .unknown()
        case nil:
            switch session.source?.kind {
            case .human:
                return .humanInteractive(subtype: .cli)
            case .automation:
                return .agentOrAutomation(subtype: .exec)
            case .unknown, nil:
                return .unknown()
            }
        }
    }

    private func text(from value: String?) -> SessionSummaryText {
        if let value = nonEmpty(value) {
            return .known(value)
        }
        return .unknown
    }

    private func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            return trimmed
        }
        return nil
    }

    private func shortThreadID(_ threadID: String) -> String {
        if threadID.count <= 12 {
            return threadID
        }
        return String(threadID.prefix(8))
    }
}

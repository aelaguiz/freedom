import Foundation

struct DockRenderProjector: Sendable {
    let now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    func snapshot(
        from input: DockRenderInput,
        localMetadata: [LocalThreadMetadataKey: LocalThreadMetadata]
    ) -> DockSnapshot {
        let summaries = input.hosts.flatMap { host in
            (input.sessionsByHostID[host.id] ?? []).map { session in
                summary(from: session, host: host)
            }
        }
        let rowProjector = SessionRowProjector(
            hosts: input.hosts,
            localMetadata: localMetadata,
            now: now
        )
        let liveRows = rowProjector.rows(from: summaries)
        let loadedKeys = Set(liveRows.map(\.metadataKey))
        let rows = liveRows + rowProjector.cachedPinnedRows(excluding: loadedKeys)

        return DockSnapshot(
            host: DockHostViewModel(host: input.hosts[0]),
            hosts: input.hosts.map(DockHostViewModel.init),
            hostStates: input.hostStates,
            rows: rows,
            mappingFailures: [],
            isPartial: input.isPartial
        )
    }

    func render(
        snapshot: DockSnapshot,
        options: DockProjectionOptions,
        revision: RenderRevision
    ) -> DockRenderSnapshot {
        DockRenderSnapshot(
            revision: revision,
            snapshot: snapshot,
            projection: snapshot.project(options: options)
        )
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

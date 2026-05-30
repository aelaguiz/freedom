import Foundation

enum SessionRowActivityMode: Equatable, Sendable {
    case dockMessage
    case raw
}

struct SessionRowProjector {
    let hosts: [DockHostConfiguration]
    let localMetadata: [LocalThreadMetadataKey: LocalThreadMetadata]
    let now: @Sendable () -> Date
    var activityMode: SessionRowActivityMode = .dockMessage

    func rows(from summaries: [SessionSummary]) -> [DockRowViewModel] {
        summaries.map(makeRow)
    }

    func cachedPinnedRows(excluding loadedKeys: Set<LocalThreadMetadataKey>) -> [DockRowViewModel] {
        let activeHostIDs = Set(hosts.map(\.id))
        return localMetadata.compactMap { key, metadata in
            guard metadata.isPinned,
                  !loadedKeys.contains(key),
                  activeHostIDs.contains(key.hostID) else {
                return nil
            }
            return cachedPinnedRow(key: key, metadata: metadata)
        }
    }

    func makeRow(summary: SessionSummary) -> DockRowViewModel {
        let metadata = localMetadata[
            LocalThreadMetadataKey(
                hostID: summary.id.hostID,
                backendSessionID: summary.backendSessionID,
                threadID: summary.id.threadID
            )
        ]
        let activity = activityDisplay(for: summary)
        return DockRowViewModel(
            id: summary.id,
            backendSessionID: summary.backendSessionID,
            title: title(for: summary),
            hostDisplayName: hostDisplayName(for: summary.id.hostID),
            hostEndpoint: hostEndpoint(for: summary.id.hostID),
            repository: repository(for: summary),
            branch: text(summary.branch, fallback: "No branch"),
            status: status(for: summary),
            lastActivity: activity.label,
            lastActivityDate: activity.date,
            summary: rowSummary(for: summary),
            rail: metadata?.rail ?? rail(for: summary),
            label: metadata?.label,
            origin: summary.origin,
            isPinned: metadata?.isPinned ?? false,
            pinnedAt: metadata?.pinnedAt,
            pinnedOrder: metadata?.pinnedOrder
        )
    }

    private func cachedPinnedRow(
        key: LocalThreadMetadataKey,
        metadata: LocalThreadMetadata
    ) -> DockRowViewModel {
        let snapshot = metadata.lastKnownPinnedDisplay
        let fallbackDate = metadata.pinnedAt ?? Date.distantPast
        return DockRowViewModel(
            id: HostScopedThreadID(hostID: key.hostID, threadID: key.threadID),
            backendSessionID: key.backendSessionID,
            title: nonEmpty(snapshot?.title) ?? "Not loaded",
            hostDisplayName: hostDisplayNameForCachedRow(hostID: key.hostID, snapshot: snapshot),
            hostEndpoint: hostEndpointForCachedRow(hostID: key.hostID, snapshot: snapshot),
            repository: nonEmpty(snapshot?.repository) ?? "Unknown workspace",
            branch: nonEmpty(snapshot?.branch) ?? "No branch",
            status: snapshot?.status ?? .dormant,
            lastActivity: nonEmpty(snapshot?.lastActivity) ?? "Not loaded",
            lastActivityDate: snapshot?.lastActivityDate ?? fallbackDate,
            summary: nonEmpty(snapshot?.summary) ?? "This pinned thread is not loaded yet.",
            rail: metadata.rail ?? snapshot?.rail ?? .blue,
            label: metadata.label ?? snapshot?.label,
            origin: snapshot?.originKind.sessionOrigin ?? .unknown(),
            isPinned: true,
            pinnedAt: metadata.pinnedAt,
            pinnedOrder: metadata.pinnedOrder
        )
    }

    private func title(for summary: SessionSummary) -> String {
        nonEmpty(summary.displayTitle) ?? "Thread \(shortThreadID(summary.id.threadID))"
    }

    private func repository(for summary: SessionSummary) -> String {
        if let repo = nonEmpty(text(summary.repository, fallback: "")) {
            return repo
        }

        return text(summary.workingDirectory, fallback: "Unknown workspace")
    }

    private func rowSummary(for summary: SessionSummary) -> String {
        if let eventSummary = nonEmpty(text(summary.shortEventSummary, fallback: "")) {
            return eventSummary
        }

        guard activityMode == .raw else {
            return "No message preview"
        }
        return summary.displayTitle
    }

    private func activityDisplay(for summary: SessionSummary) -> (label: String, date: Date) {
        switch activityMode {
        case .dockMessage:
            guard let messageActivityDate = summary.messageActivityDate else {
                return ("No messages", .distantPast)
            }
            return (relativeTime(since: messageActivityDate), messageActivityDate)
        case .raw:
            return (relativeTime(since: summary.lastActivity), summary.lastActivity)
        }
    }

    private func status(for summary: SessionSummary) -> DockRowStatusKind {
        switch summary.status {
        case .idle:
            return .idle
        case .active(let activeFlags):
            if activeFlags.contains(.waitingOnApproval) {
                return .needsApproval
            }
            if activeFlags.contains(.waitingOnUserInput) {
                return .needsInput
            }
            return .running
        case .notLoaded:
            return .dormant
        case .systemError:
            return .error
        case .unknown:
            return .unknown
        }
    }

    private func relativeTime(since date: Date) -> String {
        let seconds = max(0, Int(now().timeIntervalSince(date)))

        switch seconds {
        case 0..<60:
            return "now"
        case 60..<3_600:
            return "\(seconds / 60)m ago"
        case 3_600..<86_400:
            return "\(seconds / 3_600)h ago"
        default:
            return "\(seconds / 86_400)d ago"
        }
    }

    private func rail(for summary: SessionSummary) -> DockRowRail {
        let rails = DockRowRail.allCases
        let checksum = summary.id.threadID.utf8.reduce(UInt64(0)) { partial, byte in
            (partial &* 31) &+ UInt64(byte)
        }
        return rails[Int(checksum % UInt64(rails.count))]
    }

    private func text(_ value: SessionSummaryText, fallback: String) -> String {
        switch value {
        case let .known(text):
            return nonEmpty(text) ?? fallback
        case .unknown:
            return fallback
        }
    }

    private func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            return trimmed
        }
        return nil
    }

    private func hostDisplayName(for hostID: String) -> String {
        hosts.first { $0.id == hostID }?.displayName ?? hostID
    }

    private func hostEndpoint(for hostID: String) -> String {
        hosts.first { $0.id == hostID }?.endpoint.displayEndpoint ?? hostID
    }

    private func hostDisplayNameForCachedRow(
        hostID: String,
        snapshot: LocalPinnedDisplaySnapshot?
    ) -> String {
        hosts.first { $0.id == hostID }?.displayName
            ?? nonEmpty(snapshot?.hostDisplayName)
            ?? hostID
    }

    private func hostEndpointForCachedRow(
        hostID: String,
        snapshot: LocalPinnedDisplaySnapshot?
    ) -> String {
        hosts.first { $0.id == hostID }?.endpoint.displayEndpoint
            ?? nonEmpty(snapshot?.hostEndpoint)
            ?? hostID
    }

    private func shortThreadID(_ threadID: String) -> String {
        if threadID.count <= 12 {
            return threadID
        }
        return String(threadID.prefix(8))
    }
}

import Foundation

struct ThreadCardRowProjector {
    let hosts: [DockHostConfiguration]
    let localMetadata: [LocalThreadMetadataKey: LocalThreadMetadata]
    let now: @Sendable () -> Date

    func rows(from cards: [DockThreadCardDTO]) -> [DockRowViewModel] {
        cards.map(makeRow)
    }

    func cachedPinnedRows(excluding loadedKeys: Set<LocalThreadMetadataKey>) -> [DockRowViewModel] {
        let activeHostIDs = Set(hosts.flatMap { host in
            [host.id, host.displayName, host.endpoint.displayEndpoint]
        })
        return localMetadata.compactMap { key, metadata in
            guard metadata.isPinned,
                  !loadedKeys.contains(key),
                  activeHostIDs.contains(key.hostID) else {
                return nil
            }
            return cachedPinnedRow(key: key, metadata: metadata)
        }
    }

    func makeRow(card: DockThreadCardDTO) -> DockRowViewModel {
        let id = HostScopedThreadID(hostID: card.logicalHostID, threadID: card.threadID)
        let metadata = localMetadata[
            LocalThreadMetadataKey(
                hostID: id.hostID,
                backendSessionID: card.backendSessionID,
                threadID: id.threadID
            )
        ]
        let activityDate = activityDate(for: card)
        return DockRowViewModel(
            id: id,
            backendSessionID: card.backendSessionID,
            title: nonEmpty(card.title) ?? "Thread \(shortThreadID(card.threadID))",
            hostDisplayName: nonEmpty(card.hostDisplayName) ?? hostDisplayName(for: card.logicalHostID),
            hostEndpoint: nonEmpty(card.hostEndpoint) ?? hostEndpoint(for: card.logicalHostID),
            repository: nonEmpty(card.repository) ?? nonEmpty(card.workingDirectory) ?? "Unknown workspace",
            branch: nonEmpty(card.branch) ?? "No branch",
            status: status(for: card.status),
            lastActivity: relativeTime(since: activityDate),
            lastActivityDate: activityDate,
            orderKey: card.orderKey,
            summary: nonEmpty(card.displaySummary) ?? "No summary",
            rail: metadata?.rail ?? rail(for: card),
            label: metadata?.label,
            origin: origin(for: card),
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

    private func activityDate(for card: DockThreadCardDTO) -> Date {
        if let activityAtMs = card.activityAtMs {
            return Date(timeIntervalSince1970: TimeInterval(activityAtMs) / 1_000)
        }
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: card.activityAt) {
            return date
        }
        if let date = ISO8601DateFormatter().date(from: card.activityAt) {
            return date
        }
        return .distantPast
    }

    private func status(for status: DockThreadCardStatus) -> DockRowStatusKind {
        switch status {
        case .running:
            return .running
        case .needsInput:
            return .needsInput
        case .needsApproval:
            return .needsApproval
        case .idle:
            return .idle
        case .error:
            return .error
        case .dormant:
            return .dormant
        case .unknown:
            return .unknown
        }
    }

    private func origin(for card: DockThreadCardDTO) -> SessionOrigin {
        switch card.lane {
        case .human:
            return .humanInteractive(subtype: .cli)
        case .agent:
            return .agentOrAutomation(subtype: .exec)
        case .unknown:
            switch card.sourceKind {
            case .human:
                return .humanInteractive(subtype: .cli)
            case .automation:
                return .agentOrAutomation(subtype: .exec)
            case .unknown:
                return .unknown()
            }
        }
    }

    private func relativeTime(since date: Date) -> String {
        guard date != .distantPast else {
            return "No activity"
        }
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

    private func rail(for card: DockThreadCardDTO) -> DockRowRail {
        let rails = DockRowRail.allCases
        let checksum = card.threadID.utf8.reduce(UInt64(0)) { partial, byte in
            (partial &* 31) &+ UInt64(byte)
        }
        return rails[Int(checksum % UInt64(rails.count))]
    }

    private func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            return trimmed
        }
        return nil
    }

    private func hostDisplayName(for hostID: String) -> String {
        hosts.first { host in
            host.id == hostID || host.displayName == hostID || host.endpoint.displayEndpoint == hostID
        }?.displayName ?? hostID
    }

    private func hostEndpoint(for hostID: String) -> String {
        hosts.first { host in
            host.id == hostID || host.displayName == hostID || host.endpoint.displayEndpoint == hostID
        }?.endpoint.displayEndpoint ?? hostID
    }

    private func hostDisplayNameForCachedRow(
        hostID: String,
        snapshot: LocalPinnedDisplaySnapshot?
    ) -> String {
        hosts.first { host in
            host.id == hostID || host.displayName == hostID || host.endpoint.displayEndpoint == hostID
        }?.displayName
            ?? nonEmpty(snapshot?.hostDisplayName)
            ?? hostID
    }

    private func hostEndpointForCachedRow(
        hostID: String,
        snapshot: LocalPinnedDisplaySnapshot?
    ) -> String {
        hosts.first { host in
            host.id == hostID || host.displayName == hostID || host.endpoint.displayEndpoint == hostID
        }?.endpoint.displayEndpoint
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

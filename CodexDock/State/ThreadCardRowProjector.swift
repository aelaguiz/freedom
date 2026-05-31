import Foundation

struct ThreadCardRowProjector {
    let hosts: [DockHostConfiguration]
    let hostIdentityResolver: DockHostIdentityResolver
    let localMetadata: [LocalThreadMetadataKey: LocalThreadMetadata]
    let now: @Sendable () -> Date

    func rows(from cards: [DockThreadCardDTO], sourceHostID: String? = nil) -> [DockRowViewModel] {
        cards.filter(\.isAppFacingHumanThreadCard).map { card in
            makeRow(card: card, sourceHostID: sourceHostID)
        }
    }

    func cachedPinnedRows(excluding loadedKeys: Set<LocalThreadMetadataKey>) -> [DockRowViewModel] {
        return localMetadata.compactMap { key, metadata in
            guard metadata.isPinned,
                  metadata.hasAppFacingHumanPinnedDisplay,
                  !loadedKeys.contains(key),
                  hostIdentityResolver.logicalHostID(forAlias: key.hostID) != nil else {
                return nil
            }
            return cachedPinnedRow(key: key, metadata: metadata)
        }
    }

    func makeRow(card: DockThreadCardDTO, sourceHostID: String? = nil) -> DockRowViewModel {
        let id = HostScopedThreadID(hostID: card.logicalHostID, threadID: card.threadID)
        let metadata = metadata(
            for: id,
            backendSessionID: card.backendSessionID,
            sourceHostID: sourceHostID
        )
        let activityDate = activityDate(for: card)
        return DockRowViewModel(
            id: id,
            sourceHostID: sourceHostID,
            backendSessionID: card.backendSessionID,
            title: nonEmpty(card.title) ?? "Thread \(shortThreadID(card.threadID))",
            hostDisplayName: nonEmpty(card.hostDisplayName)
                ?? hostDisplayName(for: card.logicalHostID, sourceHostID: sourceHostID),
            hostEndpoint: nonEmpty(card.hostEndpoint)
                ?? hostEndpoint(for: card.logicalHostID, sourceHostID: sourceHostID),
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
        let resolved = hostIdentityResolver.resolve(rowHostID: key.hostID)
        let logicalHostID = resolved?.logicalHostID ?? key.hostID
        return DockRowViewModel(
            id: HostScopedThreadID(hostID: logicalHostID, threadID: key.threadID),
            sourceHostID: resolved?.host.id,
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

    private func metadata(
        for id: HostScopedThreadID,
        backendSessionID: String,
        sourceHostID: String?
    ) -> LocalThreadMetadata? {
        let exactKey = LocalThreadMetadataKey(
            hostID: id.hostID,
            backendSessionID: backendSessionID,
            threadID: id.threadID
        )
        if let metadata = localMetadata[exactKey] {
            return metadata
        }

        return localMetadata.first { key, _ in
            guard key.backendSessionID == backendSessionID,
                  key.threadID == id.threadID else {
                return false
            }
            return hostIdentityResolver.logicalHostID(
                forAlias: key.hostID,
                sourceConfiguredHostID: sourceHostID
            ) == id.hostID
        }?.value
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

    private func hostDisplayName(for hostID: String, sourceHostID: String? = nil) -> String {
        hostIdentityResolver.displayName(forAlias: hostID, sourceConfiguredHostID: sourceHostID)
            ?? hostID
    }

    private func hostEndpoint(for hostID: String, sourceHostID: String? = nil) -> String {
        hostIdentityResolver.endpoint(forAlias: hostID, sourceConfiguredHostID: sourceHostID)
            ?? hostID
    }

    private func hostDisplayNameForCachedRow(
        hostID: String,
        snapshot: LocalPinnedDisplaySnapshot?
    ) -> String {
        hostIdentityResolver.displayName(forAlias: hostID)
            ?? nonEmpty(snapshot?.hostDisplayName)
            ?? hostID
    }

    private func hostEndpointForCachedRow(
        hostID: String,
        snapshot: LocalPinnedDisplaySnapshot?
    ) -> String {
        hostIdentityResolver.endpoint(forAlias: hostID)
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

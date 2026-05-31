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
            relationship: relationship(for: card),
            isPinned: metadata?.isPinned ?? false,
            pinnedAt: metadata?.pinnedAt,
            pinnedOrder: metadata?.pinnedOrder
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
        // The relay owns card recency. If this timestamp is missing, decoding
        // fails at the DTO boundary instead of letting Swift invent an order.
        Date(timeIntervalSince1970: TimeInterval(card.activityAtMs) / 1_000)
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

    private func relationship(for card: DockThreadCardDTO) -> DockRowThreadRelationship {
        switch card.relationship {
        case .forked:
            return .forked
        case .root, .spawned:
            return .root
        case .unknown, nil:
            return .root
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

    private func shortThreadID(_ threadID: String) -> String {
        if threadID.count <= 12 {
            return threadID
        }
        return String(threadID.prefix(8))
    }
}

import Foundation

struct ThreadCardRowProjector {
    let hosts: [DockHostConfiguration]
    let hostIdentityResolver: DockHostIdentityResolver
    let localMetadata: [LocalThreadMetadataKey: LocalThreadMetadata]
    let now: @Sendable () -> Date

    func rows(from cards: [DockThreadCardDTO]) -> [DockRowViewModel] {
        cards.filter(\.isAppFacingHumanThreadCard).map { card in
            makeRow(card: card)
        }
    }

    func makeRow(card: DockThreadCardDTO) -> DockRowViewModel {
        guard let resolvedSourceHostID = nonEmpty(card.sourceHostID),
              let projectionID = nonEmpty(card.projectionID),
              let displayOrderKey = nonEmpty(card.displayOrderKey) else {
            preconditionFailure("ThreadCardRowProjector only accepts relay projection rows with sourceHostID, projectionID, and displayOrderKey")
        }
        // Dock rows are projection rows. `logicalHostID` is display payload only;
        // action identity follows the relay-owned source host namespace.
        let id = HostScopedThreadID(hostID: resolvedSourceHostID, threadID: card.threadID)
        let metadata = metadata(
            for: id,
            backendSessionID: card.backendSessionID,
            sourceHostID: resolvedSourceHostID
        )
        let activityDate = activityDate(for: card)
        return DockRowViewModel(
            threadIdentity: id,
            sourceHostID: resolvedSourceHostID,
            projectionID: projectionID,
            backendSessionID: card.backendSessionID,
            title: nonEmpty(card.title) ?? "Thread \(shortThreadID(card.threadID))",
            hostDisplayName: nonEmpty(card.hostDisplayName)
                ?? hostDisplayName(for: card.logicalHostID, sourceHostID: resolvedSourceHostID),
            hostEndpoint: nonEmpty(card.hostEndpoint)
                ?? hostEndpoint(for: card.logicalHostID, sourceHostID: resolvedSourceHostID),
            repository: nonEmpty(card.repository) ?? nonEmpty(card.workingDirectory) ?? "Unknown workspace",
            branch: nonEmpty(card.branch) ?? "No branch",
            status: status(for: card.status),
            lastActivity: relativeTime(since: activityDate),
            lastActivityDate: activityDate,
            displayOrderKey: displayOrderKey,
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

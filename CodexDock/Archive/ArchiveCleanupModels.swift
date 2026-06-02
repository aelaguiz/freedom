import Foundation

public enum ArchiveCleanupAge: Equatable, Sendable {
    case days30
    case days90
    case year1
    case custom(days: Int)

    public var days: Int {
        switch self {
        case .days30:
            return 30
        case .days90:
            return 90
        case .year1:
            return 365
        case .custom(let days):
            return days
        }
    }

    public var label: String {
        switch self {
        case .days30:
            return "30d"
        case .days90:
            return "90d"
        case .year1:
            return "1y"
        case .custom(let days):
            return "\(days)d"
        }
    }
}

public struct ArchiveCleanupRule: Equatable, Sendable {
    public var age: ArchiveCleanupAge
    public var excludesPinned: Bool
    public var excludesRunning: Bool
    public var excludesNeedsInput: Bool
    public var excludesWatchLabel: Bool

    public init(
        age: ArchiveCleanupAge = .days90,
        excludesPinned: Bool = true,
        excludesRunning: Bool = true,
        excludesNeedsInput: Bool = true,
        excludesWatchLabel: Bool = true
    ) {
        self.age = age
        self.excludesPinned = excludesPinned
        self.excludesRunning = excludesRunning
        self.excludesNeedsInput = excludesNeedsInput
        self.excludesWatchLabel = excludesWatchLabel
    }
}

public enum ArchiveCleanupExclusionReason: String, Equatable, Sendable {
    case tooRecent
    case nonHuman
    case pinned
    case running
    case needsInput
    case needsApproval
    case watchLabel

    public var label: String {
        switch self {
        case .tooRecent:
            return "Too recent"
        case .nonHuman:
            return "Not human scope"
        case .pinned:
            return "Pinned"
        case .running:
            return "Running"
        case .needsInput:
            return "Needs input"
        case .needsApproval:
            return "Needs approval"
        case .watchLabel:
            return "Watch label"
        }
    }
}

public struct ArchiveCleanupHostSummary: Equatable, Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public let candidateCount: Int
    public let excludedCount: Int
}

public struct ArchiveCleanupExcludedRow: Equatable, Identifiable, Sendable {
    public var id: HostScopedThreadID { row.threadIdentity }
    public let row: DockRowViewModel
    public let reason: ArchiveCleanupExclusionReason
}

public struct ArchiveCleanupPreviewSnapshot: Equatable, Sendable {
    public let hosts: [DockHostViewModel]
    public let hostStates: [DockHostStateViewModel]
    public let hostIdentityResolver: DockHostIdentityResolver
    public let hostSummaries: [ArchiveCleanupHostSummary]
    public let candidates: [DockRowViewModel]
    public let excluded: [ArchiveCleanupExcludedRow]

    public var candidateCount: Int { candidates.count }
    public var excludedCount: Int { excluded.count }

    public var unavailableMessage: String? {
        guard !hostStates.isEmpty,
              hostStates.allSatisfy(\.status.isUnavailable) else {
            return nil
        }
        return hostStates.map { "\($0.host.displayName): \($0.status.unavailableMessage ?? $0.status.subtitle)" }
            .joined(separator: "; ")
    }
}

public enum ArchiveCleanupStoreState: Equatable, Sendable {
    case configurationError(String)
    case idle([DockHostViewModel])
    case loading([DockHostViewModel])
    case preview(ArchiveCleanupPreviewSnapshot)
    case failed(String)
}

public enum ArchiveCleanupExecutionRowStatus: Equatable, Sendable {
    case archived
    case failed(String)
    case skipped
}

public struct ArchiveCleanupExecutionResult: Equatable, Sendable {
    public let row: DockRowViewModel
    public let status: ArchiveCleanupExecutionRowStatus
}

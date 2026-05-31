import Foundation

public enum DockRowStatusKind: String, Codable, Equatable, Sendable, CaseIterable {
    case running
    case needsInput
    case needsApproval
    case idle
    case error
    case dormant
    case unknown

    public var label: String {
        switch self {
        case .running:
            return "Running"
        case .needsInput:
            return "Needs input"
        case .needsApproval:
            return "Needs approval"
        case .idle:
            return "Idle"
        case .error:
            return "Error"
        case .dormant:
            return "Not loaded"
        case .unknown:
            return "Unknown"
        }
    }

    public var visibleBadgeLabel: String? {
        switch self {
        case .running, .needsInput, .needsApproval, .error:
            return label
        case .idle, .dormant, .unknown:
            return nil
        }
    }
}

public enum DockLensID: String, CaseIterable, Identifiable, Equatable, Sendable {
    case newest
    case host
    case branch

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .newest:
            return "Newest"
        case .host:
            return "Host"
        case .branch:
            return "Branch"
        }
    }
}

public enum DockSortOrder: String, CaseIterable, Identifiable, Equatable, Sendable {
    case newestActivity

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .newestActivity:
            return "Newest activity"
        }
    }
}

public enum DockSourceFilter: String, CaseIterable, Identifiable, Equatable, Sendable {
    case any
    case human
    case agents
    case unknown

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .any:
            return "Any"
        case .human:
            return "Human"
        case .agents:
            return "Agents"
        case .unknown:
            return "Unknown"
        }
    }

    public func includes(_ origin: SessionOrigin) -> Bool {
        switch self {
        case .any:
            return true
        case .human:
            return origin.kind == .humanInteractive
        case .agents:
            return origin.kind == .agentOrAutomation
        case .unknown:
            return origin.kind == .unknown
        }
    }
}

extension SessionOrigin {
    var automationKind: String {
        switch kind {
        case .humanInteractive:
            return "human"
        case .agentOrAutomation:
            return "automation"
        case .unknown:
            return "unknown"
        }
    }
}

public struct DockFilterState: Equatable, Sendable {
    public var selectedHostIDs: Set<String>
    public var selectedBranches: Set<String>
    public var statusKinds: Set<DockRowStatusKind>
    public var repositoryQuery: String
    public var selectedRepositories: Set<String>
    public var source: DockSourceFilter
    public var showsIdle: Bool
    public var sortOrder: DockSortOrder

    public init(
        selectedHostIDs: Set<String> = [],
        selectedBranches: Set<String> = [],
        statusKinds: Set<DockRowStatusKind> = Set(DockRowStatusKind.allCases),
        repositoryQuery: String = "",
        selectedRepositories: Set<String> = [],
        source: DockSourceFilter = .any,
        showsIdle: Bool = false,
        sortOrder: DockSortOrder = .newestActivity
    ) {
        self.selectedHostIDs = selectedHostIDs
        self.selectedBranches = selectedBranches
        self.statusKinds = statusKinds
        self.repositoryQuery = repositoryQuery
        self.selectedRepositories = selectedRepositories
        self.source = source
        self.showsIdle = showsIdle
        self.sortOrder = sortOrder
    }

    // Dock V1 deliberately defaults to all loaded source scopes and no archive facet.
    public static let `default` = DockFilterState()

    public var activeFilterCount: Int {
        var count = 0
        if !selectedHostIDs.isEmpty { count += 1 }
        if !selectedBranches.isEmpty { count += 1 }
        if statusKinds != Set(DockRowStatusKind.allCases) { count += 1 }
        if !repositoryQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { count += 1 }
        if !selectedRepositories.isEmpty { count += 1 }
        if source != .any { count += 1 }
        if showsIdle { count += 1 }
        return count
    }

    public var isDefault: Bool {
        self == .default
    }
}

public enum DockRowRail: String, Codable, Equatable, Sendable, CaseIterable {
    case blue
    case green
    case orange
    case red
    case violet
}

public struct DockRowViewModel: Equatable, Identifiable, Sendable {
    public let id: HostScopedThreadID
    public let backendSessionID: String
    public let title: String
    public let hostDisplayName: String
    public let hostEndpoint: String
    public let repository: String
    public let branch: String
    public let status: DockRowStatusKind
    public let lastActivity: String
    public let lastActivityDate: Date
    public let orderKey: String?
    public let summary: String
    public let rail: DockRowRail
    public let label: String?
    public let origin: SessionOrigin
    public let isPinned: Bool
    public let pinnedAt: Date?
    public let pinnedOrder: Int?

    public init(
        id: HostScopedThreadID,
        backendSessionID: String,
        title: String,
        hostDisplayName: String,
        hostEndpoint: String,
        repository: String,
        branch: String,
        status: DockRowStatusKind,
        lastActivity: String,
        lastActivityDate: Date,
        orderKey: String? = nil,
        summary: String,
        rail: DockRowRail,
        label: String?,
        origin: SessionOrigin,
        isPinned: Bool = false,
        pinnedAt: Date? = nil,
        pinnedOrder: Int? = nil
    ) {
        self.id = id
        self.backendSessionID = backendSessionID
        self.title = title
        self.hostDisplayName = hostDisplayName
        self.hostEndpoint = hostEndpoint
        self.repository = repository
        self.branch = branch
        self.status = status
        self.lastActivity = lastActivity
        self.lastActivityDate = lastActivityDate
        self.orderKey = orderKey
        self.summary = summary
        self.rail = rail
        self.label = label
        self.origin = origin
        self.isPinned = isPinned
        self.pinnedAt = isPinned ? pinnedAt : nil
        self.pinnedOrder = isPinned ? pinnedOrder : nil
    }

    public var metadataKey: LocalThreadMetadataKey {
        LocalThreadMetadataKey(
            hostID: id.hostID,
            backendSessionID: backendSessionID,
            threadID: id.threadID
        )
    }
}

public struct DockSectionViewModel: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let rows: [DockRowViewModel]
}

public enum DockProjectionGroupKind: String, Equatable, Sendable {
    case host
    case branch
}

public struct DockProjectionGroupViewModel: Equatable, Identifiable, Sendable {
    public let id: String
    public let kind: DockProjectionGroupKind
    public let title: String
    public let subtitle: String
    public let rows: [DockRowViewModel]
    public let hostIDs: [String]
    public let newestActivityDate: Date?
    public let runningCount: Int
    public let hiddenIdleCount: Int
    public let isUnavailable: Bool
    public let unavailableMessage: String?

    public var count: Int { rows.count }
}

public struct DockProjectionHiddenCounts: Equatable, Sendable {
    public let idle: Int
}

public struct DockPinnedSummary: Equatable, Sendable {
    public let visibleCount: Int
    public let totalCount: Int
    public let hiddenByScopeCount: Int

    public init(visibleCount: Int, totalCount: Int, hiddenByScopeCount: Int) {
        self.visibleCount = visibleCount
        self.totalCount = totalCount
        self.hiddenByScopeCount = hiddenByScopeCount
    }
}

public struct DockProjectionFacets: Equatable, Sendable {
    public let hosts: [DockHostViewModel]
    public let branches: [String]
    public let statuses: [DockRowStatusKind]
    public let repositories: [String]
    public let sources: [DockSourceFilter]
}

public enum DockProjectionEmptyReason: Equatable, Sendable {
    case noData
    case noSearchMatches
    case noFilterMatches
    case idleHidden
    case hostUnavailable

    public var title: String {
        switch self {
        case .noData:
            return "No sessions"
        case .noSearchMatches:
            return "No matches"
        case .noFilterMatches:
            return "No filtered sessions"
        case .idleHidden:
            return "Idle hidden"
        case .hostUnavailable:
            return "Host unavailable"
        }
    }

    public var message: String {
        switch self {
        case .noData:
            return "No sessions are loaded on reachable hosts."
        case .noSearchMatches:
            return "No sessions match this search."
        case .noFilterMatches:
            return "No sessions match the active filters."
        case .idleHidden:
            return "Show idle sessions to include matching idle threads."
        case .hostUnavailable:
            return "The selected host is unavailable."
        }
    }
}

public struct DockProjectionSummary: Equatable, Sendable {
    public let text: String
    public let activeFilterCount: Int
    public let resultCount: Int
}

public struct DockHostViewModel: Equatable, Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public let endpoint: String

    public init(host: DockHostConfiguration) {
        self.id = host.id
        self.displayName = host.displayName
        self.endpoint = host.endpoint.displayEndpoint
    }
}

public struct DockSnapshot: Equatable, Sendable {
    public let host: DockHostViewModel
    public let hosts: [DockHostViewModel]
    public let hostStates: [DockHostStateViewModel]
    public let rows: [DockRowViewModel]
    public let isPartial: Bool

    public var rowCount: Int {
        rows.count
    }

    public init(
        host: DockHostViewModel,
        hosts: [DockHostViewModel],
        hostStates: [DockHostStateViewModel],
        rows: [DockRowViewModel],
        isPartial: Bool = false
    ) {
        self.host = host
        self.hosts = hosts
        self.hostStates = hostStates
        self.rows = rows
        self.isPartial = isPartial
    }
}

public enum DockHostLoadStatus: Equatable, Sendable {
    case checking
    case loaded(rowCount: Int)
    case partial(rowCount: Int, message: String)
    case empty
    case offline(String)
    case error(String)

    public var subtitle: String {
        switch self {
        case .checking:
            return "Checking"
        case .loaded(let rowCount):
            return "\(rowCount) sessions"
        case .partial(let rowCount, let message):
            return "\(rowCount) sessions, partial: \(message)"
        case .empty:
            return "Online, no sessions"
        case .offline:
            return "Offline"
        case .error:
            return "Error"
        }
    }

    public var isUnavailable: Bool {
        switch self {
        case .offline, .error:
            return true
        case .checking, .loaded, .partial, .empty:
            return false
        }
    }

    public var isPartial: Bool {
        if case .partial = self {
            return true
        }
        return false
    }

    public var unavailableMessage: String? {
        switch self {
        case .offline(let message), .error(let message):
            return message
        case .checking, .loaded, .partial, .empty:
            return nil
        }
    }
}

public struct DockHostStateViewModel: Equatable, Identifiable, Sendable {
    public let id: String
    public let host: DockHostViewModel
    public let status: DockHostLoadStatus

    public init(host: DockHostViewModel, status: DockHostLoadStatus) {
        self.id = host.id
        self.host = host
        self.status = status
    }
}

public enum DockStoreState: Equatable, Sendable {
    case configurationError(String)
    case idle([DockHostViewModel])
    case loading([DockHostViewModel])
    case loaded(DockSnapshot)
    case offline(DockHostViewModel, String)
    case error(DockHostViewModel, String)
}

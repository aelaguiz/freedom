import Foundation

public enum SystemHealthCategory: String, CaseIterable, Identifiable, Sendable {
    case dockFeed
    case threadDetail
    case archive
    case voice
    case diagnostics

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dockFeed:
            return "Dock feed"
        case .threadDetail:
            return "Thread detail"
        case .archive:
            return "Archive"
        case .voice:
            return "Voice"
        case .diagnostics:
            return "Diagnostics"
        }
    }
}

public enum SystemHealthCategoryStatus: Equatable, Sendable {
    case healthy(String)
    case checking(String)
    case notChecked(String)
    case degraded(String, nextAction: String)
    case failed(String, nextAction: String)
    case blocked(String, nextAction: String)
    case stale(String, nextAction: String)

    public var label: String {
        switch self {
        case .healthy:
            return "Healthy"
        case .checking:
            return "Checking"
        case .notChecked:
            return "Not checked"
        case .degraded:
            return "Degraded"
        case .failed:
            return "Failed"
        case .blocked:
            return "Blocked"
        case .stale:
            return "Stale"
        }
    }

    public var detail: String {
        switch self {
        case .healthy(let detail),
             .checking(let detail),
             .notChecked(let detail):
            return detail
        case .degraded(let detail, let nextAction),
             .failed(let detail, let nextAction),
             .blocked(let detail, let nextAction),
             .stale(let detail, let nextAction):
            return "\(detail) \(nextAction)"
        }
    }
}

public struct SystemHealthCategorySnapshot: Equatable, Identifiable, Sendable {
    public let category: SystemHealthCategory
    public let status: SystemHealthCategoryStatus

    public var id: SystemHealthCategory { category }
}

public struct SystemHealthSnapshot: Equatable, Sendable {
    public let summary: AppConnectivityOverallStatus
    public let categories: [SystemHealthCategorySnapshot]
    public let hosts: [HostConnectivitySnapshot]

    public init(
        summary: AppConnectivityOverallStatus,
        categories: [SystemHealthCategorySnapshot],
        hosts: [HostConnectivitySnapshot]
    ) {
        self.summary = summary
        self.categories = categories
        self.hosts = hosts
    }
}

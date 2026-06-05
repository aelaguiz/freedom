import Foundation

public enum ThreadDetailLiveState: Equatable, Sendable {
    case connecting
    case updating
    case reconnecting(String)
    case live
    case stale(String)
    case closed

    public var label: String {
        switch self {
        case .connecting:
            return "Connecting"
        case .updating:
            return "Updating"
        case .reconnecting:
            return "Reconnecting"
        case .live:
            return "Live"
        case .stale:
            return "Stale"
        case .closed:
            return "Closed"
        }
    }
}

public struct ThreadDetailHeader: Equatable, Sendable {
    public let hostID: String
    public let hostName: String
    public let threadID: String
    public let title: String
    public let repository: String
    public let branch: String
    public let statusLabel: String?
    public let lastActivity: String
    public let lastActivityDate: Date
    public let relationship: DockRowThreadRelationship

    public init(host: DockHostConfiguration, row: DockRowViewModel) {
        self.hostID = host.id
        self.hostName = host.displayName
        self.threadID = row.threadID
        self.title = row.title
        self.repository = row.repository
        self.branch = row.branch
        self.statusLabel = row.status.threadDetailStatusLabel
        self.lastActivity = row.lastActivity
        self.lastActivityDate = row.lastActivityDate
        self.relationship = row.relationship
    }
}

public struct ThreadDetailSnapshot: Equatable, Sendable {
    public let header: ThreadDetailHeader
    public let liveState: ThreadDetailLiveState
    public let events: [ThreadEvent]
    public let pendingOutboundMessages: [PendingOutboundMessage]

    public init(
        header: ThreadDetailHeader,
        liveState: ThreadDetailLiveState,
        events: [ThreadEvent],
        pendingOutboundMessages: [PendingOutboundMessage] = []
    ) {
        self.header = header
        self.liveState = liveState
        self.events = events
        self.pendingOutboundMessages = pendingOutboundMessages
    }
}

public enum ThreadDetailStoreState: Equatable, Sendable {
    case idle(ThreadDetailHeader)
    case loading(ThreadDetailHeader)
    case loaded(ThreadDetailSnapshot)
    case error(ThreadDetailHeader, String)
}

import Foundation

public struct HostScopedThreadID: Hashable, Codable, Sendable {
    public let hostID: String
    public let threadID: String

    public init(hostID: String, threadID: String) {
        self.hostID = hostID
        self.threadID = threadID
    }
}

public enum SessionSummaryText: Equatable, Sendable {
    case known(String)
    case unknown
}

public enum SessionActiveFlag: Equatable, Sendable {
    case waitingOnApproval
    case waitingOnUserInput
    case unknown(String)
}

public enum SessionStatus: Equatable, Sendable {
    case unknown
    case notLoaded
    case idle
    case systemError
    case active(activeFlags: [SessionActiveFlag])

    public var needsAttention: Bool {
        guard case .active(let activeFlags) = self else {
            return false
        }
        return activeFlags.contains(.waitingOnApproval)
            || activeFlags.contains(.waitingOnUserInput)
    }
}

public struct SessionSummary: Equatable, Sendable {
    public let id: HostScopedThreadID
    public let backendSessionID: String
    public let displayTitle: String
    public let status: SessionStatus
    public let repository: SessionSummaryText
    public let workingDirectory: SessionSummaryText
    public let branch: SessionSummaryText
    public let lastActivity: Date
    public let shortEventSummary: SessionSummaryText

    public var backendThreadID: String {
        id.threadID
    }

    public init(
        id: HostScopedThreadID,
        backendSessionID: String,
        displayTitle: String,
        status: SessionStatus,
        repository: SessionSummaryText,
        workingDirectory: SessionSummaryText,
        branch: SessionSummaryText,
        lastActivity: Date,
        shortEventSummary: SessionSummaryText
    ) {
        self.id = id
        self.backendSessionID = backendSessionID
        self.displayTitle = displayTitle
        self.status = status
        self.repository = repository
        self.workingDirectory = workingDirectory
        self.branch = branch
        self.lastActivity = lastActivity
        self.shortEventSummary = shortEventSummary
    }
}

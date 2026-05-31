import Foundation
@testable import CodexDock

enum ThreadCardFixtureText: Equatable, Sendable {
    case known(String)
    case unknown
}

enum ThreadCardFixtureActiveFlag: Equatable, Sendable {
    case waitingOnApproval
    case waitingOnUserInput
    case unknown(String)
}

enum ThreadCardFixtureStatus: Equatable, Sendable {
    case unknown
    case notLoaded
    case idle
    case systemError
    case active(activeFlags: [ThreadCardFixtureActiveFlag])

    var needsAttention: Bool {
        guard case .active(let activeFlags) = self else {
            return false
        }
        return activeFlags.contains(.waitingOnApproval)
            || activeFlags.contains(.waitingOnUserInput)
    }
}

struct ThreadCardFixtureSummary: Equatable, Sendable {
    let id: HostScopedThreadID
    let backendSessionID: String
    let displayTitle: String
    let status: ThreadCardFixtureStatus
    let repository: ThreadCardFixtureText
    let workingDirectory: ThreadCardFixtureText
    let branch: ThreadCardFixtureText
    let lastActivity: Date
    let displaySummary: ThreadCardFixtureText
    let cardActivityDate: Date?
    let origin: SessionOrigin

    var backendThreadID: String {
        id.threadID
    }

    init(
        id: HostScopedThreadID,
        backendSessionID: String,
        displayTitle: String,
        status: ThreadCardFixtureStatus,
        repository: ThreadCardFixtureText,
        workingDirectory: ThreadCardFixtureText,
        branch: ThreadCardFixtureText,
        lastActivity: Date,
        displaySummary: ThreadCardFixtureText,
        cardActivityDate: Date? = nil,
        origin: SessionOrigin
    ) {
        self.id = id
        self.backendSessionID = backendSessionID
        self.displayTitle = displayTitle
        self.status = status
        self.repository = repository
        self.workingDirectory = workingDirectory
        self.branch = branch
        self.lastActivity = lastActivity
        self.displaySummary = displaySummary
        self.cardActivityDate = cardActivityDate
        self.origin = origin
    }
}

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

public enum SessionOriginKind: Hashable, Sendable {
    case humanInteractive
    case agentOrAutomation
    case unknown
}

public enum SessionHumanOriginSubtype: Hashable, Sendable {
    case cli
    case vscode
    case customInteractive(String)
}

public enum SessionAgentOriginSubtype: Hashable, Sendable {
    case exec
    case appServer
    case subAgentReview
    case subAgentCompact
    case subAgentThreadSpawn
    case subAgentOther
}

public struct SessionOriginEvidence: Equatable, Sendable {
    public let sourceKind: ThreadSourceKind?
    public let rawSource: JSONValue?
    public let threadSource: String?
    public let agentNickname: String?
    public let agentRole: String?

    public init(
        sourceKind: ThreadSourceKind? = nil,
        rawSource: JSONValue? = nil,
        threadSource: String? = nil,
        agentNickname: String? = nil,
        agentRole: String? = nil
    ) {
        self.sourceKind = sourceKind
        self.rawSource = rawSource
        self.threadSource = threadSource
        self.agentNickname = agentNickname
        self.agentRole = agentRole
    }
}

public enum SessionOrigin: Equatable, Sendable {
    case human(SessionHumanOriginSubtype, evidence: SessionOriginEvidence)
    case automation(SessionAgentOriginSubtype, evidence: SessionOriginEvidence)
    case unknownOrigin(SessionOriginEvidence)

    public var kind: SessionOriginKind {
        switch self {
        case .human:
            return .humanInteractive
        case .automation:
            return .agentOrAutomation
        case .unknownOrigin:
            return .unknown
        }
    }

    public var humanSubtype: SessionHumanOriginSubtype? {
        switch self {
        case .human(let subtype, _):
            return subtype
        case .automation, .unknownOrigin:
            return nil
        }
    }

    public var automationSubtype: SessionAgentOriginSubtype? {
        switch self {
        case .automation(let subtype, _):
            return subtype
        case .human, .unknownOrigin:
            return nil
        }
    }

    public var debugSubtypeDescription: String {
        switch self {
        case .human(let subtype, _):
            return String(describing: subtype)
        case .automation(let subtype, _):
            return String(describing: subtype)
        case .unknownOrigin:
            return "unknown"
        }
    }

    public var evidence: SessionOriginEvidence {
        switch self {
        case .human(_, let evidence),
             .automation(_, let evidence),
             .unknownOrigin(let evidence):
            return evidence
        }
    }

    public static func humanInteractive(
        subtype: SessionHumanOriginSubtype,
        evidence: SessionOriginEvidence = SessionOriginEvidence()
    ) -> SessionOrigin {
        .human(subtype, evidence: evidence)
    }

    public static func agentOrAutomation(
        subtype: SessionAgentOriginSubtype,
        evidence: SessionOriginEvidence = SessionOriginEvidence()
    ) -> SessionOrigin {
        .automation(subtype, evidence: evidence)
    }

    public static func unknown(
        evidence: SessionOriginEvidence = SessionOriginEvidence()
    ) -> SessionOrigin {
        .unknownOrigin(evidence)
    }

    public func replacingEvidence(_ evidence: SessionOriginEvidence) -> SessionOrigin {
        switch self {
        case .human(let subtype, _):
            return .human(subtype, evidence: evidence)
        case .automation(let subtype, _):
            return .automation(subtype, evidence: evidence)
        case .unknownOrigin:
            return .unknownOrigin(evidence)
        }
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
    public let messageActivityDate: Date?
    public let origin: SessionOrigin

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
        shortEventSummary: SessionSummaryText,
        messageActivityDate: Date? = nil,
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
        self.shortEventSummary = shortEventSummary
        self.messageActivityDate = messageActivityDate
        self.origin = origin
    }
}

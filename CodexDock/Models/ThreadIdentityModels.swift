import Foundation

public struct HostScopedThreadID: Hashable, Codable, Sendable {
    public let hostID: String
    public let threadID: String

    public init(hostID: String, threadID: String) {
        self.hostID = hostID
        self.threadID = threadID
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

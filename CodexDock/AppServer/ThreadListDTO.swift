import Foundation

public struct ThreadListParams: Codable, Equatable, Sendable {
    public let cursor: String?
    public let limit: Int?
    public let sortKey: ThreadSortKey?
    public let sortDirection: SortDirection?
    public let modelProviders: [String]?
    public let sourceKinds: [ThreadSourceKind]?
    public let archived: Bool?
    public let cwd: ThreadListCwdFilter?
    public let useStateDbOnly: Bool?
    public let searchTerm: String?

    public init(
        cursor: String? = nil,
        limit: Int? = nil,
        sortKey: ThreadSortKey? = nil,
        sortDirection: SortDirection? = nil,
        modelProviders: [String]? = nil,
        sourceKinds: [ThreadSourceKind]? = nil,
        archived: Bool? = nil,
        cwd: ThreadListCwdFilter? = nil,
        useStateDbOnly: Bool? = nil,
        searchTerm: String? = nil
    ) {
        self.cursor = cursor
        self.limit = limit
        self.sortKey = sortKey
        self.sortDirection = sortDirection
        self.modelProviders = modelProviders
        self.sourceKinds = sourceKinds
        self.archived = archived
        self.cwd = cwd
        self.useStateDbOnly = useStateDbOnly
        self.searchTerm = searchTerm
    }
}

public enum ThreadSortKey: String, Codable, Equatable, Sendable {
    case createdAt = "created_at"
    case updatedAt = "updated_at"
}

public enum SortDirection: String, Codable, Equatable, Sendable {
    case asc
    case desc
}

public enum ThreadSourceKind: String, Codable, Equatable, Sendable {
    case cli
    case vscode
    case exec
    case appServer
    case subAgent
    case subAgentReview
    case subAgentCompact
    case subAgentThreadSpawn
    case subAgentOther
    case unknown

    public static let dockAgentScopeKinds: [ThreadSourceKind] = [
        .exec,
        .appServer,
        .subAgentReview,
        .subAgentCompact,
        .subAgentThreadSpawn,
        .subAgentOther,
        .unknown
    ]
}

public enum ThreadListCwdFilter: Codable, Equatable, Sendable {
    case one(String)
    case many([String])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .one(value)
            return
        }
        self = .many(try container.decode([String].self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .one(let value):
            try container.encode(value)
        case .many(let values):
            try container.encode(values)
        }
    }
}

public struct ThreadListResponseDTO: Codable, Equatable, Sendable {
    public let data: [ThreadDTO]
    public let nextCursor: String?
    public let backwardsCursor: String?

    public init(
        data: [ThreadDTO],
        nextCursor: String? = nil,
        backwardsCursor: String? = nil
    ) {
        self.data = data
        self.nextCursor = nextCursor
        self.backwardsCursor = backwardsCursor
    }
}

/// Row fields stay optional so stale or partial app-server rows can produce
/// scoped mapper failures instead of failing the whole page decode.
public struct ThreadDTO: Codable, Equatable, Sendable {
    public let id: String?
    public let sessionId: String?
    public let forkedFromId: String?
    public let preview: String?
    public let ephemeral: Bool?
    public let modelProvider: String?
    public let createdAt: Int64?
    public let updatedAt: Int64?
    public let status: ThreadStatusDTO?
    public let path: String?
    public let cwd: String?
    public let cliVersion: String?
    public let source: JSONValue?
    public let threadSource: String?
    public let agentNickname: String?
    public let agentRole: String?
    public let gitInfo: ThreadGitInfoDTO?
    public let name: String?
    public let turns: [JSONValue]?

    public init(
        id: String? = nil,
        sessionId: String? = nil,
        forkedFromId: String? = nil,
        preview: String? = nil,
        ephemeral: Bool? = nil,
        modelProvider: String? = nil,
        createdAt: Int64? = nil,
        updatedAt: Int64? = nil,
        status: ThreadStatusDTO? = nil,
        path: String? = nil,
        cwd: String? = nil,
        cliVersion: String? = nil,
        source: JSONValue? = nil,
        threadSource: String? = nil,
        agentNickname: String? = nil,
        agentRole: String? = nil,
        gitInfo: ThreadGitInfoDTO? = nil,
        name: String? = nil,
        turns: [JSONValue]? = []
    ) {
        self.id = id
        self.sessionId = sessionId
        self.forkedFromId = forkedFromId
        self.preview = preview
        self.ephemeral = ephemeral
        self.modelProvider = modelProvider
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.status = status
        self.path = path
        self.cwd = cwd
        self.cliVersion = cliVersion
        self.source = source
        self.threadSource = threadSource
        self.agentNickname = agentNickname
        self.agentRole = agentRole
        self.gitInfo = gitInfo
        self.name = name
        self.turns = turns
    }

    public func replacingTurns(_ turns: [JSONValue]?) -> ThreadDTO {
        ThreadDTO(
            id: id,
            sessionId: sessionId,
            forkedFromId: forkedFromId,
            preview: preview,
            ephemeral: ephemeral,
            modelProvider: modelProvider,
            createdAt: createdAt,
            updatedAt: updatedAt,
            status: status,
            path: path,
            cwd: cwd,
            cliVersion: cliVersion,
            source: source,
            threadSource: threadSource,
            agentNickname: agentNickname,
            agentRole: agentRole,
            gitInfo: gitInfo,
            name: name,
            turns: turns
        )
    }
}

public struct ThreadGitInfoDTO: Codable, Equatable, Sendable {
    public let sha: String?
    public let branch: String?
    public let originUrl: String?

    public init(sha: String? = nil, branch: String? = nil, originUrl: String? = nil) {
        self.sha = sha
        self.branch = branch
        self.originUrl = originUrl
    }
}

public enum ThreadStatusDTO: Codable, Equatable, Sendable {
    case notLoaded
    case idle
    case systemError
    case active(activeFlags: [ThreadActiveFlagDTO])
    case unknown(String)

    private enum CodingKeys: String, CodingKey {
        case type
        case activeFlags
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "notLoaded":
            self = .notLoaded
        case "idle":
            self = .idle
        case "systemError":
            self = .systemError
        case "active":
            self = .active(
                activeFlags: try container.decodeIfPresent(
                    [ThreadActiveFlagDTO].self,
                    forKey: .activeFlags
                ) ?? []
            )
        default:
            self = .unknown(type)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .notLoaded:
            try container.encode("notLoaded", forKey: .type)
        case .idle:
            try container.encode("idle", forKey: .type)
        case .systemError:
            try container.encode("systemError", forKey: .type)
        case .active(let activeFlags):
            try container.encode("active", forKey: .type)
            try container.encode(activeFlags, forKey: .activeFlags)
        case .unknown(let type):
            try container.encode(type, forKey: .type)
        }
    }
}

public enum ThreadActiveFlagDTO: Codable, Equatable, Sendable {
    case waitingOnApproval
    case waitingOnUserInput
    case unknown(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        switch value {
        case "waitingOnApproval":
            self = .waitingOnApproval
        case "waitingOnUserInput":
            self = .waitingOnUserInput
        default:
            self = .unknown(value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .waitingOnApproval:
            try container.encode("waitingOnApproval")
        case .waitingOnUserInput:
            try container.encode("waitingOnUserInput")
        case .unknown(let value):
            try container.encode(value)
        }
    }
}

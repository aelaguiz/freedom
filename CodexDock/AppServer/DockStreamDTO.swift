import Foundation

public enum DockStreamKind: String, Codable, Equatable, Sendable {
    case snapshot
    case delta
    case heartbeat
}

public enum DockStreamSessionStatus: Equatable, Sendable {
    case running
    case needsInput
    case needsApproval
    case idle
    case error
    case dormant
    case unknown

    public var rawValue: String {
        switch self {
        case .running:
            return "running"
        case .needsInput:
            return "needsInput"
        case .needsApproval:
            return "needsApproval"
        case .idle:
            return "idle"
        case .error:
            return "error"
        case .dormant:
            return "dormant"
        case .unknown:
            return "unknown"
        }
    }
}

extension DockStreamSessionStatus: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        switch try container.decode(String.self) {
        case "running":
            self = .running
        case "needsInput":
            self = .needsInput
        case "needsApproval":
            self = .needsApproval
        case "idle":
            self = .idle
        case "error":
            self = .error
        case "dormant":
            self = .dormant
        default:
            self = .unknown
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum DockStreamFreshnessStatus: Equatable, Sendable {
    case unknown
    case fresh
    case stale
    case offline
    case error

    public var rawValue: String {
        switch self {
        case .unknown:
            return "unknown"
        case .fresh:
            return "fresh"
        case .stale:
            return "stale"
        case .offline:
            return "offline"
        case .error:
            return "error"
        }
    }
}

extension DockStreamFreshnessStatus: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        switch try container.decode(String.self) {
        case "fresh":
            self = .fresh
        case "stale":
            self = .stale
        case "offline":
            self = .offline
        case "error":
            self = .error
        default:
            self = .unknown
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct DockStreamFreshnessDTO: Codable, Equatable, Sendable {
    public let status: DockStreamFreshnessStatus
    public let lastAttemptAt: String?
    public let lastSyncAt: String?
    public let lastError: String?

    public init(
        status: DockStreamFreshnessStatus,
        lastAttemptAt: String? = nil,
        lastSyncAt: String? = nil,
        lastError: String? = nil
    ) {
        self.status = status
        self.lastAttemptAt = lastAttemptAt
        self.lastSyncAt = lastSyncAt
        self.lastError = lastError
    }
}

public struct DockStreamHostDTO: Codable, Equatable, Sendable {
    public let id: String
    public let displayName: String?
    public let endpoint: String?

    public init(id: String, displayName: String? = nil, endpoint: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.endpoint = endpoint
    }
}

public enum DockStreamSourceKind: Equatable, Sendable {
    case human
    case automation
    case unknown

    public var rawValue: String {
        switch self {
        case .human:
            return "human"
        case .automation:
            return "automation"
        case .unknown:
            return "unknown"
        }
    }
}

extension DockStreamSourceKind: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        switch try container.decode(String.self) {
        case "human":
            self = .human
        case "automation":
            self = .automation
        default:
            self = .unknown
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum DockStreamLane: Equatable, Sendable {
    case human
    case agent
    case unknown

    public var rawValue: String {
        switch self {
        case .human:
            return "human"
        case .agent:
            return "agent"
        case .unknown:
            return "unknown"
        }
    }
}

extension DockStreamLane: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        switch try container.decode(String.self) {
        case "human":
            self = .human
        case "agent":
            self = .agent
        default:
            self = .unknown
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct DockStreamSourceDTO: Codable, Equatable, Sendable {
    public let kind: DockStreamSourceKind

    public init(kind: DockStreamSourceKind) {
        self.kind = kind
    }
}

public struct DockStreamSessionDTO: Codable, Equatable, Sendable {
    public let id: String
    public let hostID: String?
    public let threadID: String
    public let backendSessionID: String?
    public let title: String?
    public let status: DockStreamSessionStatus
    public let lane: DockStreamLane?
    public let kindLabel: String?
    public let repository: String?
    public let workingDirectory: String?
    public let branch: String?
    public let updatedAt: Int64?
    public let summary: String?
    public let messageSummary: String?
    public let messageUpdatedAt: Int64?
    public let source: DockStreamSourceDTO?

    public init(
        id: String,
        hostID: String? = nil,
        threadID: String,
        backendSessionID: String? = nil,
        title: String? = nil,
        status: DockStreamSessionStatus,
        lane: DockStreamLane? = nil,
        kindLabel: String? = nil,
        repository: String? = nil,
        workingDirectory: String? = nil,
        branch: String? = nil,
        updatedAt: Int64? = nil,
        summary: String? = nil,
        messageSummary: String? = nil,
        messageUpdatedAt: Int64? = nil,
        source: DockStreamSourceDTO? = nil
    ) {
        self.id = id
        self.hostID = hostID
        self.threadID = threadID
        self.backendSessionID = backendSessionID
        self.title = title
        self.status = status
        self.lane = lane
        self.kindLabel = kindLabel
        self.repository = repository
        self.workingDirectory = workingDirectory
        self.branch = branch
        self.updatedAt = updatedAt
        self.summary = summary
        self.messageSummary = messageSummary
        self.messageUpdatedAt = messageUpdatedAt
        self.source = source
    }
}

public struct DockStreamWindowDTO: Codable, Equatable, Sendable {
    public let offset: Int
    public let limit: Int
    public let rowCount: Int
    public let nextOffset: Int?

    public init(
        offset: Int,
        limit: Int,
        rowCount: Int,
        nextOffset: Int? = nil
    ) {
        self.offset = offset
        self.limit = limit
        self.rowCount = rowCount
        self.nextOffset = nextOffset
    }
}

public struct DockStreamUpdateDTO: Codable, Equatable, Sendable {
    public let kind: DockStreamKind
    public let schemaVersion: Int?
    public let view: String?
    public let complete: Bool?
    public let totalRows: Int?
    public let window: DockStreamWindowDTO?
    public let stateGeneration: Int64?
    public let epoch: String
    public let baseSeq: Int64?
    public let seq: Int64
    public let asOf: String?
    public let freshness: DockStreamFreshnessDTO?
    public let hosts: [DockStreamHostDTO]?
    public let sessions: [DockStreamSessionDTO]?
    public let upsertHosts: [DockStreamHostDTO]?
    public let upsertSessions: [DockStreamSessionDTO]?
    public let deleteSessionIDs: [String]?

    public init(
        kind: DockStreamKind,
        schemaVersion: Int? = nil,
        view: String? = nil,
        complete: Bool? = nil,
        totalRows: Int? = nil,
        window: DockStreamWindowDTO? = nil,
        stateGeneration: Int64? = nil,
        epoch: String,
        baseSeq: Int64? = nil,
        seq: Int64,
        asOf: String? = nil,
        freshness: DockStreamFreshnessDTO? = nil,
        hosts: [DockStreamHostDTO]? = nil,
        sessions: [DockStreamSessionDTO]? = nil,
        upsertHosts: [DockStreamHostDTO]? = nil,
        upsertSessions: [DockStreamSessionDTO]? = nil,
        deleteSessionIDs: [String]? = nil
    ) {
        self.kind = kind
        self.schemaVersion = schemaVersion
        self.view = view
        self.complete = complete
        self.totalRows = totalRows
        self.window = window
        self.stateGeneration = stateGeneration
        self.epoch = epoch
        self.baseSeq = baseSeq
        self.seq = seq
        self.asOf = asOf
        self.freshness = freshness
        self.hosts = hosts
        self.sessions = sessions
        self.upsertHosts = upsertHosts
        self.upsertSessions = upsertSessions
        self.deleteSessionIDs = deleteSessionIDs
    }
}

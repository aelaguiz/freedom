import Foundation

public struct ThreadReadParams: Codable, Equatable, Sendable {
    public let threadId: String
    public let includeTurns: Bool?

    public init(threadId: String, includeTurns: Bool? = nil) {
        self.threadId = threadId
        self.includeTurns = includeTurns
    }
}

public struct ThreadTurnsListParams: Codable, Equatable, Sendable {
    public let threadId: String
    public let cursor: String?
    public let limit: Int?
    public let sortDirection: SortDirection?

    public init(
        threadId: String,
        cursor: String? = nil,
        limit: Int? = nil,
        sortDirection: SortDirection? = nil
    ) {
        self.threadId = threadId
        self.cursor = cursor
        self.limit = limit
        self.sortDirection = sortDirection
    }
}

public struct ThreadTurnsListResponseDTO: Codable, Equatable, Sendable {
    public let data: [JSONValue]
    public let nextCursor: String?
    public let backwardsCursor: String?

    public init(
        data: [JSONValue],
        nextCursor: String? = nil,
        backwardsCursor: String? = nil
    ) {
        self.data = data
        self.nextCursor = nextCursor
        self.backwardsCursor = backwardsCursor
    }
}

public struct ThreadReadResponseDTO: Codable, Equatable, Sendable {
    public let thread: ThreadDTO

    public init(thread: ThreadDTO) {
        self.thread = thread
    }
}

public struct ThreadResumeParams: Codable, Equatable, Sendable {
    public let threadId: String
    public let excludeTurns: Bool?

    public init(threadId: String, excludeTurns: Bool? = nil) {
        self.threadId = threadId
        self.excludeTurns = excludeTurns
    }
}

public struct ThreadResumeResponseDTO: Codable, Equatable, Sendable {
    public let thread: ThreadDTO

    public init(thread: ThreadDTO) {
        self.thread = thread
    }
}

public struct ThreadArchiveParams: Codable, Equatable, Sendable {
    public let threadId: String

    public init(threadId: String) {
        self.threadId = threadId
    }
}

public struct ThreadArchiveResponseDTO: Codable, Equatable, Sendable {
    public init() {}
}

public struct ThreadUnarchiveParams: Codable, Equatable, Sendable {
    public let threadId: String

    public init(threadId: String) {
        self.threadId = threadId
    }
}

public struct ThreadUnarchiveResponseDTO: Codable, Equatable, Sendable {
    public let thread: ThreadDTO

    public init(thread: ThreadDTO) {
        self.thread = thread
    }
}

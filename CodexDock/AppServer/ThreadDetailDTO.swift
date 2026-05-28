import Foundation

public struct ThreadReadParams: Codable, Equatable, Sendable {
    public let threadId: String
    public let includeTurns: Bool?

    public init(threadId: String, includeTurns: Bool? = nil) {
        self.threadId = threadId
        self.includeTurns = includeTurns
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

    public init(threadId: String) {
        self.threadId = threadId
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

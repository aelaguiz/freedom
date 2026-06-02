import Foundation
@testable import CodexDock

// Fixture-only legacy DTOs. Production Thread Detail reads projection DTOs only;
// raw Codex `thread/*` shapes stay outside the app target so display code cannot
// route around the relay-owned projection ledger.
struct ThreadReadParams: Codable, Equatable, Sendable {
    let threadId: String
    let includeTurns: Bool?

    init(threadId: String, includeTurns: Bool? = nil) {
        self.threadId = threadId
        self.includeTurns = includeTurns
    }
}

enum SortDirection: String, Codable, Equatable, Sendable {
    case asc
    case desc
}

enum ThreadTurnItemsView: String, Codable, Equatable, Sendable {
    case notLoaded
    case summary
    case full
}

struct ThreadTurnsListParams: Codable, Equatable, Sendable {
    let threadId: String
    let cursor: String?
    let limit: Int?
    let sortDirection: SortDirection?
    let itemsView: ThreadTurnItemsView?

    init(
        threadId: String,
        cursor: String? = nil,
        limit: Int? = nil,
        sortDirection: SortDirection? = nil,
        itemsView: ThreadTurnItemsView? = nil
    ) {
        self.threadId = threadId
        self.cursor = cursor
        self.limit = limit
        self.sortDirection = sortDirection
        self.itemsView = itemsView
    }
}

struct ThreadTurnsListResponseDTO: Codable, Equatable, Sendable {
    let data: [JSONValue]
    let nextCursor: String?
    let backwardsCursor: String?

    init(
        data: [JSONValue],
        nextCursor: String? = nil,
        backwardsCursor: String? = nil
    ) {
        self.data = data
        self.nextCursor = nextCursor
        self.backwardsCursor = backwardsCursor
    }
}

struct ThreadReadResponseDTO: Codable, Equatable, Sendable {
    let thread: ThreadDTO

    init(thread: ThreadDTO) {
        self.thread = thread
    }
}

struct ThreadResumeParams: Codable, Equatable, Sendable {
    let threadId: String
    let excludeTurns: Bool?

    init(threadId: String, excludeTurns: Bool? = nil) {
        self.threadId = threadId
        self.excludeTurns = excludeTurns
    }
}

struct ThreadResumeResponseDTO: Codable, Equatable, Sendable {
    let thread: ThreadDTO

    init(thread: ThreadDTO) {
        self.thread = thread
    }
}

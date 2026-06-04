import Foundation

enum ClientCommandEngineError: LocalizedError, Sendable {
    case missingArchiver
    case missingRenamer

    var errorDescription: String? {
        switch self {
        case .missingArchiver:
            return "Archive commands are not configured."
        case .missingRenamer:
            return "Rename commands are not configured."
        }
    }
}

actor ClientCommandEngine {
    private let archiver: (any ThreadArchiveCommanding)?
    private let renamer: (any ThreadRenameCommanding)?

    init() {
        self.archiver = nil
        self.renamer = nil
    }

    init(archiver: any ThreadArchiveCommanding) {
        self.archiver = archiver
        self.renamer = nil
    }

    init(archiver: any ThreadArchiveCommanding, renamer: any ThreadRenameCommanding) {
        self.archiver = archiver
        self.renamer = renamer
    }

    func archive(_ row: DockRowViewModel, on host: DockHostConfiguration) async throws {
        guard let archiver else {
            throw ClientCommandEngineError.missingArchiver
        }
        try await archiver.archiveThread(row.threadID, on: host)
    }

    func unarchive(_ row: DockRowViewModel, on host: DockHostConfiguration) async throws {
        guard let archiver else {
            throw ClientCommandEngineError.missingArchiver
        }
        try await archiver.unarchiveThread(row.threadID, on: host)
    }

    func rename(_ row: DockRowViewModel, to name: String, on host: DockHostConfiguration) async throws {
        guard let renamer else {
            throw ClientCommandEngineError.missingRenamer
        }
        try await renamer.renameThread(row.threadID, to: name, on: host)
    }

    func sendDraft(
        _ text: String,
        threadID: String,
        activeTurnID: String?,
        session: any ThreadDetailSession
    ) async throws -> String? {
        if let activeTurnID {
            let response = try await session.turnSteer(
                params: .text(
                    threadId: threadID,
                    text: text,
                    expectedTurnId: activeTurnID
                ),
                timeout: CodexDockConstants.AppServer.defaultRequestTimeout
            )
            return response.turnId
        }

        let response = try await session.turnStart(
            params: .text(threadId: threadID, text: text),
            timeout: CodexDockConstants.AppServer.defaultRequestTimeout
        )
        return response.turn.objectValue?["id"]?.stringValue
    }

    func respondToServerRequest(
        requestID: JSONRPCRequestID,
        payload: JSONValue,
        session: any ThreadDetailSession
    ) async throws {
        try await session.sendResponse(id: requestID, result: payload)
    }
}

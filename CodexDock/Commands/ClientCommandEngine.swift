import Foundation

enum ClientCommandEngineError: LocalizedError, Sendable {
    case missingArchiver

    var errorDescription: String? {
        switch self {
        case .missingArchiver:
            return "Archive commands are not configured."
        }
    }
}

actor ClientCommandEngine {
    private let archiver: (any DockSessionArchiving)?

    init() {
        self.archiver = nil
    }

    init(archiver: any DockSessionArchiving) {
        self.archiver = archiver
    }

    func archive(_ row: DockRowViewModel, on host: DockHostConfiguration) async throws {
        guard let archiver else {
            throw ClientCommandEngineError.missingArchiver
        }
        try await archiver.archiveThread(row.id.threadID, on: host)
    }

    func unarchive(_ row: DockRowViewModel, on host: DockHostConfiguration) async throws {
        guard let archiver else {
            throw ClientCommandEngineError.missingArchiver
        }
        try await archiver.unarchiveThread(row.id.threadID, on: host)
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

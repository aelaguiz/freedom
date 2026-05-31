import Foundation

public protocol ThreadArchiveCommanding: Sendable {
    func archiveThread(_ threadID: String, on host: DockHostConfiguration) async throws
    func unarchiveThread(_ threadID: String, on host: DockHostConfiguration) async throws
}

public enum DockRequestFailure: Error, Equatable, LocalizedError, Sendable {
    case offline(String)
    case error(String)

    public var errorDescription: String? {
        switch self {
        case let .offline(message), let .error(message):
            return message
        }
    }
}

public struct AppServerThreadCommandClient: ThreadArchiveCommanding {
    public init() {}

    public func archiveThread(_ threadID: String, on host: DockHostConfiguration) async throws {
        DockLog.dock.notice("dock archive started host_id=\(host.id, privacy: .public) thread_id=\(DockLog.publicID(threadID), privacy: .public)")
        _ = try await withClient(for: host) { client in
            try await client.threadArchive(
                params: ThreadArchiveParams(threadId: threadID),
                timeout: CodexDockConstants.AppServer.defaultRequestTimeout,
                observabilityContext: AppServerRequestObservabilityContext(
                    configuredHostID: host.id,
                    route: AppServerMethods.threadArchive,
                    store: .shared
                )
            )
        }
        DockLog.dock.notice("dock archive finished host_id=\(host.id, privacy: .public) thread_id=\(DockLog.publicID(threadID), privacy: .public)")
    }

    public func unarchiveThread(_ threadID: String, on host: DockHostConfiguration) async throws {
        DockLog.archive.notice("archive restore started host_id=\(host.id, privacy: .public) thread_id=\(DockLog.publicID(threadID), privacy: .public)")
        _ = try await withClient(for: host) { client in
            try await client.threadUnarchive(
                params: ThreadUnarchiveParams(threadId: threadID),
                timeout: CodexDockConstants.AppServer.defaultRequestTimeout,
                observabilityContext: AppServerRequestObservabilityContext(
                    configuredHostID: host.id,
                    route: AppServerMethods.threadUnarchive,
                    store: .shared
                )
            )
        }
        DockLog.archive.notice("archive restore finished host_id=\(host.id, privacy: .public) thread_id=\(DockLog.publicID(threadID), privacy: .public)")
    }

    private func withClient<Value>(
        for host: DockHostConfiguration,
        operation: @Sendable (AppServerClient) async throws -> Value
    ) async throws -> Value {
        do {
            return try await AppServerHostConnector().withConnectedClient(for: host) { connection in
                try await operation(connection.client)
            }
        } catch {
            throw mapRequestFailure(error)
        }
    }

    private func mapRequestFailure(_ error: Error) -> DockRequestFailure {
        if let failure = error as? DockRequestFailure {
            return failure
        }

        if let clientError = error as? AppServerClientError {
            switch clientError {
            case .disconnected, .notConnected, .requestTimedOut, .transport:
                return .offline(clientError.localizedDescription)
            case .duplicateRequestID,
                 .malformedMessage,
                 .requestCancelled,
                 .responseDecoding,
                 .server,
                 .unexpectedServerRequest,
                 .unmatchedResponse:
                return .error(clientError.localizedDescription)
            }
        }

        return .error(error.localizedDescription)
    }
}

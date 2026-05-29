import Foundation

public struct DockLoadResult: Equatable, Sendable {
    public let summaries: [SessionSummary]
    public let mappingFailures: [SessionSummaryMappingFailure]
    public let nextCursor: String?
    public let backwardsCursor: String?
    public let liveOverlay: ThreadListLiveOverlayDTO?

    public init(
        summaries: [SessionSummary],
        mappingFailures: [SessionSummaryMappingFailure] = [],
        nextCursor: String? = nil,
        backwardsCursor: String? = nil,
        liveOverlay: ThreadListLiveOverlayDTO? = nil
    ) {
        self.summaries = summaries
        self.mappingFailures = mappingFailures
        self.nextCursor = nextCursor
        self.backwardsCursor = backwardsCursor
        self.liveOverlay = liveOverlay
    }
}

public struct DockSessionQuery: Equatable, Sendable {
    public let archived: Bool
    public let sourceKinds: [ThreadSourceKind]?

    public init(
        archived: Bool = false,
        sourceKinds: [ThreadSourceKind]? = nil
    ) {
        self.archived = archived
        self.sourceKinds = sourceKinds
    }

    public static let activeHuman = DockSessionQuery(archived: false, sourceKinds: nil)
    public static let archivedHuman = DockSessionQuery(archived: true, sourceKinds: nil)
    public static let activeAgents = DockSessionQuery(
        archived: false,
        sourceKinds: ThreadSourceKind.dockAgentScopeKinds
    )
}

public protocol DockSessionLoading: Sendable {
    func loadSessions(
        for host: DockHostConfiguration,
        query: DockSessionQuery
    ) async throws -> DockLoadResult
}

public protocol DockSessionArchiving: Sendable {
    func archiveThread(_ threadID: String, on host: DockHostConfiguration) async throws
    func unarchiveThread(_ threadID: String, on host: DockHostConfiguration) async throws
}

public enum DockLoadFailure: Error, Equatable, LocalizedError, Sendable {
    case offline(String)
    case error(String)

    public var errorDescription: String? {
        switch self {
        case let .offline(message), let .error(message):
            return message
        }
    }
}

public struct AppServerDockClient: DockSessionLoading, DockSessionArchiving {
    private let humanSessionPageLimit = CodexDockConstants.Dock.humanSessionPageLimit
    private let agentSessionPageLimit = CodexDockConstants.Dock.agentSessionPageLimit

    public init() {}

    public func loadSessions(
        for host: DockHostConfiguration,
        query: DockSessionQuery
    ) async throws -> DockLoadResult {
        let startedAt = Date()
        let sourceKinds = query.sourceKinds?.map(\.rawValue).joined(separator: ",")
        DockLog.dock.info("dock client load started host_id=\(host.id, privacy: .public) endpoint=\(DockLog.endpoint(host.webSocketURL), privacy: .public) archived=\(query.archived, privacy: .public) source_kinds=\(DockLog.publicID(sourceKinds), privacy: .public)")
        return try await withClient(for: host) { client in
            let result = try await loadSessions(
                using: client,
                hostID: host.id,
                query: query
            )
            DockLog.dock.info("dock client load finished host_id=\(host.id, privacy: .public) archived=\(query.archived, privacy: .public) rows=\(result.summaries.count, privacy: .public) mapping_failures=\(result.mappingFailures.count, privacy: .public) duration_ms=\(DockLog.milliseconds(since: startedAt), privacy: .public)")
            return result
        }
    }

    func loadSessions(
        using client: AppServerClient,
        hostID: String,
        query: DockSessionQuery
    ) async throws -> DockLoadResult {
        var cursor: String?
        var seenCursors = Set<String>()
        var summaries: [SessionSummary] = []
        var mappingFailures: [SessionSummaryMappingFailure] = []
        var backwardsCursor: String?
        var nextCursor: String?
        var liveOverlay: ThreadListLiveOverlayDTO?

        repeat {
            let response = try await client.threadList(
                params: ThreadListParams(
                    cursor: cursor,
                    limit: pageLimit(for: query),
                    sortKey: .updatedAt,
                    sortDirection: .desc,
                    modelProviders: [],
                    sourceKinds: query.sourceKinds,
                    archived: query.archived
                ),
                timeout: CodexDockConstants.AppServer.defaultRequestTimeout
            )
            let mapped = SessionSummaryMapper.map(response: response, hostID: hostID)
            summaries.append(contentsOf: mapped.summaries)
            mappingFailures.append(contentsOf: mapped.failures)
            backwardsCursor = backwardsCursor ?? response.backwardsCursor
            nextCursor = response.nextCursor
            liveOverlay = combineLiveOverlay(current: liveOverlay, next: response.liveOverlay)

            guard let next = response.nextCursor, !next.isEmpty else {
                cursor = nil
                break
            }
            guard seenCursors.insert(next).inserted else {
                throw DockLoadFailure.error("Relay returned repeated thread/list cursor \(next)")
            }
            cursor = next
        } while cursor != nil

        return DockLoadResult(
            summaries: summaries,
            mappingFailures: mappingFailures,
            nextCursor: nextCursor,
            backwardsCursor: backwardsCursor,
            liveOverlay: liveOverlay
        )
    }

    private func pageLimit(for query: DockSessionQuery) -> Int {
        query == .activeAgents ? agentSessionPageLimit : humanSessionPageLimit
    }

    private func combineLiveOverlay(
        current: ThreadListLiveOverlayDTO?,
        next: ThreadListLiveOverlayDTO?
    ) -> ThreadListLiveOverlayDTO? {
        guard let next else {
            return current
        }
        return next
    }

    public func archiveThread(_ threadID: String, on host: DockHostConfiguration) async throws {
        DockLog.dock.notice("dock archive started host_id=\(host.id, privacy: .public) thread_id=\(DockLog.publicID(threadID), privacy: .public)")
        _ = try await withClient(for: host) { client in
            try await client.threadArchive(
                params: ThreadArchiveParams(threadId: threadID),
                timeout: CodexDockConstants.AppServer.defaultRequestTimeout
            )
        }
        DockLog.dock.notice("dock archive finished host_id=\(host.id, privacy: .public) thread_id=\(DockLog.publicID(threadID), privacy: .public)")
    }

    public func unarchiveThread(_ threadID: String, on host: DockHostConfiguration) async throws {
        DockLog.archive.notice("archive restore started host_id=\(host.id, privacy: .public) thread_id=\(DockLog.publicID(threadID), privacy: .public)")
        _ = try await withClient(for: host) { client in
            try await client.threadUnarchive(
                params: ThreadUnarchiveParams(threadId: threadID),
                timeout: CodexDockConstants.AppServer.defaultRequestTimeout
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
            throw mapLoadFailure(error)
        }
    }

    private func mapLoadFailure(_ error: Error) -> DockLoadFailure {
        if let failure = error as? DockLoadFailure {
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

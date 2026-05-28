import Combine
import Foundation

public struct DockLoadResult: Equatable, Sendable {
    public let summaries: [SessionSummary]
    public let mappingFailures: [SessionSummaryMappingFailure]

    public init(
        summaries: [SessionSummary],
        mappingFailures: [SessionSummaryMappingFailure] = []
    ) {
        self.summaries = summaries
        self.mappingFailures = mappingFailures
    }
}

public protocol DockSessionLoading: Sendable {
    func loadSessions(for host: DockHostConfiguration) async throws -> DockLoadResult
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

public struct AppServerDockClient: DockSessionLoading {
    private let sessionPageLimit = 200

    public init() {}

    public func loadSessions(for host: DockHostConfiguration) async throws -> DockLoadResult {
        let client = AppServerClient(
            webSocketURL: host.webSocketURL,
            bearerToken: host.bearerToken
        )

        do {
            _ = try await client.connectAndInitialize(
                params: .codexDock(version: "0.1.0"),
                timeout: .seconds(5)
            )

            let response = try await client.threadList(
                params: ThreadListParams(
                    limit: sessionPageLimit,
                    sortKey: .updatedAt,
                    sortDirection: .desc,
                    modelProviders: []
                ),
                timeout: .seconds(10)
            )
            let mapped = SessionSummaryMapper.map(response: response, hostID: host.id)
            await client.disconnect()

            return DockLoadResult(
                summaries: mapped.summaries,
                mappingFailures: mapped.failures
            )
        } catch {
            await client.disconnect()
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

public enum DockRowStatusKind: String, Equatable, Sendable, CaseIterable {
    case needsMe
    case running
    case idle
    case limited
    case failed
    case unknown

    public var label: String {
        switch self {
        case .needsMe:
            return "Needs me"
        case .running:
            return "Running"
        case .idle:
            return "Idle"
        case .limited:
            return "Limited"
        case .failed:
            return "Error"
        case .unknown:
            return "Unknown"
        }
    }
}

public enum DockRowRail: String, Equatable, Sendable, CaseIterable {
    case blue
    case green
    case orange
    case red
    case violet
}

public struct DockRowViewModel: Equatable, Identifiable, Sendable {
    public let id: HostScopedThreadID
    public let title: String
    public let repository: String
    public let branch: String
    public let status: DockRowStatusKind
    public let lastActivity: String
    public let lastActivityDate: Date
    public let summary: String
    public let rail: DockRowRail
}

public struct DockSectionViewModel: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let rows: [DockRowViewModel]
}

public struct DockHostViewModel: Equatable, Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public let endpoint: String

    public init(host: DockHostConfiguration) {
        self.id = host.id
        self.displayName = host.displayName
        self.endpoint = host.webSocketURL.host ?? host.webSocketURL.absoluteString
    }
}

public struct DockSnapshot: Equatable, Sendable {
    public let host: DockHostViewModel
    public let sections: [DockSectionViewModel]
    public let mappingFailures: [SessionSummaryMappingFailure]

    public var rowCount: Int {
        sections.reduce(0) { count, section in
            count + section.rows.count
        }
    }
}

public enum DockStoreState: Equatable, Sendable {
    case configurationError(String)
    case idle(DockHostViewModel)
    case loading(DockHostViewModel)
    case loaded(DockSnapshot)
    case empty(DockHostViewModel)
    case offline(DockHostViewModel, String)
    case error(DockHostViewModel, String)
}

@MainActor
public final class DockStore: ObservableObject {
    public static let defaultAutoRefreshInterval: Duration = .seconds(5)

    @Published public private(set) var state: DockStoreState

    private let host: DockHostConfiguration?
    private let loader: any DockSessionLoading
    private let now: @Sendable () -> Date
    private var isLoading = false

    public init(
        host: DockHostConfiguration,
        loader: any DockSessionLoading = AppServerDockClient(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.host = host
        self.loader = loader
        self.now = now
        self.state = .idle(DockHostViewModel(host: host))
    }

    public init(
        configurationError error: Error,
        loader: any DockSessionLoading = AppServerDockClient(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.host = nil
        self.loader = loader
        self.now = now
        self.state = .configurationError(error.localizedDescription)
    }

    public func load() async {
        await reload(showLoading: true)
    }

    public func refresh() async {
        await reload(showLoading: false)
    }

    private func reload(showLoading: Bool) async {
        guard let host else {
            return
        }
        guard !isLoading else {
            return
        }

        isLoading = true
        defer { isLoading = false }

        let hostViewModel = DockHostViewModel(host: host)
        if showLoading {
            state = .loading(hostViewModel)
        }

        do {
            let result = try await loader.loadSessions(for: host)
            let snapshot = makeSnapshot(
                host: hostViewModel,
                summaries: result.summaries,
                mappingFailures: result.mappingFailures
            )
            state = snapshot.rowCount == 0 ? .empty(hostViewModel) : .loaded(snapshot)
        } catch let failure as DockLoadFailure {
            switch failure {
            case let .offline(message):
                state = .offline(hostViewModel, message)
            case let .error(message):
                state = .error(hostViewModel, message)
            }
        } catch {
            state = .error(hostViewModel, error.localizedDescription)
        }
    }

    private func makeSnapshot(
        host: DockHostViewModel,
        summaries: [SessionSummary],
        mappingFailures: [SessionSummaryMappingFailure]
    ) -> DockSnapshot {
        let rows = summaries.map(makeRow)
        let groupedRows = Dictionary(grouping: rows, by: \.branch)
        let sections = groupedRows
            .map { branch, rows in
                DockSectionViewModel(
                    id: branch,
                    title: branch,
                    rows: rows.sorted(by: rowPrecedes)
                )
            }
            .sorted(by: sectionPrecedes)

        return DockSnapshot(
            host: host,
            sections: sections,
            mappingFailures: mappingFailures
        )
    }

    private func sectionPrecedes(_ lhs: DockSectionViewModel, _ rhs: DockSectionViewModel) -> Bool {
        let lhsDate = lhs.rows.map(\.lastActivityDate).max() ?? Date.distantPast
        let rhsDate = rhs.rows.map(\.lastActivityDate).max() ?? Date.distantPast
        if lhsDate != rhsDate {
            return lhsDate > rhsDate
        }

        let lhsPriority = lhs.rows.map { statusPriority($0.status) }.min() ?? Int.max
        let rhsPriority = rhs.rows.map { statusPriority($0.status) }.min() ?? Int.max
        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
        }

        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private func rowPrecedes(_ lhs: DockRowViewModel, _ rhs: DockRowViewModel) -> Bool {
        if lhs.lastActivityDate != rhs.lastActivityDate {
            return lhs.lastActivityDate > rhs.lastActivityDate
        }

        let lhsPriority = statusPriority(lhs.status)
        let rhsPriority = statusPriority(rhs.status)
        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
        }

        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private func statusPriority(_ status: DockRowStatusKind) -> Int {
        switch status {
        case .needsMe:
            return 0
        case .running:
            return 1
        case .failed:
            return 2
        case .idle:
            return 3
        case .unknown:
            return 4
        case .limited:
            return 5
        }
    }

    private func makeRow(summary: SessionSummary) -> DockRowViewModel {
        DockRowViewModel(
            id: summary.id,
            title: title(for: summary),
            repository: repository(for: summary),
            branch: text(summary.branch, fallback: "No branch"),
            status: status(for: summary),
            lastActivity: relativeTime(since: summary.lastActivity),
            lastActivityDate: summary.lastActivity,
            summary: latestSummary(for: summary),
            rail: rail(for: summary)
        )
    }

    private func title(for summary: SessionSummary) -> String {
        nonEmpty(summary.displayTitle) ?? summary.id.threadID
    }

    private func repository(for summary: SessionSummary) -> String {
        if let repo = nonEmpty(text(summary.repository, fallback: "")) {
            return repo
        }

        return text(summary.workingDirectory, fallback: "Unknown workspace")
    }

    private func latestSummary(for summary: SessionSummary) -> String {
        if let eventSummary = nonEmpty(text(summary.shortEventSummary, fallback: "")) {
            return eventSummary
        }

        return summary.displayTitle
    }

    private func status(for summary: SessionSummary) -> DockRowStatusKind {
        switch summary.status {
        case .idle:
            return .idle
        case .active(let activeFlags):
            return activeFlags.contains(.waitingOnApproval) || activeFlags.contains(.waitingOnUserInput)
                ? .needsMe
                : .running
        case .notLoaded:
            return .limited
        case .systemError:
            return .failed
        case .unknown:
            return .unknown
        }
    }

    private func relativeTime(since date: Date) -> String {
        let seconds = max(0, Int(now().timeIntervalSince(date)))

        switch seconds {
        case 0..<60:
            return "now"
        case 60..<3_600:
            return "\(seconds / 60)m ago"
        case 3_600..<86_400:
            return "\(seconds / 3_600)h ago"
        default:
            return "\(seconds / 86_400)d ago"
        }
    }

    private func rail(for summary: SessionSummary) -> DockRowRail {
        let rails = DockRowRail.allCases
        let checksum = summary.id.threadID.utf8.reduce(UInt64(0)) { partial, byte in
            (partial &* 31) &+ UInt64(byte)
        }
        return rails[Int(checksum % UInt64(rails.count))]
    }

    private func text(_ value: SessionSummaryText, fallback: String) -> String {
        switch value {
        case let .known(text):
            return nonEmpty(text) ?? fallback
        case .unknown:
            return fallback
        }
    }

    private func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            return trimmed
        }
        return nil
    }
}

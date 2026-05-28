import Combine
import Foundation

public protocol ThreadDetailSession: Sendable {
    var notifications: AsyncStream<JSONRPCNotification> { get }
    var serverRequests: AsyncStream<JSONRPCRequest> { get }

    func connectAndInitialize(params: InitializeParams, timeout: Duration) async throws -> InitializeResponse
    func threadRead(params: ThreadReadParams, timeout: Duration) async throws -> ThreadReadResponseDTO
    func threadResume(params: ThreadResumeParams, timeout: Duration) async throws -> ThreadResumeResponseDTO
    func disconnect() async
}

extension AppServerClient: ThreadDetailSession {}

public protocol ThreadDetailSessionMaking: Sendable {
    func makeSession(for host: DockHostConfiguration) -> any ThreadDetailSession
}

public struct AppServerThreadDetailSessionFactory: ThreadDetailSessionMaking {
    public init() {}

    public func makeSession(for host: DockHostConfiguration) -> any ThreadDetailSession {
        AppServerClient(
            webSocketURL: host.webSocketURL,
            bearerToken: host.bearerToken
        )
    }
}

public enum ThreadDetailLiveState: Equatable, Sendable {
    case connecting
    case live
    case stale(String)
    case closed

    public var label: String {
        switch self {
        case .connecting:
            return "Connecting"
        case .live:
            return "Live"
        case .stale:
            return "Stale"
        case .closed:
            return "Closed"
        }
    }
}

public struct ThreadDetailHeader: Equatable, Sendable {
    public let hostID: String
    public let hostName: String
    public let threadID: String
    public let title: String
    public let repository: String
    public let branch: String
    public let statusLabel: String
    public let lastActivity: String
    public let lastActivityDate: Date

    public init(host: DockHostConfiguration, row: DockRowViewModel) {
        self.hostID = host.id
        self.hostName = host.displayName
        self.threadID = row.id.threadID
        self.title = row.title
        self.repository = row.repository
        self.branch = row.branch
        self.statusLabel = row.status.label
        self.lastActivity = row.lastActivity
        self.lastActivityDate = row.lastActivityDate
    }
}

public struct ThreadDetailSnapshot: Equatable, Sendable {
    public let header: ThreadDetailHeader
    public let liveState: ThreadDetailLiveState
    public let events: [ThreadEvent]
}

public enum ThreadDetailStoreState: Equatable, Sendable {
    case idle(ThreadDetailHeader)
    case loading(ThreadDetailHeader)
    case loaded(ThreadDetailSnapshot)
    case error(ThreadDetailHeader, String)
}

@MainActor
public final class ThreadDetailStore: ObservableObject {
    @Published public private(set) var state: ThreadDetailStoreState

    private let host: DockHostConfiguration
    private let row: DockRowViewModel
    private let header: ThreadDetailHeader
    private let factory: any ThreadDetailSessionMaking
    private let now: @Sendable () -> Date

    private var session: (any ThreadDetailSession)?
    private var notificationTask: Task<Void, Never>?
    private var requestTask: Task<Void, Never>?
    private var events: [ThreadEvent] = []
    private var liveState: ThreadDetailLiveState = .connecting
    private var didLoad = false

    public init(
        host: DockHostConfiguration,
        row: DockRowViewModel,
        factory: any ThreadDetailSessionMaking = AppServerThreadDetailSessionFactory(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.host = host
        self.row = row
        self.header = ThreadDetailHeader(host: host, row: row)
        self.factory = factory
        self.now = now
        self.state = .idle(ThreadDetailHeader(host: host, row: row))
    }

    deinit {
        notificationTask?.cancel()
        requestTask?.cancel()
        let session = session
        Task {
            await session?.disconnect()
        }
    }

    public func load() async {
        guard !didLoad else {
            return
        }
        didLoad = true

        guard row.id.hostID == host.id else {
            state = .error(
                header,
                "This row belongs to host \(row.id.hostID), not \(host.id)."
            )
            return
        }

        state = .loading(header)
        liveState = .connecting

        let session = factory.makeSession(for: host)
        self.session = session

        do {
            _ = try await session.connectAndInitialize(
                params: .codexDock(version: "0.1.0"),
                timeout: .seconds(5)
            )
            startObservation(session: session)

            let readResponse = try await session.threadRead(
                params: ThreadReadParams(threadId: row.id.threadID, includeTurns: true),
                timeout: .seconds(10)
            )
            try replaceEvents(from: readResponse.thread, liveState: .connecting)

            do {
                let resumeResponse = try await session.threadResume(
                    params: ThreadResumeParams(threadId: row.id.threadID),
                    timeout: .seconds(10)
                )
                try replaceEvents(from: resumeResponse.thread, liveState: .live)
            } catch {
                liveState = .stale(message(from: error))
                publishLoaded()
            }
        } catch {
            state = .error(header, message(from: error))
            await session.disconnect()
        }
    }

    public func close() {
        notificationTask?.cancel()
        notificationTask = nil
        requestTask?.cancel()
        requestTask = nil

        let session = session
        self.session = nil
        Task {
            await session?.disconnect()
        }
    }

    private func startObservation(session: any ThreadDetailSession) {
        notificationTask?.cancel()
        requestTask?.cancel()

        notificationTask = Task { [weak self] in
            for await notification in session.notifications {
                self?.handle(notification: notification)
            }
        }

        requestTask = Task { [weak self] in
            for await request in session.serverRequests {
                self?.handle(request: request)
            }
        }
    }

    private func replaceEvents(from thread: ThreadDTO, liveState: ThreadDetailLiveState) throws {
        try validate(thread: thread)
        events = ThreadEventNormalizer.events(from: thread)
        self.liveState = liveState
        publishLoaded()
    }

    private func validate(thread: ThreadDTO) throws {
        guard thread.id == row.id.threadID else {
            throw ThreadDetailStoreError.threadMismatch(
                expected: row.id.threadID,
                actual: thread.id ?? "missing"
            )
        }
    }

    private func handle(notification: JSONRPCNotification) {
        guard ThreadEventNormalizer.threadId(from: notification) == row.id.threadID else {
            return
        }

        if notification.method == "thread/closed" {
            liveState = .closed
        } else {
            liveState = .live
        }

        guard let event = ThreadEventNormalizer.event(from: notification, now: now()) else {
            publishLoaded()
            return
        }
        appendOrMerge(event)
        publishLoaded()
    }

    private func handle(request: JSONRPCRequest) {
        guard ThreadEventNormalizer.threadId(from: request) == row.id.threadID else {
            return
        }

        liveState = .live
        appendOrMerge(ThreadEventNormalizer.event(from: request, now: now()))
        publishLoaded()
    }

    private func appendOrMerge(_ event: ThreadEvent) {
        guard let index = events.firstIndex(where: { $0.id == event.id }) else {
            events.append(event)
            return
        }

        if events[index].isLive, event.isLive, events[index].kind == event.kind {
            events[index].body += event.body
        } else {
            events[index] = event
        }
    }

    private func publishLoaded() {
        state = .loaded(
            ThreadDetailSnapshot(
                header: header,
                liveState: liveState,
                events: events
            )
        )
    }

    private func message(from error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}

public enum ThreadDetailStoreError: Error, Equatable, LocalizedError, Sendable {
    case threadMismatch(expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case let .threadMismatch(expected, actual):
            return "App-server returned thread \(actual), expected \(expected)."
        }
    }
}

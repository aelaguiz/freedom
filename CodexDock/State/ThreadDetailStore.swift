import Combine
import Foundation

public protocol ThreadDetailSession: Sendable {
    var connectionStates: AsyncStream<AppServerConnectionState> { get }
    var notifications: AsyncStream<JSONRPCNotification> { get }
    var serverRequests: AsyncStream<JSONRPCRequest> { get }

    func connectAndInitialize(params: InitializeParams, timeout: Duration) async throws -> InitializeResponse
    func threadRead(params: ThreadReadParams, timeout: Duration) async throws -> ThreadReadResponseDTO
    func threadTurnsList(params: ThreadTurnsListParams, timeout: Duration) async throws -> ThreadTurnsListResponseDTO
    func threadResume(params: ThreadResumeParams, timeout: Duration) async throws -> ThreadResumeResponseDTO
    func turnStart(params: TurnStartParams, timeout: Duration) async throws -> TurnStartResponseDTO
    func turnSteer(params: TurnSteerParams, timeout: Duration) async throws -> TurnSteerResponseDTO
    func sendResponse(id: JSONRPCRequestID, result: JSONValue) async throws
    func disconnect() async
}

extension AppServerClient: ThreadDetailSession {}

public protocol ThreadDetailSessionMaking: Sendable {
    func makeSession(for host: DockHostConfiguration) -> any ThreadDetailSession
    func makeSession(
        for host: DockHostConfiguration,
        foregroundWorkGate: (any AppForegroundWorkGating)?
    ) -> any ThreadDetailSession
}

public extension ThreadDetailSessionMaking {
    func makeSession(
        for host: DockHostConfiguration,
        foregroundWorkGate: (any AppForegroundWorkGating)?
    ) -> any ThreadDetailSession {
        makeSession(for: host)
    }
}

public enum ThreadDetailLiveState: Equatable, Sendable {
    case connecting
    case reconnecting(String)
    case live
    case stale(String)
    case closed

    public var label: String {
        switch self {
        case .connecting:
            return "Connecting"
        case .reconnecting:
            return "Reconnecting"
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
    public let statusLabel: String?
    public let lastActivity: String
    public let lastActivityDate: Date
    public let relationship: DockRowThreadRelationship

    public init(host: DockHostConfiguration, row: DockRowViewModel) {
        self.hostID = host.id
        self.hostName = host.displayName
        self.threadID = row.id.threadID
        self.title = row.title
        self.repository = row.repository
        self.branch = row.branch
        self.statusLabel = row.status.visibleBadgeLabel
        self.lastActivity = row.lastActivity
        self.lastActivityDate = row.lastActivityDate
        self.relationship = row.relationship
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
    private struct FullThreadRead {
        let thread: ThreadDTO
        let turns: [JSONValue]
    }

    private static let turnPageLimit = CodexDockConstants.Dock.turnPageLimit
    @Published public private(set) var state: ThreadDetailStoreState
    @Published public private(set) var requestCards: [ServerRequestCard] = []

    let screenStore: ThreadDetailScreenStore

    public internal(set) var composer: ComposerState {
        get {
            screenStore.composer
        }
        set {
            screenStore.setComposer(newValue)
        }
    }

    private let host: DockHostConfiguration
    let row: DockRowViewModel
    private let hostIdentityResolver: DockHostIdentityResolver
    private let header: ThreadDetailHeader
    private let factory: any ThreadDetailSessionMaking
    private let dataEngine: ThreadDetailDataEngine
    private let commandEngine: ClientCommandEngine
    let transcriptionEngine: TranscriptionEngine
    let voiceCaptureEngine: VoiceCaptureEngine
    let transcriptionService: any RealtimeTranscriptionServicing
    let liveVoiceCaptureController: any LiveVoiceCaptureControlling
    private let lifecycleCoordinator: AppLifecycleCoordinator?
    private weak var connectivityReporter: (any AppConnectivityReporting)?
    private let connectivityEventSink: ConnectivityEventSink?
    private let now: @Sendable () -> Date

    private var session: (any ThreadDetailSession)?
    private var connectionTask: Task<Void, Never>?
    private var notificationTask: Task<Void, Never>?
    private var requestTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?
    private var lifecycleTask: Task<Void, Never>?
    var transcriptionTask: Task<Void, Never>?
    var voiceCaptureTask: Task<Void, Never>?
    var voiceTranscriptPublishTask: Task<Void, Never>?
    var activeTranscriptionSession: (any RealtimeTranscriptionSession)?
    var activeVoiceCaptureSession: (any LiveVoiceCaptureSession)?
    var activeDictationSegment: ActiveDictationSegment?
    private var handledForegroundResumeGeneration: Int?
    private var events: [ThreadEvent] = []
    private var liveState: ThreadDetailLiveState = .connecting
    private var latestConnectionState: AppServerConnectionState = .idle
    private var activeTurnID: String?
    private var didLoad = false
    private var isClosing = false
    private var liveEventBuffer = ThreadDetailLiveEventBuffer()

    public init(
        host: DockHostConfiguration,
        row: DockRowViewModel,
        factory: any ThreadDetailSessionMaking = AppServerThreadDetailSessionFactory(),
        realtimeTranscriptionService: (any RealtimeTranscriptionServicing)? = nil,
        liveVoiceCaptureController: (any LiveVoiceCaptureControlling)? = nil,
        lifecycleCoordinator: AppLifecycleCoordinator? = nil,
        connectivityReporter: (any AppConnectivityReporting)? = nil,
        connectivityEventSink: ConnectivityEventSink? = nil,
        hostIdentityResolver: DockHostIdentityResolver? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.host = host
        self.row = row
        self.hostIdentityResolver = hostIdentityResolver ?? DockHostIdentityResolver(hosts: [host])
        self.header = ThreadDetailHeader(host: host, row: row)
        self.screenStore = ThreadDetailScreenStore(header: self.header)
        self.factory = factory
        self.dataEngine = ThreadDetailDataEngine()
        self.commandEngine = ClientCommandEngine()
        self.transcriptionEngine = TranscriptionEngine()
        self.voiceCaptureEngine = VoiceCaptureEngine()
        self.transcriptionService = realtimeTranscriptionService ?? RelayRealtimeTranscriptionClient(host: host)
        self.liveVoiceCaptureController = liveVoiceCaptureController
            ?? (realtimeTranscriptionService == nil
                ? LiveVoiceCaptureController()
                : SilentLiveVoiceCaptureController())
        self.lifecycleCoordinator = lifecycleCoordinator
        self.connectivityReporter = connectivityReporter
        self.connectivityEventSink = connectivityEventSink
        self.now = now
        self.state = .idle(ThreadDetailHeader(host: host, row: row))
        self.screenStore.start()
        startLifecycleObservation()
    }

    deinit {
        connectionTask?.cancel()
        notificationTask?.cancel()
        requestTask?.cancel()
        recoveryTask?.cancel()
        lifecycleTask?.cancel()
        transcriptionTask?.cancel()
        voiceCaptureTask?.cancel()
        voiceTranscriptPublishTask?.cancel()
        let session = session
        let activeTranscriptionSession = activeTranscriptionSession
        let activeVoiceCaptureSession = activeVoiceCaptureSession
        Task {
            await activeVoiceCaptureSession?.cancel()
            await activeTranscriptionSession?.cancel()
            await session?.disconnect()
        }
    }

    public func load() async {
        guard !didLoad else {
            DockLog.threadDetail.debug("thread detail load skipped reason=already_loaded host_id=\(self.host.id, privacy: .public) thread_id=\(DockLog.publicID(self.row.id.threadID), privacy: .public)")
            return
        }
        didLoad = true

        guard hostIdentityResolver.contains(
            rowHostID: row.id.hostID,
            sourceConfiguredHostID: row.sourceHostID,
            in: host.id
        ) else {
            DockLog.threadDetail.error("thread detail load failed reason=host_mismatch expected=\(self.host.id, privacy: .public) actual=\(self.row.id.hostID, privacy: .public) thread_id=\(DockLog.publicID(self.row.id.threadID), privacy: .public)")
            let message = "This row belongs to host \(self.row.id.hostID), not \(self.host.id)."
            state = .error(
                header,
                message
            )
            screenStore.setError(header: header, message: message)
            return
        }

        state = .loading(header)
        screenStore.setLoading(header)
        liveState = .connecting
        isClosing = false
        let startedAt = Date()
        DockLog.threadDetail.notice("thread detail load started host_id=\(self.host.id, privacy: .public) thread_id=\(DockLog.publicID(self.row.id.threadID), privacy: .public)")

        let session = factory.makeSession(for: host, foregroundWorkGate: lifecycleCoordinator)
        self.session = session

        do {
            _ = try await session.connectAndInitialize(
                params: .codexDock(version: "0.1.0"),
                timeout: CodexDockConstants.AppServer.connectInitializeTimeout
            )
            latestConnectionState = .connected
            liveEventBuffer.begin()
            startObservation(session: session)

            let fullRead = try await readFullThread(session: session)
            DockLog.threadDetail.info("thread detail full read finished host_id=\(self.host.id, privacy: .public) thread_id=\(DockLog.publicID(self.row.id.threadID), privacy: .public) turns=\(fullRead.turns.count, privacy: .public)")
            try await replaceEvents(from: fullRead.thread, liveState: .connecting)

            do {
                let liveThread = try await resumeCompactThread(
                    session: session,
                    turns: fullRead.turns
                )
                try await replaceEvents(from: liveThread, liveState: .live)
                await replayBufferedLiveEvents()
                DockLog.threadDetail.notice("thread detail load finished live host_id=\(self.host.id, privacy: .public) thread_id=\(DockLog.publicID(self.row.id.threadID), privacy: .public) events=\(self.events.count, privacy: .public) duration_ms=\(DockLog.milliseconds(since: startedAt), privacy: .public)")
            } catch {
                liveEventBuffer.discard()
                liveState = .stale(message(from: error))
                publishLoaded()
                DockLog.threadDetail.warning("thread detail resume failed; loaded stale host_id=\(self.host.id, privacy: .public) thread_id=\(DockLog.publicID(self.row.id.threadID), privacy: .public) duration_ms=\(DockLog.milliseconds(since: startedAt), privacy: .public) error=\(DockLog.errorSummary(error), privacy: .public)")
            }
        } catch {
            liveEventBuffer.discard()
            let message = message(from: error)
            state = .error(header, message)
            screenStore.setError(header: header, message: message)
            await session.disconnect()
            DockLog.threadDetail.error("thread detail load failed host_id=\(self.host.id, privacy: .public) thread_id=\(DockLog.publicID(self.row.id.threadID), privacy: .public) duration_ms=\(DockLog.milliseconds(since: startedAt), privacy: .public) error=\(DockLog.errorSummary(error), privacy: .public)")
        }
    }

    public func close() {
        DockLog.threadDetail.notice("thread detail close requested host_id=\(self.host.id, privacy: .public) thread_id=\(DockLog.publicID(self.row.id.threadID), privacy: .public)")
        isClosing = true
        connectionTask?.cancel()
        connectionTask = nil
        notificationTask?.cancel()
        notificationTask = nil
        requestTask?.cancel()
        requestTask = nil
        recoveryTask?.cancel()
        recoveryTask = nil
        liveEventBuffer.discard()
        lifecycleTask?.cancel()
        lifecycleTask = nil
        transcriptionTask?.cancel()
        transcriptionTask = nil
        voiceCaptureTask?.cancel()
        voiceCaptureTask = nil
        voiceTranscriptPublishTask?.cancel()
        voiceTranscriptPublishTask = nil
        screenStore.stop()

        let activeVoiceCaptureSession = activeVoiceCaptureSession
        self.activeVoiceCaptureSession = nil
        let activeTranscriptionSession = activeTranscriptionSession
        self.activeTranscriptionSession = nil
        if let activeDictationSegment {
            composer.draft = activeDictationSegment.baseDraft
        }
        activeDictationSegment = nil
        composer.voice = ComposerVoiceState()

        let session = session
        self.session = nil
        Task {
            await activeVoiceCaptureSession?.cancel()
            await activeTranscriptionSession?.cancel()
            await session?.disconnect()
        }
    }

    public func updateDraft(_ draft: String) {
        guard composer.canEditDraft else {
            return
        }
        composer.draft = draft
        composer.lastError = nil
    }

    public func sendDraft() async {
        guard let session else {
            composer.lastError = "Thread is not connected."
            DockLog.threadDetail.warning("send draft skipped reason=no_session thread_id=\(DockLog.publicID(self.row.id.threadID), privacy: .public)")
            return
        }
        guard !composer.voice.phase.isBusy else {
            composer.lastError = "Finish dictation before sending."
            DockLog.threadDetail.warning("send draft skipped reason=voice_busy thread_id=\(DockLog.publicID(self.row.id.threadID), privacy: .public)")
            return
        }

        let text = composer.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            DockLog.threadDetail.debug("send draft skipped reason=empty thread_id=\(DockLog.publicID(self.row.id.threadID), privacy: .public)")
            return
        }

        let startedAt = Date()
        DockLog.threadDetail.notice("send draft started thread_id=\(DockLog.publicID(self.row.id.threadID), privacy: .public) characters=\(text.count, privacy: .public) active_turn=\((self.activeTurnID != nil), privacy: .public)")
        composer.isSending = true
        composer.lastError = nil

        do {
            let nextTurnID = try await commandEngine.sendDraft(
                text,
                threadID: row.id.threadID,
                activeTurnID: activeTurnID,
                session: session
            )
            activeTurnID = nextTurnID ?? activeTurnID
            await dataEngine.setActiveTurnID(activeTurnID)
            composer.draft = ""
            composer.isSending = false
            DockLog.threadDetail.notice("send draft finished thread_id=\(DockLog.publicID(self.row.id.threadID), privacy: .public) duration_ms=\(DockLog.milliseconds(since: startedAt), privacy: .public) active_turn_id=\(DockLog.publicID(self.activeTurnID), privacy: .public)")
        } catch {
            composer.isSending = false
            composer.lastError = message(from: error)
            DockLog.threadDetail.error("send draft failed thread_id=\(DockLog.publicID(self.row.id.threadID), privacy: .public) duration_ms=\(DockLog.milliseconds(since: startedAt), privacy: .public) error=\(DockLog.errorSummary(error), privacy: .public)")
        }
    }

    public func updateRequestCardInput(cardID: String, draft: String) {
        guard let index = requestCards.firstIndex(where: { $0.id == cardID }) else {
            return
        }
        requestCards[index].inputDraft = draft
        if case .failed = requestCards[index].status {
            requestCards[index].status = .pending
        }
        publishCurrentRenderState()
    }

    public func respond(to cardID: String, action: ServerRequestCardAction) async {
        guard let session else {
            setCardStatus(cardID: cardID, status: .failed("Thread is not connected."))
            DockLog.threadDetail.warning("request card response skipped reason=no_session card_id=\(DockLog.publicID(cardID), privacy: .public)")
            return
        }
        guard let index = requestCards.firstIndex(where: { $0.id == cardID }) else {
            return
        }
        let card = requestCards[index]
        guard let payload = card.responsePayload(for: action) else {
            setCardStatus(cardID: cardID, status: .failed("This request cannot be answered on phone."))
            return
        }

        setCardStatus(cardID: cardID, status: .responding)
        let startedAt = Date()
        DockLog.threadDetail.notice("request card response started card_id=\(DockLog.publicID(cardID), privacy: .public) method=\(card.method, privacy: .public) action=\(action.logDescription, privacy: .public)")
        do {
            try await commandEngine.respondToServerRequest(
                requestID: card.requestID,
                payload: payload,
                session: session
            )
            setCardStatus(cardID: cardID, status: .resolved)
            DockLog.threadDetail.notice("request card response finished card_id=\(DockLog.publicID(cardID), privacy: .public) duration_ms=\(DockLog.milliseconds(since: startedAt), privacy: .public)")
        } catch {
            setCardStatus(cardID: cardID, status: .failed(message(from: error)))
            DockLog.threadDetail.error("request card response failed card_id=\(DockLog.publicID(cardID), privacy: .public) duration_ms=\(DockLog.milliseconds(since: startedAt), privacy: .public) error=\(DockLog.errorSummary(error), privacy: .public)")
        }
    }

    private func startObservation(session: any ThreadDetailSession) {
        connectionTask?.cancel()
        notificationTask?.cancel()
        requestTask?.cancel()

        connectionTask = Task { [weak self] in
            for await state in session.connectionStates {
                self?.handle(connectionState: state)
            }
        }

        notificationTask = Task { [weak self] in
            for await notification in session.notifications {
                await self?.handle(notification: notification)
            }
            DockLog.threadDetail.warning("thread notification stream ended")
            self?.markLiveSessionStale("Live update stream ended.")
        }

        requestTask = Task { [weak self] in
            for await request in session.serverRequests {
                await self?.handle(request: request)
            }
            DockLog.threadDetail.warning("server request stream ended")
            self?.markLiveSessionStale("Server request stream ended.")
        }
    }

    private func startLifecycleObservation() {
        guard let lifecycleCoordinator else {
            return
        }

        let snapshots = lifecycleCoordinator.makeSnapshotStream()
        lifecycleTask?.cancel()
        lifecycleTask = Task { [weak self] in
            for await snapshot in snapshots {
                await self?.handle(lifecycleSnapshot: snapshot)
            }
        }
    }

    private func handle(lifecycleSnapshot snapshot: AppLifecycleSnapshot) async {
        switch snapshot.phase {
        case .backgrounded:
            await handleAppBackgrounded()
        case .foregroundResuming:
            await handleForegroundResuming(snapshot)
        case .active, .inactive:
            return
        }
    }

    private func handleAppBackgrounded() async {
        guard !isClosing else {
            return
        }

        recoveryTask?.cancel()
        recoveryTask = nil

        if composer.voice.phase.isBusy {
            DockLog.voice.notice("voice capture stopping reason=backgrounded thread_id=\(DockLog.publicID(self.row.id.threadID), privacy: .public)")
            let activeTranscriptionSession = activeTranscriptionSession
            await cancelActiveVoiceCapture()
            failActiveDictation(message: "Dictation stopped because the app moved to the background.")
            await activeTranscriptionSession?.cancel()
        }

        guard case .loaded = state, liveState != .closed else {
            return
        }

        liveState = .stale("Backgrounded")
        DockLog.threadDetail.notice("thread detail marked stale reason=backgrounded thread_id=\(DockLog.publicID(self.row.id.threadID), privacy: .public)")
        publishLoaded()
    }

    private func handleForegroundResuming(_ snapshot: AppLifecycleSnapshot) async {
        guard handledForegroundResumeGeneration != snapshot.resumeGeneration else {
            return
        }
        handledForegroundResumeGeneration = snapshot.resumeGeneration

        guard !isClosing,
              case .loaded = state,
              liveState != .closed,
              let session else {
            return
        }

        recoveryTask?.cancel()
        recoveryTask = nil
        if latestConnectionState == .connected {
            await rehydrateAfterReconnect(session: session, reason: "Resuming")
        } else if latestConnectionState.shouldWaitForForegroundRehydrate {
            markLiveSessionReconnecting("Resuming")
        } else {
            markLiveSessionStale(message(from: latestConnectionState))
        }
    }

    private func handle(connectionState: AppServerConnectionState) {
        latestConnectionState = connectionState
        DockLog.threadDetail.debug("thread detail connection state=\(connectionState.logDescription, privacy: .public) thread_id=\(DockLog.publicID(self.row.id.threadID), privacy: .public)")
        switch connectionState {
        case .reconnecting(_, let reason):
            markLiveSessionReconnecting(reason)
        case .connected:
            startRehydrateAfterReconnectIfNeeded()
        case .offline(let reason):
            markLiveSessionStale(reason)
        case .error(let message):
            markLiveSessionStale(message)
        case .closed(let reason):
            markLiveSessionStale(reason)
        case .idle, .connecting:
            return
        }
    }

    private func message(from connectionState: AppServerConnectionState) -> String {
        switch connectionState {
        case .idle:
            return "Waiting for connection."
        case .connecting:
            return "Connecting."
        case .connected:
            return "Connected."
        case .reconnecting(_, let reason):
            return reason
        case .offline(let reason):
            return reason
        case .error(let message):
            return message
        case .closed(let reason):
            return reason
        }
    }

    private func readFullThread(session: any ThreadDetailSession) async throws -> FullThreadRead {
        let startedAt = Date()
        let signpostState = DockSignpost.threadDetail.beginInterval("thread.readFull")
        defer {
            DockSignpost.threadDetail.endInterval("thread.readFull", signpostState)
        }
        let readResponse = try await session.threadRead(
            params: ThreadReadParams(threadId: row.id.threadID, includeTurns: false),
            timeout: CodexDockConstants.AppServer.defaultRequestTimeout
        )
        let turns = try await readAllTurns(session: session)
        DockLog.threadDetail.info("thread full read finished thread_id=\(DockLog.publicID(self.row.id.threadID), privacy: .public) turns=\(turns.count, privacy: .public) duration_ms=\(DockLog.milliseconds(since: startedAt), privacy: .public)")
        return FullThreadRead(
            thread: readResponse.thread.replacingTurns(turns),
            turns: turns
        )
    }

    private func readAllTurns(session: any ThreadDetailSession) async throws -> [JSONValue] {
        var cursor: String?
        var seenCursors = Set<String>()
        var turns: [JSONValue] = []

        repeat {
            let response = try await session.threadTurnsList(
                params: ThreadTurnsListParams(
                    threadId: row.id.threadID,
                    cursor: cursor,
                    limit: Self.turnPageLimit,
                    sortDirection: .desc,
                    itemsView: .full
                ),
                timeout: CodexDockConstants.AppServer.defaultRequestTimeout
            )
            turns.append(contentsOf: response.data)

            guard let nextCursor = response.nextCursor, !nextCursor.isEmpty else {
                cursor = nil
                break
            }
            guard seenCursors.insert(nextCursor).inserted else {
                throw ThreadDetailStoreError.repeatedTurnsCursor(nextCursor)
            }
            cursor = nextCursor
        } while cursor != nil

        return turns
    }

    private func resumeCompactThread(
        session: any ThreadDetailSession,
        turns: [JSONValue]
    ) async throws -> ThreadDTO {
        let startedAt = Date()
        let signpostState = DockSignpost.threadDetail.beginInterval("thread.resume")
        defer {
            DockSignpost.threadDetail.endInterval("thread.resume", signpostState)
        }
        let resumeResponse = try await session.threadResume(
            params: ThreadResumeParams(threadId: row.id.threadID, excludeTurns: true),
            timeout: CodexDockConstants.AppServer.defaultRequestTimeout
        )
        DockLog.threadDetail.info("thread resume finished thread_id=\(DockLog.publicID(self.row.id.threadID), privacy: .public) turns=\(turns.count, privacy: .public) duration_ms=\(DockLog.milliseconds(since: startedAt), privacy: .public)")
        return resumeResponse.thread.replacingTurns(turns)
    }

    private func startRehydrateAfterReconnectIfNeeded() {
        guard !isClosing,
              recoveryTask == nil,
              case .loaded = state,
              case let .reconnecting(reason) = liveState,
              let session else {
            return
        }

        recoveryTask = Task { [weak self] in
            await self?.rehydrateAfterReconnect(session: session, reason: reason)
        }
    }

    private func rehydrateAfterReconnect(
        session: any ThreadDetailSession,
        reason: String
    ) async {
        guard !isClosing, case .loaded = state else {
            recoveryTask = nil
            return
        }

        liveState = .reconnecting(reason)
        liveEventBuffer.begin()
        DockLog.threadDetail.notice("thread detail rehydrate started thread_id=\(DockLog.publicID(self.row.id.threadID), privacy: .public) reason=\(DockLog.redacted(reason), privacy: .public)")
        publishLoaded()

        do {
            let fullRead = try await readFullThread(session: session)
            let liveThread = try await resumeCompactThread(session: session, turns: fullRead.turns)
            try await replaceEvents(from: liveThread, liveState: .live)
            await replayBufferedLiveEvents()
            DockLog.threadDetail.notice("thread detail rehydrate finished thread_id=\(DockLog.publicID(self.row.id.threadID), privacy: .public) events=\(self.events.count, privacy: .public)")
        } catch {
            liveEventBuffer.discard()
            liveState = .stale(message(from: error))
            publishLoaded()
            DockLog.threadDetail.warning("thread detail rehydrate failed thread_id=\(DockLog.publicID(self.row.id.threadID), privacy: .public) error=\(DockLog.errorSummary(error), privacy: .public)")
        }

        recoveryTask = nil
    }

    private func markLiveSessionReconnecting(_ message: String) {
        guard !isClosing, case .loaded = state else {
            return
        }
        switch liveState {
        case .closed:
            return
        case .connecting, .reconnecting, .live, .stale:
            liveState = .reconnecting(message)
            DockLog.threadDetail.notice("thread detail reconnecting thread_id=\(DockLog.publicID(self.row.id.threadID), privacy: .public) reason=\(DockLog.redacted(message), privacy: .public)")
            publishLoaded()
        }
    }

    private func replaceEvents(from thread: ThreadDTO, liveState: ThreadDetailLiveState) async throws {
        let snapshot = try await dataEngine.replace(
            from: thread,
            expectedThreadID: row.id.threadID
        )
        applyDataSnapshot(snapshot)
        self.liveState = liveState
        publishLoaded()
    }

    private func mergeEvents(from thread: ThreadDTO, liveState: ThreadDetailLiveState) async throws {
        let snapshot = try await dataEngine.merge(
            from: thread,
            expectedThreadID: row.id.threadID
        )
        applyDataSnapshot(snapshot)
        self.liveState = liveState
        publishLoaded()
    }

    private func replayBufferedLiveEvents() async {
        while let bufferedEvents = liveEventBuffer.takeBatch() {
            for event in bufferedEvents {
                switch event {
                case .notification(let notification):
                    await apply(notification: notification)
                case .request(let request):
                    await apply(request: request)
                }
            }
        }
        liveEventBuffer.finishReplay()
    }

    private func handle(notification: JSONRPCNotification) async {
        if liveEventBuffer.isBuffering {
            liveEventBuffer.append(notification: notification)
            DockLog.threadDetail.debug("thread notification buffered during canonical load method=\(notification.method, privacy: .public) thread_id=\(DockLog.publicID(self.row.id.threadID), privacy: .public)")
            return
        }
        await apply(notification: notification)
    }

    private func apply(notification: JSONRPCNotification) async {
        guard let dataSnapshot = await dataEngine.apply(
            notification: notification,
            expectedThreadID: row.id.threadID,
            now: now()
        ) else {
            return
        }
        applyDataSnapshot(dataSnapshot)

        resolveRequestCard(from: notification)

        if notification.method == "thread/closed" {
            liveState = .closed
        } else {
            liveState = .live
        }
        DockLog.threadDetail.debug("thread notification handled method=\(notification.method, privacy: .public) thread_id=\(DockLog.publicID(self.row.id.threadID), privacy: .public) live_state=\(self.liveState.logDescription, privacy: .public)")

        publishLoaded()
    }

    private func handle(request: JSONRPCRequest) async {
        if liveEventBuffer.isBuffering {
            liveEventBuffer.append(request: request)
            DockLog.threadDetail.debug("server request buffered during canonical load method=\(request.method, privacy: .public) request_id=\(DockLog.publicID(request.id), privacy: .public) thread_id=\(DockLog.publicID(self.row.id.threadID), privacy: .public)")
            return
        }
        await apply(request: request)
    }

    private func apply(request: JSONRPCRequest) async {
        let receivedAt = now()
        guard let dataSnapshot = await dataEngine.apply(
            request: request,
            expectedThreadID: row.id.threadID,
            now: receivedAt
        ) else {
            return
        }
        applyDataSnapshot(dataSnapshot)

        liveState = .live
        upsertRequestCard(ServerRequestCard.make(from: request, now: receivedAt))
        DockLog.threadDetail.notice("server request received method=\(request.method, privacy: .public) request_id=\(DockLog.publicID(request.id), privacy: .public) thread_id=\(DockLog.publicID(self.row.id.threadID), privacy: .public)")
        publishLoaded()
    }

    private func markLiveSessionStale(_ message: String) {
        guard !isClosing, case .loaded = state else {
            return
        }
        switch liveState {
        case .closed, .stale:
            return
        case .connecting, .reconnecting, .live:
            break
        }
        liveState = .stale(message)
        DockLog.threadDetail.warning("thread detail marked stale thread_id=\(DockLog.publicID(self.row.id.threadID), privacy: .public) reason=\(DockLog.redacted(message), privacy: .public)")
        publishLoaded()
    }

    private func publishLoaded() {
        let signpostState = DockSignpost.rendering.beginInterval(RenderSignpostName.threadMainPublish)
        defer {
            DockSignpost.rendering.endInterval(RenderSignpostName.threadMainPublish, signpostState)
        }
        let snapshot = ThreadDetailSnapshot(
            header: header,
            liveState: liveState,
            events: events
        )
        state = .loaded(snapshot)
        screenStore.publish(snapshot: snapshot, requestCards: requestCards)
        publishConnectivity(liveState: liveState)
    }

    private func applyDataSnapshot(_ snapshot: ThreadDetailDataSnapshot) {
        events = snapshot.events
        activeTurnID = snapshot.activeTurnID
    }

    private func publishConnectivity(liveState: ThreadDetailLiveState) {
        guard let connectivityEventSink else {
            connectivityReporter?.reportThreadDetail(host: host, liveState: liveState)
            return
        }

        let event = ConnectivityRuntimeEvent(
            source: .threadDetail,
            hostID: host.id,
            route: "thread/detail",
            status: liveState.label,
            phase: connectivityPhase(for: liveState),
            recordedAt: now()
        )
        Task {
            await connectivityEventSink.record(event)
        }
    }

    private nonisolated func connectivityPhase(
        for liveState: ThreadDetailLiveState
    ) -> HostConnectivityPhase {
        switch liveState {
        case .connecting:
            return .checking
        case .reconnecting(let message):
            return .reconnecting(message)
        case .live:
            return .online("Live")
        case .stale(let message):
            return .stale(message)
        case .closed:
            return .offline("Closed")
        }
    }

    private func setCardStatus(cardID: String, status: ServerRequestCardStatus) {
        guard let index = requestCards.firstIndex(where: { $0.id == cardID }) else {
            return
        }
        requestCards[index].status = status
        publishCurrentRenderState()
    }

    private func publishCurrentRenderState() {
        guard case .loaded(let snapshot) = state else {
            return
        }
        screenStore.publish(snapshot: snapshot, requestCards: requestCards)
    }

    private func upsertRequestCard(_ card: ServerRequestCard) {
        if let index = requestCards.firstIndex(where: { $0.id == card.id }) {
            let existing = requestCards[index]
            requestCards[index] = ServerRequestCard(
                id: card.id,
                requestID: card.requestID,
                method: card.method,
                threadID: card.threadID,
                turnID: card.turnID,
                itemID: card.itemID,
                kind: card.kind,
                title: card.title,
                summary: card.summary,
                detail: card.detail,
                params: card.params,
                requestedAt: card.requestedAt,
                inputDraft: existing.inputDraft,
                status: existing.status
            )
        } else {
            requestCards.append(card)
        }
    }

    private func resolveRequestCard(from notification: JSONRPCNotification) {
        guard notification.method == "serverRequest/resolved",
              let requestID = notification.params?.objectValue?["requestId"],
              let cardID = cardID(from: requestID) else {
            return
        }
        setCardStatus(cardID: cardID, status: .resolved)
    }

    private func cardID(from requestID: JSONValue) -> String? {
        if let value = requestID.stringValue {
            return "request-\(value)"
        }
        if let value = requestID.numberValue {
            return "request-\(Int64(value))"
        }
        return nil
    }

    private func message(from error: Error) -> String {
        if let message = ThreadDetailHumanOnlyRejection.message(for: error) {
            return message
        }
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }
        return error.localizedDescription
    }

}

private extension AppServerConnectionState {
    var logDescription: String {
        switch self {
        case .idle:
            return "idle"
        case .connecting:
            return "connecting"
        case .connected:
            return "connected"
        case .reconnecting(let attempt, let reason):
            return "reconnecting(attempt=\(attempt),reason=\(DockLog.redacted(reason)))"
        case .offline(let reason):
            return "offline(reason=\(DockLog.redacted(reason)))"
        case .error(let message):
            return "error(message=\(DockLog.redacted(message)))"
        case .closed(let reason):
            return "closed(reason=\(DockLog.redacted(reason)))"
        }
    }

    var shouldWaitForForegroundRehydrate: Bool {
        switch self {
        case .idle, .connecting, .reconnecting:
            return true
        case .connected, .offline, .error, .closed:
            return false
        }
    }
}

private extension ThreadDetailLiveState {
    var logDescription: String {
        switch self {
        case .connecting:
            return "connecting"
        case .reconnecting:
            return "reconnecting"
        case .live:
            return "live"
        case .stale:
            return "stale"
        case .closed:
            return "closed"
        }
    }
}

private extension ServerRequestCardAction {
    var logDescription: String {
        switch self {
        case .accept:
            return "accept"
        case .decline:
            return "decline"
        case .submitInput:
            return "submitInput"
        }
    }
}

public enum ThreadDetailStoreError: Error, Equatable, LocalizedError, Sendable {
    case threadMismatch(expected: String, actual: String)
    case repeatedTurnsCursor(String)

    public var errorDescription: String? {
        switch self {
        case let .threadMismatch(expected, actual):
            return "App-server returned thread \(actual), expected \(expected)."
        case let .repeatedTurnsCursor(cursor):
            return "App-server returned repeated thread turns cursor \(cursor)."
        }
    }
}

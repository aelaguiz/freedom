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
    private struct CompactThreadRead {
        let thread: ThreadDTO
        let turns: [JSONValue]
    }

    @Published public private(set) var state: ThreadDetailStoreState
    @Published public internal(set) var composer = ComposerState()
    @Published public private(set) var requestCards: [ServerRequestCard] = []

    private let host: DockHostConfiguration
    let row: DockRowViewModel
    private let header: ThreadDetailHeader
    private let factory: any ThreadDetailSessionMaking
    let transcriptionService: any RealtimeTranscriptionServicing
    let liveVoiceCaptureController: any LiveVoiceCaptureControlling
    private let lifecycleCoordinator: AppLifecycleCoordinator?
    private weak var connectivityReporter: (any AppConnectivityReporting)?
    private let now: @Sendable () -> Date

    private var session: (any ThreadDetailSession)?
    private var connectionTask: Task<Void, Never>?
    private var notificationTask: Task<Void, Never>?
    private var requestTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?
    private var lifecycleTask: Task<Void, Never>?
    var transcriptionTask: Task<Void, Never>?
    var voiceCaptureTask: Task<Void, Never>?
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

    public init(
        host: DockHostConfiguration,
        row: DockRowViewModel,
        factory: any ThreadDetailSessionMaking = AppServerThreadDetailSessionFactory(),
        realtimeTranscriptionService: (any RealtimeTranscriptionServicing)? = nil,
        liveVoiceCaptureController: (any LiveVoiceCaptureControlling)? = nil,
        lifecycleCoordinator: AppLifecycleCoordinator? = nil,
        connectivityReporter: (any AppConnectivityReporting)? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.host = host
        self.row = row
        self.header = ThreadDetailHeader(host: host, row: row)
        self.factory = factory
        self.transcriptionService = realtimeTranscriptionService ?? RelayRealtimeTranscriptionClient(host: host)
        self.liveVoiceCaptureController = liveVoiceCaptureController
            ?? (realtimeTranscriptionService == nil
                ? LiveVoiceCaptureController()
                : SilentLiveVoiceCaptureController())
        self.lifecycleCoordinator = lifecycleCoordinator
        self.connectivityReporter = connectivityReporter
        self.now = now
        self.state = .idle(ThreadDetailHeader(host: host, row: row))
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

        guard row.id.hostID == host.id else {
            DockLog.threadDetail.error("thread detail load failed reason=host_mismatch expected=\(self.host.id, privacy: .public) actual=\(self.row.id.hostID, privacy: .public) thread_id=\(DockLog.publicID(self.row.id.threadID), privacy: .public)")
            state = .error(
                header,
                "This row belongs to host \(self.row.id.hostID), not \(self.host.id)."
            )
            return
        }

        state = .loading(header)
        liveState = .connecting
        isClosing = false
        let startedAt = Date()
        DockLog.threadDetail.notice("thread detail load started host_id=\(self.host.id, privacy: .public) thread_id=\(DockLog.publicID(self.row.id.threadID), privacy: .public)")

        let session = factory.makeSession(for: host, foregroundWorkGate: lifecycleCoordinator)
        self.session = session

        do {
            _ = try await session.connectAndInitialize(
                params: .codexDock(version: "0.1.0"),
                timeout: .seconds(5)
            )
            latestConnectionState = .connected
            startObservation(session: session)

            let compactRead = try await readCompactThread(session: session)
            DockLog.threadDetail.info("thread detail compact read finished host_id=\(self.host.id, privacy: .public) thread_id=\(DockLog.publicID(self.row.id.threadID), privacy: .public) turns=\(compactRead.turns.count, privacy: .public)")
            try replaceEvents(from: compactRead.thread, liveState: .connecting)

            do {
                let liveThread = try await resumeCompactThread(
                    session: session,
                    turns: compactRead.turns
                )
                try replaceEvents(from: liveThread, liveState: .live)
                DockLog.threadDetail.notice("thread detail load finished live host_id=\(self.host.id, privacy: .public) thread_id=\(DockLog.publicID(self.row.id.threadID), privacy: .public) events=\(self.events.count, privacy: .public) duration_ms=\(DockLog.milliseconds(since: startedAt), privacy: .public)")
            } catch {
                liveState = .stale(message(from: error))
                publishLoaded()
                DockLog.threadDetail.warning("thread detail resume failed; loaded stale host_id=\(self.host.id, privacy: .public) thread_id=\(DockLog.publicID(self.row.id.threadID), privacy: .public) duration_ms=\(DockLog.milliseconds(since: startedAt), privacy: .public) error=\(DockLog.errorSummary(error), privacy: .public)")
            }
        } catch {
            state = .error(header, message(from: error))
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
        lifecycleTask?.cancel()
        lifecycleTask = nil
        transcriptionTask?.cancel()
        transcriptionTask = nil
        voiceCaptureTask?.cancel()
        voiceCaptureTask = nil

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
            if let activeTurnID {
                let response = try await session.turnSteer(
                    params: .text(
                        threadId: row.id.threadID,
                        text: text,
                        expectedTurnId: activeTurnID
                    ),
                    timeout: .seconds(10)
                )
                self.activeTurnID = response.turnId
            } else {
                let response = try await session.turnStart(
                    params: .text(threadId: row.id.threadID, text: text),
                    timeout: .seconds(10)
                )
                activeTurnID = turnID(from: response.turn) ?? activeTurnID
            }
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
            try await session.sendResponse(id: card.requestID, result: payload)
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
                self?.handle(notification: notification)
            }
            DockLog.threadDetail.warning("thread notification stream ended")
            self?.markLiveSessionStale("Live update stream ended.")
        }

        requestTask = Task { [weak self] in
            for await request in session.serverRequests {
                self?.handle(request: request)
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

    private func readCompactThread(session: any ThreadDetailSession) async throws -> CompactThreadRead {
        let startedAt = Date()
        let signpostState = DockSignpost.threadDetail.beginInterval("thread.readCompact")
        defer {
            DockSignpost.threadDetail.endInterval("thread.readCompact", signpostState)
        }
        let readResponse = try await session.threadRead(
            params: ThreadReadParams(threadId: row.id.threadID, includeTurns: false),
            timeout: .seconds(10)
        )
        let turnsResponse = try await session.threadTurnsList(
            params: ThreadTurnsListParams(threadId: row.id.threadID, limit: 10),
            timeout: .seconds(10)
        )
        DockLog.threadDetail.info("thread compact read finished thread_id=\(DockLog.publicID(self.row.id.threadID), privacy: .public) turns=\(turnsResponse.data.count, privacy: .public) duration_ms=\(DockLog.milliseconds(since: startedAt), privacy: .public)")
        return CompactThreadRead(
            thread: readResponse.thread.replacingTurns(turnsResponse.data),
            turns: turnsResponse.data
        )
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
            timeout: .seconds(10)
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
        DockLog.threadDetail.notice("thread detail rehydrate started thread_id=\(DockLog.publicID(self.row.id.threadID), privacy: .public) reason=\(DockLog.redacted(reason), privacy: .public)")
        publishLoaded()

        do {
            let compactRead = try await readCompactThread(session: session)
            let liveThread = try await resumeCompactThread(session: session, turns: compactRead.turns)
            try mergeEvents(from: liveThread, liveState: .live)
            DockLog.threadDetail.notice("thread detail rehydrate finished thread_id=\(DockLog.publicID(self.row.id.threadID), privacy: .public) events=\(self.events.count, privacy: .public)")
        } catch {
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

    private func replaceEvents(from thread: ThreadDTO, liveState: ThreadDetailLiveState) throws {
        try validate(thread: thread)
        events = ThreadEventNormalizer.events(from: thread)
        activeTurnID = activeTurnID(from: thread)
        self.liveState = liveState
        publishLoaded()
    }

    private func mergeEvents(from thread: ThreadDTO, liveState: ThreadDetailLiveState) throws {
        try validate(thread: thread)
        for event in ThreadEventNormalizer.events(from: thread) {
            appendOrMerge(event)
        }
        activeTurnID = activeTurnID(from: thread)
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

        updateActiveTurn(from: notification)
        resolveRequestCard(from: notification)

        if notification.method == "thread/closed" {
            liveState = .closed
        } else {
            liveState = .live
        }
        DockLog.threadDetail.debug("thread notification handled method=\(notification.method, privacy: .public) thread_id=\(DockLog.publicID(self.row.id.threadID), privacy: .public) live_state=\(self.liveState.logDescription, privacy: .public)")

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
        upsertRequestCard(ServerRequestCard.make(from: request, now: now()))
        appendOrMerge(ThreadEventNormalizer.event(from: request, now: now()))
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
                events: ThreadEventDisplayOrder.naturalFlow(events)
            )
        )
        connectivityReporter?.reportThreadDetail(host: host, liveState: liveState)
    }

    private func setCardStatus(cardID: String, status: ServerRequestCardStatus) {
        guard let index = requestCards.firstIndex(where: { $0.id == cardID }) else {
            return
        }
        requestCards[index].status = status
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

    private func updateActiveTurn(from notification: JSONRPCNotification) {
        guard let params = notification.params?.objectValue else {
            return
        }

        switch notification.method {
        case "turn/started":
            if let turn = params["turn"] {
                activeTurnID = turnID(from: turn)
            }
        case "turn/completed":
            if let turn = params["turn"], activeTurnID == turnID(from: turn) {
                activeTurnID = nil
            }
        default:
            return
        }
    }

    private func activeTurnID(from thread: ThreadDTO) -> String? {
        thread.turns?
            .compactMap { turn -> String? in
                guard let object = turn.objectValue,
                      object["status"]?.stringValue == "inProgress" else {
                    return nil
                }
                return object["id"]?.stringValue
            }
            .last
    }

    private func turnID(from turn: JSONValue) -> String? {
        turn.objectValue?["id"]?.stringValue
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

    public var errorDescription: String? {
        switch self {
        case let .threadMismatch(expected, actual):
            return "App-server returned thread \(actual), expected \(expected)."
        }
    }
}

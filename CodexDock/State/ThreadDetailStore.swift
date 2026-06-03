import Combine
import Foundation

public protocol ThreadDetailSession: Sendable {
    var connectionStates: AsyncStream<AppServerConnectionState> { get }
    var notifications: AsyncStream<JSONRPCNotification> { get }

    func connectAndInitialize(params: InitializeParams, timeout: Duration) async throws -> InitializeResponse
    func threadDetailSubscribe(params: ThreadDetailParams, timeout: Duration) async throws -> ThreadDetailSnapshotDTO
    func threadDetailResync(params: ThreadDetailParams, timeout: Duration) async throws -> ThreadDetailSnapshotDTO
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
        self.threadID = row.threadID
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
    private struct DockRowActivityMarker: Equatable, Sendable {
        let activityDate: Date
        let displayOrderKey: String?

        init(row: DockRowViewModel) {
            self.activityDate = row.lastActivityDate
            self.displayOrderKey = row.displayOrderKey
        }

        func isNewer(than other: DockRowActivityMarker) -> Bool {
            activityDate > other.activityDate
                || (activityDate == other.activityDate && displayOrderKey != other.displayOrderKey)
        }
    }

    @Published public private(set) var state: ThreadDetailStoreState
    public var requestCards: [ServerRequestCard] {
        requestCardPresentation.cards(from: events)
    }

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
    public private(set) var row: DockRowViewModel
    private let hostIdentityResolver: DockHostIdentityResolver
    private var header: ThreadDetailHeader
    private let factory: any ThreadDetailSessionMaking
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
    private var reconciler: StreamReconciler<ThreadDetailEventDTO>?
    private var reconcilerTask: Task<Void, Never>?
    private var connectionTask: Task<Void, Never>?
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
    private var requestCardPresentation = ThreadDetailRequestCardPresentation()
    private var latestDockRowActivityMarker: DockRowActivityMarker
    private var lastCompletedDockRowRefreshMarker: DockRowActivityMarker

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
        dockRowSettleRefreshDelay _: Duration = CodexDockConstants.Dock.threadDetailCanonicalHistorySettleDelay,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.host = host
        self.row = row
        self.hostIdentityResolver = hostIdentityResolver ?? DockHostIdentityResolver(hosts: [host])
        self.header = ThreadDetailHeader(host: host, row: row)
        self.screenStore = ThreadDetailScreenStore(header: self.header)
        self.factory = factory
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
        let dockActivityMarker = DockRowActivityMarker(row: row)
        self.latestDockRowActivityMarker = dockActivityMarker
        self.lastCompletedDockRowRefreshMarker = dockActivityMarker
        self.screenStore.start()
        startLifecycleObservation()
    }

    deinit {
        reconcilerTask?.cancel()
        connectionTask?.cancel()
        lifecycleTask?.cancel()
        transcriptionTask?.cancel()
        voiceCaptureTask?.cancel()
        voiceTranscriptPublishTask?.cancel()
        let session = session
        let reconciler = reconciler
        let activeTranscriptionSession = activeTranscriptionSession
        let activeVoiceCaptureSession = activeVoiceCaptureSession
        Task {
            await activeVoiceCaptureSession?.cancel()
            await activeTranscriptionSession?.cancel()
            if let reconciler {
                await reconciler.close()
            } else {
                await session?.disconnect()
            }
        }
    }

    public func load() async {
        guard !didLoad else {
            DockLog.threadDetail.debug("thread detail load skipped reason=already_loaded host_id=\(self.host.id, privacy: .public) thread_id=\(DockLog.publicID(self.row.threadID), privacy: .public)")
            return
        }
        didLoad = true

        guard hostIdentityResolver.contains(
            rowHostID: row.hostID,
            sourceConfiguredHostID: row.sourceHostID,
            in: host.id
        ) else {
            DockLog.threadDetail.error("thread detail load failed reason=host_mismatch expected=\(self.host.id, privacy: .public) actual=\(self.row.hostID, privacy: .public) thread_id=\(DockLog.publicID(self.row.threadID), privacy: .public)")
            let message = "This row belongs to host \(self.row.hostID), not \(self.host.id)."
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
        DockLog.threadDetail.notice("thread detail load started host_id=\(self.host.id, privacy: .public) thread_id=\(DockLog.publicID(self.row.threadID), privacy: .public)")

        let session = factory.makeSession(for: host, foregroundWorkGate: lifecycleCoordinator)
        self.session = session
        let reconciler = StreamReconciler(
            viewKey: ProjectionViewKey(
                sourceHostID: row.sourceHostID,
                view: ThreadDetailProjectionContract.view,
                scope: "thread",
                viewParamsKey: nil
            ),
            policy: .threadDetail(threadID: row.threadID),
            connector: ThreadDetailProjectionStreamConnector(
                session: session,
                threadID: row.threadID
            )
        )
        self.reconciler = reconciler
        await reconciler.start()
        let projectionSnapshot = await reconciler.snapshot()
        do {
            try applyProjectionSnapshot(projectionSnapshot, failEmptyFailure: true)
            await startReconcilerObservation(reconciler)
            startObservation(session: session, reconciler: reconciler)
            if case .live = projectionSnapshot.freshness {
                DockLog.threadDetail.notice("thread detail load finished live host_id=\(self.host.id, privacy: .public) thread_id=\(DockLog.publicID(self.row.threadID), privacy: .public) events=\(self.events.count, privacy: .public) duration_ms=\(DockLog.milliseconds(since: startedAt), privacy: .public)")
            }
        } catch {
            let message = message(from: error)
            state = .error(header, message)
            screenStore.setError(header: header, message: message)
            await reconciler.close()
            DockLog.threadDetail.error("thread detail load failed host_id=\(self.host.id, privacy: .public) thread_id=\(DockLog.publicID(self.row.threadID), privacy: .public) duration_ms=\(DockLog.milliseconds(since: startedAt), privacy: .public) error=\(DockLog.errorSummary(error), privacy: .public)")
        }
    }

    public func observeDockRowUpdate(_ updatedRow: DockRowViewModel) {
        guard updatedRow.id == row.id else {
            return
        }

        row = updatedRow
        header = ThreadDetailHeader(host: host, row: updatedRow)
        latestDockRowActivityMarker = DockRowActivityMarker(row: updatedRow)

        if case .loaded = state {
            publishLoaded()
        }

        guard latestDockRowActivityMarker.isNewer(than: lastCompletedDockRowRefreshMarker) else {
            return
        }

        lastCompletedDockRowRefreshMarker = latestDockRowActivityMarker
        Task { [weak self] in
            await self?.reconciler?.manualRefresh()
        }
    }

    public func close() {
        DockLog.threadDetail.notice("thread detail close requested host_id=\(self.host.id, privacy: .public) thread_id=\(DockLog.publicID(self.row.threadID), privacy: .public)")
        isClosing = true
        reconcilerTask?.cancel()
        reconcilerTask = nil
        connectionTask?.cancel()
        connectionTask = nil
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

        let reconciler = reconciler
        self.reconciler = nil
        session = nil
        Task {
            await activeVoiceCaptureSession?.cancel()
            await activeTranscriptionSession?.cancel()
            await reconciler?.close()
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
            DockLog.threadDetail.warning("send draft skipped reason=no_session thread_id=\(DockLog.publicID(self.row.threadID), privacy: .public)")
            return
        }
        guard !composer.voice.phase.isBusy else {
            composer.lastError = "Finish dictation before sending."
            DockLog.threadDetail.warning("send draft skipped reason=voice_busy thread_id=\(DockLog.publicID(self.row.threadID), privacy: .public)")
            return
        }

        let text = composer.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            DockLog.threadDetail.debug("send draft skipped reason=empty thread_id=\(DockLog.publicID(self.row.threadID), privacy: .public)")
            return
        }

        let startedAt = Date()
        DockLog.threadDetail.notice("send draft started thread_id=\(DockLog.publicID(self.row.threadID), privacy: .public) characters=\(text.count, privacy: .public) active_turn=\((self.activeTurnID != nil), privacy: .public)")
        composer.isSending = true
        composer.lastError = nil

        do {
            // Projection v1 does not create Swift-side optimistic rows. Visible
            // outbound rows must come from relay projection updates, otherwise
            // pending and canonical identities can split into duplicates.
            let nextTurnID = try await commandEngine.sendDraft(
                text,
                threadID: row.threadID,
                activeTurnID: activeTurnID,
                session: session
            )
            activeTurnID = nextTurnID ?? activeTurnID
            composer.draft = ""
            composer.isSending = false
            await reconciler?.commandCompletedInvalidation()
            DockLog.threadDetail.notice("send draft finished thread_id=\(DockLog.publicID(self.row.threadID), privacy: .public) duration_ms=\(DockLog.milliseconds(since: startedAt), privacy: .public) active_turn_id=\(DockLog.publicID(self.activeTurnID), privacy: .public)")
        } catch {
            composer.isSending = false
            composer.lastError = message(from: error)
            DockLog.threadDetail.error("send draft failed thread_id=\(DockLog.publicID(self.row.threadID), privacy: .public) duration_ms=\(DockLog.milliseconds(since: startedAt), privacy: .public) error=\(DockLog.errorSummary(error), privacy: .public)")
        }
    }

    public func updateRequestCardInput(cardID: String, draft: String) {
        guard requestCardPresentation.updateInput(
            projectionID: cardID,
            draft: draft,
            in: events
        ) else {
            return
        }
        publishCurrentRenderState()
    }

    public func respond(to cardID: String, action: ServerRequestCardAction) async {
        guard let session else {
            setCardStatus(cardID: cardID, status: .failed("Thread is not connected."))
            DockLog.threadDetail.warning("request card response skipped reason=no_session card_id=\(DockLog.publicID(cardID), privacy: .public)")
            return
        }
        guard let card = requestCardPresentation.card(for: cardID, in: events) else {
            return
        }
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
            await reconciler?.commandCompletedInvalidation()
            DockLog.threadDetail.notice("request card response finished card_id=\(DockLog.publicID(cardID), privacy: .public) duration_ms=\(DockLog.milliseconds(since: startedAt), privacy: .public)")
        } catch {
            setCardStatus(cardID: cardID, status: .failed(message(from: error)))
            DockLog.threadDetail.error("request card response failed card_id=\(DockLog.publicID(cardID), privacy: .public) duration_ms=\(DockLog.milliseconds(since: startedAt), privacy: .public) error=\(DockLog.errorSummary(error), privacy: .public)")
        }
    }

    private func startReconcilerObservation(_ reconciler: StreamReconciler<ThreadDetailEventDTO>) async {
        reconcilerTask?.cancel()
        let snapshots = await reconciler.snapshots()
        reconcilerTask = Task { [weak self] in
            for await snapshot in snapshots {
                await self?.handle(reconcilerSnapshot: snapshot)
            }
        }
    }

    private func handle(reconcilerSnapshot snapshot: StreamReconcilerSnapshot<ThreadDetailEventDTO>) async {
        do {
            try applyProjectionSnapshot(snapshot, failEmptyFailure: false)
        } catch {
            let message = message(from: error)
            liveState = .stale(message)
            publishLoaded()
        }
    }

    private func startObservation(
        session: any ThreadDetailSession,
        reconciler: StreamReconciler<ThreadDetailEventDTO>
    ) {
        connectionTask?.cancel()
        connectionTask = Task { [weak self] in
            for await state in session.connectionStates {
                await self?.handle(connectionState: state, reconciler: reconciler)
            }
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

        if composer.voice.phase.isBusy {
            DockLog.voice.notice("voice capture stopping reason=backgrounded thread_id=\(DockLog.publicID(self.row.threadID), privacy: .public)")
            let activeTranscriptionSession = activeTranscriptionSession
            await cancelActiveVoiceCapture()
            failActiveDictation(message: "Dictation stopped because the app moved to the background.")
            await activeTranscriptionSession?.cancel()
        }

        guard case .loaded = state, liveState != .closed else {
            return
        }

        await reconciler?.staleDeadlineExceeded("Backgrounded")
        DockLog.threadDetail.notice("thread detail marked stale reason=backgrounded thread_id=\(DockLog.publicID(self.row.threadID), privacy: .public)")
    }

    private func handleForegroundResuming(_ snapshot: AppLifecycleSnapshot) async {
        guard handledForegroundResumeGeneration != snapshot.resumeGeneration else {
            return
        }
        handledForegroundResumeGeneration = snapshot.resumeGeneration

        guard !isClosing,
              case .loaded = state,
              liveState != .closed else {
            return
        }

        if latestConnectionState == .connected {
            await reconciler?.foregroundResumed()
        } else if latestConnectionState.shouldWaitForForegroundRehydrate {
            await reconciler?.transportReconnecting("Resuming")
        } else {
            await reconciler?.transportDisconnected(message(from: latestConnectionState))
        }
    }

    private func handle(
        connectionState: AppServerConnectionState,
        reconciler: StreamReconciler<ThreadDetailEventDTO>
    ) async {
        let previousConnectionState = latestConnectionState
        latestConnectionState = connectionState
        DockLog.threadDetail.debug("thread detail connection state=\(connectionState.logDescription, privacy: .public) thread_id=\(DockLog.publicID(self.row.threadID), privacy: .public)")
        switch connectionState {
        case .reconnecting(_, let reason):
            await reconciler.transportReconnecting(reason)
        case .connected:
            if previousConnectionState.shouldTriggerProjectionCatchupAfterConnected {
                await reconciler.transportReconnected()
            }
        case .offline(let reason):
            await reconciler.transportDisconnected(reason)
        case .error(let message):
            await reconciler.transportDisconnected(message)
        case .closed(let reason):
            await reconciler.transportDisconnected(reason)
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

    private func applyProjectionSnapshot(
        _ projectionSnapshot: StreamReconcilerSnapshot<ThreadDetailEventDTO>,
        failEmptyFailure: Bool
    ) throws {
        if failEmptyFailure,
           projectionSnapshot.rows.isEmpty,
           case .failed(let message) = projectionSnapshot.freshness {
            throw ThreadDetailStoreError.invalidProjectionEnvelope(message)
        }

        let nextEvents = ThreadEventDisplayOrder.newestFirst(
            projectionSnapshot.rows.map(ThreadEvent.init(detailEvent:))
        )
        events = nextEvents
        activeTurnID = projectionSnapshot.activeTurnID
        requestCardPresentation.prune(to: nextEvents)
        liveState = ThreadDetailLiveState(projectionSnapshot: projectionSnapshot)
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
        screenStore.publish(snapshot: snapshot, requestCardPresentation: requestCardPresentation)
        publishConnectivity(liveState: liveState)
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
        guard requestCardPresentation.setStatus(
            projectionID: cardID,
            status: status,
            in: events
        ) else {
            return
        }
        publishCurrentRenderState()
    }

    private func publishCurrentRenderState() {
        guard case .loaded(let snapshot) = state else {
            return
        }
        screenStore.publish(snapshot: snapshot, requestCardPresentation: requestCardPresentation)
    }

    private func message(from error: Error) -> String {
        if let message = ThreadDetailHumanOnlyRejection.message(for: error) {
            return message
        }
        if let message = ThreadDetailHumanOnlyRejection.message(forErrorDescription: error.localizedDescription) {
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

    var shouldTriggerProjectionCatchupAfterConnected: Bool {
        switch self {
        case .reconnecting, .offline, .error, .closed:
            return true
        case .idle, .connecting, .connected:
            return false
        }
    }
}

private extension ThreadDetailLiveState {
    init(projectionSnapshot: StreamReconcilerSnapshot<ThreadDetailEventDTO>) {
        switch projectionSnapshot.freshness {
        case .connecting, .subscribing:
            self = .connecting
        case .live:
            self = .live
        case .catchingUp(let reason):
            self = .reconnecting(projectionSnapshot.lastError ?? reason.rawValue)
        case .stale(let message), .offline(let message), .failed(let message):
            self = .stale(message)
        case .closed:
            self = .closed
        }
    }

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
    case invalidProjectionEnvelope(String)
    case projectionEpochMismatch(expected: String, actual: String)
    case projectionSequenceGap(expected: Int64, actual: Int64)
    case projectionResyncRequired(String)

    public var errorDescription: String? {
        switch self {
        case let .threadMismatch(expected, actual):
            return "App-server returned thread \(actual), expected \(expected)."
        case let .repeatedTurnsCursor(cursor):
            return "App-server returned repeated thread turns cursor \(cursor)."
        case let .invalidProjectionEnvelope(message):
            return message
        case let .projectionEpochMismatch(expected, actual):
            return "Thread Detail projection epoch changed from \(expected) to \(actual)."
        case let .projectionSequenceGap(expected, actual):
            return "Thread Detail projection sequence gap: expected \(expected), got \(actual)."
        case let .projectionResyncRequired(reason):
            return reason
        }
    }
}

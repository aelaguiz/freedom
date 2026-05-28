import Combine
import Foundation

public protocol ThreadDetailSession: Sendable {
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

public struct ComposerState: Equatable, Sendable {
    public var draft: String
    public var isSending: Bool
    public var lastError: String?
    public var voice: ComposerVoiceState

    public init(
        draft: String = "",
        isSending: Bool = false,
        lastError: String? = nil,
        voice: ComposerVoiceState = ComposerVoiceState()
    ) {
        self.draft = draft
        self.isSending = isSending
        self.lastError = lastError
        self.voice = voice
    }

    public var canSend: Bool {
        !isSending
            && !voice.phase.isBusy
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public enum ComposerVoicePhase: Equatable, Sendable {
    case idle
    case recording
    case transcribing

    public var isBusy: Bool {
        self == .recording || self == .transcribing
    }

    public var label: String {
        switch self {
        case .idle:
            return "Dictate"
        case .recording:
            return "Recording"
        case .transcribing:
            return "Transcribing"
        }
    }
}

public struct ComposerVoiceState: Equatable, Sendable {
    public var phase: ComposerVoicePhase
    public var lastError: String?

    public init(phase: ComposerVoicePhase = .idle, lastError: String? = nil) {
        self.phase = phase
        self.lastError = lastError
    }
}

@MainActor
public final class ThreadDetailStore: ObservableObject {
    @Published public private(set) var state: ThreadDetailStoreState
    @Published public private(set) var composer = ComposerState()
    @Published public private(set) var requestCards: [ServerRequestCard] = []

    private let host: DockHostConfiguration
    private let row: DockRowViewModel
    private let header: ThreadDetailHeader
    private let factory: any ThreadDetailSessionMaking
    private let voiceCapture: any VoiceCaptureControlling
    private let transcriptionService: any TranscriptionServicing
    private let now: @Sendable () -> Date

    private var session: (any ThreadDetailSession)?
    private var notificationTask: Task<Void, Never>?
    private var requestTask: Task<Void, Never>?
    private var events: [ThreadEvent] = []
    private var liveState: ThreadDetailLiveState = .connecting
    private var activeTurnID: String?
    private var didLoad = false

    public init(
        host: DockHostConfiguration,
        row: DockRowViewModel,
        factory: any ThreadDetailSessionMaking = AppServerThreadDetailSessionFactory(),
        voiceCapture: any VoiceCaptureControlling = VoiceCaptureController(),
        transcriptionService: any TranscriptionServicing = OpenAITranscriptionClient(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.host = host
        self.row = row
        self.header = ThreadDetailHeader(host: host, row: row)
        self.factory = factory
        self.voiceCapture = voiceCapture
        self.transcriptionService = transcriptionService
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
                params: ThreadReadParams(threadId: row.id.threadID, includeTurns: false),
                timeout: .seconds(10)
            )
            let turnsResponse = try await session.threadTurnsList(
                params: ThreadTurnsListParams(threadId: row.id.threadID, limit: 10),
                timeout: .seconds(10)
            )
            let readThread = readResponse.thread.replacingTurns(turnsResponse.data)
            try replaceEvents(from: readThread, liveState: .connecting)

            do {
                let resumeResponse = try await session.threadResume(
                    params: ThreadResumeParams(threadId: row.id.threadID, excludeTurns: true),
                    timeout: .seconds(10)
                )
                let liveThread = resumeResponse.thread.replacingTurns(turnsResponse.data)
                try replaceEvents(from: liveThread, liveState: .live)
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

    public func updateDraft(_ draft: String) {
        composer.draft = draft
        composer.lastError = nil
    }

    public func beginVoiceCapture() async {
        guard !composer.isSending, !composer.voice.phase.isBusy else {
            return
        }

        composer.voice = ComposerVoiceState(phase: .recording)

        do {
            _ = try await voiceCapture.startRecording()
        } catch {
            composer.voice = ComposerVoiceState(phase: .idle, lastError: voiceMessage(from: error))
        }
    }

    public func finishVoiceCapture() async {
        guard composer.voice.phase == .recording else {
            return
        }

        composer.voice = ComposerVoiceState(phase: .transcribing)

        do {
            let audioFile = try await voiceCapture.stopRecording()
            defer {
                try? FileManager.default.removeItem(at: audioFile)
            }
            let transcript = try await transcriptionService.transcribe(audioFile: audioFile)
            try insertTranscript(transcript)
            composer.voice = ComposerVoiceState()
        } catch {
            composer.voice = ComposerVoiceState(phase: .idle, lastError: voiceMessage(from: error))
        }
    }

    public func cancelVoiceCapture() async {
        await voiceCapture.cancelRecording()
        composer.voice = ComposerVoiceState()
    }

    private func insertTranscript(_ transcript: String) throws {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TranscriptionServiceError.emptyTranscript
        }

        let existing = composer.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if existing.isEmpty {
            composer.draft = trimmed
        } else {
            composer.draft = "\(existing) \(trimmed)"
        }
        composer.lastError = nil
    }

    public func sendDraft() async {
        guard let session else {
            composer.lastError = "Thread is not connected."
            return
        }
        guard !composer.voice.phase.isBusy else {
            composer.lastError = "Finish dictation before sending."
            return
        }

        let text = composer.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return
        }

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
        } catch {
            composer.isSending = false
            composer.lastError = message(from: error)
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
        do {
            try await session.sendResponse(id: card.requestID, result: payload)
            setCardStatus(cardID: cardID, status: .resolved)
        } catch {
            setCardStatus(cardID: cardID, status: .failed(message(from: error)))
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

    private func voiceMessage(from error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }
        return "Voice input failed."
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

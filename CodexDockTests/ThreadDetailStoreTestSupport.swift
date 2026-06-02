import XCTest
@testable import CodexDock

struct FakeThreadDetailSessionFactory: ThreadDetailSessionMaking {
    let session: FakeThreadDetailSession

    func makeSession(for host: DockHostConfiguration) -> any ThreadDetailSession {
        session
    }
}

final class FakeThreadDetailSession: @unchecked Sendable, ThreadDetailSession {
    let connectionStates: AsyncStream<AppServerConnectionState>
    let notifications: AsyncStream<JSONRPCNotification>
    let serverRequests: AsyncStream<JSONRPCRequest>

    private let connectionStateContinuation: AsyncStream<AppServerConnectionState>.Continuation
    private let notificationContinuation: AsyncStream<JSONRPCNotification>.Continuation
    private let serverRequestContinuation: AsyncStream<JSONRPCRequest>.Continuation
    private var readResults: [Result<ThreadReadResponseDTO, any Error>]
    private var turnsListResults: [Result<ThreadTurnsListResponseDTO, any Error>]
    private var resumeResults: [Result<ThreadResumeResponseDTO, any Error>]
    private var detailSubscribeResults: [Result<ThreadDetailSnapshotDTO, any Error>]?
    private var detailResyncResults: [Result<ThreadDetailSnapshotDTO, any Error>]?
    private let turnStartResult: Result<TurnStartResponseDTO, any Error>
    private let turnSteerResult: Result<TurnSteerResponseDTO, any Error>
    private let resumeDelay: Duration?
    private var readParams: [ThreadReadParams] = []
    private var turnsListParams: [ThreadTurnsListParams] = []
    private var resumeParams: [ThreadResumeParams] = []
    private var detailSubscribeParams: [ThreadDetailParams] = []
    private var detailResyncParams: [ThreadDetailParams] = []
    private var turnStartParams: [TurnStartParams] = []
    private var turnSteerParams: [TurnSteerParams] = []
    private var sentResponses: [SentServerResponse] = []
    private var detailEventsByID: [String: ThreadEvent] = [:]
    private var detailRevisionsByID: [String: Int] = [:]
    private var detailActiveTurnID: String?
    private let detailSourceHostID: String
    private let detailEpoch = "test-epoch"
    private var detailSeq: Int64 = 0

    init(
        readResult: Result<ThreadReadResponseDTO, any Error>,
        turnsListResult: Result<ThreadTurnsListResponseDTO, any Error> = .success(
            ThreadTurnsListResponseDTO(data: [])
        ),
        resumeResult: Result<ThreadResumeResponseDTO, any Error>,
        turnStartResult: Result<TurnStartResponseDTO, any Error> = .success(
            TurnStartResponseDTO(
                turn: .object([
                    "id": .string("turn-started"),
                    "status": .string("inProgress"),
                ])
            )
        ),
        turnSteerResult: Result<TurnSteerResponseDTO, any Error> = .success(
            TurnSteerResponseDTO(turnId: "turn-started")
        ),
        resumeDelay: Duration? = nil,
        readResults: [Result<ThreadReadResponseDTO, any Error>]? = nil,
        turnsListResults: [Result<ThreadTurnsListResponseDTO, any Error>]? = nil,
        resumeResults: [Result<ThreadResumeResponseDTO, any Error>]? = nil,
        detailSubscribeResults: [Result<ThreadDetailSnapshotDTO, any Error>]? = nil,
        detailResyncResults: [Result<ThreadDetailSnapshotDTO, any Error>]? = nil,
        detailSourceHostID: String = "test-host"
    ) {
        let connectionStates = AsyncStream.makeStream(of: AppServerConnectionState.self)
        let notifications = AsyncStream.makeStream(of: JSONRPCNotification.self)
        let serverRequests = AsyncStream.makeStream(of: JSONRPCRequest.self)
        self.connectionStates = connectionStates.stream
        self.connectionStateContinuation = connectionStates.continuation
        self.notifications = notifications.stream
        self.notificationContinuation = notifications.continuation
        self.serverRequests = serverRequests.stream
        self.serverRequestContinuation = serverRequests.continuation
        self.readResults = readResults ?? [readResult]
        self.turnsListResults = turnsListResults ?? [turnsListResult]
        self.resumeResults = resumeResults ?? [resumeResult]
        self.detailSubscribeResults = detailSubscribeResults
        self.detailResyncResults = detailResyncResults
        self.detailSourceHostID = detailSourceHostID
        self.turnStartResult = turnStartResult
        self.turnSteerResult = turnSteerResult
        self.resumeDelay = resumeDelay
    }

    func connectAndInitialize(
        params: InitializeParams,
        timeout: Duration
    ) async throws -> InitializeResponse {
        connectionStateContinuation.yield(.connecting)
        connectionStateContinuation.yield(.connected)
        return InitializeResponse(
            userAgent: "fake-codex",
            codexHome: "/Users/aelaguiz/.codex",
            platformFamily: "unix",
            platformOs: "macos"
        )
    }

    func threadRead(
        params: ThreadReadParams,
        timeout: Duration
    ) async throws -> ThreadReadResponseDTO {
        readParams.append(params)
        let result = readResults.count > 1 ? readResults.removeFirst() : readResults[0]
        return try result.get()
    }

    func threadTurnsList(
        params: ThreadTurnsListParams,
        timeout: Duration
    ) async throws -> ThreadTurnsListResponseDTO {
        turnsListParams.append(params)
        let result = turnsListResults.count > 1 ? turnsListResults.removeFirst() : turnsListResults[0]
        return try result.get()
    }

    func threadResume(
        params: ThreadResumeParams,
        timeout: Duration
    ) async throws -> ThreadResumeResponseDTO {
        resumeParams.append(params)
        if let resumeDelay {
            try await Task.sleep(for: resumeDelay)
        }
        let result = resumeResults.count > 1 ? resumeResults.removeFirst() : resumeResults[0]
        return try result.get()
    }

    func threadDetailSubscribe(
        params: ThreadDetailParams,
        timeout: Duration
    ) async throws -> ThreadDetailSnapshotDTO {
        detailSubscribeParams.append(params)
        if var results = detailSubscribeResults {
            let result = results.count > 1 ? results.removeFirst() : results[0]
            detailSubscribeResults = results
            return try result.get()
        }
        if let resumeDelay {
            try await Task.sleep(for: resumeDelay)
        }
        let resumeResult = resumeResults.count > 1 ? resumeResults.removeFirst() : resumeResults[0]
        _ = try resumeResult.get()
        return try makeNextDetailSnapshot(threadID: params.threadId, preservingLiveEvents: true)
    }

    func threadDetailResync(
        params: ThreadDetailParams,
        timeout: Duration
    ) async throws -> ThreadDetailSnapshotDTO {
        detailResyncParams.append(params)
        if var results = detailResyncResults {
            let result = results.count > 1 ? results.removeFirst() : results[0]
            detailResyncResults = results
            return try result.get()
        }
        if let resumeDelay {
            try await Task.sleep(for: resumeDelay)
        }
        return try makeNextDetailSnapshot(threadID: params.threadId, preservingLiveEvents: true)
    }

    func turnStart(
        params: TurnStartParams,
        timeout: Duration
    ) async throws -> TurnStartResponseDTO {
        turnStartParams.append(params)
        return try turnStartResult.get()
    }

    func turnSteer(
        params: TurnSteerParams,
        timeout: Duration
    ) async throws -> TurnSteerResponseDTO {
        turnSteerParams.append(params)
        return try turnSteerResult.get()
    }

    func sendResponse(id: JSONRPCRequestID, result: JSONValue) async throws {
        sentResponses.append(SentServerResponse(id: id, result: result))
    }

    func disconnect() async {
        connectionStateContinuation.yield(.closed(reason: "client disconnected"))
        connectionStateContinuation.finish()
        notificationContinuation.finish()
        serverRequestContinuation.finish()
    }

    func emitConnectionState(_ state: AppServerConnectionState) async {
        connectionStateContinuation.yield(state)
    }

    func emitNotification(_ notification: JSONRPCNotification) async {
        guard let update = applyDetail(notification: notification) else {
            return
        }
        notificationContinuation.yield(
            JSONRPCNotification(
                method: AppServerMethods.threadDetailUpdate,
                params: try? JSONValue.encoded(update)
            )
        )
    }

    func emitServerRequest(_ request: JSONRPCRequest) async {
        guard let update = applyDetail(request: request) else {
            return
        }
        notificationContinuation.yield(
            JSONRPCNotification(
                method: AppServerMethods.threadDetailUpdate,
                params: try? JSONValue.encoded(update)
            )
        )
    }

    func finishNotifications() async {
        notificationContinuation.finish()
    }

    func finishServerRequests() async {
        serverRequestContinuation.finish()
    }

    func finishConnectionStates() async {
        connectionStateContinuation.finish()
    }

    func readParamsSnapshot() -> [ThreadReadParams] {
        readParams
    }

    func turnsListParamsSnapshot() -> [ThreadTurnsListParams] {
        turnsListParams
    }

    func resumeParamsSnapshot() -> [ThreadResumeParams] {
        resumeParams
    }

    func detailSubscribeParamsSnapshot() -> [ThreadDetailParams] {
        detailSubscribeParams
    }

    func detailResyncParamsSnapshot() -> [ThreadDetailParams] {
        detailResyncParams
    }

    func turnStartParamsSnapshot() -> [TurnStartParams] {
        turnStartParams
    }

    func turnSteerParamsSnapshot() -> [TurnSteerParams] {
        turnSteerParams
    }

    func sentResponsesSnapshot() -> [SentServerResponse] {
        sentResponses
    }

    private func makeNextDetailSnapshot(
        threadID: String,
        preservingLiveEvents: Bool
    ) throws -> ThreadDetailSnapshotDTO {
        let preservedEvents = preservingLiveEvents
            ? detailEventsByID.values.filter { $0.isLive || $0.request != nil }
            : []
        let readResult = readResults.count > 1 ? readResults.removeFirst() : readResults[0]
        let read = try readResult.get()
        let turns = try drainNextTurnsPageSet()
        var snapshot = Self.detailSnapshot(
            thread: read.thread.replacingTurns(turns),
            threadID: read.thread.id ?? threadID,
            sourceHostID: detailSourceHostID,
            epoch: detailEpoch,
            seq: nextDetailSeq()
        )
        let existingIDs = Set(snapshot.events.map(\.projectionID))
        let preservedDTOs = preservedEvents
            .filter { !existingIDs.contains($0.id) }
            .enumerated()
            .map { offset, event in
                Self.detailEventDTO(
                    from: event,
                    threadID: read.thread.id ?? threadID,
                    sourceHostID: detailSourceHostID,
                    index: snapshot.events.count + offset,
                    revision: detailRevisionsByID[event.id] ?? 1
                )
            }
        if !preservedDTOs.isEmpty {
            snapshot = ThreadDetailSnapshotDTO(
                sourceHostID: snapshot.sourceHostID,
                threadID: snapshot.threadID,
                epoch: snapshot.epoch,
                seq: snapshot.seq,
                viewParamsKey: snapshot.viewParamsKey,
                activeTurnID: snapshot.activeTurnID,
                order: snapshot.order,
                rows: snapshot.events + preservedDTOs
            )
        }
        detailEventsByID = Dictionary(uniqueKeysWithValues: snapshot.events.map {
            (ThreadEvent(detailEvent: $0).id, ThreadEvent(detailEvent: $0))
        })
        detailRevisionsByID = Dictionary(uniqueKeysWithValues: snapshot.events.map {
            ($0.projectionID, $0.revision)
        })
        detailActiveTurnID = snapshot.activeTurnID
        return snapshot
    }

    private func drainNextTurnsPageSet() throws -> [JSONValue] {
        var turns: [JSONValue] = []
        var seenCursors = Set<String>()
        while true {
            let result = turnsListResults.count > 1 ? turnsListResults.removeFirst() : turnsListResults[0]
            let response = try result.get()
            turns.append(contentsOf: response.data)
            guard let cursor = response.nextCursor, !cursor.isEmpty else {
                return turns
            }
            guard seenCursors.insert(cursor).inserted else {
                throw ThreadDetailStoreError.repeatedTurnsCursor(cursor)
            }
        }
    }

    private func applyDetail(notification: JSONRPCNotification) -> ThreadDetailUpdateDTO? {
        if let eventThreadID = LegacyThreadEventFixtureNormalizer.threadId(from: notification),
           eventThreadID != detailThreadID() {
            return nil
        }
        if notification.method == "serverRequest/resolved",
           let requestID = notification.params?.objectValue?["requestId"] {
            let requestIDText = requestID.stringValue ?? requestID.numberValue.map { String(Int64($0)) }
            let projectionID = requestIDText.flatMap { requestProjectionID(requestID: $0, threadID: detailThreadID()) }
            if let projectionID, let event = detailEventsByID[projectionID], let request = event.request {
                let revision = (detailRevisionsByID[projectionID] ?? 1) + 1
                let next = ThreadEvent(
                    id: event.id,
                    kind: event.kind,
                    visibilityCategory: event.visibilityCategory,
                    title: event.title,
                    body: event.body,
                    date: event.date,
                    isLive: event.isLive,
                    turnID: event.turnID,
                    itemID: event.itemID,
                    turnSequence: event.turnSequence,
                    itemSequence: event.itemSequence,
                    eventSequence: event.eventSequence,
                    displayOrderKey: event.displayOrderKey,
                    displayGroupDate: event.displayGroupDate,
                    activityDate: event.activityDate,
                    isStreamingDelta: event.isStreamingDelta,
                    request: ThreadDetailEventRequestDTO(
                        requestID: request.requestID,
                        method: request.method,
                        params: request.params,
                        status: "resolved"
                    )
                )
                detailEventsByID[projectionID] = next
                detailRevisionsByID[projectionID] = revision
                return ThreadDetailUpdateDTO(
                    kind: .upsert,
                    sourceHostID: detailSourceHostID,
                    threadID: detailThreadID(),
                    epoch: detailEpoch,
                    seq: nextDetailSeq(),
                    viewParamsKey: "default-view",
                    order: "displayOrderKeyAscending",
                    rows: [
                        Self.detailEventDTO(
                            from: next,
                            threadID: detailThreadID(),
                            sourceHostID: detailSourceHostID,
                            index: detailEventsByID.count,
                            revision: revision
                        ),
                    ],
                    activeTurnID: detailActiveTurnID
                )
            }
            return ThreadDetailUpdateDTO(
                kind: .heartbeat,
                sourceHostID: detailSourceHostID,
                threadID: detailThreadID(),
                epoch: detailEpoch,
                seq: nextDetailSeq(),
                viewParamsKey: "default-view",
                order: "displayOrderKeyAscending",
                activeTurnID: detailActiveTurnID
            )
        }

        if notification.method == "turn/started" {
            detailActiveTurnID = notification.params?.objectValue?["turn"]?.objectValue?["id"]?.stringValue
        }
        if notification.method == "turn/completed",
           detailActiveTurnID == notification.params?.objectValue?["turn"]?.objectValue?["id"]?.stringValue {
            detailActiveTurnID = nil
        }
        guard let event = LegacyThreadEventFixtureNormalizer.event(from: notification) else {
            return nil
        }
        return upsertDetailEvent(event)
    }

    private func applyDetail(request: JSONRPCRequest) -> ThreadDetailUpdateDTO? {
        let event = LegacyThreadEventFixtureNormalizer.event(from: request)
        return upsertDetailEvent(event)
    }

    private func upsertDetailEvent(_ event: ThreadEvent) -> ThreadDetailUpdateDTO {
        let projected = ThreadEvent(detailEvent: Self.detailEventDTO(
            from: event,
            threadID: detailThreadID(),
            sourceHostID: detailSourceHostID,
            index: detailEventsByID.count
        ))
        var next = projected
        if let existing = detailEventsByID[projected.id],
           existing.isStreamingDelta,
           projected.isStreamingDelta,
           existing.kind == projected.kind {
            next = existing.mergingStreamingDelta(projected)
        }
        let revision = detailEventsByID[projected.id] == nil
            ? 1
            : (detailRevisionsByID[projected.id] ?? 1) + 1
        detailEventsByID[projected.id] = next
        detailRevisionsByID[projected.id] = revision
        return ThreadDetailUpdateDTO(
            kind: .upsert,
            sourceHostID: detailSourceHostID,
            threadID: detailThreadID(),
            epoch: detailEpoch,
            seq: nextDetailSeq(),
            viewParamsKey: "default-view",
            order: "displayOrderKeyAscending",
            rows: [
                Self.detailEventDTO(
                    from: next,
                    threadID: detailThreadID(),
                    sourceHostID: detailSourceHostID,
                    index: detailEventsByID.count,
                    revision: revision
                ),
            ],
            activeTurnID: detailActiveTurnID,
            liveState: event.title == "Thread closed" ? "closed" : nil
        )
    }

    private func detailThreadID() -> String {
        detailSubscribeParams.last?.threadId
            ?? detailResyncParams.last?.threadId
            ?? "thread-1"
    }

    private func nextDetailSeq() -> Int64 {
        detailSeq += 1
        return detailSeq
    }

    private func requestProjectionID(requestID: String, threadID: String) -> String? {
        detailEventsByID.values.first { event in
            event.request?.requestID.description == requestID
        }?.id ?? "host:\(detailSourceHostID)/thread:\(threadID)/request:\(requestID)/row:request"
    }

    private static func detailSnapshot(
        thread: ThreadDTO,
        threadID: String,
        sourceHostID: String,
        epoch: String,
        seq: Int64
    ) -> ThreadDetailSnapshotDTO {
        let events = LegacyThreadEventFixtureNormalizer.events(from: thread).enumerated().map { index, event in
            detailEventDTO(from: event, threadID: threadID, sourceHostID: sourceHostID, index: index)
        }
        return ThreadDetailSnapshotDTO(
            sourceHostID: sourceHostID,
            threadID: threadID,
            epoch: epoch,
            seq: seq,
            viewParamsKey: "default-view",
            activeTurnID: thread.turns?
                .compactMap { turn -> String? in
                    guard turn.objectValue?["status"]?.stringValue == "inProgress" else {
                        return nil
                    }
                    return turn.objectValue?["id"]?.stringValue
                }
                .first,
            order: "displayOrderKeyAscending",
            rows: events
        )
    }

    private static func detailEventDTO(
        from event: ThreadEvent,
        threadID: String,
        sourceHostID: String,
        index: Int,
        revision: Int = 1
    ) -> ThreadDetailEventDTO {
        let rowRole = rowRole(for: event)
        let projectionID = projectionID(for: event, threadID: threadID, sourceHostID: sourceHostID, rowRole: rowRole)
        let sourceRef = sourceRef(for: event, projectionID: projectionID, rowRole: rowRole)
        let activityDate = event.activityDate ?? event.date
        return ThreadDetailEventDTO(
            sourceHostID: sourceHostID,
            threadID: threadID,
            projectionID: projectionID,
            sourceRef: sourceRef,
            itemType: event.kind.rawValue,
            rowRole: rowRole,
            visibility: event.visibilityCategory,
            renderKind: event.kind,
            displayOrderKey: event.displayOrderKey,
            title: event.title,
            body: event.body,
            eventTime: activityDate.map(isoString),
            activityTime: activityDate.map(isoString),
            turnID: event.turnID,
            itemID: event.itemID,
            turnOrder: event.turnSequence,
            itemOrder: event.itemSequence,
            rowOrder: event.eventSequence,
            revision: revision,
            renderState: event.isStreamingDelta ? .streaming : (event.isLive ? .live : .settled),
            requestID: event.request?.requestID.description,
            request: event.request
        )
    }

    private static func rowRole(for event: ThreadEvent) -> String {
        switch event.kind {
        case .userMessage:
            return "userMessage"
        case .agentMessage:
            return event.visibilityCategory == .thinking ? "reasoning" : "agentMessage"
        case .command:
            return "command"
        case .output:
            return "commandOutput"
        case .request:
            return "request"
        case .system:
            return "system"
        case .unknown:
            return "unknown"
        }
    }

    private static func projectionID(
        for event: ThreadEvent,
        threadID: String,
        sourceHostID: String,
        rowRole: String
    ) -> String {
        if event.id.hasPrefix("host:") {
            return event.id
        }
        if rowRole == "request", let requestID = event.request?.requestID.description {
            return "host:\(sourceHostID)/thread:\(threadID)/request:\(requestID)/row:request"
        }
        if let turnID = event.turnID, let itemID = event.itemID {
            return "host:\(sourceHostID)/thread:\(threadID)/turn:\(turnID)/item:\(itemID)/row:\(rowRole)"
        }
        return "host:\(sourceHostID)/thread:\(threadID)/diagnostic:\(event.id)/row:\(rowRole)"
    }

    private static func sourceRef(for event: ThreadEvent, projectionID: String, rowRole: String) -> String {
        if let suffixRange = projectionID.range(of: "/row:\(rowRole)", options: .backwards) {
            return String(projectionID[..<suffixRange.lowerBound])
        }
        return event.id
    }

    private static func isoString(from date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

}

final class FakeRealtimeTranscriptionService: @unchecked Sendable, RealtimeTranscriptionServicing {
    private(set) var sessions: [FakeRealtimeTranscriptionSession]
    private let startResult: Result<Void, TranscriptionServiceError>
    var startDelay: Duration?
    private(set) var startCount = 0

    var session: FakeRealtimeTranscriptionSession {
        sessions[0]
    }

    init(
        session: FakeRealtimeTranscriptionSession = FakeRealtimeTranscriptionSession(),
        startResult: Result<Void, TranscriptionServiceError> = .success(()),
        startDelay: Duration? = nil
    ) {
        self.sessions = [session]
        self.startResult = startResult
        self.startDelay = startDelay
    }

    func startSession() async throws -> any RealtimeTranscriptionSession {
        let sessionIndex = startCount
        startCount += 1
        if let startDelay {
            try await Task.sleep(for: startDelay)
        }
        try startResult.get()
        // A real realtime start returns a fresh event stream. Reusing a closed
        // fake stream makes multi-start voice tests timing-dependent.
        if sessionIndex >= sessions.count {
            sessions.append(FakeRealtimeTranscriptionSession(id: "fake-transcription-session-\(sessionIndex + 1)"))
        }
        let nextSession = sessions[sessionIndex]
        nextSession.emit(.started(sessionID: nextSession.id))
        return nextSession
    }
}

final class FakeRealtimeTranscriptionSession: @unchecked Sendable, RealtimeTranscriptionSession {
    let id: String
    let events: AsyncStream<RealtimeTranscriptionEvent>

    private let continuation: AsyncStream<RealtimeTranscriptionEvent>.Continuation
    private(set) var commitCount = 0
    private(set) var cancelCount = 0
    private(set) var appendedChunks: [(chunk: Data, sequence: Int)] = []
    var eventsOnCommit: [RealtimeTranscriptionEvent] = []
    var commitError: TranscriptionServiceError?
    var commitDelay: Duration?

    init(id: String = "fake-transcription-session") {
        self.id = id
        let stream = AsyncStream.makeStream(of: RealtimeTranscriptionEvent.self)
        self.events = stream.stream
        self.continuation = stream.continuation
    }

    func appendAudio(_ chunk: Data, sequence: Int) async throws {
        appendedChunks.append((chunk: chunk, sequence: sequence))
    }

    func commit() async throws {
        commitCount += 1
        if let commitDelay {
            try? await Task.sleep(for: commitDelay)
        }
        if let commitError {
            throw commitError
        }
        for event in eventsOnCommit {
            emit(event)
        }
        continuation.finish()
    }

    func cancel() async {
        cancelCount += 1
        emit(.canceled(sessionID: id))
        emit(.closed(sessionID: id))
        continuation.finish()
    }

    func emit(_ event: RealtimeTranscriptionEvent) {
        continuation.yield(event)
    }

    func finish() {
        continuation.finish()
    }
}

final class FakeLiveVoiceCaptureController: @unchecked Sendable, LiveVoiceCaptureControlling {
    private(set) var sessions: [FakeLiveVoiceCaptureSession]
    private let startResult: Result<Void, VoiceCaptureError>
    private(set) var startCount = 0

    var session: FakeLiveVoiceCaptureSession {
        sessions[0]
    }

    init(
        session: FakeLiveVoiceCaptureSession = FakeLiveVoiceCaptureSession(),
        startResult: Result<Void, VoiceCaptureError> = .success(())
    ) {
        self.sessions = [session]
        self.startResult = startResult
    }

    func startCapture() async throws -> any LiveVoiceCaptureSession {
        try startResult.get()
        if startCount >= sessions.count {
            sessions.append(FakeLiveVoiceCaptureSession())
        }
        let nextSession = sessions[startCount]
        startCount += 1
        return nextSession
    }
}

final class FakeLiveVoiceCaptureSession: @unchecked Sendable, LiveVoiceCaptureSession {
    let chunks: AsyncStream<VoiceAudioChunk>

    private let continuation: AsyncStream<VoiceAudioChunk>.Continuation
    private(set) var stopCount = 0
    private(set) var cancelCount = 0

    init() {
        let stream = AsyncStream.makeStream(of: VoiceAudioChunk.self)
        self.chunks = stream.stream
        self.continuation = stream.continuation
    }

    func emit(_ chunk: VoiceAudioChunk) {
        continuation.yield(chunk)
    }

    func finishChunks() {
        continuation.finish()
    }

    func stop() async {
        stopCount += 1
        continuation.finish()
    }

    func cancel() async {
        cancelCount += 1
        continuation.finish()
    }
}

enum FakeThreadDetailError: Error, LocalizedError, Sendable {
    case resumeFailed
    case turnFailed

    var errorDescription: String? {
        switch self {
        case .resumeFailed:
            return "resume failed"
        case .turnFailed:
            return "turn failed"
        }
    }
}

struct SentServerResponse: Equatable, Sendable {
    let id: JSONRPCRequestID
    let result: JSONValue
}

func makeDetailHost() -> DockHostConfiguration {
    try! DockHostConfiguration(host: "192.168.50.117", port: 4510)
}

func makeDetailRow(
    hostID: String,
    threadID: String,
    sourceHostID: String? = nil,
    status: DockRowStatusKind = .running,
    relationship: DockRowThreadRelationship = .root,
    lastActivity: String = "now",
    lastActivityDate: Date = Date(timeIntervalSince1970: 2_000),
    displayOrderKey: String? = nil
) -> DockRowViewModel {
    let projectionID = "host:\(sourceHostID ?? hostID)/thread:\(threadID)/row:threadCard"
    let resolvedDisplayOrderKey = displayOrderKey ?? "9999999998000000|0001|\(projectionID)"
    return DockRowViewModel(
        threadIdentity: HostScopedThreadID(hostID: hostID, threadID: threadID),
        sourceHostID: sourceHostID,
        projectionID: projectionID,
        backendSessionID: "\(threadID)-session",
        title: "Build live detail",
        hostDisplayName: "Test host",
        hostEndpoint: "\(hostID):4510",
        repository: "codex-client",
        branch: "main",
        status: status,
        lastActivity: lastActivity,
        lastActivityDate: lastActivityDate,
        displayOrderKey: resolvedDisplayOrderKey,
        summary: "Open a real thread",
        rail: .blue,
        label: nil,
        origin: .humanInteractive(subtype: .cli),
        relationship: relationship
    )
}

func makeDetailThread(_ id: String, text: String) -> ThreadDTO {
    ThreadDTO(
        id: id,
        turns: [
            makeDetailTurn(id: "turn-1", text: text),
        ]
    )
}

func makeDetailTurn(
    id: String,
    startedAt: Int64? = nil,
    text: String
) -> JSONValue {
    var fields: [String: JSONValue] = [
        "id": .string(id),
        "items": .array([
            .object([
                "id": .string("\(id)-agent"),
                "type": .string("agentMessage"),
                "text": .string(text),
            ]),
        ]),
    ]
    if let startedAt {
        fields["startedAt"] = .integer(startedAt)
    }
    return .object(fields)
}

@MainActor
func waitForDetailStore(
    timeout: Duration = .seconds(2),
    _ predicate: @escaping () -> Bool
) async throws {
    let start = ContinuousClock.now
    while start.duration(to: .now) < timeout {
        if predicate() {
            return
        }
        try await Task.sleep(for: .milliseconds(10))
    }
    throw DetailStoreTimeoutError()
}

@MainActor
func waitForDetailStoreAsync(
    timeout: Duration = .seconds(2),
    _ predicate: @escaping () async -> Bool
) async throws {
    let start = ContinuousClock.now
    while start.duration(to: .now) < timeout {
        if await predicate() {
            return
        }
        try await Task.sleep(for: .milliseconds(10))
    }
    throw DetailStoreTimeoutError()
}

struct DetailStoreTimeoutError: Error {}

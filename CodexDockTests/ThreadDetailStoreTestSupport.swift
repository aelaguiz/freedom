import XCTest
@testable import CodexDock

struct FakeThreadDetailSessionFactory: ThreadDetailSessionMaking {
    let session: FakeThreadDetailSession

    func makeSession(for host: DockHostConfiguration) -> any ThreadDetailSession {
        session
    }
}

struct ThreadDetailProjectionSeed: Equatable, Sendable {
    let threadID: String
    let rows: [ThreadDetailEventDTO]
    let activeTurnID: String?
    let sourceHostID: String?

    init(
        threadID: String = "thread-1",
        rows: [ThreadDetailEventDTO] = [],
        activeTurnID: String? = nil,
        sourceHostID: String? = nil
    ) {
        self.threadID = threadID
        self.rows = rows
        self.activeTurnID = activeTurnID
        self.sourceHostID = sourceHostID
    }

    static func thread(
        _ threadID: String = "thread-1",
        rows: [ThreadDetailEventDTO] = [],
        activeTurnID: String? = nil,
        sourceHostID: String? = nil
    ) -> ThreadDetailProjectionSeed {
        ThreadDetailProjectionSeed(
            threadID: threadID,
            rows: rows,
            activeTurnID: activeTurnID,
            sourceHostID: sourceHostID
        )
    }
}

final class FakeThreadDetailSession: @unchecked Sendable, ThreadDetailSession {
    let connectionStates: AsyncStream<AppServerConnectionState>
    let notifications: AsyncStream<JSONRPCNotification>
    let serverRequests: AsyncStream<JSONRPCRequest>

    private let connectionStateContinuation: AsyncStream<AppServerConnectionState>.Continuation
    private let notificationContinuation: AsyncStream<JSONRPCNotification>.Continuation
    private let serverRequestContinuation: AsyncStream<JSONRPCRequest>.Continuation
    private var detailSubscribeResults: [Result<ThreadDetailProjectionSeed, any Error>]
    private var detailResyncResults: [Result<ThreadDetailProjectionSeed, any Error>]
    private var projectionRowsResults: [Result<[ThreadDetailEventDTO], any Error>]
    private let turnStartResult: Result<TurnStartResponseDTO, any Error>
    private let turnSteerResult: Result<TurnSteerResponseDTO, any Error>
    private let projectionDelay: Duration?
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
        detailSubscribeResult: Result<ThreadDetailProjectionSeed, any Error> = .success(.thread()),
        projectionRowsResult: Result<[ThreadDetailEventDTO], any Error> = .success([]),
        detailResyncResult: Result<ThreadDetailProjectionSeed, any Error> = .success(.thread()),
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
        projectionDelay: Duration? = nil,
        detailSubscribeResults: [Result<ThreadDetailProjectionSeed, any Error>]? = nil,
        projectionRowsResults: [Result<[ThreadDetailEventDTO], any Error>]? = nil,
        detailResyncResults: [Result<ThreadDetailProjectionSeed, any Error>]? = nil,
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
        self.detailSubscribeResults = detailSubscribeResults ?? [detailSubscribeResult]
        self.detailResyncResults = detailResyncResults ?? [detailResyncResult]
        self.projectionRowsResults = projectionRowsResults ?? [projectionRowsResult]
        self.detailSourceHostID = detailSourceHostID
        self.turnStartResult = turnStartResult
        self.turnSteerResult = turnSteerResult
        self.projectionDelay = projectionDelay
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

    func threadDetailSubscribe(
        params: ThreadDetailParams,
        timeout: Duration
    ) async throws -> ThreadDetailSnapshotDTO {
        detailSubscribeParams.append(params)
        if let projectionDelay {
            try await Task.sleep(for: projectionDelay)
        }
        return try makeNextDetailSnapshot(
            seed: nextProjectionSeed(from: &detailSubscribeResults),
            requestedThreadID: params.threadId,
            preservingLiveEvents: true
        )
    }

    func threadDetailResync(
        params: ThreadDetailParams,
        timeout: Duration
    ) async throws -> ThreadDetailSnapshotDTO {
        detailResyncParams.append(params)
        if let projectionDelay {
            try await Task.sleep(for: projectionDelay)
        }
        return try makeNextDetailSnapshot(
            seed: nextProjectionSeed(from: &detailResyncResults),
            requestedThreadID: params.threadId,
            preservingLiveEvents: true
        )
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
        guard notification.method == AppServerMethods.threadDetailUpdate else {
            return
        }
        notificationContinuation.yield(notification)
    }

    func emitProjectionUpdate(_ update: ThreadDetailUpdateDTO) async {
        notificationContinuation.yield(projectedNotification(update))
    }

    func emitProjectedRow(_ row: ThreadDetailEventDTO) async {
        await emitProjectionUpdate(upsertDetailRow(row))
    }

    func emitProjectedAgentDelta(
        threadID: String = "thread-1",
        turnID: String,
        itemID: String,
        text: String
    ) async {
        let row = makeProjectedDetailEvent(
            threadID: threadID,
            sourceHostID: detailSourceHostID,
            turnID: turnID,
            itemID: itemID,
            activityDate: Date(timeIntervalSince1970: 3_000 + TimeInterval(detailSeq)),
            text: text,
            renderState: .streaming
        )
        await emitProjectionUpdate(upsertDetailRow(row))
    }

    func emitProjectedAgentCompleted(
        threadID: String = "thread-1",
        turnID: String,
        itemID: String,
        text: String
    ) async {
        let row = makeProjectedDetailEvent(
            threadID: threadID,
            sourceHostID: detailSourceHostID,
            turnID: turnID,
            itemID: itemID,
            activityDate: Date(timeIntervalSince1970: 3_000 + TimeInterval(detailSeq)),
            text: text,
            renderState: .settled
        )
        await emitProjectionUpdate(upsertDetailRow(row))
    }

    func emitProjectedThreadClosed(threadID: String = "thread-1") async {
        await emitProjectionUpdate(
            ThreadDetailUpdateDTO(
                kind: .heartbeat,
                sourceHostID: detailSourceHostID,
                threadID: threadID,
                epoch: detailEpoch,
                seq: detailSeq,
                viewParamsKey: "default-view",
                order: "displayOrderKeyAscending",
                activeTurnID: detailActiveTurnID,
                liveState: "closed"
            )
        )
    }

    func emitServerRequest(_ request: JSONRPCRequest) async {
        guard let update = applyDetail(request: request) else {
            return
        }
        await emitProjectionUpdate(update)
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
        seed: ThreadDetailProjectionSeed,
        requestedThreadID: String,
        preservingLiveEvents: Bool
    ) throws -> ThreadDetailSnapshotDTO {
        let sourceHostID = seed.sourceHostID ?? detailSourceHostID
        let rows = seed.rows.isEmpty ? try nextProjectionRows() : seed.rows
        let preservedEvents = preservingLiveEvents
            ? detailEventsByID.values.filter { $0.isLive || $0.request != nil }
            : []
        var snapshot = Self.detailSnapshot(
            threadID: seed.threadID,
            rows: rows,
            activeTurnID: seed.activeTurnID,
            sourceHostID: sourceHostID,
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
                    threadID: seed.threadID,
                    sourceHostID: sourceHostID,
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
        if snapshot.threadID != requestedThreadID {
            detailEventsByID.removeAll()
            detailRevisionsByID.removeAll()
            detailActiveTurnID = nil
            return snapshot
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

    private func nextProjectionSeed(
        from results: inout [Result<ThreadDetailProjectionSeed, any Error>]
    ) throws -> ThreadDetailProjectionSeed {
        let result = results.count > 1 ? results.removeFirst() : results[0]
        return try result.get()
    }

    private func nextProjectionRows() throws -> [ThreadDetailEventDTO] {
        let result = projectionRowsResults.count > 1
            ? projectionRowsResults.removeFirst()
            : projectionRowsResults[0]
        return try result.get()
    }

    private func applyDetail(request: JSONRPCRequest) -> ThreadDetailUpdateDTO? {
        let params = request.params?.objectValue ?? [:]
        if let requestThreadID = params["threadId"]?.stringValue,
           requestThreadID != detailThreadID() {
            return nil
        }
        let requestDate = params["startedAtMs"]?.numberValue.map { Date(timeIntervalSince1970: $0 / 1_000) }
            ?? Date(timeIntervalSince1970: 3_000)
        let body = commandText(params["command"])
            ?? params["reason"]?.stringValue
            ?? params["message"]?.stringValue
            ?? request.method
        let row = makeProjectedDetailEvent(
            threadID: detailThreadID(),
            sourceHostID: detailSourceHostID,
            turnID: params["turnId"]?.stringValue,
            itemID: params["itemId"]?.stringValue,
            requestID: request.id.description,
            kind: .request,
            visibility: .request,
            rowRole: "request",
            title: requestTitle(for: request.method),
            activityDate: requestDate,
            text: body,
            renderState: .live,
            request: ThreadDetailEventRequestDTO(
                requestID: request.id,
                method: request.method,
                params: request.params,
                status: "pending"
            )
        )
        return upsertDetailRow(row)
    }

    private func upsertDetailRow(_ row: ThreadDetailEventDTO) -> ThreadDetailUpdateDTO {
        let projected = ThreadEvent(detailEvent: row)
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
        let nextRow = Self.detailEventDTO(
            from: next,
            threadID: detailThreadID(),
            sourceHostID: detailSourceHostID,
            index: detailEventsByID.count,
            revision: revision
        )
        detailEventsByID[nextRow.projectionID] = ThreadEvent(detailEvent: nextRow)
        detailRevisionsByID[nextRow.projectionID] = revision
        return ThreadDetailUpdateDTO(
            kind: .upsert,
            sourceHostID: detailSourceHostID,
            threadID: detailThreadID(),
            epoch: detailEpoch,
            seq: nextDetailSeq(),
            viewParamsKey: "default-view",
            order: "displayOrderKeyAscending",
            rows: [
                nextRow,
            ],
            activeTurnID: detailActiveTurnID
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

    private func projectedNotification(_ update: ThreadDetailUpdateDTO) -> JSONRPCNotification {
        JSONRPCNotification(
            method: AppServerMethods.threadDetailUpdate,
            params: try! JSONValue.encoded(update)
        )
    }

    private static func detailSnapshot(
        threadID: String,
        rows: [ThreadDetailEventDTO],
        activeTurnID: String?,
        sourceHostID: String,
        epoch: String,
        seq: Int64
    ) -> ThreadDetailSnapshotDTO {
        let projectedRows = rows.enumerated().map { index, row in
            detailEventDTO(
                from: ThreadEvent(detailEvent: row),
                threadID: threadID,
                sourceHostID: sourceHostID,
                index: index,
                revision: row.revision
            )
        }
        return ThreadDetailSnapshotDTO(
            sourceHostID: sourceHostID,
            threadID: threadID,
            epoch: epoch,
            seq: seq,
            viewParamsKey: "default-view",
            activeTurnID: activeTurnID,
            order: "displayOrderKeyAscending",
            rows: projectedRows
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
            request: event.request,
            fileChange: event.fileChange
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
    case projectionFailed
    case turnFailed

    var errorDescription: String? {
        switch self {
        case .projectionFailed:
            return "projection failed"
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

func makeProjectedDetailEvent(
    threadID: String = "thread-1",
    sourceHostID: String = "test-host",
    turnID: String? = "turn-1",
    itemID: String? = nil,
    requestID: String? = nil,
    kind: ThreadEventKind = .agentMessage,
    visibility: ThreadEventVisibilityCategory = .message,
    rowRole: String? = nil,
    title: String? = nil,
    startedAt: Int64? = nil,
    activityDate: Date? = nil,
    text: String,
    renderState: ThreadDetailRenderState = .settled,
    request: ThreadDetailEventRequestDTO? = nil,
    fileChange: ThreadDetailFileChangeDTO? = nil,
    revision: Int = 1
) -> ThreadDetailEventDTO {
    let resolvedItemID = itemID ?? turnID.map { "\($0)-agent" }
    let resolvedRowRole = rowRole ?? rowRoleForProjectedEvent(kind: kind, visibility: visibility)
    let projectionID = projectionIDForProjectedDetailEvent(
        sourceHostID: sourceHostID,
        threadID: threadID,
        turnID: turnID,
        itemID: resolvedItemID,
        requestID: requestID,
        rowRole: resolvedRowRole
    )
    let eventDate = activityDate ?? startedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    return ThreadDetailEventDTO(
        sourceHostID: sourceHostID,
        threadID: threadID,
        projectionID: projectionID,
        sourceRef: sourceRefForProjectedDetailEvent(
            projectionID: projectionID,
            rowRole: resolvedRowRole
        ),
        itemType: kind.rawValue,
        rowRole: resolvedRowRole,
        visibility: visibility,
        renderKind: kind,
        displayOrderKey: displayOrderKeyForProjectedDetailEvent(
            activityDate: eventDate,
            projectionID: projectionID
        ),
        title: title ?? titleForProjectedEvent(kind: kind, visibility: visibility),
        body: text,
        eventTime: eventDate.map(projectedEventISOString),
        activityTime: eventDate.map(projectedEventISOString),
        turnID: turnID,
        itemID: resolvedItemID,
        turnOrder: nil,
        itemOrder: nil,
        rowOrder: nil,
        revision: revision,
        renderState: renderState,
        requestID: requestID,
        request: request,
        fileChange: fileChange
    )
}

func makeProjectedFileChangeEvent(
    sourceHostID: String = "test-host",
    threadID: String = "thread-1",
    turnID: String = "turn-1",
    itemID: String = "item-file-1",
    requestID: String? = "approval-1",
    approvalRequired: Bool = true
) -> ThreadDetailEventDTO {
    let request = requestID.map {
        ThreadDetailEventRequestDTO(
            requestID: .string($0),
            method: "item/fileChange/requestApproval",
            params: .object([
                "threadId": .string(threadID),
                "turnId": .string(turnID),
                "itemId": .string(itemID),
                "reason": .string("Approve file change"),
            ]),
            status: "pending"
        )
    }
    return makeProjectedDetailEvent(
        threadID: threadID,
        sourceHostID: sourceHostID,
        turnID: turnID,
        itemID: itemID,
        requestID: requestID,
        kind: .request,
        visibility: .request,
        rowRole: "fileChange",
        title: requestID == nil ? "File change" : "File change approval",
        startedAt: 3_000,
        text: approvalRequired ? "Review 1 file before approving, +2 -1" : "1 file changed, +2 -1",
        renderState: requestID == nil ? .settled : .live,
        request: request,
        fileChange: ThreadDetailFileChangeDTO(
            version: 1,
            status: approvalRequired ? "pending" : "completed",
            approvalRequired: approvalRequired,
            summary: ThreadDetailFileChangeSummaryDTO(
                fileCount: 1,
                additions: 2,
                deletions: 1,
                truncated: false
            ),
            changes: [
                ThreadDetailFileChangeEntryDTO(
                    path: "CodexDock/AppServer/ThreadDetailDTO.swift",
                    oldPath: nil,
                    kind: "update",
                    additions: 2,
                    deletions: 1,
                    diffAvailability: "available",
                    diff: "@@ -1,3 +1,4 @@\n import Foundation\n-old line\n+new line\n+added line\n context\n",
                    truncated: false
                ),
            ]
        )
    )
}

private func rowRoleForProjectedEvent(
    kind: ThreadEventKind,
    visibility: ThreadEventVisibilityCategory
) -> String {
    switch kind {
    case .userMessage:
        return "userMessage"
    case .agentMessage:
        return visibility == .thinking ? "reasoning" : "agentMessage"
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

private func titleForProjectedEvent(
    kind: ThreadEventKind,
    visibility: ThreadEventVisibilityCategory
) -> String {
    switch kind {
    case .agentMessage where visibility == .thinking:
        return "Reasoning update"
    case .agentMessage:
        return "Agent message"
    case .userMessage:
        return "User message"
    case .command:
        return "Command"
    case .output:
        return "Command output"
    case .request:
        return "Request"
    case .system:
        return "System"
    case .unknown:
        return "Unknown"
    }
}

private func requestTitle(for method: String) -> String {
    switch method {
    case "item/commandExecution/requestApproval":
        return "Command approval"
    case "apply_patch/approval":
        return "Patch approval"
    default:
        return "Request"
    }
}

private func commandText(_ value: JSONValue?) -> String? {
    switch value {
    case .string(let text):
        return text
    case .array(let parts):
        let joined = parts.compactMap(\.stringValue).joined(separator: " ")
        return joined.isEmpty ? nil : joined
    case .object(let object):
        return commandText(object["cmd"]) ?? commandText(object["command"])
    case .null, .bool, .integer, .double, .none:
        return nil
    }
}

private func projectionIDForProjectedDetailEvent(
    sourceHostID: String,
    threadID: String,
    turnID: String?,
    itemID: String?,
    requestID: String?,
    rowRole: String
) -> String {
    if rowRole == "request", let requestID {
        return "host:\(sourceHostID)/thread:\(threadID)/request:\(requestID)/row:request"
    }
    if let turnID, let itemID {
        return "host:\(sourceHostID)/thread:\(threadID)/turn:\(turnID)/item:\(itemID)/row:\(rowRole)"
    }
    return "host:\(sourceHostID)/thread:\(threadID)/diagnostic:\(UUID().uuidString)/row:\(rowRole)"
}

private func sourceRefForProjectedDetailEvent(
    projectionID: String,
    rowRole: String
) -> String {
    if let suffixRange = projectionID.range(of: "/row:\(rowRole)", options: .backwards) {
        return String(projectionID[..<suffixRange.lowerBound])
    }
    return projectionID
}

private func displayOrderKeyForProjectedDetailEvent(
    activityDate: Date?,
    projectionID: String
) -> String {
    let timestamp = Int64(activityDate?.timeIntervalSince1970 ?? 0)
    let inverted = 9_999_999_999_999_999 - timestamp
    return String(format: "%016lld|%@", inverted, projectionID)
}

private func projectedEventISOString(from date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
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

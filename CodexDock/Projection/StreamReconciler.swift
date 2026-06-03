import Foundation

struct ProjectionViewKey: Hashable, Sendable {
    let sourceHostID: String?
    let view: String
    let scope: String?
    let viewParamsKey: String?

    init(
        sourceHostID: String?,
        view: String,
        scope: String?,
        viewParamsKey: String?
    ) {
        self.sourceHostID = sourceHostID
        self.view = view
        self.scope = scope
        self.viewParamsKey = viewParamsKey
    }
}

enum StreamReconcilerRecoveryReason: String, Equatable, Sendable {
    case manualRefresh
    case foregroundResume
    case transportReconnect
    case heartbeatTimeout
    case sequenceGap
    case relayResyncRequired
    case bufferOverflow
    case commandCompletedInvalidation
    case streamContract
}

enum StreamReconcilerFreshnessState: Equatable, Sendable {
    case connecting
    case subscribing
    case live
    case catchingUp(StreamReconcilerRecoveryReason)
    case stale(String)
    case offline(String)
    case failed(String)
    case closed
}

struct StreamReconcilerSnapshot<Row: Equatable & Sendable>: Equatable, Sendable {
    let viewKey: ProjectionViewKey
    let freshness: StreamReconcilerFreshnessState
    let revision: Int
    let rows: [Row]
    let epoch: String?
    let seq: Int64
    let generation: Int
    let activeTurnID: String?
    let complete: Bool?
    let totalRows: Int?
    let window: ProjectionWindow?
    let bufferedEnvelopeCount: Int
    let lastError: String?
}

protocol ProjectionStreamConnection<Row>: Sendable {
    associatedtype Row: Equatable & Sendable

    func subscribe() async throws -> ProjectionEnvelope<Row>
    func resync(reason: StreamReconcilerRecoveryReason) async throws -> ProjectionEnvelope<Row>
    func updates() -> AsyncThrowingStream<ProjectionEnvelope<Row>, Error>
    func close() async
}

protocol ProjectionStreamConnecting<Row>: Sendable {
    associatedtype Row: Equatable & Sendable

    func connect() async throws -> any ProjectionStreamConnection<Row>
}

actor StreamReconciler<Row: Equatable & Sendable> {
    private let viewKey: ProjectionViewKey
    private let policy: ProjectionReducerPolicy<Row>
    private let connector: any ProjectionStreamConnecting<Row>
    private let maxBufferedEnvelopeCount: Int
    private let heartbeatTimeout: Duration?
    private let reconnectDelay: Duration?

    private var reducer = ProjectionReducer<Row>()
    private var resolvedSourceHostID: String?
    private var resolvedViewParamsKey: String?
    private var connection: (any ProjectionStreamConnection<Row>)?
    private var updateTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var heartbeatToken: UUID?
    private var freshness: StreamReconcilerFreshnessState = .closed
    private var revision = 0
    private var activeTurnID: String?
    private var complete: Bool?
    private var totalRows: Int?
    private var window: ProjectionWindow?
    private var activeCatchupReason: StreamReconcilerRecoveryReason?
    private var isResyncing = false
    private var pendingRecoveryReason: StreamReconcilerRecoveryReason?
    private var bufferedEnvelopes: [ProjectionEnvelope<Row>] = []
    private var lastError: String?
    private var sinks: [UUID: AsyncStream<StreamReconcilerSnapshot<Row>>.Continuation] = [:]

    init(
        viewKey: ProjectionViewKey,
        policy: ProjectionReducerPolicy<Row>,
        connector: any ProjectionStreamConnecting<Row>,
        maxBufferedEnvelopeCount: Int = 128,
        heartbeatTimeout: Duration? = nil,
        reconnectDelay: Duration? = nil
    ) {
        self.viewKey = viewKey
        self.policy = policy
        self.connector = connector
        self.maxBufferedEnvelopeCount = max(1, maxBufferedEnvelopeCount)
        self.heartbeatTimeout = heartbeatTimeout
        self.reconnectDelay = reconnectDelay
    }

    deinit {
        updateTask?.cancel()
        heartbeatTask?.cancel()
        reconnectTask?.cancel()
        for continuation in sinks.values {
            continuation.finish()
        }
    }

    func snapshots() -> AsyncStream<StreamReconcilerSnapshot<Row>> {
        let id = UUID()
        return AsyncStream { continuation in
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeSink(id: id) }
            }
            Task { await self.addSink(id: id, continuation: continuation) }
        }
    }

    func snapshot() -> StreamReconcilerSnapshot<Row> {
        currentSnapshot()
    }

    func start() async {
        reconnectTask?.cancel()
        reconnectTask = nil
        guard freshness != .closed || connection == nil else {
            freshness = .connecting
            publish()
            await openConnection(recoveryReason: nil)
            return
        }
        await closeCurrentConnection()
        freshness = .connecting
        publish()
        await openConnection(recoveryReason: nil)
    }

    func manualRefresh() async {
        await requestResync(reason: .manualRefresh)
    }

    func foregroundResumed() async {
        await requestResync(reason: .foregroundResume)
    }

    func transportReconnected() async {
        await requestResync(reason: .transportReconnect, message: lastError)
    }

    func transportReconnecting(_ message: String) {
        guard freshness != .closed else {
            return
        }
        activeCatchupReason = .transportReconnect
        freshness = .catchingUp(.transportReconnect)
        lastError = message
        publish()
    }

    func commandCompletedInvalidation() async {
        await requestResync(reason: .commandCompletedInvalidation)
    }

    func heartbeatTimedOut() async {
        await closeCurrentConnection()
        await markOffline("Projection stream heartbeat timed out.")
        scheduleReconnectIfNeeded()
    }

    func staleDeadlineExceeded(_ message: String = "Projection stream is stale.") {
        guard freshness != .closed else {
            return
        }
        freshness = .stale(message)
        lastError = message
        publish()
    }

    func transportDisconnected(_ message: String) {
        guard freshness != .closed else {
            return
        }
        freshness = .offline(message)
        lastError = message
        publish()
    }

    func receive(_ envelope: ProjectionEnvelope<Row>) async {
        guard freshness != .closed else {
            return
        }
        if isResyncing {
            await buffer(envelope)
            return
        }
        await applyIncoming(envelope)
    }

    func close() async {
        freshness = .closed
        activeCatchupReason = nil
        isResyncing = false
        pendingRecoveryReason = nil
        bufferedEnvelopes.removeAll()
        heartbeatTask?.cancel()
        heartbeatTask = nil
        heartbeatToken = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        updateTask?.cancel()
        updateTask = nil
        await closeCurrentConnection()
        publish()
        for continuation in sinks.values {
            continuation.finish()
        }
        sinks.removeAll()
    }

    private func openConnection(recoveryReason: StreamReconcilerRecoveryReason?) async {
        do {
            let opened = try await connector.connect()
            guard freshness != .closed else {
                await opened.close()
                return
            }
            connection = opened
            freshness = .subscribing
            publish()
            let subscribed = try await opened.subscribe()
            try applySnapshot(subscribed, recoveryReason: recoveryReason)
            startUpdateTask(opened)
        } catch {
            await closeCurrentConnection()
            await markFailed(error)
            scheduleReconnectIfNeeded()
        }
    }

    private func startUpdateTask(_ connection: any ProjectionStreamConnection<Row>) {
        updateTask?.cancel()
        updateTask = Task { [connection] in
            do {
                for try await envelope in connection.updates() {
                    await self.receive(envelope)
                }
                if !Task.isCancelled {
                    await self.handleConnectionLoss("Projection stream closed.")
                }
            } catch is CancellationError {
                return
            } catch {
                await self.handleConnectionFailure(error)
            }
        }
    }

    private func requestResync(
        reason: StreamReconcilerRecoveryReason,
        message: String? = nil
    ) async {
        guard freshness != .closed else {
            return
        }
        guard let connection else {
            activeCatchupReason = reason
            freshness = .connecting
            lastError = message
            publish()
            await openConnection(recoveryReason: reason)
            return
        }
        if isResyncing {
            pendingRecoveryReason = reason
            return
        }

        isResyncing = true
        activeCatchupReason = reason
        freshness = .catchingUp(reason)
        lastError = message
        publish()

        do {
            let snapshot = try await connection.resync(reason: reason)
            isResyncing = false
            try applySnapshot(snapshot, recoveryReason: reason)
            if let pendingRecoveryReason {
                self.pendingRecoveryReason = nil
                await requestResync(reason: pendingRecoveryReason)
                return
            }
            await drainBufferedEnvelopes()
        } catch {
            isResyncing = false
            activeCatchupReason = nil
            await markFailed(error)
        }
    }

    private func applyIncoming(_ envelope: ProjectionEnvelope<Row>) async {
        guard validateViewKey(envelope) else {
            await requestResync(reason: .streamContract)
            return
        }

        if activeCatchupReason != nil {
            if envelope.kind == .page {
                await applyCatchupPage(envelope)
            } else {
                await buffer(envelope)
            }
            return
        }

        guard envelope.kind != .page else {
            await requestResync(reason: .streamContract)
            return
        }

        do {
            try reducer.apply(envelope, policy: policy)
            updateProjectionMetadata(from: envelope)
            activeTurnID = envelope.activeTurnID
            freshness = freshnessState(after: envelope)
            lastError = lastError(after: freshness)
            scheduleHeartbeatIfNeeded()
            publish()
        } catch {
            await handleReducerError(error)
        }
    }

    private func applySnapshot(
        _ envelope: ProjectionEnvelope<Row>,
        recoveryReason: StreamReconcilerRecoveryReason?
    ) throws {
        guard validateViewKey(envelope), envelope.kind == .snapshot else {
            throw ProjectionReducerError.streamContract("Projection subscribe/resync must return a snapshot for the reconciler view key.")
        }
        try reducer.apply(envelope, policy: policy)
        resolvedSourceHostID = envelope.sourceHostID
        resolvedViewParamsKey = envelope.viewParamsKey
        updateProjectionMetadata(from: envelope)
        activeTurnID = envelope.activeTurnID
        if isCatchupComplete(envelope) {
            activeCatchupReason = nil
            freshness = freshnessState(after: envelope)
        } else {
            let reason = recoveryReason ?? .manualRefresh
            activeCatchupReason = reason
            freshness = .catchingUp(reason)
        }
        lastError = lastError(after: freshness)
        scheduleHeartbeatIfNeeded()
        publish()
    }

    private func applyCatchupPage(_ envelope: ProjectionEnvelope<Row>) async {
        do {
            try reducer.apply(envelope, policy: policy)
            updateProjectionMetadata(from: envelope)
            activeTurnID = envelope.activeTurnID
            if isCatchupComplete(envelope) {
                activeCatchupReason = nil
                freshness = freshnessState(after: envelope)
                lastError = lastError(after: freshness)
                scheduleHeartbeatIfNeeded()
                publish()
                await drainBufferedEnvelopes()
            } else if let activeCatchupReason {
                freshness = .catchingUp(activeCatchupReason)
                publish()
            }
        } catch {
            await handleReducerError(error)
        }
    }

    private func drainBufferedEnvelopes() async {
        while !bufferedEnvelopes.isEmpty {
            if activeCatchupReason != nil,
               bufferedEnvelopes.first?.kind != .page {
                return
            }
            let next = bufferedEnvelopes.removeFirst()
            await applyIncoming(next)
            if isResyncing || pendingRecoveryReason != nil {
                return
            }
        }
    }

    private func buffer(_ envelope: ProjectionEnvelope<Row>) async {
        if bufferedEnvelopes.count >= maxBufferedEnvelopeCount {
            bufferedEnvelopes.removeAll()
            if isResyncing {
                pendingRecoveryReason = .bufferOverflow
            } else {
                await requestResync(reason: .bufferOverflow)
            }
            return
        }
        bufferedEnvelopes.append(envelope)
        publish()
    }

    private func handleReducerError(_ error: Error) async {
        switch error {
        case ProjectionReducerError.sequenceGap:
            await requestResync(reason: .sequenceGap)
        case ProjectionReducerError.resyncRequired:
            await requestResync(reason: .relayResyncRequired)
        case ProjectionReducerError.epochMismatch,
             ProjectionReducerError.schemaMismatch,
             ProjectionReducerError.streamContract:
            await requestResync(reason: .streamContract)
        default:
            await markFailed(error)
        }
    }

    private func validateViewKey(_ envelope: ProjectionEnvelope<Row>) -> Bool {
        guard envelope.view == viewKey.view,
              envelope.scope == viewKey.scope,
              !envelope.sourceHostID.isEmpty,
              let envelopeViewParamsKey = envelope.viewParamsKey,
              !envelopeViewParamsKey.isEmpty else {
            return false
        }
        let expectedSourceHostID = resolvedSourceHostID ?? viewKey.sourceHostID
        let expectedViewParamsKey = resolvedViewParamsKey ?? viewKey.viewParamsKey
        return (expectedSourceHostID == nil || envelope.sourceHostID == expectedSourceHostID)
            && (expectedViewParamsKey == nil || envelopeViewParamsKey == expectedViewParamsKey)
    }

    private func isCatchupComplete(_ envelope: ProjectionEnvelope<Row>) -> Bool {
        // Catch-up pagination is driven by nextOffset. A stale partial snapshot
        // with no next page must not strand the view in catchingUp forever.
        if envelope.window?.nextOffset != nil {
            return false
        }
        return true
    }

    private func closeCurrentConnection() async {
        updateTask?.cancel()
        updateTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        heartbeatToken = nil
        let previousConnection = connection
        connection = nil
        await previousConnection?.close()
    }

    private func handleConnectionLoss(_ message: String) async {
        await markOffline(message)
        scheduleReconnectIfNeeded()
    }

    private func handleConnectionFailure(_ error: Error) async {
        await markFailed(error)
        scheduleReconnectIfNeeded()
    }

    private func markOffline(_ message: String) async {
        guard freshness != .closed else {
            return
        }
        freshness = .offline(message)
        lastError = message
        publish()
    }

    private func markFailed(_ error: Error) async {
        guard freshness != .closed else {
            return
        }
        let message = error.localizedDescription
        freshness = error.isProjectionOfflineFailure ? .offline(message) : .failed(message)
        lastError = message
        publish()
    }

    private func scheduleHeartbeatIfNeeded() {
        guard let heartbeatTimeout, freshness != .closed else {
            return
        }
        let token = UUID()
        heartbeatToken = token
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self, heartbeatTimeout] in
            do {
                try await Task.sleep(for: heartbeatTimeout)
            } catch {
                return
            }
            await self?.heartbeatTimedOut(ifCurrent: token)
        }
    }

    private func heartbeatTimedOut(ifCurrent token: UUID) async {
        guard heartbeatToken == token, freshness != .closed else {
            return
        }
        await heartbeatTimedOut()
    }

    private func scheduleReconnectIfNeeded() {
        guard let reconnectDelay, freshness != .closed else {
            return
        }
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self, reconnectDelay] in
            do {
                try await Task.sleep(for: reconnectDelay)
            } catch {
                return
            }
            await self?.start()
        }
    }

    private func updateProjectionMetadata(from envelope: ProjectionEnvelope<Row>) {
        complete = envelope.complete ?? complete
        totalRows = envelope.totalRows ?? totalRows
        window = envelope.window ?? window
    }

    private func freshnessState(after envelope: ProjectionEnvelope<Row>) -> StreamReconcilerFreshnessState {
        if envelope.liveState == "closed" {
            return .closed
        }
        switch envelope.freshnessStatus {
        case "stale":
            return .stale(envelope.freshnessError ?? "Stale")
        case "offline":
            return .offline(envelope.freshnessError ?? "Offline")
        case "error":
            return .failed(envelope.freshnessError ?? "Error")
        default:
            return .live
        }
    }

    private func lastError(after freshness: StreamReconcilerFreshnessState) -> String? {
        switch freshness {
        case .stale(let message), .offline(let message), .failed(let message):
            return message
        case .connecting, .subscribing, .live, .catchingUp, .closed:
            return nil
        }
    }

    private func addSink(
        id: UUID,
        continuation: AsyncStream<StreamReconcilerSnapshot<Row>>.Continuation
    ) async {
        sinks[id] = continuation
        continuation.yield(currentSnapshot())
    }

    private func removeSink(id: UUID) async {
        sinks[id] = nil
    }

    private func publish() {
        revision += 1
        let snapshot = currentSnapshot()
        for continuation in sinks.values {
            continuation.yield(snapshot)
        }
    }

    private func currentSnapshot() -> StreamReconcilerSnapshot<Row> {
        StreamReconcilerSnapshot(
            viewKey: ProjectionViewKey(
                sourceHostID: resolvedSourceHostID ?? viewKey.sourceHostID,
                view: viewKey.view,
                scope: viewKey.scope,
                viewParamsKey: resolvedViewParamsKey ?? viewKey.viewParamsKey
            ),
            freshness: freshness,
            revision: revision,
            rows: reducer.sortedRows(policy: policy),
            epoch: reducer.epoch,
            seq: reducer.seq,
            generation: reducer.generation,
            activeTurnID: activeTurnID,
            complete: complete,
            totalRows: totalRows,
            window: window,
            bufferedEnvelopeCount: bufferedEnvelopes.count,
            lastError: lastError
        )
    }
}

private extension Error {
    var isProjectionOfflineFailure: Bool {
        if let failure = self as? DockRequestFailure {
            switch failure {
            case .offline:
                return true
            case .error:
                return false
            }
        }
        guard let clientError = self as? AppServerClientError else {
            return false
        }
        switch clientError {
        case .disconnected, .notConnected, .transport:
            return true
        case .duplicateRequestID,
             .malformedMessage,
             .requestCancelled,
             .requestTimedOut,
             .responseDecoding,
             .server,
             .unexpectedServerRequest,
             .unmatchedResponse:
            return false
        }
    }
}

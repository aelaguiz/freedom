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
    let rows: [Row]
    let epoch: String?
    let seq: Int64
    let generation: Int
    let activeTurnID: String?
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

    private var reducer = ProjectionReducer<Row>()
    private var resolvedSourceHostID: String?
    private var resolvedViewParamsKey: String?
    private var connection: (any ProjectionStreamConnection<Row>)?
    private var updateTask: Task<Void, Never>?
    private var freshness: StreamReconcilerFreshnessState = .closed
    private var activeTurnID: String?
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
        maxBufferedEnvelopeCount: Int = 128
    ) {
        self.viewKey = viewKey
        self.policy = policy
        self.connector = connector
        self.maxBufferedEnvelopeCount = max(1, maxBufferedEnvelopeCount)
    }

    deinit {
        updateTask?.cancel()
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
        guard freshness != .closed || connection == nil else {
            freshness = .connecting
            publish()
            await openConnection()
            return
        }
        await closeCurrentConnection()
        freshness = .connecting
        publish()
        await openConnection()
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
        await requestResync(reason: .heartbeatTimeout)
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
        updateTask?.cancel()
        updateTask = nil
        await closeCurrentConnection()
        publish()
        for continuation in sinks.values {
            continuation.finish()
        }
        sinks.removeAll()
    }

    private func openConnection() async {
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
            try applySnapshot(subscribed, recoveryReason: nil)
            startUpdateTask(opened)
        } catch {
            await markFailed(error)
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
                    await self.markOffline("Projection stream closed.")
                }
            } catch is CancellationError {
                return
            } catch {
                await self.markFailed(error)
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
            freshness = .offline("Projection stream is not connected.")
            lastError = "Projection stream is not connected."
            publish()
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
            activeTurnID = envelope.activeTurnID
            freshness = .live
            lastError = nil
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
        activeTurnID = envelope.activeTurnID
        if isCatchupComplete(envelope) {
            activeCatchupReason = nil
            freshness = .live
        } else {
            let reason = recoveryReason ?? .manualRefresh
            activeCatchupReason = reason
            freshness = .catchingUp(reason)
        }
        lastError = nil
        publish()
    }

    private func applyCatchupPage(_ envelope: ProjectionEnvelope<Row>) async {
        do {
            try reducer.apply(envelope, policy: policy)
            activeTurnID = envelope.activeTurnID
            if isCatchupComplete(envelope) {
                activeCatchupReason = nil
                freshness = .live
                lastError = nil
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
        if let complete = envelope.complete {
            return complete
        }
        return envelope.window?.nextOffset == nil
    }

    private func closeCurrentConnection() async {
        updateTask?.cancel()
        updateTask = nil
        let previousConnection = connection
        connection = nil
        await previousConnection?.close()
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
        freshness = .failed(message)
        lastError = message
        publish()
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
            rows: reducer.sortedRows(policy: policy),
            epoch: reducer.epoch,
            seq: reducer.seq,
            generation: reducer.generation,
            activeTurnID: activeTurnID,
            bufferedEnvelopeCount: bufferedEnvelopes.count,
            lastError: lastError
        )
    }
}

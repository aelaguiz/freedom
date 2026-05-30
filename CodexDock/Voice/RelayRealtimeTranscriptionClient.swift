import Foundation

public enum RelayRealtimeTranscriptionClientError: Error, Equatable, LocalizedError, Sendable {
    case emptyAudioChunk
    case audioChunkTooLarge(maxBytes: Int)
    case invalidRelayEvent
    case invalidSequence
    case sessionClosed
    case unexpectedSession(expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case .emptyAudioChunk:
            return "Realtime transcription audio chunk is empty."
        case .audioChunkTooLarge:
            return "Realtime transcription audio chunk is too large."
        case .invalidRelayEvent:
            return "Realtime transcription relay event could not be read."
        case .invalidSequence:
            return "Realtime transcription audio sequence is invalid."
        case .sessionClosed:
            return "Realtime transcription session is closed."
        case .unexpectedSession:
            return "Realtime transcription relay returned the wrong session."
        }
    }
}

@MainActor
public final class RelayRealtimeTranscriptionClient: RealtimeTranscriptionServicing {
    private let host: DockHostConfiguration
    private let completionTimeout: Duration
    private let maxChunkBytes: Int
    private let observabilityStore: ClientObservabilityStore
    private let makeClient: @Sendable (DockRelayEndpoint) -> AppServerClient

    public init(
        host: DockHostConfiguration,
        completionTimeout: Duration = CodexDockConstants.Voice.transcriptionCompletionTimeout,
        maxChunkBytes: Int = CodexDockConstants.Voice.transcriptionMaxChunkBytes,
        observabilityStore: ClientObservabilityStore = .shared,
        makeClient: @escaping @Sendable (DockRelayEndpoint) -> AppServerClient = {
            AppServerClient(webSocketURL: $0.webSocketURL, bearerToken: nil)
        }
    ) {
        self.host = host
        self.completionTimeout = completionTimeout
        self.maxChunkBytes = maxChunkBytes
        self.observabilityStore = observabilityStore
        self.makeClient = makeClient
    }

    public func startSession() async throws -> any RealtimeTranscriptionSession {
        // OpenAI credentials are relay-owned; the phone sends only session and audio controls.
        let startedAt = Date()
        let hostID = host.id
        let endpointURL = host.webSocketURL
        DockLog.transcription.notice("relay transcription session start requested host_id=\(hostID, privacy: .public) endpoint=\(DockLog.endpoint(endpointURL), privacy: .public)")
        do {
            let retained = try await AppServerHostConnector(makeClient: makeClient)
                .retainConnectedClient(for: host) { connection in
                    let startStartedAt = Date()
                    let context = AppServerRequestObservabilityContext(
                        configuredHostID: hostID,
                        route: AppServerMethods.audioTranscriptionStart,
                        store: observabilityStore
                    )
                    let response = try await connection.client.audioTranscriptionStart(
                        params: AudioTranscriptionStartParams(),
                        timeout: CodexDockConstants.Voice.transcriptionCommandTimeout,
                        observabilityContext: context
                    )
                    DockLog.transcription.debug("relay transcription start command accepted host_id=\(hostID, privacy: .public) endpoint=\(DockLog.endpoint(connection.endpoint.webSocketURL), privacy: .public) duration_ms=\(DockLog.milliseconds(since: startStartedAt), privacy: .public)")
                    return response
                }
            let connection = retained.connection
            let response = retained.value
            DockLog.transcription.notice("relay transcription session started host_id=\(hostID, privacy: .public) endpoint=\(DockLog.endpoint(connection.endpoint.webSocketURL), privacy: .public) session_id=\(DockLog.publicID(response.sessionId), privacy: .public) model=\(DockLog.publicID(response.model), privacy: .public) language=\(DockLog.publicID(response.language), privacy: .public) delay=\(DockLog.publicID(response.delay), privacy: .public) duration_ms=\(DockLog.milliseconds(since: startedAt), privacy: .public)")
            return RelayRealtimeTranscriptionSession(
                client: connection.client,
                configuredHostID: hostID,
                startResponse: response,
                completionTimeout: completionTimeout,
                maxChunkBytes: maxChunkBytes,
                observabilityStore: observabilityStore
            )
        } catch {
            DockLog.transcription.error("relay transcription session start failed host_id=\(hostID, privacy: .public) duration_ms=\(DockLog.milliseconds(since: startedAt), privacy: .public) error=\(DockLog.errorSummary(error), privacy: .public)")
            throw error
        }
    }
}

@MainActor
private final class RelayRealtimeTranscriptionSession: RealtimeTranscriptionSession {
    let id: String
    let events: AsyncStream<RealtimeTranscriptionEvent>

    private let client: AppServerClient
    private let configuredHostID: String
    private let completionTimeout: Duration
    private let maxChunkBytes: Int
    private let observabilityStore: ClientObservabilityStore
    private let continuation: AsyncStream<RealtimeTranscriptionEvent>.Continuation
    private var notificationTask: Task<Void, Never>?
    private var completionTimeoutTask: Task<Void, Never>?
    private var lastSequence = 0
    private var appendedChunks = 0
    private var appendedBytes = 0
    private var didCommit = false
    private var isClosed = false

    init(
        client: AppServerClient,
        configuredHostID: String,
        startResponse: AudioTranscriptionStartResponseDTO,
        completionTimeout: Duration,
        maxChunkBytes: Int,
        observabilityStore: ClientObservabilityStore
    ) {
        self.id = startResponse.sessionId
        self.client = client
        self.configuredHostID = configuredHostID
        self.completionTimeout = completionTimeout
        self.maxChunkBytes = maxChunkBytes
        self.observabilityStore = observabilityStore
        let stream = AsyncStream.makeStream(of: RealtimeTranscriptionEvent.self)
        self.events = stream.stream
        self.continuation = stream.continuation
        self.continuation.yield(.started(sessionID: startResponse.sessionId))
        startNotificationObservation()
    }

    deinit {
        notificationTask?.cancel()
        completionTimeoutTask?.cancel()
        let client = client
        Task {
            await client.disconnect()
        }
    }

    func appendAudio(_ chunk: Data, sequence: Int) async throws {
        guard !isClosed else {
            DockLog.transcription.warning("relay transcription append rejected session_id=\(DockLog.publicID(self.id), privacy: .public) reason=session_closed")
            throw RelayRealtimeTranscriptionClientError.sessionClosed
        }
        guard !chunk.isEmpty else {
            DockLog.transcription.warning("relay transcription append rejected session_id=\(DockLog.publicID(self.id), privacy: .public) reason=empty_audio")
            throw RelayRealtimeTranscriptionClientError.emptyAudioChunk
        }
        guard chunk.count <= maxChunkBytes else {
            DockLog.transcription.warning("relay transcription append rejected session_id=\(DockLog.publicID(self.id), privacy: .public) reason=chunk_too_large bytes=\(chunk.count, privacy: .public) max_bytes=\(self.maxChunkBytes, privacy: .public)")
            throw RelayRealtimeTranscriptionClientError.audioChunkTooLarge(maxBytes: maxChunkBytes)
        }
        guard sequence > lastSequence else {
            DockLog.transcription.warning("relay transcription append rejected session_id=\(DockLog.publicID(self.id), privacy: .public) reason=invalid_sequence sequence=\(sequence, privacy: .public) last_sequence=\(self.lastSequence, privacy: .public)")
            throw RelayRealtimeTranscriptionClientError.invalidSequence
        }

        let startedAt = Date()
        let response: AudioTranscriptionAppendResponseDTO
        do {
            response = try await client.audioTranscriptionAppend(
                params: AudioTranscriptionAppendParams(
                    sessionId: id,
                    sequence: sequence,
                    base64Audio: chunk.base64EncodedString()
                ),
                timeout: CodexDockConstants.Voice.transcriptionCommandTimeout,
                observabilityContext: AppServerRequestObservabilityContext(
                    configuredHostID: configuredHostID,
                    route: AppServerMethods.audioTranscriptionAppend,
                    store: observabilityStore
                )
            )
        } catch {
            DockLog.transcription.error("relay transcription append failed session_id=\(DockLog.publicID(self.id), privacy: .public) sequence=\(sequence, privacy: .public) bytes=\(chunk.count, privacy: .public) last_sequence=\(self.lastSequence, privacy: .public) max_bytes=\(self.maxChunkBytes, privacy: .public) duration_ms=\(DockLog.milliseconds(since: startedAt), privacy: .public) error=\(DockLog.errorSummary(error), privacy: .public)")
            throw error
        }
        try validate(responseSessionID: response.sessionId)
        guard response.acceptedSequence == sequence else {
            DockLog.transcription.warning("relay transcription append accepted wrong sequence session_id=\(DockLog.publicID(self.id), privacy: .public) sequence=\(sequence, privacy: .public) accepted=\(response.acceptedSequence, privacy: .public)")
            throw RelayRealtimeTranscriptionClientError.invalidSequence
        }
        lastSequence = response.acceptedSequence
        appendedChunks += 1
        appendedBytes += chunk.count
        DockLog.transcription.debug("relay transcription append accepted session_id=\(DockLog.publicID(self.id), privacy: .public) sequence=\(sequence, privacy: .public) bytes=\(chunk.count, privacy: .public) appended_chunks=\(self.appendedChunks, privacy: .public) appended_bytes=\(self.appendedBytes, privacy: .public) duration_ms=\(DockLog.milliseconds(since: startedAt), privacy: .public)")
    }

    func commit() async throws {
        guard !isClosed else {
            DockLog.transcription.warning("relay transcription commit rejected session_id=\(DockLog.publicID(self.id), privacy: .public) reason=session_closed")
            throw RelayRealtimeTranscriptionClientError.sessionClosed
        }
        let startedAt = Date()
        DockLog.transcription.notice("relay transcription commit requested session_id=\(DockLog.publicID(self.id), privacy: .public) last_sequence=\(self.lastSequence, privacy: .public) appended_chunks=\(self.appendedChunks, privacy: .public) appended_bytes=\(self.appendedBytes, privacy: .public) zero_audio=\((self.appendedChunks == 0), privacy: .public)")
        let response: AudioTranscriptionCommitResponseDTO
        do {
            response = try await client.audioTranscriptionCommit(
                params: AudioTranscriptionCommitParams(sessionId: id),
                timeout: CodexDockConstants.Voice.transcriptionCommandTimeout,
                observabilityContext: AppServerRequestObservabilityContext(
                    configuredHostID: configuredHostID,
                    route: AppServerMethods.audioTranscriptionCommit,
                    store: observabilityStore
                )
            )
        } catch {
            DockLog.transcription.error("relay transcription commit failed session_id=\(DockLog.publicID(self.id), privacy: .public) last_sequence=\(self.lastSequence, privacy: .public) appended_chunks=\(self.appendedChunks, privacy: .public) appended_bytes=\(self.appendedBytes, privacy: .public) duration_ms=\(DockLog.milliseconds(since: startedAt), privacy: .public) error=\(DockLog.errorSummary(error), privacy: .public)")
            throw error
        }
        try validate(responseSessionID: response.sessionId)
        didCommit = true
        startCompletionTimeout()
        DockLog.transcription.notice("relay transcription commit accepted session_id=\(DockLog.publicID(self.id), privacy: .public) appended_chunks=\(self.appendedChunks, privacy: .public) appended_bytes=\(self.appendedBytes, privacy: .public) duration_ms=\(DockLog.milliseconds(since: startedAt), privacy: .public)")
    }

    func cancel() async {
        guard !isClosed else {
            return
        }
        DockLog.transcription.notice("relay transcription cancel requested session_id=\(DockLog.publicID(self.id), privacy: .public)")
        _ = try? await client.audioTranscriptionCancel(
            params: AudioTranscriptionCancelParams(sessionId: id),
            timeout: CodexDockConstants.Voice.transcriptionCancelTimeout,
            observabilityContext: AppServerRequestObservabilityContext(
                configuredHostID: configuredHostID,
                route: AppServerMethods.audioTranscriptionCancel,
                store: observabilityStore
            )
        )
        continuation.yield(.canceled(sessionID: id))
        continuation.yield(.closed(sessionID: id))
        await finish(disconnect: true)
    }

    private func startNotificationObservation() {
        notificationTask?.cancel()
        notificationTask = Task { [weak self, client] in
            for await notification in client.notifications {
                await self?.handle(notification)
            }
            await self?.handleNotificationStreamEnded()
        }
    }

    private func handle(_ notification: JSONRPCNotification) async {
        guard !isClosed else {
            return
        }
        if notification.method.hasPrefix("audio/transcription/") {
            await observabilityStore.recordPassive(
                route: notification.method,
                configuredHostID: configuredHostID
            )
        }

        switch notification.method {
        case AppServerMethods.audioTranscriptionDelta:
            guard let dto = decoded(
                AudioTranscriptionDeltaNotificationDTO.self,
                from: notification
            ) else {
                DockLog.transcription.warning("relay transcription invalid delta event session_id=\(DockLog.publicID(self.id), privacy: .public)")
                await failAndClose(code: "invalid_relay_event", message: "Realtime transcription relay event could not be read.")
                return
            }
            guard dto.sessionId == id else {
                DockLog.transcription.debug("relay transcription ignored delta wrong_session expected=\(DockLog.publicID(self.id), privacy: .public) actual=\(DockLog.publicID(dto.sessionId), privacy: .public)")
                return
            }
            DockLog.transcription.debug("relay transcription delta event session_id=\(DockLog.publicID(dto.sessionId), privacy: .public) item_id=\(DockLog.publicID(dto.itemId), privacy: .public) content_index=\(dto.contentIndex ?? -1, privacy: .public) partial_characters=\(dto.partialText.count, privacy: .public) last_sequence=\(self.lastSequence, privacy: .public) did_commit=\(self.didCommit, privacy: .public)")
            continuation.yield(
                .delta(
                    sessionID: dto.sessionId,
                    itemID: dto.itemId,
                    sequence: dto.contentIndex,
                    deltaText: dto.deltaText,
                    partialText: dto.partialText
                )
            )

        case AppServerMethods.audioTranscriptionCompleted:
            guard let dto = decoded(
                AudioTranscriptionCompletedNotificationDTO.self,
                from: notification
            ) else {
                DockLog.transcription.warning("relay transcription invalid completed event session_id=\(DockLog.publicID(self.id), privacy: .public)")
                await failAndClose(code: "invalid_relay_event", message: "Realtime transcription relay event could not be read.")
                return
            }
            guard dto.sessionId == id else {
                DockLog.transcription.debug("relay transcription ignored completed wrong_session expected=\(DockLog.publicID(self.id), privacy: .public) actual=\(DockLog.publicID(dto.sessionId), privacy: .public)")
                return
            }
            DockLog.transcription.notice("relay transcription completed event session_id=\(DockLog.publicID(dto.sessionId), privacy: .public) item_id=\(DockLog.publicID(dto.itemId), privacy: .public) characters=\(dto.transcript.count, privacy: .public) last_sequence=\(self.lastSequence, privacy: .public) did_commit=\(self.didCommit, privacy: .public)")
            continuation.yield(
                .completed(
                    sessionID: dto.sessionId,
                    itemID: dto.itemId,
                    text: dto.transcript
                )
            )
            continuation.yield(.closed(sessionID: id))
            await finish(disconnect: true)

        case AppServerMethods.audioTranscriptionFailed:
            guard let dto = decoded(
                AudioTranscriptionFailedNotificationDTO.self,
                from: notification
            ) else {
                DockLog.transcription.warning("relay transcription invalid failed event session_id=\(DockLog.publicID(self.id), privacy: .public)")
                await failAndClose(code: "invalid_relay_event", message: "Realtime transcription relay event could not be read.")
                return
            }
            guard dto.sessionId == id else {
                DockLog.transcription.debug("relay transcription ignored failed wrong_session expected=\(DockLog.publicID(self.id), privacy: .public) actual=\(DockLog.publicID(dto.sessionId), privacy: .public)")
                return
            }
            DockLog.transcription.warning("relay transcription failed event session_id=\(DockLog.publicID(dto.sessionId), privacy: .public) reason=\(dto.reason, privacy: .public) last_sequence=\(self.lastSequence, privacy: .public) did_commit=\(self.didCommit, privacy: .public)")
            await failAndClose(code: dto.reason, message: userMessage(for: dto.reason))

        case AppServerMethods.audioTranscriptionCanceled:
            guard let dto = decoded(
                AudioTranscriptionCanceledNotificationDTO.self,
                from: notification
            ) else {
                DockLog.transcription.warning("relay transcription invalid canceled event session_id=\(DockLog.publicID(self.id), privacy: .public)")
                await failAndClose(code: "invalid_relay_event", message: "Realtime transcription relay event could not be read.")
                return
            }
            guard dto.sessionId == id else {
                return
            }
            continuation.yield(.canceled(sessionID: id))
            continuation.yield(.closed(sessionID: id))
            DockLog.transcription.notice("relay transcription canceled event session_id=\(DockLog.publicID(self.id), privacy: .public) last_sequence=\(self.lastSequence, privacy: .public) did_commit=\(self.didCommit, privacy: .public)")
            await finish(disconnect: true)

        case AppServerMethods.audioTranscriptionClosed:
            guard let dto = decoded(
                AudioTranscriptionClosedNotificationDTO.self,
                from: notification
            ) else {
                DockLog.transcription.warning("relay transcription invalid closed event session_id=\(DockLog.publicID(self.id), privacy: .public)")
                await failAndClose(code: "invalid_relay_event", message: "Realtime transcription relay event could not be read.")
                return
            }
            guard dto.sessionId == id else {
                return
            }
            continuation.yield(.closed(sessionID: id))
            DockLog.transcription.notice("relay transcription closed event session_id=\(DockLog.publicID(self.id), privacy: .public) last_sequence=\(self.lastSequence, privacy: .public) did_commit=\(self.didCommit, privacy: .public)")
            await finish(disconnect: true)

        default:
            return
        }
    }

    private func handleNotificationStreamEnded() async {
        guard !isClosed else {
            return
        }
        await failAndClose(
            code: "connection_closed",
            message: "Realtime transcription connection closed."
        )
        DockLog.transcription.warning("relay transcription notification stream ended session_id=\(DockLog.publicID(self.id), privacy: .public) last_sequence=\(self.lastSequence, privacy: .public) did_commit=\(self.didCommit, privacy: .public)")
    }

    private func startCompletionTimeout() {
        completionTimeoutTask?.cancel()
        let completionTimeout = completionTimeout
        completionTimeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: completionTimeout)
            } catch {
                return
            }
            await self?.handleCompletionTimeout()
        }
    }

    private func handleCompletionTimeout() async {
        DockLog.transcription.warning("relay transcription completion timeout session_id=\(DockLog.publicID(self.id), privacy: .public) last_sequence=\(self.lastSequence, privacy: .public) appended_chunks=\(self.appendedChunks, privacy: .public) appended_bytes=\(self.appendedBytes, privacy: .public) did_commit=\(self.didCommit, privacy: .public)")
        await failAndClose(
            code: "commit_timeout",
            message: "Realtime transcription timed out."
        )
    }

    private func failAndClose(code: String, message: String) async {
        guard !isClosed else {
            return
        }
        continuation.yield(.failed(sessionID: id, code: code, message: message))
        continuation.yield(.closed(sessionID: id))
        DockLog.transcription.warning("relay transcription failed and closing session_id=\(DockLog.publicID(self.id), privacy: .public) code=\(code, privacy: .public) last_sequence=\(self.lastSequence, privacy: .public) appended_chunks=\(self.appendedChunks, privacy: .public) appended_bytes=\(self.appendedBytes, privacy: .public) did_commit=\(self.didCommit, privacy: .public)")
        await finish(disconnect: true)
    }

    private func finish(disconnect: Bool) async {
        guard !isClosed else {
            return
        }
        isClosed = true
        completionTimeoutTask?.cancel()
        completionTimeoutTask = nil
        notificationTask?.cancel()
        notificationTask = nil
        continuation.finish()
        if disconnect {
            await client.disconnect()
        }
        DockLog.transcription.notice("relay transcription session finished session_id=\(DockLog.publicID(self.id), privacy: .public) disconnect=\(disconnect, privacy: .public) last_sequence=\(self.lastSequence, privacy: .public) appended_chunks=\(self.appendedChunks, privacy: .public) appended_bytes=\(self.appendedBytes, privacy: .public) did_commit=\(self.didCommit, privacy: .public)")
    }

    private func validate(responseSessionID: String) throws {
        if responseSessionID != id {
            DockLog.transcription.warning("relay transcription unexpected session expected=\(DockLog.publicID(self.id), privacy: .public) actual=\(DockLog.publicID(responseSessionID), privacy: .public)")
            throw RelayRealtimeTranscriptionClientError.unexpectedSession(
                expected: id,
                actual: responseSessionID
            )
        }
    }

    private func decoded<T: Decodable>(
        _ type: T.Type,
        from notification: JSONRPCNotification
    ) -> T? {
        guard let params = notification.params else {
            return nil
        }
        return try? params.decoded(as: type)
    }

    private func userMessage(for reason: String) -> String {
        switch reason {
        case "commit_timeout":
            return "Realtime transcription timed out."
        case "connection_closed", "downstream_closed":
            return "Realtime transcription connection closed."
        case "missing_api_key":
            return "Realtime transcription key is not configured on the relay."
        default:
            return "Realtime transcription stopped."
        }
    }
}

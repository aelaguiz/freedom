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
    private let makeClient: @Sendable (DockHostConfiguration) -> AppServerClient

    public init(
        host: DockHostConfiguration,
        completionTimeout: Duration = .seconds(30),
        maxChunkBytes: Int = 64 * 1024,
        makeClient: @escaping @Sendable (DockHostConfiguration) -> AppServerClient = {
            AppServerClient(webSocketURL: $0.webSocketURL, bearerToken: nil)
        }
    ) {
        self.host = host
        self.completionTimeout = completionTimeout
        self.maxChunkBytes = maxChunkBytes
        self.makeClient = makeClient
    }

    public func startSession() async throws -> any RealtimeTranscriptionSession {
        // OpenAI credentials are relay-owned; the phone sends only session and audio controls.
        let client = makeClient(host)
        let startedAt = Date()
        DockLog.transcription.notice("relay transcription session start requested host_id=\(self.host.id, privacy: .public) endpoint=\(DockLog.endpoint(self.host.webSocketURL), privacy: .public)")
        do {
            let connectStartedAt = Date()
            _ = try await client.connectAndInitialize(
                params: .codexDock(version: "0.1.0"),
                timeout: .seconds(5)
            )
            DockLog.transcription.debug("relay transcription client connected host_id=\(self.host.id, privacy: .public) duration_ms=\(DockLog.milliseconds(since: connectStartedAt), privacy: .public)")
            let startStartedAt = Date()
            let response = try await client.audioTranscriptionStart(
                params: AudioTranscriptionStartParams(),
                timeout: .seconds(10)
            )
            DockLog.transcription.notice("relay transcription session started host_id=\(self.host.id, privacy: .public) session_id=\(DockLog.publicID(response.sessionId), privacy: .public) model=\(DockLog.publicID(response.model), privacy: .public) language=\(DockLog.publicID(response.language), privacy: .public) delay=\(DockLog.publicID(response.delay), privacy: .public) start_duration_ms=\(DockLog.milliseconds(since: startStartedAt), privacy: .public) duration_ms=\(DockLog.milliseconds(since: startedAt), privacy: .public)")
            return RelayRealtimeTranscriptionSession(
                client: client,
                startResponse: response,
                completionTimeout: completionTimeout,
                maxChunkBytes: maxChunkBytes
            )
        } catch {
            await client.disconnect()
            DockLog.transcription.error("relay transcription session start failed host_id=\(self.host.id, privacy: .public) duration_ms=\(DockLog.milliseconds(since: startedAt), privacy: .public) error=\(DockLog.errorSummary(error), privacy: .public)")
            throw error
        }
    }
}

@MainActor
private final class RelayRealtimeTranscriptionSession: RealtimeTranscriptionSession {
    let id: String
    let events: AsyncStream<RealtimeTranscriptionEvent>

    private let client: AppServerClient
    private let completionTimeout: Duration
    private let maxChunkBytes: Int
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
        startResponse: AudioTranscriptionStartResponseDTO,
        completionTimeout: Duration,
        maxChunkBytes: Int
    ) {
        self.id = startResponse.sessionId
        self.client = client
        self.completionTimeout = completionTimeout
        self.maxChunkBytes = maxChunkBytes
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
                timeout: .seconds(10)
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
                timeout: .seconds(10)
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
            timeout: .seconds(5)
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

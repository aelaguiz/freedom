import Foundation

struct ThreadDetailProjectionStreamConnector: ProjectionStreamConnecting {
    private let session: any ThreadDetailSession
    private let threadID: String

    init(session: any ThreadDetailSession, threadID: String) {
        self.session = session
        self.threadID = threadID
    }

    func connect() async throws -> any ProjectionStreamConnection<ThreadDetailEventDTO> {
        _ = try await session.connectAndInitialize(
            params: .codexDock(version: "0.1.0"),
            timeout: CodexDockConstants.AppServer.connectInitializeTimeout
        )
        return ThreadDetailProjectionStreamConnection(
            session: session,
            threadID: threadID
        )
    }
}

final class ThreadDetailProjectionStreamConnection: ProjectionStreamConnection, @unchecked Sendable {
    private let session: any ThreadDetailSession
    private let threadID: String
    private let updateStream: AsyncThrowingStream<ProjectionEnvelope<ThreadDetailEventDTO>, Error>
    private let updateContinuation: AsyncThrowingStream<ProjectionEnvelope<ThreadDetailEventDTO>, Error>.Continuation
    private var notificationTask: Task<Void, Never>?

    init(session: any ThreadDetailSession, threadID: String) {
        self.session = session
        self.threadID = threadID
        let stream = AsyncThrowingStream<ProjectionEnvelope<ThreadDetailEventDTO>, Error>.makeStream()
        self.updateStream = stream.stream
        self.updateContinuation = stream.continuation
        self.notificationTask = Task { [session, updateContinuation] in
            for await notification in session.notifications {
                guard notification.method == AppServerMethods.threadDetailUpdate else {
                    continue
                }
                do {
                    guard let params = notification.params else {
                        continue
                    }
                    let update = try params.decoded(as: ThreadDetailUpdateDTO.self)
                    updateContinuation.yield(ProjectionEnvelope(update: update))
                } catch {
                    updateContinuation.finish(throwing: AppServerClientError.responseDecoding(error.localizedDescription))
                    return
                }
            }
            updateContinuation.finish()
        }
    }

    deinit {
        notificationTask?.cancel()
        updateContinuation.finish()
    }

    func subscribe() async throws -> ProjectionEnvelope<ThreadDetailEventDTO> {
        let snapshot = try await session.threadDetailSubscribe(
            params: ThreadDetailParams(threadId: threadID),
            timeout: CodexDockConstants.AppServer.defaultRequestTimeout
        )
        return ProjectionEnvelope(snapshot: snapshot)
    }

    func resync(reason _: StreamReconcilerRecoveryReason) async throws -> ProjectionEnvelope<ThreadDetailEventDTO> {
        let snapshot = try await session.threadDetailResync(
            params: ThreadDetailParams(threadId: threadID),
            timeout: CodexDockConstants.AppServer.defaultRequestTimeout
        )
        return ProjectionEnvelope(snapshot: snapshot)
    }

    func updates() -> AsyncThrowingStream<ProjectionEnvelope<ThreadDetailEventDTO>, Error> {
        updateStream
    }

    func close() async {
        notificationTask?.cancel()
        updateContinuation.finish()
        await session.disconnect()
    }
}

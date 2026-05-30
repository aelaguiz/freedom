import Foundation

public actor RenderCoalescer<Snapshot: Sendable> {
    public let snapshots: AsyncStream<Snapshot>

    private let continuation: AsyncStream<Snapshot>.Continuation
    private var latestAcceptedRevision: RenderRevision?

    public init(
        bufferingNewest: Int = CodexDockConstants.Rendering.renderStreamBufferNewest
    ) {
        let stream = AsyncStream.makeStream(
            of: Snapshot.self,
            bufferingPolicy: .bufferingNewest(bufferingNewest)
        )
        self.snapshots = stream.stream
        self.continuation = stream.continuation
    }

    public func submit(_ snapshot: Snapshot, revision: RenderRevision) {
        if let latestAcceptedRevision,
           revision < latestAcceptedRevision {
            return
        }

        latestAcceptedRevision = revision
        continuation.yield(snapshot)
    }

    public func stream() -> AsyncStream<Snapshot> {
        snapshots
    }

    public func latestRevision() -> RenderRevision? {
        latestAcceptedRevision
    }

    public func finish() {
        continuation.finish()
    }
}

import Foundation

public enum ConnectivityRuntimeEventSource: String, Equatable, Sendable {
    case bootstrap
    case dock
    case threadDetail
    case archive
    case hosts
    case command
    case relayDiagnostics
}

public struct ConnectivityRuntimeEvent: Equatable, Sendable {
    public let source: ConnectivityRuntimeEventSource
    public let hostID: String?
    public let route: String
    public let status: String
    public let phase: HostConnectivityPhase?
    public let recordedAt: Date

    public init(
        source: ConnectivityRuntimeEventSource,
        hostID: String? = nil,
        route: String,
        status: String,
        phase: HostConnectivityPhase? = nil,
        recordedAt: Date = Date()
    ) {
        self.source = source
        self.hostID = hostID
        self.route = route
        self.status = status
        self.phase = phase
        self.recordedAt = recordedAt
    }
}

public protocol ConnectivityEventSinking: Sendable {
    func record(_ event: ConnectivityRuntimeEvent) async
}

public actor ConnectivityEventSink: ConnectivityEventSinking {
    private var events: [ConnectivityRuntimeEvent] = []
    private var continuations: [UUID: AsyncStream<ConnectivityRuntimeEvent>.Continuation] = [:]

    public init() {}

    public func record(_ event: ConnectivityRuntimeEvent) {
        events.append(event)
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }

    public func snapshot() -> [ConnectivityRuntimeEvent] {
        events
    }

    public func drain() -> [ConnectivityRuntimeEvent] {
        let drained = events
        events.removeAll(keepingCapacity: true)
        return drained
    }

    public func makeStream() -> AsyncStream<ConnectivityRuntimeEvent> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(CodexDockConstants.Rendering.renderStreamBufferNewest)) { continuation in
            self.addContinuation(continuation, id: id)
            continuation.onTermination = { _ in
                Task { await self.removeContinuation(id: id) }
            }
        }
    }

    public func makeStreamDrainingBacklog() -> (
        stream: AsyncStream<ConnectivityRuntimeEvent>,
        backlog: [ConnectivityRuntimeEvent]
    ) {
        let stream = makeStream()
        let backlog = events
        events.removeAll(keepingCapacity: true)
        return (stream, backlog)
    }

    private func addContinuation(
        _ continuation: AsyncStream<ConnectivityRuntimeEvent>.Continuation,
        id: UUID
    ) {
        continuations[id] = continuation
    }

    private func removeContinuation(id: UUID) {
        continuations[id]?.finish()
        continuations[id] = nil
    }
}

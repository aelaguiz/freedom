import Foundation

public struct ThreadDetailDataSnapshot: Equatable, Sendable {
    public let events: [ThreadEvent]
    public let activeTurnID: String?

    public init(events: [ThreadEvent], activeTurnID: String?) {
        self.events = events
        self.activeTurnID = activeTurnID
    }
}

public actor ThreadDetailDataEngine {
    private var index = ThreadEventIndex()
    private var activeTurnID: String?

    public init() {}

    public func replace(
        from thread: ThreadDTO,
        expectedThreadID: String
    ) throws -> ThreadDetailDataSnapshot {
        try validate(thread: thread, expectedThreadID: expectedThreadID)
        let signpostState = DockSignpost.rendering.beginInterval(RenderSignpostName.threadModelNormalize)
        let events = ThreadEventNormalizer.events(from: thread)
        DockSignpost.rendering.endInterval(RenderSignpostName.threadModelNormalize, signpostState)
        index.replace(with: events)
        activeTurnID = Self.activeTurnID(from: thread)
        return snapshot()
    }

    public func merge(
        from thread: ThreadDTO,
        expectedThreadID: String
    ) throws -> ThreadDetailDataSnapshot {
        try validate(thread: thread, expectedThreadID: expectedThreadID)
        let signpostState = DockSignpost.rendering.beginInterval(RenderSignpostName.threadModelNormalize)
        let events = ThreadEventNormalizer.events(from: thread)
        DockSignpost.rendering.endInterval(RenderSignpostName.threadModelNormalize, signpostState)
        for event in events {
            index.appendOrMerge(event)
        }
        activeTurnID = Self.activeTurnID(from: thread)
        return snapshot()
    }

    public func apply(
        notification: JSONRPCNotification,
        expectedThreadID: String,
        now: Date
    ) -> ThreadDetailDataSnapshot? {
        guard ThreadEventNormalizer.threadId(from: notification) == expectedThreadID else {
            return nil
        }
        updateActiveTurn(from: notification)
        if let event = ThreadEventNormalizer.event(from: notification, now: now) {
            index.appendOrMerge(event)
        }
        return snapshot()
    }

    public func apply(
        request: JSONRPCRequest,
        expectedThreadID: String,
        now: Date
    ) -> ThreadDetailDataSnapshot? {
        guard ThreadEventNormalizer.threadId(from: request) == expectedThreadID else {
            return nil
        }
        index.appendOrMerge(ThreadEventNormalizer.event(from: request, now: now))
        return snapshot()
    }

    public func setActiveTurnID(_ activeTurnID: String?) {
        self.activeTurnID = activeTurnID
    }

    public func currentSnapshot() -> ThreadDetailDataSnapshot {
        snapshot()
    }

    private func snapshot() -> ThreadDetailDataSnapshot {
        ThreadDetailDataSnapshot(
            events: index.eventsNewestFirst(),
            activeTurnID: activeTurnID
        )
    }

    private func validate(thread: ThreadDTO, expectedThreadID: String) throws {
        guard thread.id == expectedThreadID else {
            throw ThreadDetailStoreError.threadMismatch(
                expected: expectedThreadID,
                actual: thread.id ?? "missing"
            )
        }
    }

    private func updateActiveTurn(from notification: JSONRPCNotification) {
        guard let params = notification.params?.objectValue else {
            return
        }

        switch notification.method {
        case "turn/started":
            if let turn = params["turn"] {
                activeTurnID = Self.turnID(from: turn)
            }
        case "turn/completed":
            if let turn = params["turn"], activeTurnID == Self.turnID(from: turn) {
                activeTurnID = nil
            }
        default:
            return
        }
    }

    private static func activeTurnID(from thread: ThreadDTO) -> String? {
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

    private static func turnID(from turn: JSONValue) -> String? {
        turn.objectValue?["id"]?.stringValue
    }
}

struct ThreadEventIndex: Sendable {
    private var events: [ThreadEvent] = []

    mutating func replace(with events: [ThreadEvent]) {
        self.events = ThreadEventDisplayOrder.newestFirst(events)
    }

    mutating func appendOrMerge(_ event: ThreadEvent) {
        guard let index = events.firstIndex(where: { $0.id == event.id }) else {
            appendOrMergeByStreamItem(event)
            return
        }

        let mergedEvent: ThreadEvent
        if events[index].isStreamingDelta, event.isStreamingDelta, events[index].kind == event.kind {
            mergedEvent = events[index].mergingStreamingDelta(event)
        } else {
            mergedEvent = event
        }
        events.remove(at: index)
        insertInOrder(mergedEvent)
    }

    func eventsNewestFirst() -> [ThreadEvent] {
        events
    }

    private mutating func appendOrMergeByStreamItem(_ event: ThreadEvent) {
        guard let mergeKey = ThreadEventStreamMergeKey(event),
              let index = events.firstIndex(where: { ThreadEventStreamMergeKey($0) == mergeKey }) else {
            insertInOrder(event)
            return
        }

        let existing = events[index]
        let mergedEvent: ThreadEvent?
        if existing.isStreamingDelta, event.isStreamingDelta, existing.kind == event.kind {
            mergedEvent = existing.mergingStreamingDelta(event)
        } else if existing.isStreamingDelta || !event.isStreamingDelta {
            mergedEvent = event
        } else {
            // Ignore late deltas after a full item snapshot has already arrived.
            mergedEvent = nil
        }

        guard let mergedEvent else {
            return
        }
        events.remove(at: index)
        insertInOrder(mergedEvent)
    }

    private mutating func insertInOrder(_ event: ThreadEvent) {
        guard let index = events.firstIndex(where: { existing in
            ThreadEventDisplayOrder.shouldPrecedeInNewestFirstOrder(event, existing)
        }) else {
            events.append(event)
            return
        }
        events.insert(event, at: index)
    }
}

private struct ThreadEventStreamMergeKey: Equatable {
    let turnID: String
    let itemID: String
    let kind: ThreadEventKind
    let visibility: ThreadEventVisibilityCategory

    init?(_ event: ThreadEvent) {
        guard let turnID = event.turnID,
              let itemID = event.itemID else {
            return nil
        }
        switch event.visibilityCategory {
        case .message, .thinking, .tooling:
            self.turnID = turnID
            self.itemID = itemID
            self.kind = event.kind
            self.visibility = event.visibilityCategory
        case .request, .system, .unknown:
            return nil
        }
    }
}

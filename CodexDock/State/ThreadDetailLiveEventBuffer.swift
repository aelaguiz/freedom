import Foundation

enum ThreadDetailBufferedLiveEvent {
    case notification(JSONRPCNotification)
}

struct ThreadDetailLiveEventBuffer {
    private(set) var isBuffering = false
    private var events: [ThreadDetailBufferedLiveEvent] = []

    var isEmpty: Bool {
        events.isEmpty
    }

    mutating func begin() {
        // Live deltas wait behind canonical history rebuilds so reconnect
        // cannot make Thread Detail look live while it still shows stale rows.
        isBuffering = true
        events.removeAll()
    }

    mutating func discard() {
        isBuffering = false
        events.removeAll()
    }

    mutating func append(notification: JSONRPCNotification) {
        events.append(.notification(notification))
    }

    mutating func takeBatch() -> [ThreadDetailBufferedLiveEvent]? {
        guard !events.isEmpty else {
            return nil
        }
        let batch = events
        events.removeAll()
        return batch
    }

    mutating func finishReplay() {
        isBuffering = false
    }
}

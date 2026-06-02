import Foundation

public enum ThreadEventKind: String, Codable, Equatable, Sendable, CaseIterable {
    case userMessage
    case agentMessage
    case command
    case output
    case request
    case system
    case unknown

    public var label: String {
        switch self {
        case .userMessage:
            return "User"
        case .agentMessage:
            return "Agent"
        case .command:
            return "Command"
        case .output:
            return "Output"
        case .request:
            return "Request"
        case .system:
            return "System"
        case .unknown:
            return "Unknown"
        }
    }
}

public enum ThreadEventVisibilityCategory: String, Codable, Equatable, Sendable, CaseIterable {
    case message
    case thinking
    case tooling
    case request
    case system
    case unknown
}

public struct ThreadEvent: Equatable, Identifiable, Sendable {
    public let id: String
    public let kind: ThreadEventKind
    public let visibilityCategory: ThreadEventVisibilityCategory
    public var title: String
    public var body: String
    public let date: Date?
    public let isLive: Bool
    public let turnID: String?
    public let itemID: String?
    public let turnSequence: Int?
    public let itemSequence: Int?
    public let eventSequence: Int?
    public let displayOrderKey: String
    /// Display grouping fallback. New ordering logic should prefer `activityDate`.
    public let displayGroupDate: Date?
    /// Semantic activity time used for newest-first thread detail ordering.
    public let activityDate: Date?
    public let isStreamingDelta: Bool
    public let request: ThreadDetailEventRequestDTO?

    public init(
        id: String,
        kind: ThreadEventKind,
        visibilityCategory: ThreadEventVisibilityCategory = .unknown,
        title: String,
        body: String,
        date: Date? = nil,
        isLive: Bool = false,
        turnID: String? = nil,
        itemID: String? = nil,
        turnSequence: Int? = nil,
        itemSequence: Int? = nil,
        eventSequence: Int? = nil,
        displayOrderKey: String,
        displayGroupDate: Date? = nil,
        activityDate: Date? = nil,
        isStreamingDelta: Bool = false,
        request: ThreadDetailEventRequestDTO? = nil
    ) {
        self.id = id
        self.kind = kind
        self.visibilityCategory = visibilityCategory
        self.title = title
        self.body = body
        self.date = date
        self.isLive = isLive
        self.turnID = turnID
        self.itemID = itemID
        self.turnSequence = turnSequence
        self.itemSequence = itemSequence
        self.eventSequence = eventSequence
        self.displayOrderKey = displayOrderKey
        self.displayGroupDate = displayGroupDate ?? date
        self.activityDate = activityDate
        self.isStreamingDelta = isStreamingDelta
        self.request = request
    }

    public init(detailEvent dto: ThreadDetailEventDTO) {
        let activityDate = Self.date(from: dto.activityTime ?? dto.eventTime)
        self.init(
            id: dto.projectionID,
            kind: dto.renderKind,
            visibilityCategory: dto.visibility,
            title: dto.title,
            body: dto.body,
            date: activityDate,
            isLive: dto.renderState == .live || dto.renderState == .streaming,
            turnID: dto.turnID,
            itemID: dto.itemID,
            turnSequence: dto.turnOrder,
            itemSequence: dto.itemOrder,
            eventSequence: dto.rowOrder,
            displayOrderKey: dto.displayOrderKey,
            displayGroupDate: activityDate,
            activityDate: activityDate,
            isStreamingDelta: dto.renderState == .streaming,
            request: dto.request
        )
    }

    private static func date(from isoString: String?) -> Date? {
        guard let isoString else {
            return nil
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: isoString) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: isoString)
    }

    func mergingStreamingDelta(_ delta: ThreadEvent) -> ThreadEvent {
        ThreadEvent(
            id: id,
            kind: kind,
            visibilityCategory: visibilityCategory,
            title: title,
            body: body + delta.body,
            date: delta.date ?? date,
            isLive: isLive || delta.isLive,
            turnID: turnID,
            itemID: itemID,
            turnSequence: turnSequence,
            itemSequence: itemSequence,
            eventSequence: eventSequence,
            displayOrderKey: displayOrderKey,
            displayGroupDate: delta.displayGroupDate ?? displayGroupDate,
            activityDate: ThreadMessageSemantics.activityDate(for: delta)
                ?? ThreadMessageSemantics.activityDate(for: self),
            isStreamingDelta: isStreamingDelta,
            request: request
        )
    }
}

public enum ThreadDetailMessageFilter: Equatable, Sendable, Identifiable, CaseIterable {
    case messages
    case all
    case kind(ThreadEventKind)

    public static var allCases: [ThreadDetailMessageFilter] {
        [.messages, .all] + ThreadEventKind.allCases.map(ThreadDetailMessageFilter.kind)
    }

    public static let `default`: ThreadDetailMessageFilter = .messages

    public var id: String {
        switch self {
        case .messages:
            return "messages"
        case .all:
            return "all"
        case .kind(let kind):
            return kind.rawValue
        }
    }

    public func includes(_ event: ThreadEvent) -> Bool {
        switch self {
        case .messages:
            return ThreadMessageSemantics.isDefaultVisibleMessage(event)
        case .all:
            return true
        case .kind(let kind):
            return event.kind == kind
        }
    }

    public func visibleEvents(from events: [ThreadEvent]) -> [ThreadEvent] {
        ThreadEventDisplayOrder.newestFirst(events.filter { includes($0) })
    }
}

public enum ThreadMessageSemantics {
    public static func isDefaultVisibleMessage(_ event: ThreadEvent) -> Bool {
        event.request != nil
            || event.visibilityCategory == .request
            || (
                event.visibilityCategory == .message
                    && (event.kind == .userMessage || event.kind == .agentMessage)
            )
    }

    public static func latestMessage(in events: [ThreadEvent]) -> ThreadEvent? {
        ThreadEventDisplayOrder.newestFirst(events.filter(isDefaultVisibleMessage)).first
    }

    public static func activityDate(for event: ThreadEvent) -> Date? {
        event.activityDate ?? event.displayGroupDate ?? event.date
    }
}

public enum ThreadEventDisplayOrder {
    public static func newestFirst(_ events: [ThreadEvent]) -> [ThreadEvent] {
        let indexed = events.enumerated().map { offset, event in
            IndexedEvent(offset: offset, event: event)
        }

        return indexed.sorted(by: areInNewestFirstOrder).map(\.event)
    }

    static func shouldPrecedeInNewestFirstOrder(_ left: ThreadEvent, _ right: ThreadEvent) -> Bool {
        areInNewestFirstOrder(
            IndexedEvent(offset: 0, event: left),
            IndexedEvent(offset: 1, event: right)
        )
    }

    private static func areInNewestFirstOrder(_ left: IndexedEvent, _ right: IndexedEvent) -> Bool {
        let leftKey = left.event.displayOrderKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let rightKey = right.event.displayOrderKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if leftKey != rightKey {
            if leftKey.isEmpty {
                return false
            }
            if rightKey.isEmpty {
                return true
            }
            return leftKey < rightKey
        }

        // Thread Detail rows are projection rows. Visible order is the relay
        // displayOrderKey, then projectionID. Do not recover order locally
        // from timestamps, turn order, item order, or row order.
        if left.event.id != right.event.id {
            return left.event.id < right.event.id
        }

        return left.offset < right.offset
    }

    private struct IndexedEvent {
        let offset: Int
        let event: ThreadEvent
    }
}

public extension JSONValue {
    var objectValue: [String: JSONValue]? {
        guard case .object(let value) = self else {
            return nil
        }
        return value
    }

    var arrayValue: [JSONValue]? {
        guard case .array(let value) = self else {
            return nil
        }
        return value
    }

    var stringValue: String? {
        guard case .string(let value) = self else {
            return nil
        }
        return value
    }

    var numberValue: Double? {
        switch self {
        case .integer(let value):
            return Double(value)
        case .double(let value):
            return value
        case .null, .bool, .string, .array, .object:
            return nil
        }
    }
}

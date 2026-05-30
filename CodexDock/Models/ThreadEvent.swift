import Foundation

public enum ThreadEventKind: String, Equatable, Sendable, CaseIterable {
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

public enum ThreadEventVisibilityCategory: String, Equatable, Sendable, CaseIterable {
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
    public let displayGroupDate: Date?
    public let isStreamingDelta: Bool

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
        displayGroupDate: Date? = nil,
        isStreamingDelta: Bool = false
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
        self.displayGroupDate = displayGroupDate ?? date
        self.isStreamingDelta = isStreamingDelta
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
            return event.visibilityCategory == .message
                && (event.kind == .userMessage || event.kind == .agentMessage)
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

public enum ThreadEventDisplayOrder {
    public static func newestFirst(_ events: [ThreadEvent]) -> [ThreadEvent] {
        let indexed = events.enumerated().map { offset, event in
            IndexedEvent(offset: offset, event: event)
        }

        return indexed.sorted { left, right in
            if let dateOrder = orderedByDateDescending(left.eventDate, right.eventDate) {
                return dateOrder
            }

            let leftTurn = left.event.turnSequence ?? Int.min
            let rightTurn = right.event.turnSequence ?? Int.min
            if leftTurn != rightTurn {
                return leftTurn > rightTurn
            }

            let leftItem = left.event.itemSequence ?? Int.max
            let rightItem = right.event.itemSequence ?? Int.max
            if leftItem != rightItem {
                return leftItem < rightItem
            }
            if left.itemKey != right.itemKey {
                return left.itemKey < right.itemKey
            }

            let leftEvent = left.event.eventSequence ?? Int.max
            let rightEvent = right.event.eventSequence ?? Int.max
            if leftEvent != rightEvent {
                return leftEvent < rightEvent
            }
            if left.event.id != right.event.id {
                return left.event.id < right.event.id
            }

            return left.offset < right.offset
        }.map(\.event)
    }

    private static func orderedByDateDescending(_ left: Date?, _ right: Date?) -> Bool? {
        switch (left, right) {
        case let (left?, right?) where left != right:
            return left > right
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            return nil
        }
    }

    private struct IndexedEvent {
        let offset: Int
        let event: ThreadEvent

        var itemKey: String {
            if let itemID = event.itemID {
                return "item:\(itemID)"
            }
            return "event:\(event.id)"
        }

        var eventDate: Date? {
            event.displayGroupDate ?? event.date
        }
    }
}

public enum ThreadEventNormalizer {
    public static func events(from thread: ThreadDTO) -> [ThreadEvent] {
        let turns = thread.turns ?? []
        return turns.enumerated().flatMap { turnSequence, turn in
            events(fromTurn: turn, turnSequence: turnSequence)
        }
    }

    public static func event(from notification: JSONRPCNotification, now: Date = Date()) -> ThreadEvent? {
        guard let params = notification.params?.objectValue else {
            return nil
        }

        switch notification.method {
        case "item/agentMessage/delta":
            return deltaEvent(
                params: params,
                method: notification.method,
                kind: .agentMessage,
                visibilityCategory: .message,
                title: "Agent update",
                key: "delta",
                now: now
            )
        case "item/plan/delta", "item/reasoning/summaryTextDelta", "item/reasoning/textDelta":
            return deltaEvent(
                params: params,
                method: notification.method,
                kind: .agentMessage,
                visibilityCategory: .thinking,
                title: "Reasoning update",
                key: "delta",
                now: now
            )
        case "item/commandExecution/outputDelta":
            return deltaEvent(
                params: params,
                method: notification.method,
                kind: .output,
                visibilityCategory: .tooling,
                title: "Command output",
                key: "delta",
                now: now
            )
        case "item/started", "item/completed":
            guard let item = params["item"] else {
                return nil
            }
            return events(fromItem: item, turn: params, defaultDate: now, isLive: true).first
        case "thread/status/changed":
            let status = params["status"]?.objectValue?["type"]?.stringValue ?? "updated"
            return ThreadEvent(
                id: "thread-status-\(params["threadId"]?.stringValue ?? "unknown")-\(now.timeIntervalSince1970)",
                kind: .system,
                visibilityCategory: .system,
                title: "Thread status",
                body: status,
                date: now,
                isLive: true,
                displayGroupDate: now
            )
        case "thread/closed":
            return ThreadEvent(
                id: "thread-closed-\(params["threadId"]?.stringValue ?? "unknown")-\(now.timeIntervalSince1970)",
                kind: .system,
                visibilityCategory: .system,
                title: "Thread closed",
                body: "The app-server closed this thread.",
                date: now,
                isLive: true,
                displayGroupDate: now
            )
        default:
            return nil
        }
    }

    public static func event(from request: JSONRPCRequest, now: Date = Date()) -> ThreadEvent {
        let params = request.params?.objectValue ?? [:]
        let body = firstNonEmpty(
            commandText(params["command"]),
            params["reason"]?.stringValue,
            params["message"]?.stringValue,
            request.method
        ) ?? request.method

        return ThreadEvent(
            id: "request-\(request.id)",
            kind: .request,
            visibilityCategory: .request,
            title: requestTitle(for: request.method),
            body: body,
            date: now,
            isLive: true,
            turnID: params["turnId"]?.stringValue,
            itemID: params["itemId"]?.stringValue,
            displayGroupDate: now
        )
    }

    public static func threadId(from notification: JSONRPCNotification) -> String? {
        notification.params?.objectValue?["threadId"]?.stringValue
    }

    public static func threadId(from request: JSONRPCRequest) -> String? {
        request.params?.objectValue?["threadId"]?.stringValue
    }

    private static func events(fromTurn turn: JSONValue, turnSequence: Int?) -> [ThreadEvent] {
        guard let object = turn.objectValue else {
            return [
                ThreadEvent(
                    id: "unknown-turn-\(UUID().uuidString)",
                    kind: .unknown,
                    visibilityCategory: .unknown,
                    title: "Unsupported turn",
                    body: "This turn shape is not supported yet.",
                    turnSequence: turnSequence,
                    eventSequence: 0
                )
            ]
        }

        let defaultDate = date(seconds: object["startedAt"]) ?? date(seconds: object["completedAt"])
        let items = object["items"]?.arrayValue ?? []
        return items.enumerated().flatMap { itemSequence, item in
            events(
                fromItem: item,
                turn: object,
                defaultDate: defaultDate,
                isLive: false,
                turnSequence: turnSequence,
                itemSequence: itemSequence
            )
        }
    }

    private static func events(
        fromItem item: JSONValue,
        turn: [String: JSONValue],
        defaultDate: Date?,
        isLive: Bool,
        turnSequence: Int? = nil,
        itemSequence: Int? = nil
    ) -> [ThreadEvent] {
        guard let object = item.objectValue else {
            return [
                ThreadEvent(
                    id: "unknown-item-\(UUID().uuidString)",
                    kind: .unknown,
                    visibilityCategory: .unknown,
                    title: "Unsupported item",
                    body: "This item shape is not supported yet.",
                    date: defaultDate,
                    isLive: isLive,
                    turnID: turn["id"]?.stringValue ?? turn["turnId"]?.stringValue,
                    turnSequence: turnSequence,
                    itemSequence: itemSequence,
                    eventSequence: 0,
                    displayGroupDate: defaultDate
                )
            ]
        }

        let itemID = object["id"]?.stringValue
        let eventItemID = itemID ?? UUID().uuidString
        let turnID = turn["id"]?.stringValue ?? turn["turnId"]?.stringValue
        let eventTurnID = turnID ?? "turn"
        let date = defaultDate ?? date(milliseconds: turn["startedAtMs"]) ?? date(milliseconds: turn["completedAtMs"])
        let type = object["type"]?.stringValue ?? "unknown"
        func makeEvent(
            suffix: String,
            kind: ThreadEventKind,
            visibilityCategory: ThreadEventVisibilityCategory,
            title: String,
            body: String,
            eventSequence: Int = 0
        ) -> ThreadEvent {
            ThreadEvent(
                id: "\(eventTurnID)-\(eventItemID)-\(suffix)",
                kind: kind,
                visibilityCategory: visibilityCategory,
                title: title,
                body: body,
                date: date,
                isLive: isLive,
                turnID: turnID,
                itemID: itemID,
                turnSequence: turnSequence,
                itemSequence: itemSequence,
                eventSequence: eventSequence,
                displayGroupDate: date
            )
        }

        switch type {
        case "userMessage":
            return [
                makeEvent(
                    suffix: "user",
                    kind: .userMessage,
                    visibilityCategory: .message,
                    title: "User message",
                    body: userInputText(object["content"]) ?? "User input"
                )
            ]
        case "agentMessage":
            return [
                makeEvent(
                    suffix: "agent",
                    kind: .agentMessage,
                    visibilityCategory: .message,
                    title: "Agent message",
                    body: firstNonEmpty(object["text"]?.stringValue, "Agent message") ?? "Agent message"
                )
            ]
        case "plan":
            return [
                makeEvent(
                    suffix: "plan",
                    kind: .agentMessage,
                    visibilityCategory: .thinking,
                    title: "Plan",
                    body: firstNonEmpty(object["text"]?.stringValue, "Plan update") ?? "Plan update"
                )
            ]
        case "reasoning":
            let body = textList(object["summary"]) ?? textList(object["content"]) ?? "Reasoning"
            return [
                makeEvent(
                    suffix: "reasoning",
                    kind: .agentMessage,
                    visibilityCategory: .thinking,
                    title: "Reasoning",
                    body: body
                )
            ]
        case "commandExecution":
            let command = commandText(object["command"])
            var events = [
                makeEvent(
                    suffix: "command",
                    kind: .command,
                    visibilityCategory: .tooling,
                    title: "Command",
                    body: firstNonEmpty(command, "Command") ?? "Command"
                )
            ]
            if let output = firstNonEmpty(object["aggregatedOutput"]?.stringValue) {
                events.append(
                    makeEvent(
                        suffix: "output",
                        kind: .output,
                        visibilityCategory: .tooling,
                        title: "Command output",
                        body: output,
                        eventSequence: 1
                    )
                )
            }
            return events
        case "fileChange":
            return [
                makeEvent(
                    suffix: "file-change",
                    kind: .request,
                    visibilityCategory: .request,
                    title: "File change",
                    body: "File changes are available on desktop."
                )
            ]
        case "mcpToolCall", "dynamicToolCall":
            return [
                makeEvent(
                    suffix: "tool",
                    kind: .command,
                    visibilityCategory: .tooling,
                    title: "Tool call",
                    body: object["tool"]?.stringValue ?? object["namespace"]?.stringValue ?? "Tool call"
                )
            ]
        default:
            return [
                makeEvent(
                    suffix: "unknown",
                    kind: .unknown,
                    visibilityCategory: .unknown,
                    title: "Unsupported event",
                    body: "Unsupported event type: \(type)"
                )
            ]
        }
    }

    private static func deltaEvent(
        params: [String: JSONValue],
        method: String,
        kind: ThreadEventKind,
        visibilityCategory: ThreadEventVisibilityCategory,
        title: String,
        key: String,
        now: Date
    ) -> ThreadEvent? {
        guard let body = nonEmptyPreservingWhitespace(params[key]?.stringValue) else {
            return nil
        }
        let turnID = params["turnId"]?.stringValue
        let itemID = params["itemId"]?.stringValue
        return ThreadEvent(
            id: "\(turnID ?? "turn")-\(itemID ?? "item")-\(method)",
            kind: kind,
            visibilityCategory: visibilityCategory,
            title: title,
            body: body,
            date: now,
            isLive: true,
            turnID: turnID,
            itemID: itemID,
            displayGroupDate: now,
            isStreamingDelta: true
        )
    }

    private static func requestTitle(for method: String) -> String {
        switch method {
        case "item/commandExecution/requestApproval":
            return "Command approval"
        case "item/fileChange/requestApproval":
            return "File change approval"
        case "item/tool/requestUserInput":
            return "Input requested"
        case "item/permissions/requestApproval":
            return "Permission approval"
        default:
            return "Needs desktop"
        }
    }

    private static func userInputText(_ value: JSONValue?) -> String? {
        guard let items = value?.arrayValue else {
            return value?.stringValue
        }

        let parts = items.compactMap { item -> String? in
            if let text = item.objectValue?["text"]?.stringValue {
                return text
            }
            return item.stringValue
        }
        return firstNonEmpty(parts.joined(separator: "\n"))
    }

    private static func textList(_ value: JSONValue?) -> String? {
        switch value {
        case .string(let text):
            return firstNonEmpty(text)
        case .array(let items):
            let parts = items.compactMap { item -> String? in
                if let text = item.stringValue {
                    return text
                }
                return item.objectValue?["text"]?.stringValue
            }
            return firstNonEmpty(parts.joined(separator: "\n"))
        case .object(let object):
            return firstNonEmpty(object["text"]?.stringValue)
        case .null, .bool, .integer, .double, nil:
            return nil
        }
    }

    private static func commandText(_ value: JSONValue?) -> String? {
        switch value {
        case .string(let text):
            return firstNonEmpty(text)
        case .array(let parts):
            return firstNonEmpty(
                parts.compactMap { part in
                    part.stringValue
                }.joined(separator: " ")
            )
        case .object(let object):
            return firstNonEmpty(
                object["command"]?.stringValue,
                object["cmd"]?.stringValue,
                object["text"]?.stringValue
            )
        case .null, .bool, .integer, .double, nil:
            return nil
        }
    }

    private static func date(seconds value: JSONValue?) -> Date? {
        guard let number = value?.numberValue else {
            return nil
        }
        return Date(timeIntervalSince1970: number)
    }

    private static func date(milliseconds value: JSONValue?) -> Date? {
        guard let number = value?.numberValue else {
            return nil
        }
        return Date(timeIntervalSince1970: number / 1_000)
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        for value in values {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed, !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    private static func nonEmptyPreservingWhitespace(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : value
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

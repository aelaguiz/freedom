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

public struct ThreadEvent: Equatable, Identifiable, Sendable {
    public let id: String
    public let kind: ThreadEventKind
    public var title: String
    public var body: String
    public let date: Date?
    public let isLive: Bool

    public init(
        id: String,
        kind: ThreadEventKind,
        title: String,
        body: String,
        date: Date? = nil,
        isLive: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body
        self.date = date
        self.isLive = isLive
    }
}

public enum ThreadEventNormalizer {
    public static func events(from thread: ThreadDTO) -> [ThreadEvent] {
        let turns = thread.turns ?? []
        return turns.flatMap(events(fromTurn:))
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
                title: "Agent update",
                key: "delta",
                now: now
            )
        case "item/plan/delta", "item/reasoning/summaryTextDelta", "item/reasoning/textDelta":
            return deltaEvent(
                params: params,
                method: notification.method,
                kind: .agentMessage,
                title: "Reasoning update",
                key: "delta",
                now: now
            )
        case "item/commandExecution/outputDelta":
            return deltaEvent(
                params: params,
                method: notification.method,
                kind: .output,
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
                title: "Thread status",
                body: status,
                date: now,
                isLive: true
            )
        case "thread/closed":
            return ThreadEvent(
                id: "thread-closed-\(params["threadId"]?.stringValue ?? "unknown")-\(now.timeIntervalSince1970)",
                kind: .system,
                title: "Thread closed",
                body: "The app-server closed this thread.",
                date: now,
                isLive: true
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
            title: requestTitle(for: request.method),
            body: body,
            date: now,
            isLive: true
        )
    }

    public static func threadId(from notification: JSONRPCNotification) -> String? {
        notification.params?.objectValue?["threadId"]?.stringValue
    }

    public static func threadId(from request: JSONRPCRequest) -> String? {
        request.params?.objectValue?["threadId"]?.stringValue
    }

    private static func events(fromTurn turn: JSONValue) -> [ThreadEvent] {
        guard let object = turn.objectValue else {
            return [
                ThreadEvent(
                    id: "unknown-turn-\(UUID().uuidString)",
                    kind: .unknown,
                    title: "Unsupported turn",
                    body: "This turn shape is not supported yet."
                )
            ]
        }

        let defaultDate = date(seconds: object["startedAt"]) ?? date(seconds: object["completedAt"])
        let items = object["items"]?.arrayValue ?? []
        return items.flatMap { item in
            events(fromItem: item, turn: object, defaultDate: defaultDate, isLive: false)
        }
    }

    private static func events(
        fromItem item: JSONValue,
        turn: [String: JSONValue],
        defaultDate: Date?,
        isLive: Bool
    ) -> [ThreadEvent] {
        guard let object = item.objectValue else {
            return [
                ThreadEvent(
                    id: "unknown-item-\(UUID().uuidString)",
                    kind: .unknown,
                    title: "Unsupported item",
                    body: "This item shape is not supported yet.",
                    date: defaultDate,
                    isLive: isLive
                )
            ]
        }

        let itemID = object["id"]?.stringValue ?? UUID().uuidString
        let turnID = turn["id"]?.stringValue ?? turn["turnId"]?.stringValue ?? "turn"
        let date = defaultDate ?? date(milliseconds: turn["startedAtMs"]) ?? date(milliseconds: turn["completedAtMs"])
        let type = object["type"]?.stringValue ?? "unknown"

        switch type {
        case "userMessage":
            return [
                ThreadEvent(
                    id: "\(turnID)-\(itemID)-user",
                    kind: .userMessage,
                    title: "User message",
                    body: userInputText(object["content"]) ?? "User input",
                    date: date,
                    isLive: isLive
                )
            ]
        case "agentMessage":
            return [
                ThreadEvent(
                    id: "\(turnID)-\(itemID)-agent",
                    kind: .agentMessage,
                    title: "Agent message",
                    body: firstNonEmpty(object["text"]?.stringValue, "Agent message") ?? "Agent message",
                    date: date,
                    isLive: isLive
                )
            ]
        case "plan":
            return [
                ThreadEvent(
                    id: "\(turnID)-\(itemID)-plan",
                    kind: .agentMessage,
                    title: "Plan",
                    body: firstNonEmpty(object["text"]?.stringValue, "Plan update") ?? "Plan update",
                    date: date,
                    isLive: isLive
                )
            ]
        case "reasoning":
            let body = textList(object["summary"]) ?? textList(object["content"]) ?? "Reasoning"
            return [
                ThreadEvent(
                    id: "\(turnID)-\(itemID)-reasoning",
                    kind: .agentMessage,
                    title: "Reasoning",
                    body: body,
                    date: date,
                    isLive: isLive
                )
            ]
        case "commandExecution":
            let command = commandText(object["command"])
            var events = [
                ThreadEvent(
                    id: "\(turnID)-\(itemID)-command",
                    kind: .command,
                    title: "Command",
                    body: firstNonEmpty(command, "Command") ?? "Command",
                    date: date,
                    isLive: isLive
                )
            ]
            if let output = firstNonEmpty(object["aggregatedOutput"]?.stringValue) {
                events.append(
                    ThreadEvent(
                        id: "\(turnID)-\(itemID)-output",
                        kind: .output,
                        title: "Command output",
                        body: output,
                        date: date,
                        isLive: isLive
                    )
                )
            }
            return events
        case "fileChange":
            return [
                ThreadEvent(
                    id: "\(turnID)-\(itemID)-file-change",
                    kind: .request,
                    title: "File change",
                    body: "File changes are available on desktop.",
                    date: date,
                    isLive: isLive
                )
            ]
        case "mcpToolCall", "dynamicToolCall":
            return [
                ThreadEvent(
                    id: "\(turnID)-\(itemID)-tool",
                    kind: .command,
                    title: "Tool call",
                    body: object["tool"]?.stringValue ?? object["namespace"]?.stringValue ?? "Tool call",
                    date: date,
                    isLive: isLive
                )
            ]
        default:
            return [
                ThreadEvent(
                    id: "\(turnID)-\(itemID)-unknown",
                    kind: .unknown,
                    title: "Unsupported event",
                    body: "Unsupported event type: \(type)",
                    date: date,
                    isLive: isLive
                )
            ]
        }
    }

    private static func deltaEvent(
        params: [String: JSONValue],
        method: String,
        kind: ThreadEventKind,
        title: String,
        key: String,
        now: Date
    ) -> ThreadEvent? {
        guard let body = nonEmptyPreservingWhitespace(params[key]?.stringValue) else {
            return nil
        }
        let turnID = params["turnId"]?.stringValue ?? "turn"
        let itemID = params["itemId"]?.stringValue ?? "item"
        return ThreadEvent(
            id: "\(turnID)-\(itemID)-\(method)",
            kind: kind,
            title: title,
            body: body,
            date: now,
            isLive: true
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

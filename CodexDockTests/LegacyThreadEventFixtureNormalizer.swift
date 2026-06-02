import Foundation
@testable import CodexDock

// Fixture-only bridge for old raw Codex test data. Production Thread Detail
// display rows must come from relay projection DTOs, not this normalizer.
enum LegacyThreadEventFixtureNormalizer {
    static func events(from thread: ThreadDTO) -> [ThreadEvent] {
        let turns = thread.turns ?? []
        return turns.enumerated().flatMap { turnSequence, turn in
            events(fromTurn: turn, turnSequence: turnSequence)
        }
    }

    static func event(from notification: JSONRPCNotification, now: Date = Date()) -> ThreadEvent? {
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
            let eventDate = lifecycleDate(for: notification.method, params: params, now: now)
            return events(fromItem: item, turn: params, defaultDate: eventDate, isLive: true).first
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
                displayOrderKey: legacyDisplayOrderKey(
                    id: "thread-status-\(params["threadId"]?.stringValue ?? "unknown")-\(now.timeIntervalSince1970)",
                    activityDate: now
                ),
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
                displayOrderKey: legacyDisplayOrderKey(
                    id: "thread-closed-\(params["threadId"]?.stringValue ?? "unknown")-\(now.timeIntervalSince1970)",
                    activityDate: now
                ),
                displayGroupDate: now
            )
        default:
            return nil
        }
    }

    static func event(from request: JSONRPCRequest, now: Date = Date()) -> ThreadEvent {
        let params = request.params?.objectValue ?? [:]
        let requestDate = date(milliseconds: params["startedAtMs"]) ?? now
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
            date: requestDate,
            isLive: true,
            turnID: params["turnId"]?.stringValue,
            itemID: params["itemId"]?.stringValue,
            displayOrderKey: legacyDisplayOrderKey(
                id: "request-\(request.id)",
                activityDate: requestDate
            ),
            displayGroupDate: requestDate,
            activityDate: requestDate,
            request: ThreadDetailEventRequestDTO(
                requestID: request.id,
                method: request.method,
                params: request.params,
                status: "pending"
            )
        )
    }

    static func threadId(from notification: JSONRPCNotification) -> String? {
        notification.params?.objectValue?["threadId"]?.stringValue
    }

    static func threadId(from request: JSONRPCRequest) -> String? {
        request.params?.objectValue?["threadId"]?.stringValue
    }

    private static func events(fromTurn turn: JSONValue, turnSequence: Int?) -> [ThreadEvent] {
        guard let object = turn.objectValue else {
            let id = "unknown-turn-\(UUID().uuidString)"
            return [
                ThreadEvent(
                    id: id,
                    kind: .unknown,
                    visibilityCategory: .unknown,
                    title: "Unsupported turn",
                    body: "This turn shape is not supported yet.",
                    turnSequence: turnSequence,
                    eventSequence: 0,
                    displayOrderKey: legacyDisplayOrderKey(
                        id: id,
                        activityDate: nil,
                        turnSequence: turnSequence,
                        eventSequence: 0
                    )
                )
            ]
        }

        let turnStartedAt = date(seconds: object["startedAt"])
        let turnCompletedAt = date(seconds: object["completedAt"])
        let defaultDate = turnStartedAt ?? turnCompletedAt
        let items = object["items"]?.arrayValue ?? []
        return items.enumerated().flatMap { itemSequence, item in
            events(
                fromItem: item,
                turn: object,
                defaultDate: defaultDate,
                turnStartedAt: turnStartedAt,
                turnCompletedAt: turnCompletedAt,
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
        turnStartedAt: Date? = nil,
        turnCompletedAt: Date? = nil,
        isLive: Bool,
        turnSequence: Int? = nil,
        itemSequence: Int? = nil
    ) -> [ThreadEvent] {
        guard let object = item.objectValue else {
            let id = "unknown-item-\(UUID().uuidString)"
            return [
                ThreadEvent(
                    id: id,
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
                    displayOrderKey: legacyDisplayOrderKey(
                        id: id,
                        activityDate: defaultDate,
                        turnSequence: turnSequence,
                        itemSequence: itemSequence,
                        eventSequence: 0
                    ),
                    displayGroupDate: defaultDate,
                    activityDate: defaultDate
                )
            ]
        }

        let itemID = object["id"]?.stringValue
        let eventItemID = itemID ?? UUID().uuidString
        let turnID = turn["id"]?.stringValue ?? turn["turnId"]?.stringValue
        let eventTurnID = turnID ?? "turn"
        let type = object["type"]?.stringValue ?? "unknown"
        func makeEvent(
            suffix: String,
            kind: ThreadEventKind,
            visibilityCategory: ThreadEventVisibilityCategory,
            title: String,
            body: String,
            eventSequence: Int = 0
        ) -> ThreadEvent {
            let eventDate = displayDate(
                for: type,
                defaultDate: defaultDate,
                turnStartedAt: turnStartedAt,
                turnCompletedAt: turnCompletedAt
            )
            return ThreadEvent(
                id: "\(eventTurnID)-\(eventItemID)-\(suffix)",
                kind: kind,
                visibilityCategory: visibilityCategory,
                title: title,
                body: body,
                date: eventDate,
                isLive: isLive,
                turnID: turnID,
                itemID: itemID,
                turnSequence: turnSequence,
                itemSequence: itemSequence,
                eventSequence: eventSequence,
                displayOrderKey: legacyDisplayOrderKey(
                    id: "\(eventTurnID)-\(eventItemID)-\(suffix)",
                    activityDate: eventDate,
                    turnSequence: turnSequence,
                    itemSequence: itemSequence,
                    eventSequence: eventSequence
                ),
                displayGroupDate: eventDate,
                activityDate: eventDate
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
            displayOrderKey: legacyDisplayOrderKey(
                id: "\(turnID ?? "turn")-\(itemID ?? "item")-\(method)",
                activityDate: now
            ),
            displayGroupDate: now,
            activityDate: now,
            isStreamingDelta: true
        )
    }

    private static func displayDate(
        for itemType: String,
        defaultDate: Date?,
        turnStartedAt: Date?,
        turnCompletedAt: Date?
    ) -> Date? {
        switch itemType {
        case "userMessage":
            return turnStartedAt ?? defaultDate
        case "agentMessage",
             "plan",
             "reasoning",
             "commandExecution",
             "fileChange",
             "mcpToolCall",
             "dynamicToolCall":
            return turnCompletedAt ?? turnStartedAt ?? defaultDate
        default:
            return defaultDate
        }
    }

    private static func lifecycleDate(
        for method: String,
        params: [String: JSONValue],
        now: Date
    ) -> Date {
        switch method {
        case "item/started":
            return date(milliseconds: params["startedAtMs"]) ?? now
        case "item/completed":
            return date(milliseconds: params["completedAtMs"])
                ?? date(milliseconds: params["startedAtMs"])
                ?? now
        default:
            return now
        }
    }

    private static func legacyDisplayOrderKey(
        id: String,
        activityDate: Date?,
        turnSequence: Int? = nil,
        itemSequence: Int? = nil,
        eventSequence: Int? = nil
    ) -> String {
        let maxSortMs: Int64 = 9_999_999_999_999_999
        let activityAtMs = activityDate.map { Int64($0.timeIntervalSince1970 * 1_000) } ?? 0
        let boundedActivityAtMs = max(0, min(maxSortMs, activityAtMs))
        let descendingActivityKey = maxSortMs - boundedActivityAtMs
        let turn = max(0, turnSequence ?? 999_999)
        let item = 999_999 - max(0, itemSequence ?? 0)
        let row = 999_999 - max(0, eventSequence ?? 0)
        return String(
            format: "%016lld|%06d|%06d|%06d|%@",
            descendingActivityKey,
            turn,
            item,
            row,
            id
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

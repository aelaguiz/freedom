import Foundation

public enum ServerRequestCardKind: String, Equatable, Sendable {
    case commandApproval
    case fileChangeApproval
    case permissionsApproval
    case userInput
    case mcpElicitation
    case unsupported
}

public enum ServerRequestCardStatus: Equatable, Sendable {
    case pending
    case responding
    case resolved
    case failed(String)

    public var label: String {
        switch self {
        case .pending:
            return "Pending"
        case .responding:
            return "Sending"
        case .resolved:
            return "Resolved"
        case .failed:
            return "Failed"
        }
    }
}

public enum ServerRequestCardAction: Equatable, Sendable {
    case accept
    case decline
    case submitInput

    public var label: String {
        switch self {
        case .accept:
            return "Approve"
        case .decline:
            return "Decline"
        case .submitInput:
            return "Send"
        }
    }
}

public struct ServerRequestCard: Equatable, Identifiable, Sendable {
    public let id: String
    public let requestID: JSONRPCRequestID
    public let method: String
    public let threadID: String
    public let turnID: String?
    public let itemID: String?
    public let kind: ServerRequestCardKind
    public let title: String
    public let summary: String
    public let detail: String
    public let params: JSONValue?
    public let requestedAt: Date
    public var inputDraft: String
    public var status: ServerRequestCardStatus

    public var isSupported: Bool {
        kind != .unsupported
    }

    public var needsTextInput: Bool {
        kind == .userInput
    }

    public init(
        id: String,
        requestID: JSONRPCRequestID,
        method: String,
        threadID: String,
        turnID: String?,
        itemID: String?,
        kind: ServerRequestCardKind,
        title: String,
        summary: String,
        detail: String,
        params: JSONValue?,
        requestedAt: Date,
        inputDraft: String = "",
        status: ServerRequestCardStatus = .pending
    ) {
        self.id = id
        self.requestID = requestID
        self.method = method
        self.threadID = threadID
        self.turnID = turnID
        self.itemID = itemID
        self.kind = kind
        self.title = title
        self.summary = summary
        self.detail = detail
        self.params = params
        self.requestedAt = requestedAt
        self.inputDraft = inputDraft
        self.status = status
    }

    public static func make(from request: JSONRPCRequest, now: Date = Date()) -> ServerRequestCard {
        let params = request.params?.objectValue ?? [:]
        let threadID = params["threadId"]?.stringValue ?? "unknown"
        let turnID = params["turnId"]?.stringValue
        let itemID = params["itemId"]?.stringValue

        let base = CardBase(
            id: "request-\(request.id)",
            requestID: request.id,
            method: request.method,
            threadID: threadID,
            turnID: turnID,
            itemID: itemID,
            params: request.params,
            requestedAt: date(milliseconds: params["startedAtMs"]) ?? now
        )

        switch request.method {
        case "item/commandExecution/requestApproval":
            return makeCard(
                base: base,
                kind: .commandApproval,
                title: "Command approval",
                summary: commandText(params["command"]) ?? params["reason"]?.stringValue ?? "Approve command",
                detail: params["cwd"]?.stringValue ?? "Command is waiting for approval."
            )
        case "item/fileChange/requestApproval":
            return makeCard(
                base: base,
                kind: .fileChangeApproval,
                title: "File change approval",
                summary: params["reason"]?.stringValue ?? params["grantRoot"]?.stringValue ?? "Approve file change",
                detail: params["grantRoot"]?.stringValue ?? "File changes are waiting for approval."
            )
        case "item/permissions/requestApproval":
            return makeCard(
                base: base,
                kind: .permissionsApproval,
                title: "Permission approval",
                summary: params["reason"]?.stringValue ?? "Grant requested permissions",
                detail: params["cwd"]?.stringValue ?? "Permissions are waiting for approval."
            )
        case "item/tool/requestUserInput":
            let question = firstQuestion(from: params)
            return makeCard(
                base: base,
                kind: .userInput,
                title: question.header ?? "Input requested",
                summary: question.question ?? "A tool is asking for input.",
                detail: "Answer from this phone."
            )
        case "mcpServer/elicitation/request":
            return makeCard(
                base: base,
                kind: .mcpElicitation,
                title: "MCP elicitation",
                summary: params["message"]?.stringValue ?? "MCP server is asking for input.",
                detail: params["serverName"]?.stringValue ?? "MCP request"
            )
        default:
            return makeCard(
                base: base,
                kind: .unsupported,
                title: "Needs desktop",
                summary: request.method,
                detail: "This request type is visible but not supported on phone yet."
            )
        }
    }

    public func responsePayload(for action: ServerRequestCardAction) -> JSONValue? {
        switch (kind, action) {
        case (.commandApproval, .accept):
            return .object(["decision": .string("accept")])
        case (.commandApproval, .decline):
            return .object(["decision": .string("decline")])
        case (.fileChangeApproval, .accept):
            return .object(["decision": .string("accept")])
        case (.fileChangeApproval, .decline):
            return .object(["decision": .string("decline")])
        case (.permissionsApproval, .accept):
            return .object([
                "permissions": grantedPermissions(),
                "scope": .string("turn"),
                "strictAutoReview": .bool(false),
            ])
        case (.permissionsApproval, .decline):
            return .object([
                "permissions": .object([:]),
                "scope": .string("turn"),
                "strictAutoReview": .bool(false),
            ])
        case (.userInput, .submitInput):
            guard let questionID = Self.firstQuestion(from: params?.objectValue ?? [:]).id,
                  let answer = Self.nonEmpty(inputDraft) else {
                return nil
            }
            return .object([
                "answers": .object([
                    questionID: .object([
                        "answers": .array([.string(answer)]),
                    ]),
                ]),
            ])
        case (.mcpElicitation, .decline):
            return .object([
                "action": .string("decline"),
                "content": .null,
                "_meta": .null,
            ])
        case (.unsupported, _),
             (.commandApproval, .submitInput),
             (.fileChangeApproval, .submitInput),
             (.permissionsApproval, .submitInput),
             (.userInput, .accept),
             (.userInput, .decline),
             (.mcpElicitation, .accept),
             (.mcpElicitation, .submitInput):
            return nil
        }
    }

    private func grantedPermissions() -> JSONValue {
        guard let permissions = params?.objectValue?["permissions"]?.objectValue else {
            return .object([:])
        }

        var result: [String: JSONValue] = [:]
        if let network = permissions["network"], network != .null {
            result["network"] = network
        }
        if let fileSystem = permissions["fileSystem"], fileSystem != .null {
            result["fileSystem"] = fileSystem
        }
        return .object(result)
    }

    private struct CardBase {
        let id: String
        let requestID: JSONRPCRequestID
        let method: String
        let threadID: String
        let turnID: String?
        let itemID: String?
        let params: JSONValue?
        let requestedAt: Date
    }

    private struct Question {
        let id: String?
        let header: String?
        let question: String?
    }

    private static func makeCard(
        base: CardBase,
        kind: ServerRequestCardKind,
        title: String,
        summary: String,
        detail: String
    ) -> ServerRequestCard {
        ServerRequestCard(
            id: base.id,
            requestID: base.requestID,
            method: base.method,
            threadID: base.threadID,
            turnID: base.turnID,
            itemID: base.itemID,
            kind: kind,
            title: title,
            summary: summary,
            detail: detail,
            params: base.params,
            requestedAt: base.requestedAt
        )
    }

    private static func firstQuestion(from params: [String: JSONValue]) -> Question {
        guard let question = params["questions"]?.arrayValue?.first?.objectValue else {
            return Question(id: nil, header: nil, question: nil)
        }
        return Question(
            id: question["id"]?.stringValue,
            header: question["header"]?.stringValue,
            question: question["question"]?.stringValue
        )
    }

    private static func commandText(_ value: JSONValue?) -> String? {
        switch value {
        case .string(let text):
            return nonEmpty(text)
        case .array(let parts):
            return nonEmpty(parts.compactMap(\.stringValue).joined(separator: " "))
        case .object(let object):
            return nonEmpty(
                object["command"]?.stringValue,
                object["cmd"]?.stringValue,
                object["text"]?.stringValue
            )
        case .null, .bool, .integer, .double, nil:
            return nil
        }
    }

    private static func nonEmpty(_ values: String?...) -> String? {
        for value in values {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed, !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    private static func date(milliseconds value: JSONValue?) -> Date? {
        guard let number = value?.numberValue else {
            return nil
        }
        return Date(timeIntervalSince1970: number / 1_000)
    }
}

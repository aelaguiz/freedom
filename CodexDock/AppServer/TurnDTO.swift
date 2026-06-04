import Foundation

public struct TurnUserInputDTO: Codable, Equatable, Sendable {
    public let type: String
    public let text: String
    public let textElements: [JSONValue]

    public init(text: String) {
        self.type = "text"
        self.text = text
        self.textElements = []
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case textElements = "text_elements"
    }
}

public struct TurnStartParams: Codable, Equatable, Sendable {
    public let threadId: String
    public let clientUserMessageId: String?
    public let input: [TurnUserInputDTO]

    public init(threadId: String, clientUserMessageId: String? = nil, input: [TurnUserInputDTO]) {
        self.threadId = threadId
        self.clientUserMessageId = clientUserMessageId
        self.input = input
    }

    public static func text(
        threadId: String,
        text: String,
        clientUserMessageId: String? = nil
    ) -> TurnStartParams {
        TurnStartParams(
            threadId: threadId,
            clientUserMessageId: clientUserMessageId,
            input: [TurnUserInputDTO(text: text)]
        )
    }
}

public struct TurnStartResponseDTO: Codable, Equatable, Sendable {
    public let turn: JSONValue

    public init(turn: JSONValue) {
        self.turn = turn
    }
}

public struct TurnSteerParams: Codable, Equatable, Sendable {
    public let threadId: String
    public let clientUserMessageId: String?
    public let input: [TurnUserInputDTO]
    public let expectedTurnId: String

    public init(
        threadId: String,
        clientUserMessageId: String? = nil,
        input: [TurnUserInputDTO],
        expectedTurnId: String
    ) {
        self.threadId = threadId
        self.clientUserMessageId = clientUserMessageId
        self.input = input
        self.expectedTurnId = expectedTurnId
    }

    public static func text(
        threadId: String,
        text: String,
        expectedTurnId: String,
        clientUserMessageId: String? = nil
    ) -> TurnSteerParams {
        TurnSteerParams(
            threadId: threadId,
            clientUserMessageId: clientUserMessageId,
            input: [TurnUserInputDTO(text: text)],
            expectedTurnId: expectedTurnId
        )
    }
}

public struct TurnSteerResponseDTO: Codable, Equatable, Sendable {
    public let turnId: String

    public init(turnId: String) {
        self.turnId = turnId
    }
}

public struct ThreadMessageSendParams: Codable, Equatable, Sendable {
    public let threadId: String
    public let clientUserMessageId: String
    public let input: [TurnUserInputDTO]

    public init(threadId: String, clientUserMessageId: String, input: [TurnUserInputDTO]) {
        self.threadId = threadId
        self.clientUserMessageId = clientUserMessageId
        self.input = input
    }

    public static func text(threadId: String, clientUserMessageId: String, text: String) -> ThreadMessageSendParams {
        ThreadMessageSendParams(
            threadId: threadId,
            clientUserMessageId: clientUserMessageId,
            input: [TurnUserInputDTO(text: text)]
        )
    }
}

public struct ThreadMessageSendResponseDTO: Codable, Equatable, Sendable {
    public let clientUserMessageId: String
    public let state: String
    public let turnId: String?
    public let itemId: String?
    public let error: String?

    public init(
        clientUserMessageId: String,
        state: String,
        turnId: String? = nil,
        itemId: String? = nil,
        error: String? = nil
    ) {
        self.clientUserMessageId = clientUserMessageId
        self.state = state
        self.turnId = turnId
        self.itemId = itemId
        self.error = error
    }
}

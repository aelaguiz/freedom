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
    public let input: [TurnUserInputDTO]

    public init(threadId: String, input: [TurnUserInputDTO]) {
        self.threadId = threadId
        self.input = input
    }

    public static func text(threadId: String, text: String) -> TurnStartParams {
        TurnStartParams(threadId: threadId, input: [TurnUserInputDTO(text: text)])
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
    public let input: [TurnUserInputDTO]
    public let expectedTurnId: String

    public init(threadId: String, input: [TurnUserInputDTO], expectedTurnId: String) {
        self.threadId = threadId
        self.input = input
        self.expectedTurnId = expectedTurnId
    }

    public static func text(
        threadId: String,
        text: String,
        expectedTurnId: String
    ) -> TurnSteerParams {
        TurnSteerParams(
            threadId: threadId,
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

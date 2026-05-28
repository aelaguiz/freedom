import XCTest
@testable import CodexDock

final class ServerRequestCardTests: XCTestCase {
    func testCommandApprovalCardBuildsAcceptAndDeclineResponses() {
        let card = ServerRequestCard.make(
            from: JSONRPCRequest(
                id: .string("approval-1"),
                method: "item/commandExecution/requestApproval",
                params: .object([
                    "threadId": .string("thread-1"),
                    "turnId": .string("turn-1"),
                    "itemId": .string("cmd-1"),
                    "command": .string("swift test"),
                    "cwd": .string("/repo"),
                ])
            ),
            now: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(card.id, "request-approval-1")
        XCTAssertEqual(card.kind, .commandApproval)
        XCTAssertEqual(card.summary, "swift test")
        XCTAssertEqual(card.detail, "/repo")
        XCTAssertEqual(card.responsePayload(for: .accept), .object(["decision": .string("accept")]))
        XCTAssertEqual(card.responsePayload(for: .decline), .object(["decision": .string("decline")]))
    }

    func testUserInputCardBuildsAnswerResponse() {
        var card = ServerRequestCard.make(
            from: JSONRPCRequest(
                id: .integer(7),
                method: "item/tool/requestUserInput",
                params: .object([
                    "threadId": .string("thread-1"),
                    "turnId": .string("turn-1"),
                    "itemId": .string("tool-1"),
                    "questions": .array([
                        .object([
                            "id": .string("confirm"),
                            "header": .string("Confirm"),
                            "question": .string("Continue?"),
                        ]),
                    ]),
                ])
            ),
            now: Date(timeIntervalSince1970: 1_000)
        )
        card.inputDraft = "yes"

        XCTAssertEqual(card.id, "request-7")
        XCTAssertEqual(card.kind, .userInput)
        XCTAssertEqual(card.title, "Confirm")
        XCTAssertEqual(card.summary, "Continue?")
        XCTAssertEqual(
            card.responsePayload(for: .submitInput),
            .object([
                "answers": .object([
                    "confirm": .object([
                        "answers": .array([.string("yes")]),
                    ]),
                ]),
            ])
        )
    }

    func testPermissionCardCanGrantRequestedSubsetOrDeclineWithEmptyGrant() {
        let card = ServerRequestCard.make(
            from: JSONRPCRequest(
                id: .string("permission-1"),
                method: "item/permissions/requestApproval",
                params: .object([
                    "threadId": .string("thread-1"),
                    "turnId": .string("turn-1"),
                    "itemId": .string("perm-1"),
                    "reason": .string("Need network"),
                    "permissions": .object([
                        "network": .object(["hosts": .array([.string("example.com")])]),
                        "fileSystem": .null,
                    ]),
                ])
            ),
            now: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(card.kind, .permissionsApproval)
        XCTAssertEqual(
            card.responsePayload(for: .accept),
            .object([
                "permissions": .object([
                    "network": .object(["hosts": .array([.string("example.com")])]),
                ]),
                "scope": .string("turn"),
                "strictAutoReview": .bool(false),
            ])
        )
        XCTAssertEqual(
            card.responsePayload(for: .decline),
            .object([
                "permissions": .object([:]),
                "scope": .string("turn"),
                "strictAutoReview": .bool(false),
            ])
        )
    }

    func testUnsupportedRequestStaysVisibleWithoutResponsePayload() {
        let card = ServerRequestCard.make(
            from: JSONRPCRequest(
                id: .string("desktop-1"),
                method: "account/chatgptAuthTokens/refresh",
                params: .object(["threadId": .string("thread-1")])
            ),
            now: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(card.kind, .unsupported)
        XCTAssertEqual(card.title, "Needs desktop")
        XCTAssertNil(card.responsePayload(for: .accept))
        XCTAssertNil(card.responsePayload(for: .decline))
    }

    func testMcpElicitationDeclinesWithSupportedResponseShape() {
        let card = ServerRequestCard.make(
            from: JSONRPCRequest(
                id: .string("mcp-1"),
                method: "mcpServer/elicitation/request",
                params: .object([
                    "threadId": .string("thread-1"),
                    "turnId": .string("turn-1"),
                    "serverName": .string("design-db"),
                    "mode": .string("form"),
                    "message": .string("Pick a record"),
                ])
            ),
            now: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(card.kind, .mcpElicitation)
        XCTAssertEqual(
            card.responsePayload(for: .decline),
            .object([
                "action": .string("decline"),
                "content": .null,
                "_meta": .null,
            ])
        )
    }
}

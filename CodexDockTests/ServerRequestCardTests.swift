import XCTest
@testable import CodexDock

final class ServerRequestCardTests: XCTestCase {
    func testCommandApprovalCardBuildsAcceptAndDeclineResponses() {
        let card = makeProjectedRequestCard(
            from: JSONRPCRequest(
                id: .string("approval-1"),
                method: "item/commandExecution/requestApproval",
                params: .object([
                    "threadId": .string("thread-1"),
                    "turnId": .string("turn-1"),
                    "itemId": .string("cmd-1"),
                    "startedAtMs": .integer(999_000),
                    "command": .string("swift test"),
                    "cwd": .string("/repo"),
                ])
            ),
            now: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(card.id, "host:test/thread:thread-1/request:approval-1/row:request")
        XCTAssertEqual(card.requestID, .string("approval-1"))
        XCTAssertEqual(card.kind, .commandApproval)
        XCTAssertEqual(card.summary, "swift test")
        XCTAssertEqual(card.detail, "/repo")
        XCTAssertEqual(card.requestedAt, Date(timeIntervalSince1970: 999))
        XCTAssertEqual(card.responsePayload(for: .accept), .object(["decision": .string("accept")]))
        XCTAssertEqual(card.responsePayload(for: .decline), .object(["decision": .string("decline")]))
    }

    func testUserInputCardBuildsAnswerResponse() {
        var card = makeProjectedRequestCard(
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

        XCTAssertEqual(card.id, "host:test/thread:thread-1/request:7/row:request")
        XCTAssertEqual(card.requestID, .integer(7))
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
        let card = makeProjectedRequestCard(
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
        let card = makeProjectedRequestCard(
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
        let card = makeProjectedRequestCard(
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

    private func makeProjectedRequestCard(
        from request: JSONRPCRequest,
        now: Date
    ) -> ServerRequestCard {
        let params = request.params?.objectValue ?? [:]
        let threadID = params["threadId"]?.stringValue ?? "unknown"
        let turnID = params["turnId"]?.stringValue
        let itemID = params["itemId"]?.stringValue
        let event = ThreadEvent(
            id: "host:test/thread:\(threadID)/request:\(request.id)/row:request",
            kind: .request,
            visibilityCategory: .request,
            title: "Request",
            body: request.method,
            date: now,
            isLive: true,
            turnID: turnID,
            itemID: itemID,
            displayOrderKey: "0000000000000000000|\(request.id)",
            activityDate: now,
            request: ThreadDetailEventRequestDTO(
                requestID: request.id,
                method: request.method,
                params: request.params
            )
        )
        guard let card = ServerRequestCard.make(from: event) else {
            XCTFail("Expected projected request event to create a request card")
            return ServerRequestCard(
                id: event.id,
                requestID: request.id,
                method: request.method,
                threadID: threadID,
                turnID: turnID,
                itemID: itemID,
                kind: .unsupported,
                title: "Invalid",
                summary: "Invalid",
                detail: "Invalid",
                params: request.params,
                requestedAt: now
            )
        }
        return card
    }
}

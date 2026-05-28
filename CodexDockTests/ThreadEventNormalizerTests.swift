import XCTest
@testable import CodexDock

final class ThreadEventNormalizerTests: XCTestCase {
    func testStoredThreadTurnsNormalizeMessagesCommandsAndOutput() {
        let thread = ThreadDTO(
            id: "thread-1",
            turns: [
                .object([
                    "id": .string("turn-1"),
                    "startedAt": .integer(1_700_000_000),
                    "items": .array([
                        .object([
                            "id": .string("user-1"),
                            "type": .string("userMessage"),
                            "content": .array([
                                .object(["text": .string("Run the tests")]),
                            ]),
                        ]),
                        .object([
                            "id": .string("agent-1"),
                            "type": .string("agentMessage"),
                            "text": .string("I am checking the suite."),
                        ]),
                        .object([
                            "id": .string("cmd-1"),
                            "type": .string("commandExecution"),
                            "command": .array([.string("swift"), .string("test")]),
                            "aggregatedOutput": .string("33 tests passed"),
                        ]),
                    ]),
                ]),
            ]
        )

        let events = ThreadEventNormalizer.events(from: thread)

        XCTAssertEqual(events.map(\.kind), [.userMessage, .agentMessage, .command, .output])
        XCTAssertEqual(events[0].body, "Run the tests")
        XCTAssertEqual(events[2].body, "swift test")
        XCTAssertEqual(events[3].body, "33 tests passed")
        XCTAssertFalse(events.contains { $0.body.contains("{") || $0.body.contains("}") })
    }

    func testLiveDeltaUsesStableThreadAndItemIdentity() {
        let notification = JSONRPCNotification(
            method: "item/agentMessage/delta",
            params: .object([
                "threadId": .string("thread-1"),
                "turnId": .string("turn-1"),
                "itemId": .string("agent-1"),
                "delta": .string("hello"),
            ])
        )

        let event = ThreadEventNormalizer.event(
            from: notification,
            now: Date(timeIntervalSince1970: 2_000)
        )

        XCTAssertEqual(ThreadEventNormalizer.threadId(from: notification), "thread-1")
        XCTAssertEqual(event?.id, "turn-1-agent-1-item/agentMessage/delta")
        XCTAssertEqual(event?.kind, .agentMessage)
        XCTAssertEqual(event?.body, "hello")
        XCTAssertEqual(event?.isLive, true)
    }

    func testServerRequestBecomesRequestEvent() {
        let request = JSONRPCRequest(
            id: .string("approval-1"),
            method: "item/commandExecution/requestApproval",
            params: .object([
                "threadId": .string("thread-1"),
                "command": .array([.string("make"), .string("app")]),
            ])
        )

        let event = ThreadEventNormalizer.event(
            from: request,
            now: Date(timeIntervalSince1970: 2_000)
        )

        XCTAssertEqual(ThreadEventNormalizer.threadId(from: request), "thread-1")
        XCTAssertEqual(event.id, "request-approval-1")
        XCTAssertEqual(event.kind, .request)
        XCTAssertEqual(event.title, "Command approval")
        XCTAssertEqual(event.body, "make app")
        XCTAssertEqual(event.isLive, true)
    }

    func testUnknownStoredItemStaysVisibleAsUnsupportedEvent() {
        let thread = ThreadDTO(
            id: "thread-1",
            turns: [
                .object([
                    "id": .string("turn-1"),
                    "items": .array([
                        .object([
                            "id": .string("new-thing"),
                            "type": .string("newServerThing"),
                        ]),
                    ]),
                ]),
            ]
        )

        let events = ThreadEventNormalizer.events(from: thread)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].kind, .unknown)
        XCTAssertEqual(events[0].body, "Unsupported event type: newServerThing")
    }
}

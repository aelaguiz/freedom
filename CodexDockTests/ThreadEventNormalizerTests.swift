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
        XCTAssertEqual(events.map(\.turnID), ["turn-1", "turn-1", "turn-1", "turn-1"])
        XCTAssertEqual(events.map(\.itemSequence), [0, 1, 2, 2])
        XCTAssertEqual(events.map(\.eventSequence), [0, 0, 0, 1])
        XCTAssertFalse(events.contains { $0.body.contains("{") || $0.body.contains("}") })
    }

    func testNewestFirstDisplayOrderPreservesSameTurnEventOrder() {
        let thread = ThreadDTO(
            id: "thread-1",
            turns: [
                .object([
                    "id": .string("turn-old"),
                    "startedAt": .integer(1_700_000_000),
                    "items": .array([
                        .object([
                            "id": .string("old-user"),
                            "type": .string("userMessage"),
                            "content": .array([
                                .object(["text": .string("Old request")]),
                            ]),
                        ]),
                    ]),
                ]),
                .object([
                    "id": .string("turn-new"),
                    "startedAt": .integer(1_700_000_100),
                    "items": .array([
                        .object([
                            "id": .string("new-user"),
                            "type": .string("userMessage"),
                            "content": .array([
                                .object(["text": .string("New request")]),
                            ]),
                        ]),
                        .object([
                            "id": .string("new-agent"),
                            "type": .string("agentMessage"),
                            "text": .string("New answer"),
                        ]),
                        .object([
                            "id": .string("new-command"),
                            "type": .string("commandExecution"),
                            "command": .array([.string("swift"), .string("test")]),
                            "aggregatedOutput": .string("passed"),
                        ]),
                    ]),
                ]),
            ]
        )

        let events = ThreadEventNormalizer.events(from: thread)
        let displayEvents = ThreadEventDisplayOrder.newestFirst(events)

        XCTAssertEqual(events.map(\.body), ["Old request", "New request", "New answer", "swift test", "passed"])
        XCTAssertEqual(displayEvents.map(\.body), ["New request", "New answer", "swift test", "passed", "Old request"])
    }

    func testStoredTurnEventsCarryDatesForDisplayOrdering() {
        let thread = ThreadDTO(
            id: "thread-1",
            turns: [
                .object([
                    "id": .string("turn-old"),
                    "startedAt": .integer(1_700_000_000),
                    "items": .array([
                        .object([
                            "id": .string("old-agent"),
                            "type": .string("agentMessage"),
                            "text": .string("Older answer"),
                        ]),
                    ]),
                ]),
                .object([
                    "id": .string("turn-new"),
                    "startedAt": .integer(1_700_000_100),
                    "items": .array([
                        .object([
                            "id": .string("new-agent"),
                            "type": .string("agentMessage"),
                            "text": .string("Newer answer"),
                        ]),
                    ]),
                ]),
            ]
        )

        let events = ThreadEventNormalizer.events(from: thread)

        XCTAssertEqual(events.map(\.turnID), ["turn-old", "turn-new"])
        XCTAssertEqual(events.map(\.turnSequence), [0, 1])
        XCTAssertEqual(events.map(\.displayGroupDate), [
            Date(timeIntervalSince1970: 1_700_000_000),
            Date(timeIntervalSince1970: 1_700_000_100),
        ])
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
        XCTAssertEqual(event?.turnID, "turn-1")
        XCTAssertEqual(event?.itemID, "agent-1")
        XCTAssertEqual(event?.displayGroupDate, Date(timeIntervalSince1970: 2_000))
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

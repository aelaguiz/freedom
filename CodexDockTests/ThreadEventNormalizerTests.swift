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
        XCTAssertEqual(events.map(\.visibilityCategory), [.message, .message, .tooling, .tooling])
        XCTAssertEqual(events[0].body, "Run the tests")
        XCTAssertEqual(events[2].body, "swift test")
        XCTAssertEqual(events[3].body, "33 tests passed")
        XCTAssertEqual(events.map(\.turnID), ["turn-1", "turn-1", "turn-1", "turn-1"])
        XCTAssertEqual(events.map(\.itemSequence), [0, 1, 2, 2])
        XCTAssertEqual(events.map(\.eventSequence), [0, 0, 0, 1])
        XCTAssertFalse(events.contains { $0.body.contains("{") || $0.body.contains("}") })
    }

    func testNewestFirstDisplayOrderShowsCompletedAgentReplyAboveEarlierUserPrompt() {
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
                    "completedAt": .integer(1_700_000_200),
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
        XCTAssertEqual(
            ThreadDetailMessageFilter.default.visibleEvents(from: displayEvents).map(\.body),
            ["New answer", "New request", "Old request"]
        )
        XCTAssertEqual(displayEvents.map(\.body).prefix(4), ["passed", "swift test", "New answer", "New request"])
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

    func testSameSecondTurnsRespectReceivedNewestFirstPageOrder() {
        let thread = ThreadDTO(
            id: "thread-1",
            turns: [
                .object([
                    "id": .string("turn-new"),
                    "startedAt": .integer(1_700_000_000),
                    "items": .array([
                        .object([
                            "id": .string("new-agent"),
                            "type": .string("agentMessage"),
                            "text": .string("Newer returned turn"),
                        ]),
                    ]),
                ]),
                .object([
                    "id": .string("turn-old"),
                    "startedAt": .integer(1_700_000_000),
                    "items": .array([
                        .object([
                            "id": .string("old-agent"),
                            "type": .string("agentMessage"),
                            "text": .string("Older returned turn"),
                        ]),
                    ]),
                ]),
            ]
        )

        let events = ThreadEventDisplayOrder.newestFirst(ThreadEventNormalizer.events(from: thread))

        XCTAssertEqual(events.map(\.body), ["Newer returned turn", "Older returned turn"])
    }

    func testInProgressUserOnlyTurnAppearsFirstWhenNewestMeaningfulActivity() {
        let thread = ThreadDTO(
            id: "thread-1",
            turns: [
                .object([
                    "id": .string("turn-user"),
                    "startedAt": .integer(1_700_000_100),
                    "status": .string("inProgress"),
                    "items": .array([
                        .object([
                            "id": .string("user-1"),
                            "type": .string("userMessage"),
                            "content": .array([
                                .object(["text": .string("Still waiting")]),
                            ]),
                        ]),
                    ]),
                ]),
                .object([
                    "id": .string("turn-old"),
                    "startedAt": .integer(1_700_000_000),
                    "completedAt": .integer(1_700_000_050),
                    "items": .array([
                        .object([
                            "id": .string("agent-old"),
                            "type": .string("agentMessage"),
                            "text": .string("Older answer"),
                        ]),
                    ]),
                ]),
            ]
        )

        let events = ThreadDetailMessageFilter.default.visibleEvents(
            from: ThreadEventNormalizer.events(from: thread)
        )

        XCTAssertEqual(events.map(\.body), ["Still waiting", "Older answer"])
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
        XCTAssertEqual(event?.visibilityCategory, .message)
        XCTAssertEqual(event?.body, "hello")
        XCTAssertEqual(event?.isLive, true)
        XCTAssertEqual(event?.isStreamingDelta, true)
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
                "startedAtMs": .integer(1_999_000),
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
        XCTAssertEqual(event.visibilityCategory, .request)
        XCTAssertEqual(event.title, "Command approval")
        XCTAssertEqual(event.body, "make app")
        XCTAssertEqual(event.isLive, true)
        XCTAssertEqual(event.date, Date(timeIntervalSince1970: 1_999))
        XCTAssertEqual(event.activityDate, Date(timeIntervalSince1970: 1_999))
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
        XCTAssertEqual(events[0].visibilityCategory, .unknown)
        XCTAssertEqual(events[0].body, "Unsupported event type: newServerThing")
    }

    func testMessageTypeFilterFiltersStoredEventKindsNewestFirst() {
        let thread = ThreadDTO(
            id: "thread-1",
            turns: [
                .object([
                    "id": .string("turn-1"),
                    "startedAt": .integer(1_700_000_000),
                    "completedAt": .integer(1_700_000_100),
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
                            "id": .string("plan-1"),
                            "type": .string("plan"),
                            "text": .string("Run the model tests first."),
                        ]),
                        .object([
                            "id": .string("reasoning-1"),
                            "type": .string("reasoning"),
                            "summary": .array([
                                .object(["text": .string("The normalizer owns visibility.")]),
                            ]),
                        ]),
                        .object([
                            "id": .string("cmd-1"),
                            "type": .string("commandExecution"),
                            "command": .array([.string("swift"), .string("test")]),
                            "aggregatedOutput": .string("passed"),
                        ]),
                        .object([
                            "id": .string("file-1"),
                            "type": .string("fileChange"),
                        ]),
                        .object([
                            "id": .string("mcp-1"),
                            "type": .string("mcpToolCall"),
                            "tool": .string("workspace.read"),
                        ]),
                        .object([
                            "id": .string("dynamic-1"),
                            "type": .string("dynamicToolCall"),
                            "namespace": .string("shell"),
                        ]),
                        .object([
                            "id": .string("unknown-1"),
                            "type": .string("newServerThing"),
                        ]),
                    ]),
                ]),
            ]
        )

        let events = ThreadEventNormalizer.events(from: thread)

        XCTAssertEqual(events.map(\.visibilityCategory), [
            .message,
            .message,
            .thinking,
            .thinking,
            .tooling,
            .tooling,
            .request,
            .tooling,
            .tooling,
            .unknown,
        ])
        XCTAssertEqual(
            ThreadDetailMessageFilter.all.visibleEvents(from: events).map(\.body),
            [
                "shell",
                "workspace.read",
                "File changes are available on desktop.",
                "passed",
                "swift test",
                "The normalizer owns visibility.",
                "Run the model tests first.",
                "I am checking the suite.",
                "Unsupported event type: newServerThing",
                "Run the tests",
            ]
        )
        XCTAssertEqual(
            ThreadDetailMessageFilter.default.visibleEvents(from: events).map(\.body),
            [
                "File changes are available on desktop.",
                "I am checking the suite.",
                "Run the tests",
            ]
        )
        XCTAssertEqual(
            ThreadDetailMessageFilter.kind(.agentMessage).visibleEvents(from: events).map(\.body),
            [
                "The normalizer owns visibility.",
                "Run the model tests first.",
                "I am checking the suite.",
            ]
        )
        XCTAssertEqual(
            ThreadDetailMessageFilter.kind(.request).visibleEvents(from: events).map(\.body),
            ["File changes are available on desktop."]
        )
    }

    func testLiveEventsUseVisibilityCategories() {
        let now = Date(timeIntervalSince1970: 2_000)
        let notifications = [
            JSONRPCNotification(
                method: "item/agentMessage/delta",
                params: .object([
                    "threadId": .string("thread-1"),
                    "turnId": .string("turn-1"),
                    "itemId": .string("agent-1"),
                    "delta": .string("message delta"),
                ])
            ),
            JSONRPCNotification(
                method: "item/reasoning/textDelta",
                params: .object([
                    "threadId": .string("thread-1"),
                    "turnId": .string("turn-1"),
                    "itemId": .string("reasoning-1"),
                    "delta": .string("reasoning delta"),
                ])
            ),
            JSONRPCNotification(
                method: "item/commandExecution/outputDelta",
                params: .object([
                    "threadId": .string("thread-1"),
                    "turnId": .string("turn-1"),
                    "itemId": .string("command-1"),
                    "delta": .string("output delta"),
                ])
            ),
            JSONRPCNotification(
                method: "thread/status/changed",
                params: .object([
                    "threadId": .string("thread-1"),
                    "status": .object(["type": .string("inProgress")]),
                ])
            ),
        ]

        let events = notifications.compactMap {
            ThreadEventNormalizer.event(from: $0, now: now)
        }

        XCTAssertEqual(events.map(\.visibilityCategory), [.message, .thinking, .tooling, .system])
        XCTAssertEqual(
            ThreadDetailMessageFilter.default.visibleEvents(from: events).map(\.body),
            ["message delta"]
        )
        XCTAssertEqual(
            ThreadDetailMessageFilter.kind(.agentMessage).visibleEvents(from: events).map(\.body),
            ["message delta", "reasoning delta"]
        )
        XCTAssertEqual(
            ThreadDetailMessageFilter.kind(.output).visibleEvents(from: events).map(\.body),
            ["output delta"]
        )
    }

    func testFullItemNotificationsUseStoredItemVisibilityCategories() {
        let reasoningStarted = JSONRPCNotification(
            method: "item/started",
            params: .object([
                "threadId": .string("thread-1"),
                "turnId": .string("turn-live"),
                "startedAtMs": .integer(2_100_000),
                "item": .object([
                    "id": .string("reasoning-live"),
                    "type": .string("reasoning"),
                    "summary": .array([
                        .object(["text": .string("Reason through the failure.")]),
                    ]),
                ]),
            ])
        )
        let commandCompleted = JSONRPCNotification(
            method: "item/completed",
            params: .object([
                "threadId": .string("thread-1"),
                "turnId": .string("turn-live"),
                "completedAtMs": .integer(2_200_000),
                "item": .object([
                    "id": .string("command-live"),
                    "type": .string("commandExecution"),
                    "command": .array([.string("swift"), .string("test")]),
                ]),
            ])
        )

        let reasoningEvent = ThreadEventNormalizer.event(
            from: reasoningStarted,
            now: Date(timeIntervalSince1970: 2_000)
        )
        let commandEvent = ThreadEventNormalizer.event(
            from: commandCompleted,
            now: Date(timeIntervalSince1970: 2_001)
        )

        XCTAssertEqual(reasoningEvent?.kind, .agentMessage)
        XCTAssertEqual(reasoningEvent?.visibilityCategory, .thinking)
        XCTAssertEqual(reasoningEvent?.body, "Reason through the failure.")
        XCTAssertEqual(reasoningEvent?.isStreamingDelta, false)
        XCTAssertEqual(reasoningEvent?.date, Date(timeIntervalSince1970: 2_100))
        XCTAssertEqual(reasoningEvent?.activityDate, Date(timeIntervalSince1970: 2_100))
        XCTAssertEqual(commandEvent?.kind, .command)
        XCTAssertEqual(commandEvent?.visibilityCategory, .tooling)
        XCTAssertEqual(commandEvent?.body, "swift test")
        XCTAssertEqual(commandEvent?.date, Date(timeIntervalSince1970: 2_200))
        XCTAssertEqual(commandEvent?.activityDate, Date(timeIntervalSince1970: 2_200))
    }

    func testMessageTypeProjectionIgnoresOtherTypeDatesWhenOrderingNewestFirst() {
        let oldMessage = ThreadEvent(
            id: "old-message",
            kind: .userMessage,
            visibilityCategory: .message,
            title: "User message",
            body: "Older visible message",
            date: Date(timeIntervalSince1970: 1_000),
            turnID: "turn-old",
            displayGroupDate: Date(timeIntervalSince1970: 1_000)
        )
        let newerMessage = ThreadEvent(
            id: "new-message",
            kind: .userMessage,
            visibilityCategory: .message,
            title: "User message",
            body: "Newer visible message",
            date: Date(timeIntervalSince1970: 2_000),
            turnID: "turn-new",
            displayGroupDate: Date(timeIntervalSince1970: 2_000)
        )
        let hiddenRequestOnOldTurn = ThreadEvent(
            id: "old-hidden-request",
            kind: .request,
            visibilityCategory: .request,
            title: "Command approval",
            body: "Hidden request",
            date: Date(timeIntervalSince1970: 3_000),
            turnID: "turn-old",
            displayGroupDate: Date(timeIntervalSince1970: 3_000)
        )

        let fullTranscript = ThreadEventDisplayOrder.newestFirst([
            oldMessage,
            newerMessage,
            hiddenRequestOnOldTurn,
        ])
        let messages = ThreadDetailMessageFilter.kind(.userMessage).visibleEvents(from: fullTranscript)

        XCTAssertEqual(fullTranscript.map(\.turnID), ["turn-old", "turn-new", "turn-old"])
        XCTAssertEqual(messages.map(\.body), ["Newer visible message", "Older visible message"])
    }

    func testMessageTypeProjectionIsStableWhenInputWasAlreadyDisplayOrdered() {
        let timestamp = Date(timeIntervalSince1970: 2_000)
        let first = ThreadEvent(
            id: "first-message",
            kind: .agentMessage,
            visibilityCategory: .message,
            title: "Agent message",
            body: "First equal-date message",
            date: timestamp,
            turnID: "turn-a",
            displayGroupDate: timestamp
        )
        let second = ThreadEvent(
            id: "second-message",
            kind: .agentMessage,
            visibilityCategory: .message,
            title: "Agent message",
            body: "Second equal-date message",
            date: timestamp,
            turnID: "turn-b",
            displayGroupDate: timestamp
        )

        let once = ThreadEventDisplayOrder.newestFirst([first, second])
        let twice = ThreadDetailMessageFilter.kind(.agentMessage).visibleEvents(from: once)

        XCTAssertEqual(twice.map(\.id), once.map(\.id))
    }
}

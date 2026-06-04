import XCTest
@testable import CodexDock

final class ThreadDetailRenderProjectorTests: XCTestCase {
    func testProjectorFiltersVisibleWindowAndAttachesRequestCard() {
        let projectionID = "host:test/thread:thread-a/turn:turn-1/item:item-1/row:command"
        let event = ThreadEvent(
            id: projectionID,
            kind: .command,
            visibilityCategory: .request,
            title: "Approval",
            body: "Allow command?",
            date: Date(timeIntervalSince1970: 1_000),
            turnID: "turn-1",
            itemID: "item-1",
            displayOrderKey: "0000000000000000001|\(projectionID)",
            request: ThreadDetailEventRequestDTO(
                requestID: .string("approval-1"),
                method: "item/commandExecution/requestApproval",
                status: "pending"
            )
        )
        let snapshot = ThreadDetailSnapshot(
            header: makeHeader(),
            liveState: .live,
            events: [
                ThreadEvent(
                    id: "message-1",
                    kind: .agentMessage,
                    visibilityCategory: .message,
                    title: "Agent",
                    body: "Done",
                    date: Date(timeIntervalSince1970: 2_000),
                    displayOrderKey: "0000000000000000000|message-1"
                ),
                event,
            ]
        )

        let render = ThreadDetailRenderProjector().render(
            snapshot: snapshot,
            options: ThreadDetailRenderOptions(filter: .all, visibleLimit: 10),
            revision: RenderRevision(rawValue: 3)
        )

        XCTAssertEqual(render.revision, RenderRevision(rawValue: 3))
        XCTAssertEqual(render.rows.map(\.event.id), ["message-1", projectionID])
        XCTAssertEqual(render.rows[1].requestCard?.id, projectionID)
        XCTAssertTrue(render.hasUnfilteredEvents)
    }

    func testProjectorKeepsFileChangePayloadOnRequestRow() {
        let event = ThreadEvent(detailEvent: makeProjectedFileChangeEvent())
        let snapshot = ThreadDetailSnapshot(
            header: makeHeader(),
            liveState: .live,
            events: [event]
        )

        let render = ThreadDetailRenderProjector().render(
            snapshot: snapshot,
            options: ThreadDetailRenderOptions(filter: .default, visibleLimit: 10),
            revision: RenderRevision(rawValue: 5)
        )

        XCTAssertEqual(render.rows.count, 1)
        XCTAssertEqual(render.rows[0].event.fileChange?.summary.fileCount, 1)
        XCTAssertEqual(render.rows[0].event.fileChange?.changes[0].path, "CodexDock/AppServer/ThreadDetailDTO.swift")
        XCTAssertEqual(render.rows[0].requestCard?.kind, .fileChangeApproval)
        XCTAssertEqual(render.rows[0].event.kind, .request)
    }

    func testProjectorAppliesVisibleLimitAfterFilteringOrderedEvents() {
        let snapshot = ThreadDetailSnapshot(
            header: makeHeader(),
            liveState: .live,
            events: ThreadEventDisplayOrder.newestFirst([
                ThreadEvent(
                    id: "old-user",
                    kind: .userMessage,
                    visibilityCategory: .message,
                    title: "User",
                    body: "Older prompt",
                    date: Date(timeIntervalSince1970: 1_000),
                    displayOrderKey: "0000000000000000001|old-user",
                    activityDate: Date(timeIntervalSince1970: 1_000)
                ),
                ThreadEvent(
                    id: "new-agent",
                    kind: .agentMessage,
                    visibilityCategory: .message,
                    title: "Agent",
                    body: "Newer answer",
                    date: Date(timeIntervalSince1970: 2_000),
                    displayOrderKey: "0000000000000000000|new-agent",
                    activityDate: Date(timeIntervalSince1970: 2_000)
                ),
            ])
        )

        let render = ThreadDetailRenderProjector().render(
            snapshot: snapshot,
            options: ThreadDetailRenderOptions(filter: .default, visibleLimit: 1),
            revision: RenderRevision(rawValue: 4)
        )

        XCTAssertEqual(render.rows.map(\.event.body), ["Newer answer"])
        XCTAssertEqual(render.visibleWindow.totalMatchingCount, 2)
    }

    func testProjectorShowsPendingOutboundMessageUntilMatchingCanonicalClientIDArrives() {
        let pending = PendingOutboundMessage(
            id: ClientUserMessageID(rawValue: "dock-msg:1"),
            threadID: "thread-a",
            input: [TurnUserInputDTO(text: "Run the smoke test")],
            createdAt: Date(timeIntervalSince1970: 2_000),
            deliveryState: .submittedUpstream,
            canonicalTurnID: "turn-1"
        )
        let pendingSnapshot = ThreadDetailSnapshot(
            header: makeHeader(),
            liveState: .live,
            events: [],
            pendingOutboundMessages: [pending]
        )

        let pendingRender = ThreadDetailRenderProjector().render(
            snapshot: pendingSnapshot,
            options: ThreadDetailRenderOptions(filter: .default, visibleLimit: 10),
            revision: RenderRevision(rawValue: 6)
        )

        XCTAssertEqual(pendingRender.rows.map(\.event.body), ["Run the smoke test"])
        XCTAssertEqual(pendingRender.rows.first?.event.clientID, "dock-msg:1")
        XCTAssertEqual(pendingRender.rows.first?.event.outboundDeliveryState, .submittedUpstream)
        XCTAssertTrue(pendingRender.hasUnfilteredEvents)

        let canonical = ThreadEvent(
            id: "host:test/thread:thread-a/turn:turn-1/item:item-1/row:userMessage",
            kind: .userMessage,
            visibilityCategory: .message,
            title: "User message",
            body: "Run the smoke test",
            date: Date(timeIntervalSince1970: 2_001),
            turnID: "turn-1",
            itemID: "item-1",
            displayOrderKey: "0000000000000000000|canonical",
            clientID: "dock-msg:1"
        )
        let canonicalSnapshot = ThreadDetailSnapshot(
            header: makeHeader(),
            liveState: .live,
            events: [canonical],
            pendingOutboundMessages: [pending]
        )

        let canonicalRender = ThreadDetailRenderProjector().render(
            snapshot: canonicalSnapshot,
            options: ThreadDetailRenderOptions(filter: .default, visibleLimit: 10),
            revision: RenderRevision(rawValue: 7)
        )

        XCTAssertEqual(canonicalRender.rows.map(\.event.id), [canonical.id])
        XCTAssertEqual(canonicalRender.rows.map(\.event.body), ["Run the smoke test"])
        XCTAssertEqual(canonicalRender.rows.first?.event.outboundDeliveryState, nil)
    }

    private func makeHeader() -> ThreadDetailHeader {
        let host = makeHost()
        let projectionID = "host:\(host.id)/thread:thread-a/row:threadCard"
        let row = DockRowViewModel(
            threadIdentity: HostScopedThreadID(hostID: host.id, threadID: "thread-a"),
            projectionID: projectionID,
            backendSessionID: "backend-thread-a",
            title: "Thread A",
            hostDisplayName: host.displayName,
            hostEndpoint: host.endpoint.displayEndpoint,
            repository: "codex-client",
            branch: "main",
            status: .running,
            lastActivity: "now",
            lastActivityDate: Date(timeIntervalSince1970: 1_000),
            displayOrderKey: "9999999999000000|0001|\(projectionID)",
            summary: "summary",
            rail: .blue,
            label: nil,
            origin: .humanInteractive(subtype: .cli)
        )
        return ThreadDetailHeader(host: host, row: row)
    }
}

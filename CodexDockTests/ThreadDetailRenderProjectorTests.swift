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
            displayOrderKey: "0000000000000000000|\(projectionID)",
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

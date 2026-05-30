import XCTest
@testable import CodexDock

final class ThreadDetailRenderProjectorTests: XCTestCase {
    func testProjectorFiltersVisibleWindowAndAttachesRequestCard() {
        let event = ThreadEvent(
            id: "request-approval-1",
            kind: .request,
            visibilityCategory: .request,
            title: "Approval",
            body: "Allow command?",
            date: Date(timeIntervalSince1970: 1_000),
            turnID: "turn-1",
            itemID: "item-1"
        )
        let card = ServerRequestCard(
            id: "request-approval-1",
            requestID: .string("approval-1"),
            method: "item/commandExecution/requestApproval",
            threadID: "thread-a",
            turnID: "turn-1",
            itemID: "item-1",
            kind: .commandApproval,
            title: "Approval",
            summary: "Allow command?",
            detail: "Allow command?",
            params: nil,
            requestedAt: Date(timeIntervalSince1970: 1_000)
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
                    date: Date(timeIntervalSince1970: 2_000)
                ),
                event,
            ]
        )

        let render = ThreadDetailRenderProjector().render(
            snapshot: snapshot,
            requestCards: [card],
            options: ThreadDetailRenderOptions(filter: .all, visibleLimit: 10),
            revision: RenderRevision(rawValue: 3)
        )

        XCTAssertEqual(render.revision, RenderRevision(rawValue: 3))
        XCTAssertEqual(render.rows.map(\.event.id), ["message-1", "request-approval-1"])
        XCTAssertEqual(render.rows[1].requestCard?.id, "request-approval-1")
        XCTAssertTrue(render.hasUnfilteredEvents)
    }

    private func makeHeader() -> ThreadDetailHeader {
        let host = makeHost()
        let row = DockRowViewModel(
            id: HostScopedThreadID(hostID: host.id, threadID: "thread-a"),
            backendSessionID: "backend-thread-a",
            title: "Thread A",
            hostDisplayName: host.displayName,
            hostEndpoint: host.endpoint.displayEndpoint,
            repository: "codex-client",
            branch: "main",
            status: .running,
            lastActivity: "now",
            lastActivityDate: Date(timeIntervalSince1970: 1_000),
            summary: "summary",
            rail: .blue,
            label: nil,
            origin: .humanInteractive(subtype: .cli)
        )
        return ThreadDetailHeader(host: host, row: row)
    }
}

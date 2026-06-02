import XCTest
@testable import CodexDock

final class ThreadDetailScreenStoreTests: XCTestCase {
    @MainActor
    func testScreenStorePublishesFilteredRenderSnapshot() async {
        let store = ThreadDetailScreenStore(header: makeHeader())
        let snapshot = ThreadDetailSnapshot(
            header: makeHeader(),
            liveState: .live,
            events: [
                ThreadEvent(
                    id: "message-1",
                    kind: .agentMessage,
                    visibilityCategory: .message,
                    title: "Agent",
                    body: "Visible",
                    date: Date(timeIntervalSince1970: 2_000),
                    displayOrderKey: "0000000000000000000|message-1"
                ),
                ThreadEvent(
                    id: "system-1",
                    kind: .system,
                    visibilityCategory: .system,
                    title: "System",
                    body: "Hidden by default",
                    date: Date(timeIntervalSince1970: 1_000),
                    displayOrderKey: "0000000000000000001|system-1"
                ),
            ]
        )

        store.start()
        store.publish(snapshot: snapshot)

        let render = await waitForLoadedRender(in: store)
        XCTAssertEqual(render?.rows.map(\.event.id), ["message-1"])

        store.setFilter(.all)
        let allRender = await waitForLoadedRender(
            in: store,
            where: { $0.revision.rawValue > (render?.revision.rawValue ?? 0) }
        )
        XCTAssertEqual(allRender?.rows.map(\.event.id), ["message-1", "system-1"])
    }

    @MainActor
    private func waitForLoadedRender(
        in store: ThreadDetailScreenStore,
        where predicate: @escaping (ThreadDetailRenderSnapshot) -> Bool = { _ in true },
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> ThreadDetailRenderSnapshot? {
        for _ in 0..<50 {
            if case .loaded(let render) = store.state,
               predicate(render) {
                return render
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for Thread Detail render snapshot", file: file, line: line)
        return nil
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

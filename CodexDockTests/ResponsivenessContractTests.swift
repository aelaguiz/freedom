import XCTest
@testable import CodexDock

final class ResponsivenessContractTests: XCTestCase {
    func testThreadRenderLargeFixturePublishesOnlyInitialVisibleWindow() {
        let events = Array(stride(from: 999, through: 0, by: -1)).enumerated().map { offset, index in
            ThreadEvent(
                id: "event-\(index)",
                kind: .agentMessage,
                visibilityCategory: .message,
                title: "Agent",
                body: "Message \(index)",
                date: Date(timeIntervalSince1970: TimeInterval(index)),
                displayOrderKey: String(format: "%016d|event-%03d", offset, index)
            )
        }
        let snapshot = ThreadDetailSnapshot(
            header: makeHeader(),
            liveState: .live,
            events: events
        )

        let render = ThreadDetailRenderProjector().render(
            snapshot: snapshot,
            options: ThreadDetailRenderOptions(),
            revision: RenderRevision(rawValue: 7)
        )

        XCTAssertEqual(
            render.rows.count,
            CodexDockConstants.Rendering.threadInitialVisibleWindowRows
        )
        XCTAssertEqual(render.visibleWindow.totalMatchingCount, 1_000)
        XCTAssertEqual(render.rows.first?.event.id, "event-999")
    }

    func testRenderSignpostNamesAreStableContractValues() {
        XCTAssertEqual(String(describing: RenderSignpostName.dockRenderProject), "dock.render.project")
        XCTAssertEqual(String(describing: RenderSignpostName.threadModelNormalize), "thread.model.normalize")
        XCTAssertEqual(String(describing: RenderSignpostName.threadRenderProject), "thread.render.project")
        XCTAssertEqual(String(describing: RenderSignpostName.threadMainPublish), "thread.main.publish")
        XCTAssertEqual(String(describing: RenderSignpostName.connectivityRenderProject), "connectivity.render.project")
    }

    @MainActor
    func testRuntimeStoresExposeScreenStoresInsteadOfFeatureViewProjection() throws {
        let host = makeHost()
        let runtime = ClientRuntime(registry: try HostRegistry(hosts: [host]))

        let dockStore = runtime.makeDockStore()
        let archiveStore = runtime.makeArchiveStore()
        let hostStore = runtime.makeHostSettingsStore()
        let connectivityStore = runtime.makeConnectivityScreenStore()

        XCTAssertNotNil(dockStore.screenStore)
        XCTAssertNotNil(archiveStore.screenStore)
        XCTAssertNotNil(hostStore.screenStore)
        XCTAssertEqual(connectivityStore.snapshot.hosts.map(\.id), [host.id])
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

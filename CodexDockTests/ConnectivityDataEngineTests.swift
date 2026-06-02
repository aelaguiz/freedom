import XCTest
@testable import CodexDock

final class ConnectivityDataEngineTests: XCTestCase {
    func testEngineAppliesRuntimeEventsAndProjectsOverallStatus() async throws {
        let host = makeHost()
        let registry = try HostRegistry(hosts: [host])
        let engine = ConnectivityDataEngine(
            registry: registry,
            now: { Date(timeIntervalSince1970: 1_000) }
        )

        let checking = await engine.apply(
            ConnectivityRuntimeEvent(
                source: .dock,
                hostID: host.id,
                route: "dock/subscribe",
                status: "checking",
                phase: .checking,
                recordedAt: Date(timeIntervalSince1970: 1_000)
            )
        )
        let loaded = await engine.apply(
            ConnectivityRuntimeEvent(
                source: .dock,
                hostID: host.id,
                route: "dock/subscribe",
                status: "3 sessions",
                phase: .online("3 sessions"),
                recordedAt: Date(timeIntervalSince1970: 2_000)
            )
        )

        XCTAssertEqual(checking.hosts.map(\.phase), [.checking])
        XCTAssertEqual(checking.overallStatus, .checking("Checking"))
        XCTAssertEqual(loaded.hosts.map(\.phase), [.online("3 sessions")])
        XCTAssertEqual(loaded.hosts.map(\.lastSuccessAt), [Date(timeIntervalSince1970: 2_000)])
        XCTAssertEqual(loaded.overallStatus, .online("3 sessions"))
    }

    func testEngineTreatsWindowedLoadedEventsAsOnline() async throws {
        let host = makeHost()
        let registry = try HostRegistry(hosts: [host])
        let engine = ConnectivityDataEngine(registry: registry)

        let snapshot = await engine.apply(
            ConnectivityRuntimeEvent(
                source: .dock,
                hostID: host.id,
                route: "dock/subscribe",
                status: "250 sessions, Showing 250 of 964",
                phase: .online("250 sessions"),
                recordedAt: Date(timeIntervalSince1970: 2_000)
            )
        )

        XCTAssertEqual(snapshot.hosts.map(\.phase), [.online("250 sessions")])
        XCTAssertEqual(snapshot.overallStatus, .online("250 sessions"))
    }

    @MainActor
    func testConnectivityScreenStoreDrainsRuntimeSinkDownstream() async throws {
        let host = makeHost()
        let registry = try HostRegistry(hosts: [host])
        let sink = ConnectivityEventSink()
        let appStore = AppConnectivityStore(registry: registry)
        let screenStore = ConnectivityScreenStore(
            registry: registry,
            eventSink: sink,
            now: { Date(timeIntervalSince1970: 1_000) }
        )

        screenStore.start(mirroring: appStore)
        await sink.record(
            ConnectivityRuntimeEvent(
                source: .dock,
                hostID: host.id,
                route: "dock/subscribe",
                status: "Loaded",
                phase: .online("Loaded"),
                recordedAt: Date(timeIntervalSince1970: 2_000)
            )
        )

        let snapshot = await waitForConnectivitySnapshot(in: screenStore)
        let appHosts = appStore.hosts

        XCTAssertEqual(snapshot?.hosts.map(\.phase), [.online("Loaded")])
        XCTAssertEqual(appHosts.map(\.phase), [.online("Loaded")])
    }

    @MainActor
    private func waitForConnectivitySnapshot(
        in store: ConnectivityScreenStore,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> ConnectivityRenderSnapshot? {
        for _ in 0..<50 {
            if store.snapshot.hosts.contains(where: { $0.phase == .online("Loaded") }) {
                return store.snapshot
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for connectivity snapshot", file: file, line: line)
        return nil
    }
}

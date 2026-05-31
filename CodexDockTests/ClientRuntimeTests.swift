import XCTest
@testable import CodexDock

final class ClientRuntimeTests: XCTestCase {
    func testRuntimeCreatesScreenFactoryDescriptorsWithoutOldStores() throws {
        let runtime = try makeRuntime()

        let factories = [
            runtime.makeDockScreenStoreFactory(),
            runtime.makeThreadDetailScreenStoreFactory(),
            runtime.makeArchiveScreenStoreFactory(),
            runtime.makeHostSettingsScreenStoreFactory(),
            runtime.makeConnectivityScreenStoreFactory()
        ]

        XCTAssertEqual(factories.map(\.kind), [
            .dock,
            .threadDetail,
            .archive,
            .hosts,
            .connectivity
        ])
        XCTAssertEqual(factories.map(\.hostCount), [1, 1, 1, 1, 1])
        XCTAssertTrue(factories.allSatisfy(\.usesRuntimeConnectivitySink))
    }

    func testConnectivityEventSinkRecordsAndDrainsEvents() async {
        let sink = ConnectivityEventSink()
        let event = ConnectivityRuntimeEvent(
            source: .dock,
            hostID: "host-a",
            route: "dock/subscribe",
            status: "loaded",
            recordedAt: Date(timeIntervalSince1970: 1_000)
        )

        await sink.record(event)

        let snapshot = await sink.snapshot()
        let drained = await sink.drain()
        let emptySnapshot = await sink.snapshot()

        XCTAssertEqual(snapshot, [event])
        XCTAssertEqual(drained, [event])
        XCTAssertEqual(emptySnapshot, [])
    }

    func testConnectivityEventSinkDrainsBacklogAtomicallyWithStreamCreation() async {
        let sink = ConnectivityEventSink()
        let backlogEvent = ConnectivityRuntimeEvent(
            source: .dock,
            hostID: "host-a",
            route: "dock/subscribe",
            status: "loaded",
            recordedAt: Date(timeIntervalSince1970: 1_000)
        )
        let streamedEvent = ConnectivityRuntimeEvent(
            source: .threadDetail,
            hostID: "host-a",
            route: "thread/detail",
            status: "live",
            recordedAt: Date(timeIntervalSince1970: 2_000)
        )

        await sink.record(backlogEvent)
        let (stream, backlog) = await sink.makeStreamDrainingBacklog()
        let snapshotAfterDrain = await sink.snapshot()

        let nextEventTask = Task {
            var iterator = stream.makeAsyncIterator()
            return await iterator.next()
        }
        await sink.record(streamedEvent)
        let nextEvent = await nextEventTask.value

        XCTAssertEqual(backlog, [backlogEvent])
        XCTAssertEqual(snapshotAfterDrain, [])
        XCTAssertEqual(nextEvent, streamedEvent)
    }

    func testRuntimeUsesInjectedClock() throws {
        let date = Date(timeIntervalSince1970: 123)
        let runtime = try makeRuntime(now: { date })

        XCTAssertEqual(runtime.currentDate(), date)
    }

    @MainActor
    func testRuntimeBuildsRootStoresFromSharedRegistry() throws {
        let runtime = try makeRuntime()

        let dockStore = runtime.makeDockStore()
        let archiveStore = runtime.makeArchiveStore()
        let hostsStore = runtime.makeHostSettingsStore()

        XCTAssertEqual(dockStore.hostConfiguration?.id, runtime.registry.hosts[0].id)
        XCTAssertEqual(hostsStore.registry, runtime.registry)
        if case .idle(let hosts) = dockStore.screenStore.state {
            XCTAssertEqual(hosts.map(\.id), runtime.registry.hosts.map(\.id))
        } else {
            XCTFail("Expected Dock screen store to start idle, got \(dockStore.screenStore.state)")
        }
        if case .idle(let hosts) = archiveStore.state {
            XCTAssertEqual(hosts.map(\.id), runtime.registry.hosts.map(\.id))
        } else {
            XCTFail("Expected archive store to start idle, got \(archiveStore.state)")
        }
    }

    @MainActor
    func testRuntimeDockStoreEmitsConnectivityFacts() async throws {
        let sink = ConnectivityEventSink()
        let runtime = try makeRuntime(connectivityEventSink: sink)
        let host = runtime.registry.hosts[0]
        let store = runtime.makeDockStore(
            streamClient: LoaderBackedThreadCardStreamClient(
                loader: FakeThreadCardFixtureLoader(
                    mode: .success(
                        ThreadCardFixtureResult(
                            fixtures: [
                                makeThreadCardFixtureSummary(
                                    hostID: host.id,
                                    threadID: "thread-a",
                                    branch: "main",
                                    status: .active(activeFlags: []),
                                    lastActivity: Date(timeIntervalSince1970: 1_000),
                                    prompt: "Runtime connectivity"
                                )
                            ]
                        )
                    )
                )
            )
        )

        await store.load()

        let events = await waitForConnectivityEvents(in: sink)
        XCTAssertTrue(events.contains { $0.source == .dock && $0.route == "dock/subscribe" })
    }

    @MainActor
    func testRuntimeThreadDetailStoreEmitsConnectivityFacts() async throws {
        let sink = ConnectivityEventSink()
        let runtime = try makeRuntime(connectivityEventSink: sink)
        let host = runtime.registry.hosts[0]
        let row = makeDetailRow(hostID: host.id, threadID: "thread-a")
        let session = FakeThreadDetailSession(
            readResult: .success(ThreadReadResponseDTO(thread: ThreadDTO(id: "thread-a", turns: []))),
            resumeResult: .success(ThreadResumeResponseDTO(thread: ThreadDTO(id: "thread-a", turns: [])))
        )
        let store = runtime.makeThreadDetailStore(
            host: host,
            row: row,
            factory: FakeThreadDetailSessionFactory(session: session)
        )

        await store.load()

        let events = await waitForConnectivityEvents(in: sink)
        XCTAssertTrue(events.contains { $0.source == .threadDetail && $0.route == "thread/detail" })
    }

    private func makeRuntime(
        connectivityEventSink: ConnectivityEventSink = ConnectivityEventSink(),
        now: @escaping @Sendable () -> Date = Date.init
    ) throws -> ClientRuntime {
        let host = try DockHostConfiguration(host: "192.168.50.117", port: 4510)
        let registry = try HostRegistry(hosts: [host])
        return ClientRuntime(
            registry: registry,
            connectivityEventSink: connectivityEventSink,
            now: now
        )
    }

    @MainActor
    private func waitForConnectivityEvents(
        in sink: ConnectivityEventSink,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> [ConnectivityRuntimeEvent] {
        for _ in 0..<50 {
            let events = await sink.snapshot()
            if !events.isEmpty {
                return events
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for connectivity events", file: file, line: line)
        return []
    }
}

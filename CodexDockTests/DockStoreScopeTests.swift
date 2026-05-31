import XCTest
@testable import CodexDock

final class DockStoreScopeTests: XCTestCase {
    @MainActor
    func testDockLoadRequestsHumanAndAgentsScopesPerActiveHost() async throws {
        let amir = makeHost()
        let home = makeHost(url: "ws://100.66.11.7:4510")
        let registry = try HostRegistry(hosts: [amir, home])
        let loader = QueryRoutedThreadCardFixtureLoader(results: [
            QueryRoutedThreadCardFixtureLoader.key(hostID: amir.id, query: .activeHuman): .success(
                ThreadCardFixtureResult(fixtures: [])
            ),
            QueryRoutedThreadCardFixtureLoader.key(hostID: amir.id, query: .activeAgents): .success(
                ThreadCardFixtureResult(fixtures: [])
            ),
            QueryRoutedThreadCardFixtureLoader.key(hostID: home.id, query: .activeHuman): .success(
                ThreadCardFixtureResult(fixtures: [])
            ),
            QueryRoutedThreadCardFixtureLoader.key(hostID: home.id, query: .activeAgents): .success(
                ThreadCardFixtureResult(fixtures: [])
            )
        ])
        let store = DockStore(registry: registry, streamClient: LoaderBackedThreadCardStreamClient(loader: loader))

        await store.load()

        let amirQueries = await loader.recordedQueries(for: amir.id)
        let homeQueries = await loader.recordedQueries(for: home.id)

        XCTAssertEqual(sortedQueries(amirQueries), [
            .activeAgents,
            .activeHuman
        ])
        XCTAssertEqual(sortedQueries(homeQueries), [
            .activeAgents,
            .activeHuman
        ])
    }

    func testAgentsQueryUsesExplicitNonInternalSourceKinds() {
        XCTAssertEqual(ThreadCardFixtureQuery.activeAgents.sourceKinds, [
            .exec,
            .appServer,
            .subAgentReview,
            .subAgentCompact,
            .subAgentThreadSpawn,
            .subAgentOther,
            .unknown
        ])
    }

    @MainActor
    func testDockSnapshotSourceFiltersAndNoNeedsMeStatus() async {
        let host = makeHost()
        let loader = QueryRoutedThreadCardFixtureLoader(results: [
            QueryRoutedThreadCardFixtureLoader.key(hostID: host.id, query: .activeHuman): .success(
                ThreadCardFixtureResult(fixtures: [
                    makeThreadCardFixtureSummary(
                        hostID: host.id,
                        threadID: "human-waiting",
                        branch: "main",
                        status: .active(activeFlags: [.waitingOnUserInput]),
                        lastActivity: Date(timeIntervalSince1970: 1_900),
                        prompt: "Human waiting"
                    ),
                    makeThreadCardFixtureSummary(
                        hostID: host.id,
                        threadID: "human-not-loaded",
                        branch: "main",
                        status: .notLoaded,
                        lastActivity: Date(timeIntervalSince1970: 1_800),
                        prompt: "Human not loaded"
                    )
                ])
            ),
            QueryRoutedThreadCardFixtureLoader.key(hostID: host.id, query: .activeAgents): .success(
                ThreadCardFixtureResult(fixtures: [
                    makeThreadCardFixtureSummary(
                        hostID: host.id,
                        threadID: "agent-running",
                        branch: "main",
                        status: .active(activeFlags: []),
                        lastActivity: Date(timeIntervalSince1970: 1_950),
                        prompt: "Agent running",
                        origin: .agentOrAutomation(subtype: .exec)
                    ),
                    makeThreadCardFixtureSummary(
                        hostID: host.id,
                        threadID: "unknown-origin",
                        branch: "main",
                        status: .idle,
                        lastActivity: Date(timeIntervalSince1970: 1_850),
                        prompt: "Unknown origin",
                        origin: .unknown()
                    )
                ])
            )
        ])
        let store = DockStore(host: host, streamClient: LoaderBackedThreadCardStreamClient(loader: loader))

        await store.load()

        guard case let .loaded(snapshot) = store.state else {
            return XCTFail("Expected loaded state, got \(store.state)")
        }

        XCTAssertEqual(snapshot.rowCount, 4)
        XCTAssertFalse(snapshot.rows.contains { $0.status.label == "Needs me" })
        XCTAssertEqual(snapshot.rows.first { $0.id.threadID == "human-waiting" }?.status, .needsInput)
        XCTAssertEqual(snapshot.rows.first { $0.id.threadID == "human-not-loaded" }?.status, .dormant)

        let humanProjection = snapshot.project(options: .init(lens: .newest, filters: DockFilterState(source: .human)))
        let agentsProjection = snapshot.project(options: .init(lens: .newest, filters: DockFilterState(source: .agents)))
        let unknownProjection = snapshot.project(options: .init(lens: .newest, filters: DockFilterState(source: .unknown, showsIdle: true)))
        let defaultProjection = snapshot.project(options: .init(lens: .newest))
        let idleVisibleProjection = snapshot.project(options: .init(lens: .newest, filters: DockFilterState(showsIdle: true)))

        XCTAssertEqual(humanProjection.rows.map(\.id.threadID), ["human-waiting", "human-not-loaded"])
        XCTAssertEqual(agentsProjection.rows.map(\.id.threadID), ["agent-running"])
        XCTAssertEqual(unknownProjection.rows.map(\.id.threadID), ["unknown-origin"])
        XCTAssertEqual(defaultProjection.rows.count, 3)
        XCTAssertEqual(defaultProjection.hiddenCounts.idle, 1)
        XCTAssertEqual(idleVisibleProjection.rows.count, 4)

        XCTAssertTrue(humanProjection.rows.allSatisfy {
            $0.origin.kind == .humanInteractive
        })
        XCTAssertTrue(agentsProjection.rows.allSatisfy {
            $0.origin.kind != .humanInteractive
        })
    }

    @MainActor
    func testDockDeduplicatesScopesAndPrefersAgentOrigin() async {
        let host = makeHost()
        let loader = QueryRoutedThreadCardFixtureLoader(results: [
            QueryRoutedThreadCardFixtureLoader.key(hostID: host.id, query: .activeHuman): .success(
                ThreadCardFixtureResult(fixtures: [
                    makeThreadCardFixtureSummary(
                        hostID: host.id,
                        threadID: "shared-thread",
                        branch: "main",
                        status: .idle,
                        lastActivity: Date(timeIntervalSince1970: 1_900),
                        prompt: "Human copy"
                    )
                ])
            ),
            QueryRoutedThreadCardFixtureLoader.key(hostID: host.id, query: .activeAgents): .success(
                ThreadCardFixtureResult(fixtures: [
                    makeThreadCardFixtureSummary(
                        hostID: host.id,
                        threadID: "shared-thread",
                        branch: "main",
                        status: .active(activeFlags: []),
                        lastActivity: Date(timeIntervalSince1970: 1_950),
                        prompt: "Agent copy",
                        origin: .agentOrAutomation(subtype: .exec)
                    )
                ])
            )
        ])
        let store = DockStore(host: host, streamClient: LoaderBackedThreadCardStreamClient(loader: loader))

        await store.load()

        guard case let .loaded(snapshot) = store.state else {
            return XCTFail("Expected loaded state, got \(store.state)")
        }

        let agentRows = snapshot.project(options: .init(lens: .newest, filters: DockFilterState(source: .agents))).rows
        XCTAssertEqual(snapshot.rowCount, 1)
        XCTAssertEqual(agentRows.map(\.title), ["Agent copy"])
        XCTAssertEqual(agentRows.map(\.origin.kind), [.agentOrAutomation])
        XCTAssertTrue(snapshot.project(options: .init(lens: .newest, filters: DockFilterState(source: .human))).rows.isEmpty)
    }

    @MainActor
    func testDockReportsPartialWhenAgentsScopeFails() async {
        let host = makeHost()
        let loader = QueryRoutedThreadCardFixtureLoader(results: [
            QueryRoutedThreadCardFixtureLoader.key(hostID: host.id, query: .activeHuman): .success(
                ThreadCardFixtureResult(fixtures: [
                    makeThreadCardFixtureSummary(
                        hostID: host.id,
                        threadID: "human-row",
                        branch: "main",
                        status: .idle,
                        lastActivity: Date(timeIntervalSince1970: 1_900),
                        prompt: "Human row"
                    )
                ])
            ),
            QueryRoutedThreadCardFixtureLoader.key(hostID: host.id, query: .activeAgents): .failure(
                .offline("Agents unreachable")
            )
        ])
        let store = DockStore(host: host, streamClient: LoaderBackedThreadCardStreamClient(loader: loader))

        await store.load()

        guard case let .loaded(snapshot) = store.state else {
            return XCTFail("Expected loaded state, got \(store.state)")
        }

        XCTAssertEqual(snapshot.rowCount, 1)
        XCTAssertEqual(snapshot.hostStates.map(\.status), [
            .partial(rowCount: 1, message: "Agents: Agents unreachable")
        ])
    }

    @MainActor
    func testDockReportsPartialWhenHumanScopeFailsButAgentsLoad() async {
        let host = makeHost()
        let loader = QueryRoutedThreadCardFixtureLoader(results: [
            QueryRoutedThreadCardFixtureLoader.key(hostID: host.id, query: .activeHuman): .failure(
                .offline("Dock unreachable")
            ),
            QueryRoutedThreadCardFixtureLoader.key(hostID: host.id, query: .activeAgents): .success(
                ThreadCardFixtureResult(fixtures: [
                    makeThreadCardFixtureSummary(
                        hostID: host.id,
                        threadID: "agent-row",
                        branch: "main",
                        status: .active(activeFlags: []),
                        lastActivity: Date(timeIntervalSince1970: 1_950),
                        prompt: "Agent row",
                        origin: .agentOrAutomation(subtype: .exec)
                    )
                ])
            )
        ])
        let store = DockStore(host: host, streamClient: LoaderBackedThreadCardStreamClient(loader: loader))

        await store.load()

        guard case let .loaded(snapshot) = store.state else {
            return XCTFail("Expected loaded state, got \(store.state)")
        }

        XCTAssertEqual(snapshot.rowCount, 1)
        XCTAssertEqual(snapshot.hostStates.map(\.status), [
            .partial(rowCount: 1, message: "Dock: Dock unreachable")
        ])
        XCTAssertEqual(snapshot.project(options: .init(lens: .newest, filters: DockFilterState(source: .agents))).rows.count, 1)
        XCTAssertEqual(snapshot.project(options: .init(lens: .newest, filters: DockFilterState(source: .human))).rows.count, 0)
    }

    @MainActor
    func testHostSettingsTestUsesDefaultHumanQuery() async throws {
        let host = makeHost()
        let registry = try HostRegistry(hosts: [host])
        let loader = QueryRoutedThreadCardFixtureLoader(results: [
            QueryRoutedThreadCardFixtureLoader.key(hostID: host.id, query: .activeHuman): .success(
                ThreadCardFixtureResult(fixtures: [
                    makeThreadCardFixtureSummary(
                        hostID: host.id,
                        threadID: "human-row",
                        branch: "main",
                        status: .idle,
                        lastActivity: Date(timeIntervalSince1970: 1_900),
                        prompt: "Human row"
                    )
                ])
            ),
            QueryRoutedThreadCardFixtureLoader.key(hostID: host.id, query: .activeAgents): .failure(
                .error("Should not load Agents scope")
            )
        ])
        let store = HostSettingsStore(
            registry: registry,
            tester: loader,
            now: { Date(timeIntervalSince1970: 2_000) }
        )

        await store.test(host.id)

        let queries = await loader.recordedQueries(for: host.id)
        XCTAssertEqual(queries, [.activeHuman])
        XCTAssertEqual(
            store.rows.first(where: { $0.id == host.id })?.status,
            .online(rowCount: 1, checkedAt: Date(timeIntervalSince1970: 2_000))
        )
    }
}

private actor QueryRoutedThreadCardFixtureLoader: ThreadCardFixtureLoading {
    private let results: [String: FakeMode]
    private var queriesByHost: [String: [ThreadCardFixtureQuery]] = [:]

    init(results: [String: FakeMode]) {
        self.results = results
    }

    func recordedQueries(for hostID: String) -> [ThreadCardFixtureQuery] {
        queriesByHost[hostID] ?? []
    }

    func loadFixtures(
        for host: DockHostConfiguration,
        query: ThreadCardFixtureQuery
    ) async throws -> ThreadCardFixtureResult {
        var queries = queriesByHost[host.id] ?? []
        queries.append(query)
        queriesByHost[host.id] = queries

        let mode = results[Self.key(hostID: host.id, query: query)]
            ?? results[Self.key(hostID: "*", query: query)]
            ?? .failure(.error("Unexpected query \(Self.queryLabel(query)) for host \(host.id)"))

        switch mode {
        case let .success(result):
            return result
        case let .failure(error):
            throw error
        }
    }

    static func key(hostID: String, query: ThreadCardFixtureQuery) -> String {
        "\(hostID)::\(queryLabel(query))"
    }

    private static func queryLabel(_ query: ThreadCardFixtureQuery) -> String {
        if query == .activeHuman {
            return "activeHuman"
        }
        if query == .activeAgents {
            return "activeAgents"
        }
        if query == .archivedHuman {
            return "archivedHuman"
        }
        return "\(query.archived)::\(query.sourceKinds?.map(\.rawValue).joined(separator: ",") ?? "nil")"
    }
}

extension QueryRoutedThreadCardFixtureLoader: HostConnectionTesting {
    func testConnection(to host: DockHostConfiguration) async throws -> HostConnectionTestResult {
        try await testConnectionResult(to: host)
    }
}

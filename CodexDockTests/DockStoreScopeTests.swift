import XCTest
@testable import CodexDock

final class DockStoreScopeTests: XCTestCase {
    @MainActor
    func testDockLoadRequestsHumanAndAgentsScopesPerActiveHost() async throws {
        let amir = makeHost()
        let home = makeHost(url: "ws://100.66.11.7:4510")
        let registry = try HostRegistry(hosts: [amir, home])
        let loader = QueryRoutedDockSessionLoader(results: [
            QueryRoutedDockSessionLoader.key(hostID: amir.id, query: .activeHuman): .success(
                DockLoadResult(summaries: [])
            ),
            QueryRoutedDockSessionLoader.key(hostID: amir.id, query: .activeAgents): .success(
                DockLoadResult(summaries: [])
            ),
            QueryRoutedDockSessionLoader.key(hostID: home.id, query: .activeHuman): .success(
                DockLoadResult(summaries: [])
            ),
            QueryRoutedDockSessionLoader.key(hostID: home.id, query: .activeAgents): .success(
                DockLoadResult(summaries: [])
            )
        ])
        let store = DockStore(registry: registry, loader: loader)

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
        XCTAssertEqual(DockSessionQuery.activeAgents.sourceKinds, [
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
        let loader = QueryRoutedDockSessionLoader(results: [
            QueryRoutedDockSessionLoader.key(hostID: host.id, query: .activeHuman): .success(
                DockLoadResult(summaries: [
                    makeSummary(
                        hostID: host.id,
                        threadID: "human-waiting",
                        branch: "main",
                        status: .active(activeFlags: [.waitingOnUserInput]),
                        lastActivity: Date(timeIntervalSince1970: 1_900),
                        prompt: "Human waiting"
                    ),
                    makeSummary(
                        hostID: host.id,
                        threadID: "human-not-loaded",
                        branch: "main",
                        status: .notLoaded,
                        lastActivity: Date(timeIntervalSince1970: 1_800),
                        prompt: "Human not loaded"
                    )
                ])
            ),
            QueryRoutedDockSessionLoader.key(hostID: host.id, query: .activeAgents): .success(
                DockLoadResult(summaries: [
                    makeSummary(
                        hostID: host.id,
                        threadID: "agent-running",
                        branch: "main",
                        status: .active(activeFlags: []),
                        lastActivity: Date(timeIntervalSince1970: 1_950),
                        prompt: "Agent running",
                        origin: .agentOrAutomation(subtype: .exec)
                    ),
                    makeSummary(
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
        let store = DockStore(host: host, loader: loader)

        await store.load()

        guard case let .loaded(snapshot) = store.state else {
            return XCTFail("Expected loaded state, got \(store.state)")
        }

        XCTAssertEqual(snapshot.rowCount, 4)
        XCTAssertFalse(snapshot.rows.contains { $0.status.label == "Needs me" })
        XCTAssertEqual(snapshot.rows.first { $0.id.threadID == "human-waiting" }?.status, .running)

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
        let loader = QueryRoutedDockSessionLoader(results: [
            QueryRoutedDockSessionLoader.key(hostID: host.id, query: .activeHuman): .success(
                DockLoadResult(summaries: [
                    makeSummary(
                        hostID: host.id,
                        threadID: "shared-thread",
                        branch: "main",
                        status: .idle,
                        lastActivity: Date(timeIntervalSince1970: 1_900),
                        prompt: "Human copy"
                    )
                ])
            ),
            QueryRoutedDockSessionLoader.key(hostID: host.id, query: .activeAgents): .success(
                DockLoadResult(summaries: [
                    makeSummary(
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
        let store = DockStore(host: host, loader: loader)

        await store.load()

        guard case let .loaded(snapshot) = store.state else {
            return XCTFail("Expected loaded state, got \(store.state)")
        }

        let agentRows = snapshot.project(options: .init(lens: .newest, filters: DockFilterState(source: .agents))).rows
        XCTAssertEqual(snapshot.rowCount, 1)
        XCTAssertEqual(snapshot.mappingFailures, [])
        XCTAssertEqual(snapshot.scopeConflicts, [
            DockScopeConflictViewModel(
                threadID: HostScopedThreadID(hostID: host.id, threadID: "shared-thread"),
                backendThreadID: "shared-thread",
                winningScope: .agents
            )
        ])
        XCTAssertEqual(agentRows.map(\.title), ["Agent copy"])
        XCTAssertEqual(agentRows.map(\.origin.kind), [.agentOrAutomation])
        XCTAssertTrue(snapshot.project(options: .init(lens: .newest, filters: DockFilterState(source: .human))).rows.isEmpty)
    }

    @MainActor
    func testDockReportsPartialWhenAgentsScopeFails() async {
        let host = makeHost()
        let loader = QueryRoutedDockSessionLoader(results: [
            QueryRoutedDockSessionLoader.key(hostID: host.id, query: .activeHuman): .success(
                DockLoadResult(summaries: [
                    makeSummary(
                        hostID: host.id,
                        threadID: "human-row",
                        branch: "main",
                        status: .idle,
                        lastActivity: Date(timeIntervalSince1970: 1_900),
                        prompt: "Human row"
                    )
                ])
            ),
            QueryRoutedDockSessionLoader.key(hostID: host.id, query: .activeAgents): .failure(
                .offline("Agents unreachable")
            )
        ])
        let store = DockStore(host: host, loader: loader)

        await store.load()

        guard case let .loaded(snapshot) = store.state else {
            return XCTFail("Expected loaded state, got \(store.state)")
        }

        XCTAssertEqual(snapshot.rowCount, 1)
        XCTAssertEqual(snapshot.hostStates.map(\.status), [
            .partial(rowCount: 1, message: "Agents: Agents unreachable")
        ])
        XCTAssertEqual(snapshot.scopeLoadFailures.map(\.scope), [.agents])
        XCTAssertEqual(snapshot.scopeLoadFailures.map(\.message), ["Agents unreachable"])
    }

    @MainActor
    func testDockReportsPartialWhenHumanScopeFailsButAgentsLoad() async {
        let host = makeHost()
        let loader = QueryRoutedDockSessionLoader(results: [
            QueryRoutedDockSessionLoader.key(hostID: host.id, query: .activeHuman): .failure(
                .offline("Dock unreachable")
            ),
            QueryRoutedDockSessionLoader.key(hostID: host.id, query: .activeAgents): .success(
                DockLoadResult(summaries: [
                    makeSummary(
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
        let store = DockStore(host: host, loader: loader)

        await store.load()

        guard case let .loaded(snapshot) = store.state else {
            return XCTFail("Expected loaded state, got \(store.state)")
        }

        XCTAssertEqual(snapshot.rowCount, 1)
        XCTAssertEqual(snapshot.hostStates.map(\.status), [
            .partial(rowCount: 1, message: "Dock: Dock unreachable")
        ])
        XCTAssertEqual(snapshot.scopeLoadFailures.map(\.scope), [.human])
        XCTAssertEqual(snapshot.scopeLoadFailures.map(\.message), ["Dock unreachable"])
        XCTAssertEqual(snapshot.project(options: .init(lens: .newest, filters: DockFilterState(source: .agents))).rows.count, 1)
        XCTAssertEqual(snapshot.project(options: .init(lens: .newest, filters: DockFilterState(source: .human))).rows.count, 0)
    }

    @MainActor
    func testHostSettingsTestUsesDefaultHumanQuery() async throws {
        let host = makeHost()
        let registry = try HostRegistry(hosts: [host])
        let loader = QueryRoutedDockSessionLoader(results: [
            QueryRoutedDockSessionLoader.key(hostID: host.id, query: .activeHuman): .success(
                DockLoadResult(summaries: [
                    makeSummary(
                        hostID: host.id,
                        threadID: "human-row",
                        branch: "main",
                        status: .idle,
                        lastActivity: Date(timeIntervalSince1970: 1_900),
                        prompt: "Human row"
                    )
                ])
            ),
            QueryRoutedDockSessionLoader.key(hostID: host.id, query: .activeAgents): .failure(
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

private actor QueryRoutedDockSessionLoader: DockSessionLoading {
    private let results: [String: FakeMode]
    private var queriesByHost: [String: [DockSessionQuery]] = [:]

    init(results: [String: FakeMode]) {
        self.results = results
    }

    func recordedQueries(for hostID: String) -> [DockSessionQuery] {
        queriesByHost[hostID] ?? []
    }

    func loadSessions(
        for host: DockHostConfiguration,
        query: DockSessionQuery
    ) async throws -> DockLoadResult {
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

    static func key(hostID: String, query: DockSessionQuery) -> String {
        "\(hostID)::\(queryLabel(query))"
    }

    private static func queryLabel(_ query: DockSessionQuery) -> String {
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

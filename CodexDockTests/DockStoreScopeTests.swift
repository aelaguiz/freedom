import XCTest
@testable import CodexDock

final class DockStoreScopeTests: XCTestCase {
    @MainActor
    func testDockLoadRequestsHumanAndAgentsScopesPerActiveHost() async throws {
        let amir = makeHost()
        let home = makeHost(
            id: "Home",
            displayName: "Home",
            url: "ws://100.66.11.7:4510"
        )
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
    func testDockSnapshotCountsAndNoLeakRowsByTab() async {
        let host = makeHost()
        let loader = QueryRoutedDockSessionLoader(results: [
            QueryRoutedDockSessionLoader.key(hostID: host.id, query: .activeHuman): .success(
                DockLoadResult(summaries: [
                    makeSummary(
                        hostID: host.id,
                        threadID: "human-needs-me",
                        branch: "main",
                        status: .active(activeFlags: [.waitingOnUserInput]),
                        lastActivity: Date(timeIntervalSince1970: 1_900),
                        prompt: "Human needs input"
                    ),
                    makeSummary(
                        hostID: host.id,
                        threadID: "human-limited",
                        branch: "main",
                        status: .notLoaded,
                        lastActivity: Date(timeIntervalSince1970: 1_800),
                        prompt: "Human limited"
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
        XCTAssertEqual(tabCounts(snapshot), [
            .all: 2,
            .needsMe: 1,
            .running: 1,
            .limited: 1,
            .agents: 2
        ])

        XCTAssertEqual(
            tabCounts(snapshot.project(options: .init(selectedTab: .all, showsIdle: false))),
            [
                .all: 2,
                .needsMe: 1,
                .running: 1,
                .limited: 1,
                .agents: 1
            ]
        )
        XCTAssertEqual(
            tabCounts(snapshot.project(options: .init(selectedTab: .all, showsIdle: true))),
            [
                .all: 2,
                .needsMe: 1,
                .running: 1,
                .limited: 1,
                .agents: 2
            ]
        )

        XCTAssertTrue(rows(in: snapshot.sections(for: .all)).allSatisfy {
            $0.origin.kind == .humanInteractive
        })
        XCTAssertTrue(rows(in: snapshot.sections(for: .running)).allSatisfy {
            $0.origin.kind == .humanInteractive
        })
        XCTAssertTrue(rows(in: snapshot.sections(for: .agents)).allSatisfy {
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

        let agentRows = rows(in: snapshot.sections(for: .agents))
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
        XCTAssertTrue(snapshot.sections(for: .all).isEmpty)
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
        XCTAssertEqual(tabCounts(snapshot)[.agents], 1)
        XCTAssertEqual(tabCounts(snapshot)[.all], 0)
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

private enum FakeMode: Sendable {
    case success(DockLoadResult)
    case failure(DockLoadFailure)
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

private func makeHost(
    id: String = "Amir-M5",
    displayName: String = "Amir-M5",
    url: String? = nil
) -> DockHostConfiguration {
    let defaultURL = id == "Amir-M5" ? "ws://192.168.50.117:4500" : "ws://\(id):4500"
    let parsedURL = URL(string: url ?? defaultURL)!
    return try! DockHostConfiguration(
        host: parsedURL.host!,
        port: parsedURL.port!
    )
}

private func makeSummary(
    hostID: String,
    threadID: String,
    branch: String,
    status: SessionStatus,
    lastActivity: Date,
    prompt: String,
    origin: SessionOrigin = .humanInteractive(subtype: .cli)
) -> SessionSummary {
    SessionSummary(
        id: HostScopedThreadID(hostID: hostID, threadID: threadID),
        backendSessionID: "\(threadID)-session",
        displayTitle: prompt,
        status: status,
        repository: .known("codex-client"),
        workingDirectory: .known("/Users/aelaguiz/workspace/codex-client"),
        branch: .known(branch),
        lastActivity: lastActivity,
        shortEventSummary: .known("Assistant update for \(prompt)"),
        origin: origin
    )
}

private func sortedQueries(_ queries: [DockSessionQuery]) -> [DockSessionQuery] {
    queries.sorted { lhs, rhs in
        querySortKey(lhs) < querySortKey(rhs)
    }
}

private func querySortKey(_ query: DockSessionQuery) -> String {
    if query == .activeAgents {
        return "0-activeAgents"
    }
    if query == .activeHuman {
        return "1-activeHuman"
    }
    if query == .archivedHuman {
        return "2-archivedHuman"
    }
    return "3-\(query.archived)-\(query.sourceKinds?.map(\.rawValue).joined(separator: ",") ?? "nil")"
}

private func tabCounts(_ snapshot: DockSnapshot) -> [DockTabID: Int] {
    Dictionary(uniqueKeysWithValues: snapshot.tabs.map { ($0.id, $0.count) })
}

private func tabCounts(_ projection: DockSessionProjection) -> [DockTabID: Int] {
    Dictionary(uniqueKeysWithValues: projection.tabs.map { ($0.id, $0.count) })
}

private func rows(in sections: [DockSectionViewModel]) -> [DockRowViewModel] {
    sections.flatMap(\.rows)
}

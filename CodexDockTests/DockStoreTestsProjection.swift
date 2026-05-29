import XCTest
@testable import CodexDock

final class DockStoreTestsProjection: XCTestCase {
    func testNewestProjectionOrdersRowsByActivityBeforeStatus() {
        let snapshot = makeSnapshot(rows: [
            makeRow(threadID: "old-running", title: "Old running", branch: "main", status: .running, lastActivity: 100),
            makeRow(threadID: "new-not-loaded", title: "New not loaded", branch: "main", status: .notLoaded, lastActivity: 300)
        ])

        let projection = snapshot.project(options: .init(lens: .newest))

        XCTAssertEqual(projection.rows.map(\.id.threadID), ["new-not-loaded", "old-running"])
        XCTAssertEqual(projection.groups, [])
    }

    func testHostLensGroupsByHostAndPreservesNewestOrdering() {
        let amir = makeProjectionHost(host: "amir-m5.fairy-salmon.ts.net")
        let home = makeProjectionHost(host: "home.fairy-salmon.ts.net")
        let snapshot = makeSnapshot(
            rows: [
                makeRow(host: amir, threadID: "amir-old", title: "Amir old", branch: "main", status: .idle, lastActivity: 100),
                makeRow(host: home, threadID: "home-new", title: "Home new", branch: "main", status: .running, lastActivity: 300),
                makeRow(host: amir, threadID: "amir-new", title: "Amir new", branch: "main", status: .running, lastActivity: 200)
            ],
            hosts: [amir, home]
        )

        let projection = snapshot.project(options: .init(lens: .host, filters: DockFilterState(showsIdle: true)))

        XCTAssertEqual(projection.groups.map(\.title), ["Home", "Amir-M5"])
        XCTAssertEqual(projection.groups[1].rows.map(\.id.threadID), ["amir-new", "amir-old"])
        XCTAssertEqual(projection.groups[1].runningCount, 1)
    }

    func testHostLensExposesHiddenIdleCountPerHost() {
        let amir = makeProjectionHost(host: "amir-m5.fairy-salmon.ts.net")
        let snapshot = makeSnapshot(
            rows: [
                makeRow(host: amir, threadID: "amir-running", title: "Amir running", branch: "main", status: .running, lastActivity: 300),
                makeRow(host: amir, threadID: "amir-idle", title: "Amir idle", branch: "main", status: .idle, lastActivity: 400)
            ],
            hosts: [amir]
        )

        let projection = snapshot.project(options: .init(lens: .host))

        XCTAssertEqual(projection.groups.map(\.title), ["Amir-M5"])
        XCTAssertEqual(projection.groups[0].rows.map(\.id.threadID), ["amir-running"])
        XCTAssertEqual(projection.groups[0].hiddenIdleCount, 1)
        XCTAssertEqual(projection.hiddenCounts.idle, 1)
    }

    func testHostLensKeepsUnavailableHostVisibleWithoutRows() {
        let amir = makeProjectionHost(host: "amir-m5.fairy-salmon.ts.net")
        let home = makeProjectionHost(host: "home.fairy-salmon.ts.net")
        let snapshot = makeSnapshot(
            rows: [
                makeRow(host: amir, threadID: "amir-row", title: "Amir row", branch: "main", status: .running, lastActivity: 200)
            ],
            hosts: [amir, home],
            hostStates: [
                DockHostStateViewModel(host: DockHostViewModel(host: amir), status: .loaded(rowCount: 1)),
                DockHostStateViewModel(host: DockHostViewModel(host: home), status: .offline("Home unreachable"))
            ]
        )

        let projection = snapshot.project(options: .init(lens: .host))

        XCTAssertEqual(projection.groups.map(\.title), ["Amir-M5", "Home"])
        XCTAssertEqual(projection.groups[1].rows, [])
        XCTAssertTrue(projection.groups[1].isUnavailable)
        XCTAssertEqual(projection.groups[1].unavailableMessage, "Home unreachable")
    }

    func testBranchLensGroupsAcrossHostsAndRowsKeepHostIdentity() {
        let amir = makeProjectionHost(host: "amir-m5.fairy-salmon.ts.net")
        let home = makeProjectionHost(host: "home.fairy-salmon.ts.net")
        let snapshot = makeSnapshot(
            rows: [
                makeRow(host: amir, threadID: "amir-main", title: "Amir main", branch: "main", status: .running, lastActivity: 100),
                makeRow(host: home, threadID: "home-main", title: "Home main", branch: "main", status: .running, lastActivity: 300),
                makeRow(host: amir, threadID: "amir-feature", title: "Amir feature", branch: "feature/dock", status: .running, lastActivity: 200)
            ],
            hosts: [amir, home]
        )

        let projection = snapshot.project(options: .init(lens: .branch))

        XCTAssertEqual(projection.groups.map(\.title), ["main", "feature/dock"])
        XCTAssertEqual(projection.groups[0].rows.map(\.hostDisplayName), ["Home", "Amir-M5"])
        XCTAssertEqual(projection.groups[0].rows.map(\.id.threadID), ["home-main", "amir-main"])
    }

    func testProjectionSearchMatchesHostBranchRepoStatusLabelSummaryAndThreadIDCaseInsensitively() {
        let home = makeProjectionHost(host: "home.fairy-salmon.ts.net")
        let snapshot = makeSnapshot(
            rows: [
                makeRow(
                    host: home,
                    threadID: "THREAD-home-123",
                    title: "Runner",
                    branch: "Feature/Dock",
                    status: .running,
                    lastActivity: 300,
                    label: "Watch"
                )
            ],
            hosts: [home]
        )

        for query in ["home", "feature/dock", "codex-client", "running", "watch", "Summary for Runner", "home-123"] {
            XCTAssertEqual(
                snapshot.project(options: .init(lens: .newest, searchText: query)).rows.map(\.id.threadID),
                ["THREAD-home-123"],
                query
            )
        }
    }

    func testFiltersComposeSourceStatusBranchRepoHostAndIdle() {
        let amir = makeProjectionHost(host: "amir-m5.fairy-salmon.ts.net")
        let home = makeProjectionHost(host: "home.fairy-salmon.ts.net")
        let snapshot = makeSnapshot(
            rows: [
                makeRow(host: amir, threadID: "human-running", title: "Human running", branch: "main", status: .running, lastActivity: 300),
                makeRow(host: home, threadID: "agent-idle", title: "Agent idle", branch: "feature/dock", status: .idle, lastActivity: 200, origin: .agentOrAutomation(subtype: .exec)),
                makeRow(host: home, threadID: "human-not-loaded", title: "Human not loaded", branch: "feature/dock", status: .notLoaded, lastActivity: 100)
            ],
            hosts: [amir, home]
        )

        let filtered = DockFilterState(
            selectedHostIDs: [home.id],
            selectedBranches: ["feature/dock"],
            statusKinds: [.notLoaded],
            source: .human,
            showsIdle: false
        )

        let projection = snapshot.project(options: .init(lens: .newest, filters: filtered))

        XCTAssertEqual(projection.rows.map(\.id.threadID), ["human-not-loaded"])
        XCTAssertEqual(projection.summary.resultCount, 1)
        XCTAssertEqual(projection.summary.activeFilterCount, 4)
        XCTAssertTrue(projection.summary.text.contains("Host: Home"))
        XCTAssertTrue(projection.summary.text.contains("Branch: feature/dock"))
        XCTAssertTrue(projection.summary.text.contains("Status: Not loaded"))
        XCTAssertTrue(projection.summary.text.contains("Source: Human"))
        XCTAssertTrue(projection.summary.text.contains("Idle hidden"))
    }

    func testActiveSummaryNamesRepoSearchSelectedReposSourceAndSearch() {
        let snapshot = makeSnapshot(rows: [
            makeRow(threadID: "running", title: "Running", branch: "main", status: .running, lastActivity: 300)
        ])
        let filters = DockFilterState(
            repositoryQuery: "codex",
            selectedRepositories: ["codex-client"],
            source: .human,
            showsIdle: true
        )

        let projection = snapshot.project(options: .init(lens: .newest, searchText: "main", filters: filters))

        XCTAssertTrue(projection.summary.text.contains("Repos: 1, search: codex"))
        XCTAssertTrue(projection.summary.text.contains("Source: Human"))
        XCTAssertTrue(projection.summary.text.contains("Idle shown"))
        XCTAssertTrue(projection.summary.text.contains("Search: main"))
    }

    func testIdleHiddenCountUsesFilteredRowSet() {
        let snapshot = makeSnapshot(rows: [
            makeRow(threadID: "running", title: "Running", branch: "main", status: .running, lastActivity: 300),
            makeRow(threadID: "idle", title: "Idle", branch: "main", status: .idle, lastActivity: 400)
        ])

        let hidden = snapshot.project(options: .init(lens: .newest))
        let visible = snapshot.project(options: .init(lens: .newest, filters: DockFilterState(showsIdle: true)))

        XCTAssertEqual(hidden.rows.map(\.id.threadID), ["running"])
        XCTAssertEqual(hidden.hiddenCounts.idle, 1)
        XCTAssertEqual(visible.rows.map(\.id.threadID), ["idle", "running"])
    }

    func testNotLoadedOnlyEmptyReasonUsesProductCopy() {
        let snapshot = makeSnapshot(rows: [
            makeRow(threadID: "running", title: "Running", branch: "main", status: .running, lastActivity: 300)
        ])

        let projection = snapshot.project(
            options: .init(
                lens: .newest,
                filters: DockFilterState(statusKinds: [.notLoaded])
            )
        )

        XCTAssertEqual(projection.emptyReason, .notLoadedOnly)
        XCTAssertEqual(
            projection.emptyReason?.message,
            "These sessions exist in the list, but Dock does not have loaded thread detail for them."
        )
    }
}

private func makeSnapshot(
    rows: [DockRowViewModel],
    hosts: [DockHostConfiguration] = [makeProjectionHost()],
    hostStates: [DockHostStateViewModel]? = nil,
    isPartial: Bool = false
) -> DockSnapshot {
    let hostViewModels = hosts.map(DockHostViewModel.init)
    return DockSnapshot(
        host: hostViewModels[0],
        hosts: hostViewModels,
        hostStates: hostStates ?? hosts.map { host in
            DockHostStateViewModel(host: DockHostViewModel(host: host), status: .loaded(rowCount: rows.filter { $0.id.hostID == host.id }.count))
        },
        rows: rows,
        scopeLoadFailures: [],
        scopeConflicts: [],
        mappingFailures: [],
        isPartial: isPartial
    )
}

private func makeProjectionHost(host: String = "amir-m5.fairy-salmon.ts.net") -> DockHostConfiguration {
    try! DockHostConfiguration(host: host, port: 4510)
}

private func makeRow(
    host: DockHostConfiguration = makeProjectionHost(),
    threadID: String,
    title: String,
    branch: String,
    status: DockRowStatusKind,
    lastActivity: TimeInterval,
    label: String? = nil,
    origin: SessionOrigin = .humanInteractive(subtype: .cli)
) -> DockRowViewModel {
    DockRowViewModel(
        id: HostScopedThreadID(hostID: host.id, threadID: threadID),
        backendSessionID: "\(threadID)-session",
        title: title,
        hostDisplayName: host.displayName,
        hostEndpoint: host.endpoint.displayEndpoint,
        repository: "codex-client",
        branch: branch,
        status: status,
        lastActivity: "now",
        lastActivityDate: Date(timeIntervalSince1970: lastActivity),
        summary: "Summary for \(title)",
        rail: .blue,
        label: label,
        origin: origin
    )
}

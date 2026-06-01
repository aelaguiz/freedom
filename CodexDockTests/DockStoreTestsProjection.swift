import XCTest
@testable import CodexDock

final class DockStoreTestsProjection: XCTestCase {
    func testNewestProjectionOrdersRowsByActivityBeforeStatus() {
        let snapshot = makeSnapshot(rows: [
            makeRow(threadID: "old-running", title: "Old running", branch: "main", status: .running, lastActivity: 100),
            makeRow(threadID: "new-history", title: "New history", branch: "main", status: .dormant, lastActivity: 300)
        ])

        let projection = snapshot.project(options: .init(lens: .newest))

        XCTAssertEqual(projection.rows.map(\.id.threadID), ["new-history", "old-running"])
        XCTAssertEqual(projection.groups, [])
    }

    func testNewestProjectionOrdersCrossHostRowsByRelayOrderKey() {
        let amir = makeProjectionHost(host: "amir-m5.fairy-salmon.ts.net")
        let home = makeProjectionHost(host: "home.fairy-salmon.ts.net")
        let snapshot = makeSnapshot(
            rows: [
                makeRow(
                    host: home,
                    threadID: "home-old",
                    title: "Home old",
                    branch: "main",
                    status: .running,
                    lastActivity: 100,
                    orderKey: "000000000000:home-old"
                ),
                makeRow(
                    host: amir,
                    threadID: "amir-new",
                    title: "Amir new",
                    branch: "main",
                    status: .running,
                    lastActivity: 300,
                    orderKey: "000000000001:amir-new"
                )
            ],
            hosts: [amir, home]
        )

        let projection = snapshot.project(options: .init(lens: .newest))

        XCTAssertEqual(projection.rows.map(\.id.threadID), ["home-old", "amir-new"])
    }

    func testNewestProjectionUsesStableRowIDWhenRelayOrderKeysTie() {
        let hostA = makeProjectionHost(host: "sim-multi-host-a.local")
        let hostB = makeProjectionHost(host: "sim-multi-host-b.local")
        let tiedOrderKey = "9007197482258991:sim-shared-thread-id"
        let snapshot = makeSnapshot(
            rows: [
                makeRow(
                    host: hostB,
                    threadID: "sim-shared-thread-id",
                    title: "Simulator shared id from host B",
                    branch: "main",
                    status: .dormant,
                    lastActivity: 200,
                    orderKey: tiedOrderKey
                ),
                makeRow(
                    host: hostA,
                    threadID: "sim-shared-thread-id",
                    title: "Simulator shared id from host A",
                    branch: "main",
                    status: .dormant,
                    lastActivity: 200,
                    orderKey: tiedOrderKey
                )
            ],
            hosts: [hostA, hostB]
        )

        let projection = snapshot.project(options: .init(lens: .newest))

        XCTAssertEqual(
            projection.rows.map { "\($0.id.hostID)::\($0.id.threadID)" },
            [
                "sim-multi-host-a.local:4510::sim-shared-thread-id",
                "sim-multi-host-b.local:4510::sim-shared-thread-id"
            ]
        )
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

        let projection = snapshot.project(options: .init(lens: .host))

        XCTAssertEqual(projection.groups.map(\.title), ["Home", "Amir-M5"])
        XCTAssertEqual(projection.groups[1].rows.map(\.id.threadID), ["amir-new", "amir-old"])
        XCTAssertEqual(projection.groups[1].runningCount, 1)
    }

    func testHostLensIncludesIdleRowsByDefault() {
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
        XCTAssertEqual(projection.groups[0].rows.map(\.id.threadID), ["amir-idle", "amir-running"])
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

    func testFiltersComposeSourceStatusBranchRepoAndHost() {
        let amir = makeProjectionHost(host: "amir-m5.fairy-salmon.ts.net")
        let home = makeProjectionHost(host: "home.fairy-salmon.ts.net")
        let snapshot = makeSnapshot(
            rows: [
                makeRow(host: amir, threadID: "human-running", title: "Human running", branch: "main", status: .running, lastActivity: 300),
                makeRow(host: home, threadID: "agent-idle", title: "Agent idle", branch: "feature/dock", status: .idle, lastActivity: 200, origin: .agentOrAutomation(subtype: .exec)),
                makeRow(host: home, threadID: "human-history", title: "Human history", branch: "feature/dock", status: .dormant, lastActivity: 100)
            ],
            hosts: [amir, home]
        )

        let filtered = DockFilterState(
            selectedHostIDs: [home.id],
            selectedBranches: ["feature/dock"],
            statusKinds: [.dormant],
            source: .human
        )

        let projection = snapshot.project(options: .init(lens: .newest, filters: filtered))

        XCTAssertEqual(projection.rows.map(\.id.threadID), ["human-history"])
        XCTAssertEqual(projection.summary.resultCount, 1)
        XCTAssertEqual(projection.summary.activeFilterCount, 4)
        XCTAssertTrue(projection.summary.text.contains("Host: Home"))
        XCTAssertTrue(projection.summary.text.contains("Branch: feature/dock"))
        XCTAssertTrue(projection.summary.text.contains("Status: Not loaded"))
        XCTAssertTrue(projection.summary.text.contains("Source: Human"))
        XCTAssertFalse(projection.summary.text.contains("Idle hidden"))
        XCTAssertFalse(projection.summary.text.contains("Idle shown"))
    }

    func testActiveSummaryNamesRepoSearchSelectedReposSourceAndSearch() {
        let snapshot = makeSnapshot(rows: [
            makeRow(threadID: "running", title: "Running", branch: "main", status: .running, lastActivity: 300)
        ])
        let filters = DockFilterState(
            repositoryQuery: "codex",
            selectedRepositories: ["codex-client"],
            source: .human
        )

        let projection = snapshot.project(options: .init(lens: .newest, searchText: "main", filters: filters))

        XCTAssertTrue(projection.summary.text.contains("Repos: 1, search: codex"))
        XCTAssertTrue(projection.summary.text.contains("Source: Human"))
        XCTAssertTrue(projection.summary.text.contains("Search: main"))
        XCTAssertFalse(projection.summary.text.contains("Idle hidden"))
        XCTAssertFalse(projection.summary.text.contains("Idle shown"))
    }

    func testDefaultProjectionIncludesIdleRows() {
        let snapshot = makeSnapshot(rows: [
            makeRow(threadID: "running", title: "Running", branch: "main", status: .running, lastActivity: 300),
            makeRow(threadID: "idle", title: "Idle", branch: "main", status: .idle, lastActivity: 400)
        ])

        let projection = snapshot.project(options: .init(lens: .newest))

        XCTAssertEqual(projection.rows.map(\.id.threadID), ["idle", "running"])
    }

    func testPinnedAndBodyIdleRowsAreVisibleByDefault() {
        let snapshot = makeSnapshot(rows: [
            makeRow(threadID: "idle-pinned", title: "Idle pinned", branch: "main", status: .idle, lastActivity: 400, isPinned: true, pinnedAt: 500),
            makeRow(threadID: "idle-body", title: "Idle body", branch: "main", status: .idle, lastActivity: 300)
        ])

        let projection = snapshot.project(options: .init(lens: .newest))

        XCTAssertEqual(projection.pinnedRows.map(\.id.threadID), ["idle-pinned"])
        XCTAssertEqual(projection.rows.map(\.id.threadID), ["idle-body"])
        XCTAssertEqual(projection.summary.resultCount, 2)
        XCTAssertEqual(
            projection.pinnedSummary,
            DockPinnedSummary(visibleCount: 1, totalCount: 1, hiddenByScopeCount: 0)
        )
    }

    func testStatusFilterIdleOnlyShowsIdleRows() {
        let snapshot = makeSnapshot(rows: [
            makeRow(threadID: "running", title: "Running", branch: "main", status: .running, lastActivity: 300),
            makeRow(threadID: "idle", title: "Idle", branch: "main", status: .idle, lastActivity: 400)
        ])

        let projection = snapshot.project(options: .init(lens: .newest, filters: DockFilterState(statusKinds: [.idle])))

        XCTAssertEqual(projection.rows.map(\.id.threadID), ["idle"])
        XCTAssertEqual(projection.summary.text.contains("Status: Idle"), true)
    }

    func testStatusFilterExcludingIdleHidesIdleRowsAndPinnedIdleRows() {
        let statusKinds = Set(DockRowStatusKind.allCases).subtracting([.idle])
        let snapshot = makeSnapshot(rows: [
            makeRow(threadID: "idle-pinned", title: "Idle pinned", branch: "main", status: .idle, lastActivity: 500, isPinned: true, pinnedAt: 500),
            makeRow(threadID: "idle-body", title: "Idle body", branch: "main", status: .idle, lastActivity: 400),
            makeRow(threadID: "running", title: "Running", branch: "main", status: .running, lastActivity: 300)
        ])

        let projection = snapshot.project(options: .init(lens: .newest, filters: DockFilterState(statusKinds: statusKinds)))

        XCTAssertEqual(projection.pinnedRows, [])
        XCTAssertEqual(projection.rows.map(\.id.threadID), ["running"])
        XCTAssertEqual(
            projection.pinnedSummary,
            DockPinnedSummary(visibleCount: 0, totalCount: 1, hiddenByScopeCount: 1)
        )
    }

    func testStatusFilterExcludingIdleUsesNormalEmptyReason() {
        let statusKinds = Set(DockRowStatusKind.allCases).subtracting([.idle])
        let snapshot = makeSnapshot(rows: [
            makeRow(threadID: "idle", title: "Idle", branch: "main", status: .idle, lastActivity: 400)
        ])

        let projection = snapshot.project(options: .init(lens: .newest, filters: DockFilterState(statusKinds: statusKinds)))

        XCTAssertEqual(projection.emptyReason, .noFilterMatches)
        XCTAssertEqual(projection.emptyReason?.message, "No sessions match the active filters.")
    }

    func testDormantOnlyEmptyReasonUsesNormalFilterCopy() {
        let snapshot = makeSnapshot(rows: [
            makeRow(threadID: "running", title: "Running", branch: "main", status: .running, lastActivity: 300)
        ])

        let projection = snapshot.project(
            options: .init(
                lens: .newest,
                filters: DockFilterState(statusKinds: [.dormant])
            )
        )

        XCTAssertEqual(projection.emptyReason, .noFilterMatches)
        XCTAssertEqual(projection.emptyReason?.message, "No sessions match the active filters.")
    }

    func testPinnedRowsAreSplitFromNewestBodyAndCountInSummary() {
        let snapshot = makeSnapshot(rows: [
            makeRow(threadID: "pinned", title: "Pinned row", branch: "main", status: .running, lastActivity: 100, isPinned: true, pinnedAt: 300),
            makeRow(threadID: "normal", title: "Normal row", branch: "main", status: .running, lastActivity: 200)
        ])

        let projection = snapshot.project(options: .init(lens: .newest))

        XCTAssertEqual(projection.pinnedRows.map(\.id.threadID), ["pinned"])
        XCTAssertEqual(projection.rows.map(\.id.threadID), ["normal"])
        XCTAssertEqual(projection.summary.resultCount, 2)
        XCTAssertEqual(
            projection.pinnedSummary,
            DockPinnedSummary(visibleCount: 1, totalCount: 1, hiddenByScopeCount: 0)
        )
    }

    func testPinnedRowsStayAboveHostAndBranchLensesWithoutDuplicatingInGroups() {
        let amir = makeProjectionHost(host: "amir-m5.fairy-salmon.ts.net")
        let home = makeProjectionHost(host: "home.fairy-salmon.ts.net")
        let snapshot = makeSnapshot(
            rows: [
                makeRow(host: amir, threadID: "amir-pinned", title: "Amir pinned", branch: "main", status: .running, lastActivity: 300, isPinned: true, pinnedAt: 350),
                makeRow(host: amir, threadID: "amir-body", title: "Amir body", branch: "main", status: .running, lastActivity: 200),
                makeRow(host: home, threadID: "home-body", title: "Home body", branch: "feature", status: .running, lastActivity: 100)
            ],
            hosts: [amir, home]
        )

        let hostProjection = snapshot.project(options: .init(lens: .host))
        let branchProjection = snapshot.project(options: .init(lens: .branch))

        XCTAssertEqual(hostProjection.pinnedRows.map(\.id.threadID), ["amir-pinned"])
        XCTAssertEqual(hostProjection.groups.flatMap(\.rows).map(\.id.threadID), ["amir-body", "home-body"])
        XCTAssertEqual(branchProjection.pinnedRows.map(\.id.threadID), ["amir-pinned"])
        XCTAssertEqual(branchProjection.groups.flatMap(\.rows).map(\.id.threadID), ["amir-body", "home-body"])
    }

    func testSearchCanHidePinnedRowsAndReportsHiddenPinnedCount() {
        let snapshot = makeSnapshot(rows: [
            makeRow(threadID: "pinned", title: "Pinned alpha", branch: "main", status: .running, lastActivity: 300, isPinned: true, pinnedAt: 350),
            makeRow(threadID: "normal", title: "Normal beta", branch: "main", status: .running, lastActivity: 200)
        ])

        let projection = snapshot.project(options: .init(lens: .newest, searchText: "beta"))

        XCTAssertEqual(projection.pinnedRows, [])
        XCTAssertEqual(projection.rows.map(\.id.threadID), ["normal"])
        XCTAssertEqual(
            projection.pinnedSummary,
            DockPinnedSummary(visibleCount: 0, totalCount: 1, hiddenByScopeCount: 1)
        )
    }

    func testFiltersCanHidePinnedRowsAndReportsHiddenPinnedCount() {
        let amir = makeProjectionHost(host: "amir-m5.fairy-salmon.ts.net")
        let home = makeProjectionHost(host: "home.fairy-salmon.ts.net")
        let snapshot = makeSnapshot(
            rows: [
                makeRow(host: amir, threadID: "amir-pinned", title: "Amir pinned", branch: "main", status: .running, lastActivity: 300, isPinned: true, pinnedAt: 350),
                makeRow(host: home, threadID: "home-body", title: "Home body", branch: "main", status: .running, lastActivity: 200)
            ],
            hosts: [amir, home]
        )
        let filters = DockFilterState(selectedHostIDs: [home.id])

        let projection = snapshot.project(options: .init(lens: .host, filters: filters))

        XCTAssertEqual(projection.pinnedRows, [])
        XCTAssertEqual(projection.groups.flatMap(\.rows).map(\.id.threadID), ["home-body"])
        XCTAssertEqual(
            projection.pinnedSummary,
            DockPinnedSummary(visibleCount: 0, totalCount: 1, hiddenByScopeCount: 1)
        )
    }

    func testPinnedRowsSortByPinnedOrderThenLegacyPinnedAtThenStableID() {
        let snapshot = makeSnapshot(rows: [
            makeRow(threadID: "order-two", title: "Order two", branch: "main", status: .running, lastActivity: 400, isPinned: true, pinnedAt: 50, pinnedOrder: 2),
            makeRow(threadID: "legacy-old", title: "Legacy old", branch: "main", status: .running, lastActivity: 500, isPinned: true, pinnedAt: 100),
            makeRow(threadID: "order-zero", title: "Order zero", branch: "main", status: .running, lastActivity: 300, isPinned: true, pinnedAt: 300, pinnedOrder: 0),
            makeRow(threadID: "legacy-new", title: "Legacy new", branch: "main", status: .running, lastActivity: 100, isPinned: true, pinnedAt: 200)
        ])

        let projection = snapshot.project(options: .init(lens: .newest))

        XCTAssertEqual(
            projection.pinnedRows.map(\.id.threadID),
            ["order-zero", "order-two", "legacy-old", "legacy-new"]
        )
    }

    func testThreadCardTableDoesNotAddPinnedRowsWhenRelayCardIsAbsent() {
        let host = makeProjectionHost(host: "amir-m5.fairy-salmon.ts.net")
        let key = LocalThreadMetadataKey(
            hostID: host.id,
            backendSessionID: "cached-session",
            threadID: "cached-thread"
        )
        var table = ThreadCardTable()
        table.reset(hosts: [host])

        let snapshot = table.snapshot(
            hosts: [host],
            localMetadata: [
                key: LocalThreadMetadata(
                    rail: .green,
                    isPinned: true,
                    pinnedAt: Date(timeIntervalSince1970: 250)
                )
            ],
            now: { Date(timeIntervalSince1970: 300) }
        )

        XCTAssertEqual(snapshot.rows, [])
    }

    func testThreadCardTableProjectsLogicalHostRowsToConfiguredEndpointHost() {
        let host = makeProjectionHost(host: "amir-m5.fairy-salmon.ts.net")
        let card = DockThreadCardDTO(
            id: "Amir-M5::thread-a",
            logicalHostID: "Amir-M5",
            threadID: "thread-a",
            backendSessionID: "thread-a-session",
            hostDisplayName: "Amir-M5",
            hostEndpoint: host.endpoint.displayEndpoint,
            orderKey: "000000000000:thread-a",
            activityAt: "2026-05-30T00:00:00.000Z",
            activityAtMs: 1_780_099_200_000,
            displaySummary: "Summary",
            title: "Logical host row",
            status: .running,
            sourceKind: .human,
            lane: .human,
            archiveState: .active,
            freshness: .fresh,
            completeness: .complete,
            repository: "codex-client",
            workingDirectory: "/Users/aelaguiz/workspace/codex-client",
            branch: "main",
            summarySource: "test"
        )
        let update = ThreadCardStreamUpdateDTO(
            kind: .snapshot,
            schemaVersion: CodexDockConstants.Dock.streamSchemaVersion,
            view: .dock,
            complete: true,
            totalRows: 1,
            window: DockStreamWindowDTO(offset: 0, limit: 1, rowCount: 1),
            epoch: "epoch",
            seq: 1,
            hosts: [
                DockStreamHostDTO(
                    id: "Amir-M5",
                    logicalHostID: "Amir-M5",
                    displayName: "Amir-M5",
                    endpoint: host.endpoint.displayEndpoint
                )
            ],
            cards: [card]
        )
        var table = ThreadCardTable()
        table.reset(hosts: [host])
        XCTAssertEqual(table.applySnapshot(update, host: host), .applied)

        let snapshot = table.snapshot(
            hosts: [host],
            localMetadata: [:],
            now: { Date(timeIntervalSince1970: 1_780_099_300) }
        )
        let projection = snapshot.project(options: .init(lens: .host))

        XCTAssertEqual(snapshot.rows[0].id.hostID, "Amir-M5")
        XCTAssertEqual(snapshot.rows[0].sourceHostID, host.id)
        XCTAssertEqual(
            snapshot.hostIdentityResolver.resolve(rowHostID: "Amir-M5", sourceConfiguredHostID: host.id)?.host.id,
            host.id
        )
        XCTAssertEqual(projection.groups.map(\.title), ["Amir-M5"])
        XCTAssertEqual(projection.groups.first?.rows.map(\.id.threadID), ["thread-a"])
    }

    func testThreadCardRowProjectorMarksForkedCards() throws {
        let host = makeProjectionHost(host: "amir-m5.fairy-salmon.ts.net")
        let projector = ThreadCardRowProjector(
            hosts: [host],
            hostIdentityResolver: DockHostIdentityResolver(hosts: [host]),
            localMetadata: [:],
            now: { Date(timeIntervalSince1970: 1_780_000_100) }
        )
        let card = threadCardFixture(
            host: host,
            threadID: "forked-thread",
            title: "Forked thread",
            updatedAt: 1_780_000_000,
            relationship: .forked,
            forkedFromID: "parent-thread"
        )

        let row = try XCTUnwrap(projector.rows(from: [card], sourceHostID: host.id).first)

        XCTAssertEqual(row.relationship, .forked)
        XCTAssertTrue(row.automationValue.contains("relationship=forked"))
    }

    func testThreadCardTableDropsPinnedPlaceholderWithoutCachedHumanDisplay() {
        let host = makeProjectionHost(host: "amir-m5.fairy-salmon.ts.net")
        let key = LocalThreadMetadataKey(
            hostID: host.id,
            backendSessionID: "missing-session",
            threadID: "missing-thread"
        )
        var table = ThreadCardTable()
        table.reset(hosts: [host])

        let snapshot = table.snapshot(
            hosts: [host],
            localMetadata: [
                key: LocalThreadMetadata(
                    isPinned: true,
                    pinnedAt: Date(timeIntervalSince1970: 250)
                )
            ],
            now: { Date(timeIntervalSince1970: 300) }
        )

        XCTAssertEqual(snapshot.rows.map(\.id.threadID), [])
    }
}

private func makeSnapshot(
    rows: [DockRowViewModel],
    hosts: [DockHostConfiguration] = [makeProjectionHost()],
    hostStates: [DockHostStateViewModel]? = nil,
    isPartial: Bool = false
) -> DockSnapshot {
    let hostViewModels = hosts.map(DockHostViewModel.init)
    let observations = rows.compactMap { row -> DockHostIdentityObservation? in
        let sourceHost = row.sourceHostID.flatMap { sourceHostID in
            hosts.first { $0.id == sourceHostID }
        }
        let inferredHost = sourceHost ?? hosts.first { host in
            host.id == row.id.hostID
                || host.displayName == row.id.hostID
                || host.endpoint.displayEndpoint == row.id.hostID
        }
        guard let host = inferredHost else {
            return nil
        }
        return DockHostIdentityObservation(
            configuredHostID: host.id,
            logicalHostID: row.id.hostID,
            displayName: row.hostDisplayName,
            endpoint: row.hostEndpoint
        )
    }
    let resolver = DockHostIdentityResolver(hosts: hosts, observations: observations)
    return DockSnapshot(
        host: hostViewModels[0],
        hosts: hostViewModels,
        hostStates: hostStates ?? hosts.map { host in
            DockHostStateViewModel(host: DockHostViewModel(host: host), status: .loaded(rowCount: rows.filter { $0.id.hostID == host.id }.count))
        },
        hostIdentityResolver: resolver,
        rows: rows,
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
    orderKey: String? = nil,
    label: String? = nil,
    origin: SessionOrigin = .humanInteractive(subtype: .cli),
    isPinned: Bool = false,
    pinnedAt: TimeInterval? = nil,
    pinnedOrder: Int? = nil
) -> DockRowViewModel {
    let resolvedOrderKey = orderKey ?? String(
        format: "%019lld:%@",
        Int64.max - Int64(lastActivity * 1_000),
        threadID
    )
    return DockRowViewModel(
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
        orderKey: resolvedOrderKey,
        summary: "Summary for \(title)",
        rail: .blue,
        label: label,
        origin: origin,
        isPinned: isPinned,
        pinnedAt: pinnedAt.map(Date.init(timeIntervalSince1970:)),
        pinnedOrder: pinnedOrder
    )
}

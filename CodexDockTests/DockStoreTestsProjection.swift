import XCTest
@testable import CodexDock

final class DockStoreTestsProjection: XCTestCase {
    func testBranchProjectionOrdersSectionsAndRowsByNewestVisibleActivity() {
        let snapshot = makeSnapshot(sections: [
            makeSection(
                title: "main",
                rows: [
                    makeRow(threadID: "older-needs-me", title: "Older needs me", branch: "main", status: .needsMe, lastActivity: 100),
                    makeRow(threadID: "newer-running", title: "Newer running", branch: "main", status: .running, lastActivity: 300)
                ]
            ),
            makeSection(
                title: "feature",
                rows: [
                    makeRow(threadID: "middle-running", title: "Middle running", branch: "feature", status: .running, lastActivity: 200)
                ]
            )
        ])

        let projection = snapshot.project(options: .init(selectedTab: .all, sortMode: .branch))

        XCTAssertEqual(projection.sections.map(\.title), ["main", "feature"])
        XCTAssertEqual(projection.sections[0].rows.map(\.id.threadID), ["newer-running", "older-needs-me"])
    }

    func testBranchProjectionReordersAfterSearchHidesNewestRow() {
        let snapshot = makeSnapshot(sections: [
            makeSection(
                title: "main",
                rows: [
                    makeRow(threadID: "hidden-newest", title: "Hidden newest", branch: "main", status: .running, lastActivity: 500),
                    makeRow(threadID: "main-keep", title: "Keep main", branch: "main", status: .running, lastActivity: 100)
                ]
            ),
            makeSection(
                title: "feature",
                rows: [
                    makeRow(threadID: "feature-keep", title: "Keep feature", branch: "feature", status: .running, lastActivity: 300)
                ]
            )
        ])

        let unfiltered = snapshot.project(options: .init(selectedTab: .all, sortMode: .branch))
        let filtered = snapshot.project(options: .init(selectedTab: .all, searchText: "Keep", sortMode: .branch))

        XCTAssertEqual(unfiltered.sections.map(\.title), ["main", "feature"])
        XCTAssertEqual(filtered.sections.map(\.title), ["feature", "main"])
    }

    func testBranchProjectionReordersAfterIdleVisibilityChanges() {
        let snapshot = makeSnapshot(sections: [
            makeSection(
                title: "main",
                rows: [
                    makeRow(threadID: "idle-newest", title: "Idle newest", branch: "main", status: .idle, lastActivity: 500),
                    makeRow(threadID: "main-running", title: "Main running", branch: "main", status: .running, lastActivity: 100)
                ]
            ),
            makeSection(
                title: "feature",
                rows: [
                    makeRow(threadID: "feature-running", title: "Feature running", branch: "feature", status: .running, lastActivity: 300)
                ]
            )
        ])

        let idleHidden = snapshot.project(options: .init(selectedTab: .all, sortMode: .branch, showsIdle: false))
        let idleVisible = snapshot.project(options: .init(selectedTab: .all, sortMode: .branch, showsIdle: true))

        XCTAssertEqual(idleHidden.sections.map(\.title), ["feature", "main"])
        XCTAssertEqual(idleHidden.hiddenIdleMatchCount, 1)
        XCTAssertEqual(idleVisible.sections.map(\.title), ["main", "feature"])
        XCTAssertEqual(idleVisible.sections[0].rows.map(\.id.threadID), ["idle-newest", "main-running"])
    }

    func testBranchProjectionReordersFromRefreshedSnapshotDates() {
        let olderMainSnapshot = makeSnapshot(sections: [
            makeSection(title: "main", rows: [
                makeRow(threadID: "main", title: "Main", branch: "main", status: .running, lastActivity: 100)
            ]),
            makeSection(title: "feature", rows: [
                makeRow(threadID: "feature", title: "Feature", branch: "feature", status: .running, lastActivity: 300)
            ])
        ])
        let newerMainSnapshot = makeSnapshot(sections: [
            makeSection(title: "main", rows: [
                makeRow(threadID: "main", title: "Main", branch: "main", status: .running, lastActivity: 400)
            ]),
            makeSection(title: "feature", rows: [
                makeRow(threadID: "feature", title: "Feature", branch: "feature", status: .running, lastActivity: 300)
            ])
        ])

        XCTAssertEqual(
            olderMainSnapshot.project(options: .init(selectedTab: .all, sortMode: .branch)).sections.map(\.title),
            ["feature", "main"]
        )
        XCTAssertEqual(
            newerMainSnapshot.project(options: .init(selectedTab: .all, sortMode: .branch)).sections.map(\.title),
            ["main", "feature"]
        )
    }

    func testBranchProjectionReordersAfterSelectedTabChanges() {
        let snapshot = makeSnapshot(sections: [
            makeSection(title: "main", rows: [
                makeRow(threadID: "main-running", title: "Main running", branch: "main", status: .running, lastActivity: 100),
                makeRow(threadID: "main-limited", title: "Main limited", branch: "main", status: .limited, lastActivity: 500)
            ]),
            makeSection(title: "feature", rows: [
                makeRow(threadID: "feature-running", title: "Feature running", branch: "feature", status: .running, lastActivity: 300)
            ])
        ])

        let allProjection = snapshot.project(options: .init(selectedTab: .all, sortMode: .branch))
        let runningProjection = snapshot.project(options: .init(selectedTab: .running, sortMode: .branch))

        XCTAssertEqual(allProjection.sections.map(\.title), ["main", "feature"])
        XCTAssertEqual(runningProjection.sections.map(\.title), ["feature", "main"])
    }

    func testNewestProjectionFlattensRowsAndSortsByActivity() {
        let snapshot = makeSnapshot(sections: [
            makeSection(title: "main", rows: [
                makeRow(threadID: "old", title: "Old", branch: "main", status: .needsMe, lastActivity: 100)
            ]),
            makeSection(title: "feature", rows: [
                makeRow(threadID: "new", title: "New", branch: "feature", status: .running, lastActivity: 300)
            ])
        ])

        let projection = snapshot.project(options: .init(selectedTab: .all, sortMode: .newest))

        XCTAssertEqual(projection.sections.map(\.title), ["Newest"])
        XCTAssertEqual(projection.sections.flatMap(\.rows).map(\.id.threadID), ["new", "old"])
    }

    func testProjectionSearchMatchesLabelHostAndThreadID() {
        let home = makeHost(id: "Home", displayName: "Home Studio")
        let snapshot = makeSnapshot(
            sections: [
                makeSection(title: "main", rows: [
                    makeRow(
                        hostID: home.id,
                        threadID: "thread-home-123",
                        title: "Runner",
                        branch: "main",
                        status: .running,
                        lastActivity: 300,
                        label: "Watch"
                    )
                ])
            ],
            hosts: [home]
        )

        XCTAssertEqual(
            snapshot.project(options: .init(selectedTab: .all, searchText: home.displayName)).sections.flatMap(\.rows).map(\.id.threadID),
            ["thread-home-123"]
        )
        XCTAssertEqual(
            snapshot.project(options: .init(selectedTab: .all, searchText: "Watch")).sections.flatMap(\.rows).map(\.id.threadID),
            ["thread-home-123"]
        )
        XCTAssertEqual(
            snapshot.project(options: .init(selectedTab: .all, searchText: "home-123")).sections.flatMap(\.rows).map(\.id.threadID),
            ["thread-home-123"]
        )
        XCTAssertEqual(
            snapshot.project(options: .init(selectedTab: .all, searchText: "Home")).sections.flatMap(\.rows).map(\.id.threadID),
            ["thread-home-123"]
        )
        XCTAssertEqual(
            snapshot.project(options: .init(selectedTab: .all, searchText: "main")).sections.flatMap(\.rows).map(\.id.threadID),
            ["thread-home-123"]
        )
        XCTAssertEqual(
            snapshot.project(options: .init(selectedTab: .all, searchText: "Running")).sections.flatMap(\.rows).map(\.id.threadID),
            ["thread-home-123"]
        )
        XCTAssertEqual(
            snapshot.project(options: .init(selectedTab: .all, searchText: "Summary for Runner")).sections.flatMap(\.rows).map(\.id.threadID),
            ["thread-home-123"]
        )
    }

    func testProjectedCountsIgnoreSortModeAndRowsHiddenByIdle() {
        let snapshot = makeSnapshot(sections: [
            makeSection(title: "main", rows: [
                makeRow(threadID: "running", title: "Running", branch: "main", status: .running, lastActivity: 300),
                makeRow(threadID: "idle", title: "Idle", branch: "main", status: .idle, lastActivity: 200),
                makeRow(
                    threadID: "agent-idle",
                    title: "Agent idle",
                    branch: "main",
                    status: .idle,
                    lastActivity: 100,
                    origin: .agentOrAutomation(subtype: .exec)
                )
            ])
        ])

        let branchCounts = tabCounts(snapshot.project(options: .init(selectedTab: .all, sortMode: .branch)))
        let newestCounts = tabCounts(snapshot.project(options: .init(selectedTab: .all, sortMode: .newest)))
        let idleVisibleCounts = tabCounts(
            snapshot.project(options: .init(selectedTab: .all, sortMode: .branch, showsIdle: true))
        )

        XCTAssertEqual(branchCounts, [.all: 1, .needsMe: 0, .running: 1, .limited: 0, .agents: 0])
        XCTAssertEqual(newestCounts, branchCounts)
        XCTAssertEqual(idleVisibleCounts, [.all: 2, .needsMe: 0, .running: 2, .limited: 0, .agents: 1])
    }
}

private func tabCounts(_ projection: DockSessionProjection) -> [DockTabID: Int] {
    Dictionary(uniqueKeysWithValues: projection.tabs.map { ($0.id, $0.count) })
}

private func makeSnapshot(
    sections: [DockSectionViewModel],
    hosts: [DockHostConfiguration] = [makeHost()]
) -> DockSnapshot {
    let allRows = sections.flatMap(\.rows)
    return DockSnapshot(
        host: DockHostViewModel(host: hosts[0]),
        hosts: hosts.map(DockHostViewModel.init),
        hostStates: hosts.map { host in
            DockHostStateViewModel(host: DockHostViewModel(host: host), status: .loaded(rowCount: allRows.count))
        },
        sections: sections,
        tabs: DockTabID.allCases.map { tab in
            DockTabViewModel(id: tab, count: allRows.filter(tab.includes).count)
        },
        scopeLoadFailures: [],
        scopeConflicts: [],
        mappingFailures: []
    )
}

private func makeSection(title: String, rows: [DockRowViewModel]) -> DockSectionViewModel {
    DockSectionViewModel(id: title, title: title, rows: rows)
}

private func makeHost(
    id: String = "Amir-M5",
    displayName: String = "Amir-M5"
) -> DockHostConfiguration {
    let hostName = id == "Amir-M5" ? "192.168.50.117" : id
    return try! DockHostConfiguration(host: hostName, port: 4510)
}

private func makeRow(
    hostID: String = "Amir-M5",
    threadID: String,
    title: String,
    branch: String,
    status: DockRowStatusKind,
    lastActivity: TimeInterval,
    label: String? = nil,
    origin: SessionOrigin = .humanInteractive(subtype: .cli)
) -> DockRowViewModel {
    DockRowViewModel(
        id: HostScopedThreadID(hostID: hostID, threadID: threadID),
        backendSessionID: "\(threadID)-session",
        title: title,
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

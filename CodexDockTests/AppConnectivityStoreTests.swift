import XCTest
@testable import CodexDock

final class AppConnectivityStoreTests: XCTestCase {
    @MainActor
    func testNilBearerHostStartsConfiguredNotAuthFailed() throws {
        let host = makeConnectivityHost(bearerToken: nil)
        let store = AppConnectivityStore(hosts: [host])

        XCTAssertEqual(store.hosts.count, 1)
        XCTAssertEqual(store.hosts[0].id, host.id)
        XCTAssertEqual(store.overallStatus, .checking("Waiting for first check"))
    }

    @MainActor
    func testDockSnapshotOnlineRollsUpToOnline() throws {
        let host = makeConnectivityHost()
        let store = AppConnectivityStore(hosts: [host])
        let hostViewModel = DockHostViewModel(host: host)

        store.reportDockState(
            .loaded(
                DockSnapshot(
                    host: hostViewModel,
                    hosts: [hostViewModel],
                    hostStates: [
                        DockHostStateViewModel(host: hostViewModel, status: .loaded(rowCount: 2)),
                    ],
                    rows: [],
                    scopeLoadFailures: [],
                    scopeConflicts: [],
                    mappingFailures: []
                )
            )
        )

        XCTAssertEqual(store.overallStatus, .online("2 sessions"))
        XCTAssertEqual(store.hosts[0].phase, .online("2 sessions"))
    }

    @MainActor
    func testAllHostLoadingRollsUpToCheckingCount() throws {
        let amir = try DockHostConfiguration(host: "amir-m5.fairy-salmon.ts.net", port: 4510)
        let home = try DockHostConfiguration(host: "home.fairy-salmon.ts.net", port: 4510)
        let store = AppConnectivityStore(hosts: [amir, home])

        store.reportDockState(.loading([DockHostViewModel(host: amir), DockHostViewModel(host: home)]))

        XCTAssertEqual(store.overallStatus, .checking("Checking 2 hosts"))
        XCTAssertEqual(store.hosts.map(\.phase), [.checking, .checking])
    }

    @MainActor
    func testLoadedPlusCheckingHostsRollUpToPartialCount() throws {
        let amir = try DockHostConfiguration(host: "amir-m5.fairy-salmon.ts.net", port: 4510)
        let home = try DockHostConfiguration(host: "home.fairy-salmon.ts.net", port: 4510)
        let store = AppConnectivityStore(hosts: [amir, home])
        let amirViewModel = DockHostViewModel(host: amir)
        let homeViewModel = DockHostViewModel(host: home)

        store.reportDockState(
            .loaded(
                DockSnapshot(
                    host: amirViewModel,
                    hosts: [amirViewModel, homeViewModel],
                    hostStates: [
                        DockHostStateViewModel(host: amirViewModel, status: .loaded(rowCount: 2)),
                        DockHostStateViewModel(host: homeViewModel, status: .checking),
                    ],
                    rows: [],
                    scopeLoadFailures: [],
                    scopeConflicts: [],
                    mappingFailures: [],
                    isPartial: true
                )
            )
        )

        XCTAssertEqual(store.overallStatus, .partial("Online 1/2, checking 1"))
        XCTAssertEqual(store.hosts.map(\.phase), [.online("2 sessions"), .checking])
    }

    @MainActor
    func testDockScopedFailureRollsUpToPartial() throws {
        let host = makeConnectivityHost()
        let store = AppConnectivityStore(hosts: [host])
        let hostViewModel = DockHostViewModel(host: host)

        store.reportDockState(
            .loaded(
                DockSnapshot(
                    host: hostViewModel,
                    hosts: [hostViewModel],
                    hostStates: [
                        DockHostStateViewModel(
                            host: hostViewModel,
                            status: .partial(rowCount: 1, message: "Agents: offline")
                        ),
                    ],
                    rows: [],
                    scopeLoadFailures: [
                        DockScopeLoadFailureViewModel(
                            host: hostViewModel,
                            scope: .agents,
                            message: "offline"
                        ),
                    ],
                    scopeConflicts: [],
                    mappingFailures: []
                )
            )
        )

        XCTAssertEqual(store.overallStatus, .partial("\(host.displayName): Agents: offline"))
        XCTAssertEqual(store.hosts[0].phase, .partial("Agents: offline"))
    }

    @MainActor
    func testAllOfflineRollsUpToOffline() throws {
        let host = makeConnectivityHost()
        let store = AppConnectivityStore(hosts: [host])

        store.reportDockState(.offline(DockHostViewModel(host: host), "transport closed"))

        XCTAssertEqual(store.overallStatus, .offline("\(host.displayName): transport closed"))
        XCTAssertEqual(store.hosts[0].phase, .offline("transport closed"))
    }

    @MainActor
    func testManualHostTestUpdatesGlobalStatus() throws {
        let checkedAt = Date(timeIntervalSince1970: 4_000)
        let host = makeConnectivityHost()
        let store = AppConnectivityStore(hosts: [host])

        store.reportHostTest(
            host: host,
            status: .online(rowCount: 3, checkedAt: checkedAt)
        )

        XCTAssertEqual(store.overallStatus, .online("3 sessions"))
        XCTAssertEqual(store.hosts[0].lastCheckedAt, checkedAt)
        XCTAssertEqual(store.hosts[0].lastSuccessAt, checkedAt)
    }

    @MainActor
    func testThreadDetailReconnectAndStaleUpdateGlobalStatus() throws {
        let host = makeConnectivityHost()
        let store = AppConnectivityStore(hosts: [host])

        store.reportThreadDetail(host: host, liveState: .reconnecting("transport closed"))

        XCTAssertEqual(store.overallStatus, .reconnecting("\(host.displayName): transport closed"))
        XCTAssertEqual(store.hosts[0].phase, .reconnecting("transport closed"))

        store.reportThreadDetail(host: host, liveState: .stale("reconnect exhausted"))

        XCTAssertEqual(store.overallStatus, .stale("\(host.displayName): reconnect exhausted"))
        XCTAssertEqual(store.hosts[0].phase, .stale("reconnect exhausted"))
    }

    @MainActor
    func testThreadDetailStaleIsNotOverwrittenByDockOnline() throws {
        let host = makeConnectivityHost()
        let store = AppConnectivityStore(hosts: [host])
        let hostViewModel = DockHostViewModel(host: host)

        store.reportThreadDetail(host: host, liveState: .stale("reconnect exhausted"))
        store.reportDockState(
            .loaded(
                DockSnapshot(
                    host: hostViewModel,
                    hosts: [hostViewModel],
                    hostStates: [
                        DockHostStateViewModel(host: hostViewModel, status: .loaded(rowCount: 2)),
                    ],
                    rows: [],
                    scopeLoadFailures: [],
                    scopeConflicts: [],
                    mappingFailures: []
                )
            )
        )

        XCTAssertEqual(store.overallStatus, .stale("\(host.displayName): reconnect exhausted"))
        XCTAssertEqual(store.hosts[0].phase, .stale("reconnect exhausted"))
    }

    @MainActor
    func testConfigurationErrorWins() {
        let error = DockHostConfigurationError.missingEndpoint
        let store = AppConnectivityStore(configurationError: error)

        XCTAssertEqual(store.hosts, [])
        XCTAssertEqual(store.overallStatus, .configurationError(error.localizedDescription))
    }

    @MainActor
    func testLifecycleBackgroundAndResumeUpdateGlobalStatusWithoutLosingSuccessTimestamp() {
        let checkedAt = Date(timeIntervalSince1970: 4_000)
        let host = makeConnectivityHost()
        let store = AppConnectivityStore(hosts: [host])
        store.reportHostTest(
            host: host,
            status: .online(rowCount: 3, checkedAt: checkedAt)
        )

        store.reportLifecycle(AppLifecycleSnapshot(phase: .backgrounded, resumeGeneration: 0))

        XCTAssertEqual(store.overallStatus, .backgrounded("\(host.displayName): Backgrounded"))
        XCTAssertEqual(store.hosts[0].phase, .backgrounded("Backgrounded"))
        XCTAssertEqual(store.hosts[0].lastSuccessAt, checkedAt)

        store.reportLifecycle(AppLifecycleSnapshot(phase: .foregroundResuming, resumeGeneration: 1))

        XCTAssertEqual(store.overallStatus, .resuming("\(host.displayName): Resuming"))
        XCTAssertEqual(store.hosts[0].phase, .resuming("Resuming"))
        XCTAssertEqual(store.hosts[0].lastSuccessAt, checkedAt)
    }

    @MainActor
    func testLifecycleResumingMasksOldStoreFactsUntilActiveClearsIt() {
        let host = makeConnectivityHost()
        let store = AppConnectivityStore(hosts: [host])
        let hostViewModel = DockHostViewModel(host: host)
        let snapshot = DockSnapshot(
            host: hostViewModel,
            hosts: [hostViewModel],
            hostStates: [
                DockHostStateViewModel(host: hostViewModel, status: .loaded(rowCount: 2)),
            ],
            rows: [],
            scopeLoadFailures: [],
            scopeConflicts: [],
            mappingFailures: []
        )
        store.reportDockState(.loaded(snapshot))
        store.reportLifecycle(AppLifecycleSnapshot(phase: .foregroundResuming, resumeGeneration: 1))

        store.reportDockState(.loaded(snapshot))
        store.reportHostTest(
            host: host,
            status: .online(rowCount: 2, checkedAt: Date(timeIntervalSince1970: 5_000))
        )

        XCTAssertEqual(store.overallStatus, .resuming("\(host.displayName): Resuming"))
        XCTAssertEqual(store.hosts[0].phase, .resuming("Resuming"))

        store.reportLifecycle(AppLifecycleSnapshot(phase: .active, resumeGeneration: 1))

        XCTAssertEqual(store.overallStatus, .online("2 sessions"))
        XCTAssertEqual(store.hosts[0].phase, .online("2 sessions"))
    }

    @MainActor
    func testBootstrapNonReadyStatesUseGlobalConnectivityStatus() throws {
        let host = makeConnectivityHost()
        let store = AppConnectivityStore()

        store.reportBootstrapState(.starting)
        XCTAssertEqual(store.overallStatus, .checking("Finding Codex Dock relay"))

        store.reportBootstrapState(.discovering(relays: [], message: "Backgrounded"))
        XCTAssertEqual(store.overallStatus, .backgrounded("Backgrounded"))

        store.reportBootstrapState(.failed("Relay unavailable"))
        XCTAssertEqual(store.overallStatus, .error("Relay unavailable"))

        store.reportBootstrapState(.ready(try HostRegistry(hosts: [host])))
        XCTAssertEqual(store.hosts.count, 1)
        XCTAssertEqual(store.hosts[0].id, host.id)
        XCTAssertEqual(store.overallStatus, .checking("Waiting for first check"))
    }
}

private func makeConnectivityHost(bearerToken: String? = nil) -> DockHostConfiguration {
    try! DockHostConfiguration(host: "192.168.50.117", port: 4510)
}

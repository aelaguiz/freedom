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
                    rows: []
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
                    isPartial: true
                )
            )
        )

        XCTAssertEqual(store.overallStatus, .partial("Online 1/2, checking 1"))
        XCTAssertEqual(store.hosts.map(\.phase), [.online("2 sessions"), .checking])
    }

    @MainActor
    func testDockWindowedLoadedHostStateRollsUpToOnline() throws {
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
                            status: .loaded(
                                rowCount: 250,
                                window: DockHostWindow(visibleRows: 250, totalRows: 964)
                            )
                        ),
                    ],
                    rows: []
                )
            )
        )

        XCTAssertEqual(store.overallStatus, .online("250 sessions"))
        XCTAssertEqual(store.hosts[0].phase, .online("250 sessions"))
    }

    @MainActor
    func testArchiveWindowedLoadedHostStateRollsUpToOnline() throws {
        let host = makeConnectivityHost()
        let store = AppConnectivityStore(hosts: [host])
        let hostViewModel = DockHostViewModel(host: host)

        store.reportArchiveState(
            .loaded(
                ArchiveSnapshot(
                    hosts: [hostViewModel],
                    hostStates: [
                        DockHostStateViewModel(
                            host: hostViewModel,
                            status: .loaded(
                                rowCount: 125,
                                window: DockHostWindow(visibleRows: 125, totalRows: 500)
                            )
                        ),
                    ],
                    hostIdentityResolver: .empty,
                    sections: []
                )
            )
        )

        XCTAssertEqual(store.overallStatus, .online("125 sessions"))
        XCTAssertEqual(store.hosts[0].phase, .online("125 sessions"))
    }

    @MainActor
    func testDockDegradedHostStateRollsUpToPartial() throws {
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
                            status: .degraded(rowCount: 1, message: "Agents: offline")
                        ),
                    ],
                    rows: []
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
                    rows: []
                )
            )
        )

        XCTAssertEqual(store.overallStatus, .stale("\(host.displayName): reconnect exhausted"))
        XCTAssertEqual(store.hosts[0].phase, .stale("reconnect exhausted"))
    }

    @MainActor
    func testAppCriticalRouteFailureIsHostEvidenceEvenWhenProcessLooksOnline() throws {
        let host = makeConnectivityHost()
        let store = AppConnectivityStore(hosts: [host])
        let checkedAt = Date(timeIntervalSince1970: 4_000)

        store.reportHostTest(host: host, status: .online(rowCount: 2, checkedAt: checkedAt))
        store.reportRouteDiagnostic(
            host: host,
            diagnostic: RouteDiagnosticSnapshot(
                configuredHostID: host.id,
                relayHostID: "home",
                route: AppServerMethods.dockSubscribe,
                operationID: "op-dock-subscribe",
                routeStatus: .failed,
                statusReasons: [
                    RouteStatusReason(
                        code: "failed:last-attempt",
                        message: "dock provider offline",
                        actual: ObservabilityFailureCategory.history.rawValue,
                        evidenceIDs: ["op-dock-subscribe"]
                    ),
                ],
                lastAttemptAt: Date(timeIntervalSince1970: 4_100),
                lastSuccessAt: nil,
                lastFailureAt: Date(timeIntervalSince1970: 4_100),
                appCritical: true
            )
        )

        XCTAssertEqual(store.hosts[0].phase, .partial("\(AppServerMethods.dockSubscribe) failed"))
        XCTAssertEqual(store.hosts[0].lastSuccessAt, checkedAt)
        XCTAssertEqual(store.hosts[0].routeDiagnostics.map(\.route), [AppServerMethods.dockSubscribe])
        XCTAssertEqual(store.overallStatus, .partial("\(host.displayName): \(AppServerMethods.dockSubscribe) failed"))
    }

    @MainActor
    func testDiagnosticsFetchFailureDoesNotReplaceOriginalRouteFailure() throws {
        let host = makeConnectivityHost()
        let store = AppConnectivityStore(hosts: [host])

        store.reportRouteDiagnostic(
            host: host,
            diagnostic: RouteDiagnosticSnapshot(
                configuredHostID: host.id,
                route: AppServerMethods.dockSubscribe,
                operationID: "op-dock-subscribe",
                routeStatus: .failed,
                statusReasons: [
                    RouteStatusReason(
                        code: "failed:last-attempt",
                        message: "dock provider offline",
                        actual: ObservabilityFailureCategory.history.rawValue,
                        evidenceIDs: ["op-dock-subscribe"]
                    ),
                ],
                appCritical: true
            )
        )
        store.reportRouteDiagnostic(
            host: host,
            diagnostic: RouteDiagnosticSnapshot(
                configuredHostID: host.id,
                route: "routesz",
                operationID: nil,
                routeStatus: .failed,
                statusReasons: [
                    RouteStatusReason(
                        code: "failed:diagnostics-fetch",
                        message: "connection refused",
                        actual: ObservabilityFailureCategory.downstream.rawValue
                    ),
                ],
                appCritical: false,
                appImpact: "diagnostic-fetch"
            )
        )

        XCTAssertEqual(store.hosts[0].phase, .partial("\(AppServerMethods.dockSubscribe) failed"))
        XCTAssertEqual(store.hosts[0].routeDiagnostics.map(\.route), [AppServerMethods.dockSubscribe, "routesz"])
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
            rows: []
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

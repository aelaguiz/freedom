@testable import CodexDock
import XCTest

final class SystemHealthProjectorTests: XCTestCase {
    func testOnlineDockEvidenceMapsDockFeedHealthyAndPassiveCategoriesNotChecked() {
        let host = HostConnectivitySnapshot(
            id: "amir",
            displayName: "Amir-M5",
            endpoint: "amir-m5.local:4510",
            phase: .online("Dock feed loaded"),
            routeDiagnostics: [
                RouteDiagnosticSnapshot(
                    configuredHostID: "amir",
                    route: AppServerMethods.dockSubscribe,
                    routeStatus: .healthy,
                    appCritical: true
                )
            ]
        )

        let snapshot = SystemHealthProjector().snapshot(
            hosts: [host],
            overallStatus: .online("Online 1/1")
        )

        XCTAssertEqual(snapshot.status(for: .dockFeed)?.label, "Healthy")
        XCTAssertEqual(snapshot.status(for: .archive)?.label, "Not checked")
    }

    func testAppCriticalRouteFailureMapsToFailedWithNextAction() {
        let host = HostConnectivitySnapshot(
            id: "amir",
            displayName: "Amir-M5",
            endpoint: "amir-m5.local:4510",
            phase: .partial("Archive route failed"),
            routeDiagnostics: [
                RouteDiagnosticSnapshot(
                    configuredHostID: "amir",
                    route: AppServerMethods.threadArchive,
                    routeStatus: .failed,
                    statusReasons: [
                        RouteStatusReason(code: "timeout", message: "Archive route timed out")
                    ],
                    appCritical: true
                )
            ]
        )

        let snapshot = SystemHealthProjector().snapshot(
            hosts: [host],
            overallStatus: .partial("Archive route failed")
        )

        let status = snapshot.status(for: .archive)
        XCTAssertEqual(status?.label, "Failed")
        XCTAssertTrue(status?.detail.contains("Run check") ?? false)
        XCTAssertFalse(status?.detail.contains(AppServerMethods.threadArchive) ?? true)
    }

    func testPartialRouteEvidenceMapsToDegradedWithoutRawRouteName() {
        let host = HostConnectivitySnapshot(
            id: "amir",
            displayName: "Amir-M5",
            endpoint: "amir-m5.local:4510",
            phase: .partial("Thread detail is stale"),
            routeDiagnostics: [
                RouteDiagnosticSnapshot(
                    configuredHostID: "amir",
                    route: AppServerMethods.threadDetailUpdate,
                    routeStatus: .partial,
                    statusReasons: [
                        RouteStatusReason(code: "stale", message: "Thread detail is stale")
                    ],
                    appCritical: true
                )
            ]
        )

        let snapshot = SystemHealthProjector().snapshot(
            hosts: [host],
            overallStatus: .partial("Thread detail is stale")
        )

        let status = snapshot.status(for: .threadDetail)
        XCTAssertEqual(status?.label, "Degraded")
        XCTAssertTrue(status?.detail.contains("Thread detail is stale") ?? false)
        XCTAssertTrue(status?.detail.contains("Run check") ?? false)
        XCTAssertFalse(status?.detail.contains(AppServerMethods.threadDetailUpdate) ?? true)
    }

    func testGlobalPartialWithoutRouteEvidenceDoesNotDegradeCategories() {
        let host = HostConnectivitySnapshot(
            id: "home",
            displayName: "Home",
            endpoint: "home.local:4510",
            phase: .online("250 sessions")
        )

        let snapshot = SystemHealthProjector().snapshot(
            hosts: [host],
            overallStatus: .partial("Home: Showing 250 of 964")
        )

        XCTAssertEqual(snapshot.status(for: .dockFeed)?.label, "Not checked")
        XCTAssertEqual(snapshot.status(for: .threadDetail)?.label, "Not checked")
        XCTAssertEqual(snapshot.status(for: .archive)?.label, "Not checked")
        XCTAssertEqual(snapshot.status(for: .voice)?.label, "Not checked")
        XCTAssertEqual(snapshot.status(for: .diagnostics)?.label, "Not checked")
    }

    func testNoHostsMapsEveryCategoryToNotChecked() {
        let snapshot = SystemHealthProjector().snapshot(
            hosts: [],
            overallStatus: .unconfigured("No relay host configured.")
        )

        XCTAssertEqual(snapshot.categories.count, SystemHealthCategory.allCases.count)
        XCTAssertTrue(snapshot.categories.allSatisfy { $0.status.label == "Not checked" })
    }
}

private extension SystemHealthSnapshot {
    func status(for category: SystemHealthCategory) -> SystemHealthCategoryStatus? {
        categories.first { $0.category == category }?.status
    }
}

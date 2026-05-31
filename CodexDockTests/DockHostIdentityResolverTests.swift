import XCTest
@testable import CodexDock

final class DockHostIdentityResolverTests: XCTestCase {
    func testHomeDisplayNameCaseResolvesToLowercaseLogicalHostID() throws {
        let host = try DockHostConfiguration(host: "home.fairy-salmon.ts.net", port: 4510)
        let resolver = DockHostIdentityResolver(
            hosts: [host],
            observations: [
                DockHostIdentityObservation(
                    configuredHostID: host.id,
                    streamHostID: "home",
                    logicalHostID: "home",
                    displayName: "Home",
                    endpoint: host.endpoint.displayEndpoint
                )
            ]
        )

        let resolved = resolver.resolve(rowHostID: "Home")

        XCTAssertEqual(resolved?.logicalHostID, "home")
        XCTAssertEqual(resolved?.host.id, host.id)
        XCTAssertTrue(resolver.contains(rowHostID: "home", in: host.id))
        XCTAssertTrue(resolver.contains(rowHostID: "Home", in: host.id))
    }

    func testSameLogicalHostMultiEndpointPrefersSourceThenLoadedThenRegistryOrder() throws {
        let local = try DockHostConfiguration(host: "amir-m5.local", port: 4510)
        let lan = try DockHostConfiguration(host: "192.168.50.74", port: 4510)
        let observations = [
            DockHostIdentityObservation(
                configuredHostID: local.id,
                streamHostID: "Amir-M5",
                logicalHostID: "Amir-M5",
                displayName: "Amir-M5",
                endpoint: local.endpoint.displayEndpoint
            ),
            DockHostIdentityObservation(
                configuredHostID: lan.id,
                streamHostID: "Amir-M5",
                logicalHostID: "Amir-M5",
                displayName: "Amir-M5",
                endpoint: lan.endpoint.displayEndpoint
            )
        ]
        let resolver = DockHostIdentityResolver(
            hosts: [local, lan],
            observations: observations,
            hostStatuses: [
                local.id: .checking,
                lan.id: .loaded(rowCount: 1)
            ]
        )

        XCTAssertEqual(
            resolver.resolve(rowHostID: "Amir-M5", sourceConfiguredHostID: local.id)?.host.id,
            local.id
        )
        XCTAssertEqual(
            resolver.resolve(rowHostID: "Amir-M5", preferredConfiguredHostID: local.id)?.host.id,
            local.id
        )
        XCTAssertEqual(resolver.resolve(rowHostID: "Amir-M5")?.host.id, lan.id)

        let registryOrderResolver = DockHostIdentityResolver(
            hosts: [local, lan],
            observations: observations
        )
        XCTAssertEqual(registryOrderResolver.resolve(rowHostID: "Amir-M5")?.host.id, local.id)
    }

    func testAmbiguousDisplayAliasFailsClosedWithoutSourceEndpoint() throws {
        let first = try DockHostConfiguration(host: "first.local", port: 4510)
        let second = try DockHostConfiguration(host: "second.local", port: 4510)
        let resolver = DockHostIdentityResolver(
            hosts: [first, second],
            observations: [
                DockHostIdentityObservation(
                    configuredHostID: first.id,
                    streamHostID: "first-logical",
                    logicalHostID: "first-logical",
                    displayName: "Shared",
                    endpoint: first.endpoint.displayEndpoint
                ),
                DockHostIdentityObservation(
                    configuredHostID: second.id,
                    streamHostID: "second-logical",
                    logicalHostID: "second-logical",
                    displayName: "Shared",
                    endpoint: second.endpoint.displayEndpoint
                )
            ]
        )

        XCTAssertNil(resolver.resolve(rowHostID: "Shared"))
        XCTAssertFalse(resolver.contains(rowHostID: "Shared", in: first.id))
        XCTAssertFalse(resolver.contains(rowHostID: "Shared", in: second.id))
        XCTAssertEqual(
            resolver.resolve(rowHostID: "Shared", sourceConfiguredHostID: first.id)?.host.id,
            first.id
        )
    }
}

import XCTest
@testable import CodexDock

final class DockConfigurationTests: XCTestCase {
    func testHostConfigurationReadsPhoneReachableEndpointAndTokenFile() throws {
        let tokenFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try "test-token\n".write(to: tokenFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tokenFile) }

        let host = try DockHostConfiguration.fromEnvironment([
            "CODEX_DOCK_PHONE_REACHABLE_APP_SERVER_WS": "ws://192.168.50.117:4500",
            "CODEX_DOCK_APP_SERVER_BEARER_TOKEN_FILE": tokenFile.path,
            "CODEX_DOCK_REAL_HOST_ID": "Amir-M5",
            "CODEX_DOCK_REAL_HOST_NAME": "Amir-M5"
        ])

        XCTAssertEqual(host.id, "Amir-M5")
        XCTAssertEqual(host.displayName, "Amir-M5")
        XCTAssertEqual(host.webSocketURL.absoluteString, "ws://192.168.50.117:4500")
        XCTAssertEqual(host.bearerToken, "test-token")
    }

    func testHostConfigurationAllowsNoClientBearerTokenForRelay() throws {
        let host = try DockHostConfiguration.fromEnvironment([
            "CODEX_DOCK_PHONE_REACHABLE_APP_SERVER_WS": "ws://192.168.50.117:4510",
            "CODEX_DOCK_REAL_HOST_ID": "Amir-M5",
            "CODEX_DOCK_REAL_HOST_NAME": "Amir-M5"
        ])

        XCTAssertEqual(host.id, "Amir-M5")
        XCTAssertEqual(host.webSocketURL.absoluteString, "ws://192.168.50.117:4510")
        XCTAssertNil(host.bearerToken)
    }

    func testHostConfigurationRejectsMissingEndpoint() {
        XCTAssertThrowsError(
            try DockHostConfiguration.fromEnvironment([
                "CODEX_DOCK_APP_SERVER_BEARER_TOKEN": "test-token"
            ])
        ) { error in
            XCTAssertEqual(error as? DockHostConfigurationError, .missingEndpoint)
        }
    }

    func testHostConfigurationRejectsCredentialBearingEndpoint() {
        XCTAssertThrowsError(
            try DockHostConfiguration.fromEnvironment([
                "CODEX_DOCK_PHONE_REACHABLE_APP_SERVER_WS": "ws://token@192.168.50.117:4510"
            ])
        ) { error in
            XCTAssertEqual(
                error as? DockHostConfigurationError,
                .invalidEndpoint("ws://token@192.168.50.117:4510")
            )
        }
    }

    func testHostRegistryReadsScopedMultiHostEnvironment() throws {
        let registry = try HostRegistry.fromEnvironment([
            "CODEX_DOCK_HOSTS": "Amir-M5, Home",
            "CODEX_DOCK_HOST_AMIR_M5_WS": "ws://192.168.50.117:4510",
            "CODEX_DOCK_HOST_AMIR_M5_BEARER_TOKEN": "amir-token",
            "CODEX_DOCK_HOST_AMIR_M5_NAME": "Amir-M5",
            "CODEX_DOCK_HOST_HOME_WS": "ws://100.66.11.7:4510",
            "CODEX_DOCK_HOST_HOME_TOKEN": "home-token",
            "CODEX_DOCK_HOST_HOME_NAME": "Home"
        ])

        XCTAssertEqual(registry.hosts.map(\.id), ["Amir-M5", "Home"])
        XCTAssertEqual(registry.hosts.map(\.displayName), ["Amir-M5", "Home"])
        XCTAssertEqual(registry.hosts.map(\.webSocketURL.absoluteString), [
            "ws://192.168.50.117:4510",
            "ws://100.66.11.7:4510"
        ])
        XCTAssertEqual(registry.hosts.map(\.bearerToken), ["amir-token", "home-token"] as [String?])
    }

    @MainActor
    func testRelayBootstrapStartsDiscoveryWithoutLaunchEnvironmentAndUsesNoSecretHost() async throws {
        let discovery = FakeRelayDiscovery()
        let configurationStore = BootstrapLocalDockConfigurationStore()
        let store = RelayBootstrapStore(
            environment: [:],
            configurationStore: configurationStore,
            discovery: discovery
        )

        store.start()

        guard case .discovering = store.state else {
            return XCTFail("Expected discovery state, got \(store.state)")
        }
        XCTAssertTrue(discovery.didStart)

        let relay = try XCTUnwrap(DiscoveredRelay(
            displayName: "Codex Dock Test",
            hostName: "Amir-M5.local.",
            port: 4510,
            txtRecords: ["auth": "none"]
        ))
        discovery.publish([relay])

        try await waitForRelayBootstrap {
            if case .ready(let registry) = store.state {
                return registry.hosts.first?.webSocketURL.absoluteString == "ws://Amir-M5.local:4510"
                    && registry.hosts.first?.bearerToken == nil
            }
            return false
        }
        let saved = await configurationStore.savedConfiguration()
        XCTAssertEqual(saved?.webSocketURL.absoluteString, "ws://Amir-M5.local:4510")
    }

    @MainActor
    func testRelayBootstrapUsesSavedRelayWhenDiscoveryHasNotPublished() async throws {
        let savedRelayURL = try XCTUnwrap(URL(string: "ws://192.168.50.117:4510"))
        let discovery = FakeRelayDiscovery()
        let configurationStore = BootstrapLocalDockConfigurationStore(
            saved: LocalRelayConfiguration(
                displayName: "Saved Relay",
                webSocketURL: savedRelayURL
            )
        )
        let store = RelayBootstrapStore(
            environment: [:],
            configurationStore: configurationStore,
            discovery: discovery
        )

        store.start()

        try await waitForRelayBootstrap {
            if case .ready(let registry) = store.state {
                return registry.hosts.first?.displayName == "Saved Relay"
                    && registry.hosts.first?.webSocketURL == savedRelayURL
                    && registry.hosts.first?.bearerToken == nil
            }
            return false
        }
        XCTAssertEqual(store.manualURLText, "ws://192.168.50.117:4510")
        XCTAssertTrue(discovery.didStop)
    }

    func testManualRelayValidationAllowsOnlyWebSocketURLs() throws {
        XCTAssertEqual(
            try RelayBootstrapStore.validatedWebSocketURL("ws://192.168.50.117:4510").absoluteString,
            "ws://192.168.50.117:4510"
        )
        XCTAssertThrowsError(
            try RelayBootstrapStore.validatedWebSocketURL("https://192.168.50.117:4510")
        ) { error in
            XCTAssertEqual(
                error as? DockHostConfigurationError,
                .invalidEndpoint("https://192.168.50.117:4510")
            )
        }
        XCTAssertThrowsError(
            try RelayBootstrapStore.validatedWebSocketURL("ws://token@192.168.50.117:4510")
        ) { error in
            XCTAssertEqual(
                error as? DockHostConfigurationError,
                .invalidEndpoint("ws://token@192.168.50.117:4510")
            )
        }
    }

    func testFileLocalDockConfigurationStorePersistsRelayWithoutSecrets() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("relay-config.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let savedURL = try XCTUnwrap(URL(string: "ws://Amir-M5.local:4510"))
        let writer = FileLocalDockConfigurationStore(fileURL: fileURL)
        try await writer.save(
            LocalRelayConfiguration(
                displayName: "Amir-M5",
                webSocketURL: savedURL
            )
        )

        let reader = FileLocalDockConfigurationStore(fileURL: fileURL)
        let loaded = try await reader.load()

        XCTAssertEqual(loaded?.displayName, "Amir-M5")
        XCTAssertEqual(loaded?.webSocketURL, savedURL)
        XCTAssertNil(loaded?.hostConfiguration.bearerToken)
    }
}

private actor BootstrapLocalDockConfigurationStore: LocalDockConfigurationStoring {
    private var saved: LocalRelayConfiguration?

    init(saved: LocalRelayConfiguration? = nil) {
        self.saved = saved
    }

    func load() async throws -> LocalRelayConfiguration? {
        saved
    }

    func save(_ configuration: LocalRelayConfiguration) async throws {
        saved = configuration
    }

    func savedConfiguration() -> LocalRelayConfiguration? {
        saved
    }
}

private final class FakeRelayDiscovery: RelayDiscoveryManaging {
    private(set) var relays: [DiscoveredRelay] = []
    var onRelaysChanged: (@Sendable ([DiscoveredRelay]) -> Void)?
    private(set) var didStart = false
    private(set) var didStop = false

    func start() {
        didStart = true
    }

    func stop() {
        didStop = true
    }

    func publish(_ relays: [DiscoveredRelay]) {
        self.relays = relays
        onRelaysChanged?(relays)
    }
}

@MainActor
private func waitForRelayBootstrap(
    timeout: Duration = .seconds(1),
    condition: @escaping @MainActor () -> Bool
) async throws {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        if ContinuousClock.now >= deadline {
            XCTFail("Timed out waiting for relay bootstrap state")
            return
        }
        try await Task.sleep(for: .milliseconds(10))
    }
}

import XCTest
@testable import CodexDock

final class DockConfigurationTests: XCTestCase {
    func testHostDisplayNameResolverDerivesShortNamesWithoutChangingEndpoint() throws {
        let amirTailnet = try DockHostConfiguration(host: "amir-m5.fairy-salmon.ts.net", port: 4510)
        let homeTailnet = try DockHostConfiguration(host: "home.fairy-salmon.ts.net", port: 4510)
        let amirLocal = try DockHostConfiguration(host: "Amir-M5.local", port: 4510)
        let phoneLAN = try DockHostConfiguration(host: "192.168.50.74", port: 4510)

        XCTAssertEqual(amirTailnet.displayName, "Amir-M5")
        XCTAssertEqual(homeTailnet.displayName, "Home")
        XCTAssertEqual(amirLocal.displayName, "Amir-M5")
        XCTAssertEqual(phoneLAN.displayName, "192.168.50.74")
        XCTAssertEqual(amirTailnet.endpoint.displayEndpoint, "amir-m5.fairy-salmon.ts.net:4510")
    }

    func testHostConfigurationReadsSingleHostEnvironment() throws {
        let host = try DockHostConfiguration.fromEnvironment([
            "CODEX_DOCK_HOSTS": "192.168.50.117:4510"
        ])

        XCTAssertEqual(host.id, "192.168.50.117:4510")
        XCTAssertEqual(host.displayName, "192.168.50.117")
        XCTAssertEqual(host.endpoint.host, "192.168.50.117")
        XCTAssertEqual(host.endpoint.port, 4510)
        XCTAssertEqual(host.webSocketURL.absoluteString, "ws://192.168.50.117:4510")
    }

    func testHostConfigurationRejectsMultipleHostEnvironmentEntries() throws {
        XCTAssertThrowsError(
            try DockHostConfiguration.fromEnvironment([
                "CODEX_DOCK_HOSTS": "Amir-M5.local:4510,home.fairy-salmon.ts.net:4510"
            ])
        ) { error in
            XCTAssertEqual(
                error as? DockHostConfigurationError,
                .multipleHostsForSingleConfiguration("Amir-M5.local:4510,home.fairy-salmon.ts.net:4510")
            )
        }
    }

    func testHostRegistryCreatesOneHostPerEnvironmentEntry() throws {
        let registry = try HostRegistry.fromEnvironment([
            "CODEX_DOCK_HOSTS": "amir-m5.fairy-salmon.ts.net:4510, home.fairy-salmon.ts.net:4510",
            "CODEX_DOCK_RELAY_INSTANCE_ID": "ignored-old-app-config"
        ])

        XCTAssertEqual(registry.hosts.map(\.id), [
            "amir-m5.fairy-salmon.ts.net:4510",
            "home.fairy-salmon.ts.net:4510"
        ])
        XCTAssertEqual(registry.hosts.map(\.displayName), [
            "Amir-M5",
            "Home"
        ])
        XCTAssertEqual(registry.hosts.map { $0.webSocketURL.absoluteString }, [
            "ws://amir-m5.fairy-salmon.ts.net:4510",
            "ws://home.fairy-salmon.ts.net:4510"
        ])
    }

    func testHostRegistryIgnoresLegacyScopedAppSecrets() throws {
        let registry = try HostRegistry.fromEnvironment([
            "CODEX_DOCK_HOSTS": "192.168.50.117:4510, home.local:4511",
            "CODEX_DOCK_RELAY_INSTANCE_ID": "ignored-old-app-config",
            "CODEX_DOCK_HOST_AMIR_M5_WS": "ws://192.168.50.117:4510/",
            "CODEX_DOCK_HOST_AMIR_M5_NAME": "Amir-M5",
            "CODEX_DOCK_HOST_AMIR_M5_AUTH_MODE": "none",
            "CODEX_DOCK_HOST_AMIR_M5_TOKEN": "ignored-token",
            "CODEX_DOCK_HOST_HOME_WS": "ws://100.66.11.7:4510/",
            "CODEX_DOCK_HOST_HOME_NAME": "Home",
            "CODEX_DOCK_HOST_HOME_AUTH_MODE": "none",
            "CODEX_DOCK_HOST_HOME_BEARER_TOKEN": "ignored-home-token"
        ])

        XCTAssertEqual(registry.hosts.map(\.id), [
            "192.168.50.117:4510",
            "home.local:4511"
        ])
    }

    func testHostConfigurationRejectsMissingEndpoint() {
        XCTAssertThrowsError(
            try DockHostConfiguration.fromEnvironment([
                "CODEX_DOCK_APP_SERVER_BEARER_TOKEN": "ignored"
            ])
        ) { error in
            XCTAssertEqual(error as? DockHostConfigurationError, .missingEndpoint)
        }
    }

    func testHostConfigurationRejectsCredentialBearingEndpointHost() {
        XCTAssertThrowsError(
            try DockHostConfiguration.fromEnvironment([
                "CODEX_DOCK_HOSTS": "token@192.168.50.117:4510"
            ])
        ) { error in
            XCTAssertEqual(
                error as? DockHostConfigurationError,
                .invalidHost("token@192.168.50.117")
            )
        }
    }

    func testHostRegistryRejectsDuplicateHostIDs() {
        XCTAssertThrowsError(
            try HostRegistry.fromEnvironment([
                "CODEX_DOCK_HOSTS": "home.local:4510, home.local:4510"
            ])
        ) { error in
            XCTAssertEqual(error as? DockHostConfigurationError, .duplicateHostID("home.local:4510"))
        }
    }

    func testHostRegistryRejectsMissingHostList() {
        XCTAssertThrowsError(
            try HostRegistry.fromEnvironment([
                "CODEX_DOCK_HOST_HOME_NAME": "Home"
            ])
        ) { error in
            XCTAssertEqual(error as? DockHostConfigurationError, .missingEndpoint)
        }
    }

    func testHostRegistryRejectsInvalidPort() {
        XCTAssertThrowsError(
            try HostRegistry.fromEnvironment([
                "CODEX_DOCK_HOSTS": "home.local:not-a-port"
            ])
        ) { error in
            XCTAssertEqual(error as? DockHostConfigurationError, .invalidPort("not-a-port"))
        }
    }

    func testHostRegistryRejectsRawAppServerPortForAppFacingConfig() {
        XCTAssertThrowsError(
            try HostRegistry.fromEnvironment([
                "CODEX_DOCK_HOSTS": "127.0.0.1:4500"
            ])
        ) { error in
            XCTAssertEqual(
                error as? DockHostConfigurationError,
                .rawAppServerEndpoint("127.0.0.1:4500")
            )
        }
    }

    func testEndpointParsingAcceptsLocalTailnetIPv4AndIPv6Hosts() throws {
        let endpoints = try DockRelayEndpoint.parseList(
            "home:4510,home.local:4511,home.example.ts.net:4512,100.66.11.7:4513,[fd7a:115c:a1e0::1]:4514"
        )

        XCTAssertEqual(endpoints.map(\.displayEndpoint), [
            "home:4510",
            "home.local:4511",
            "home.example.ts.net:4512",
            "100.66.11.7:4513",
            "[fd7a:115c:a1e0::1]:4514"
        ])
        XCTAssertEqual(endpoints.last?.host, "fd7a:115c:a1e0::1")
        XCTAssertEqual(endpoints.last?.webSocketURL.absoluteString, "ws://[fd7a:115c:a1e0::1]:4514")
    }

    func testEndpointParsingRejectsURLCredentialPathQueryFragmentWhitespaceAndBadPorts() {
        let invalidEndpoints: [(String, DockHostConfigurationError)] = [
            ("ws://home.local:4510", .invalidEndpoint("ws://home.local:4510")),
            ("token@home.local:4510", .invalidHost("token@home.local")),
            ("home.local/path:4510", .invalidHost("home.local/path")),
            ("home.local?x=1:4510", .invalidHost("home.local?x=1")),
            ("home.local#frag:4510", .invalidHost("home.local#frag")),
            ("home local:4510", .invalidHost("home local")),
            ("home.local", .invalidEndpoint("home.local")),
            ("home.local:0", .invalidPort("0")),
            ("home.local:65536", .invalidPort("65536")),
            ("home.local:-1", .invalidPort("-1"))
        ]

        for (value, expectedError) in invalidEndpoints {
            XCTAssertThrowsError(try DockRelayEndpoint.parse(value), value) { error in
                XCTAssertEqual(error as? DockHostConfigurationError, expectedError)
            }
        }
    }

    func testDiscoveredRelayUsesEndpointAsHostIdentityAndKeepsRelayIDAsMetadata() throws {
        let relay = try XCTUnwrap(DiscoveredRelay(
            displayName: "Codex Dock Test",
            hostName: "Amir-M5.local.",
            port: 4510,
            txtRecords: ["relay-id": "Amir-M5"]
        ))

        XCTAssertEqual(relay.id, "Amir-M5.local:4510")
        XCTAssertEqual(relay.relayInstanceID, "Amir-M5")
        XCTAssertEqual(relay.hostConfiguration.id, "Amir-M5.local:4510")
        XCTAssertEqual(relay.hostConfiguration.webSocketURL.absoluteString, "ws://Amir-M5.local:4510")
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
            }
            return false
        }
        let saved = await configurationStore.savedConfiguration()
        XCTAssertEqual(try saved?.hostConfigurations.first?.endpoint.displayEndpoint, "Amir-M5.local:4510")
    }

    @MainActor
    func testRelayBootstrapUsesSavedRelayAndDoesNotMergeDiscoveredEndpointAfterStoppingDiscovery() async throws {
        let discovery = FakeRelayDiscovery()
        let configurationStore = BootstrapLocalDockConfigurationStore(
            saved: LocalRelayHostList(hosts: [
                DockHostConfiguration(endpoint: try DockRelayEndpoint(host: "192.168.50.117", port: 4510))
            ])
        )
        let store = RelayBootstrapStore(
            environment: [:],
            configurationStore: configurationStore,
            discovery: discovery
        )

        store.start()

        try await waitForRelayBootstrap {
            if case .ready(let registry) = store.state {
                return registry.hosts.first?.displayName == "192.168.50.117"
                    && registry.hosts.first?.webSocketURL.absoluteString == "ws://192.168.50.117:4510"
            }
            return false
        }
        XCTAssertEqual(store.manualHostText, "192.168.50.117")
        XCTAssertEqual(store.manualPortText, "4510")
        XCTAssertTrue(discovery.didStop)

        let relay = try XCTUnwrap(DiscoveredRelay(
            displayName: "Codex Dock Test",
            hostName: "Amir-M5.local.",
            port: 4510
        ))
        discovery.publish([relay])
        try await Task.sleep(for: .milliseconds(50))

        guard case .ready(let registry) = store.state else {
            return XCTFail("Expected ready state, got \(store.state)")
        }
        XCTAssertEqual(registry.hosts.map(\.id), ["192.168.50.117:4510"])
        let saved = await configurationStore.savedConfiguration()
        XCTAssertEqual(
            try saved?.hostConfigurations.map { $0.endpoint.displayEndpoint },
            ["192.168.50.117:4510"]
        )
    }

    @MainActor
    func testRelayBootstrapEnvironmentHostsDoNotMergeSavedOrDiscoveredHosts() async throws {
        let discovery = FakeRelayDiscovery()
        let configurationStore = BootstrapLocalDockConfigurationStore(
            saved: LocalRelayHostList(hosts: [
                DockHostConfiguration(endpoint: try DockRelayEndpoint(host: "saved.local", port: 4510))
            ])
        )
        let store = RelayBootstrapStore(
            environment: [
                "CODEX_DOCK_HOSTS": "env.local:4510",
                "CODEX_DOCK_RELAY_INSTANCE_ID": "ignored-old-app-config"
            ],
            configurationStore: configurationStore,
            discovery: discovery
        )

        store.start()

        guard case .ready(let registry) = store.state else {
            return XCTFail("Expected ready state, got \(store.state)")
        }
        XCTAssertEqual(registry.hosts.map(\.id), ["env.local:4510"])
        XCTAssertEqual(store.manualHostText, "env.local")
        XCTAssertEqual(store.manualPortText, "4510")
        XCTAssertFalse(discovery.didStart)

        let relay = try XCTUnwrap(DiscoveredRelay(
            displayName: "Codex Dock Test",
            hostName: "discovered.local.",
            port: 4510,
            txtRecords: ["relay-id": "Amir-M5"]
        ))
        discovery.publish([relay])
        try await Task.sleep(for: .milliseconds(50))

        guard case .ready(let unchangedRegistry) = store.state else {
            return XCTFail("Expected ready state, got \(store.state)")
        }
        XCTAssertEqual(unchangedRegistry.hosts.map(\.id), ["env.local:4510"])
        let saved = await configurationStore.savedConfiguration()
        XCTAssertEqual(
            try saved?.hostConfigurations.map { $0.endpoint.displayEndpoint },
            ["saved.local:4510"]
        )
    }

    @MainActor
    func testRelayBootstrapStopsDiscoveryWhenBackgroundedBeforeReady() {
        let discovery = FakeRelayDiscovery()
        let store = RelayBootstrapStore(
            environment: [:],
            configurationStore: BootstrapLocalDockConfigurationStore(),
            discovery: discovery
        )

        store.start()
        store.handleLifecycle(AppLifecycleSnapshot(phase: .backgrounded, resumeGeneration: 0))

        XCTAssertEqual(discovery.startCount, 1)
        XCTAssertEqual(discovery.stopCount, 1)
        guard case .discovering(_, let message) = store.state else {
            return XCTFail("Expected discovering state, got \(store.state)")
        }
        XCTAssertEqual(message, "Backgrounded")
    }

    @MainActor
    func testRelayBootstrapIgnoresLateDiscoveryCallbackWhileBackgrounded() async throws {
        let discovery = FakeRelayDiscovery()
        let configurationStore = BootstrapLocalDockConfigurationStore()
        let store = RelayBootstrapStore(
            environment: [:],
            configurationStore: configurationStore,
            discovery: discovery
        )
        let relay = try XCTUnwrap(DiscoveredRelay(
            displayName: "Codex Dock Test",
            hostName: "Amir-M5.local.",
            port: 4510,
            txtRecords: ["auth": "none"]
        ))

        store.start()
        store.handleLifecycle(AppLifecycleSnapshot(phase: .backgrounded, resumeGeneration: 0))
        discovery.publish([relay])
        try await Task.sleep(for: .milliseconds(50))

        guard case .discovering = store.state else {
            return XCTFail("Expected discovering state, got \(store.state)")
        }
        let savedConfiguration = await configurationStore.savedConfiguration()
        let saveCount = await configurationStore.saveCountSnapshot()
        XCTAssertNil(savedConfiguration)
        XCTAssertEqual(saveCount, 0)
        XCTAssertEqual(discovery.stopCount, 1)
    }

    @MainActor
    func testRelayBootstrapRestartsDiscoveryOnForegroundResumeWhenStillUnready() async throws {
        let discovery = FakeRelayDiscovery()
        let configurationStore = BootstrapLocalDockConfigurationStore()
        let store = RelayBootstrapStore(
            environment: [:],
            configurationStore: configurationStore,
            discovery: discovery
        )
        let relay = try XCTUnwrap(DiscoveredRelay(
            displayName: "Codex Dock Test",
            hostName: "Amir-M5.local.",
            port: 4510,
            txtRecords: ["auth": "none"]
        ))

        store.start()
        store.handleLifecycle(AppLifecycleSnapshot(phase: .backgrounded, resumeGeneration: 0))
        store.handleLifecycle(AppLifecycleSnapshot(phase: .foregroundResuming, resumeGeneration: 1))

        XCTAssertEqual(discovery.startCount, 2)
        discovery.publish([relay])

        try await waitForRelayBootstrap {
            if case .ready(let registry) = store.state {
                return registry.hosts.first?.webSocketURL.absoluteString == "ws://Amir-M5.local:4510"
            }
            return false
        }
        let savedConfiguration = await configurationStore.savedConfiguration()
        XCTAssertEqual(try savedConfiguration?.hostConfigurations.first?.endpoint.displayEndpoint, "Amir-M5.local:4510")
    }

    @MainActor
    func testRelayBootstrapPreservesManualEndpointTextAndDoesNotDuplicateDiscoveryStartsAcrossResume() {
        let discovery = FakeRelayDiscovery()
        let store = RelayBootstrapStore(
            environment: [:],
            configurationStore: BootstrapLocalDockConfigurationStore(),
            discovery: discovery
        )

        store.start()
        store.manualHostText = "manual.local"
        store.manualPortText = "4510"
        store.handleLifecycle(AppLifecycleSnapshot(phase: .backgrounded, resumeGeneration: 0))
        store.handleLifecycle(AppLifecycleSnapshot(phase: .foregroundResuming, resumeGeneration: 1))
        store.handleLifecycle(AppLifecycleSnapshot(phase: .active, resumeGeneration: 1))
        store.handleLifecycle(AppLifecycleSnapshot(phase: .active, resumeGeneration: 1))

        XCTAssertEqual(store.manualHostText, "manual.local")
        XCTAssertEqual(store.manualPortText, "4510")
        XCTAssertEqual(discovery.startCount, 2)
        XCTAssertEqual(discovery.callbackSetCount, 1)
    }

    @MainActor
    func testRelayBootstrapDoesNotAutoUseRelayTwiceFromDuplicateCallbacks() async throws {
        let discovery = FakeRelayDiscovery()
        let configurationStore = BootstrapLocalDockConfigurationStore()
        let store = RelayBootstrapStore(
            environment: [:],
            configurationStore: configurationStore,
            discovery: discovery
        )
        let relay = try XCTUnwrap(DiscoveredRelay(
            displayName: "Codex Dock Test",
            hostName: "Amir-M5.local.",
            port: 4510,
            txtRecords: ["auth": "none"]
        ))

        store.start()
        discovery.publish([relay])
        discovery.publish([relay])

        try await waitForRelayBootstrap {
            if case .ready(let registry) = store.state {
                return registry.hosts.count == 1
            }
            return false
        }
        let saveCount = await configurationStore.saveCountSnapshot()
        XCTAssertEqual(saveCount, 1)
    }

    func testManualRelayValidationAllowsOnlyHostAndPort() throws {
        XCTAssertEqual(
            try RelayBootstrapStore.validatedEndpoint(
                host: "192.168.50.117",
                port: "4510"
            ).displayEndpoint,
            "192.168.50.117:4510"
        )
        XCTAssertThrowsError(
            try RelayBootstrapStore.validatedEndpoint(host: "https://192.168.50.117", port: "4510")
        ) { error in
            XCTAssertEqual(
                error as? DockHostConfigurationError,
                .invalidHost("https://192.168.50.117")
            )
        }
        XCTAssertThrowsError(
            try RelayBootstrapStore.validatedEndpoint(host: "192.168.50.117", port: "not-a-port")
        ) { error in
            XCTAssertEqual(
                error as? DockHostConfigurationError,
                .invalidPort("not-a-port")
            )
        }
        XCTAssertThrowsError(
            try RelayBootstrapStore.validatedEndpoint(host: "127.0.0.1", port: "4500")
        ) { error in
            XCTAssertEqual(
                error as? DockHostConfigurationError,
                .rawAppServerEndpoint("127.0.0.1:4500")
            )
        }
    }

    func testFileLocalDockConfigurationStorePersistsHostListWithoutSecrets() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("relay-config.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let writer = FileLocalDockConfigurationStore(fileURL: fileURL)
        try await writer.save(
            LocalRelayHostList(hosts: [
                DockHostConfiguration(endpoint: try DockRelayEndpoint(host: "Amir-M5.local", port: 4510)),
                DockHostConfiguration(endpoint: try DockRelayEndpoint(host: "home.fairy-salmon.ts.net", port: 4510))
            ])
        )

        let reader = FileLocalDockConfigurationStore(fileURL: fileURL)
        let loaded = try await reader.load()

        XCTAssertEqual(
            try loaded?.hostConfigurations.map { $0.endpoint.displayEndpoint },
            ["Amir-M5.local:4510", "home.fairy-salmon.ts.net:4510"]
        )
        let savedText = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(savedText.contains(#""hosts""#))
        XCTAssertFalse(savedText.contains(#""endpoints""#))
        XCTAssertFalse(savedText.contains("relayInstanceID"))
        XCTAssertFalse(savedText.contains("OPENAI_API_KEY"))
        XCTAssertFalse(savedText.contains("TOKEN"))
    }

    func testFileLocalDockConfigurationStoreRejectsOldEndpointListJSONWithoutDeletingFile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("relay-config.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try #"{"endpoints":[{"host":"amir-m5.fairy-salmon.ts.net","port":4510},{"host":"home.fairy-salmon.ts.net","port":4510}],"relayInstanceID":"Amir-M5"}"#
            .write(to: fileURL, atomically: true, encoding: .utf8)

        let reader = FileLocalDockConfigurationStore(fileURL: fileURL)

        do {
            _ = try await reader.load()
            XCTFail("Expected old endpoint-list JSON to fail")
        } catch {
            XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testFileLocalDockConfigurationStoreRejectsPhoneSideRelayIdentityWithoutDeletingFile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("relay-config.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try #"{"hosts":[{"host":"amir-m5.fairy-salmon.ts.net","port":4510}],"relayInstanceID":"Amir-M5"}"#
            .write(to: fileURL, atomically: true, encoding: .utf8)

        let reader = FileLocalDockConfigurationStore(fileURL: fileURL)

        do {
            _ = try await reader.load()
            XCTFail("Expected saved phone-side relay identity to fail")
        } catch {
            XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        }
    }

    func testFileLocalDockConfigurationStoreRejectsDuplicateHostsWithoutDeletingFile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("relay-config.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try #"{"hosts":[{"host":"Amir-M5.local","port":4510},{"host":"Amir-M5.local","port":4510}]}"#
            .write(to: fileURL, atomically: true, encoding: .utf8)

        let reader = FileLocalDockConfigurationStore(fileURL: fileURL)

        do {
            _ = try await reader.load()
            XCTFail("Expected duplicate saved hosts to fail")
        } catch {
            XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        }
    }

    func testFileLocalDockConfigurationStoreRejectsRawAppServerHostWithoutDeletingFile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("relay-config.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try #"{"hosts":[{"host":"127.0.0.1","port":4500}]}"#
            .write(to: fileURL, atomically: true, encoding: .utf8)

        let reader = FileLocalDockConfigurationStore(fileURL: fileURL)

        do {
            _ = try await reader.load()
            XCTFail("Expected raw app-server host to fail")
        } catch DockHostConfigurationError.rawAppServerEndpoint(let value) {
            XCTAssertEqual(value, "127.0.0.1:4500")
            XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        } catch {
            XCTFail("Expected rawAppServerEndpoint, got \(error)")
        }
    }

    func testFileLocalDockConfigurationStoreRejectsLegacyWebSocketURLWithoutDeletingFile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("relay-config.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try #"{"displayName":"Amir-M5","webSocketURL":"ws://Amir-M5.local:4510"}"#
            .write(to: fileURL, atomically: true, encoding: .utf8)

        let reader = FileLocalDockConfigurationStore(fileURL: fileURL)

        do {
            _ = try await reader.load()
            XCTFail("Expected legacy WebSocket URL JSON to fail")
        } catch {
            XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }
}

private actor BootstrapLocalDockConfigurationStore: LocalDockConfigurationStoring {
    private var saved: LocalRelayHostList?
    private var saveCount = 0

    init(saved: LocalRelayHostList? = nil) {
        self.saved = saved
    }

    func load() async throws -> LocalRelayHostList? {
        saved
    }

    func save(_ configuration: LocalRelayHostList) async throws {
        saveCount += 1
        saved = configuration
    }

    func savedConfiguration() -> LocalRelayHostList? {
        saved
    }

    func saveCountSnapshot() -> Int {
        saveCount
    }
}

private final class FakeRelayDiscovery: RelayDiscoveryManaging {
    private(set) var relays: [DiscoveredRelay] = []
    private var relaysChangedHandler: (@Sendable ([DiscoveredRelay]) -> Void)?
    var onRelaysChanged: (@Sendable ([DiscoveredRelay]) -> Void)? {
        get {
            relaysChangedHandler
        }
        set {
            callbackSetCount += 1
            relaysChangedHandler = newValue
        }
    }
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var callbackSetCount = 0

    var didStart: Bool {
        startCount > 0
    }

    var didStop: Bool {
        stopCount > 0
    }

    func start() {
        startCount += 1
    }

    func stop() {
        stopCount += 1
    }

    func publish(_ relays: [DiscoveredRelay]) {
        self.relays = relays
        relaysChangedHandler?(relays)
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

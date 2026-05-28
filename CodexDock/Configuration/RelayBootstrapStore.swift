import Combine
import Foundation

public enum RelayBootstrapState: Equatable, Sendable {
    case starting
    case discovering(relays: [DiscoveredRelay], message: String?)
    case ready(HostRegistry)
    case failed(String)
}

@MainActor
public final class RelayBootstrapStore: ObservableObject {
    @Published public private(set) var state: RelayBootstrapState = .starting
    @Published public var manualURLText = ""

    private let environment: [String: String]
    private let configurationStore: any LocalDockConfigurationStoring
    private let discovery: any RelayDiscoveryManaging
    private var didStart = false

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        configurationStore: any LocalDockConfigurationStoring = FileLocalDockConfigurationStore(),
        discovery: any RelayDiscoveryManaging = BonjourRelayDiscovery()
    ) {
        self.environment = environment
        self.configurationStore = configurationStore
        self.discovery = discovery
    }

    public func start() {
        guard !didStart else {
            return
        }
        didStart = true

        if let registry = try? HostRegistry.fromEnvironment(environment) {
            state = .ready(registry)
            return
        }

        state = .discovering(relays: discovery.relays, message: "Finding Codex Dock relay")
        discovery.onRelaysChanged = { [weak self] relays in
            Task { @MainActor in
                self?.handleDiscoveredRelays(relays)
            }
        }
        discovery.start()

        Task {
            await loadSavedManualURL()
        }
    }

    public func connectManually() async {
        do {
            let url = try Self.validatedWebSocketURL(manualURLText)
            try await useManualURL(url)
        } catch {
            state = .discovering(relays: discovery.relays, message: error.localizedDescription)
        }
    }

    public func use(_ relay: DiscoveredRelay) async {
        await useConfiguration(
            relay.hostConfiguration,
            persistence: LocalRelayConfiguration(
                displayName: relay.displayName,
                webSocketURL: relay.webSocketURL
            )
        )
    }

    nonisolated public static func validatedWebSocketURL(_ rawValue: String) throws -> URL {
        try DockHostConfiguration.validatedWebSocketURL(rawValue)
    }

    private func handleDiscoveredRelays(_ relays: [DiscoveredRelay]) {
        guard case .ready = state else {
            if let first = relays.first {
                Task {
                    await use(first)
                }
            } else {
                state = .discovering(relays: relays, message: "Finding Codex Dock relay")
            }
            return
        }
    }

    private func loadSavedManualURL() async {
        do {
            guard let configuration = try await configurationStore.load() else {
                return
            }
            manualURLText = configuration.webSocketURL.absoluteString
            if case .discovering = state {
                await useConfiguration(
                    configuration.hostConfiguration,
                    persistence: configuration
                )
            }
        } catch {
            if case .discovering(let relays, _) = state {
                state = .discovering(relays: relays, message: "Saved relay could not be read")
            }
        }
    }

    private func useManualURL(_ url: URL) async throws {
        let configuration = DockHostConfiguration(
            id: url.host ?? "codex-dock-relay",
            displayName: url.host ?? "Codex Dock Relay",
            webSocketURL: url,
            bearerToken: nil
        )
        await useConfiguration(
            configuration,
            persistence: LocalRelayConfiguration(
                displayName: configuration.displayName,
                webSocketURL: url
            )
        )
    }

    private func useConfiguration(
        _ host: DockHostConfiguration,
        persistence: LocalRelayConfiguration
    ) async {
        do {
            try await configurationStore.save(persistence)
        } catch {
            state = .failed("Relay was found, but the connection could not be saved.")
            return
        }

        do {
            state = .ready(try HostRegistry(hosts: [host]))
            discovery.stop()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

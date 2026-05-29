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
    @Published public var manualHostText = ""
    @Published public var manualPortText = "4510"

    private let environment: [String: String]
    private let configurationStore: any LocalDockConfigurationStoring
    private let discovery: any RelayDiscoveryManaging
    private var didStart = false
    private var didBindDiscoveryCallback = false
    private var isBackgrounded = false
    private var isDiscoveryRunning = false
    private var isLoadingSavedConfiguration = false
    private var isUsingConfiguration = false
    private var handledResumeGeneration: Int?

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
            DockLog.bootstrap.debug("relay bootstrap start skipped reason=already_started")
            return
        }
        didStart = true
        DockLog.bootstrap.notice("relay bootstrap started")

        if let registry = try? HostRegistry.fromEnvironment(environment) {
            DockLog.bootstrap.notice("relay bootstrap environment ready hosts=\(registry.hosts.count, privacy: .public)")
            state = .ready(registry)
            startDiscoveryIfNeeded(message: "Finding Codex Dock relay", preserveReadyState: true)
            Task {
                await loadSavedManualURL(allowManualTextOverwrite: true)
            }
            return
        }
        DockLog.bootstrap.info("relay bootstrap environment missing; starting discovery")

        isLoadingSavedConfiguration = true
        startDiscoveryIfNeeded(message: "Finding Codex Dock relay")

        Task {
            await loadSavedManualURL(allowManualTextOverwrite: true)
        }
    }

    public func handleLifecycle(_ snapshot: AppLifecycleSnapshot) {
        DockLog.bootstrap.debug("relay bootstrap lifecycle phase=\(snapshot.phase.logDescription, privacy: .public) resume_generation=\(snapshot.resumeGeneration, privacy: .public)")
        switch snapshot.phase {
        case .inactive:
            return
        case .backgrounded:
            isBackgrounded = true
            guard !isReady else {
                return
            }
            stopDiscoveryIfNeeded()
            state = .discovering(relays: discovery.relays, message: "Backgrounded")
        case .foregroundResuming:
            guard handledResumeGeneration != snapshot.resumeGeneration else {
                return
            }
            handledResumeGeneration = snapshot.resumeGeneration
            isBackgrounded = false
            guard !isReady else {
                return
            }
            startDiscoveryIfNeeded(message: "Finding Codex Dock relay")
            Task {
                await loadSavedManualURL(allowManualTextOverwrite: false)
            }
        case .active:
            isBackgrounded = false
        }
    }

    public func connectManually() async {
        do {
            let endpoint = try Self.validatedEndpoint(host: manualHostText, port: manualPortText)
            DockLog.bootstrap.notice("relay manual connect started endpoint=\(DockLog.endpoint(endpoint.webSocketURL), privacy: .public)")
            await useEndpoint(endpoint)
        } catch {
            DockLog.bootstrap.error("relay manual connect failed error=\(DockLog.errorSummary(error), privacy: .public)")
            state = .discovering(relays: discovery.relays, message: error.localizedDescription)
        }
    }

    public func use(_ relay: DiscoveredRelay) async {
        DockLog.bootstrap.notice("relay discovery selection started relay_id=\(relay.id, privacy: .public) name=\(relay.displayName, privacy: .public)")
        await useEndpoints([relay.endpoint], relayInstanceID: relay.relayInstanceID, stopDiscovery: true)
    }

    nonisolated public static func validatedEndpoint(host: String, port: String) throws -> DockRelayEndpoint {
        guard let portNumber = Int(port.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw DockHostConfigurationError.invalidPort(port)
        }
        let endpoint = try DockRelayEndpoint(host: host, port: portNumber)
        try endpoint.validateAppFacingRelayEndpoint()
        return endpoint
    }

    private func handleDiscoveredRelays(_ relays: [DiscoveredRelay]) {
        DockLog.bootstrap.debug("relay discovery updated count=\(relays.count, privacy: .public) backgrounded=\(self.isBackgrounded, privacy: .public) running=\(self.isDiscoveryRunning, privacy: .public)")
        guard !isBackgrounded, isDiscoveryRunning else {
            guard !isReady else {
                return
            }
            state = .discovering(
                relays: relays,
                message: isBackgrounded ? "Backgrounded" : "Finding Codex Dock relay"
            )
            return
        }

        guard !isLoadingSavedConfiguration else {
            state = .discovering(relays: relays, message: "Finding Codex Dock relay")
            return
        }

        if case .ready(let registry) = state {
            Task {
                var currentRegistry = registry
                for relay in relays {
                    await upsert([relay.endpoint], relayInstanceID: relay.relayInstanceID, into: currentRegistry, stopDiscovery: false)
                    if case .ready(let updatedRegistry) = self.state {
                        currentRegistry = updatedRegistry
                    }
                }
            }
            return
        }

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

    private var isReady: Bool {
        if case .ready = state {
            return true
        }
        return false
    }

    private func bindDiscoveryCallbackIfNeeded() {
        guard !didBindDiscoveryCallback else {
            return
        }
        didBindDiscoveryCallback = true
        discovery.onRelaysChanged = { [weak self] relays in
            Task { @MainActor in
                self?.handleDiscoveredRelays(relays)
            }
        }
    }

    private func startDiscoveryIfNeeded(message: String, preserveReadyState: Bool = false) {
        bindDiscoveryCallbackIfNeeded()
        if !preserveReadyState || !isReady {
            state = .discovering(relays: discovery.relays, message: message)
        }
        guard !isDiscoveryRunning else {
            DockLog.bootstrap.debug("relay discovery start skipped reason=already_running")
            return
        }
        DockLog.bootstrap.notice("relay discovery started message=\(message, privacy: .public)")
        discovery.start()
        isDiscoveryRunning = true
    }

    private func stopDiscoveryIfNeeded() {
        guard isDiscoveryRunning else {
            return
        }
        DockLog.bootstrap.notice("relay discovery stopped")
        discovery.stop()
        isDiscoveryRunning = false
    }

    private func loadSavedManualURL(allowManualTextOverwrite: Bool) async {
        do {
            guard let configuration = try await configurationStore.load() else {
                DockLog.bootstrap.info("saved relay configuration missing")
                await finishLoadingSavedConfigurationWithoutSavedRelay()
                return
            }
            let endpoints = try configuration.relayEndpoints
            guard !endpoints.isEmpty else {
                await finishLoadingSavedConfigurationWithoutSavedRelay()
                return
            }
            let first = endpoints[0]
            DockLog.bootstrap.info("saved relay configuration loaded endpoints=\(endpoints.count, privacy: .public) first_endpoint=\(DockLog.endpoint(first.webSocketURL), privacy: .public)")
            let typedManualText = manualHostText.trimmingCharacters(in: .whitespacesAndNewlines)
            let shouldUseSaved = allowManualTextOverwrite
                || typedManualText.isEmpty
                || typedManualText == first.host
            if allowManualTextOverwrite || typedManualText.isEmpty {
                manualHostText = first.host
                manualPortText = String(first.port)
            }
            if case .ready(let registry) = state {
                isLoadingSavedConfiguration = false
                await upsert(
                    endpoints,
                    relayInstanceID: configuration.relayInstanceID,
                    into: registry,
                    stopDiscovery: false
                )
            } else if case .discovering = state, !isBackgrounded, shouldUseSaved {
                isLoadingSavedConfiguration = false
                await useEndpoints(
                    endpoints,
                    relayInstanceID: configuration.relayInstanceID,
                    stopDiscovery: true
                )
            } else {
                isLoadingSavedConfiguration = false
            }
        } catch {
            isLoadingSavedConfiguration = false
            DockLog.bootstrap.warning("saved relay configuration load failed error=\(DockLog.errorSummary(error), privacy: .public)")
            if case .discovering(let relays, _) = state {
                state = .discovering(relays: relays, message: "Saved relay could not be read")
            }
        }
    }

    private func finishLoadingSavedConfigurationWithoutSavedRelay() async {
        let wasLoadingSavedConfiguration = isLoadingSavedConfiguration
        isLoadingSavedConfiguration = false
        guard wasLoadingSavedConfiguration,
              !isBackgrounded,
              case .discovering = state,
              let first = discovery.relays.first
        else {
            return
        }
        await use(first)
    }

    private func useEndpoint(_ endpoint: DockRelayEndpoint) async {
        await useEndpoints([endpoint], relayInstanceID: nil, stopDiscovery: true)
    }

    private func useEndpoints(
        _ endpoints: [DockRelayEndpoint],
        relayInstanceID: String? = nil,
        stopDiscovery: Bool
    ) async {
        guard !isUsingConfiguration else {
            return
        }
        isUsingConfiguration = true
        defer {
            isUsingConfiguration = false
        }

        do {
            let persistence = LocalRelayEndpointList(endpoints: endpoints, relayInstanceID: relayInstanceID)
            try await configurationStore.save(persistence)
            DockLog.bootstrap.notice("relay configuration saved endpoints=\(persistence.endpoints.count, privacy: .public)")
        } catch {
            DockLog.bootstrap.error("relay configuration save failed error=\(DockLog.errorSummary(error), privacy: .public)")
            state = .failed("Relay was found, but the connection could not be saved.")
            return
        }

        do {
            state = .ready(try HostRegistry(hosts: Self.hosts(for: endpoints, relayInstanceID: relayInstanceID)))
            DockLog.bootstrap.notice("relay bootstrap ready hosts=\(endpoints.count, privacy: .public)")
            if stopDiscovery {
                stopDiscoveryIfNeeded()
            }
        } catch {
            DockLog.bootstrap.error("relay host registry failed error=\(DockLog.errorSummary(error), privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }

    private func upsert(
        _ endpoints: [DockRelayEndpoint],
        relayInstanceID: String?,
        into registry: HostRegistry,
        stopDiscovery: Bool = true
    ) async {
        guard let candidate = try? Self.hosts(for: endpoints, relayInstanceID: relayInstanceID).first else {
            return
        }
        var hosts = registry.hosts
        if let index = hosts.firstIndex(where: { $0.id == candidate.id }) {
            let existing = hosts[index]
            let mergedEndpoints = existing.endpoints + candidate.endpoints.filter { endpoint in
                !existing.endpoints.contains { $0.id == endpoint.id }
            }
            guard mergedEndpoints.count != existing.endpoints.count else {
                if stopDiscovery {
                    stopDiscoveryIfNeeded()
                }
                return
            }
            hosts[index] = (try? DockHostConfiguration(
                endpoints: mergedEndpoints,
                relayInstanceID: existing.relayInstanceID ?? candidate.relayInstanceID
            )) ?? existing
        } else {
            hosts.append(candidate)
        }

        let persistedRelayInstanceID = hosts.count == 1 ? hosts[0].relayInstanceID : nil
        let persistedEndpoints = hosts.flatMap(\.endpoints)
        guard let updatedRegistry = try? HostRegistry(hosts: hosts),
              updatedRegistry != registry
        else {
            if stopDiscovery {
                stopDiscoveryIfNeeded()
            }
            return
        }
        guard hosts.count == 1 || persistedRelayInstanceID != nil else {
            DockLog.bootstrap.warning("relay upsert skipped reason=missing_relay_instance_id_for_endpoint_aliases hosts=\(hosts.count, privacy: .public)")
            if stopDiscovery {
                stopDiscoveryIfNeeded()
            }
            return
        }
        await useEndpoints(
            persistedEndpoints,
            relayInstanceID: persistedRelayInstanceID,
            stopDiscovery: stopDiscovery
        )
    }

    private static func hosts(
        for endpoints: [DockRelayEndpoint],
        relayInstanceID: String?
    ) throws -> [DockHostConfiguration] {
        let trimmedRelayInstanceID = relayInstanceID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return [
            try DockHostConfiguration(
                endpoints: endpoints,
                relayInstanceID: trimmedRelayInstanceID.isEmpty ? nil : trimmedRelayInstanceID
            )
        ]
    }
}

private extension AppLifecyclePhase {
    var logDescription: String {
        switch self {
        case .active:
            return "active"
        case .inactive:
            return "inactive"
        case .backgrounded:
            return "backgrounded"
        case .foregroundResuming:
            return "foregroundResuming"
        }
    }
}

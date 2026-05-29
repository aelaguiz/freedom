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
    @Published public var manualPortText = CodexDockConstants.Ports.dockRelayString

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
            populateManualFields(from: registry.hosts.first, allowManualTextOverwrite: true)
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
        await useHost(relay.hostConfiguration, stopDiscovery: true)
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
                    await upsert([relay.hostConfiguration], into: currentRegistry, stopDiscovery: false)
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
            let hosts = try configuration.hostConfigurations
            guard !hosts.isEmpty else {
                await finishLoadingSavedConfigurationWithoutSavedRelay()
                return
            }
            let first = hosts[0].endpoint
            DockLog.bootstrap.info("saved relay configuration loaded hosts=\(hosts.count, privacy: .public) first_endpoint=\(DockLog.endpoint(first.webSocketURL), privacy: .public)")
            let shouldUseSaved = shouldUseSavedConfiguration(first: first, allowManualTextOverwrite: allowManualTextOverwrite)
            populateManualFields(from: hosts.first, allowManualTextOverwrite: allowManualTextOverwrite)
            if case .ready(let registry) = state {
                isLoadingSavedConfiguration = false
                await upsert(
                    hosts,
                    into: registry,
                    stopDiscovery: false
                )
            } else if case .discovering = state, !isBackgrounded, shouldUseSaved {
                isLoadingSavedConfiguration = false
                await useHosts(hosts, stopDiscovery: true)
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

    private func shouldUseSavedConfiguration(
        first: DockRelayEndpoint,
        allowManualTextOverwrite: Bool
    ) -> Bool {
        let typedManualText = manualHostText.trimmingCharacters(in: .whitespacesAndNewlines)
        return allowManualTextOverwrite
            || typedManualText.isEmpty
            || typedManualText == first.host
    }

    private func populateManualFields(
        from host: DockHostConfiguration?,
        allowManualTextOverwrite: Bool
    ) {
        guard let endpoint = host?.endpoint else {
            return
        }
        let typedManualText = manualHostText.trimmingCharacters(in: .whitespacesAndNewlines)
        if allowManualTextOverwrite || typedManualText.isEmpty {
            manualHostText = endpoint.host
            manualPortText = String(endpoint.port)
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
        await useHost(DockHostConfiguration(endpoint: endpoint), stopDiscovery: true)
    }

    private func useHost(
        _ host: DockHostConfiguration,
        stopDiscovery: Bool
    ) async {
        await useHosts([host], stopDiscovery: stopDiscovery)
    }

    private func useHosts(
        _ hosts: [DockHostConfiguration],
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
            let persistence = LocalRelayHostList(hosts: hosts)
            try await configurationStore.save(persistence)
            DockLog.bootstrap.notice("relay configuration saved hosts=\(persistence.hosts.count, privacy: .public)")
        } catch {
            DockLog.bootstrap.error("relay configuration save failed error=\(DockLog.errorSummary(error), privacy: .public)")
            state = .failed("Relay was found, but the connection could not be saved.")
            return
        }

        do {
            state = .ready(try HostRegistry(hosts: hosts))
            DockLog.bootstrap.notice("relay bootstrap ready hosts=\(hosts.count, privacy: .public)")
            if stopDiscovery {
                stopDiscoveryIfNeeded()
            }
        } catch {
            DockLog.bootstrap.error("relay host registry failed error=\(DockLog.errorSummary(error), privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }

    private func upsert(
        _ incomingHosts: [DockHostConfiguration],
        into registry: HostRegistry,
        stopDiscovery: Bool = true
    ) async {
        var hosts = registry.hosts
        var didChange = false
        for candidate in incomingHosts {
            if let index = hosts.firstIndex(where: { $0.id == candidate.id }) {
                guard hosts[index] != candidate else {
                    continue
                }
                hosts[index] = candidate
                didChange = true
            } else {
                hosts.append(candidate)
                didChange = true
            }
        }

        guard didChange else {
            if stopDiscovery {
                stopDiscoveryIfNeeded()
            }
            return
        }
        guard let updatedRegistry = try? HostRegistry(hosts: hosts),
              updatedRegistry != registry
        else {
            if stopDiscovery {
                stopDiscoveryIfNeeded()
            }
            return
        }
        await useHosts(updatedRegistry.hosts, stopDiscovery: stopDiscovery)
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

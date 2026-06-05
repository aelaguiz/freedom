import Combine
import Foundation

public enum HostConnectivityPhase: Equatable, Sendable {
    case unknown
    case checking
    case online(String)
    case partial(String)
    case reconnecting(String)
    case backgrounded(String)
    case resuming(String)
    case stale(String)
    case offline(String)
    case error(String)
    case configurationError(String)

    public var isOnlineLike: Bool {
        switch self {
        case .online, .partial:
            return true
        case .unknown, .checking, .reconnecting, .stale, .offline, .error, .configurationError:
            return false
        case .backgrounded, .resuming:
            return false
        }
    }

    public var message: String {
        switch self {
        case .unknown:
            return "Waiting for first check"
        case .checking:
            return "Checking"
        case .online(let message),
             .partial(let message),
             .reconnecting(let message),
             .backgrounded(let message),
             .resuming(let message),
             .stale(let message),
             .offline(let message),
             .error(let message),
             .configurationError(let message):
            return message
        }
    }
}

public struct HostConnectivitySnapshot: Equatable, Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public let endpoint: String
    public let phase: HostConnectivityPhase
    public let lastCheckedAt: Date?
    public let lastSuccessAt: Date?
    public let routeDiagnostics: [RouteDiagnosticSnapshot]

    public init(
        id: String,
        displayName: String,
        endpoint: String,
        phase: HostConnectivityPhase,
        lastCheckedAt: Date? = nil,
        lastSuccessAt: Date? = nil,
        routeDiagnostics: [RouteDiagnosticSnapshot] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.endpoint = endpoint
        self.phase = phase
        self.lastCheckedAt = lastCheckedAt
        self.lastSuccessAt = lastSuccessAt
        self.routeDiagnostics = routeDiagnostics
    }
}

public enum AppConnectivityOverallStatus: Equatable, Sendable {
    // Connectivity says whether the relay path is reachable. Dock card
    // freshness is separate and comes from relay stream freshness/proof fields,
    // not from process reachability alone.
    case unconfigured(String)
    case checking(String)
    case online(String)
    case partial(String)
    case reconnecting(String)
    case backgrounded(String)
    case resuming(String)
    case stale(String)
    case offline(String)
    case error(String)
    case configurationError(String)

    public var label: String {
        switch self {
        case .unconfigured:
            return "Unconfigured"
        case .checking:
            return "Checking"
        case .online:
            return "Online"
        case .partial:
            return "Partial"
        case .reconnecting:
            return "Reconnecting"
        case .backgrounded:
            return "Backgrounded"
        case .resuming:
            return "Resuming"
        case .stale:
            return "Stale"
        case .offline:
            return "Offline"
        case .error:
            return "Error"
        case .configurationError:
            return "Config error"
        }
    }

    public var message: String {
        switch self {
        case .unconfigured(let message),
             .checking(let message),
             .online(let message),
             .partial(let message),
             .reconnecting(let message),
             .backgrounded(let message),
             .resuming(let message),
             .stale(let message),
             .offline(let message),
             .error(let message),
             .configurationError(let message):
            return message
        }
    }
}

@MainActor
public protocol AppConnectivityReporting: AnyObject {
    func reportDockState(_ state: DockStoreState)
    func reportArchiveState(_ state: ArchiveStoreState)
    func reportHostTest(host: DockHostConfiguration, status: HostConnectionTestStatus)
    func reportThreadDetail(host: DockHostConfiguration, liveState: ThreadDetailLiveState)
    func reportRouteDiagnostic(host: DockHostConfiguration, diagnostic: RouteDiagnosticSnapshot)
    func reportLifecycle(_ snapshot: AppLifecycleSnapshot)
}

@MainActor
public final class AppConnectivityStore: ObservableObject, AppConnectivityReporting {
    @Published public private(set) var hosts: [HostConnectivitySnapshot] = []
    @Published public private(set) var overallStatus: AppConnectivityOverallStatus

    private enum ObservationSource: Hashable {
        case dock
        case archive
        case hostTest
        case threadDetail
    }

    private struct Observation {
        var phase: HostConnectivityPhase
        var lastCheckedAt: Date?
        var lastSuccessAt: Date?
    }

    private struct HostRecord {
        var id: String
        var displayName: String
        var endpoint: String
        var observations: [ObservationSource: Observation]
        var routeDiagnostics: [String: RouteDiagnosticSnapshot]
        var lifecyclePhase: HostConnectivityPhase?
    }

    private let now: @Sendable () -> Date
    private var hostConfigurations: [String: DockHostConfiguration] = [:]
    private var hostOrder: [String] = []
    private var records: [String: HostRecord] = [:]
    private var bootstrapStatus: AppConnectivityOverallStatus?
    private var lastLoggedOverallStatus: AppConnectivityOverallStatus?
    private var lastLoggedHostPhases: [String: HostConnectivityPhase] = [:]

    public init(
        registry: HostRegistry? = nil,
        configurationError: Error? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.now = now
        if let configurationError {
            self.overallStatus = .configurationError(configurationError.localizedDescription)
        } else {
            self.overallStatus = .unconfigured("No relay host configured.")
        }
        if let registry {
            configure(registry)
        } else if let configurationError {
            recordConfigurationError(configurationError.localizedDescription)
        }
    }

    public init(
        hosts: [DockHostConfiguration],
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.now = now
        self.overallStatus = .unconfigured("No relay host configured.")
        configure(hosts: hosts)
    }

    public func configure(_ registry: HostRegistry) {
        configure(hosts: registry.hosts)
    }

    public func configure(hosts: [DockHostConfiguration]) {
        bootstrapStatus = nil
        DockLog.connectivity.notice("connectivity configured hosts=\(hosts.count, privacy: .public)")
        hostConfigurations = Dictionary(uniqueKeysWithValues: hosts.map { ($0.id, $0) })
        hostOrder = hosts.map(\.id)
        let existing = records
        records = Dictionary(
            uniqueKeysWithValues: hosts.map { host in
                let hostViewModel = DockHostViewModel(host: host)
                var record = existing[host.id] ?? HostRecord(
                    id: hostViewModel.id,
                    displayName: hostViewModel.displayName,
                    endpoint: hostViewModel.endpoint,
                    observations: [:],
                    routeDiagnostics: [:],
                    lifecyclePhase: nil
                )
                record.id = hostViewModel.id
                record.displayName = hostViewModel.displayName
                record.endpoint = hostViewModel.endpoint
                return (host.id, record)
            }
        )
        publish()
    }

    public func applyRuntimeSnapshot(_ snapshot: ConnectivityRenderSnapshot) {
        bootstrapStatus = nil
        hosts = snapshot.hosts
        overallStatus = snapshot.overallStatus
        logHostPhasesIfNeeded(snapshot.hosts)
        logOverallStatusIfNeeded(snapshot.overallStatus)
    }

    public func recordConfigurationError(_ message: String) {
        bootstrapStatus = nil
        hostConfigurations = [:]
        hostOrder = []
        records = [:]
        hosts = []
        overallStatus = .configurationError(message)
        logOverallStatusIfNeeded(overallStatus)
    }

    public func reportBootstrapState(_ state: RelayBootstrapState) {
        switch state {
        case .starting:
            bootstrapStatus = .checking("Finding Codex Dock relay")
        case .discovering(_, let message):
            let message = message ?? "Finding Codex Dock relay"
            if message == "Backgrounded" {
                bootstrapStatus = .backgrounded(message)
            } else {
                bootstrapStatus = .checking(message)
            }
        case .ready(let registry):
            bootstrapStatus = nil
            configure(registry)
            return
        case .failed(let message):
            bootstrapStatus = .error(message)
        }
        publishBootstrapStatusIfNeeded()
    }

    public func reportDockState(_ state: DockStoreState) {
        switch state {
        case .configurationError(let message):
            recordConfigurationError(message)
        case .idle(let hosts):
            for host in hosts {
                record(host: host, source: .dock, phase: .unknown, checked: false)
            }
        case .loading(let hosts):
            for host in hosts {
                record(host: host, source: .dock, phase: .checking)
            }
        case .offline(let host, let message):
            record(host: host, source: .dock, phase: .offline(message))
        case .error(let host, let message):
            record(host: host, source: .dock, phase: .error(message))
        case .loaded(let snapshot):
            record(hostStates: snapshot.hostStates, source: .dock)
        }
    }

    public func reportArchiveState(_ state: ArchiveStoreState) {
        switch state {
        case .configurationError(let message):
            recordConfigurationError(message)
        case .idle(let hosts):
            for host in hosts {
                record(host: host, source: .archive, phase: .unknown, checked: false)
            }
        case .loading(let hosts):
            for host in hosts {
                record(host: host, source: .archive, phase: .checking)
            }
        case .loaded(let snapshot), .empty(let snapshot), .unavailable(let snapshot, _):
            record(hostStates: snapshot.hostStates, source: .archive)
        }
    }

    public func reportHostTest(host: DockHostConfiguration, status: HostConnectionTestStatus) {
        let hostViewModel = DockHostViewModel(host: host)
        switch status {
        case .notChecked:
            record(host: hostViewModel, source: .hostTest, phase: .unknown, checked: false)
        case .testing:
            record(host: hostViewModel, source: .hostTest, phase: .checking)
        case .online(let rowCount, let checkedAt):
            record(
                host: hostViewModel,
                source: .hostTest,
                phase: .online("\(rowCount) sessions"),
                checkedAt: checkedAt,
                successAt: checkedAt
            )
        case .offline(let message, let checkedAt):
            record(host: hostViewModel, source: .hostTest, phase: .offline(message), checkedAt: checkedAt)
        case .error(let message, let checkedAt):
            record(host: hostViewModel, source: .hostTest, phase: .error(message), checkedAt: checkedAt)
        }
    }

    public func reportThreadDetail(host: DockHostConfiguration, liveState: ThreadDetailLiveState) {
        let hostViewModel = DockHostViewModel(host: host)
        switch liveState {
        case .connecting:
            record(host: hostViewModel, source: .threadDetail, phase: .checking)
        case .updating:
            record(host: hostViewModel, source: .threadDetail, phase: .checking)
        case .reconnecting(let message):
            record(host: hostViewModel, source: .threadDetail, phase: .reconnecting(message))
        case .live:
            record(host: hostViewModel, source: .threadDetail, phase: .online("Thread live"), successAt: now())
        case .stale(let message):
            record(host: hostViewModel, source: .threadDetail, phase: .stale(message))
        case .closed:
            record(host: hostViewModel, source: .threadDetail, phase: .online("Thread closed"), successAt: now())
        }
    }

    public func reportRouteDiagnostic(host: DockHostConfiguration, diagnostic: RouteDiagnosticSnapshot) {
        let hostViewModel = DockHostViewModel(host: host)
        var record = records[host.id] ?? HostRecord(
            id: hostViewModel.id,
            displayName: hostViewModel.displayName,
            endpoint: hostViewModel.endpoint,
            observations: [:],
            routeDiagnostics: [:],
            lifecyclePhase: nil
        )
        record.routeDiagnostics[diagnostic.route] = diagnostic
        records[host.id] = record
        if !hostOrder.contains(host.id) {
            hostOrder.append(host.id)
        }
        publish()
    }

    public func refreshRelayDiagnostics(
        client: RelayDiagnosticsClient = RelayDiagnosticsClient(),
        store: ClientObservabilityStore = .shared
    ) async {
        for host in hostConfigurations.values {
            do {
                let routes = try await client.fetchRoutes(for: host.endpoint)
                await store.attachRelayDiagnostics(configuredHostID: host.id, relayRoutes: routes)
                for route in routes {
                    reportRouteDiagnostic(host: host, diagnostic: route)
                }
            } catch {
                let diagnostic = RouteDiagnosticSnapshot(
                    configuredHostID: host.id,
                    route: "routesz",
                    routeStatus: .failed,
                    statusReasons: [
                        RouteStatusReason(
                            code: "failed:diagnostics-fetch",
                            message: error.localizedDescription,
                            actual: ObservabilityFailureCategory.downstream.rawValue,
                            evidenceIDs: []
                        )
                    ],
                    lastAttemptAt: now(),
                    lastFailureAt: now(),
                    appCritical: false,
                    appImpact: "diagnostic-fetch"
                )
                reportRouteDiagnostic(host: host, diagnostic: diagnostic)
            }
        }
    }

    public func reportLifecycle(_ snapshot: AppLifecycleSnapshot) {
        switch snapshot.phase {
        case .backgrounded:
            markAllHosts(.backgrounded("Backgrounded"))
        case .foregroundResuming:
            markAllHosts(.resuming("Resuming"))
        case .active:
            clearLifecyclePhase()
        case .inactive:
            return
        }
    }

    private func record(hostStates: [DockHostStateViewModel], source: ObservationSource) {
        for hostState in hostStates {
            let phase: HostConnectivityPhase
            switch hostState.status {
            case .checking:
                phase = .checking
            case .loaded(let rowCount, _):
                phase = .online("\(rowCount) sessions")
            case .degraded(_, let message):
                phase = .partial(message)
            case .empty:
                phase = .online("Online, no sessions")
            case .offline(let message):
                phase = .offline(message)
            case .error(let message):
                phase = .error(message)
            }
            record(host: hostState.host, source: source, phase: phase)
        }
    }

    private func markAllHosts(_ phase: HostConnectivityPhase) {
        guard !records.isEmpty else {
            overallStatus = rollup([])
            return
        }
        for id in Array(records.keys) {
            records[id]?.lifecyclePhase = phase
        }
        publish()
    }

    private func clearLifecyclePhase() {
        guard !records.isEmpty else {
            publishBootstrapStatusIfNeeded()
            return
        }
        for id in Array(records.keys) {
            records[id]?.lifecyclePhase = nil
        }
        publish()
    }

    private func record(
        host: DockHostViewModel,
        source: ObservationSource,
        phase: HostConnectivityPhase,
        checked: Bool = true,
        checkedAt: Date? = nil,
        successAt: Date? = nil
    ) {
        bootstrapStatus = nil
        let timestamp = checkedAt ?? (checked ? now() : nil)
        var record = records[host.id] ?? HostRecord(
            id: host.id,
            displayName: host.displayName,
            endpoint: host.endpoint,
            observations: [:],
            routeDiagnostics: [:],
            lifecyclePhase: nil
        )
        if !hostOrder.contains(host.id) {
            hostOrder.append(host.id)
        }
        let existingObservation = record.observations[source]
        let lastSuccessAt: Date?
        if let successAt {
            lastSuccessAt = successAt
        } else if phase.isOnlineLike {
            lastSuccessAt = timestamp ?? now()
        } else {
            lastSuccessAt = existingObservation?.lastSuccessAt
        }

        record.observations[source] = Observation(
            phase: phase,
            lastCheckedAt: timestamp ?? existingObservation?.lastCheckedAt,
            lastSuccessAt: lastSuccessAt
        )
        records[host.id] = record
        publish()
    }

    private func publishBootstrapStatusIfNeeded() {
        guard records.isEmpty else {
            publish()
            return
        }
        hosts = []
        overallStatus = bootstrapStatus ?? .unconfigured("No relay host configured.")
        logOverallStatusIfNeeded(overallStatus)
    }

    private func publish() {
        let nextHosts = records.values
            .map(snapshot(from:))
            .sorted { lhs, rhs in
                let leftIndex = hostIndex(lhs.id)
                let rightIndex = hostIndex(rhs.id)
                if leftIndex == rightIndex {
                    return lhs.displayName < rhs.displayName
                }
                return leftIndex < rightIndex
            }
        let nextOverallStatus = rollup(nextHosts)
        hosts = nextHosts
        overallStatus = nextOverallStatus
        logHostPhasesIfNeeded(nextHosts)
        logOverallStatusIfNeeded(nextOverallStatus)
    }

    private func snapshot(from record: HostRecord) -> HostConnectivitySnapshot {
        let observations = Array(record.observations.values)
        let routeDiagnostics = record.routeDiagnostics.values.sorted { $0.route < $1.route }
        let routePhase = phaseForRouteDiagnostics(routeDiagnostics)
        let observationPhase = rollupObservations(observations)
        return HostConnectivitySnapshot(
            id: record.id,
            displayName: record.displayName,
            endpoint: record.endpoint,
            phase: record.lifecyclePhase ?? routePhase ?? observationPhase,
            lastCheckedAt: latestDate(observations.compactMap(\.lastCheckedAt)),
            lastSuccessAt: latestDate(observations.compactMap(\.lastSuccessAt)),
            routeDiagnostics: routeDiagnostics
        )
    }

    private func phaseForRouteDiagnostics(_ diagnostics: [RouteDiagnosticSnapshot]) -> HostConnectivityPhase? {
        guard let failed = diagnostics.first(where: { $0.appCritical && $0.routeStatus == .failed }) else {
            return nil
        }
        return .partial("\(failed.route) failed")
    }

    private func rollupObservations(_ observations: [Observation]) -> HostConnectivityPhase {
        guard let strongest = observations.min(by: {
            priority(for: $0.phase) < priority(for: $1.phase)
        }) else {
            return .unknown
        }
        return strongest.phase
    }

    private func rollup(_ hosts: [HostConnectivitySnapshot]) -> AppConnectivityOverallStatus {
        guard !hosts.isEmpty else {
            return bootstrapStatus ?? .unconfigured("No relay host configured.")
        }

        if let status = firstStatus(hosts, matching: {
            if case .configurationError = $0.phase { return true }
            return false
        }) {
            return .configurationError(status.phase.message)
        }
        if let status = firstStatus(hosts, matching: {
            if case .backgrounded = $0.phase { return true }
            return false
        }) {
            return .backgrounded("\(status.displayName): \(status.phase.message)")
        }
        if let status = firstStatus(hosts, matching: {
            if case .resuming = $0.phase { return true }
            return false
        }) {
            return .resuming("\(status.displayName): \(status.phase.message)")
        }
        if let status = firstStatus(hosts, matching: {
            if case .reconnecting = $0.phase { return true }
            return false
        }) {
            return .reconnecting("\(status.displayName): \(status.phase.message)")
        }
        if let status = firstStatus(hosts, matching: {
            if case .stale = $0.phase { return true }
            return false
        }) {
            return .stale("\(status.displayName): \(status.phase.message)")
        }
        let onlineLikeCount = hosts.filter { $0.phase.isOnlineLike }.count
        let checkingCount = hosts.filter { status in
            if case .checking = status.phase {
                return true
            }
            return false
        }.count
        if checkingCount == hosts.count {
            return .checking(hosts.count == 1 ? hosts[0].phase.message : "Checking \(hosts.count) hosts")
        }
        if onlineLikeCount > 0, checkingCount > 0 {
            return .partial("Online \(onlineLikeCount)/\(hosts.count), checking \(checkingCount)")
        }
        if onlineLikeCount == hosts.count {
            if let partial = firstStatus(hosts, matching: {
                if case .partial = $0.phase { return true }
                return false
            }) {
                return .partial("\(partial.displayName): \(partial.phase.message)")
            }
            return .online(hosts.count == 1 ? hosts[0].phase.message : "\(hosts.count) hosts online")
        }
        if onlineLikeCount > 0 {
            let failing = hosts.first { !$0.phase.isOnlineLike } ?? hosts[0]
            return .partial("\(failing.displayName): \(failing.phase.message)")
        }

        if let error = firstStatus(hosts, matching: {
            if case .error = $0.phase { return true }
            return false
        }) {
            return .error("\(error.displayName): \(error.phase.message)")
        }
        if let offline = firstStatus(hosts, matching: {
            if case .offline = $0.phase { return true }
            return false
        }) {
            return .offline("\(offline.displayName): \(offline.phase.message)")
        }

        return .checking("Waiting for first check")
    }

    private func priority(for phase: HostConnectivityPhase) -> Int {
        switch phase {
        case .configurationError:
            return 0
        case .backgrounded:
            return 1
        case .resuming:
            return 2
        case .reconnecting:
            return 3
        case .stale:
            return 4
        case .checking:
            return 5
        case .offline:
            return 6
        case .error:
            return 7
        case .partial:
            return 8
        case .online:
            return 9
        case .unknown:
            return 10
        }
    }

    private func firstStatus(
        _ hosts: [HostConnectivitySnapshot],
        matching predicate: (HostConnectivitySnapshot) -> Bool
    ) -> HostConnectivitySnapshot? {
        hosts.first(where: predicate)
    }

    private func latestDate(_ dates: [Date]) -> Date? {
        dates.max()
    }

    private func hostIndex(_ hostID: String) -> Int {
        hostOrder.firstIndex(of: hostID) ?? Int.max
    }

    private func logHostPhasesIfNeeded(_ hosts: [HostConnectivitySnapshot]) {
        for host in hosts {
            guard lastLoggedHostPhases[host.id] != host.phase else {
                continue
            }
            lastLoggedHostPhases[host.id] = host.phase
            DockLog.connectivity.info("connectivity host phase host_id=\(host.id, privacy: .public) endpoint=\(host.endpoint, privacy: .public) phase=\(host.phase.logDescription, privacy: .public) message=\(DockLog.redacted(host.phase.message), privacy: .public)")
        }
    }

    private func logOverallStatusIfNeeded(_ status: AppConnectivityOverallStatus) {
        guard lastLoggedOverallStatus != status else {
            return
        }
        lastLoggedOverallStatus = status
        DockLog.connectivity.notice("connectivity overall status=\(status.label, privacy: .public) message=\(DockLog.redacted(status.message), privacy: .public)")
    }
}

private extension HostConnectivityPhase {
    var logDescription: String {
        switch self {
        case .unknown:
            return "unknown"
        case .checking:
            return "checking"
        case .online:
            return "online"
        case .partial:
            return "partial"
        case .reconnecting:
            return "reconnecting"
        case .backgrounded:
            return "backgrounded"
        case .resuming:
            return "resuming"
        case .stale:
            return "stale"
        case .offline:
            return "offline"
        case .error:
            return "error"
        case .configurationError:
            return "configurationError"
        }
    }
}

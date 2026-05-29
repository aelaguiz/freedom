import Combine
import Foundation

public enum HostConnectionTestStatus: Equatable, Sendable {
    case notChecked
    case testing
    case online(rowCount: Int, checkedAt: Date)
    case offline(String, checkedAt: Date)
    case error(String, checkedAt: Date)

    public var title: String {
        switch self {
        case .notChecked:
            return "Not checked"
        case .testing:
            return "Testing"
        case .online:
            return "Online"
        case .offline:
            return "Offline"
        case .error:
            return "Error"
        }
    }

    public var detail: String {
        switch self {
        case .notChecked:
            return "No test run"
        case .testing:
            return "Checking app-server"
        case .online(let rowCount, let checkedAt):
            return "\(rowCount) sessions · \(Self.lastCheckText(checkedAt))"
        case .offline(let message, let checkedAt), .error(let message, let checkedAt):
            return "\(message) · \(Self.lastCheckText(checkedAt))"
        }
    }

    private static func lastCheckText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return "last checked \(formatter.string(from: date))"
    }
}

public struct HostSettingsRowViewModel: Equatable, Identifiable, Sendable {
    public let id: String
    public let host: DockHostConfiguration
    public let displayHost: DockHostViewModel
    public let status: HostConnectionTestStatus

    public init(host: DockHostConfiguration, status: HostConnectionTestStatus) {
        self.id = host.id
        self.host = host
        self.displayHost = DockHostViewModel(host: host)
        self.status = status
    }
}

public enum HostSettingsError: Error, Equatable, LocalizedError, Sendable {
    case invalidEndpoint(String)
    case duplicateID(String)
    case missingRegistry

    public var errorDescription: String? {
        switch self {
        case let .invalidEndpoint(value):
            return "Relay endpoint must be a host and port: \(value)"
        case let .duplicateID(id):
            return "Relay endpoint already exists: \(id)"
        case .missingRegistry:
            return "Host registry is not available."
        }
    }
}

@MainActor
public final class HostSettingsStore: ObservableObject {
    @Published public private(set) var registry: HostRegistry?
    @Published public private(set) var configurationError: String?
    @Published private var statuses: [String: HostConnectionTestStatus] = [:]

    private let tester: any DockSessionLoading
    private let configurationStore: any LocalDockConfigurationStoring
    private let now: @Sendable () -> Date
    private weak var connectivityReporter: (any AppConnectivityReporting)?

    public var rows: [HostSettingsRowViewModel] {
        registry?.hosts.map { host in
            HostSettingsRowViewModel(
                host: host,
                status: statuses[host.id] ?? .notChecked
            )
        } ?? []
    }

    public init(
        registry: HostRegistry,
        tester: any DockSessionLoading = AppServerDockClient(),
        configurationStore: any LocalDockConfigurationStoring = FileLocalDockConfigurationStore(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.registry = registry
        self.tester = tester
        self.configurationStore = configurationStore
        self.now = now
    }

    public init(
        configurationError error: Error,
        tester: any DockSessionLoading = AppServerDockClient(),
        configurationStore: any LocalDockConfigurationStoring = FileLocalDockConfigurationStore(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.registry = nil
        self.configurationError = error.localizedDescription
        self.tester = tester
        self.configurationStore = configurationStore
        self.now = now
    }

    public func testAll() async {
        for host in registry?.hosts ?? [] {
            await test(host.id)
        }
    }

    public func setConnectivityReporter(_ reporter: (any AppConnectivityReporting)?) {
        connectivityReporter = reporter
        for row in rows {
            reporter?.reportHostTest(host: row.host, status: row.status)
        }
    }

    public func test(_ hostID: String) async {
        guard let host = registry?.hosts.first(where: { $0.id == hostID }) else {
            DockLog.hostConfiguration.warning("host test skipped missing host_id=\(hostID, privacy: .public)")
            return
        }

        let startedAt = Date()
        let signpostState = DockSignpost.hostConfiguration.beginInterval("host.test")
        DockLog.hostConfiguration.notice("host test started host_id=\(host.id, privacy: .public) endpoint=\(DockLog.endpoint(host.webSocketURL), privacy: .public)")
        statuses[hostID] = .testing
        connectivityReporter?.reportHostTest(host: host, status: .testing)
        defer {
            DockSignpost.hostConfiguration.endInterval("host.test", signpostState)
        }

        do {
            let result = try await tester.loadSessions(for: host, query: .activeHuman)
            let status = HostConnectionTestStatus.online(rowCount: result.summaries.count, checkedAt: now())
            statuses[hostID] = status
            connectivityReporter?.reportHostTest(host: host, status: status)
            DockLog.hostConfiguration.notice("host test finished host_id=\(host.id, privacy: .public) rows=\(result.summaries.count, privacy: .public) duration_ms=\(DockLog.milliseconds(since: startedAt), privacy: .public)")
        } catch let failure as DockLoadFailure {
            let status: HostConnectionTestStatus
            switch failure {
            case .offline(let message):
                status = .offline(message, checkedAt: now())
            case .error(let message):
                status = .error(message, checkedAt: now())
            }
            statuses[hostID] = status
            connectivityReporter?.reportHostTest(host: host, status: status)
            DockLog.hostConfiguration.warning("host test failed host_id=\(host.id, privacy: .public) duration_ms=\(DockLog.milliseconds(since: startedAt), privacy: .public) error=\(DockLog.errorSummary(failure), privacy: .public)")
        } catch {
            let status = HostConnectionTestStatus.error(error.localizedDescription, checkedAt: now())
            statuses[hostID] = status
            connectivityReporter?.reportHostTest(host: host, status: status)
            DockLog.hostConfiguration.error("host test failed host_id=\(host.id, privacy: .public) duration_ms=\(DockLog.milliseconds(since: startedAt), privacy: .public) error=\(DockLog.errorSummary(error), privacy: .public)")
        }
    }

    public func saveHost(
        replacing originalID: String?,
        host rawHost: String,
        port rawPort: String
    ) async throws {
        if registry == nil, originalID != nil {
            DockLog.hostConfiguration.error("host save failed reason=missing_registry")
            throw HostSettingsError.missingRegistry
        }

        let rawHost = normalized(rawHost)
        let rawPort = normalized(rawPort)
        let endpoint: DockRelayEndpoint
        do {
            guard let port = Int(rawPort) else {
                throw DockHostConfigurationError.invalidPort(rawPort)
            }
            endpoint = try DockRelayEndpoint(host: rawHost, port: port)
        } catch {
            DockLog.hostConfiguration.warning("host save validation failed reason=invalid_endpoint")
            throw HostSettingsError.invalidEndpoint("\(rawHost):\(rawPort)")
        }

        let currentHosts = registry?.hosts ?? []
        let existingIDs = Set(currentHosts.map(\.id))
        if endpoint.id != originalID, existingIDs.contains(endpoint.id) {
            DockLog.hostConfiguration.warning("host save validation failed endpoint=\(endpoint.id, privacy: .public) reason=duplicate")
            throw HostSettingsError.duplicateID(endpoint.id)
        }

        let host = DockHostConfiguration(endpoint: endpoint)

        DockLog.hostConfiguration.notice("host save started endpoint=\(endpoint.id, privacy: .public) replacing=\(DockLog.publicID(originalID), privacy: .public)")

        let newRegistry: HostRegistry
        if let originalID,
           let index = currentHosts.firstIndex(where: { $0.id == originalID }) {
            newRegistry = try HostRegistry(
                hosts: currentHosts.enumerated().map { offset, existing in
                    offset == index ? host : existing
                }
            )
            if originalID != endpoint.id {
                statuses.removeValue(forKey: originalID)
            }
            statuses[endpoint.id] = .notChecked
        } else {
            newRegistry = try HostRegistry(hosts: currentHosts + [host])
            statuses[endpoint.id] = .notChecked
        }
        try await persist(newRegistry)
        self.registry = newRegistry
        configurationError = nil
        DockLog.hostConfiguration.notice("host save finished endpoint=\(endpoint.id, privacy: .public) hosts=\(newRegistry.hosts.count, privacy: .public)")
    }

    public func removeHost(_ hostID: String) async throws {
        guard let registry else {
            DockLog.hostConfiguration.error("host remove failed reason=missing_registry")
            throw HostSettingsError.missingRegistry
        }
        let hosts = registry.hosts.filter { $0.id != hostID }
        if hosts.isEmpty {
            try await configurationStore.save(LocalRelayEndpointList(endpoints: []))
            statuses.removeValue(forKey: hostID)
            self.registry = nil
            configurationError = nil
            DockLog.hostConfiguration.notice("host remove finished endpoint=\(hostID, privacy: .public) hosts=0")
            return
        }
        let newRegistry = try HostRegistry(hosts: hosts)
        try await persist(newRegistry)
        statuses.removeValue(forKey: hostID)
        self.registry = newRegistry
        configurationError = nil
        DockLog.hostConfiguration.notice("host remove finished endpoint=\(hostID, privacy: .public) hosts=\(newRegistry.hosts.count, privacy: .public)")
    }

    private func persist(_ registry: HostRegistry) async throws {
        try await configurationStore.save(LocalRelayEndpointList(endpoints: registry.hosts.map(\.endpoint)))
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

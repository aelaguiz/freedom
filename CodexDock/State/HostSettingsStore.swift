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
    case emptyID
    case emptyName
    case invalidEndpoint(String)
    case duplicateID(String)
    case missingRegistry

    public var errorDescription: String? {
        switch self {
        case .emptyID:
            return "Host ID is required."
        case .emptyName:
            return "Host name is required."
        case let .invalidEndpoint(value):
            return "Host WebSocket URL must be ws:// or wss://: \(value)"
        case let .duplicateID(id):
            return "Host ID already exists: \(id)"
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

    public func test(_ hostID: String) async {
        guard let host = registry?.hosts.first(where: { $0.id == hostID }) else {
            return
        }

        statuses[hostID] = .testing

        do {
            let result = try await tester.loadSessions(for: host, archived: false)
            statuses[hostID] = .online(rowCount: result.summaries.count, checkedAt: now())
        } catch let failure as DockLoadFailure {
            switch failure {
            case .offline(let message):
                statuses[hostID] = .offline(message, checkedAt: now())
            case .error(let message):
                statuses[hostID] = .error(message, checkedAt: now())
            }
        } catch {
            statuses[hostID] = .error(error.localizedDescription, checkedAt: now())
        }
    }

    public func saveHost(
        replacing originalID: String?,
        id rawID: String,
        displayName rawDisplayName: String,
        webSocketURL rawWebSocketURL: String
    ) async throws {
        guard var registry else {
            throw HostSettingsError.missingRegistry
        }

        let id = normalized(rawID)
        let displayName = normalized(rawDisplayName)
        let rawWebSocketURL = normalized(rawWebSocketURL)

        guard !id.isEmpty else {
            throw HostSettingsError.emptyID
        }
        guard !displayName.isEmpty else {
            throw HostSettingsError.emptyName
        }
        let webSocketURL: URL
        do {
            webSocketURL = try DockHostConfiguration.validatedWebSocketURL(rawWebSocketURL)
        } catch {
            throw HostSettingsError.invalidEndpoint(rawWebSocketURL)
        }

        let existingIDs = Set(registry.hosts.map(\.id))
        if id != originalID, existingIDs.contains(id) {
            throw HostSettingsError.duplicateID(id)
        }

        let host = DockHostConfiguration(
            id: id,
            displayName: displayName,
            webSocketURL: webSocketURL,
            bearerToken: nil
        )

        try await configurationStore.save(
            LocalRelayConfiguration(
                displayName: displayName,
                webSocketURL: webSocketURL
            )
        )

        if let originalID,
           let index = registry.hosts.firstIndex(where: { $0.id == originalID }) {
            registry = try HostRegistry(
                hosts: registry.hosts.enumerated().map { offset, existing in
                    offset == index ? host : existing
                }
            )
            if originalID != id {
                statuses.removeValue(forKey: originalID)
            }
            statuses[id] = .notChecked
        } else {
            registry = try HostRegistry(hosts: registry.hosts + [host])
            statuses[id] = .notChecked
        }
        self.registry = registry
        configurationError = nil
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

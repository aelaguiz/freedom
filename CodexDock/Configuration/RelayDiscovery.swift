import Combine
import Foundation

public let codexDockBonjourServiceType = "_codexdock._tcp."
public let codexDockBonjourDomain = "local."

public struct DiscoveredRelay: Equatable, Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public let endpoint: DockRelayEndpoint
    public let relayInstanceID: String?
    public let txtRecords: [String: String]

    public var hostName: String { endpoint.host }
    public var port: Int { endpoint.port }

    public init?(
        displayName: String,
        hostName: String,
        port: Int,
        txtRecords: [String: String] = [:]
    ) {
        let normalizedHostName = Self.normalizedHostName(hostName)
        guard let endpoint = try? DockRelayEndpoint(host: normalizedHostName, port: port) else {
            return nil
        }

        let relayInstanceID = Self.normalizedRelayInstanceID(
            txtRecords["relay-id"] ?? txtRecords["relay_id"] ?? txtRecords["relayInstanceID"]
        )

        self.id = endpoint.id
        self.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.endpoint = endpoint
        self.relayInstanceID = relayInstanceID
        self.txtRecords = txtRecords
    }

    public var hostConfiguration: DockHostConfiguration {
        DockHostConfiguration(endpoint: endpoint)
    }

    private static func normalizedHostName(_ value: String) -> String {
        var host = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while host.hasSuffix(".") {
            host.removeLast()
        }
        return host
    }

    private static func normalizedRelayInstanceID(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

public struct PersistedRelayHost: Codable, Equatable, Sendable {
    public let host: String
    public let port: Int

    private enum CodingKeys: String, CodingKey {
        case host
        case port
    }

    public init(endpoint: DockRelayEndpoint) {
        self.host = endpoint.host
        self.port = endpoint.port
    }

    public init(from decoder: Decoder) throws {
        let allKeys = try decoder.container(keyedBy: AnyCodingKey.self)
        try Self.rejectUnexpectedKeys(
            Set(allKeys.allKeys.map(\.stringValue)),
            allowed: Set([CodingKeys.host.rawValue, CodingKeys.port.rawValue]),
            in: decoder
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.host = try container.decode(String.self, forKey: .host)
        self.port = try container.decode(Int.self, forKey: .port)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(host, forKey: .host)
        try container.encode(port, forKey: .port)
    }

    public var endpoint: DockRelayEndpoint {
        get throws {
            try DockRelayEndpoint(host: host, port: port)
        }
    }

    private static func rejectUnexpectedKeys(
        _ keys: Set<String>,
        allowed: Set<String>,
        in decoder: Decoder
    ) throws {
        guard let unexpected = keys.subtracting(allowed).sorted().first else {
            return
        }
        let context = DecodingError.Context(
            codingPath: decoder.codingPath,
            debugDescription: "Unexpected relay host key: \(unexpected)"
        )
        throw DecodingError.dataCorrupted(context)
    }
}

public struct LocalRelayHostList: Codable, Equatable, Sendable {
    public let hosts: [PersistedRelayHost]

    private enum CodingKeys: String, CodingKey {
        case hosts
    }

    public init(hosts: [DockHostConfiguration]) {
        self.hosts = hosts.map { PersistedRelayHost(endpoint: $0.endpoint) }
    }

    public init(from decoder: Decoder) throws {
        let allKeys = try decoder.container(keyedBy: AnyCodingKey.self)
        try Self.rejectUnexpectedKeys(
            Set(allKeys.allKeys.map(\.stringValue)),
            allowed: Set([CodingKeys.hosts.rawValue]),
            in: decoder
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.hosts = try container.decode([PersistedRelayHost].self, forKey: .hosts)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hosts, forKey: .hosts)
    }

    public var hostConfigurations: [DockHostConfiguration] {
        get throws {
            try hosts.map {
                let endpoint = try $0.endpoint
                try endpoint.validateAppFacingRelayEndpoint()
                return DockHostConfiguration(endpoint: endpoint)
            }
        }
    }

    public func validatePersistedConfiguration() throws {
        guard !hosts.isEmpty else {
            return
        }
        let configurations = try hostConfigurations
        var seenHostIDs: Set<String> = []
        for configuration in configurations {
            guard seenHostIDs.insert(configuration.id).inserted else {
                throw DockHostConfigurationError.duplicateHostID(configuration.id)
            }
        }
    }

    private static func rejectUnexpectedKeys(
        _ keys: Set<String>,
        allowed: Set<String>,
        in decoder: Decoder
    ) throws {
        guard let unexpected = keys.subtracting(allowed).sorted().first else {
            return
        }
        let context = DecodingError.Context(
            codingPath: decoder.codingPath,
            debugDescription: "Unexpected relay host-list key: \(unexpected)"
        )
        throw DecodingError.dataCorrupted(context)
    }
}

private struct AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

public protocol LocalDockConfigurationStoring: Sendable {
    func load() async throws -> LocalRelayHostList?
    func save(_ configuration: LocalRelayHostList) async throws
}

public actor FileLocalDockConfigurationStore: LocalDockConfigurationStoring {
    private let fileURL: URL
    private var cache: LocalRelayHostList?

    public init(fileURL: URL = FileLocalDockConfigurationStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    public func load() async throws -> LocalRelayHostList? {
        if let cache {
            return cache
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: fileURL)
        let configuration = try JSONDecoder().decode(LocalRelayHostList.self, from: data)
        try configuration.validatePersistedConfiguration()
        cache = configuration
        return configuration
    }

    public func save(_ configuration: LocalRelayHostList) async throws {
        try configuration.validatePersistedConfiguration()
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(configuration)
        try data.write(to: fileURL, options: [.atomic])
        cache = configuration
    }

    public static func defaultFileURL() -> URL {
        let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return directory
            .appendingPathComponent("CodexDock", isDirectory: true)
            .appendingPathComponent("relay-config.json")
    }
}

public protocol RelayDiscoveryManaging: AnyObject {
    var relays: [DiscoveredRelay] { get }
    var onRelaysChanged: (@Sendable ([DiscoveredRelay]) -> Void)? { get set }

    func start()
    func stop()
}

public final class BonjourRelayDiscovery: NSObject, ObservableObject, RelayDiscoveryManaging {
    @Published public private(set) var relays: [DiscoveredRelay] = []
    public var onRelaysChanged: (@Sendable ([DiscoveredRelay]) -> Void)?

    private let browser = NetServiceBrowser()
    private var services: [NetService] = []
    private var isSearching = false

    public override init() {
        super.init()
        browser.delegate = self
    }

    public func start() {
        guard !isSearching else {
            DockLog.relayDiscovery.debug("bonjour discovery start skipped reason=already_searching")
            return
        }
        isSearching = true
        DockLog.relayDiscovery.notice("bonjour discovery started type=\(codexDockBonjourServiceType, privacy: .public) domain=\(codexDockBonjourDomain, privacy: .public)")
        browser.searchForServices(
            ofType: codexDockBonjourServiceType,
            inDomain: codexDockBonjourDomain
        )
    }

    public func stop() {
        guard isSearching else {
            return
        }
        isSearching = false
        DockLog.relayDiscovery.notice("bonjour discovery stopped service_count=\(self.services.count, privacy: .public) relay_count=\(self.relays.count, privacy: .public)")
        browser.stop()
        for service in services {
            service.stop()
        }
        services.removeAll()
    }

    private func add(_ service: NetService) {
        services.append(service)
        service.delegate = self
        DockLog.relayDiscovery.info("bonjour service found name=\(service.name, privacy: .public) service_count=\(self.services.count, privacy: .public)")
        service.resolve(withTimeout: 4)
    }

    private func remove(_ service: NetService) {
        services.removeAll { $0 === service }
        let name = service.name
        relays.removeAll { $0.displayName == name }
        DockLog.relayDiscovery.info("bonjour service removed name=\(name, privacy: .public) relay_count=\(self.relays.count, privacy: .public)")
        onRelaysChanged?(relays)
    }

    private func resolved(_ service: NetService) {
        guard let hostName = service.hostName,
              let relay = DiscoveredRelay(
                displayName: service.name,
                hostName: hostName,
                port: service.port,
                txtRecords: Self.txtRecords(from: service.txtRecordData())
              )
        else {
            DockLog.relayDiscovery.warning("bonjour service resolve ignored name=\(service.name, privacy: .public) reason=invalid_endpoint")
            return
        }

        relays.removeAll { $0.id == relay.id }
        relays.append(relay)
        relays.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        DockLog.relayDiscovery.notice("bonjour service resolved relay_id=\(relay.id, privacy: .public) name=\(relay.displayName, privacy: .public) endpoint=\(DockLog.endpoint(relay.endpoint.webSocketURL), privacy: .public) relay_count=\(self.relays.count, privacy: .public)")
        onRelaysChanged?(relays)
    }

    private static func txtRecords(from data: Data?) -> [String: String] {
        guard let data else {
            return [:]
        }
        return NetService.dictionary(fromTXTRecord: data).reduce(into: [:]) { result, entry in
            result[entry.key] = String(data: entry.value, encoding: .utf8)
        }
    }
}

extension BonjourRelayDiscovery: NetServiceBrowserDelegate {
    public nonisolated func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didFind service: NetService,
        moreComing: Bool
    ) {
        add(service)
    }

    public nonisolated func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didRemove service: NetService,
        moreComing: Bool
    ) {
        remove(service)
    }
}

extension BonjourRelayDiscovery: NetServiceDelegate {
    public nonisolated func netServiceDidResolveAddress(_ sender: NetService) {
        resolved(sender)
    }

    public nonisolated func netService(
        _ sender: NetService,
        didNotResolve errorDict: [String: NSNumber]
    ) {
        DockLog.relayDiscovery.warning("bonjour service resolve failed name=\(sender.name, privacy: .public) errors=\(errorDict.count, privacy: .public)")
    }
}

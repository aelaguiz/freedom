import Combine
import Foundation

public let codexDockBonjourServiceType = "_codexdock._tcp."
public let codexDockBonjourDomain = "local."

public struct DiscoveredRelay: Equatable, Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public let hostName: String
    public let port: Int
    public let txtRecords: [String: String]
    public let webSocketURL: URL

    public init?(
        displayName: String,
        hostName: String,
        port: Int,
        txtRecords: [String: String] = [:]
    ) {
        let normalizedHostName = Self.normalizedHostName(hostName)
        guard port > 0,
              let url = URL(string: "ws://\(normalizedHostName):\(port)"),
              url.host?.isEmpty == false
        else {
            return nil
        }

        self.id = "\(normalizedHostName):\(port)"
        self.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.hostName = normalizedHostName
        self.port = port
        self.txtRecords = txtRecords
        self.webSocketURL = url
    }

    public var hostConfiguration: DockHostConfiguration {
        DockHostConfiguration(
            id: hostName,
            displayName: displayName.isEmpty ? hostName : displayName,
            webSocketURL: webSocketURL,
            bearerToken: nil
        )
    }

    private static func normalizedHostName(_ value: String) -> String {
        var host = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while host.hasSuffix(".") {
            host.removeLast()
        }
        return host
    }
}

public struct LocalRelayConfiguration: Codable, Equatable, Sendable {
    public let displayName: String
    public let webSocketURL: URL

    public init(displayName: String, webSocketURL: URL) {
        self.displayName = displayName
        self.webSocketURL = webSocketURL
    }

    public var hostConfiguration: DockHostConfiguration {
        DockHostConfiguration(
            id: webSocketURL.host ?? "codex-dock-relay",
            displayName: displayName,
            webSocketURL: webSocketURL,
            bearerToken: nil
        )
    }
}

public protocol LocalDockConfigurationStoring: Sendable {
    func load() async throws -> LocalRelayConfiguration?
    func save(_ configuration: LocalRelayConfiguration) async throws
}

public actor FileLocalDockConfigurationStore: LocalDockConfigurationStoring {
    private let fileURL: URL
    private var cache: LocalRelayConfiguration?

    public init(fileURL: URL = FileLocalDockConfigurationStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    public func load() async throws -> LocalRelayConfiguration? {
        if let cache {
            return cache
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: fileURL)
        let configuration = try JSONDecoder().decode(LocalRelayConfiguration.self, from: data)
        cache = configuration
        return configuration
    }

    public func save(_ configuration: LocalRelayConfiguration) async throws {
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

    public override init() {
        super.init()
        browser.delegate = self
    }

    public func start() {
        browser.searchForServices(
            ofType: codexDockBonjourServiceType,
            inDomain: codexDockBonjourDomain
        )
    }

    public func stop() {
        browser.stop()
        for service in services {
            service.stop()
        }
        services.removeAll()
    }

    private func add(_ service: NetService) {
        services.append(service)
        service.delegate = self
        service.resolve(withTimeout: 4)
    }

    private func remove(_ service: NetService) {
        services.removeAll { $0 === service }
        let name = service.name
        relays.removeAll { $0.displayName == name }
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
            return
        }

        relays.removeAll { $0.id == relay.id }
        relays.append(relay)
        relays.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
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
}

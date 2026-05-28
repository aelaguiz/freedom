import Foundation

public enum AppServerMethods {
    public static let initialize = "initialize"
    public static let initialized = "initialized"
}

public struct ClientInfo: Codable, Equatable, Sendable {
    public let name: String
    public let title: String?
    public let version: String

    public init(name: String, title: String? = nil, version: String) {
        self.name = name
        self.title = title
        self.version = version
    }
}

public struct InitializeCapabilities: Codable, Equatable, Sendable {
    public let experimentalApi: Bool
    public let requestAttestation: Bool
    public let optOutNotificationMethods: [String]?

    public init(
        experimentalApi: Bool = true,
        requestAttestation: Bool = false,
        optOutNotificationMethods: [String]? = nil
    ) {
        self.experimentalApi = experimentalApi
        self.requestAttestation = requestAttestation
        self.optOutNotificationMethods = optOutNotificationMethods
    }
}

public struct InitializeParams: Codable, Equatable, Sendable {
    public let clientInfo: ClientInfo
    public let capabilities: InitializeCapabilities?

    public init(clientInfo: ClientInfo, capabilities: InitializeCapabilities? = nil) {
        self.clientInfo = clientInfo
        self.capabilities = capabilities
    }

    public static func codexDock(version: String = "0.1.0") -> InitializeParams {
        InitializeParams(
            clientInfo: ClientInfo(
                name: "codex_dock",
                title: "Codex Dock",
                version: version
            ),
            capabilities: InitializeCapabilities(experimentalApi: true)
        )
    }
}

public struct InitializeResponse: Codable, Equatable, Sendable {
    public let userAgent: String
    public let codexHome: String
    public let platformFamily: String
    public let platformOs: String

    public init(
        userAgent: String,
        codexHome: String,
        platformFamily: String,
        platformOs: String
    ) {
        self.userAgent = userAgent
        self.codexHome = codexHome
        self.platformFamily = platformFamily
        self.platformOs = platformOs
    }
}

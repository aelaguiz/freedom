import Foundation

public enum AppServerMethods {
    public static let initialize = "initialize"
    public static let initialized = "initialized"
    public static let threadDetailSubscribe = "thread/detail/subscribe"
    public static let threadDetailResync = "thread/detail/resync"
    public static let threadDetailUpdate = "thread/detail/update"
    public static let threadArchive = "thread/archive"
    public static let threadUnarchive = "thread/unarchive"
    public static let threadNameSet = "thread/name/set"
    public static let dockSubscribe = "dock/subscribe"
    public static let dockUpdate = "dock/update"
    public static let dockResync = "dock/resync"
    public static let archiveSubscribe = "archive/subscribe"
    public static let archiveUpdate = "archive/update"
    public static let archiveResync = "archive/resync"
    public static let turnStart = "turn/start"
    public static let turnSteer = "turn/steer"
    public static let turnInterrupt = "turn/interrupt"
    public static let audioTranscriptionStart = "audio/transcription/start"
    public static let audioTranscriptionAppend = "audio/transcription/append"
    public static let audioTranscriptionCommit = "audio/transcription/commit"
    public static let audioTranscriptionCancel = "audio/transcription/cancel"
    public static let audioTranscriptionDelta = "audio/transcription/delta"
    public static let audioTranscriptionCompleted = "audio/transcription/completed"
    public static let audioTranscriptionFailed = "audio/transcription/failed"
    public static let audioTranscriptionCanceled = "audio/transcription/canceled"
    public static let audioTranscriptionClosed = "audio/transcription/closed"
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
    public let relayInstanceID: String?

    public init(
        userAgent: String,
        codexHome: String,
        platformFamily: String,
        platformOs: String,
        relayInstanceID: String? = nil
    ) {
        self.userAgent = userAgent
        self.codexHome = codexHome
        self.platformFamily = platformFamily
        self.platformOs = platformOs
        self.relayInstanceID = relayInstanceID
    }
}

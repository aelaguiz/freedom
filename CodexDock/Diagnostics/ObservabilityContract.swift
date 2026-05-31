import Foundation

public enum ObservabilityRouteStatus: String, Codable, CaseIterable, Sendable {
    case unknown
    case healthy
    case degraded
    case failed
    case stale
    case partial
    case blocked
}

public enum ObservabilityFailureCategory: String, Codable, CaseIterable, Sendable {
    case none
    case downstream
    case history
    case liveUpstream = "live-upstream"
    case transcription
    case upstreamOverload = "upstream-overload"
    case payloadSerialization = "payload.serialization"
    case timeout
    case cancelled
    case validation
    case unsupported
    case relay
}

public enum ObservabilityProbeSafety: String, Codable, CaseIterable, Sendable {
    case processOnly = "process-only"
    case autoProbeSafe = "auto-probe-safe"
    case manualOnly = "manual-only"
    case passiveOnly = "passive-only"
}

public struct ObservabilityRouteConfig: Codable, Equatable, Sendable {
    public let name: String
    public let probeSafety: ObservabilityProbeSafety
    public let appCritical: Bool

    public init(name: String, probeSafety: ObservabilityProbeSafety, appCritical: Bool = false) {
        self.name = name
        self.probeSafety = probeSafety
        self.appCritical = appCritical
    }
}

public enum ObservabilityContract {
    public static let traceParamKey = "_codexDockTrace"

    public static let routes: [ObservabilityRouteConfig] = [
        ObservabilityRouteConfig(name: AppServerMethods.initialize, probeSafety: .autoProbeSafe, appCritical: true),
        ObservabilityRouteConfig(name: AppServerMethods.initialized, probeSafety: .passiveOnly),
        ObservabilityRouteConfig(name: AppServerMethods.threadRead, probeSafety: .manualOnly, appCritical: true),
        ObservabilityRouteConfig(name: AppServerMethods.threadResume, probeSafety: .passiveOnly, appCritical: true),
        ObservabilityRouteConfig(name: AppServerMethods.threadTurnsList, probeSafety: .manualOnly, appCritical: true),
        ObservabilityRouteConfig(name: AppServerMethods.threadArchive, probeSafety: .passiveOnly, appCritical: true),
        ObservabilityRouteConfig(name: AppServerMethods.threadUnarchive, probeSafety: .passiveOnly, appCritical: true),
        ObservabilityRouteConfig(name: AppServerMethods.dockSubscribe, probeSafety: .autoProbeSafe, appCritical: true),
        ObservabilityRouteConfig(name: AppServerMethods.dockUpdate, probeSafety: .passiveOnly, appCritical: true),
        ObservabilityRouteConfig(name: AppServerMethods.dockResync, probeSafety: .autoProbeSafe, appCritical: true),
        ObservabilityRouteConfig(name: AppServerMethods.archiveSubscribe, probeSafety: .autoProbeSafe, appCritical: true),
        ObservabilityRouteConfig(name: AppServerMethods.archiveUpdate, probeSafety: .passiveOnly, appCritical: true),
        ObservabilityRouteConfig(name: AppServerMethods.archiveResync, probeSafety: .autoProbeSafe, appCritical: true),
        ObservabilityRouteConfig(name: AppServerMethods.turnStart, probeSafety: .passiveOnly, appCritical: true),
        ObservabilityRouteConfig(name: AppServerMethods.turnSteer, probeSafety: .passiveOnly, appCritical: true),
        ObservabilityRouteConfig(name: AppServerMethods.turnInterrupt, probeSafety: .passiveOnly, appCritical: true),
        ObservabilityRouteConfig(name: AppServerMethods.audioTranscriptionStart, probeSafety: .passiveOnly, appCritical: true),
        ObservabilityRouteConfig(name: AppServerMethods.audioTranscriptionAppend, probeSafety: .passiveOnly, appCritical: true),
        ObservabilityRouteConfig(name: AppServerMethods.audioTranscriptionCommit, probeSafety: .passiveOnly, appCritical: true),
        ObservabilityRouteConfig(name: AppServerMethods.audioTranscriptionCancel, probeSafety: .passiveOnly, appCritical: true),
        ObservabilityRouteConfig(name: AppServerMethods.audioTranscriptionDelta, probeSafety: .passiveOnly, appCritical: true),
        ObservabilityRouteConfig(name: AppServerMethods.audioTranscriptionCompleted, probeSafety: .passiveOnly, appCritical: true),
        ObservabilityRouteConfig(name: AppServerMethods.audioTranscriptionFailed, probeSafety: .passiveOnly, appCritical: true),
        ObservabilityRouteConfig(name: AppServerMethods.audioTranscriptionCanceled, probeSafety: .passiveOnly, appCritical: true),
        ObservabilityRouteConfig(name: AppServerMethods.audioTranscriptionClosed, probeSafety: .passiveOnly, appCritical: true)
    ]

    public static func config(for route: String) -> ObservabilityRouteConfig {
        routes.first { $0.name == route } ?? ObservabilityRouteConfig(name: route, probeSafety: .manualOnly)
    }
}

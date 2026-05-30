import Foundation

public struct RouteStatusReason: Codable, Equatable, Sendable {
    public let code: String
    public let message: String
    public let actual: String?
    public let evidenceIDs: [String]

    public init(code: String, message: String, actual: String? = nil, evidenceIDs: [String] = []) {
        self.code = code
        self.message = message
        self.actual = actual
        self.evidenceIDs = evidenceIDs
    }
}

public struct RouteDiagnosticSnapshot: Codable, Equatable, Identifiable, Sendable {
    public var id: String { "\(configuredHostID)::\(route)" }
    public let configuredHostID: String
    public let relayHostID: String?
    public let route: String
    public let operationID: String?
    public let routeStatus: ObservabilityRouteStatus
    public let statusReasons: [RouteStatusReason]
    public let lastAttemptAt: Date?
    public let lastSuccessAt: Date?
    public let lastFailureAt: Date?
    public let appCritical: Bool
    public let appImpact: String

    public init(
        configuredHostID: String,
        relayHostID: String? = nil,
        route: String,
        operationID: String? = nil,
        routeStatus: ObservabilityRouteStatus,
        statusReasons: [RouteStatusReason] = [],
        lastAttemptAt: Date? = nil,
        lastSuccessAt: Date? = nil,
        lastFailureAt: Date? = nil,
        appCritical: Bool = false,
        appImpact: String? = nil
    ) {
        self.configuredHostID = configuredHostID
        self.relayHostID = relayHostID
        self.route = route
        self.operationID = operationID
        self.routeStatus = routeStatus
        self.statusReasons = statusReasons
        self.lastAttemptAt = lastAttemptAt
        self.lastSuccessAt = lastSuccessAt
        self.lastFailureAt = lastFailureAt
        self.appCritical = appCritical
        self.appImpact = appImpact ?? (appCritical ? "app-critical" : "diagnostic")
    }
}

public struct AppServerRequestObservabilityContext: Sendable {
    public let configuredHostID: String
    public let relayHostID: String?
    public let route: String
    public let operationID: String
    public let traceID: String
    public let parentOperationID: String?
    public let clientBuild: String
    public let platform: String
    public let store: ClientObservabilityStore?

    public init(
        configuredHostID: String,
        relayHostID: String? = nil,
        route: String,
        operationID: String = "op_client_\(UUID().uuidString)",
        traceID: String = "tr_client_\(UUID().uuidString)",
        parentOperationID: String? = nil,
        clientBuild: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
        platform: String = "ios",
        store: ClientObservabilityStore? = .shared
    ) {
        self.configuredHostID = configuredHostID
        self.relayHostID = relayHostID
        self.route = route
        self.operationID = operationID
        self.traceID = traceID
        self.parentOperationID = parentOperationID
        self.clientBuild = clientBuild
        self.platform = platform
        self.store = store
    }

    public var traceJSONValue: JSONValue {
        .object([
            "schema": .string("codexdock.trace.v1"),
            "traceID": .string(traceID),
            "operationID": .string(operationID),
            "parentOperationID": parentOperationID.map(JSONValue.string) ?? .null,
            "configuredHostID": .string(configuredHostID),
            "route": .string(route),
            "clientBuild": .string(clientBuild),
            "platform": .string(platform),
        ])
    }
}

public struct ClientDiagnosticBundle: Codable, Equatable, Sendable {
    public let schema: String
    public let createdAt: Date
    public let appBuild: String
    public let hosts: [String]
    public let routeDiagnostics: [RouteDiagnosticSnapshot]
    public let omitted: [String]
}

// Apple unified logging is a sink. This actor owns durable local route evidence.
public actor ClientObservabilityStore {
    public static let shared = ClientObservabilityStore()

    private struct OperationRecord: Sendable {
        var context: AppServerRequestObservabilityContext
        var startedAt: Date
    }

    private let now: @Sendable () -> Date
    private let persistenceDirectory: URL?
    private let maxOperations: Int
    private var operations: [String: OperationRecord] = [:]
    private var routeDiagnostics: [String: RouteDiagnosticSnapshot] = [:]

    public init(
        persistenceDirectory: URL? = ClientObservabilityStore.defaultPersistenceDirectory(),
        maxOperations: Int = 200,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.persistenceDirectory = persistenceDirectory
        self.maxOperations = maxOperations
        self.now = now
    }

    public func start(_ context: AppServerRequestObservabilityContext) {
        operations[context.operationID] = OperationRecord(context: context, startedAt: now())
        trimOperations()
    }

    public func finish(
        _ context: AppServerRequestObservabilityContext,
        result: Result<Void, Error>
    ) {
        let finishedAt = now()
        let config = ObservabilityContract.config(for: context.route)
        let existing = routeDiagnostics["\(context.configuredHostID)::\(context.route)"]
        let snapshot: RouteDiagnosticSnapshot
        switch result {
        case .success:
            snapshot = RouteDiagnosticSnapshot(
                configuredHostID: context.configuredHostID,
                relayHostID: context.relayHostID,
                route: context.route,
                operationID: context.operationID,
                routeStatus: .healthy,
                lastAttemptAt: finishedAt,
                lastSuccessAt: finishedAt,
                lastFailureAt: existing?.lastFailureAt,
                appCritical: config.appCritical
            )
        case .failure(let error):
            snapshot = RouteDiagnosticSnapshot(
                configuredHostID: context.configuredHostID,
                relayHostID: context.relayHostID,
                route: context.route,
                operationID: context.operationID,
                routeStatus: .failed,
                statusReasons: [
                    RouteStatusReason(
                        code: "failed:last-attempt",
                        message: error.localizedDescription,
                        actual: failureCategory(for: error).rawValue,
                        evidenceIDs: [context.operationID]
                    )
                ],
                lastAttemptAt: finishedAt,
                lastSuccessAt: existing?.lastSuccessAt,
                lastFailureAt: finishedAt,
                appCritical: config.appCritical
            )
        }
        routeDiagnostics[snapshot.id] = snapshot
        operations.removeValue(forKey: context.operationID)
        persist()
    }

    public func recordPassive(
        route: String,
        configuredHostID: String,
        relayHostID: String? = nil,
        operationID: String? = nil
    ) {
        let config = ObservabilityContract.config(for: route)
        let timestamp = now()
        let snapshot = RouteDiagnosticSnapshot(
            configuredHostID: configuredHostID,
            relayHostID: relayHostID,
            route: route,
            operationID: operationID,
            routeStatus: .healthy,
            lastAttemptAt: timestamp,
            lastSuccessAt: timestamp,
            appCritical: config.appCritical
        )
        routeDiagnostics[snapshot.id] = snapshot
        persist()
    }

    public func attachRelayDiagnostics(
        configuredHostID: String,
        relayRoutes: [RouteDiagnosticSnapshot]
    ) {
        for route in relayRoutes {
            let snapshot = RouteDiagnosticSnapshot(
                configuredHostID: configuredHostID,
                relayHostID: route.relayHostID,
                route: route.route,
                operationID: route.operationID,
                routeStatus: route.routeStatus,
                statusReasons: route.statusReasons,
                lastAttemptAt: route.lastAttemptAt,
                lastSuccessAt: route.lastSuccessAt,
                lastFailureAt: route.lastFailureAt,
                appCritical: route.appCritical,
                appImpact: route.appImpact
            )
            routeDiagnostics[snapshot.id] = snapshot
        }
        persist()
    }

    public func snapshots() -> [RouteDiagnosticSnapshot] {
        routeDiagnostics.values.sorted {
            if $0.configuredHostID == $1.configuredHostID {
                return $0.route < $1.route
            }
            return $0.configuredHostID < $1.configuredHostID
        }
    }

    public func snapshot(forConfiguredHostID hostID: String) -> [RouteDiagnosticSnapshot] {
        snapshots().filter { $0.configuredHostID == hostID }
    }

    public func diagnosticBundle(hosts: [String]) -> ClientDiagnosticBundle {
        ClientDiagnosticBundle(
            schema: "codexdock.appBundle.v1",
            createdAt: now(),
            appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            hosts: hosts,
            routeDiagnostics: snapshots(),
            omitted: ["prompts", "transcripts", "audio", "headers", "full-jsonrpc-payloads"]
        )
    }

    private func trimOperations() {
        guard operations.count > maxOperations else {
            return
        }
        let extra = operations.count - maxOperations
        for key in operations.keys.prefix(extra) {
            operations.removeValue(forKey: key)
        }
    }

    private func persist() {
        guard let persistenceDirectory else {
            return
        }
        do {
            try FileManager.default.createDirectory(at: persistenceDirectory, withIntermediateDirectories: true)
            let bundle = diagnosticBundle(hosts: Array(Set(routeDiagnostics.values.map(\.configuredHostID))).sorted())
            let data = try JSONEncoder.diagnostics.encode(bundle)
            try data.write(to: persistenceDirectory.appendingPathComponent("client-observability.json"), options: [.atomic])
        } catch {
            DockLog.connectivity.warning("client observability persistence failed error=\(DockLog.errorSummary(error), privacy: .public)")
        }
    }

    private func failureCategory(for error: Error) -> ObservabilityFailureCategory {
        if let clientError = error as? AppServerClientError {
            switch clientError {
            case .requestTimedOut:
                return .timeout
            case .requestCancelled:
                return .cancelled
            case .server(let object):
                if object.code == -32601 {
                    return .unsupported
                }
                if object.code == -32602 {
                    return .validation
                }
                return .relay
            case .transport, .disconnected, .notConnected:
                return .downstream
            default:
                return .relay
            }
        }
        return .relay
    }

    public static func defaultPersistenceDirectory() -> URL? {
        guard let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return applicationSupport
            .appendingPathComponent("CodexDock", isDirectory: true)
            .appendingPathComponent("Diagnostics", isDirectory: true)
    }
}

private extension JSONEncoder {
    static var diagnostics: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

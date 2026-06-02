import Foundation

public struct SystemHealthProjector: Sendable {
    public init() {}

    public func snapshot(
        hosts: [HostConnectivitySnapshot],
        overallStatus: AppConnectivityOverallStatus
    ) -> SystemHealthSnapshot {
        SystemHealthSnapshot(
            summary: overallStatus,
            categories: SystemHealthCategory.allCases.map { category in
                SystemHealthCategorySnapshot(
                    category: category,
                    status: status(for: category, hosts: hosts, overallStatus: overallStatus)
                )
            },
            hosts: hosts
        )
    }

    private func status(
        for category: SystemHealthCategory,
        hosts: [HostConnectivitySnapshot],
        overallStatus: AppConnectivityOverallStatus
    ) -> SystemHealthCategoryStatus {
        if hosts.isEmpty {
            return .notChecked("No relay host is configured.")
        }

        let routeNames = routeNames(for: category)
        let diagnostics = hosts.flatMap(\.routeDiagnostics).filter { routeNames.contains($0.route) }
        if diagnostics.isEmpty {
            return fallbackStatus(for: category, overallStatus: overallStatus)
        }

        if let failed = diagnostics.first(where: { diagnostic in
            diagnostic.routeStatus == .failed || diagnostic.routeStatus == .blocked
        }) {
            return .failed(
                failed.statusReasons.first?.message ?? "\(category.title) is failing.",
                nextAction: "Run check or open host details."
            )
        }

        if let degraded = diagnostics.first(where: { diagnostic in
            diagnostic.routeStatus == .degraded || diagnostic.routeStatus == .partial || diagnostic.routeStatus == .stale
        }) {
            return .degraded(
                degraded.statusReasons.first?.message ?? "\(category.title) has partial or stale evidence.",
                nextAction: "Run check or review technical details."
            )
        }

        if diagnostics.contains(where: { $0.routeStatus == .healthy }) {
            return .healthy("\(category.title) route evidence is healthy.")
        }

        return .notChecked("No completed check for \(category.title.lowercased()).")
    }

    private func fallbackStatus(
        for category: SystemHealthCategory,
        overallStatus: AppConnectivityOverallStatus
    ) -> SystemHealthCategoryStatus {
        switch overallStatus {
        case .checking, .reconnecting, .resuming:
            return .checking("Checking relay health.")
        case .online:
            switch category {
            case .dockFeed:
                return .healthy("Dock feed is receiving app evidence.")
            case .diagnostics:
                return .healthy("Relay process is reachable.")
            case .threadDetail, .archive, .voice:
                return .notChecked("No recent \(category.title.lowercased()) evidence.")
            }
        case .partial(let message):
            return .degraded(message, nextAction: "Run check or open host details.")
        case .offline(let message), .error(let message), .configurationError(let message), .unconfigured(let message):
            return .failed(message, nextAction: "Open Relay Settings.")
        case .backgrounded(let message):
            return .stale(message, nextAction: "Bring the app foreground to refresh.")
        case .stale(let message):
            return .stale(message, nextAction: "Run check.")
        }
    }

    private func routeNames(for category: SystemHealthCategory) -> Set<String> {
        switch category {
        case .dockFeed:
            return [AppServerMethods.dockSubscribe, AppServerMethods.dockUpdate, AppServerMethods.dockResync]
        case .threadDetail:
            return [
                AppServerMethods.threadDetailSubscribe,
                AppServerMethods.threadDetailUpdate,
                AppServerMethods.threadDetailResync,
            ]
        case .archive:
            return [
                AppServerMethods.archiveSubscribe,
                AppServerMethods.archiveUpdate,
                AppServerMethods.archiveResync,
                AppServerMethods.threadArchive,
                AppServerMethods.threadUnarchive
            ]
        case .voice:
            return [
                AppServerMethods.audioTranscriptionStart,
                AppServerMethods.audioTranscriptionAppend,
                AppServerMethods.audioTranscriptionCommit,
                AppServerMethods.audioTranscriptionCompleted
            ]
        case .diagnostics:
            return [AppServerMethods.initialize, AppServerMethods.initialized]
        }
    }
}

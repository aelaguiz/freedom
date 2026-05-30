import Foundation

struct ConnectivityRenderProjector: Sendable {
    func render(
        records: [String: ConnectivityHostRecord],
        hostOrder: [String],
        revision: RenderRevision
    ) -> ConnectivityRenderSnapshot {
        let hosts = records.values
            .map(snapshot(from:))
            .sorted { lhs, rhs in
                let leftIndex = hostOrder.firstIndex(of: lhs.id) ?? Int.max
                let rightIndex = hostOrder.firstIndex(of: rhs.id) ?? Int.max
                if leftIndex == rightIndex {
                    return lhs.displayName < rhs.displayName
                }
                return leftIndex < rightIndex
            }
        return ConnectivityRenderSnapshot(
            revision: revision,
            hosts: hosts,
            overallStatus: rollup(hosts)
        )
    }

    private func snapshot(from record: ConnectivityHostRecord) -> HostConnectivitySnapshot {
        HostConnectivitySnapshot(
            id: record.id,
            displayName: record.displayName,
            endpoint: record.endpoint,
            phase: record.phase,
            lastCheckedAt: record.lastCheckedAt,
            lastSuccessAt: record.lastSuccessAt,
            routeDiagnostics: record.routeDiagnostics
        )
    }

    private func rollup(_ hosts: [HostConnectivitySnapshot]) -> AppConnectivityOverallStatus {
        guard !hosts.isEmpty else {
            return .unconfigured("No relay host configured.")
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

    private func firstStatus(
        _ hosts: [HostConnectivitySnapshot],
        matching predicate: (HostConnectivitySnapshot) -> Bool
    ) -> HostConnectivitySnapshot? {
        hosts.first(where: predicate)
    }
}

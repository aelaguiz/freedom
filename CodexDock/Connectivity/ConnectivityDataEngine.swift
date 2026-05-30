import Foundation

public actor ConnectivityDataEngine {
    private var records: [String: ConnectivityHostRecord]
    private var hostOrder: [String]
    private var revision = RenderRevision.zero
    private let now: @Sendable () -> Date

    public init(
        registry: HostRegistry,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.records = Self.records(from: registry)
        self.hostOrder = registry.hosts.map(\.id)
        self.now = now
    }

    public func configure(_ registry: HostRegistry) -> ConnectivityRenderSnapshot {
        records = Self.records(from: registry, preserving: records)
        hostOrder = registry.hosts.map(\.id)
        revision = revision.next()
        return render()
    }

    public func apply(_ event: ConnectivityRuntimeEvent) -> ConnectivityRenderSnapshot {
        guard let hostID = event.hostID else {
            revision = revision.next()
            return render()
        }

        var record = records[hostID] ?? ConnectivityHostRecord(
            id: hostID,
            displayName: hostID,
            endpoint: hostID,
            phase: .unknown,
            lastCheckedAt: nil,
            lastSuccessAt: nil,
            routeDiagnostics: []
        )
        let phase = event.phase ?? Self.phase(from: event)
        record.phase = phase
        record.lastCheckedAt = event.recordedAt
        if phase.isOnlineLike {
            record.lastSuccessAt = event.recordedAt
        }
        records[hostID] = record
        if !hostOrder.contains(hostID) {
            hostOrder.append(hostID)
        }
        revision = revision.next()
        return render()
    }

    public func snapshot() -> ConnectivityRenderSnapshot {
        render()
    }

    private func render() -> ConnectivityRenderSnapshot {
        ConnectivityRenderProjector().render(
            records: records,
            hostOrder: hostOrder,
            revision: revision
        )
    }

    private static func records(
        from registry: HostRegistry,
        preserving existing: [String: ConnectivityHostRecord] = [:]
    ) -> [String: ConnectivityHostRecord] {
        Dictionary(
            uniqueKeysWithValues: registry.hosts.map { host in
                let display = DockHostViewModel(host: host)
                var record = existing[host.id] ?? ConnectivityHostRecord(
                    id: host.id,
                    displayName: display.displayName,
                    endpoint: display.endpoint,
                    phase: .unknown,
                    lastCheckedAt: nil,
                    lastSuccessAt: nil,
                    routeDiagnostics: []
                )
                record.displayName = display.displayName
                record.endpoint = display.endpoint
                return (host.id, record)
            }
        )
    }

    private static func phase(from event: ConnectivityRuntimeEvent) -> HostConnectivityPhase {
        let status = event.status.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = status.lowercased()

        if lowercased == "idle" {
            return .unknown
        }
        if lowercased == "checking" || lowercased.hasPrefix("checking ") {
            return .checking
        }
        if lowercased.hasPrefix("offline:") {
            return .offline(trimmedMessage(status, prefix: "offline:"))
        }
        if lowercased == "offline" {
            return .offline("Offline")
        }
        if lowercased.hasPrefix("error:") {
            return .error(trimmedMessage(status, prefix: "error:"))
        }
        if lowercased == "error" {
            return .error("Error")
        }
        if lowercased.contains("partial") {
            return .partial(status)
        }
        return .online(status.isEmpty ? "Online" : status)
    }

    private static func trimmedMessage(_ status: String, prefix: String) -> String {
        let start = status.index(status.startIndex, offsetBy: prefix.count)
        return status[start...].trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

import SwiftUI

public struct ConnectivityDiagnosticsSheet: View {
    private let hosts: [HostConnectivitySnapshot]

    public init(hosts: [HostConnectivitySnapshot]) {
        self.hosts = hosts
    }

    public var body: some View {
        NavigationStack {
            List {
                ForEach(hosts) { host in
                    Section {
                        LabeledContent("Endpoint", value: host.endpoint)
                        LabeledContent("Status", value: host.phase.message)
                        if let lastSuccessAt = host.lastSuccessAt {
                            LabeledContent("Last success", value: lastSuccessAt.formatted(date: .omitted, time: .standard))
                        }
                        if host.routeDiagnostics.isEmpty {
                            Text("No route evidence yet")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(host.routeDiagnostics) { diagnostic in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(diagnostic.route)
                                            .font(.subheadline.weight(.semibold))
                                        Spacer()
                                        Text(diagnostic.routeStatus.rawValue)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(color(for: diagnostic.routeStatus))
                                    }
                                    if let operationID = diagnostic.operationID {
                                        Text(operationID)
                                            .font(.caption.monospaced())
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    ForEach(diagnostic.statusReasons, id: \.code) { reason in
                                        Text(reason.message)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    } header: {
                        Text(host.displayName)
                    }
                }
            }
            .navigationTitle("Connectivity")
        }
    }

    private func color(for status: ObservabilityRouteStatus) -> Color {
        switch status {
        case .healthy:
            return .green
        case .unknown:
            return .secondary
        case .degraded, .partial, .stale:
            return .orange
        case .failed, .blocked:
            return .red
        }
    }
}

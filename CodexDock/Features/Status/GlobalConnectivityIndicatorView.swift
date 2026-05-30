import SwiftUI

public struct GlobalConnectivityIndicatorView: View {
    @ObservedObject private var store: AppConnectivityStore
    @State private var showsDiagnostics = false

    public init(store: AppConnectivityStore) {
        self.store = store
    }

    public var body: some View {
        Button {
            showsDiagnostics = true
        } label: {
            Label(displayLabel, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(foregroundColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(backgroundColor, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(displayLabel)
        .accessibilityValue("\(store.overallStatus.label): \(store.overallStatus.message)")
        .codexAutomationID(AutomationID.Connectivity.globalIndicator)
        .sheet(isPresented: $showsDiagnostics) {
            ConnectivityDiagnosticsSheet(hosts: store.hosts)
                .task {
                    await store.refreshRelayDiagnostics()
                }
        }
    }

    private var displayLabel: String {
        switch store.overallStatus {
        case .checking:
            return store.hosts.count > 1 ? "Checking \(store.hosts.count) hosts" : "Checking"
        case .online:
            return hostCountLabel(prefix: "Online") ?? "Online"
        case .partial:
            return hostCountLabel(prefix: "Online") ?? "Partial"
        case .offline:
            return "Offline"
        case .error:
            return "Error"
        case .configurationError:
            return "Config error"
        case .unconfigured:
            return "Unconfigured"
        case .reconnecting:
            return "Reconnecting"
        case .backgrounded:
            return "Backgrounded"
        case .resuming:
            return "Resuming"
        case .stale:
            return "Stale"
        }
    }

    private func hostCountLabel(prefix: String) -> String? {
        guard store.hosts.count > 1 else {
            return nil
        }
        let onlineCount = store.hosts.filter(\.phase.isOnlineLike).count
        return "\(prefix) \(onlineCount)/\(store.hosts.count)"
    }

    private var systemImage: String {
        switch store.overallStatus {
        case .unconfigured:
            return "questionmark.circle"
        case .checking:
            return "antenna.radiowaves.left.and.right"
        case .online:
            return "checkmark.circle"
        case .partial:
            return "exclamationmark.triangle"
        case .reconnecting:
            return "arrow.triangle.2.circlepath"
        case .backgrounded:
            return "pause.circle"
        case .resuming:
            return "arrow.clockwise.circle"
        case .stale:
            return "clock.badge.exclamationmark"
        case .offline:
            return "wifi.slash"
        case .error, .configurationError:
            return "exclamationmark.octagon"
        }
    }

    private var foregroundColor: Color {
        switch store.overallStatus {
        case .online:
            return .green
        case .checking, .unconfigured:
            return .secondary
        case .partial, .reconnecting, .backgrounded, .resuming, .stale:
            return .orange
        case .offline, .error, .configurationError:
            return .red
        }
    }

    private var backgroundColor: Color {
        foregroundColor.opacity(0.14)
    }
}

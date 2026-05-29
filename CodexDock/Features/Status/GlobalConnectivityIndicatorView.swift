import SwiftUI

public struct GlobalConnectivityIndicatorView: View {
    @ObservedObject private var store: AppConnectivityStore

    public init(store: AppConnectivityStore) {
        self.store = store
    }

    public var body: some View {
        Label(store.overallStatus.label, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(backgroundColor, in: Capsule())
            .accessibilityLabel(store.overallStatus.label)
            .accessibilityValue(store.overallStatus.message)
            .codexAutomationID(AutomationID.Connectivity.globalIndicator)
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

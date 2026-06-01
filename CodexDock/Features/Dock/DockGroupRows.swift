import SwiftUI

struct DockGroupHeaderView: View {
    let group: DockProjectionGroupViewModel
    let isCollapsed: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(group.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Text("\(group.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.secondary.opacity(0.12), in: Capsule())
        }
        .padding(10)
        .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityValue(accessibilityValue)
    }

    private var detailText: String {
        var parts = [group.subtitle]
        if group.runningCount > 0 {
            parts.append("\(group.runningCount) running")
        }
        if let newest = group.newestActivityDate {
            parts.append(newest.formatted(date: .abbreviated, time: .shortened))
        }
        return parts.joined(separator: " · ")
    }

    private var accessibilityValue: String {
        var parts = [group.subtitle, "\(group.count) sessions", "running \(group.runningCount)"]
        parts.append(isCollapsed ? "collapsed" : "expanded")
        return parts.joined(separator: "; ")
    }
}

struct HostLoadingRow: View {
    let hostState: DockHostStateViewModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: hostState.status == .checking ? "clock.arrow.circlepath" : "desktopcomputer")
                .font(.system(size: 20))
                .foregroundStyle(.blue)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(hostState.host.displayName)
                    .font(.subheadline.weight(.semibold))
                Text(hostState.status == .checking ? "Checking" : hostState.status.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(hostState.host.id); endpoint=\(hostState.host.endpoint); \(hostState.status.subtitle)")
    }
}

struct HostFailureRow: View {
    let hostState: DockHostStateViewModel
    let onRetry: @MainActor () -> Void
    let onOpenRelaySettings: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 20))
                    .foregroundStyle(.orange)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(hostState.host.displayName)
                        .font(.subheadline.weight(.semibold))
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                Spacer(minLength: 8)
            }

            HStack(spacing: 8) {
                Button {
                    onRetry()
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .codexAutomationID(AutomationID.Dock.hostRetry(hostID: hostState.host.id))

                Button {
                    onOpenRelaySettings()
                } label: {
                    Label("Relay", systemImage: "desktopcomputer")
                }
                .buttonStyle(.bordered)
                .codexAutomationID(AutomationID.Dock.hostRelaySettings(hostID: hostState.host.id))
            }
            .font(.caption.weight(.semibold))
        }
        .padding(12)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityValue("\(hostState.host.id); endpoint=\(hostState.host.endpoint); \(message)")
    }

    private var message: String {
        switch hostState.status {
        case .checking:
            return "Checking"
        case .loaded, .partial, .empty:
            return hostState.status.subtitle
        case .offline(let message), .error(let message):
            return "\(hostState.status.subtitle): \(message)"
        }
    }
}

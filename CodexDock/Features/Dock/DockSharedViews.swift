import SwiftUI

struct HostSummaryView: View {
    let host: DockHostViewModel
    let subtitle: String
    let automationID: AutomationID?

    init(host: DockHostViewModel, subtitle: String, automationID: AutomationID? = nil) {
        self.host = host
        self.subtitle = subtitle
        self.automationID = automationID
    }

    init(hostState: DockHostStateViewModel, automationID: AutomationID? = nil) {
        self.host = hostState.host
        self.automationID = automationID
        switch hostState.status {
        case .checking:
            self.subtitle = hostState.status.subtitle
        case .loaded, .partial, .empty:
            self.subtitle = hostState.status.subtitle
        case .offline(let message), .error(let message):
            self.subtitle = "\(hostState.status.subtitle): \(message)"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 24))
                .foregroundStyle(.blue)
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(host.displayName)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            Text("Codex")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.blue.opacity(0.12), in: Capsule())
                .fixedSize()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(host.id); endpoint=\(host.endpoint); \(subtitle)")
        .codexAutomationID(automationID)
    }
}

struct MappingFailureBanner: View {
    let count: Int
    var automationID: AutomationID? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text("\(count) sessions could not be normalized.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(12)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(count) mapping failures")
        .codexAutomationID(automationID)
    }
}

struct ActionErrorBanner: View {
    let message: String
    var automationID: AutomationID? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(.red)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Spacer()
        }
        .padding(12)
        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityValue(message)
        .codexAutomationID(automationID)
    }
}

struct DockMessageView: View {
    let icon: String
    let title: String
    let message: String
    var automationID: AutomationID? = nil

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityValue(message)
        .codexAutomationID(automationID)
    }
}

struct DockRowView: View {
    let row: DockRowViewModel
    var showsPinIndicator = false
    var automationID: AutomationID? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(railColor)
                .frame(width: 5)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .top, spacing: 8) {
                    if showsPinIndicator, row.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.blue)
                            .padding(.top, 2)
                            .accessibilityHidden(true)
                    }

                    Text(row.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)

                    Spacer(minLength: 8)

                    HStack(spacing: 6) {
                        if row.relationship.isForked {
                            Label("Fork", systemImage: "arrow.triangle.branch")
                                .labelStyle(.titleAndIcon)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(Color.secondary.opacity(0.12), in: Capsule())
                        }

                        if let statusLabel = row.status.visibleBadgeLabel {
                            Text(statusLabel)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(statusColor)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(statusColor.opacity(0.12), in: Capsule())
                        }
                    }
                }

                Text("\(row.hostDisplayName) · \(row.repository) · \(row.branch)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let label = row.label {
                    Label(label, systemImage: "tag")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(row.summary)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Image(systemName: "clock")
                    Text(row.lastActivity)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityValue(row.automationValue)
        .codexAutomationID(automationID)
    }

    private var railColor: Color {
        switch row.rail {
        case .blue:
            return .blue
        case .green:
            return .green
        case .orange:
            return .orange
        case .red:
            return .red
        case .violet:
            return .purple
        }
    }

    private var statusColor: Color {
        switch row.status {
        case .running:
            return .green
        case .needsInput:
            return .orange
        case .needsApproval:
            return .orange
        case .idle:
            return .blue
        case .error:
            return .red
        case .dormant:
            return .secondary
        case .unknown:
            return .secondary
        }
    }
}

extension DockRowRail {
    var label: String {
        switch self {
        case .blue:
            return "Blue"
        case .green:
            return "Green"
        case .orange:
            return "Orange"
        case .red:
            return "Red"
        case .violet:
            return "Violet"
        }
    }

    var systemImage: String {
        switch self {
        case .blue:
            return "circle.fill"
        case .green:
            return "circle.fill"
        case .orange:
            return "circle.fill"
        case .red:
            return "circle.fill"
        case .violet:
            return "circle.fill"
        }
    }
}

extension DockRowViewModel {
    var automationValue: String {
        [
            "host=\(id.hostID)",
            "hostDisplay=\(hostDisplayName)",
            "thread=\(id.threadID)",
            "status=\(status.rawValue)",
            "origin=\(origin.automationKind)",
            "relationship=\(relationship.rawValue)",
            "label=\(label == nil ? "none" : "present")",
            isPinned ? "Pinned" : "Not pinned",
        ].joined(separator: "; ")
    }
}

extension View {
    @ViewBuilder
    func dockNavigationChrome() -> some View {
        #if os(iOS)
        self.navigationBarHidden(true)
        #else
        self
        #endif
    }
}

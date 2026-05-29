import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

public struct SessionDetailView: View {
    @StateObject private var store: ThreadDetailStore
    @State private var visibilityMode: ThreadEventVisibilityMode = .messages

    public init(store: ThreadDetailStore) {
        _store = StateObject(wrappedValue: store)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
        .background(detailBackgroundColor)
        .navigationTitle("Thread")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await store.load()
        }
        .onDisappear {
            store.close()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.state {
        case let .idle(header):
            DetailHeaderView(header: header, liveState: .connecting)
        case let .loading(header):
            DetailHeaderView(header: header, liveState: .connecting)
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 140)
        case let .loaded(snapshot):
            DetailHeaderView(
                header: snapshot.header,
                liveState: snapshot.liveState,
                visibilityMode: visibilityMode,
                onCycleVisibility: cycleVisibilityMode
            )
            if case let .stale(message) = snapshot.liveState {
                DetailMessageView(
                    icon: "wifi.exclamationmark",
                    title: "Live updates stopped",
                    message: message
                )
            }
            ComposerView(store: store)
            RequestCardsView(store: store)
            EventTimelineView(
                events: visibilityMode.visibleEvents(from: snapshot.events),
                visibilityMode: visibilityMode,
                hasUnfilteredEvents: !snapshot.events.isEmpty
            )
        case let .error(header, message):
            DetailHeaderView(header: header, liveState: .stale(message))
            DetailMessageView(
                icon: "exclamationmark.octagon",
                title: "Thread unavailable",
                message: message
            )
        }
    }

    private var detailBackgroundColor: Color {
        #if os(iOS)
        Color(uiColor: .systemGroupedBackground)
        #elseif os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(.background)
        #endif
    }

    private func cycleVisibilityMode() {
        visibilityMode = visibilityMode.next
    }
}

private struct DetailHeaderView: View {
    let header: ThreadDetailHeader
    let liveState: ThreadDetailLiveState
    let visibilityMode: ThreadEventVisibilityMode?
    let onCycleVisibility: (() -> Void)?

    init(
        header: ThreadDetailHeader,
        liveState: ThreadDetailLiveState,
        visibilityMode: ThreadEventVisibilityMode? = nil,
        onCycleVisibility: (() -> Void)? = nil
    ) {
        self.header = header
        self.liveState = liveState
        self.visibilityMode = visibilityMode
        self.onCycleVisibility = onCycleVisibility
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "terminal")
                    .font(.title3)
                    .foregroundStyle(.blue)
                    .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 5) {
                    Text(header.title)
                        .font(.title3.weight(.semibold))
                        .lineLimit(3)

                    Text("\(header.repository) · \(header.branch)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)
            }

            statusRow

            Text("\(header.threadID) · \(header.lastActivity)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusRow: some View {
        if let visibilityMode, let onCycleVisibility {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    pillGroup
                    Spacer(minLength: 8)
                    VisibilityModeButton(mode: visibilityMode, onCycle: onCycleVisibility)
                }

                VStack(alignment: .leading, spacing: 8) {
                    pillGroup
                    VisibilityModeButton(mode: visibilityMode, onCycle: onCycleVisibility)
                }
            }
        } else {
            pillGroup
        }
    }

    @ViewBuilder
    private var pillGroup: some View {
        ViewThatFits(in: .horizontal) {
            pillRow

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    hostPill
                    livePill
                }
                statusPill
            }

            VStack(alignment: .leading, spacing: 8) {
                hostPill
                livePill
                statusPill
            }
        }
    }

    private var pillRow: some View {
        HStack(spacing: 8) {
            hostPill
            livePill
            statusPill
        }
    }

    private var hostPill: some View {
        DetailPill(label: header.hostName, systemImage: "desktopcomputer", color: .blue)
    }

    private var livePill: some View {
        DetailPill(label: liveState.label, systemImage: liveIcon, color: liveColor)
    }

    private var statusPill: some View {
        DetailPill(label: header.statusLabel, systemImage: "circle.dashed", color: .secondary)
    }

    private var liveIcon: String {
        switch liveState {
        case .connecting:
            return "antenna.radiowaves.left.and.right"
        case .reconnecting:
            return "arrow.triangle.2.circlepath"
        case .live:
            return "dot.radiowaves.left.and.right"
        case .stale:
            return "wifi.exclamationmark"
        case .closed:
            return "xmark.circle"
        }
    }

    private var liveColor: Color {
        switch liveState {
        case .connecting:
            return .secondary
        case .reconnecting:
            return .orange
        case .live:
            return .green
        case .stale:
            return .orange
        case .closed:
            return .red
        }
    }
}

private extension ThreadEventVisibilityMode {
    var buttonLabel: String {
        switch self {
        case .messages:
            return "Messages"
        case .messagesAndThinking:
            return "Thinking"
        case .everything:
            return "Everything"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .messages:
            return "Timeline visibility: Messages"
        case .messagesAndThinking:
            return "Timeline visibility: Messages and Thinking"
        case .everything:
            return "Timeline visibility: Everything"
        }
    }

    var systemImage: String {
        switch self {
        case .messages:
            return "text.bubble"
        case .messagesAndThinking:
            return "lightbulb"
        case .everything:
            return "square.stack.3d.up"
        }
    }

    var emptyStateTitle: String {
        switch self {
        case .messages:
            return "No messages"
        case .messagesAndThinking:
            return "No messages or thinking"
        case .everything:
            return "No transcript"
        }
    }
}

private struct VisibilityModeButton: View {
    let mode: ThreadEventVisibilityMode
    let onCycle: () -> Void

    var body: some View {
        Button(action: onCycle) {
            Label(mode.buttonLabel, systemImage: mode.systemImage)
                .lineLimit(1)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .font(.caption.weight(.semibold))
        .accessibilityLabel(mode.accessibilityLabel)
        .accessibilityHint("Cycles timeline visibility")
    }
}

private struct DetailPill: View {
    let label: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label(label, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(color.opacity(0.12), in: Capsule())
    }
}

private struct EventTimelineView: View {
    let events: [ThreadEvent]
    let visibilityMode: ThreadEventVisibilityMode
    let hasUnfilteredEvents: Bool

    var body: some View {
        if events.isEmpty {
            if hasUnfilteredEvents {
                DetailMessageView(
                    icon: visibilityMode.systemImage,
                    title: visibilityMode.emptyStateTitle,
                    message: "This visibility mode has no readable events."
                )
            } else {
                DetailMessageView(
                    icon: "text.bubble",
                    title: "No transcript",
                    message: "This thread returned no readable events."
                )
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(events) { event in
                    ThreadEventCard(event: event)
                }
            }
        }
    }
}

private struct ThreadEventCard: View {
    let event: ThreadEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Label(event.kind.label, systemImage: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)

                Spacer(minLength: 8)

                if event.isLive {
                    Text("Live")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.green.opacity(0.12), in: Capsule())
                }
            }

            Text(event.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Text(event.body)
                .font(bodyFont)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var bodyFont: Font {
        switch event.kind {
        case .command, .output:
            return .caption.monospaced()
        case .userMessage, .agentMessage, .request, .system, .unknown:
            return .footnote
        }
    }

    private var icon: String {
        switch event.kind {
        case .userMessage:
            return "person"
        case .agentMessage:
            return "sparkles"
        case .command:
            return "terminal"
        case .output:
            return "text.alignleft"
        case .request:
            return "hand.raised"
        case .system:
            return "gearshape"
        case .unknown:
            return "questionmark.circle"
        }
    }

    private var color: Color {
        switch event.kind {
        case .userMessage:
            return .blue
        case .agentMessage:
            return .green
        case .command:
            return .purple
        case .output:
            return .secondary
        case .request:
            return .orange
        case .system:
            return .teal
        case .unknown:
            return .red
        }
    }
}

private struct DetailMessageView: View {
    let icon: String
    let title: String
    let message: String

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
        .frame(maxWidth: .infinity, minHeight: 140)
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

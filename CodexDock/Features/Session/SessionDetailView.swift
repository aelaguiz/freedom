import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

public struct SessionDetailView: View {
    @StateObject private var store: ThreadDetailStore

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
            DetailHeaderView(header: snapshot.header, liveState: snapshot.liveState)
            if case let .stale(message) = snapshot.liveState {
                DetailMessageView(
                    icon: "wifi.exclamationmark",
                    title: "Live updates stopped",
                    message: message
                )
            }
            ComposerView(store: store)
            RequestCardsView(store: store)
            EventTimelineView(events: snapshot.events)
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
}

private struct DetailHeaderView: View {
    let header: ThreadDetailHeader
    let liveState: ThreadDetailLiveState

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

            HStack(spacing: 8) {
                DetailPill(label: header.hostName, systemImage: "desktopcomputer", color: .blue)
                DetailPill(label: liveState.label, systemImage: liveIcon, color: liveColor)
                DetailPill(label: header.statusLabel, systemImage: "circle.dashed", color: .secondary)
            }

            Text("\(header.threadID) · \(header.lastActivity)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private var liveIcon: String {
        switch liveState {
        case .connecting:
            return "antenna.radiowaves.left.and.right"
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
        case .live:
            return .green
        case .stale:
            return .orange
        case .closed:
            return .red
        }
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

    var body: some View {
        if events.isEmpty {
            DetailMessageView(
                icon: "text.bubble",
                title: "No transcript",
                message: "This thread returned no readable events."
            )
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

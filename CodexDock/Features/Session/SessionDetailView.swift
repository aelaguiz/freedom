import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

public struct SessionDetailView: View {
    @StateObject private var store: ThreadDetailStore
    @State private var selectedMessageKind: ThreadEventKind?

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
            loadedContent(snapshot)
        case let .error(header, message):
            DetailHeaderView(header: header, liveState: .stale(message))
            DetailMessageView(
                icon: "exclamationmark.octagon",
                title: "Thread unavailable",
                message: message
            )
        }
    }

    @ViewBuilder
    private func loadedContent(_ snapshot: ThreadDetailSnapshot) -> some View {
        let filter = ThreadDetailMessageFilter(kind: selectedMessageKind)
        DetailHeaderView(
            header: snapshot.header,
            liveState: snapshot.liveState
        )
        MessageTypeFilterControl(selectedKind: $selectedMessageKind)
        if case let .stale(message) = snapshot.liveState {
            DetailMessageView(
                icon: "wifi.exclamationmark",
                title: "Live updates stopped",
                message: message
            )
        }
        ComposerView(store: store)
        ThreadMessageListView(
            events: filter.visibleEvents(from: snapshot.events),
            filter: filter,
            hasUnfilteredEvents: !snapshot.events.isEmpty,
            requestCards: store.requestCards,
            onRequestInputChange: { cardID, draft in
                store.updateRequestCardInput(cardID: cardID, draft: draft)
            },
            onRequestAction: { cardID, action in
                Task {
                    await store.respond(to: cardID, action: action)
                }
            }
        )
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

    init(header: ThreadDetailHeader, liveState: ThreadDetailLiveState) {
        self.header = header
        self.liveState = liveState
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
        pillGroup
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

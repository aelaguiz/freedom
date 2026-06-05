import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

public struct SessionDetailView: View {
    @StateObject private var store: ThreadDetailStore
    @StateObject private var screenStore: ThreadDetailScreenStore
    private let onRename: (@MainActor (DockRowViewModel) -> Void)?

    public init(
        store: ThreadDetailStore,
        onRename: (@MainActor (DockRowViewModel) -> Void)? = nil
    ) {
        _store = StateObject(wrappedValue: store)
        _screenStore = StateObject(wrappedValue: store.screenStore)
        self.onRename = onRename
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
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        #endif
        .background(detailBackgroundColor)
        .navigationTitle("Thread")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if let onRename {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        onRename(store.row)
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .accessibilityLabel("Rename Thread")
                    .codexAutomationID(AutomationID.Session.renameButton)
                }
            }
        }
        .task {
            await store.load()
        }
        .onDisappear {
            store.detachView()
        }
        .accessibilityElement(children: .contain)
        .codexAutomationID(AutomationID.Session.root(threadID: store.row.threadID))
        .accessibilityValue(sessionScreenValue)
    }

    @ViewBuilder
    private var content: some View {
        switch screenStore.state {
        case let .idle(header):
            DetailHeaderView(header: header, liveState: .connecting)
        case let .loading(header):
            DetailHeaderView(header: header, liveState: .connecting)
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 140)
                .codexAutomationID(AutomationID.Session.state(.loading))
        case let .loaded(renderSnapshot):
            loadedContent(renderSnapshot)
        case let .error(header, message):
            DetailHeaderView(header: header, liveState: .stale(message))
            DetailMessageView(
                icon: "exclamationmark.octagon",
                title: "Thread unavailable",
                message: message,
                automationID: AutomationID.Session.state(.error)
            )
        }
    }

    @ViewBuilder
    private func loadedContent(_ renderSnapshot: ThreadDetailRenderSnapshot) -> some View {
        let filter = renderSnapshot.options.filter
        DetailHeaderView(
            header: renderSnapshot.header,
            liveState: renderSnapshot.liveState
        )
        MessageTypeFilterControl(filter: messageFilterBinding)
        if case let .stale(message) = renderSnapshot.liveState {
            DetailMessageView(
                icon: "wifi.exclamationmark",
                title: "Live updates stopped",
                message: message,
                automationID: AutomationID.Session.state(.stale)
            )
        }
        ComposerView(
            screenStore: screenStore,
            onUpdateDraft: { draft in
                store.updateDraft(draft)
            },
            onSendDraft: {
                store.sendDraftInBackground()
            },
            onBeginVoiceCapture: {
                await store.beginVoiceCapture()
            },
            onFinishVoiceCapture: {
                await store.finishVoiceCapture()
            },
            onToggleTapVoiceCapture: {
                await store.toggleTapVoiceCapture()
            }
        )
        ThreadMessageListView(
            rows: renderSnapshot.rows,
            filter: filter,
            hasUnfilteredEvents: renderSnapshot.hasUnfilteredEvents,
            fileChangeViewedFileIDsByEventID: store.fileChangeViewedFileIDsByEventID,
            onRequestInputChange: { cardID, draft in
                store.updateRequestCardInput(cardID: cardID, draft: draft)
            },
            onRequestAction: { cardID, action in
                Task {
                    await store.respond(to: cardID, action: action)
                }
            },
            onFileChangeViewed: { eventID, fileID in
                store.markFileChangeFileViewed(eventID: eventID, fileID: fileID)
            },
            onFileChangeApprovalRiskConfirmed: { cardID in
                store.confirmFileChangeApprovalRisk(cardID: cardID)
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

    private var sessionScreenValue: String {
        switch screenStore.state {
        case let .idle(header):
            return "idle; host=\(header.hostID); thread=\(header.threadID); live=connecting"
        case let .loading(header):
            return "loading; host=\(header.hostID); thread=\(header.threadID); live=connecting"
        case let .loaded(renderSnapshot):
            return "loaded; host=\(renderSnapshot.header.hostID); thread=\(renderSnapshot.header.threadID); live=\(renderSnapshot.liveState.label); events=\(renderSnapshot.rows.count)"
        case let .error(header, _):
            return "error; host=\(header.hostID); thread=\(header.threadID); live=stale"
        }
    }

    private var messageFilterBinding: Binding<ThreadDetailMessageFilter> {
        Binding(
            get: { screenStore.options.filter },
            set: { screenStore.setFilter($0) }
        )
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
        .accessibilityElement(children: .contain)
        .accessibilityValue("host=\(header.hostID); thread=\(header.threadID); live=\(liveState.label); status=\(header.statusLabel ?? "none"); relationship=\(header.relationship.rawValue)")
        .codexAutomationID(AutomationID.Session.header)
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
                    forkPill
                }
                statusPill
            }

            VStack(alignment: .leading, spacing: 8) {
                hostPill
                livePill
                forkPill
                statusPill
            }
        }
    }

    private var pillRow: some View {
        HStack(spacing: 8) {
            hostPill
            livePill
            forkPill
            statusPill
        }
    }

    private var hostPill: some View {
        DetailPill(label: header.hostName, systemImage: "desktopcomputer", color: .blue)
            .accessibilityValue(header.hostID)
            .codexAutomationID(AutomationID.Session.hostPill)
    }

    private var livePill: some View {
        DetailPill(label: liveState.label, systemImage: liveIcon, color: liveColor)
            .accessibilityValue(liveState.label)
            .codexAutomationID(AutomationID.Session.livePill)
    }

    @ViewBuilder
    private var forkPill: some View {
        if header.relationship.isForked {
            DetailPill(label: "Fork", systemImage: "arrow.triangle.branch", color: .secondary)
                .accessibilityValue("Forked thread")
        }
    }

    @ViewBuilder
    private var statusPill: some View {
        if let statusLabel = header.statusLabel {
            DetailPill(label: statusLabel, systemImage: "circle.dashed", color: .secondary)
                .accessibilityValue(statusLabel)
                .codexAutomationID(AutomationID.Session.statusPill)
        }
    }

    private var liveIcon: String {
        switch liveState {
        case .connecting:
            return "antenna.radiowaves.left.and.right"
        case .updating:
            return "arrow.triangle.2.circlepath"
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
        case .updating:
            return .blue
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

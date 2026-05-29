import SwiftUI

struct MessageTypeFilterControl: View {
    @Binding var selectedKind: ThreadEventKind?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            controlRow
            VStack(alignment: .leading, spacing: 8) {
                controlRow
            }
        }
    }

    private var controlRow: some View {
        HStack(spacing: 8) {
            Menu {
                Button {
                    selectedKind = nil
                } label: {
                    Label("All", systemImage: ThreadDetailMessageFilter.all.systemImage)
                }

                Divider()

                ForEach(ThreadEventKind.allCases, id: \.self) { kind in
                    Button {
                        selectedKind = kind
                    } label: {
                        Label(kind.label, systemImage: kind.systemImage)
                    }
                }
            } label: {
                Label(currentLabel, systemImage: currentImage)
                    .lineLimit(1)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .font(.caption.weight(.semibold))

            if selectedKind != nil {
                Button {
                    selectedKind = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityLabel("Clear message type filter")
                .help("Clear filter")
            }
        }
    }

    private var currentLabel: String {
        selectedKind?.label ?? "All"
    }

    private var currentImage: String {
        selectedKind?.systemImage ?? ThreadDetailMessageFilter.all.systemImage
    }
}

struct ThreadMessageListView: View {
    let events: [ThreadEvent]
    let filter: ThreadDetailMessageFilter
    let hasUnfilteredEvents: Bool
    let requestCards: [ServerRequestCard]
    let onRequestInputChange: (String, String) -> Void
    let onRequestAction: (String, ServerRequestCardAction) -> Void

    var body: some View {
        if events.isEmpty {
            if hasUnfilteredEvents {
                DetailMessageView(
                    icon: filter.systemImage,
                    title: filter.emptyStateTitle,
                    message: "No rows match this filter."
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
                    ThreadMessageCard(
                        event: event,
                        requestCard: requestCard(for: event),
                        onRequestInputChange: onRequestInputChange,
                        onRequestAction: onRequestAction
                    )
                }
            }
        }
    }

    private func requestCard(for event: ThreadEvent) -> ServerRequestCard? {
        guard event.kind == .request else {
            return nil
        }
        return requestCards.first { card in
            card.id == event.id
                || ((event.turnID != nil || event.itemID != nil)
                    && card.turnID == event.turnID
                    && card.itemID == event.itemID)
        }
    }
}

struct DetailMessageView: View {
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

private struct ThreadMessageCard: View {
    let event: ThreadEvent
    let requestCard: ServerRequestCard?
    let onRequestInputChange: (String, String) -> Void
    let onRequestAction: (String, ServerRequestCardAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Label(event.kind.label, systemImage: event.kind.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(event.kind.color)

                Spacer(minLength: 8)

                statusBadges
            }

            Text(event.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Text(event.body)
                .font(bodyFont)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if let requestCard {
                requestControls(for: requestCard)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var statusBadges: some View {
        if let requestCard {
            statusBadge(requestCard.status.label, color: requestCard.status.color(for: requestCard.kind))
        }
        if event.isLive {
            statusBadge("Live", color: .green)
        }
    }

    private func statusBadge(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }

    @ViewBuilder
    private func requestControls(for card: ServerRequestCard) -> some View {
        if card.detail != event.body {
            Text(card.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }

        if card.needsTextInput {
            TextField(
                "Answer",
                text: Binding(
                    get: { card.inputDraft },
                    set: { onRequestInputChange(card.id, $0) }
                ),
                axis: .vertical
            )
            .lineLimit(1...3)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }

        if case let .failed(message) = card.status {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }

        requestActions(for: card)
    }

    @ViewBuilder
    private func requestActions(for card: ServerRequestCard) -> some View {
        switch card.kind {
        case .commandApproval, .fileChangeApproval, .permissionsApproval:
            HStack(spacing: 8) {
                Button {
                    onRequestAction(card.id, .decline)
                } label: {
                    Label("Decline", systemImage: "xmark")
                }
                .buttonStyle(.bordered)
                .disabled(card.isBusyOrDone)

                Button {
                    onRequestAction(card.id, .accept)
                } label: {
                    Label("Approve", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .disabled(card.isBusyOrDone)
            }
        case .userInput:
            Button {
                onRequestAction(card.id, .submitInput)
            } label: {
                Label("Send", systemImage: "paperplane.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(card.isBusyOrDone || card.inputDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        case .mcpElicitation:
            Button {
                onRequestAction(card.id, .decline)
            } label: {
                Label("Decline", systemImage: "xmark")
            }
            .buttonStyle(.bordered)
            .disabled(card.isBusyOrDone)
        case .unsupported:
            Label("Needs desktop", systemImage: "desktopcomputer")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var bodyFont: Font {
        switch event.kind {
        case .command, .output:
            return .caption.monospaced()
        case .userMessage, .agentMessage, .request, .system, .unknown:
            return .footnote
        }
    }
}

private extension ThreadDetailMessageFilter {
    var systemImage: String {
        selectedKind?.systemImage ?? "line.3.horizontal.decrease.circle"
    }

    var emptyStateTitle: String {
        switch self {
        case .all:
            return "No transcript"
        case .kind(let kind):
            return "No \(kind.label.lowercased()) rows"
        }
    }
}

private extension ThreadEventKind {
    var systemImage: String {
        switch self {
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

    var color: Color {
        switch self {
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

private extension ServerRequestCard {
    var isBusyOrDone: Bool {
        switch status {
        case .responding, .resolved:
            return true
        case .pending, .failed:
            return false
        }
    }
}

private extension ServerRequestCardStatus {
    func color(for kind: ServerRequestCardKind) -> Color {
        switch self {
        case .failed:
            return .red
        case .resolved:
            return .green
        case .responding:
            return .blue
        case .pending:
            switch kind {
            case .commandApproval, .fileChangeApproval, .permissionsApproval, .userInput, .mcpElicitation:
                return .orange
            case .unsupported:
                return .secondary
            }
        }
    }
}

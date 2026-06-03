import SwiftUI

struct MessageTypeFilterControl: View {
    @Binding var filter: ThreadDetailMessageFilter

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
                    filter = .messages
                } label: {
                    Label("Messages", systemImage: ThreadDetailMessageFilter.messages.systemImage)
                }

                Button {
                    filter = .all
                } label: {
                    Label("All", systemImage: ThreadDetailMessageFilter.all.systemImage)
                }

                Divider()

                ForEach(ThreadEventKind.allCases, id: \.self) { kind in
                    Button {
                        filter = .kind(kind)
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
            .accessibilityValue(filter.id)
            .codexAutomationID(AutomationID.Session.messageFilter)

            if filter != .default {
                Button {
                    filter = .default
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityLabel("Reset message type filter")
                .help("Reset filter")
                .codexAutomationID(AutomationID.Session.clearMessageFilter)
            }
        }
    }

    private var currentLabel: String {
        filter.label
    }

    private var currentImage: String {
        filter.systemImage
    }
}

struct ThreadMessageListView: View {
    let rows: [ThreadEventRenderRow]
    let filter: ThreadDetailMessageFilter
    let hasUnfilteredEvents: Bool
    let onRequestInputChange: (String, String) -> Void
    let onRequestAction: (String, ServerRequestCardAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if rows.isEmpty {
                if hasUnfilteredEvents {
                    DetailMessageView(
                        icon: filter.systemImage,
                        title: filter.emptyStateTitle,
                        message: "No rows match this filter.",
                        automationID: AutomationID.Session.state(.noRowsMatch)
                    )
                } else {
                    DetailMessageView(
                        icon: "text.bubble",
                        title: "No transcript",
                        message: "This thread returned no readable events.",
                        automationID: AutomationID.Session.state(.noTranscript)
                    )
                }
            } else {
                ForEach(rows) { row in
                    ThreadMessageCard(
                        event: row.event,
                        requestCard: row.requestCard,
                        onRequestInputChange: onRequestInputChange,
                        onRequestAction: onRequestAction
                    )
                }
            }
        }
        .accessibilityElement(children: .contain)
        .codexAutomationID(AutomationID.Session.messageList)
        .accessibilityValue(messageListAutomationValue)
    }

    private var messageListAutomationValue: String {
        let projectionIDs = rows
            .map { AutomationID.safeSegment($0.event.id) }
            .joined(separator: "|")
        let requestStatuses = rows
            .compactMap { row -> String? in
                guard let requestCard = row.requestCard else {
                    return nil
                }
                return "\(AutomationID.safeSegment(requestCard.id))=\(requestCard.status.label)"
            }
            .joined(separator: "|")
        // This is the canonical rendered detail-list dump for live-update proof:
        // derived from the same rows drawn below, not from a second data path.
        return [
            "events=\(rows.count)",
            "filter=\(filter.id)",
            "projections=\(projectionIDs)",
            "request-statuses=\(requestStatuses)",
        ].joined(separator: "; ")
    }
}

struct DetailMessageView: View {
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
        .frame(maxWidth: .infinity, minHeight: 140)
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityValue(message)
        .codexAutomationID(automationID)
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
                // The visible title carries the canonical row marker because
                // nested request controls can shadow a container identifier in
                // XCUITest. Request cards are decorations on this projection row.
                .accessibilityValue(messageAutomationValue)
                .codexAutomationID(AutomationID.Session.messageCard(projectionID: event.id))

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
        .accessibilityElement(children: .contain)
        .accessibilityValue(messageAutomationValue)
    }

    @ViewBuilder
    private var statusBadges: some View {
        if let requestCard {
            statusBadge(requestCard.status.label, color: requestCard.status.color(for: requestCard.kind))
                .accessibilityValue(requestCard.status.label)
                .codexAutomationID(AutomationID.RequestCard.status(cardID: requestCard.id))
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
        VStack(alignment: .leading, spacing: 8) {
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
                .codexAutomationID(AutomationID.RequestCard.inputField(cardID: card.id))
            }

            if case let .failed(message) = card.status {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .codexAutomationID(AutomationID.RequestCard.error(cardID: card.id))
            }

            requestActions(for: card)
        }
        .accessibilityElement(children: .contain)
        .codexAutomationID(AutomationID.RequestCard.card(cardID: card.id))
        .accessibilityValue(card.automationValue)
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
                .codexAutomationID(AutomationID.RequestCard.declineButton(cardID: card.id))

                Button {
                    onRequestAction(card.id, .accept)
                } label: {
                    Label("Approve", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .disabled(card.isBusyOrDone)
                .codexAutomationID(AutomationID.RequestCard.approveButton(cardID: card.id))
            }
        case .userInput:
            Button {
                onRequestAction(card.id, .submitInput)
            } label: {
                Label("Send", systemImage: "paperplane.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(card.isBusyOrDone || card.inputDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .codexAutomationID(AutomationID.RequestCard.sendButton(cardID: card.id))
        case .mcpElicitation:
            Button {
                onRequestAction(card.id, .decline)
            } label: {
                Label("Decline", systemImage: "xmark")
            }
            .buttonStyle(.bordered)
            .disabled(card.isBusyOrDone)
            .codexAutomationID(AutomationID.RequestCard.declineButton(cardID: card.id))
        case .unsupported:
            Label("Needs desktop", systemImage: "desktopcomputer")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .codexAutomationID(AutomationID.RequestCard.unsupportedState(cardID: card.id))
        }
    }

    private var messageAutomationValue: String {
        [
            "projection=\(event.id)",
            "kind=\(event.kind.rawValue)",
            "visibility=\(event.visibilityCategory.rawValue)",
            "live=\(event.isLive)",
            requestCard.map { "request=\($0.id); request-status=\($0.status.label)" },
        ].compactMap(\.self).joined(separator: "; ")
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
    var label: String {
        switch self {
        case .messages:
            return "Messages"
        case .all:
            return "All"
        case .kind(let kind):
            return kind.label
        }
    }

    var systemImage: String {
        switch self {
        case .messages:
            return "text.bubble"
        case .all:
            return "line.3.horizontal.decrease.circle"
        case .kind(let kind):
            return kind.systemImage
        }
    }

    var emptyStateTitle: String {
        switch self {
        case .messages:
            return "No messages"
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

    var automationValue: String {
        [
            "card=\(id)",
            "kind=\(kind.rawValue)",
            "status=\(status.label)",
            "needs-input=\(needsTextInput)",
        ].joined(separator: "; ")
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

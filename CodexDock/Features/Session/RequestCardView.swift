import SwiftUI

public struct RequestCardsView: View {
    @ObservedObject private var store: ThreadDetailStore

    public init(store: ThreadDetailStore) {
        self.store = store
    }

    public var body: some View {
        if !store.requestCards.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(store.requestCards) { card in
                    RequestCardView(
                        card: card,
                        onInputChange: { store.updateRequestCardInput(cardID: card.id, draft: $0) },
                        onAction: { action in
                            Task {
                                await store.respond(to: card.id, action: action)
                            }
                        }
                    )
                }
            }
        }
    }
}

private struct RequestCardView: View {
    let card: ServerRequestCard
    let onInputChange: (String) -> Void
    let onAction: (ServerRequestCardAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Label(card.title, systemImage: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)

                Spacer(minLength: 8)

                Text(card.status.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(color)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(color.opacity(0.12), in: Capsule())
            }

            Text(card.summary)
                .font(.footnote)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(card.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if card.needsTextInput {
                TextField(
                    "Answer",
                    text: Binding(
                        get: { card.inputDraft },
                        set: { onInputChange($0) }
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

            actions
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var actions: some View {
        switch card.kind {
        case .commandApproval, .fileChangeApproval, .permissionsApproval:
            HStack(spacing: 8) {
                Button {
                    onAction(.decline)
                } label: {
                    Label("Decline", systemImage: "xmark")
                }
                .buttonStyle(.bordered)
                .disabled(isBusyOrDone)

                Button {
                    onAction(.accept)
                } label: {
                    Label("Approve", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBusyOrDone)
            }
        case .userInput:
            Button {
                onAction(.submitInput)
            } label: {
                Label("Send", systemImage: "paperplane.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isBusyOrDone || card.inputDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        case .mcpElicitation:
            Button {
                onAction(.decline)
            } label: {
                Label("Decline", systemImage: "xmark")
            }
            .buttonStyle(.bordered)
            .disabled(isBusyOrDone)
        case .unsupported:
            Label("Needs desktop", systemImage: "desktopcomputer")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var isBusyOrDone: Bool {
        switch card.status {
        case .responding, .resolved:
            return true
        case .pending, .failed:
            return false
        }
    }

    private var icon: String {
        switch card.kind {
        case .commandApproval:
            return "terminal"
        case .fileChangeApproval:
            return "doc.badge.gearshape"
        case .permissionsApproval:
            return "lock.open"
        case .userInput:
            return "text.bubble"
        case .mcpElicitation:
            return "questionmark.bubble"
        case .unsupported:
            return "desktopcomputer"
        }
    }

    private var color: Color {
        switch card.status {
        case .failed:
            return .red
        case .resolved:
            return .green
        case .responding:
            return .blue
        case .pending:
            switch card.kind {
            case .commandApproval, .fileChangeApproval, .permissionsApproval, .userInput, .mcpElicitation:
                return .orange
            case .unsupported:
                return .secondary
            }
        }
    }
}

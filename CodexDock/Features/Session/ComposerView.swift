import SwiftUI

public struct ComposerView: View {
    @ObservedObject private var store: ThreadDetailStore

    public init(store: ThreadDetailStore) {
        self.store = store
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField(
                    "Message Codex",
                    text: Binding(
                        get: { store.composer.draft },
                        set: { store.updateDraft($0) }
                    ),
                    axis: .vertical
                )
                .lineLimit(1...4)
                .autocorrectionDisabled(false)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Button {
                    Task {
                        await store.sendDraft()
                    }
                } label: {
                    if store.composer.isSending {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 22, height: 22)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .frame(width: 22, height: 22)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!store.composer.canSend)
                .accessibilityLabel("Send")
            }

            if let error = store.composer.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

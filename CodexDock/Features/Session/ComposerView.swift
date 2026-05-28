import SwiftUI

public struct ComposerView: View {
    @ObservedObject private var store: ThreadDetailStore
    @State private var isPressingMic = false

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
                .accessibilityLabel("Message")
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                micButton

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
                .frame(minWidth: 44, minHeight: 44)
                .buttonStyle(.borderedProminent)
                .disabled(!store.composer.canSend)
                .accessibilityLabel("Send")
            }

            voiceStatus

            if let error = store.composer.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var micButton: some View {
        Button {} label: {
            Image(systemName: micSystemImage)
                .frame(width: 22, height: 22)
        }
        .frame(minWidth: 44, minHeight: 44)
        .buttonStyle(.bordered)
        .tint(store.composer.voice.phase == .recording ? .red : .blue)
        .disabled(store.composer.isSending || store.composer.voice.phase == .transcribing)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressingMic else {
                        return
                    }
                    isPressingMic = true
                    Task {
                        await store.beginVoiceCapture()
                    }
                }
                .onEnded { _ in
                    isPressingMic = false
                    Task {
                        await store.finishVoiceCapture()
                    }
                }
        )
        .accessibilityLabel("Hold to dictate")
        .accessibilityValue(store.composer.voice.phase.label)
    }

    @ViewBuilder
    private var voiceStatus: some View {
        switch store.composer.voice.phase {
        case .idle:
            if let error = store.composer.voice.lastError {
                Label(error, systemImage: "mic.slash")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .recording:
            Label("Recording. Release to transcribe.", systemImage: "mic.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
        case .transcribing:
            Label("Transcribing", systemImage: "waveform")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.blue)
        }
    }

    private var micSystemImage: String {
        switch store.composer.voice.phase {
        case .idle:
            return "mic"
        case .recording:
            return "mic.fill"
        case .transcribing:
            return "waveform"
        }
    }
}

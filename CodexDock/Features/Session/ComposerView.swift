import SwiftUI

struct ComposerVoiceControlsPresentation: Equatable {
    let holdIcon: String
    let tapIcon: String
    let holdDisabled: Bool
    let tapDisabled: Bool
    let holdAccessibilityLabel: String
    let holdAccessibilityHint: String
    let tapAccessibilityLabel: String
    let tapAccessibilityHint: String
    let accessibilityValue: String
    let statusText: String?
    let statusSystemImage: String?

    init(composer: ComposerState) {
        self.holdIcon = Self.holdIcon(for: composer.voice.phase)
        self.tapIcon = composer.voice.interactionMode == .tap && composer.voice.phase.isBusy
            ? "stop.circle.fill"
            : "mic.circle"
        self.holdDisabled = composer.isSending
            || composer.voice.phase == .finalizing
            || (composer.voice.phase.isBusy && composer.voice.interactionMode != .hold)
        self.tapDisabled = composer.isSending
            || (composer.voice.phase.isBusy && composer.voice.interactionMode != .tap)
            || composer.voice.phase == .finalizing
        self.holdAccessibilityLabel = "Hold to dictate"
        self.holdAccessibilityHint = "Press and hold to stream dictation. Release to finalize."
        let isTapDictationActive = composer.voice.interactionMode == .tap
            && composer.voice.phase.isBusy
        self.tapAccessibilityLabel = isTapDictationActive ? "Stop dictation" : "Start dictation"
        self.tapAccessibilityHint = "Tap once to start dictation and tap again to finalize."
        self.accessibilityValue = composer.voice.phase.label

        switch composer.voice.phase {
        case .idle:
            self.statusText = composer.voice.lastError
            self.statusSystemImage = composer.voice.lastError == nil ? nil : "mic.slash"
        case .starting:
            self.statusText = "Starting dictation"
            self.statusSystemImage = "mic"
        case .streaming:
            self.statusText = composer.voice.interactionMode == .tap
                ? "Listening. Tap stop to finalize."
                : "Listening. Release to finalize."
            self.statusSystemImage = "mic.fill"
        case .finalizing:
            self.statusText = "Finalizing"
            self.statusSystemImage = "waveform"
        }
    }

    private static func holdIcon(for phase: ComposerVoicePhase) -> String {
        switch phase {
        case .idle:
            return "mic"
        case .starting, .streaming:
            return "mic.fill"
        case .finalizing:
            return "waveform"
        }
    }
}

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
                .disabled(!store.composer.canEditDraft)
                .accessibilityLabel("Message")
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .codexAutomationID(AutomationID.Composer.messageField)

                holdMicButton
                tapMicButton

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
                .accessibilityValue(sendButtonAutomationValue)
                .codexAutomationID(AutomationID.Composer.sendButton)
            }

            voiceStatus

            if let error = store.composer.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .codexAutomationID(AutomationID.Composer.composerError)
            }
        }
        .accessibilityElement(children: .contain)
        .codexAutomationID(AutomationID.Composer.root)
        .accessibilityValue(composerAutomationValue)
    }

    private var holdMicButton: some View {
        Button {} label: {
            Image(systemName: voicePresentation.holdIcon)
                .frame(width: 22, height: 22)
        }
        .frame(minWidth: 44, minHeight: 44)
        .buttonStyle(.bordered)
        .tint(.blue)
        .disabled(voicePresentation.holdDisabled)
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
        .accessibilityLabel(voicePresentation.holdAccessibilityLabel)
        .accessibilityHint(voicePresentation.holdAccessibilityHint)
        .accessibilityValue(voicePresentation.accessibilityValue)
        .codexAutomationID(AutomationID.Composer.holdMicButton)
    }

    private var tapMicButton: some View {
        Button {
            Task {
                await store.toggleTapVoiceCapture()
            }
        } label: {
            Image(systemName: voicePresentation.tapIcon)
                .frame(width: 22, height: 22)
        }
        .frame(minWidth: 44, minHeight: 44)
        .buttonStyle(.bordered)
        .tint(.blue)
        .disabled(voicePresentation.tapDisabled)
        .accessibilityLabel(voicePresentation.tapAccessibilityLabel)
        .accessibilityHint(voicePresentation.tapAccessibilityHint)
        .accessibilityValue(voicePresentation.accessibilityValue)
        .codexAutomationID(AutomationID.Composer.tapMicButton)
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
                    .codexAutomationID(AutomationID.Composer.voiceError)
            }
        case .starting:
            Label(voicePresentation.statusText ?? "", systemImage: voicePresentation.statusSystemImage ?? "mic")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.blue)
                .accessibilityValue(voicePresentation.accessibilityValue)
                .codexAutomationID(AutomationID.Composer.voiceStatus)
        case .streaming:
            Label(voicePresentation.statusText ?? "", systemImage: voicePresentation.statusSystemImage ?? "mic.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.blue)
                .accessibilityValue(voicePresentation.accessibilityValue)
                .codexAutomationID(AutomationID.Composer.voiceStatus)
        case .finalizing:
            Label(voicePresentation.statusText ?? "", systemImage: voicePresentation.statusSystemImage ?? "waveform")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.blue)
                .accessibilityValue(voicePresentation.accessibilityValue)
                .codexAutomationID(AutomationID.Composer.voiceStatus)
        }
    }

    private var voicePresentation: ComposerVoiceControlsPresentation {
        ComposerVoiceControlsPresentation(composer: store.composer)
    }

    private var composerAutomationValue: String {
        [
            "can-edit=\(store.composer.canEditDraft)",
            "can-send=\(store.composer.canSend)",
            "sending=\(store.composer.isSending)",
            "voice=\(voicePresentation.accessibilityValue)",
        ].joined(separator: "; ")
    }

    private var sendButtonAutomationValue: String {
        store.composer.isSending ? "sending" : (store.composer.canSend ? "enabled" : "disabled")
    }
}

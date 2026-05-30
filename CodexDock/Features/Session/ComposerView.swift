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
        self.init(renderState: ComposerRenderState(composer: composer))
    }

    init(renderState: ComposerRenderState) {
        self.holdIcon = Self.holdIcon(for: renderState.voice.phase)
        self.tapIcon = renderState.voice.interactionMode == .tap && renderState.voice.phase.isBusy
            ? "stop.circle.fill"
            : "mic.circle"
        self.holdDisabled = renderState.isSending
            || renderState.voice.phase == .finalizing
            || (renderState.voice.phase.isBusy && renderState.voice.interactionMode != .hold)
        self.tapDisabled = renderState.isSending
            || (renderState.voice.phase.isBusy && renderState.voice.interactionMode != .tap)
            || renderState.voice.phase == .finalizing
        self.holdAccessibilityLabel = "Hold to dictate"
        self.holdAccessibilityHint = "Press and hold to stream dictation. Release to finalize."
        let isTapDictationActive = renderState.voice.interactionMode == .tap
            && renderState.voice.phase.isBusy
        self.tapAccessibilityLabel = isTapDictationActive ? "Stop dictation" : "Start dictation"
        self.tapAccessibilityHint = "Tap once to start dictation and tap again to finalize."
        self.accessibilityValue = renderState.voice.phase.label

        switch renderState.voice.phase {
        case .idle:
            self.statusText = renderState.voice.lastError
            self.statusSystemImage = renderState.voice.lastError == nil ? nil : "mic.slash"
        case .starting:
            self.statusText = "Starting dictation"
            self.statusSystemImage = "mic"
        case .streaming:
            self.statusText = renderState.voice.interactionMode == .tap
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
    @ObservedObject private var screenStore: ThreadDetailScreenStore
    @State private var isPressingMic = false
    private let onUpdateDraft: (String) -> Void
    private let onSendDraft: () async -> Void
    private let onBeginVoiceCapture: () async -> Void
    private let onFinishVoiceCapture: () async -> Void
    private let onToggleTapVoiceCapture: () async -> Void

    init(
        screenStore: ThreadDetailScreenStore,
        onUpdateDraft: @escaping (String) -> Void,
        onSendDraft: @escaping () async -> Void,
        onBeginVoiceCapture: @escaping () async -> Void,
        onFinishVoiceCapture: @escaping () async -> Void,
        onToggleTapVoiceCapture: @escaping () async -> Void
    ) {
        self.screenStore = screenStore
        self.onUpdateDraft = onUpdateDraft
        self.onSendDraft = onSendDraft
        self.onBeginVoiceCapture = onBeginVoiceCapture
        self.onFinishVoiceCapture = onFinishVoiceCapture
        self.onToggleTapVoiceCapture = onToggleTapVoiceCapture
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField(
                    "Message Codex",
                    text: Binding(
                        get: { screenStore.composerRenderState.draft },
                        set: { onUpdateDraft($0) }
                    ),
                    axis: .vertical
                )
                .lineLimit(1...4)
                .autocorrectionDisabled(false)
                .disabled(!screenStore.composerRenderState.canEditDraft)
                .accessibilityLabel("Message")
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .codexAutomationID(AutomationID.Composer.messageField)

                holdMicButton
                tapMicButton

                Button {
                    Task {
                        await onSendDraft()
                    }
                } label: {
                    if screenStore.composerRenderState.isSending {
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
                .disabled(!screenStore.composerRenderState.canSend)
                .accessibilityLabel("Send")
                .accessibilityValue(sendButtonAutomationValue)
                .codexAutomationID(AutomationID.Composer.sendButton)
            }

            voiceStatus

            if let error = screenStore.composerRenderState.lastError {
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
                        await onBeginVoiceCapture()
                    }
                }
                .onEnded { _ in
                    isPressingMic = false
                    Task {
                        await onFinishVoiceCapture()
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
                await onToggleTapVoiceCapture()
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
        switch screenStore.composerRenderState.voice.phase {
        case .idle:
            if let error = screenStore.composerRenderState.voice.lastError {
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
        ComposerVoiceControlsPresentation(renderState: screenStore.composerRenderState)
    }

    private var composerAutomationValue: String {
        [
            "can-edit=\(screenStore.composerRenderState.canEditDraft)",
            "can-send=\(screenStore.composerRenderState.canSend)",
            "sending=\(screenStore.composerRenderState.isSending)",
            "voice=\(voicePresentation.accessibilityValue)",
        ].joined(separator: "; ")
    }

    private var sendButtonAutomationValue: String {
        screenStore.composerRenderState.isSending ? "sending" : (screenStore.composerRenderState.canSend ? "enabled" : "disabled")
    }
}

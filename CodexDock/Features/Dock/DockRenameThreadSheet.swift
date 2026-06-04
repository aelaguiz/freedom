import SwiftUI

struct DockRenameDraft: Identifiable {
    let row: DockRowViewModel

    var id: String {
        row.id
    }

    var initialName: String {
        row.title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct DockRenameThreadSheet: View {
    let draft: DockRenameDraft
    let isSaving: Bool
    let onCancel: @MainActor () -> Void
    let onSave: @MainActor (String) -> Bool

    @State private var name: String
    @FocusState private var isNameFieldFocused: Bool

    init(
        draft: DockRenameDraft,
        isSaving: Bool,
        onCancel: @escaping @MainActor () -> Void,
        onSave: @escaping @MainActor (String) -> Bool
    ) {
        self.draft = draft
        self.isSaving = isSaving
        self.onCancel = onCancel
        self.onSave = onSave
        _name = State(initialValue: draft.initialName)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .disabled(isSaving)
                .codexAutomationID(AutomationID.Dock.renameCancelButton)

                Spacer(minLength: 8)

                Text("Rename Thread")
                    .font(.headline)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Button {
                    saveIfPossible()
                } label: {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Save")
                    }
                }
                .disabled(!canSave)
                .codexAutomationID(AutomationID.Dock.renameSaveButton)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            nameField
                .padding(16)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 8)
        .accessibilityElement(children: .contain)
        .codexAutomationID(AutomationID.Dock.renameSheet)
        .onAppear {
            isNameFieldFocused = true
        }
        #if os(iOS)
        .textFieldStyle(.roundedBorder)
        #endif
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !isSaving && !trimmedName.isEmpty && trimmedName != draft.initialName
    }

    @ViewBuilder
    private var nameField: some View {
        #if os(iOS)
        TextField("Name", text: $name)
            .textInputAutocapitalization(.sentences)
            .autocorrectionDisabled()
            .focused($isNameFieldFocused)
            .submitLabel(.done)
            .disabled(isSaving)
            .onSubmit {
                saveIfPossible()
            }
            .codexAutomationID(AutomationID.Dock.renameNameField)
        #else
        TextField("Name", text: $name)
            .focused($isNameFieldFocused)
            .disabled(isSaving)
            .onSubmit {
                saveIfPossible()
            }
            .codexAutomationID(AutomationID.Dock.renameNameField)
        #endif
    }

    private func saveIfPossible() {
        guard canSave else {
            return
        }
        let nextName = trimmedName
        isNameFieldFocused = false
        _ = onSave(nextName)
    }
}

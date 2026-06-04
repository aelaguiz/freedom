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
    let onSave: @MainActor (String) async -> Bool

    @State private var name: String
    @FocusState private var isNameFieldFocused: Bool

    init(
        draft: DockRenameDraft,
        isSaving: Bool,
        onCancel: @escaping @MainActor () -> Void,
        onSave: @escaping @MainActor (String) async -> Bool
    ) {
        self.draft = draft
        self.isSaving = isSaving
        self.onCancel = onCancel
        self.onSave = onSave
        _name = State(initialValue: draft.initialName)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    nameField
                }
            }
            .navigationTitle("Rename Thread")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .disabled(isSaving)
                    .codexAutomationID(AutomationID.Dock.renameCancelButton)
                }

                ToolbarItem(placement: .confirmationAction) {
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
            }
            .onAppear {
                isNameFieldFocused = true
            }
        }
        .codexAutomationID(AutomationID.Dock.renameSheet)
        #if os(iOS)
        .presentationDetents([.height(220), .medium])
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
            .autocorrectionDisabled(false)
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
        Task {
            _ = await onSave(nextName)
        }
    }
}

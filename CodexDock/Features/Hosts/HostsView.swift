import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

public struct HostsView: View {
    @ObservedObject private var store: HostSettingsStore
    @State private var draft = HostDraft()
    @State private var editingHostID: String?
    @State private var validationMessage: String?

    public init(store: HostSettingsStore) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    content
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 24)
            }
            .background(hostsBackgroundColor)
            .dockNavigationChrome()
        }
        .accessibilityElement(children: .contain)
        .codexAutomationID(AutomationID.Relay.root)
        .accessibilityValue(relayScreenValue)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Relay")
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(.primary)

            Spacer(minLength: 12)

            Button {
                Task {
                    await store.testAll()
                }
            } label: {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.bordered)
            .disabled(store.rows.isEmpty)
            .accessibilityLabel("Test relay connections")
            .codexAutomationID(AutomationID.Relay.testAllButton)
        }
    }

    private var hostsBackgroundColor: Color {
        #if os(iOS)
        Color(uiColor: .systemGroupedBackground)
        #elseif os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(.background)
        #endif
    }

    @ViewBuilder
    private var content: some View {
        if let configurationError = store.configurationError {
            DockMessageView(
                icon: "exclamationmark.triangle",
                title: "Relay not configured",
                message: configurationError,
                automationID: AutomationID.Relay.state(.configurationError)
            )
        } else {
            hostRows
            hostEditor
        }
    }

    private var hostRows: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(store.rows) { row in
                HostSettingsRow(
                    row: row,
                    onTest: {
                        Task {
                            await store.test(row.id)
                        }
                    },
                    onEdit: {
                        editingHostID = row.id
                        draft = HostDraft(host: row.host)
                        validationMessage = nil
                    },
                    onRemove: {
                        Task {
                            do {
                                try await store.removeHost(row.id)
                                if editingHostID == row.id {
                                    editingHostID = nil
                                    draft = HostDraft()
                                }
                            } catch {
                                validationMessage = error.localizedDescription
                            }
                        }
                    }
                )
            }
        }
    }

    private var hostEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(editingHostID == nil ? "Add Relay" : "Edit Relay")
                    .font(.headline)
                Spacer()
                if editingHostID != nil {
                    Button {
                        editingHostID = nil
                        draft = HostDraft()
                        validationMessage = nil
                    } label: {
                        Label("Cancel", systemImage: "xmark")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .codexAutomationID(AutomationID.Relay.cancelButton)
                }
            }

            VStack(spacing: 10) {
                HostTextField(
                    title: "Host",
                    text: $draft.host,
                    automationID: AutomationID.Relay.hostField
                )
                HostTextField(
                    title: "Port",
                    text: $draft.port,
                    automationID: AutomationID.Relay.portField
                )
            }

            if let validationMessage {
                ActionErrorBanner(
                    message: validationMessage,
                    automationID: AutomationID.Relay.state(.validationError)
                )
            }

            Button {
                saveDraft()
            } label: {
                Label("Save Relay", systemImage: "square.and.arrow.down")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .codexAutomationID(AutomationID.Relay.saveButton)
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .contain)
        .codexAutomationID(AutomationID.Relay.editor)
        .accessibilityValue(editingHostID == nil ? "add" : "edit; host=\(editingHostID ?? "")")
    }

    private func saveDraft() {
        Task { @MainActor in
            do {
                try await store.saveHost(
                    replacing: editingHostID,
                    host: draft.host,
                    port: draft.port
                )
                editingHostID = nil
                draft = HostDraft()
                validationMessage = nil
            } catch {
                validationMessage = error.localizedDescription
            }
        }
    }

    private var relayScreenValue: String {
        if store.configurationError != nil {
            return "configuration-error"
        }
        return "loaded; hosts=\(store.rows.count); editor=\(editingHostID == nil ? "add" : "edit")"
    }
}

private struct HostSettingsRow: View {
    let row: HostSettingsRowViewModel
    let onTest: () -> Void
    let onEdit: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 24))
                    .foregroundStyle(statusColor)
                    .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text(row.displayHost.displayName)
                        .font(.headline)
                    Text(row.displayHost.endpoint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Text(row.status.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                .layoutPriority(1)

                Spacer(minLength: 8)

                Text(row.status.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.12), in: Capsule())
                    .fixedSize()
            }

            HStack(spacing: 8) {
                Button(action: onTest) {
                    Label("Test", systemImage: "network")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .disabled(row.status == .testing)
                .codexAutomationID(AutomationID.Relay.rowTestButton(hostID: row.id))

                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .codexAutomationID(AutomationID.Relay.rowEditButton(hostID: row.id))

                Button(role: .destructive, action: onRemove) {
                    Label("Remove", systemImage: "trash")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .codexAutomationID(AutomationID.Relay.rowRemoveButton(hostID: row.id))
            }
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityValue("\(row.id); \(row.status.title); \(row.status.detail)")
        .codexAutomationID(AutomationID.Relay.row(hostID: row.id))
    }

    private var statusColor: Color {
        switch row.status {
        case .notChecked:
            return .secondary
        case .testing:
            return .blue
        case .online:
            return .green
        case .offline:
            return .orange
        case .error:
            return .red
        }
    }
}

private struct HostTextField: View {
    let title: String
    @Binding var text: String
    var isSecure = false
    var automationID: AutomationID? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            editableField
                .font(.subheadline)
                .padding(.horizontal, 10)
                .frame(height: 40)
                .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .codexAutomationID(automationID)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var editableField: some View {
        #if os(iOS)
        field
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        field
        #endif
    }

    @ViewBuilder
    private var field: some View {
        if isSecure {
            SecureField(title, text: $text)
        } else {
            TextField(title, text: $text)
        }
    }
}

private struct HostDraft: Equatable {
    var host = ""
    var port = CodexDockConstants.Ports.dockRelayString

    init() {}

    init(host: DockHostConfiguration) {
        self.host = host.endpoint.host
        self.port = String(host.endpoint.port)
    }
}

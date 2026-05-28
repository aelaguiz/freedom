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
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Hosts")
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
            .accessibilityLabel("Test all hosts")
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
                title: "Host not configured",
                message: configurationError
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
                    }
                )
            }
        }
    }

    private var hostEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(editingHostID == nil ? "Add Host" : "Edit Host")
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
                }
            }

            VStack(spacing: 10) {
                HostTextField(title: "ID", text: $draft.id)
                HostTextField(title: "Name", text: $draft.displayName)
                HostTextField(title: "WebSocket", text: $draft.webSocketURL)
                HostTextField(title: "Token", text: $draft.bearerToken, isSecure: true)
            }

            if let validationMessage {
                ActionErrorBanner(message: validationMessage)
            }

            Button {
                saveDraft()
            } label: {
                Label("Save Host", systemImage: "square.and.arrow.down")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func saveDraft() {
        do {
            try store.saveHost(
                replacing: editingHostID,
                id: draft.id,
                displayName: draft.displayName,
                webSocketURL: draft.webSocketURL,
                bearerToken: draft.bearerToken
            )
            editingHostID = nil
            draft = HostDraft()
            validationMessage = nil
        } catch {
            validationMessage = error.localizedDescription
        }
    }
}

private struct HostSettingsRow: View {
    let row: HostSettingsRowViewModel
    let onTest: () -> Void
    let onEdit: () -> Void

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

                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
        }
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
    var id = ""
    var displayName = ""
    var webSocketURL = ""
    var bearerToken = ""

    init() {}

    init(host: DockHostConfiguration) {
        self.id = host.id
        self.displayName = host.displayName
        self.webSocketURL = host.webSocketURL.absoluteString
        self.bearerToken = host.bearerToken
    }
}

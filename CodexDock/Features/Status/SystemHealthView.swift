import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

public struct SystemHealthView<RelaySettingsDestination: View>: View {
    @ObservedObject private var store: AppConnectivityStore
    private let onOpenRelaySettings: @MainActor () -> Void
    private let relaySettingsDestination: (() -> RelaySettingsDestination)?
    private let onClose: @MainActor () -> Void
    private let projector = SystemHealthProjector()
    @State private var didRequestInitialDiagnostics = false

    public init(
        store: AppConnectivityStore,
        onOpenRelaySettings: @escaping @MainActor () -> Void = {},
        @ViewBuilder relaySettingsDestination: @escaping () -> RelaySettingsDestination,
        onClose: @escaping @MainActor () -> Void = {}
    ) {
        self.store = store
        self.onOpenRelaySettings = onOpenRelaySettings
        self.relaySettingsDestination = relaySettingsDestination
        self.onClose = onClose
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    summaryCard
                    categoryGrid
                    hostCards
                    actions
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 24)
            }
            .background(backgroundColor)
            .dockNavigationChrome()
            .navigationTitle("System Health")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onClose)
                        .codexAutomationID(AutomationID.SystemHealth.closeButton)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task {
                            await store.refreshRelayDiagnostics()
                        }
                    } label: {
                        Label("Run check", systemImage: "arrow.clockwise")
                    }
                    .codexAutomationID(AutomationID.SystemHealth.runCheckButton)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .codexAutomationID(AutomationID.SystemHealth.root)
        .accessibilityValue("\(snapshot.summary.label): \(snapshot.summary.message)")
        .task {
            guard !didRequestInitialDiagnostics else {
                return
            }
            didRequestInitialDiagnostics = true
            await store.refreshRelayDiagnostics()
        }
    }

    private var snapshot: SystemHealthSnapshot {
        projector.snapshot(hosts: store.hosts, overallStatus: store.overallStatus)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(snapshot.summary.label)
                .font(.title2.weight(.semibold))
            Text(snapshot.summary.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .codexAutomationID(AutomationID.SystemHealth.summary)
    }

    private var categoryGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
            ForEach(snapshot.categories) { category in
                VStack(alignment: .leading, spacing: 6) {
                    Text(category.category.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(category.status.label)
                        .font(.subheadline.weight(.semibold))
                    Text(category.status.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
                .padding(12)
                .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityElement(children: .combine)
                .accessibilityLabel(category.category.title)
                .accessibilityValue("\(category.status.label). \(category.status.detail)")
                .codexAutomationID(AutomationID.SystemHealth.category(category.category.rawValue))
            }
        }
    }

    private var hostCards: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Hosts")
                .font(.headline)
            if snapshot.hosts.isEmpty {
                DockMessageView(
                    icon: "desktopcomputer",
                    title: "No relay hosts",
                    message: "Add a relay host in Relay Settings.",
                    automationID: AutomationID.SystemHealth.state(.empty)
                )
            } else {
                ForEach(snapshot.hosts) { host in
                    NavigationLink {
                        SystemHealthHostDetailView(host: host)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: host.phase.isOnlineLike ? "checkmark.circle" : "exclamationmark.triangle")
                                .foregroundStyle(host.phase.isOnlineLike ? .green : .orange)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(host.displayName)
                                    .font(.subheadline.weight(.semibold))
                                Text(host.endpoint)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(host.phase.message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(host.displayName) health")
                    .accessibilityValue(host.phase.message)
                    .codexAutomationID(AutomationID.SystemHealth.hostCard(hostID: host.id))
                }
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            relaySettingsAction

            Button {
                copyDoctorCommand()
            } label: {
                Label("Copy doctor command", systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .codexAutomationID(AutomationID.SystemHealth.copyDoctorButton)
        }
    }

    @ViewBuilder
    private var relaySettingsAction: some View {
        if let relaySettingsDestination {
            NavigationLink {
                relaySettingsDestination()
            } label: {
                Label("Relay settings", systemImage: "desktopcomputer")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .codexAutomationID(AutomationID.SystemHealth.relaySettingsButton)
        } else {
            Button {
                onOpenRelaySettings()
            } label: {
                Label("Relay settings", systemImage: "desktopcomputer")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .codexAutomationID(AutomationID.SystemHealth.relaySettingsButton)
        }
    }

    private var backgroundColor: Color {
        #if os(iOS)
        Color(uiColor: .systemGroupedBackground)
        #elseif os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(.background)
        #endif
    }

    private func copyDoctorCommand() {
        #if os(iOS)
        UIPasteboard.general.string = "rtk make relay-doctor"
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("rtk make relay-doctor", forType: .string)
        #endif
    }
}

public extension SystemHealthView where RelaySettingsDestination == EmptyView {
    init(
        store: AppConnectivityStore,
        onOpenRelaySettings: @escaping @MainActor () -> Void = {},
        onClose: @escaping @MainActor () -> Void = {}
    ) {
        self.store = store
        self.onOpenRelaySettings = onOpenRelaySettings
        self.relaySettingsDestination = nil
        self.onClose = onClose
    }
}

private struct SystemHealthHostDetailView: View {
    let host: HostConnectivitySnapshot

    var body: some View {
        List {
            Section("Status") {
                LabeledContent("Host", value: host.displayName)
                LabeledContent("Endpoint", value: host.endpoint)
                LabeledContent("State", value: host.phase.message)
            }

            Section("Technical Evidence") {
                if host.routeDiagnostics.isEmpty {
                    Text("No route evidence yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(host.routeDiagnostics, id: \.route) { diagnostic in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(diagnostic.route)
                                .font(.subheadline.weight(.semibold))
                            Text(diagnostic.routeStatus.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let reason = diagnostic.statusReasons.first {
                                Text(reason.message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(host.displayName)
        .codexAutomationID(AutomationID.SystemHealth.hostDetail(hostID: host.id))
    }
}

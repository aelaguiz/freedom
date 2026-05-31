import Foundation
import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

public struct CodexDockBootstrapView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store: RelayBootstrapStore
    @StateObject private var lifecycleCoordinator: AppLifecycleCoordinator
    @StateObject private var connectivityStore: AppConnectivityStore

    public init(store: RelayBootstrapStore = RelayBootstrapStore()) {
        _store = StateObject(wrappedValue: store)
        _lifecycleCoordinator = StateObject(wrappedValue: AppLifecycleCoordinator())
        _connectivityStore = StateObject(wrappedValue: AppConnectivityStore())
    }

    public var body: some View {
        content
            .task {
                connectivityStore.reportBootstrapState(store.state)
                store.start()
                store.handleLifecycle(lifecycleCoordinator.snapshot)
                connectivityStore.reportBootstrapState(store.state)
            }
            .onChange(of: scenePhase) { _, scenePhase in
                lifecycleCoordinator.handle(appScenePhase(from: scenePhase))
                store.handleLifecycle(lifecycleCoordinator.snapshot)
                connectivityStore.reportLifecycle(lifecycleCoordinator.snapshot)
                connectivityStore.reportBootstrapState(store.state)
            }
            .onChange(of: store.state) { _, state in
                connectivityStore.reportBootstrapState(state)
            }
            .overlay(alignment: .topTrailing) {
                if !isReady {
                    GlobalConnectivityIndicatorView(store: connectivityStore)
                        .padding(.top, 8)
                        .padding(.trailing, 16)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch store.state {
        case .starting:
            RelaySetupView(
                title: "Connecting",
                message: "Finding Codex Dock relay",
                automationState: .starting,
                relays: [],
                manualHostText: $store.manualHostText,
                manualPortText: $store.manualPortText,
                onUseRelay: { _ in },
                onManualConnect: {
                    Task {
                        await store.connectManually()
                    }
                }
            )
        case let .discovering(relays, message):
            RelaySetupView(
                title: "Relay",
                message: message ?? "Finding Codex Dock relay",
                automationState: .discovering,
                relays: relays,
                manualHostText: $store.manualHostText,
                manualPortText: $store.manualPortText,
                onUseRelay: { relay in
                    Task {
                        await store.use(relay)
                    }
                },
                onManualConnect: {
                    Task {
                        await store.connectManually()
                    }
                }
            )
        case .ready(let registry):
            CodexDockRootView(
                runtime: ClientRuntime(registry: registry),
                streamClient: streamClient,
                threadDetailFactory: threadDetailFactory,
                lifecycleCoordinator: lifecycleCoordinator,
                connectivityStore: connectivityStore
            )
                .id(registry.hosts.map(\.id).joined(separator: "|"))
        case .failed(let message):
            RelaySetupView(
                title: "Relay Error",
                message: message,
                automationState: .failed,
                relays: [],
                manualHostText: $store.manualHostText,
                manualPortText: $store.manualPortText,
                onUseRelay: { _ in },
                onManualConnect: {
                    Task {
                        await store.connectManually()
                    }
                }
            )
        }
    }

    private var isReady: Bool {
        if case .ready = store.state {
            return true
        }
        return false
    }

    private var streamClient: any ThreadCardStreamConnecting {
        #if DEBUG
        if let rawScenario = ProcessInfo.processInfo.environment["CODEX_DOCK_UI_DOCK_STREAM_SCENARIO"],
           let scenario = ScriptedDockStreamScenario(rawValue: rawScenario) {
            DockLog.dock.notice("dock scripted stream enabled scenario=\(scenario.rawValue, privacy: .public)")
            return ScriptedDockStreamClient(scenario: scenario)
        }
        #endif
        return AppServerThreadCardStreamClient()
    }

    private var threadDetailFactory: any ThreadDetailSessionMaking {
        #if DEBUG
        if let rawScenario = ProcessInfo.processInfo.environment["CODEX_DOCK_UI_DOCK_STREAM_SCENARIO"],
           let scenario = ScriptedDockStreamScenario(rawValue: rawScenario) {
            return ScriptedThreadDetailSessionFactory(scenario: scenario)
        }
        #endif
        return AppServerThreadDetailSessionFactory()
    }

    private func appScenePhase(from scenePhase: ScenePhase) -> AppScenePhase {
        switch scenePhase {
        case .active:
            return .active
        case .inactive:
            return .inactive
        case .background:
            return .background
        @unknown default:
            return .inactive
        }
    }
}

private struct RelaySetupView: View {
    let title: String
    let message: String
    let automationState: AutomationID.StateKind
    let relays: [DiscoveredRelay]
    @Binding var manualHostText: String
    @Binding var manualPortText: String
    let onUseRelay: (DiscoveredRelay) -> Void
    let onManualConnect: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    relayList
                    manualEntry
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 24)
            }
            .background(backgroundColor)
            .dockNavigationChrome()
        }
        .accessibilityElement(children: .contain)
        .codexAutomationID(AutomationID.Bootstrap.root)
        .accessibilityValue("\(automationState.rawValue); \(message)")
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.largeTitle.weight(.semibold))
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            .layoutPriority(1)

            Spacer(minLength: 8)
        }
    }

    @ViewBuilder
    private var relayList: some View {
        if relays.isEmpty {
            DockMessageView(
                icon: "wifi",
                title: "Searching",
                message: "No Codex Dock relay is visible on this network.",
                automationID: AutomationID.Bootstrap.state(automationState)
            )
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(relays) { relay in
                    Button {
                        onUseRelay(relay)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "desktopcomputer")
                                .font(.system(size: 24))
                                .foregroundStyle(.blue)
                                .frame(width: 30, height: 30)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(relay.displayName)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(relay.endpoint.displayEndpoint)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .layoutPriority(1)

                            Spacer(minLength: 8)

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue("\(relay.id); \(relay.endpoint.displayEndpoint)")
                    .codexAutomationID(AutomationID.Bootstrap.discoveredRelayRow(relay.id))
                }
            }
        }
    }

    private var manualEntry: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Manual Relay")
                .font(.headline)

            HStack(spacing: 8) {
                Image(systemName: "link")
                    .foregroundStyle(.secondary)
                manualHostField
                manualPortField
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Button {
                onManualConnect()
            } label: {
                Label("Connect", systemImage: "arrow.right.circle")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .disabled(manualHostText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || manualPortText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .codexAutomationID(AutomationID.Bootstrap.manualConnectButton)
        }
    }

    @ViewBuilder
    private var manualHostField: some View {
        #if os(iOS)
        TextField("192.168.50.117", text: $manualHostText)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
            .codexAutomationID(AutomationID.Bootstrap.manualHostField)
        #else
        TextField("192.168.50.117", text: $manualHostText)
            .codexAutomationID(AutomationID.Bootstrap.manualHostField)
        #endif
    }

    @ViewBuilder
    private var manualPortField: some View {
        #if os(iOS)
        TextField(CodexDockConstants.Ports.dockRelayString, text: $manualPortText)
            .keyboardType(.numberPad)
            .frame(width: 72)
            .codexAutomationID(AutomationID.Bootstrap.manualPortField)
        #else
        TextField(CodexDockConstants.Ports.dockRelayString, text: $manualPortText)
            .frame(width: 72)
            .codexAutomationID(AutomationID.Bootstrap.manualPortField)
        #endif
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
}

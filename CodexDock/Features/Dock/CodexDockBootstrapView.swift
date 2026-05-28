import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

public struct CodexDockBootstrapView: View {
    @StateObject private var store: RelayBootstrapStore

    public init(store: RelayBootstrapStore = RelayBootstrapStore()) {
        _store = StateObject(wrappedValue: store)
    }

    public var body: some View {
        content
            .task {
                store.start()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch store.state {
        case .starting:
            RelaySetupView(
                title: "Connecting",
                message: "Finding Codex Dock relay",
                relays: [],
                manualURLText: $store.manualURLText,
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
                relays: relays,
                manualURLText: $store.manualURLText,
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
            CodexDockRootView(registry: registry)
                .id(registry.hosts.map(\.id).joined(separator: "|"))
        case .failed(let message):
            RelaySetupView(
                title: "Relay Error",
                message: message,
                relays: [],
                manualURLText: $store.manualURLText,
                onUseRelay: { _ in },
                onManualConnect: {
                    Task {
                        await store.connectManually()
                    }
                }
            )
        }
    }
}

private struct RelaySetupView: View {
    let title: String
    let message: String
    let relays: [DiscoveredRelay]
    @Binding var manualURLText: String
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
                message: "No Codex Dock relay is visible on this network."
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
                                Text(relay.webSocketURL.absoluteString)
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
                manualField
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
            .disabled(manualURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    @ViewBuilder
    private var manualField: some View {
        #if os(iOS)
        TextField("ws://192.168.50.117:4510", text: $manualURLText)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
        #else
        TextField("ws://192.168.50.117:4510", text: $manualURLText)
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

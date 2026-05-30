import SwiftUI

struct DockTaskMenuView: View {
    let onOpenArchiveCleanup: @MainActor () -> Void
    let onOpenArchivedThreads: @MainActor () -> Void
    let onOpenSystemHealth: @MainActor () -> Void
    let onOpenRelaySettings: @MainActor () -> Void

    var body: some View {
        Menu {
            Button {
                onOpenArchiveCleanup()
            } label: {
                Label("Archive cleanup", systemImage: "archivebox")
            }
            .codexAutomationID(AutomationID.TaskSheet.menuItem(.archiveCleanup))

            Button {
                onOpenArchivedThreads()
            } label: {
                Label("Archived threads", systemImage: "clock.arrow.circlepath")
            }
            .codexAutomationID(AutomationID.TaskSheet.menuItem(.archivedThreads))

            Button {
                onOpenSystemHealth()
            } label: {
                Label("System health", systemImage: "heart.text.square")
            }
            .codexAutomationID(AutomationID.TaskSheet.menuItem(.systemHealth))

            Button {
                onOpenRelaySettings()
            } label: {
                Label("Relay settings", systemImage: "desktopcomputer")
            }
            .codexAutomationID(AutomationID.TaskSheet.menuItem(.relaySettings))
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 22, weight: .semibold))
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("More")
        .codexAutomationID(AutomationID.TaskSheet.moreButton)
    }
}

import SwiftUI

struct DockRowContextMenu: View {
    let row: DockRowViewModel
    let store: DockStore
    let onRename: @MainActor (DockRowViewModel) -> Void
    let onArchiveSucceeded: @MainActor () async -> Void

    var body: some View {
        Button(role: row.isPinned ? .destructive : nil) {
            Task {
                await store.setPinned(!row.isPinned, for: row)
            }
        } label: {
            Label(row.isPinned ? "Unpin" : "Pin", systemImage: row.isPinned ? "pin.slash" : "pin.fill")
        }
        .codexAutomationID(
            AutomationID.Dock.rowAction(
                hostID: row.hostID,
                threadID: row.threadID,
                action: row.isPinned ? .unpin : .pin
            )
        )

        Button {
            onRename(row)
        } label: {
            Label("Rename", systemImage: "pencil")
        }
        .codexAutomationID(
            AutomationID.Dock.rowAction(
                hostID: row.hostID,
                threadID: row.threadID,
                action: .rename
            )
        )

        Button {
            Task {
                await store.setLabel("Watch", for: row)
            }
        } label: {
            Label("Mark Watch", systemImage: "tag")
        }
        .codexAutomationID(
            AutomationID.Dock.rowAction(
                hostID: row.hostID,
                threadID: row.threadID,
                action: .markWatch
            )
        )

        Button {
            Task {
                await store.setLabel(nil, for: row)
            }
        } label: {
            Label("Clear Label", systemImage: "tag.slash")
        }
        .codexAutomationID(
            AutomationID.Dock.rowAction(
                hostID: row.hostID,
                threadID: row.threadID,
                action: .clearLabel
            )
        )

        Button(role: .destructive) {
            Task {
                if await store.archive(row) {
                    await onArchiveSucceeded()
                }
            }
        } label: {
            Label("Archive", systemImage: "archivebox")
        }
        .codexAutomationID(
            AutomationID.Dock.rowAction(
                hostID: row.hostID,
                threadID: row.threadID,
                action: .archive
            )
        )

        Menu {
            ForEach(DockRowRail.allCases, id: \.self) { rail in
                Button {
                    Task {
                        await store.setRail(rail, for: row)
                    }
                } label: {
                    Label(rail.label, systemImage: rail.systemImage)
                }
                .codexAutomationID(
                    AutomationID.Dock.rowColorAction(
                        hostID: row.hostID,
                        threadID: row.threadID,
                        rail: rail.rawValue
                    )
                )
            }

            Button {
                Task {
                    await store.setRail(nil, for: row)
                }
            } label: {
                Label("Clear Color", systemImage: "circle.slash")
            }
            .codexAutomationID(
                AutomationID.Dock.rowAction(
                    hostID: row.hostID,
                    threadID: row.threadID,
                    action: .clearColor
                )
            )
        } label: {
            Label("Color", systemImage: "paintpalette")
        }
        .codexAutomationID(
            AutomationID.Dock.rowAction(
                hostID: row.hostID,
                threadID: row.threadID,
                action: .color
            )
        )
    }
}

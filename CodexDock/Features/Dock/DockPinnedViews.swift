import SwiftUI

struct DockSwipeActionRow<Content: View>: View {
    let row: DockRowViewModel
    let actionID: AutomationID
    let onTogglePinned: () -> Void
    let canOpen: Bool
    let onOpen: () -> Void
    @ViewBuilder var content: () -> Content
    @State private var offset: CGFloat = 0

    private let actionWidth: CGFloat = 86

    var body: some View {
        ZStack(alignment: .trailing) {
            if offset != 0 {
                swipeButton
            }

            content()
                .offset(x: offset)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(dragGesture)
        .onTapGesture(perform: handleTap)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(row.title)
        .accessibilityValue(row.automationValue)
        .accessibilityAddTraits(canOpen ? .isButton : [])
        .accessibilityAction {
            handleTap()
        }
        .codexAutomationID(AutomationID.Dock.row(hostID: row.id.hostID, threadID: row.id.threadID))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 18, coordinateSpace: .local)
            .onChanged(updateOffset)
            .onEnded(finishDrag)
    }

    private var swipeButton: some View {
        Button(role: row.isPinned ? .destructive : nil) {
            closeAction()
            onTogglePinned()
        } label: {
            Label(row.isPinned ? "Unpin" : "Pin", systemImage: row.isPinned ? "pin.slash" : "pin.fill")
                .font(.caption.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .frame(width: actionWidth)
                .frame(maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(row.isPinned ? Color.red : Color.blue)
        .codexAutomationID(actionID)
    }

    private func updateOffset(_ value: DragGesture.Value) {
        guard abs(value.translation.width) > abs(value.translation.height) else {
            return
        }
        offset = min(0, max(-actionWidth, value.translation.width))
    }

    private func finishDrag(_ value: DragGesture.Value) {
        let shouldOpen = value.translation.width < -(actionWidth * 0.35)
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            offset = shouldOpen ? -actionWidth : 0
        }
    }

    private func handleTap() {
        if offset != 0 {
            closeAction()
        } else if canOpen {
            onOpen()
        }
    }

    private func closeAction() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            offset = 0
        }
    }
}

struct PinnedThreadsManageView: View {
    let rows: [DockRowViewModel]
    let onUnpin: (DockRowViewModel) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 10) {
                    if rows.isEmpty {
                        DockMessageView(
                            icon: "pin.slash",
                            title: "No pinned threads",
                            message: "Pinned threads will appear here."
                        )
                    } else {
                        ForEach(rows) { row in
                            pinnedRow(row)
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("Pinned")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Manage pinned threads")
        .codexAutomationID(AutomationID.Dock.pinnedManageSheet)
    }

    private func pinnedRow(_ row: DockRowViewModel) -> some View {
        HStack(alignment: .top, spacing: 10) {
            DockRowView(row: row, showsPinIndicator: true)
                .accessibilityValue(row.automationValue)
                .codexAutomationID(AutomationID.Dock.pinnedManageRow(hostID: row.id.hostID, threadID: row.id.threadID))
                .layoutPriority(1)

            Button(role: .destructive) {
                onUnpin(row)
            } label: {
                Image(systemName: "pin.slash")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Unpin thread")
            .codexAutomationID(
                AutomationID.Dock.pinnedManageUnpinButton(
                    hostID: row.id.hostID,
                    threadID: row.id.threadID
                )
            )
        }
    }
}

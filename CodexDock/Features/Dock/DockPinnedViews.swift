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
        .codexAutomationID(AutomationID.Dock.row(hostID: row.hostID, threadID: row.threadID))
        // Parent ForEach owns row identity. Do not add a nested .id here;
        // live reorders can otherwise leave stale duplicate accessibility rows.
        .onChange(of: row.id) { _, _ in
            closeAction(animated: false)
        }
        .onChange(of: row.isPinned) { _, _ in
            closeAction(animated: false)
        }
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

    private func closeAction(animated: Bool = true) {
        // A live Dock update should not reset the action surface. Only close
        // when the user acts or the row's semantic identity/pin state changes.
        guard offset != 0 else {
            return
        }
        if animated {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                offset = 0
            }
        } else {
            offset = 0
        }
    }
}

struct DockPinnedSectionView<RowContent: View>: View {
    let projection: DockCardProjection
    @Binding var isCollapsed: Bool
    let onMove: ([DockRowViewModel]) -> Void
    let onUnpin: (DockRowViewModel) -> Void
    let onOpen: (DockRowViewModel) -> Void
    @ViewBuilder let rowContent: (DockRowViewModel) -> RowContent
    @State private var isReorderPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                        isCollapsed.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Label(headerTitle, systemImage: "pin.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .accessibilityAddTraits(.isHeader)
                            .codexAutomationID(AutomationID.Dock.pinnedHeader)

                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Pinned")
                .accessibilityValue(isCollapsed ? "Collapsed, \(headerTitle)" : "Expanded, \(headerTitle)")
                .codexAutomationID(AutomationID.Dock.pinnedToggleButton)

                Spacer(minLength: 8)

                if projection.pinnedRows.count > 1 {
                    Button {
                        isReorderPresented = true
                    } label: {
                        Label("Reorder", systemImage: "arrow.up.arrow.down")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Reorder pinned rows")
                    .codexAutomationID(AutomationID.Dock.pinnedReorderButton)
                }
            }

            if !isCollapsed {
                DockPinnedRowsList(
                    rows: projection.pinnedRows,
                    onUnpin: onUnpin,
                    onOpen: onOpen,
                    rowContent: rowContent
                )
            }
        }
        .sheet(isPresented: $isReorderPresented) {
            DockPinnedReorderView(
                rows: projection.pinnedRows,
                onCancel: { isReorderPresented = false },
                onSave: { rows in
                    isReorderPresented = false
                    onMove(rows)
                },
                rowContent: rowContent
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue(headerTitle)
        .codexAutomationID(AutomationID.Dock.pinnedSection)
    }

    private var headerTitle: String {
        projection.pinnedSummary.totalCount > projection.pinnedSummary.visibleCount
            ? "Pinned \(projection.pinnedSummary.visibleCount) of \(projection.pinnedSummary.totalCount)"
            : "Pinned \(projection.pinnedSummary.visibleCount)"
    }
}

struct DockPinnedHiddenHintView: View {
    let projection: DockCardProjection
    let searchText: String

    var body: some View {
        HStack(spacing: 8) {
            Label(title, systemImage: "pin.slash")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Text("\(projection.pinnedSummary.hiddenByScopeCount) hidden")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue("\(projection.pinnedSummary.hiddenByScopeCount) pinned hidden")
        .codexAutomationID(AutomationID.Dock.pinnedHiddenHint)
    }

    private var title: String {
        normalizedQuery(searchText).isEmpty
            ? "Pinned hidden by filters"
            : "No pinned rows match search"
    }

    private func normalizedQuery(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct DockPinnedRowsList<RowContent: View>: View {
    let rows: [DockRowViewModel]
    let onUnpin: (DockRowViewModel) -> Void
    let onOpen: (DockRowViewModel) -> Void
    @ViewBuilder let rowContent: (DockRowViewModel) -> RowContent

    private let rowSpacing: CGFloat = 10

    var body: some View {
        LazyVStack(alignment: .leading, spacing: rowSpacing) {
            ForEach(rows) { row in
                DockSwipeActionRow(
                    row: row,
                    actionID: AutomationID.Dock.rowAction(
                        hostID: row.hostID,
                        threadID: row.threadID,
                        action: .unpin
                    ),
                    onTogglePinned: {
                        onUnpin(row)
                    },
                    canOpen: true,
                    onOpen: {
                        onOpen(row)
                    }
                ) {
                    rowContent(row)
                }
            }
        }
        .codexAutomationID(AutomationID.Dock.pinnedRowsList)
    }
}

private struct DockPinnedReorderView<RowContent: View>: View {
    @State private var rows: [DockRowViewModel]
    let onCancel: () -> Void
    let onSave: ([DockRowViewModel]) -> Void
    @ViewBuilder let rowContent: (DockRowViewModel) -> RowContent

    init(
        rows: [DockRowViewModel],
        onCancel: @escaping () -> Void,
        onSave: @escaping ([DockRowViewModel]) -> Void,
        @ViewBuilder rowContent: @escaping (DockRowViewModel) -> RowContent
    ) {
        _rows = State(initialValue: rows)
        self.onCancel = onCancel
        self.onSave = onSave
        self.rowContent = rowContent
    }

    var body: some View {
        NavigationStack {
            reorderList
            .navigationTitle("Reorder pinned")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(rows)
                    }
                }
            }
        }
        .codexAutomationID(AutomationID.Dock.pinnedReorderSheet)
    }

    @ViewBuilder
    private var reorderList: some View {
        let list = List {
            ForEach(rows) { row in
                rowContent(row)
            }
            .onMove { source, destination in
                rows.move(fromOffsets: source, toOffset: destination)
            }
        }
        #if os(iOS)
        list.environment(\.editMode, .constant(.active))
        #else
        list
        #endif
    }
}

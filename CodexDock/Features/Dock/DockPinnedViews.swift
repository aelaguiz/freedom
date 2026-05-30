import SwiftUI
#if os(iOS)
import UIKit

private let dockPinnedRowCellReuseID = "DockPinnedRowCell"
#endif

struct DockSwipeActionRow<Content: View>: View {
    let row: DockRowViewModel
    let actionID: AutomationID
    let resetToken: RenderRevision
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
        .id(row.id)
        .onChange(of: row.id) { _, _ in
            closeAction()
        }
        .onChange(of: row.isPinned) { _, _ in
            closeAction()
        }
        .onChange(of: resetToken) { _, _ in
            closeAction()
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

    private func closeAction() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            offset = 0
        }
    }
}

struct DockPinnedSectionView<RowContent: View>: View {
    let projection: DockSessionProjection
    @Binding var isCollapsed: Bool
    let onMove: ([DockRowViewModel]) -> Void
    let onUnpin: (DockRowViewModel) -> Void
    let onOpen: (DockRowViewModel) -> Void
    @ViewBuilder let rowContent: (DockRowViewModel) -> RowContent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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

                    Spacer(minLength: 8)

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

            if !isCollapsed {
                DockPinnedRowsList(
                    rows: projection.pinnedRows,
                    onReorder: onMove,
                    onUnpin: onUnpin,
                    onOpen: onOpen,
                    rowContent: rowContent
                )
            }
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
    let projection: DockSessionProjection
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
    let onReorder: ([DockRowViewModel]) -> Void
    let onUnpin: (DockRowViewModel) -> Void
    let onOpen: (DockRowViewModel) -> Void
    @ViewBuilder let rowContent: (DockRowViewModel) -> RowContent
    @State private var measuredListHeight: CGFloat = 0

    private let estimatedRowHeight: CGFloat = 130
    private let rowSpacing: CGFloat = 10

    var body: some View {
        Group {
            #if os(iOS)
            DockPinnedReorderCollectionView(
                rows: rows,
                rowSpacing: rowSpacing,
                onReorder: onReorder,
                onUnpin: onUnpin,
                onOpen: onOpen,
                onHeightChange: updateMeasuredListHeight,
                rowContent: rowContent
            )
            .frame(height: listHeight)
            #else
            VStack(alignment: .leading, spacing: rowSpacing) {
                ForEach(rows) { row in
                    rowContent(row)
                }
            }
            #endif
        }
        .codexAutomationID(AutomationID.Dock.pinnedRowsList)
    }

    private var listHeight: CGFloat {
        max(1, measuredListHeight > 0 ? measuredListHeight : estimatedListHeight)
    }

    private var estimatedListHeight: CGFloat {
        guard !rows.isEmpty else {
            return 1
        }
        return (CGFloat(rows.count) * estimatedRowHeight) + (CGFloat(max(0, rows.count - 1)) * rowSpacing)
    }

    private func updateMeasuredListHeight(_ height: CGFloat) {
        let nextHeight = max(1, ceil(height))
        guard nextHeight.isFinite, abs(measuredListHeight - nextHeight) > 0.5 else {
            return
        }
        measuredListHeight = nextHeight
    }
}

#if os(iOS)
private struct DockPinnedReorderCollectionView<RowContent: View>: UIViewRepresentable {
    let rows: [DockRowViewModel]
    let rowSpacing: CGFloat
    let onReorder: ([DockRowViewModel]) -> Void
    let onUnpin: (DockRowViewModel) -> Void
    let onOpen: (DockRowViewModel) -> Void
    let onHeightChange: (CGFloat) -> Void
    @ViewBuilder let rowContent: (DockRowViewModel) -> RowContent

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UICollectionView {
        let coordinator = context.coordinator
        var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
        configuration.backgroundColor = .clear
        configuration.showsSeparators = false
        configuration.trailingSwipeActionsConfigurationProvider = { indexPath in
            coordinator.trailingSwipeActionsConfiguration(for: indexPath)
        }
        let layout = UICollectionViewCompositionalLayout.list(using: configuration)

        let collectionView = PinnedCollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = false
        collectionView.isScrollEnabled = false
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.showsVerticalScrollIndicator = false
        collectionView.dataSource = context.coordinator
        collectionView.delegate = context.coordinator
        collectionView.register(UICollectionViewListCell.self, forCellWithReuseIdentifier: dockPinnedRowCellReuseID)
        collectionView.accessibilityIdentifier = AutomationID.Dock.pinnedRowsList.rawValue
        collectionView.onContentHeightChange = { [weak coordinator] height in
            coordinator?.reportMeasuredHeight(height)
        }

        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        longPress.minimumPressDuration = 0.35
        longPress.cancelsTouchesInView = true
        longPress.delegate = context.coordinator
        collectionView.addGestureRecognizer(longPress)

        return collectionView
    }

    func updateUIView(_ collectionView: UICollectionView, context: Context) {
        context.coordinator.parent = self
        guard !context.coordinator.isMoving else {
            return
        }
        context.coordinator.workingRows = rows
        collectionView.reloadData()
        collectionView.collectionViewLayout.invalidateLayout()
        collectionView.setNeedsLayout()
        collectionView.layoutIfNeeded()
        context.coordinator.reportMeasuredHeight(collectionView.collectionViewLayout.collectionViewContentSize.height)
    }

    final class PinnedCollectionView: UICollectionView {
        var onContentHeightChange: ((CGFloat) -> Void)?
        private var lastContentHeight: CGFloat = 0

        override func layoutSubviews() {
            super.layoutSubviews()
            let height = collectionViewLayout.collectionViewContentSize.height
            guard height.isFinite, abs(height - lastContentHeight) > 0.5 else {
                return
            }
            lastContentHeight = height
            onContentHeightChange?(height)
        }
    }

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegate, UIGestureRecognizerDelegate {
        var parent: DockPinnedReorderCollectionView
        var workingRows: [DockRowViewModel]
        var isMoving = false
        private var lastReportedHeight: CGFloat = 0

        init(_ parent: DockPinnedReorderCollectionView) {
            self.parent = parent
            self.workingRows = parent.rows
        }

        func reportMeasuredHeight(_ height: CGFloat) {
            guard height.isFinite, abs(height - lastReportedHeight) > 0.5 else {
                return
            }
            lastReportedHeight = height
            DispatchQueue.main.async { [weak self] in
                self?.parent.onHeightChange(height)
            }
        }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            workingRows.count
        }

        func collectionView(
            _ collectionView: UICollectionView,
            cellForItemAt indexPath: IndexPath
        ) -> UICollectionViewCell {
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: dockPinnedRowCellReuseID,
                for: indexPath
            )
            guard let cell = cell as? UICollectionViewListCell else {
                return cell
            }
            cell.contentConfiguration = nil
            cell.backgroundColor = .clear
            cell.contentView.backgroundColor = .clear
            cell.backgroundConfiguration = .clear()

            guard indexPath.item < workingRows.count else {
                return cell
            }

            let row = workingRows[indexPath.item]
            cell.contentConfiguration = UIHostingConfiguration {
                parent.rowContent(row)
                    .padding(.vertical, parent.rowSpacing / 2)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .margins(.all, 0)
            return cell
        }

        func collectionView(_ collectionView: UICollectionView, canMoveItemAt indexPath: IndexPath) -> Bool {
            indexPath.item < workingRows.count
        }

        func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            guard indexPath.item < workingRows.count else {
                return
            }
            parent.onOpen(workingRows[indexPath.item])
        }

        func collectionView(
            _ collectionView: UICollectionView,
            moveItemAt sourceIndexPath: IndexPath,
            to destinationIndexPath: IndexPath
        ) {
            guard sourceIndexPath.item != destinationIndexPath.item,
                  sourceIndexPath.item < workingRows.count else {
                return
            }

            let row = workingRows.remove(at: sourceIndexPath.item)
            let insertionIndex = Swift.max(0, Swift.min(workingRows.count, destinationIndexPath.item))
            workingRows.insert(row, at: insertionIndex)
        }

        func trailingSwipeActionsConfiguration(for indexPath: IndexPath) -> UISwipeActionsConfiguration? {
            guard indexPath.item < workingRows.count else {
                return nil
            }

            let row = workingRows[indexPath.item]
            let action = UIContextualAction(style: .destructive, title: "Unpin") { [weak self] _, _, completion in
                self?.parent.onUnpin(row)
                completion(true)
            }
            action.image = UIImage(systemName: "pin.slash")

            let configuration = UISwipeActionsConfiguration(actions: [action])
            configuration.performsFirstActionWithFullSwipe = true
            return configuration
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard let collectionView = gesture.view as? UICollectionView else {
                return
            }

            let location = gesture.location(in: collectionView)
            switch gesture.state {
            case .began:
                guard let indexPath = collectionView.indexPathForItem(at: location) else {
                    return
                }
                workingRows = parent.rows
                guard collectionView.beginInteractiveMovementForItem(at: indexPath) else {
                    isMoving = false
                    workingRows = parent.rows
                    return
                }
                isMoving = true
            case .changed:
                guard isMoving else {
                    return
                }
                collectionView.updateInteractiveMovementTargetPosition(location)
            case .ended:
                guard isMoving else {
                    return
                }
                collectionView.endInteractiveMovement()
                isMoving = false
                parent.onReorder(workingRows)
            default:
                collectionView.cancelInteractiveMovement()
                isMoving = false
                workingRows = parent.rows
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            if gestureRecognizer is UILongPressGestureRecognizer
                || otherGestureRecognizer is UILongPressGestureRecognizer {
                return false
            }
            return true
        }
    }
}
#endif

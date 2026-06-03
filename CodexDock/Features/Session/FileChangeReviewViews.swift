import SwiftUI

struct FileChangeReviewCard: View {
    let event: ThreadEvent
    let fileChange: ThreadDetailFileChangeDTO
    let viewedFileIDs: Set<String>
    let requestCard: ServerRequestCard?
    let onFileViewed: (String, String) -> Void
    let onApprovalRiskConfirmed: (String) -> Void
    let onRequestAction: (String, ServerRequestCardAction) -> Void

    @State private var isReviewPresented = false
    @State private var showDeclineConfirmation = false

    private var reviewState: FileChangeReviewState {
        FileChangeReviewState(
            eventID: event.id,
            fileChange: fileChange,
            viewedFileIDs: viewedFileIDs
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            summaryHeader
            previewFiles
            actionRow
        }
        .sheet(isPresented: $isReviewPresented) {
            NavigationStack {
                FileChangeListView(
                    reviewState: reviewState,
                    requestCard: requestCard,
                    onFileViewed: onFileViewed,
                    onApprovalRiskConfirmed: onApprovalRiskConfirmed,
                    onRequestAction: onRequestAction
                )
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            "Decline file change?",
            isPresented: $showDeclineConfirmation,
            titleVisibility: .visible
        ) {
            if let requestCard {
                Button("Decline", role: .destructive) {
                    onRequestAction(requestCard.id, .decline)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This sends a decline response for this file-change request.")
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue("\(reviewState.rowSummary); \(reviewState.viewedCount) of \(reviewState.files.count) viewed")
        .codexAutomationID(AutomationID.FileChange.card(eventID: event.id))
    }

    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label("Files changed", systemImage: "doc.text.magnifyingglass")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                if let requestCard {
                    Text(requestCard.status.label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(statusColor(requestCard.status))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(statusColor(requestCard.status).opacity(0.12), in: Capsule())
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    Text("\(reviewState.fileCount) \(reviewState.fileCount == 1 ? "file" : "files")")
                    ChangeCountLabel(value: reviewState.additions, kind: .addition)
                    ChangeCountLabel(value: reviewState.deletions, kind: .deletion)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(reviewState.fileCount) \(reviewState.fileCount == 1 ? "file" : "files")")
                    HStack(spacing: 10) {
                        ChangeCountLabel(value: reviewState.additions, kind: .addition)
                        ChangeCountLabel(value: reviewState.deletions, kind: .deletion)
                    }
                }
            }
            .font(.caption.weight(.semibold))

            if reviewState.hasLimitedDiff {
                Label("Some diff content is limited on phone.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Review the diff before approving this change.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var previewFiles: some View {
        if reviewState.files.isEmpty {
            FileChangeUnavailableSummary(reason: fileChange.unavailableReason ?? "missingDiff")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(reviewState.files.prefix(3)), id: \.id) { file in
                    FileChangeCompactRow(
                        file: file,
                        isViewed: viewedFileIDs.contains(file.id)
                    )
                }
                if reviewState.files.count > 3 {
                    Text("+\(reviewState.files.count - 3) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var actionRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                reviewButton
                declineButton
            }
            VStack(alignment: .leading, spacing: 8) {
                reviewButton
                declineButton
            }
        }
    }

    private var reviewButton: some View {
        Button {
            isReviewPresented = true
        } label: {
            Label("Review changes", systemImage: "list.bullet.rectangle")
        }
        .buttonStyle(.borderedProminent)
        .codexAutomationID(AutomationID.FileChange.reviewButton(eventID: event.id))
    }

    @ViewBuilder
    private var declineButton: some View {
        if let requestCard {
            Button {
                showDeclineConfirmation = true
            } label: {
                Label("Decline", systemImage: "xmark")
            }
            .buttonStyle(.bordered)
            .disabled(isBusyOrDone(requestCard))
            .codexAutomationID(AutomationID.RequestCard.declineButton(cardID: requestCard.id))
        }
    }
}

private struct FileChangeListView: View {
    let reviewState: FileChangeReviewState
    let requestCard: ServerRequestCard?
    let onFileViewed: (String, String) -> Void
    let onApprovalRiskConfirmed: (String) -> Void
    let onRequestAction: (String, ServerRequestCardAction) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var filter: FileChangeListFilter = .all

    private var visibleFiles: [FileChangeReviewFile] {
        switch filter {
        case .all:
            return reviewState.files
        case .unviewed:
            return reviewState.files.filter { !reviewState.viewedFileIDs.contains($0.id) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summary
                    filterControl
                    fileRows
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            FileChangeApprovalBar(
                reviewState: reviewState,
                requestCard: requestCard,
                onApprovalRiskConfirmed: onApprovalRiskConfirmed,
                onRequestAction: onRequestAction
            )
        }
        .navigationTitle("File changes")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .navigationDestination(for: FileChangeReviewFile.self) { file in
            FileChangeDiffView(
                file: file,
                reviewState: reviewState,
                requestCard: requestCard,
                onFileViewed: onFileViewed,
                onApprovalRiskConfirmed: onApprovalRiskConfirmed,
                onRequestAction: onRequestAction
            )
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(reviewState.rowSummary)
                .font(.headline)
                .codexAutomationID(AutomationID.FileChange.list(eventID: reviewState.eventID))
            Text("\(reviewState.viewedCount) of \(reviewState.files.count) viewed")
                .font(.caption)
                .foregroundStyle(.secondary)
            if reviewState.hasLimitedDiff {
                Label("Limited diff available on phone", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var filterControl: some View {
        Picker("Files", selection: $filter) {
            Text("All").tag(FileChangeListFilter.all)
            Text("Unviewed").tag(FileChangeListFilter.unviewed)
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var fileRows: some View {
        if visibleFiles.isEmpty {
            DetailMessageView(
                icon: "checkmark.circle",
                title: "All files viewed",
                message: "No unviewed files remain."
            )
        } else {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(visibleFiles) { file in
                    NavigationLink(value: file) {
                        FileChangeListRow(
                            file: file,
                            isViewed: reviewState.viewedFileIDs.contains(file.id)
                        )
                    }
                    .buttonStyle(.plain)
                    .codexAutomationID(AutomationID.FileChange.fileRow(eventID: reviewState.eventID, fileID: file.id))
                }
            }
        }
    }
}

private struct FileChangeDiffView: View {
    let file: FileChangeReviewFile
    let reviewState: FileChangeReviewState
    let requestCard: ServerRequestCard?
    let onFileViewed: (String, String) -> Void
    let onApprovalRiskConfirmed: (String) -> Void
    let onRequestAction: (String, ServerRequestCardAction) -> Void

    @State private var selectedHunkIndex = 0
    @State private var expandedContextRunIDs: Set<Int> = []

    private var lines: [FileChangeDiffLine] {
        FileChangeDiffParser.parse(file.diff ?? "", fallbackKind: file.kind)
    }

    private var hunkLines: [FileChangeDiffLine] {
        lines.filter { $0.kind == .hunk }
    }

    private var effectiveReviewState: FileChangeReviewState {
        guard file.isRenderable else {
            return reviewState
        }
        return FileChangeReviewState(
            eventID: reviewState.eventID,
            fileChange: reviewState.fileChange,
            viewedFileIDs: reviewState.viewedFileIDs.union([file.id])
        )
    }

    private var displayRows: [FileChangeDiffDisplayRow] {
        var rows: [FileChangeDiffDisplayRow] = []
        var index = 0
        while index < lines.count {
            if lines[index].kind == .context {
                let start = index
                while index < lines.count && lines[index].kind == .context {
                    index += 1
                }
                appendContextRows(
                    from: start,
                    to: index,
                    rows: &rows
                )
            } else {
                rows.append(.line(lines[index]))
                index += 1
            }
        }
        return rows
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    fileHeader
                    if file.isRenderable {
                        diffLines
                    } else {
                        unavailableState
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            FileChangeApprovalBar(
                reviewState: effectiveReviewState,
                requestCard: requestCard,
                onApprovalRiskConfirmed: onApprovalRiskConfirmed,
                onRequestAction: onRequestAction
            )
        }
        .navigationTitle(file.displayName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            if file.isRenderable {
                onFileViewed(reviewState.eventID, file.id)
            }
        }
    }

    private var fileHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(file.displayName)
                .font(.headline)
                .lineLimit(3)
                .codexAutomationID(AutomationID.FileChange.diff(eventID: reviewState.eventID, fileID: file.id))
            Text(file.directory)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    FileChangeStatusBadge(label: file.statusLabel, symbol: file.statusSymbol)
                    Text("\(file.hunkCount) \(file.hunkCount == 1 ? "hunk" : "hunks")")
                    ChangeCountLabel(value: file.additions, kind: .addition)
                    ChangeCountLabel(value: file.deletions, kind: .deletion)
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        FileChangeStatusBadge(label: file.statusLabel, symbol: file.statusSymbol)
                        Text("\(file.hunkCount) \(file.hunkCount == 1 ? "hunk" : "hunks")")
                    }
                    HStack(spacing: 8) {
                        ChangeCountLabel(value: file.additions, kind: .addition)
                        ChangeCountLabel(value: file.deletions, kind: .deletion)
                    }
                }
            }
            .font(.caption.weight(.semibold))
        }
    }

    private var diffLines: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 8) {
                hunkNavigation(proxy)
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(displayRows) { row in
                        switch row {
                        case .line(let line):
                            FileChangeDiffLineView(line: line)
                                .id(line.id)
                        case .contextExpansion(let id, let hiddenCount):
                            FileChangeContextExpansionButton(hiddenCount: hiddenCount) {
                                expandedContextRunIDs.insert(id)
                            }
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.secondary.opacity(0.25), lineWidth: 1)
                }
            }
        }
    }

    @ViewBuilder
    private func hunkNavigation(_ proxy: ScrollViewProxy) -> some View {
        if hunkLines.count > 1 {
            HStack(spacing: 8) {
                Button {
                    selectedHunkIndex = max(0, selectedHunkIndex - 1)
                    proxy.scrollTo(hunkLines[selectedHunkIndex].id, anchor: .top)
                } label: {
                    Label("Previous hunk", systemImage: "chevron.up")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(selectedHunkIndex == 0)

                Text("\(selectedHunkIndex + 1) of \(hunkLines.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Button {
                    selectedHunkIndex = min(hunkLines.count - 1, selectedHunkIndex + 1)
                    proxy.scrollTo(hunkLines[selectedHunkIndex].id, anchor: .top)
                } label: {
                    Label("Next hunk", systemImage: "chevron.down")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(selectedHunkIndex >= hunkLines.count - 1)
            }
            .font(.caption)
        }
    }

    private func appendContextRows(
        from start: Int,
        to end: Int,
        rows: inout [FileChangeDiffDisplayRow]
    ) {
        let count = end - start
        let collapseThreshold = 8
        let edgeCount = 3
        if count <= collapseThreshold || expandedContextRunIDs.contains(start) {
            rows.append(contentsOf: lines[start..<end].map(FileChangeDiffDisplayRow.line))
            return
        }
        rows.append(contentsOf: lines[start..<(start + edgeCount)].map(FileChangeDiffDisplayRow.line))
        rows.append(.contextExpansion(id: start, hiddenCount: count - (edgeCount * 2)))
        rows.append(contentsOf: lines[(end - edgeCount)..<end].map(FileChangeDiffDisplayRow.line))
    }

    private var unavailableState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(file.availabilityLabel, systemImage: "exclamationmark.triangle")
                .font(.headline)
                .foregroundStyle(.orange)
            Text(file.unavailableReason ?? "This file cannot be rendered as a text diff on phone.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                onFileViewed(reviewState.eventID, file.id)
            } label: {
                Label("Acknowledge", systemImage: "checkmark")
            }
            .buttonStyle(.bordered)
            .codexAutomationID(AutomationID.FileChange.acknowledgeButton(eventID: reviewState.eventID, fileID: file.id))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct FileChangeApprovalBar: View {
    let reviewState: FileChangeReviewState
    let requestCard: ServerRequestCard?
    let onApprovalRiskConfirmed: (String) -> Void
    let onRequestAction: (String, ServerRequestCardAction) -> Void

    @State private var showApprovalConfirmation = false
    @State private var showDeclineConfirmation = false

    var body: some View {
        if let requestCard {
            VStack(alignment: .leading, spacing: 8) {
                if case let .failed(message) = requestCard.status {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ViewThatFits(in: .horizontal) {
                    buttonRow(requestCard)
                    VStack(alignment: .leading, spacing: 8) {
                        buttonRow(requestCard)
                    }
                }
            }
            .padding(12)
            .background(.bar)
            .confirmationDialog(
                reviewState.confirmationTitle,
                isPresented: $showApprovalConfirmation,
                titleVisibility: .visible
            ) {
                Button("Approve anyway") {
                    onApprovalRiskConfirmed(requestCard.id)
                    onRequestAction(requestCard.id, .accept)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(reviewState.confirmationMessage)
            }
            .confirmationDialog(
                "Decline file change?",
                isPresented: $showDeclineConfirmation,
                titleVisibility: .visible
            ) {
                Button("Decline", role: .destructive) {
                    onRequestAction(requestCard.id, .decline)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This sends a decline response for this file-change request.")
            }
        }
    }

    private func buttonRow(_ requestCard: ServerRequestCard) -> some View {
        HStack(spacing: 8) {
            Button {
                showDeclineConfirmation = true
            } label: {
                Label("Decline", systemImage: "xmark")
            }
            .buttonStyle(.bordered)
            .disabled(isBusyOrDone(requestCard))
            .codexAutomationID(AutomationID.RequestCard.declineButton(cardID: requestCard.id))

            Button {
                if reviewState.canApproveWithoutConfirmation {
                    onRequestAction(requestCard.id, .accept)
                } else {
                    showApprovalConfirmation = true
                }
            } label: {
                Label(reviewState.approveButtonTitle, systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isBusyOrDone(requestCard))
            .codexAutomationID(AutomationID.RequestCard.approveButton(cardID: requestCard.id))
        }
    }
}

private struct FileChangeListRow: View {
    let file: FileChangeReviewFile
    let isViewed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                FileChangeStatusBadge(label: file.statusLabel, symbol: file.statusSymbol)
                VStack(alignment: .leading, spacing: 3) {
                    Text(file.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(file.directory)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Image(systemName: isViewed ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isViewed ? .green : .secondary)
                    .accessibilityLabel(isViewed ? "Viewed" : "Not viewed")
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    Text(file.availabilityLabel)
                    Text("\(file.hunkCount) \(file.hunkCount == 1 ? "hunk" : "hunks")")
                    ChangeCountLabel(value: file.additions, kind: .addition)
                    ChangeCountLabel(value: file.deletions, kind: .deletion)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        Text(file.availabilityLabel)
                        Text("\(file.hunkCount) \(file.hunkCount == 1 ? "hunk" : "hunks")")
                    }
                    HStack(spacing: 10) {
                        ChangeCountLabel(value: file.additions, kind: .addition)
                        ChangeCountLabel(value: file.deletions, kind: .deletion)
                    }
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(file.statusLabel), \(file.additions) additions, \(file.deletions) deletions, \(isViewed ? "viewed" : "not viewed")")
    }
}

private struct FileChangeCompactRow: View {
    let file: FileChangeReviewFile
    let isViewed: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(file.statusSymbol)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(file.displayName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(file.directory)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            ChangeCountLabel(value: file.additions, kind: .addition)
            ChangeCountLabel(value: file.deletions, kind: .deletion)
            Image(systemName: isViewed ? "checkmark.circle.fill" : "circle")
                .font(.caption)
                .foregroundStyle(isViewed ? .green : .secondary)
        }
    }
}

private struct FileChangeUnavailableSummary: View {
    let reason: String

    var body: some View {
        Label("Diff unavailable on phone: \(reason)", systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private enum FileChangeDiffDisplayRow: Identifiable {
    case line(FileChangeDiffLine)
    case contextExpansion(id: Int, hiddenCount: Int)

    var id: String {
        switch self {
        case .line(let line):
            return "line-\(line.id)"
        case .contextExpansion(let id, _):
            return "context-\(id)"
        }
    }
}

private struct FileChangeContextExpansionButton: View {
    let hiddenCount: Int
    let onExpand: () -> Void

    var body: some View {
        Button {
            onExpand()
        } label: {
            Label("Expand \(hiddenCount) unchanged lines", systemImage: "ellipsis")
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(.secondary.opacity(0.08))
    }
}

private struct FileChangeDiffLineView: View {
    let line: FileChangeDiffLine

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(line.oldLine.map(String.init) ?? "")
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
            Text(line.newLine.map(String.init) ?? "")
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
            Text(line.sign)
                .foregroundStyle(signColor)
                .frame(width: 26, alignment: .center)
            Text(line.text.isEmpty ? " " : line.text)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption.monospaced())
        .padding(.horizontal, 8)
        .padding(.vertical, line.kind == .hunk ? 7 : 4)
        .background(backgroundColor)
        .accessibilityElement(children: .combine)
        .accessibilityValue(accessibilityValue)
    }

    private var backgroundColor: Color {
        switch line.kind {
        case .addition:
            return .green.opacity(0.14)
        case .deletion:
            return .red.opacity(0.14)
        case .hunk:
            return .blue.opacity(0.12)
        case .context:
            return .clear
        }
    }

    private var signColor: Color {
        switch line.kind {
        case .addition:
            return .green
        case .deletion:
            return .red
        case .hunk:
            return .blue
        case .context:
            return .secondary
        }
    }

    private var accessibilityValue: String {
        switch line.kind {
        case .addition:
            return "Added line \(line.newLine.map(String.init) ?? ""), \(line.text)"
        case .deletion:
            return "Removed line \(line.oldLine.map(String.init) ?? ""), \(line.text)"
        case .hunk:
            return "Diff hunk \(line.text)"
        case .context:
            return "Context line \(line.newLine.map(String.init) ?? ""), \(line.text)"
        }
    }
}

private struct FileChangeStatusBadge: View {
    let label: String
    let symbol: String

    var body: some View {
        HStack(spacing: 4) {
            Text(symbol)
                .font(.caption2.weight(.bold))
            Text(label)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.secondary.opacity(0.12), in: Capsule())
    }
}

private enum ChangeCountKind {
    case addition
    case deletion
}

private struct ChangeCountLabel: View {
    let value: Int
    let kind: ChangeCountKind

    var body: some View {
        Text("\(prefix)\(value)")
            .font(.caption.monospacedDigit().weight(.semibold))
            .foregroundStyle(color)
            .accessibilityLabel("\(value) \(kind == .addition ? "additions" : "deletions")")
    }

    private var prefix: String {
        switch kind {
        case .addition:
            return "+"
        case .deletion:
            return "-"
        }
    }

    private var color: Color {
        switch kind {
        case .addition:
            return .green
        case .deletion:
            return .red
        }
    }
}

private enum FileChangeListFilter: Hashable {
    case all
    case unviewed
}

private func isBusyOrDone(_ card: ServerRequestCard) -> Bool {
    switch card.status {
    case .responding, .resolved:
        return true
    case .pending, .failed:
        return false
    }
}

private func statusColor(_ status: ServerRequestCardStatus) -> Color {
    switch status {
    case .failed:
        return .red
    case .responding:
        return .blue
    case .resolved:
        return .green
    case .pending:
        return .orange
    }
}

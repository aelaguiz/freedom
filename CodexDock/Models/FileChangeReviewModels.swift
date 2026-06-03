import Foundation

struct FileChangeReviewFile: Equatable, Hashable, Identifiable, Sendable {
    let id: String
    let index: Int
    let path: String
    let oldPath: String?
    let kind: String
    let additions: Int
    let deletions: Int
    let diffAvailability: String
    let diff: String?
    let truncated: Bool
    let unavailableReason: String?

    init(index: Int, change: ThreadDetailFileChangeEntryDTO) {
        self.id = Self.id(index: index, path: change.path, oldPath: change.oldPath, kind: change.kind)
        self.index = index
        self.path = change.path
        self.oldPath = change.oldPath
        self.kind = change.kind
        self.additions = change.additions
        self.deletions = change.deletions
        self.diffAvailability = change.diffAvailability
        self.diff = change.diff
        self.truncated = change.truncated
        self.unavailableReason = change.unavailableReason
    }

    static func id(index: Int, path: String, oldPath: String?, kind: String) -> String {
        "\(index):\(kind):\(oldPath ?? ""):\(path)"
    }

    var displayName: String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    var directory: String {
        let parts = path.split(separator: "/")
        guard parts.count > 1 else {
            return "."
        }
        return parts.dropLast().joined(separator: "/")
    }

    var statusLabel: String {
        switch kind {
        case "add":
            return "Added"
        case "delete":
            return "Deleted"
        case "move":
            return "Moved"
        case "update":
            return "Modified"
        default:
            return "Changed"
        }
    }

    var statusSymbol: String {
        switch kind {
        case "add":
            return "A"
        case "delete":
            return "D"
        case "move":
            return "R"
        case "update":
            return "M"
        default:
            return "?"
        }
    }

    var isRenderable: Bool {
        diffAvailability == "available" && diff?.isEmpty == false
    }

    var isLimited: Bool {
        truncated || diffAvailability != "available" || diff?.isEmpty != false
    }

    var hunkCount: Int {
        guard let diff else {
            return 0
        }
        return diff.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.hasPrefix("@@") }
            .count
    }

    var availabilityLabel: String {
        if truncated {
            return "Truncated"
        }
        switch diffAvailability {
        case "available":
            return "Text diff"
        case "binary":
            return "Binary"
        case "generated":
            return "Generated"
        case "tooLarge":
            return "Too large"
        case "missing":
            return "Missing diff"
        case "unsupported":
            return "Unsupported"
        default:
            return "Unknown diff"
        }
    }
}

struct FileChangeReviewState: Equatable, Sendable {
    let eventID: String
    let fileChange: ThreadDetailFileChangeDTO
    let files: [FileChangeReviewFile]
    let viewedFileIDs: Set<String>

    init(
        eventID: String,
        fileChange: ThreadDetailFileChangeDTO,
        viewedFileIDs: Set<String>
    ) {
        self.eventID = eventID
        self.fileChange = fileChange
        self.files = fileChange.changes.enumerated().map { index, change in
            FileChangeReviewFile(index: index, change: change)
        }
        self.viewedFileIDs = viewedFileIDs
    }

    var fileCount: Int {
        fileChange.summary.fileCount
    }

    var additions: Int {
        fileChange.summary.additions
    }

    var deletions: Int {
        fileChange.summary.deletions
    }

    var viewedCount: Int {
        files.filter { viewedFileIDs.contains($0.id) }.count
    }

    var unviewedCount: Int {
        max(0, files.count - viewedCount)
    }

    var hasLimitedDiff: Bool {
        fileChange.summary.truncated
            || fileChange.unavailableReason != nil
            || files.contains { $0.isLimited }
    }

    var canApproveWithoutConfirmation: Bool {
        !files.isEmpty && unviewedCount == 0 && !hasLimitedDiff
    }

    var approveButtonTitle: String {
        if canApproveWithoutConfirmation {
            return "Approve changes"
        }
        if files.isEmpty {
            return "Approve with unavailable diff"
        }
        if hasLimitedDiff {
            return "Approve with limited diff"
        }
        return "Review before approve"
    }

    var confirmationTitle: String {
        if files.isEmpty {
            return "Approve without a visible diff?"
        }
        if hasLimitedDiff {
            return "Approve with a limited diff?"
        }
        return "Approve without reviewing all files?"
    }

    var confirmationMessage: String {
        if files.isEmpty {
            return "The phone did not receive a renderable file list or diff for this approval."
        }
        if hasLimitedDiff {
            return "Some files are missing, truncated, binary, generated, or otherwise not fully renderable on phone."
        }
        return "\(unviewedCount) changed file(s) have not been opened yet."
    }

    var rowSummary: String {
        let label = fileCount == 1 ? "file" : "files"
        return "\(fileCount) \(label) - +\(additions) -\(deletions)"
    }
}

enum FileChangeDiffLineKind: Equatable, Sendable {
    case hunk
    case context
    case addition
    case deletion
}

struct FileChangeDiffLine: Equatable, Identifiable, Sendable {
    let id: Int
    let kind: FileChangeDiffLineKind
    let oldLine: Int?
    let newLine: Int?
    let sign: String
    let text: String
}

enum FileChangeDiffParser {
    static func parse(_ diff: String, fallbackKind: String? = nil) -> [FileChangeDiffLine] {
        if shouldTreatAsFullContent(diff, fallbackKind: fallbackKind) {
            return parseFullContent(diff, fallbackKind: fallbackKind)
        }
        var oldLine: Int?
        var newLine: Int?
        var parsed: [FileChangeDiffLine] = []

        for (index, rawLine) in diff.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = String(rawLine)
            if line.hasPrefix("@@") {
                if let starts = hunkStarts(from: line) {
                    oldLine = starts.old
                    newLine = starts.new
                }
                parsed.append(FileChangeDiffLine(
                    id: index,
                    kind: .hunk,
                    oldLine: nil,
                    newLine: nil,
                    sign: "@@",
                    text: line
                ))
            } else if line.hasPrefix("+") && !line.hasPrefix("+++") {
                parsed.append(FileChangeDiffLine(
                    id: index,
                    kind: .addition,
                    oldLine: nil,
                    newLine: newLine,
                    sign: "+",
                    text: String(line.dropFirst())
                ))
                newLine = newLine.map { $0 + 1 }
            } else if line.hasPrefix("-") && !line.hasPrefix("---") {
                parsed.append(FileChangeDiffLine(
                    id: index,
                    kind: .deletion,
                    oldLine: oldLine,
                    newLine: nil,
                    sign: "-",
                    text: String(line.dropFirst())
                ))
                oldLine = oldLine.map { $0 + 1 }
            } else {
                let text = line.hasPrefix(" ") ? String(line.dropFirst()) : line
                parsed.append(FileChangeDiffLine(
                    id: index,
                    kind: .context,
                    oldLine: oldLine,
                    newLine: newLine,
                    sign: " ",
                    text: text
                ))
                oldLine = oldLine.map { $0 + 1 }
                newLine = newLine.map { $0 + 1 }
            }
        }

        return parsed
    }

    private static func shouldTreatAsFullContent(_ diff: String, fallbackKind: String?) -> Bool {
        guard fallbackKind == "add" || fallbackKind == "delete" else {
            return false
        }
        let lines = diff.split(separator: "\n", omittingEmptySubsequences: false)
        return !lines.contains { line in
            line.hasPrefix("@@")
                || line.hasPrefix("+")
                || line.hasPrefix("-")
        }
    }

    private static func parseFullContent(_ diff: String, fallbackKind: String?) -> [FileChangeDiffLine] {
        diff.split(separator: "\n", omittingEmptySubsequences: false).enumerated().map { index, rawLine in
            let lineNumber = index + 1
            let isAdd = fallbackKind == "add"
            return FileChangeDiffLine(
                id: index,
                kind: isAdd ? .addition : .deletion,
                oldLine: isAdd ? nil : lineNumber,
                newLine: isAdd ? lineNumber : nil,
                sign: isAdd ? "+" : "-",
                text: String(rawLine)
            )
        }
    }

    private static func hunkStarts(from header: String) -> (old: Int, new: Int)? {
        let parts = header.split(separator: " ")
        guard let oldPart = parts.first(where: { $0.hasPrefix("-") }),
              let newPart = parts.first(where: { $0.hasPrefix("+") }) else {
            return nil
        }
        guard let oldStartPart = oldPart.dropFirst().split(separator: ",").first,
              let newStartPart = newPart.dropFirst().split(separator: ",").first,
              let oldStart = Int(oldStartPart),
              let newStart = Int(newStartPart) else {
            return nil
        }
        return (oldStart, newStart)
    }
}

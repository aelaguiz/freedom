import Foundation
import SwiftUI

/// Stable accessibility identifiers are automation API. Use model IDs only for
/// dynamic segments, and never place visible copy, secrets, prompts, or bodies here.
public struct AutomationID: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }
}

public extension AutomationID {
    enum StateKind: String, Sendable {
        case starting
        case discovering
        case failed
        case loading
        case idle
        case empty
        case offline
        case error
        case stale
        case configurationError = "configuration-error"
        case validationError = "validation-error"
        case mappingFailure = "mapping-failure"
        case actionError = "action-error"
        case unavailable
        case noRowsMatch = "no-rows-match"
        case noTranscript = "no-transcript"
        case voiceError = "voice-error"
        case composerError = "composer-error"
        case requestError = "request-error"
        case unsupported
    }

    enum DockRowAction: String, Sendable {
        case pin
        case unpin
        case markWatch = "mark-watch"
        case clearLabel = "clear-label"
        case archive
        case color
        case clearColor = "clear-color"
    }

    enum App {
        public static let root = AutomationID("codexdock.app.root")
    }

    enum Bootstrap {
        public static let root = AutomationID("codexdock.bootstrap.root")
        public static let manualHostField = AutomationID("codexdock.bootstrap.manual-host")
        public static let manualPortField = AutomationID("codexdock.bootstrap.manual-port")
        public static let manualConnectButton = AutomationID("codexdock.bootstrap.connect")

        public static func state(_ kind: StateKind) -> AutomationID {
            AutomationID("codexdock.bootstrap.state.\(kind.rawValue)")
        }

        public static func discoveredRelayRow(_ relayID: String) -> AutomationID {
            AutomationID("codexdock.bootstrap.discovered-relay.\(safeSegment(relayID))")
        }
    }

    enum Connectivity {
        public static let globalIndicator = AutomationID("codexdock.connectivity.global")
    }

    enum TaskSheet {
        public static let moreButton = AutomationID("codexdock.tasks.more")

        public static func menuItem(_ sheet: DockTaskSheet) -> AutomationID {
            AutomationID("codexdock.tasks.menu.\(sheet.rawValue)")
        }

        public static func sheet(_ sheet: DockTaskSheet) -> AutomationID {
            AutomationID("codexdock.tasks.sheet.\(sheet.rawValue)")
        }
    }

    enum SystemHealth {
        public static let root = AutomationID("codexdock.system-health.root")
        public static let closeButton = AutomationID("codexdock.system-health.close")
        public static let runCheckButton = AutomationID("codexdock.system-health.run-check")
        public static let summary = AutomationID("codexdock.system-health.summary")
        public static let relaySettingsButton = AutomationID("codexdock.system-health.relay-settings")
        public static let copyDoctorButton = AutomationID("codexdock.system-health.copy-doctor")

        public static func state(_ kind: StateKind) -> AutomationID {
            AutomationID("codexdock.system-health.state.\(kind.rawValue)")
        }

        public static func category(_ categoryID: String) -> AutomationID {
            AutomationID("codexdock.system-health.category.\(safeSegment(categoryID))")
        }

        public static func hostCard(hostID: String) -> AutomationID {
            AutomationID("codexdock.system-health.host.\(safeSegment(hostID))")
        }

        public static func hostDetail(hostID: String) -> AutomationID {
            AutomationID("codexdock.system-health.host.\(safeSegment(hostID)).detail")
        }
    }

    enum ArchiveCleanup {
        public static let root = AutomationID("codexdock.archive-cleanup.root")
        public static let closeButton = AutomationID("codexdock.archive-cleanup.close")
        public static let previewButton = AutomationID("codexdock.archive-cleanup.preview")
        public static let archiveButton = AutomationID("codexdock.archive-cleanup.archive")
        public static let openArchivedThreadsButton = AutomationID("codexdock.archive-cleanup.open-archived-threads")
        public static let customAgeField = AutomationID("codexdock.archive-cleanup.age.custom.field")
        public static let customAgeApplyButton = AutomationID("codexdock.archive-cleanup.age.custom.apply")
        public static let summary = AutomationID("codexdock.archive-cleanup.summary")
        public static let viewAllButton = AutomationID("codexdock.archive-cleanup.preview.view-all")
        public static let reviewListButton = AutomationID("codexdock.archive-cleanup.review-list.open")
        public static let reviewList = AutomationID("codexdock.archive-cleanup.review-list")
        public static let reviewSearchField = AutomationID("codexdock.archive-cleanup.review-list.search")
        public static let reviewArchiveButton = AutomationID("codexdock.archive-cleanup.review-list.archive")
        public static let selectedCount = AutomationID("codexdock.archive-cleanup.selected-count")
        public static let showExcludedToggle = AutomationID("codexdock.archive-cleanup.review-list.show-excluded")
        public static let progress = AutomationID("codexdock.archive-cleanup.progress")
        public static let stopRemainingButton = AutomationID("codexdock.archive-cleanup.progress.stop")
        public static let retryFailedButton = AutomationID("codexdock.archive-cleanup.progress.retry-failed")
        public static let viewArchivedButton = AutomationID("codexdock.archive-cleanup.progress.view-archived")
        public static let confirmArchiveButton = AutomationID("codexdock.archive-cleanup.confirm.archive")
        public static let doneButton = AutomationID("codexdock.archive-cleanup.progress.done")

        public static func state(_ kind: StateKind) -> AutomationID {
            AutomationID("codexdock.archive-cleanup.state.\(kind.rawValue)")
        }

        public static func ageButton(_ value: String) -> AutomationID {
            AutomationID("codexdock.archive-cleanup.age.\(safeSegment(value))")
        }

        public static func hostSummary(hostID: String) -> AutomationID {
            AutomationID("codexdock.archive-cleanup.host.\(safeSegment(hostID))")
        }

        public static func row(hostID: String, threadID: String) -> AutomationID {
            AutomationID("codexdock.archive-cleanup.row.\(safeSegment(hostID)).\(safeSegment(threadID))")
        }

        public static func selectionToggle(hostID: String, threadID: String) -> AutomationID {
            AutomationID("codexdock.archive-cleanup.row.\(safeSegment(hostID)).\(safeSegment(threadID)).select")
        }

        public static func filterChip(_ value: String) -> AutomationID {
            AutomationID("codexdock.archive-cleanup.filter.\(safeSegment(value))")
        }
    }

    enum Dock {
        public static let root = AutomationID("codexdock.dock.root")
        public static let searchField = AutomationID("codexdock.dock.search")
        public static let lensPicker = AutomationID("codexdock.dock.lens")
        public static let filterButton = AutomationID("codexdock.dock.filters.button")
        public static let activeFilterSummary = AutomationID("codexdock.dock.filters.summary")
        public static let clearSearchButton = AutomationID("codexdock.dock.search.clear")
        public static let clearFiltersButton = AutomationID("codexdock.dock.filters.clear")
        public static let filterSurface = AutomationID("codexdock.dock.filters.surface")
        public static let filterResultSummary = AutomationID("codexdock.dock.filters.result-summary")
        public static let filterHostAny = AutomationID("codexdock.dock.filters.host.any")
        public static let filterBranchSearch = AutomationID("codexdock.dock.filters.branch.search")
        public static let filterStatusAny = AutomationID("codexdock.dock.filters.status.any")
        public static let filterRepoQuery = AutomationID("codexdock.dock.filters.repo.query")
        public static let filterSourcePicker = AutomationID("codexdock.dock.filters.source")
        public static let filterIdleToggle = AutomationID("codexdock.dock.filters.idle")
        public static let pinnedSection = AutomationID("codexdock.dock.pinned.section")
        public static let pinnedHeader = AutomationID("codexdock.dock.pinned.header")
        public static let pinnedToggleButton = AutomationID("codexdock.dock.pinned.toggle")
        public static let pinnedRowsList = AutomationID("codexdock.dock.pinned.rows")
        public static let pinnedBodyDivider = AutomationID("codexdock.dock.pinned.body-divider")
        public static let pinnedHiddenHint = AutomationID("codexdock.dock.pinned.hidden")

        public static func state(_ kind: StateKind) -> AutomationID {
            AutomationID("codexdock.dock.state.\(kind.rawValue)")
        }

        public static func lensButton(_ lensID: String) -> AutomationID {
            AutomationID("codexdock.dock.lens.\(safeSegment(lensID))")
        }

        public static func hostSummary(hostID: String) -> AutomationID {
            AutomationID("codexdock.dock.host.\(safeSegment(hostID))")
        }

        public static func hostGroup(_ groupID: String) -> AutomationID {
            AutomationID("codexdock.dock.group.host.\(safeSegment(groupID))")
        }

        public static func hostToggle(_ groupID: String) -> AutomationID {
            AutomationID("codexdock.dock.group.host.\(safeSegment(groupID)).toggle")
        }

        public static func branchGroup(_ groupID: String) -> AutomationID {
            AutomationID("codexdock.dock.group.branch.\(safeSegment(groupID))")
        }

        public static func branchToggle(_ groupID: String) -> AutomationID {
            AutomationID("codexdock.dock.group.branch.\(safeSegment(groupID)).toggle")
        }

        public static func hostRetry(hostID: String) -> AutomationID {
            AutomationID("codexdock.dock.host.\(safeSegment(hostID)).retry")
        }

        public static func hostRelaySettings(hostID: String) -> AutomationID {
            AutomationID("codexdock.dock.host.\(safeSegment(hostID)).relay-settings")
        }

        public static func filterHost(hostID: String) -> AutomationID {
            AutomationID("codexdock.dock.filters.host.\(safeSegment(hostID))")
        }

        public static func filterBranch(_ branch: String) -> AutomationID {
            AutomationID("codexdock.dock.filters.branch.\(safeSegment(branch))")
        }

        public static func filterStatus(_ status: String) -> AutomationID {
            AutomationID("codexdock.dock.filters.status.\(safeSegment(status))")
        }

        public static func filterRepo(_ repo: String) -> AutomationID {
            AutomationID("codexdock.dock.filters.repo.\(safeSegment(repo))")
        }

        public static func section(_ sectionID: String) -> AutomationID {
            AutomationID("codexdock.dock.section.\(safeSegment(sectionID))")
        }

        public static func row(hostID: String, threadID: String) -> AutomationID {
            AutomationID("codexdock.dock.row.\(safeSegment(hostID)).\(safeSegment(threadID))")
        }

        public static func rowAction(hostID: String, threadID: String, action: DockRowAction) -> AutomationID {
            AutomationID("codexdock.dock.row.\(safeSegment(hostID)).\(safeSegment(threadID)).action.\(action.rawValue)")
        }

        public static func rowColorAction(hostID: String, threadID: String, rail: String) -> AutomationID {
            AutomationID("codexdock.dock.row.\(safeSegment(hostID)).\(safeSegment(threadID)).action.color.\(safeSegment(rail))")
        }
    }

    enum Archive {
        public static let root = AutomationID("codexdock.archive.root")
        public static let refreshButton = AutomationID("codexdock.archive.refresh")
        public static let searchField = AutomationID("codexdock.archive.search")
        public static let selectButton = AutomationID("codexdock.archive.select")
        public static let cancelSelectionButton = AutomationID("codexdock.archive.selection.cancel")
        public static let selectionToolbar = AutomationID("codexdock.archive.selection.toolbar")
        public static let restoreSelectedButton = AutomationID("codexdock.archive.selection.restore")
        public static let batchProgress = AutomationID("codexdock.archive.batch.progress")
        public static let stopRemainingButton = AutomationID("codexdock.archive.batch.stop")
        public static let retryFailedButton = AutomationID("codexdock.archive.batch.retry-failed")
        public static let doneButton = AutomationID("codexdock.archive.batch.done")

        public static func state(_ kind: StateKind) -> AutomationID {
            AutomationID("codexdock.archive.state.\(kind.rawValue)")
        }

        public static func hostSummary(hostID: String) -> AutomationID {
            AutomationID("codexdock.archive.host.\(safeSegment(hostID))")
        }

        public static func section(_ sectionID: String) -> AutomationID {
            AutomationID("codexdock.archive.section.\(safeSegment(sectionID))")
        }

        public static func row(hostID: String, threadID: String) -> AutomationID {
            AutomationID("codexdock.archive.row.\(safeSegment(hostID)).\(safeSegment(threadID))")
        }

        public static func restoreButton(hostID: String, threadID: String) -> AutomationID {
            AutomationID("codexdock.archive.row.\(safeSegment(hostID)).\(safeSegment(threadID)).restore")
        }

        public static func selectionToggle(hostID: String, threadID: String) -> AutomationID {
            AutomationID("codexdock.archive.row.\(safeSegment(hostID)).\(safeSegment(threadID)).select")
        }

        public static func filterChip(_ value: String) -> AutomationID {
            AutomationID("codexdock.archive.filter.\(safeSegment(value))")
        }
    }

    enum Relay {
        public static let root = AutomationID("codexdock.relay.root")
        public static let testAllButton = AutomationID("codexdock.relay.test-all")
        public static let addButton = AutomationID("codexdock.relay.add")
        public static let editor = AutomationID("codexdock.relay.editor")
        public static let hostField = AutomationID("codexdock.relay.editor.host")
        public static let portField = AutomationID("codexdock.relay.editor.port")
        public static let saveButton = AutomationID("codexdock.relay.editor.save")
        public static let cancelButton = AutomationID("codexdock.relay.editor.cancel")

        public static func state(_ kind: StateKind) -> AutomationID {
            AutomationID("codexdock.relay.state.\(kind.rawValue)")
        }

        public static func row(hostID: String) -> AutomationID {
            AutomationID("codexdock.relay.row.\(safeSegment(hostID))")
        }

        public static func rowTestButton(hostID: String) -> AutomationID {
            AutomationID("codexdock.relay.row.\(safeSegment(hostID)).test")
        }

        public static func rowEditButton(hostID: String) -> AutomationID {
            AutomationID("codexdock.relay.row.\(safeSegment(hostID)).edit")
        }

        public static func rowRemoveButton(hostID: String) -> AutomationID {
            AutomationID("codexdock.relay.row.\(safeSegment(hostID)).remove")
        }
    }

    enum Session {
        public static let header = AutomationID("codexdock.session.header")
        public static let hostPill = AutomationID("codexdock.session.header.host")
        public static let livePill = AutomationID("codexdock.session.header.live")
        public static let statusPill = AutomationID("codexdock.session.header.status")
        public static let messageFilter = AutomationID("codexdock.session.message-filter")
        public static let clearMessageFilter = AutomationID("codexdock.session.message-filter.clear")
        public static let messageList = AutomationID("codexdock.session.message-list")

        public static func root(threadID: String) -> AutomationID {
            AutomationID("codexdock.session.root.\(safeSegment(threadID))")
        }

        public static func state(_ kind: StateKind) -> AutomationID {
            AutomationID("codexdock.session.state.\(kind.rawValue)")
        }

        public static func messageCard(eventID: String) -> AutomationID {
            AutomationID("codexdock.session.message.\(safeSegment(eventID))")
        }
    }

    enum Composer {
        public static let root = AutomationID("codexdock.session.composer")
        public static let messageField = AutomationID("codexdock.session.composer.message")
        public static let sendButton = AutomationID("codexdock.session.composer.send")
        public static let holdMicButton = AutomationID("codexdock.session.composer.voice.hold")
        public static let tapMicButton = AutomationID("codexdock.session.composer.voice.tap")
        public static let voiceStatus = AutomationID("codexdock.session.composer.voice.status")
        public static let voiceError = AutomationID("codexdock.session.composer.voice.error")
        public static let composerError = AutomationID("codexdock.session.composer.error")
    }

    enum RequestCard {
        public static func card(cardID: String) -> AutomationID {
            AutomationID("codexdock.session.request.\(safeSegment(cardID))")
        }

        public static func inputField(cardID: String) -> AutomationID {
            AutomationID("codexdock.session.request.\(safeSegment(cardID)).input")
        }

        public static func approveButton(cardID: String) -> AutomationID {
            AutomationID("codexdock.session.request.\(safeSegment(cardID)).approve")
        }

        public static func declineButton(cardID: String) -> AutomationID {
            AutomationID("codexdock.session.request.\(safeSegment(cardID)).decline")
        }

        public static func sendButton(cardID: String) -> AutomationID {
            AutomationID("codexdock.session.request.\(safeSegment(cardID)).send")
        }

        public static func unsupportedState(cardID: String) -> AutomationID {
            AutomationID("codexdock.session.request.\(safeSegment(cardID)).unsupported")
        }

        public static func status(cardID: String) -> AutomationID {
            AutomationID("codexdock.session.request.\(safeSegment(cardID)).status")
        }

        public static func error(cardID: String) -> AutomationID {
            AutomationID("codexdock.session.request.\(safeSegment(cardID)).error")
        }
    }

    static func safeSegment(_ value: String) -> String {
        var escaped = ""
        for byte in value.utf8 {
            switch byte {
            case 48...57, 65...90, 97...122:
                escaped.unicodeScalars.append(UnicodeScalar(Int(byte))!)
            case 45, 46, 95:
                escaped.unicodeScalars.append(UnicodeScalar(Int(byte))!)
            default:
                escaped.append(String(format: "%%%02X", byte))
            }
        }
        return escaped.isEmpty ? "_" : escaped
    }
}

public extension View {
    func codexAutomationID(_ id: AutomationID) -> some View {
        accessibilityIdentifier(id.rawValue)
    }

    @ViewBuilder
    func codexAutomationID(_ id: AutomationID?) -> some View {
        if let id {
            codexAutomationID(id)
        } else {
            self
        }
    }
}

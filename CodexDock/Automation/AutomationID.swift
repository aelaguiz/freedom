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
        case scopeConflict = "scope-conflict"
        case scopeLoadFailure = "scope-load-failure"
        case actionError = "action-error"
        case unavailable
        case noRowsMatch = "no-rows-match"
        case noTranscript = "no-transcript"
        case voiceError = "voice-error"
        case composerError = "composer-error"
        case requestError = "request-error"
        case unsupported
    }

    enum RootTab: String, Sendable {
        case dock
        case archive
        case relay
    }

    enum DockRowAction: String, Sendable {
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

    enum Root {
        public static let tabs = AutomationID("codexdock.root.tabs")

        public static func tab(_ tab: RootTab) -> AutomationID {
            AutomationID("codexdock.root.tab.\(tab.rawValue)")
        }
    }

    enum Connectivity {
        public static let globalIndicator = AutomationID("codexdock.connectivity.global")
    }

    enum Dock {
        public static let root = AutomationID("codexdock.dock.root")
        public static let filterPicker = AutomationID("codexdock.dock.filter")
        public static let searchField = AutomationID("codexdock.dock.search")
        public static let sortPicker = AutomationID("codexdock.dock.sort")
        public static let idleToggle = AutomationID("codexdock.dock.idle-toggle")
        public static let addHostButton = AutomationID("codexdock.dock.add-host")

        public static func state(_ kind: StateKind) -> AutomationID {
            AutomationID("codexdock.dock.state.\(kind.rawValue)")
        }

        public static func filterTab(_ tabID: String) -> AutomationID {
            AutomationID("codexdock.dock.filter.\(safeSegment(tabID))")
        }

        public static func hostSummary(hostID: String) -> AutomationID {
            AutomationID("codexdock.dock.host.\(safeSegment(hostID))")
        }

        public static func section(_ sectionID: String) -> AutomationID {
            AutomationID("codexdock.dock.section.\(safeSegment(sectionID))")
        }

        public static func scopeConflict(hostID: String, threadID: String) -> AutomationID {
            AutomationID("codexdock.dock.state.scope-conflict.\(safeSegment(hostID)).\(safeSegment(threadID))")
        }

        public static func scopeLoadFailure(hostID: String, scopeID: String) -> AutomationID {
            AutomationID("codexdock.dock.state.scope-load-failure.\(safeSegment(hostID)).\(safeSegment(scopeID))")
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
    }

    enum Relay {
        public static let root = AutomationID("codexdock.relay.root")
        public static let testAllButton = AutomationID("codexdock.relay.test-all")
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

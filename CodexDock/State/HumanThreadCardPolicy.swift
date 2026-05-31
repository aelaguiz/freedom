import Foundation

extension DockThreadCardDTO {
    var isAppFacingHumanThreadCard: Bool {
        lane == .human && sourceKind == .human
    }
}

extension LocalThreadMetadata {
    var hasAppFacingHumanPinnedDisplay: Bool {
        lastKnownPinnedDisplay?.originKind == .human
    }
}

import Foundation

extension DockThreadCardDTO {
    var isAppFacingHumanThreadCard: Bool {
        lane == .human && sourceKind == .human
    }
}

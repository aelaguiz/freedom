import Foundation

public struct RenderRevision: Equatable, Comparable, Hashable, Sendable {
    public let rawValue: UInt64

    public init(rawValue: UInt64 = 0) {
        self.rawValue = rawValue
    }

    public static let zero = RenderRevision()

    public func next() -> RenderRevision {
        RenderRevision(rawValue: rawValue + 1)
    }

    public static func < (lhs: RenderRevision, rhs: RenderRevision) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

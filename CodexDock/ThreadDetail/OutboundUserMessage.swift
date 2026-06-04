import Foundation

public struct ClientUserMessageID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func make() -> ClientUserMessageID {
        ClientUserMessageID(rawValue: "dock-msg:\(UUID().uuidString.lowercased())")
    }
}

public enum OutboundMessageDeliveryState: Equatable, Sendable {
    case pendingLocal
    case acceptedByRelay
    case submittedUpstream
    case canonicalObserved
    case failedDefinite(String)
    case failedAmbiguous(String)

    init(response: ThreadMessageSendResponseDTO) {
        switch response.state {
        case "acceptedByRelay":
            self = .acceptedByRelay
        case "submittedUpstream":
            self = .submittedUpstream
        case "canonicalObserved":
            self = .canonicalObserved
        case "failedDefinite":
            self = .failedDefinite(response.error ?? "Message failed.")
        case "failedAmbiguous":
            self = .failedAmbiguous(response.error ?? "Message delivery is uncertain.")
        default:
            self = .submittedUpstream
        }
    }

    var label: String {
        switch self {
        case .pendingLocal:
            return "Pending"
        case .acceptedByRelay:
            return "Accepted"
        case .submittedUpstream:
            return "Sending"
        case .canonicalObserved:
            return "Sent"
        case .failedDefinite:
            return "Failed"
        case .failedAmbiguous:
            return "Check"
        }
    }

    var message: String? {
        switch self {
        case .failedDefinite(let message), .failedAmbiguous(let message):
            return message
        case .pendingLocal, .acceptedByRelay, .submittedUpstream, .canonicalObserved:
            return nil
        }
    }
}

public struct PendingOutboundMessage: Identifiable, Equatable, Sendable {
    public let id: ClientUserMessageID
    public let threadID: String
    public let input: [TurnUserInputDTO]
    public let createdAt: Date
    public var deliveryState: OutboundMessageDeliveryState
    public var canonicalTurnID: String?
    public var canonicalItemID: String?

    public init(
        id: ClientUserMessageID = .make(),
        threadID: String,
        input: [TurnUserInputDTO],
        createdAt: Date,
        deliveryState: OutboundMessageDeliveryState = .pendingLocal,
        canonicalTurnID: String? = nil,
        canonicalItemID: String? = nil
    ) {
        self.id = id
        self.threadID = threadID
        self.input = input
        self.createdAt = createdAt
        self.deliveryState = deliveryState
        self.canonicalTurnID = canonicalTurnID
        self.canonicalItemID = canonicalItemID
    }

    public var body: String {
        let text = input
            .map(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "User input" : text
    }

    func event(sourceHostID: String, threadID: String) -> ThreadEvent {
        let projectionID = "pending:\(sourceHostID):\(threadID):\(id.rawValue)"
        return ThreadEvent(
            id: projectionID,
            kind: .userMessage,
            visibilityCategory: .message,
            title: "User message",
            body: body,
            date: createdAt,
            isLive: false,
            turnID: canonicalTurnID,
            itemID: canonicalItemID,
            displayOrderKey: Self.displayOrderKey(activityDate: createdAt, projectionID: projectionID),
            displayGroupDate: createdAt,
            activityDate: createdAt,
            clientID: id.rawValue,
            outboundDeliveryState: deliveryState
        )
    }

    private static func displayOrderKey(activityDate: Date, projectionID: String) -> String {
        let maxSortMilliseconds: Int64 = 9_999_999_999_999_999
        let maxOrder = "9999999999"
        let activityMilliseconds = max(0, Int64((activityDate.timeIntervalSince1970 * 1_000).rounded()))
        let invertedMilliseconds = max(0, maxSortMilliseconds - min(maxSortMilliseconds, activityMilliseconds))
        return [
            String(format: "%016lld", invertedMilliseconds),
            maxOrder,
            maxOrder,
            maxOrder,
            projectionID,
        ].joined(separator: "|")
    }
}

struct PendingOutboundMessageRegistry: Equatable, Sendable {
    private var messagesByID: [ClientUserMessageID: PendingOutboundMessage] = [:]

    mutating func insert(_ message: PendingOutboundMessage) {
        messagesByID[message.id] = message
    }

    mutating func update(
        _ id: ClientUserMessageID,
        _ update: (inout PendingOutboundMessage) -> Void
    ) -> Bool {
        guard var message = messagesByID[id] else {
            return false
        }
        update(&message)
        messagesByID[id] = message
        return true
    }

    mutating func prune(canonicalEvents: [ThreadEvent]) {
        let canonicalClientIDs = Set(canonicalEvents.compactMap(\.clientID))
        guard !canonicalClientIDs.isEmpty else {
            return
        }
        messagesByID = messagesByID.filter { id, _ in
            !canonicalClientIDs.contains(id.rawValue)
        }
    }

    func sortedMessages() -> [PendingOutboundMessage] {
        messagesByID.values.sorted { left, right in
            if left.createdAt != right.createdAt {
                return left.createdAt > right.createdAt
            }
            return left.id.rawValue < right.id.rawValue
        }
    }
}

import Foundation

public struct AudioTranscriptionStartParams: Codable, Equatable, Sendable {
    public let language: String?
    public let delay: String?

    public init(language: String? = nil, delay: String? = nil) {
        self.language = language
        self.delay = delay
    }
}

public struct AudioTranscriptionStartResponseDTO: Codable, Equatable, Sendable {
    public let sessionId: String
    public let format: String
    public let sampleRate: Int
    public let model: String?
    public let language: String?
    public let delay: String?

    public init(
        sessionId: String,
        format: String,
        sampleRate: Int,
        model: String? = nil,
        language: String? = nil,
        delay: String? = nil
    ) {
        self.sessionId = sessionId
        self.format = format
        self.sampleRate = sampleRate
        self.model = model
        self.language = language
        self.delay = delay
    }
}

public struct AudioTranscriptionAppendParams: Codable, Equatable, Sendable {
    public let sessionId: String
    public let sequence: Int
    public let base64Audio: String

    public init(sessionId: String, sequence: Int, base64Audio: String) {
        self.sessionId = sessionId
        self.sequence = sequence
        self.base64Audio = base64Audio
    }
}

public struct AudioTranscriptionAppendResponseDTO: Codable, Equatable, Sendable {
    public let sessionId: String
    public let acceptedSequence: Int

    public init(sessionId: String, acceptedSequence: Int) {
        self.sessionId = sessionId
        self.acceptedSequence = acceptedSequence
    }
}

public struct AudioTranscriptionCommitParams: Codable, Equatable, Sendable {
    public let sessionId: String

    public init(sessionId: String) {
        self.sessionId = sessionId
    }
}

public struct AudioTranscriptionCommitResponseDTO: Codable, Equatable, Sendable {
    public let sessionId: String
    public let committed: Bool

    public init(sessionId: String, committed: Bool) {
        self.sessionId = sessionId
        self.committed = committed
    }
}

public struct AudioTranscriptionCancelParams: Codable, Equatable, Sendable {
    public let sessionId: String

    public init(sessionId: String) {
        self.sessionId = sessionId
    }
}

public struct AudioTranscriptionCancelResponseDTO: Codable, Equatable, Sendable {
    public let sessionId: String
    public let canceled: Bool

    public init(sessionId: String, canceled: Bool) {
        self.sessionId = sessionId
        self.canceled = canceled
    }
}

public struct AudioTranscriptionDeltaNotificationDTO: Codable, Equatable, Sendable {
    public let sessionId: String
    public let itemId: String?
    public let contentIndex: Int?
    public let deltaText: String
    public let partialText: String

    public init(
        sessionId: String,
        itemId: String? = nil,
        contentIndex: Int? = nil,
        deltaText: String,
        partialText: String
    ) {
        self.sessionId = sessionId
        self.itemId = itemId
        self.contentIndex = contentIndex
        self.deltaText = deltaText
        self.partialText = partialText
    }
}

public struct AudioTranscriptionCompletedNotificationDTO: Codable, Equatable, Sendable {
    public let sessionId: String
    public let itemId: String?
    public let contentIndex: Int?
    public let transcript: String

    public init(
        sessionId: String,
        itemId: String? = nil,
        contentIndex: Int? = nil,
        transcript: String
    ) {
        self.sessionId = sessionId
        self.itemId = itemId
        self.contentIndex = contentIndex
        self.transcript = transcript
    }
}

public struct AudioTranscriptionFailedNotificationDTO: Codable, Equatable, Sendable {
    public let sessionId: String
    public let reason: String

    public init(sessionId: String, reason: String) {
        self.sessionId = sessionId
        self.reason = reason
    }
}

public struct AudioTranscriptionCanceledNotificationDTO: Codable, Equatable, Sendable {
    public let sessionId: String

    public init(sessionId: String) {
        self.sessionId = sessionId
    }
}

public struct AudioTranscriptionClosedNotificationDTO: Codable, Equatable, Sendable {
    public let sessionId: String
    public let reason: String

    public init(sessionId: String, reason: String) {
        self.sessionId = sessionId
        self.reason = reason
    }
}

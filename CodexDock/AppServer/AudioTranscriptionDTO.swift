import Foundation

public struct AudioTranscribeParams: Codable, Equatable, Sendable {
    public let mimeType: String
    public let base64Audio: String

    public init(mimeType: String, base64Audio: String) {
        self.mimeType = mimeType
        self.base64Audio = base64Audio
    }
}

public struct AudioTranscribeResponseDTO: Codable, Equatable, Sendable {
    public let text: String

    public init(text: String) {
        self.text = text
    }
}

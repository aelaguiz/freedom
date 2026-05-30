import Foundation

actor TranscriptionEngine {
    func normalizedTranscript(_ transcript: String) -> String {
        transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func draft(base: String, transcript: String) -> String {
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranscript.isEmpty else {
            return base
        }
        guard !base.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return trimmedTranscript
        }
        if base.last?.isWhitespace == true {
            return base + trimmedTranscript
        }
        return "\(base) \(trimmedTranscript)"
    }

    func finalDraft(base: String, transcript: String) throws -> String {
        let finalTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !finalTranscript.isEmpty else {
            throw TranscriptionServiceError.emptyTranscript
        }
        return draft(base: base, transcript: finalTranscript)
    }
}

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol TranscriptionServicing: Sendable {
    func transcribe(audioFile: URL) async throws -> String
}

public enum TranscriptionServiceError: Error, Equatable, LocalizedError, Sendable {
    case missingAPIKey
    case emptyTranscript
    case invalidResponse
    case requestFailed(statusCode: Int)
    case transportFailed

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OpenAI transcription key is not configured."
        case .emptyTranscript:
            return "No speech was detected."
        case .invalidResponse:
            return "Transcription response could not be read."
        case .requestFailed:
            return "Transcription request failed."
        case .transportFailed:
            return "Transcription could not reach OpenAI."
        }
    }
}

public struct OpenAITranscriptionConfiguration: Equatable, Sendable {
    public let apiKey: String?
    public let model: String
    public let endpoint: URL

    public init(
        apiKey: String?,
        model: String = "gpt-4o-transcribe",
        endpoint: URL = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
    ) {
        self.apiKey = Self.normalized(apiKey)
        self.model = Self.normalized(model) ?? "gpt-4o-transcribe"
        self.endpoint = endpoint
    }

    public static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> OpenAITranscriptionConfiguration {
        OpenAITranscriptionConfiguration(
            apiKey: environment["OPENAI_API_KEY"],
            model: environment["CODEX_DOCK_OPENAI_TRANSCRIPTION_MODEL"] ?? "gpt-4o-transcribe"
        )
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            return trimmed
        }
        return nil
    }
}

public struct OpenAITranscriptionClient: TranscriptionServicing {
    private struct TranscriptionResponse: Decodable {
        let text: String
    }

    private let configuration: OpenAITranscriptionConfiguration
    private let session: URLSession
    private let boundaryPrefix = "CodexDockBoundary"

    public init(
        configuration: OpenAITranscriptionConfiguration = .fromEnvironment(),
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.session = session
    }

    public func transcribe(audioFile: URL) async throws -> String {
        guard let apiKey = configuration.apiKey else {
            throw TranscriptionServiceError.missingAPIKey
        }

        var request = URLRequest(url: configuration.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let boundary = "\(boundaryPrefix)-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let body = try multipartBody(
            audioFile: audioFile,
            model: configuration.model,
            boundary: boundary
        )

        do {
            let (data, response) = try await session.upload(for: request, from: body)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw TranscriptionServiceError.invalidResponse
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw TranscriptionServiceError.requestFailed(statusCode: httpResponse.statusCode)
            }

            let decoded = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
            let transcript = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !transcript.isEmpty else {
                throw TranscriptionServiceError.emptyTranscript
            }
            return transcript
        } catch let error as TranscriptionServiceError {
            throw error
        } catch is DecodingError {
            throw TranscriptionServiceError.invalidResponse
        } catch {
            throw TranscriptionServiceError.transportFailed
        }
    }

    private func multipartBody(
        audioFile: URL,
        model: String,
        boundary: String
    ) throws -> Data {
        var body = Data()
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        body.appendString("\(model)\r\n")

        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n")
        body.appendString("json\r\n")

        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"file\"; filename=\"recording.m4a\"\r\n")
        body.appendString("Content-Type: audio/mp4\r\n\r\n")
        body.append(try Data(contentsOf: audioFile))
        body.appendString("\r\n")
        body.appendString("--\(boundary)--\r\n")
        return body
    }
}

private extension Data {
    mutating func appendString(_ value: String) {
        append(Data(value.utf8))
    }
}

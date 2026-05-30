import Foundation
import OSLog

public enum DockLog {
    public static let subsystem = "com.aelaguiz.CodexDock"

    public static let app = logger("app")
    public static let appLifecycle = logger("appLifecycle")
    public static let bootstrap = logger("bootstrap")
    public static let relayDiscovery = logger("relayDiscovery")
    public static let hostConfiguration = logger("hostConfiguration")
    public static let appServer = logger("appServer")
    public static let dock = logger("dock")
    public static let archive = logger("archive")
    public static let threadDetail = logger("threadDetail")
    public static let connectivity = logger("connectivity")
    public static let voice = logger("voice")
    public static let transcription = logger("transcription")
    public static let persistence = logger("persistence")
    public static let metrics = logger("metrics")
    public static let rendering = logger("rendering")
    public static let runtime = logger("runtime")

    public static func logger(_ category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }

    public static func endpoint(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return redacted(url.absoluteString)
        }
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        return redacted(components.string ?? url.absoluteString)
    }

    public static func publicID(_ value: CustomStringConvertible?) -> String {
        guard let value else {
            return "none"
        }
        return clipped(String(describing: value), maxLength: 96)
    }

    public static func errorSummary(_ error: Error) -> String {
        let typeName = String(describing: type(of: error))
        let message: String
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription,
           !description.isEmpty {
            message = description
        } else {
            message = error.localizedDescription
        }
        return "\(typeName): \(redacted(message))"
    }

    public static func milliseconds(since start: Date, now: Date = Date()) -> Int {
        max(0, Int((now.timeIntervalSince(start) * 1_000).rounded()))
    }

    public static func redacted(_ value: String, maxLength: Int = 240) -> String {
        var result = value
        let replacements: [(String, String)] = [
            (#"(?i)bearer\s+[A-Za-z0-9._~+/=-]+"#, "Bearer <redacted>"),
            (#"(?i)(authorization|api[_-]?key|openai[_-]?api[_-]?key|token|secret)\s*[:=]\s*[^ \r\n;,]+"#, "$1=<redacted>"),
            (#"sk-[A-Za-z0-9]{16,}"#, "sk-<redacted>"),
            (#"\b[A-Za-z0-9+/]{120,}={0,2}\b"#, "<redacted-large-token>"),
        ]

        for (pattern, template) in replacements {
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                continue
            }
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: template
            )
        }

        return clipped(result, maxLength: maxLength)
    }

    private static func clipped(_ value: String, maxLength: Int) -> String {
        guard value.count > maxLength else {
            return value
        }
        let suffix = "..."
        let endIndex = value.index(value.startIndex, offsetBy: max(0, maxLength - suffix.count))
        return "\(value[..<endIndex])\(suffix)"
    }
}

public enum DockSignpost {
    public static let appServer = OSSignposter(logger: DockLog.appServer)
    public static let dock = OSSignposter(logger: DockLog.dock)
    public static let archive = OSSignposter(logger: DockLog.archive)
    public static let threadDetail = OSSignposter(logger: DockLog.threadDetail)
    public static let voice = OSSignposter(logger: DockLog.voice)
    public static let transcription = OSSignposter(logger: DockLog.transcription)
    public static let hostConfiguration = OSSignposter(logger: DockLog.hostConfiguration)
    public static let rendering = OSSignposter(logger: DockLog.rendering)
}

public enum RenderSignpostName {
    public static let dockModelApply: StaticString = "dock.model.apply"
    public static let dockRenderProject: StaticString = "dock.render.project"
    public static let dockRenderCoalesce: StaticString = "dock.render.coalesce"
    public static let dockMainPublish: StaticString = "dock.main.publish"
    public static let threadModelPage: StaticString = "thread.model.page"
    public static let threadModelNormalize: StaticString = "thread.model.normalize"
    public static let threadRenderProject: StaticString = "thread.render.project"
    public static let threadMainPublish: StaticString = "thread.main.publish"
    public static let connectivityRenderProject: StaticString = "connectivity.render.project"
    public static let commandIntentToRender: StaticString = "command.intent.to.render"
    public static let voiceTranscriptPublish: StaticString = "voice.transcript.publish"
}

import Foundation

#if canImport(MetricKit)
import MetricKit
#endif

public final class MetricKitDiagnosticsReporter: NSObject, @unchecked Sendable {
    public static let shared = MetricKitDiagnosticsReporter()

    private let fileManager: FileManager
    private let directoryURL: URL
    private var didStart = false
    private var didLogPersistenceFailure = false

    public init(
        fileManager: FileManager = .default,
        directoryURL: URL = MetricKitDiagnosticsReporter.defaultDirectoryURL()
    ) {
        self.fileManager = fileManager
        self.directoryURL = directoryURL
        super.init()
    }

    public func start() {
        guard !didStart else {
            return
        }
        didStart = true

        #if canImport(MetricKit)
        MXMetricManager.shared.add(self)
        DockLog.metrics.notice("MetricKit diagnostics reporter started")
        #else
        DockLog.metrics.notice("MetricKit diagnostics reporter unavailable on this platform")
        #endif
    }

    public static func defaultDirectoryURL() -> URL {
        let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return directory
            .appendingPathComponent("CodexDock", isDirectory: true)
            .appendingPathComponent("Diagnostics", isDirectory: true)
    }

    private func persistLatestPayload(_ data: Data, name: String) {
        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            try data.write(
                to: directoryURL.appendingPathComponent(name),
                options: [.atomic]
            )
        } catch {
            if !didLogPersistenceFailure {
                didLogPersistenceFailure = true
                DockLog.metrics.error("MetricKit payload persistence failed error=\(DockLog.errorSummary(error), privacy: .public)")
            }
        }
    }

    private static func summary(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return "json=unreadable"
        }

        let keys = [
            "crashDiagnostics",
            "hangDiagnostics",
            "cpuExceptionDiagnostics",
            "diskWriteExceptionDiagnostics",
            "appLaunchDiagnostics",
            "applicationLaunchMetrics",
        ]
        let parts = keys.map { key in
            "\(key)=\(count(for: key, in: dictionary))"
        }
        return parts.joined(separator: " ")
    }

    private static func count(for key: String, in dictionary: [String: Any]) -> Int {
        guard let value = dictionary[key] else {
            return 0
        }
        if let array = value as? [Any] {
            return array.count
        }
        if let dictionary = value as? [String: Any] {
            return dictionary.isEmpty ? 0 : 1
        }
        return 1
    }
}

#if canImport(MetricKit)
extension MetricKitDiagnosticsReporter: MXMetricManagerSubscriber {
    public func didReceive(_ payloads: [MXMetricPayload]) {
        for (index, payload) in payloads.enumerated() {
            let data = payload.jsonRepresentation()
            DockLog.metrics.notice("MetricKit metrics delivered index=\(index, privacy: .public) \(Self.summary(from: data), privacy: .public)")
            persistLatestPayload(data, name: "latest-metrics.json")
        }
    }

    public func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for (index, payload) in payloads.enumerated() {
            let data = payload.jsonRepresentation()
            DockLog.metrics.fault("MetricKit diagnostics delivered index=\(index, privacy: .public) \(Self.summary(from: data), privacy: .public)")
            persistLatestPayload(data, name: "latest-diagnostics.json")
        }
    }
}
#endif

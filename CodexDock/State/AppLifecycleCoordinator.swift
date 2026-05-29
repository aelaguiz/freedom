import Combine
import Foundation

public enum AppScenePhase: Equatable, Sendable {
    case active
    case inactive
    case background
}

public enum AppLifecyclePhase: Equatable, Sendable {
    case active
    case inactive
    case backgrounded
    case foregroundResuming
}

public struct AppLifecycleSnapshot: Equatable, Sendable {
    public let phase: AppLifecyclePhase
    public let resumeGeneration: Int

    public var allowsForegroundWork: Bool {
        switch phase {
        case .active, .foregroundResuming:
            return true
        case .inactive, .backgrounded:
            return false
        }
    }
}

public protocol AppForegroundWorkGating: AnyObject, Sendable {
    @MainActor var allowsForegroundWork: Bool { get }
}

@MainActor
public final class AppLifecycleCoordinator: ObservableObject, @unchecked Sendable {
    @Published public private(set) var snapshot: AppLifecycleSnapshot
    public var snapshots: AsyncStream<AppLifecycleSnapshot> {
        makeSnapshotStream()
    }

    private var continuations: [UUID: AsyncStream<AppLifecycleSnapshot>.Continuation] = [:]
    private var wasBackgrounded = false

    public init() {
        self.snapshot = AppLifecycleSnapshot(phase: .active, resumeGeneration: 0)
        DockLog.appLifecycle.notice("app lifecycle initialized phase=active resume_generation=0")
    }

    deinit {
        for continuation in continuations.values {
            continuation.finish()
        }
    }

    public var allowsForegroundWork: Bool {
        snapshot.allowsForegroundWork
    }

    public func makeSnapshotStream() -> AsyncStream<AppLifecycleSnapshot> {
        let id = UUID()
        let currentSnapshot = snapshot
        return AsyncStream { continuation in
            continuation.yield(currentSnapshot)
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    self?.continuations[id] = nil
                }
            }
        }
    }

    public func handle(_ scenePhase: AppScenePhase) {
        switch scenePhase {
        case .active:
            if snapshot.phase == .foregroundResuming {
                return
            } else if wasBackgrounded {
                wasBackgrounded = false
                setPhase(.foregroundResuming, resumeGeneration: snapshot.resumeGeneration + 1)
            } else {
                setPhase(.active, resumeGeneration: snapshot.resumeGeneration)
            }
        case .inactive:
            setPhase(.inactive, resumeGeneration: snapshot.resumeGeneration)
        case .background:
            wasBackgrounded = true
            setPhase(.backgrounded, resumeGeneration: snapshot.resumeGeneration)
        }
    }

    public func finishForegroundResume() {
        guard snapshot.phase == .foregroundResuming else {
            return
        }
        setPhase(.active, resumeGeneration: snapshot.resumeGeneration)
    }

    private func setPhase(_ phase: AppLifecyclePhase, resumeGeneration: Int) {
        let next = AppLifecycleSnapshot(phase: phase, resumeGeneration: resumeGeneration)
        guard snapshot != next else {
            return
        }
        DockLog.appLifecycle.notice("app lifecycle phase changed from=\(self.snapshot.phase.logDescription, privacy: .public) to=\(phase.logDescription, privacy: .public) resume_generation=\(resumeGeneration, privacy: .public)")
        snapshot = next
        for continuation in continuations.values {
            continuation.yield(next)
        }
    }
}

extension AppLifecycleCoordinator: AppForegroundWorkGating {}

private extension AppLifecyclePhase {
    var logDescription: String {
        switch self {
        case .active:
            return "active"
        case .inactive:
            return "inactive"
        case .backgrounded:
            return "backgrounded"
        case .foregroundResuming:
            return "foregroundResuming"
        }
    }
}

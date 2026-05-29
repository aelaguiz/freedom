import XCTest
@testable import CodexDock

final class AppLifecycleCoordinatorTests: XCTestCase {
    @MainActor
    func testInactiveIsTransitionalAndDoesNotAdvanceResumeGeneration() {
        let coordinator = AppLifecycleCoordinator()

        coordinator.handle(.inactive)

        XCTAssertEqual(
            coordinator.snapshot,
            AppLifecycleSnapshot(phase: .inactive, resumeGeneration: 0)
        )
        XCTAssertFalse(coordinator.allowsForegroundWork)
    }

    @MainActor
    func testBackgroundThenActivePublishesForegroundResumeGeneration() {
        let coordinator = AppLifecycleCoordinator()

        coordinator.handle(.background)
        XCTAssertEqual(
            coordinator.snapshot,
            AppLifecycleSnapshot(phase: .backgrounded, resumeGeneration: 0)
        )
        XCTAssertFalse(coordinator.allowsForegroundWork)

        coordinator.handle(.active)
        XCTAssertEqual(
            coordinator.snapshot,
            AppLifecycleSnapshot(phase: .foregroundResuming, resumeGeneration: 1)
        )
        XCTAssertTrue(coordinator.allowsForegroundWork)

        coordinator.handle(.active)
        XCTAssertEqual(
            coordinator.snapshot,
            AppLifecycleSnapshot(phase: .foregroundResuming, resumeGeneration: 1)
        )

        coordinator.finishForegroundResume()
        XCTAssertEqual(
            coordinator.snapshot,
            AppLifecycleSnapshot(phase: .active, resumeGeneration: 1)
        )
    }

    @MainActor
    func testSnapshotStreamsReceiveLifecycleChanges() async throws {
        let coordinator = AppLifecycleCoordinator()
        let stream = coordinator.makeSnapshotStream()
        let task = Task {
            var iterator = stream.makeAsyncIterator()
            var snapshots: [AppLifecycleSnapshot] = []
            while snapshots.count < 3, let snapshot = await iterator.next() {
                snapshots.append(snapshot)
            }
            return snapshots
        }

        coordinator.handle(.background)
        coordinator.handle(.active)

        let snapshots = try await valueWithinOneSecond {
            await task.value
        }
        XCTAssertEqual(snapshots, [
            AppLifecycleSnapshot(phase: .active, resumeGeneration: 0),
            AppLifecycleSnapshot(phase: .backgrounded, resumeGeneration: 0),
            AppLifecycleSnapshot(phase: .foregroundResuming, resumeGeneration: 1),
        ])
    }
}

private func valueWithinOneSecond<T: Sendable>(
    _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(for: .seconds(1))
            throw TestTimeoutError()
        }

        guard let value = try await group.next() else {
            throw TestTimeoutError()
        }
        group.cancelAll()
        return value
    }
}

private struct TestTimeoutError: Error {}

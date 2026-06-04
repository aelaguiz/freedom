import Foundation
import XCTest

private struct DisplayedUIDockAutomationSnapshot: Codable {
    var schemaVersion: Int
    var revision: UInt64
    var rows: [DisplayedUIDockRow]
}

extension XCUIApplication {
    func dockRowsFromAutomationSnapshot(_ rootValue: String) -> [DisplayedUIDockRow]? {
        guard rootValue != "not-visible" else {
            return nil
        }
        guard rootValue.contains("loaded") else {
            return []
        }
        guard let revisionText = codexDockAutomationField("automationRevision", in: rootValue),
              let expectedRevision = UInt64(revisionText),
              let rawPath = codexDockAutomationField("automationSnapshotPath", in: rootValue),
              !rawPath.isEmpty else {
            return nil
        }
        do {
            let snapshotURL = try dockAutomationSnapshotURL(relativePath: rawPath)
            let data = try Data(contentsOf: snapshotURL)
            let snapshot = try JSONDecoder().decode(DisplayedUIDockAutomationSnapshot.self, from: data)
            guard snapshot.schemaVersion == 1 else {
                throw dockAutomationSnapshotError("unsupported schemaVersion=\(snapshot.schemaVersion)")
            }
            guard snapshot.revision == expectedRevision else {
                throw dockAutomationSnapshotError(
                    "stale snapshot revision=\(snapshot.revision) expected=\(expectedRevision)"
                )
            }
            return snapshot.rows
        } catch {
            XCTFail("Dock automation snapshot read failed: \(error)")
            return []
        }
    }

    private func dockAutomationSnapshotURL(relativePath rawPath: String) throws -> URL {
        let relativePath = rawPath.removingPercentEncoding ?? rawPath
        guard !relativePath.hasPrefix("/") else {
            throw dockAutomationSnapshotError("automationSnapshotPath must be Application Support relative")
        }
        let candidates = dockAutomationAppDataContainers()
        for container in candidates {
            let url = dockAutomationSnapshotURL(container: container, relativePath: relativePath)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        if let firstContainer = candidates.first {
            return dockAutomationSnapshotURL(container: firstContainer, relativePath: relativePath)
        }
        throw dockAutomationSnapshotError(
            "missing CODEX_DOCK_UI_TEST_APP_DATA_CONTAINER and unable to resolve simulator app data container"
        )
    }

    private func dockAutomationSnapshotURL(container: String, relativePath: String) -> URL {
        URL(fileURLWithPath: container, isDirectory: true)
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(relativePath, isDirectory: false)
    }

    private func dockAutomationAppDataContainers() -> [String] {
        var containers: [String] = []

        func append(_ container: String?) {
            guard let container = displayedUINonEmpty(container),
                  !containers.contains(container) else {
                return
            }
            containers.append(container)
        }

        if let dumpConfig = try? DisplayedUICurrentDumpConfig.load() {
            append(dumpConfig.appDataContainer)
            append(dockAutomationSimulatorAppDataContainer(
                udid: dumpConfig.simulatorUDID,
                bundleID: dumpConfig.appBundleID
            ))
        }
        let environment = ProcessInfo.processInfo.environment
        append(environment["CODEX_DOCK_UI_TEST_APP_DATA_CONTAINER"])
        if let udid = displayedUINonEmpty(environment["CODEX_DOCK_UI_TEST_SIMULATOR_UDID"]),
           let bundleID = displayedUINonEmpty(environment["CODEX_DOCK_UI_TEST_APP_BUNDLE_ID"]),
           let simulatorContainer = dockAutomationSimulatorAppDataContainer(
            udid: udid,
            bundleID: bundleID
           ) {
            append(simulatorContainer)
        }
        return containers
    }

    private func dockAutomationSimulatorAppDataContainer(
        udid rawUDID: String,
        bundleID rawBundleID: String
    ) -> String? {
        guard let udid = displayedUINonEmpty(rawUDID),
              let bundleID = displayedUINonEmpty(rawBundleID) else {
            return nil
        }
        let environment = ProcessInfo.processInfo.environment
        let homeCandidates = [
            environment["SIMULATOR_HOST_HOME"],
            environment["HOME"],
            NSHomeDirectory(),
        ].compactMap(displayedUINonEmpty)

        for home in homeCandidates {
            let applicationsURL = URL(fileURLWithPath: home, isDirectory: true)
                .appendingPathComponent("Library/Developer/CoreSimulator/Devices", isDirectory: true)
                .appendingPathComponent(udid, isDirectory: true)
                .appendingPathComponent("data/Containers/Data/Application", isDirectory: true)
            if let container = dockAutomationSimulatorAppDataContainer(
                applicationsURL: applicationsURL,
                bundleID: bundleID
            ) {
                return container
            }
        }
        return nil
    }

    private func dockAutomationSimulatorAppDataContainer(
        applicationsURL: URL,
        bundleID: String
    ) -> String? {
        let fileManager = FileManager.default
        guard let containerURLs = try? fileManager.contentsOfDirectory(
            at: applicationsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        for containerURL in containerURLs {
            guard let resourceValues = try? containerURL.resourceValues(forKeys: [.isDirectoryKey]),
                  resourceValues.isDirectory == true else {
                continue
            }
            let metadataURL = containerURL.appendingPathComponent(
                ".com.apple.mobile_container_manager.metadata.plist",
                isDirectory: false
            )
            guard let metadataData = try? Data(contentsOf: metadataURL),
                  let metadata = try? PropertyListSerialization.propertyList(
                    from: metadataData,
                    options: [],
                    format: nil
                  ) as? [String: Any],
                  metadata["MCMMetadataIdentifier"] as? String == bundleID else {
                continue
            }
            return containerURL.path
        }
        return nil
    }

    private func dockAutomationSnapshotError(_ description: String) -> NSError {
        NSError(
            domain: "CodexDockDisplayedUISnapshot",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: description]
        )
    }
}

func displayedUINonEmpty(_ value: String?) -> String? {
    guard let value else {
        return nil
    }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

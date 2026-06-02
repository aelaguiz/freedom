import Foundation

public struct DockHostIdentityObservation: Equatable, Sendable {
    public let configuredHostID: String
    public let streamHostID: String?
    public let logicalHostID: String?
    public let displayName: String?
    public let endpoint: String?

    public init(
        configuredHostID: String,
        streamHostID: String? = nil,
        logicalHostID: String? = nil,
        displayName: String? = nil,
        endpoint: String? = nil
    ) {
        self.configuredHostID = configuredHostID
        self.streamHostID = Self.nonEmpty(streamHostID)
        self.logicalHostID = Self.nonEmpty(logicalHostID)
        self.displayName = Self.nonEmpty(displayName)
        self.endpoint = Self.nonEmpty(endpoint)
    }

    init(configuredHostID: String, card: DockThreadCardDTO) {
        self.init(
            configuredHostID: configuredHostID,
            streamHostID: card.sourceHostID,
            logicalHostID: card.logicalHostID,
            displayName: card.hostDisplayName,
            endpoint: card.hostEndpoint
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

public struct ResolvedDockHost: Equatable, Sendable {
    public let logicalHostID: String
    public let host: DockHostConfiguration
    public let configuredHostIDs: [String]
    public let displayName: String
    public let endpoint: String
}

public struct DockHostIdentityResolver: Equatable, Sendable {
    private struct HostRecord: Equatable, Sendable {
        var host: DockHostConfiguration
        var aliases: Set<String>
        var displayNames: [String]
        var endpoints: [String]
        var hasObservedLogicalIdentity: Bool
    }

    private struct LogicalRecord: Equatable, Sendable {
        var logicalHostID: String
        var records: [HostRecord]
        var hasObservedLogicalIdentity: Bool
    }

    public static let empty = DockHostIdentityResolver(hosts: [])

    private let logicalRecordsByID: [String: LogicalRecord]
    private let logicalIDsByAlias: [String: Set<String>]
    private let logicalIDByConfiguredHostID: [String: String]
    private let hostStatuses: [String: DockHostLoadStatus]

    public init(
        hosts: [DockHostConfiguration],
        observations: [DockHostIdentityObservation] = [],
        hostStatuses: [String: DockHostLoadStatus] = [:]
    ) {
        let observationsByConfiguredHostID = Dictionary(grouping: observations, by: \.configuredHostID)
        self.hostStatuses = hostStatuses

        var logicalRecordsByID: [String: LogicalRecord] = [:]
        var logicalIDByConfiguredHostID: [String: String] = [:]

        for host in hosts {
            let hostObservations = observationsByConfiguredHostID[host.id] ?? []
            let observedLogicalHostID = Self.firstNonEmpty(
                hostObservations.map(\.logicalHostID) + hostObservations.map(\.streamHostID)
            )
            let logicalHostID = observedLogicalHostID ?? host.id
            logicalIDByConfiguredHostID[host.id] = logicalHostID

            var aliases = Set<String>()
            [
                host.id,
                host.displayName,
                host.endpoint.displayEndpoint,
                logicalHostID
            ].forEach { Self.insertAlias($0, into: &aliases) }
            for observation in hostObservations {
                [
                    observation.configuredHostID,
                    observation.streamHostID,
                    observation.logicalHostID,
                    observation.displayName,
                    observation.endpoint
                ].forEach { Self.insertAlias($0, into: &aliases) }
            }

            let displayNames = Self.uniqueNonEmpty(
                hostObservations.map(\.displayName) + [host.displayName, logicalHostID]
            )
            let endpoints = Self.uniqueNonEmpty(
                hostObservations.map(\.endpoint) + [host.endpoint.displayEndpoint]
            )
            let record = HostRecord(
                host: host,
                aliases: aliases,
                displayNames: displayNames,
                endpoints: endpoints,
                hasObservedLogicalIdentity: observedLogicalHostID != nil
            )

            var logicalRecord = logicalRecordsByID[logicalHostID]
                ?? LogicalRecord(
                    logicalHostID: logicalHostID,
                    records: [],
                    hasObservedLogicalIdentity: false
                )
            logicalRecord.records.append(record)
            logicalRecord.hasObservedLogicalIdentity = logicalRecord.hasObservedLogicalIdentity || record.hasObservedLogicalIdentity
            logicalRecordsByID[logicalHostID] = logicalRecord
        }

        var logicalIDsByAlias: [String: Set<String>] = [:]
        for logicalRecord in logicalRecordsByID.values {
            for record in logicalRecord.records {
                for alias in record.aliases {
                    logicalIDsByAlias[alias, default: []].insert(logicalRecord.logicalHostID)
                    logicalIDsByAlias[Self.normalizedAlias(alias), default: []].insert(logicalRecord.logicalHostID)
                }
            }
        }

        self.logicalRecordsByID = logicalRecordsByID
        self.logicalIDByConfiguredHostID = logicalIDByConfiguredHostID
        self.logicalIDsByAlias = logicalIDsByAlias
    }

    public func logicalHostID(
        forAlias alias: String,
        sourceConfiguredHostID: String? = nil
    ) -> String? {
        let aliasLogicalIDs = logicalIDs(forAlias: alias)
        if let sourceConfiguredHostID,
           let sourceLogicalID = logicalIDByConfiguredHostID[sourceConfiguredHostID],
           aliasLogicalIDs.isEmpty || aliasLogicalIDs.contains(sourceLogicalID) {
            return sourceLogicalID
        }
        guard aliasLogicalIDs.count == 1 else {
            return nil
        }
        return aliasLogicalIDs.first
    }

    public func migrationLogicalHostID(
        forAlias alias: String,
        sourceConfiguredHostID: String? = nil
    ) -> String? {
        guard let logicalHostID = logicalHostID(
            forAlias: alias,
            sourceConfiguredHostID: sourceConfiguredHostID
        ),
              let logicalRecord = logicalRecordsByID[logicalHostID],
              logicalRecord.hasObservedLogicalIdentity else {
            return nil
        }
        return logicalHostID
    }

    public func resolve(
        rowHostID: String,
        sourceConfiguredHostID: String? = nil,
        preferredConfiguredHostID: String? = nil
    ) -> ResolvedDockHost? {
        let logicalHostID = logicalHostID(
            forAlias: rowHostID,
            sourceConfiguredHostID: sourceConfiguredHostID
        )
        guard let logicalHostID,
              let logicalRecord = logicalRecordsByID[logicalHostID] else {
            return nil
        }

        guard let selectedRecord = preferredRecord(
            in: logicalRecord,
            sourceConfiguredHostID: sourceConfiguredHostID,
            preferredConfiguredHostID: preferredConfiguredHostID
        ) else {
            return nil
        }

        return ResolvedDockHost(
            logicalHostID: logicalHostID,
            host: selectedRecord.host,
            configuredHostIDs: logicalRecord.records.map(\.host.id),
            displayName: selectedRecord.displayNames.first ?? selectedRecord.host.displayName,
            endpoint: selectedRecord.endpoints.first ?? selectedRecord.host.endpoint.displayEndpoint
        )
    }

    public func contains(
        rowHostID: String,
        sourceConfiguredHostID: String? = nil,
        in configuredHostID: String
    ) -> Bool {
        guard let expectedLogicalID = logicalIDByConfiguredHostID[configuredHostID] else {
            return false
        }
        let rowLogicalIDs = logicalIDs(forAlias: rowHostID)
        guard rowLogicalIDs.count == 1,
              rowLogicalIDs.contains(expectedLogicalID) else {
            return false
        }
        guard let sourceConfiguredHostID else {
            return true
        }
        let sourceLogicalIDs = logicalIDs(forAlias: sourceConfiguredHostID)
        if sourceLogicalIDs.isEmpty,
           sourceConfiguredHostID == configuredHostID {
            return true
        }
        return sourceLogicalIDs.count == 1 && sourceLogicalIDs.contains(expectedLogicalID)
    }

    public func displayName(
        forAlias alias: String,
        sourceConfiguredHostID: String? = nil
    ) -> String? {
        resolve(
            rowHostID: alias,
            sourceConfiguredHostID: sourceConfiguredHostID
        )?.displayName
    }

    public func endpoint(
        forAlias alias: String,
        sourceConfiguredHostID: String? = nil
    ) -> String? {
        resolve(
            rowHostID: alias,
            sourceConfiguredHostID: sourceConfiguredHostID
        )?.endpoint
    }

    public func state(
        forAlias alias: String,
        sourceConfiguredHostID: String? = nil,
        in states: [DockHostStateViewModel]
    ) -> DockHostStateViewModel? {
        guard let resolved = resolve(
            rowHostID: alias,
            sourceConfiguredHostID: sourceConfiguredHostID
        ) else {
            return nil
        }
        return states.first { resolved.configuredHostIDs.contains($0.host.id) }
    }

    private func logicalIDs(forAlias alias: String) -> Set<String> {
        let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }
        return logicalIDsByAlias[trimmed]
            ?? logicalIDsByAlias[Self.normalizedAlias(trimmed)]
            ?? []
    }

    private func preferredRecord(
        in logicalRecord: LogicalRecord,
        sourceConfiguredHostID: String?,
        preferredConfiguredHostID: String?
    ) -> HostRecord? {
        if let sourceConfiguredHostID,
           let record = logicalRecord.records.first(where: { $0.host.id == sourceConfiguredHostID }) {
            return record
        }
        if let preferredConfiguredHostID,
           let record = logicalRecord.records.first(where: { $0.host.id == preferredConfiguredHostID }) {
            return record
        }
        if let loadedRecord = logicalRecord.records.first(where: { isLoadedStatus(hostStatuses[$0.host.id]) }) {
            return loadedRecord
        }
        return logicalRecord.records.first
    }

    private func isLoadedStatus(_ status: DockHostLoadStatus?) -> Bool {
        guard let status else {
            return false
        }
        switch status {
        case .loaded, .partial, .empty:
            return true
        case .checking, .offline, .error:
            return false
        }
    }

    private static func insertAlias(_ value: String?, into aliases: inout Set<String>) {
        guard let value = nonEmpty(value) else {
            return
        }
        aliases.insert(value)
    }

    private static func uniqueNonEmpty(_ values: [String?]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values {
            guard let value = nonEmpty(value),
                  seen.insert(value).inserted else {
                continue
            }
            result.append(value)
        }
        return result
    }

    private static func firstNonEmpty(_ values: [String?]) -> String? {
        values.lazy.compactMap(nonEmpty).first
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func normalizedAlias(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

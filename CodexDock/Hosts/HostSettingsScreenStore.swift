import Combine
import Foundation

@MainActor
public final class HostSettingsScreenStore: ObservableObject {
    @Published public private(set) var registry: HostRegistry?
    @Published public private(set) var configurationError: String?
    @Published public private(set) var rows: [HostSettingsRowViewModel]

    public init(
        registry: HostRegistry?,
        configurationError: String?,
        rows: [HostSettingsRowViewModel]
    ) {
        self.registry = registry
        self.configurationError = configurationError
        self.rows = rows
    }

    public func publish(
        registry: HostRegistry?,
        configurationError: String?,
        rows: [HostSettingsRowViewModel]
    ) {
        self.registry = registry
        self.configurationError = configurationError
        self.rows = rows
    }
}

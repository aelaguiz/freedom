import Foundation

public enum CodexDockConstants {
    public enum AppServer {
        public static let defaultRequestTimeout: Duration = .seconds(120)
        public static let connectInitializeTimeout: Duration = .seconds(30)
        public static let reconnectMaxAttempts = 3
        public static let reconnectInitialDelayMilliseconds = 500
        public static let reconnectMaxDelayMilliseconds = 5_000
        public static let reconnectJitterRatio = 0.2
        public static let maximumBackoffExponent = 20
        public static let foregroundPollInterval: Duration = .milliseconds(250)
        public static let maximumMessageSize = 512 * 1024 * 1024
    }

    public enum Dock {
        public static let streamSchemaVersion = 1
        public static let humanSessionPageLimit = 250
        public static let agentSessionPageLimit = 250
        public static let activeSessionMaxPages = 1
        public static let turnPageLimit = 250
        public static let autoRefreshInterval: Duration = .seconds(5)
        public static let streamHeartbeatTimeout: Duration = .seconds(15)
        public static let threadDetailCanonicalHistorySettleDelay: Duration = .seconds(3)
        public static let bonjourResolveTimeout: TimeInterval = 4
    }

    public enum ThreadDetail {
        public static let retainedStoreCapacity = 24
        public static let retainedRefreshMinimumUpdatingMilliseconds = 750
    }

    public enum ArchiveCleanup {
        public static let archiveBatchConcurrency = 1
        public static let restoreBatchConcurrency = 1
        public static let confirmationThreshold = 100
    }

    public enum Voice {
        public static let transcriptionCompletionTimeout: Duration = .seconds(30)
        public static let transcriptionCommandTimeout: Duration = .seconds(10)
        public static let transcriptionCancelTimeout: Duration = .seconds(5)
        public static let transcriptionMaxChunkBytes = 64 * 1024
        public static let sampleRate: Double = 24_000
        public static let channelCount = 1
        public static let tapBufferFrameCount: UInt32 = 2_048
    }

    public enum Rendering {
        public static let mainPublishWarningBudgetMilliseconds = 2
        public static let mainPublishCriticalBudgetMilliseconds = 4
        public static let dockRenderDropsSupersededRevisions = true
        public static let searchDebounceMilliseconds = 80
        public static let voiceTranscriptPublishDebounceMilliseconds = 50
        public static let threadInitialVisibleWindowRows = 240
        public static let threadPaginationPrefetchThresholdRows = 60
        public static let maxDockRowsPerMainPublish = 600
        public static let renderStreamBufferNewest = 1
    }

    public enum Ports {
        public static let rawAppServer = 4_500
        public static let dockRelay = 4_510
        public static let rawAppServerString = String(rawAppServer)
        public static let dockRelayString = String(dockRelay)
        public static let maximumTCPPort = 65_535
    }
}

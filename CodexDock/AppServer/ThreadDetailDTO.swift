import Foundation

public struct ThreadDetailParams: Codable, Equatable, Sendable {
    public let threadId: String

    public init(threadId: String) {
        self.threadId = threadId
    }
}

public enum ThreadDetailUpdateKind: String, Codable, Equatable, Sendable {
    case snapshot
    case page
    case upsert
    case delete
    case heartbeat
    case resyncRequired
}

public enum ThreadDetailRenderState: String, Codable, Equatable, Sendable {
    case live
    case streaming
    case settled
    case stale
    case diagnostic
}

public struct ThreadDetailFreshnessDTO: Codable, Equatable, Sendable {
    public let state: String
    public let asOf: String?
    public let sourceWatermark: String?

    public init(
        state: String,
        asOf: String? = nil,
        sourceWatermark: String? = nil
    ) {
        self.state = state
        self.asOf = asOf
        self.sourceWatermark = sourceWatermark
    }
}

public struct ThreadDetailEventRequestDTO: Codable, Equatable, Sendable {
    public let requestID: JSONRPCRequestID
    public let method: String
    public let params: JSONValue?
    public let status: String?

    public init(
        requestID: JSONRPCRequestID,
        method: String,
        params: JSONValue? = nil,
        status: String? = nil
    ) {
        self.requestID = requestID
        self.method = method
        self.params = params
        self.status = status
    }
}

public struct ThreadDetailEventPayloadDTO: Codable, Equatable, Sendable {
    public let itemType: String?
    public let visibility: ThreadEventVisibilityCategory
    public let renderKind: ThreadEventKind
    public let title: String
    public let body: String
    public let eventTime: String?
    public let activityTime: String?
    public let turnID: String?
    public let itemID: String?
    public let turnOrder: Int?
    public let itemOrder: Int?
    public let rowOrder: Int?
    public let renderState: ThreadDetailRenderState
    public let requestID: String?
    public let request: ThreadDetailEventRequestDTO?
    public let diagnostic: JSONValue?

    public init(
        itemType: String? = nil,
        visibility: ThreadEventVisibilityCategory,
        renderKind: ThreadEventKind,
        title: String,
        body: String,
        eventTime: String? = nil,
        activityTime: String? = nil,
        turnID: String? = nil,
        itemID: String? = nil,
        turnOrder: Int? = nil,
        itemOrder: Int? = nil,
        rowOrder: Int? = nil,
        renderState: ThreadDetailRenderState = .settled,
        requestID: String? = nil,
        request: ThreadDetailEventRequestDTO? = nil,
        diagnostic: JSONValue? = nil
    ) {
        self.itemType = itemType
        self.visibility = visibility
        self.renderKind = renderKind
        self.title = title
        self.body = body
        self.eventTime = eventTime
        self.activityTime = activityTime
        self.turnID = turnID
        self.itemID = itemID
        self.turnOrder = turnOrder
        self.itemOrder = itemOrder
        self.rowOrder = rowOrder
        self.renderState = renderState
        self.requestID = requestID
        self.request = request
        self.diagnostic = diagnostic
    }
}

public struct ThreadDetailEventDTO: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let identityVersion: Int
    public let projectionEngineVersion: Int
    public let sourceHostID: String
    public let view: String
    public let threadID: String
    public let projectionID: String
    public let sourceRef: String
    public let rowRole: String
    public let displayOrderKey: String
    public let revision: Int
    public let freshness: ThreadDetailFreshnessDTO?
    public let payload: ThreadDetailEventPayloadDTO

    public var itemType: String? { payload.itemType }
    public var visibility: ThreadEventVisibilityCategory { payload.visibility }
    public var renderKind: ThreadEventKind { payload.renderKind }
    public var title: String { payload.title }
    public var body: String { payload.body }
    public var eventTime: String? { payload.eventTime }
    public var activityTime: String? { payload.activityTime }
    public var turnID: String? { payload.turnID }
    public var itemID: String? { payload.itemID }
    public var turnOrder: Int? { payload.turnOrder }
    public var itemOrder: Int? { payload.itemOrder }
    public var rowOrder: Int? { payload.rowOrder }
    public var renderState: ThreadDetailRenderState { payload.renderState }
    public var requestID: String? { payload.requestID }
    public var request: ThreadDetailEventRequestDTO? { payload.request }
    public var diagnostic: JSONValue? { payload.diagnostic }

    public init(
        schemaVersion: Int = 1,
        identityVersion: Int = 1,
        projectionEngineVersion: Int = 1,
        sourceHostID: String,
        view: String = "thread.detail",
        threadID: String,
        projectionID: String,
        sourceRef: String,
        itemType: String? = nil,
        rowRole: String,
        visibility: ThreadEventVisibilityCategory,
        renderKind: ThreadEventKind,
        displayOrderKey: String,
        title: String,
        body: String,
        eventTime: String? = nil,
        activityTime: String? = nil,
        turnID: String? = nil,
        itemID: String? = nil,
        turnOrder: Int? = nil,
        itemOrder: Int? = nil,
        rowOrder: Int? = nil,
        revision: Int = 1,
        freshness: ThreadDetailFreshnessDTO? = nil,
        renderState: ThreadDetailRenderState = .settled,
        requestID: String? = nil,
        request: ThreadDetailEventRequestDTO? = nil,
        diagnostic: JSONValue? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.identityVersion = identityVersion
        self.projectionEngineVersion = projectionEngineVersion
        self.sourceHostID = sourceHostID
        self.view = view
        self.threadID = threadID
        self.projectionID = projectionID
        self.sourceRef = sourceRef
        self.rowRole = rowRole
        self.displayOrderKey = displayOrderKey
        self.revision = revision
        self.freshness = freshness
        self.payload = ThreadDetailEventPayloadDTO(
            itemType: itemType,
            visibility: visibility,
            renderKind: renderKind,
            title: title,
            body: body,
            eventTime: eventTime,
            activityTime: activityTime,
            turnID: turnID,
            itemID: itemID,
            turnOrder: turnOrder,
            itemOrder: itemOrder,
            rowOrder: rowOrder,
            renderState: renderState,
            requestID: requestID,
            request: request,
            diagnostic: diagnostic
        )
    }
}

public struct ThreadDetailSnapshotDTO: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let identityVersion: Int
    public let projectionEngineVersion: Int
    public let sourceHostID: String
    public let view: String
    public let threadID: String
    public let epoch: String
    public let seq: Int64
    public let generation: Int
    public let snapshotID: String?
    public let scope: String?
    public let viewParamsKey: String?
    public let complete: Bool?
    public let activeTurnID: String?
    public let order: String?
    public let freshness: ThreadDetailFreshnessDTO?
    public let rows: [ThreadDetailEventDTO]

    public var events: [ThreadDetailEventDTO] {
        rows
    }

    public init(
        schemaVersion: Int = 1,
        identityVersion: Int = 1,
        projectionEngineVersion: Int = 1,
        sourceHostID: String,
        view: String = "thread.detail",
        threadID: String,
        epoch: String = "test",
        seq: Int64 = 0,
        generation: Int = 1,
        snapshotID: String? = nil,
        scope: String? = "thread",
        viewParamsKey: String? = nil,
        complete: Bool? = true,
        activeTurnID: String? = nil,
        order: String? = nil,
        freshness: ThreadDetailFreshnessDTO? = nil,
        rows: [ThreadDetailEventDTO]
    ) {
        self.schemaVersion = schemaVersion
        self.identityVersion = identityVersion
        self.projectionEngineVersion = projectionEngineVersion
        self.sourceHostID = sourceHostID
        self.view = view
        self.threadID = threadID
        self.epoch = epoch
        self.seq = seq
        self.generation = generation
        self.snapshotID = snapshotID
        self.scope = scope
        self.viewParamsKey = viewParamsKey
        self.complete = complete
        self.activeTurnID = activeTurnID
        self.order = order
        self.freshness = freshness
        self.rows = rows
    }
}

public struct ThreadDetailUpdateDTO: Codable, Equatable, Sendable {
    public let kind: ThreadDetailUpdateKind
    public let schemaVersion: Int
    public let identityVersion: Int
    public let projectionEngineVersion: Int
    public let sourceHostID: String
    public let view: String
    public let threadID: String
    public let scope: String
    public let epoch: String
    public let seq: Int64
    public let generation: Int
    public let viewParamsKey: String?
    public let order: String?
    public let freshness: ThreadDetailFreshnessDTO?
    public let rows: [ThreadDetailEventDTO]
    public let projectionIDs: [String]
    public let activeTurnID: String?
    public let reason: String?
    public let liveState: String?

    public init(
        kind: ThreadDetailUpdateKind,
        schemaVersion: Int = 1,
        identityVersion: Int = 1,
        projectionEngineVersion: Int = 1,
        sourceHostID: String,
        view: String = "thread.detail",
        threadID: String,
        scope: String = "thread",
        epoch: String = "test",
        seq: Int64 = 0,
        generation: Int = 1,
        viewParamsKey: String? = nil,
        order: String? = nil,
        freshness: ThreadDetailFreshnessDTO? = nil,
        rows: [ThreadDetailEventDTO] = [],
        projectionIDs: [String] = [],
        activeTurnID: String? = nil,
        reason: String? = nil,
        liveState: String? = nil
    ) {
        self.kind = kind
        self.schemaVersion = schemaVersion
        self.identityVersion = identityVersion
        self.projectionEngineVersion = projectionEngineVersion
        self.sourceHostID = sourceHostID
        self.view = view
        self.threadID = threadID
        self.scope = scope
        self.epoch = epoch
        self.seq = seq
        self.generation = generation
        self.viewParamsKey = viewParamsKey
        self.order = order
        self.freshness = freshness
        self.rows = rows
        self.projectionIDs = projectionIDs
        self.activeTurnID = activeTurnID
        self.reason = reason
        self.liveState = liveState
    }
}

public struct ThreadArchiveParams: Codable, Equatable, Sendable {
    public let threadId: String

    public init(threadId: String) {
        self.threadId = threadId
    }
}

public struct ThreadArchiveResponseDTO: Codable, Equatable, Sendable {
    public init() {}
}

public struct ThreadUnarchiveParams: Codable, Equatable, Sendable {
    public let threadId: String

    public init(threadId: String) {
        self.threadId = threadId
    }
}

public struct ThreadUnarchiveResponseDTO: Codable, Equatable, Sendable {
    public let thread: ThreadDTO

    public init(thread: ThreadDTO) {
        self.thread = thread
    }
}

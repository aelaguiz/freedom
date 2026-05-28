import Foundation

public enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case integer(Int64)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .integer(let value):
            try container.encode(value)
        case .double(let value):
            guard value.isFinite else {
                throw EncodingError.invalidValue(
                    value,
                    EncodingError.Context(
                        codingPath: encoder.codingPath,
                        debugDescription: "JSON numbers must be finite"
                    )
                )
            }
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }

    public static func encoded<T: Encodable>(
        _ value: T,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> JSONValue {
        let data = try encoder.encode(value)
        return try decoder.decode(JSONValue.self, from: data)
    }

    public func decoded<T: Decodable>(
        as type: T.Type,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> T {
        let data = try encoder.encode(self)
        return try decoder.decode(type, from: data)
    }
}

public enum JSONRPCRequestID: Codable, Hashable, Sendable, CustomStringConvertible {
    case string(String)
    case integer(Int64)

    public var description: String {
        switch self {
        case .string(let value):
            value
        case .integer(let value):
            String(value)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "JSON-RPC request id must be an integer or string"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .integer(let value):
            try container.encode(value)
        }
    }
}

public struct JSONRPCRequest: Codable, Equatable, Sendable {
    public let id: JSONRPCRequestID
    public let method: String
    public let params: JSONValue?

    public init(id: JSONRPCRequestID, method: String, params: JSONValue? = nil) {
        self.id = id
        self.method = method
        self.params = params
    }
}

public struct JSONRPCNotification: Codable, Equatable, Sendable {
    public let method: String
    public let params: JSONValue?

    public init(method: String, params: JSONValue? = nil) {
        self.method = method
        self.params = params
    }
}

public struct JSONRPCResponse: Codable, Equatable, Sendable {
    public let id: JSONRPCRequestID
    public let result: JSONValue

    public init(id: JSONRPCRequestID, result: JSONValue) {
        self.id = id
        self.result = result
    }
}

public struct JSONRPCErrorObject: Codable, Equatable, Sendable {
    public let code: Int64
    public let data: JSONValue?
    public let message: String

    public init(code: Int64, message: String, data: JSONValue? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }
}

public struct JSONRPCErrorResponse: Codable, Equatable, Sendable {
    public let error: JSONRPCErrorObject
    public let id: JSONRPCRequestID

    public init(error: JSONRPCErrorObject, id: JSONRPCRequestID) {
        self.error = error
        self.id = id
    }
}

public enum JSONRPCMessage: Codable, Equatable, Sendable {
    case request(JSONRPCRequest)
    case notification(JSONRPCNotification)
    case response(JSONRPCResponse)
    case error(JSONRPCErrorResponse)

    private enum CodingKeys: String, CodingKey {
        case id
        case method
        case result
        case error
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if container.contains(.error) {
            self = .error(try JSONRPCErrorResponse(from: decoder))
        } else if container.contains(.result) {
            self = .response(try JSONRPCResponse(from: decoder))
        } else if container.contains(.method), container.contains(.id) {
            self = .request(try JSONRPCRequest(from: decoder))
        } else if container.contains(.method) {
            self = .notification(try JSONRPCNotification(from: decoder))
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .method,
                in: container,
                debugDescription: "JSON-RPC message must be a request, notification, response, or error"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .request(let value):
            try value.encode(to: encoder)
        case .notification(let value):
            try value.encode(to: encoder)
        case .response(let value):
            try value.encode(to: encoder)
        case .error(let value):
            try value.encode(to: encoder)
        }
    }

    public static func decode(
        from text: String,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> JSONRPCMessage {
        guard let data = text.data(using: .utf8) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "JSON-RPC text is not valid UTF-8"
                )
            )
        }
        return try decoder.decode(JSONRPCMessage.self, from: data)
    }

    public func jsonData(encoder: JSONEncoder = JSONEncoder()) throws -> Data {
        try encoder.encode(self)
    }

    public func jsonString(encoder: JSONEncoder = JSONEncoder()) throws -> String {
        let data = try jsonData(encoder: encoder)
        guard let text = String(data: data, encoding: .utf8) else {
            throw EncodingError.invalidValue(
                self,
                EncodingError.Context(
                    codingPath: [],
                    debugDescription: "Encoded JSON-RPC data is not valid UTF-8"
                )
            )
        }
        return text
    }
}

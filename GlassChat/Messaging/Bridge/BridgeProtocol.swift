import Foundation

enum BridgeMethod: String, Sendable {
    case sessionStatus = "session.status"
    case sessionPairStart = "session.pair.start"
    case sessionConnect = "session.connect"
    case sessionLogout = "session.logout"
    case messagesSendText = "messages.send.text"
    case chatsList = "chats.list"
    case messagesList = "messages.list"
}

enum BridgeEvent: String, Sendable {
    case pairQR = "session.pair.qr"
    case pairSuccess = "session.pair.success"
    case pairTimeout = "session.pair.timeout"
    case pairError = "session.pair.error"
    case sessionStatus = "session.status"
    case messageEvent = "messages.event"
    case chatsUpdated = "chats.updated"
}

struct BridgeEnvelope: Codable, Sendable {
    var id: String
    var type: String
    var method: String
    var ok: Bool?
    var error: String?
    var payload: [String: BridgeJSON]?
}

enum BridgeJSON: Codable, Sendable, Hashable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: BridgeJSON])
    case array([BridgeJSON])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: BridgeJSON].self) {
            self = .object(value)
        } else if let value = try? container.decode([BridgeJSON].self) {
            self = .array(value)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var intValue: Int? {
        switch self {
        case .int(let value): return value
        case .double(let value): return Int(value)
        default: return nil
        }
    }

    var arrayValue: [BridgeJSON]? {
        if case .array(let value) = self { return value }
        return nil
    }

    var objectValue: [String: BridgeJSON]? {
        if case .object(let value) = self { return value }
        return nil
    }
}

extension BridgeEnvelope {
    func payloadString(_ key: String) -> String? {
        payload?[key]?.stringValue
    }
}

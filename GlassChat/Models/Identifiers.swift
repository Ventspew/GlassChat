import Foundation

struct ChatID: Hashable, Codable, Sendable, Identifiable {
    let rawValue: String
    var id: String { rawValue }

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

struct MessageID: Hashable, Codable, Sendable, Identifiable {
    let rawValue: String
    var id: String { rawValue }

    init(_ rawValue: String = UUID().uuidString) {
        self.rawValue = rawValue
    }
}

struct ContactID: Hashable, Codable, Sendable, Identifiable {
    let rawValue: String
    var id: String { rawValue }

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

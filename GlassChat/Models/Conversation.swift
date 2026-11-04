import Foundation

enum ConversationKind: String, Codable, Sendable {
    case individual
    case group
}

struct Conversation: Identifiable, Hashable, Codable, Sendable {
    let id: ChatID
    var title: String
    var kind: ConversationKind
    var participants: [Contact]
    var lastMessagePreview: String
    var lastActivity: Date
    var unreadCount: Int
    var isPinned: Bool
    var avatarSymbol: String
    var avatarHue: Double

    var isGroup: Bool { kind == .group }
}

struct Contact: Identifiable, Hashable, Codable, Sendable {
    let id: ContactID
    var displayName: String
    var phoneNumber: String?
}

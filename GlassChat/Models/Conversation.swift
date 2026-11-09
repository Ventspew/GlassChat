import Foundation

enum ConversationKind: String, Codable, Sendable {
    case individual
    case group
}

enum MessengerProtocol: String, Codable, Sendable, CaseIterable, Identifiable {
    case whatsapp
    case telegram
    case discord
    case all

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .whatsapp: return "WhatsApp"
        case .telegram: return "Telegram"
        case .discord: return "Discord"
        case .all: return "All"
        }
    }

    var symbolName: String {
        switch self {
        case .whatsapp: return "phone.fill"
        case .telegram: return "paperplane.fill"
        case .discord: return "gamecontroller.fill"
        case .all: return "bubble.left.and.bubble.right.fill"
        }
    }
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
    var messenger: MessengerProtocol

    var isGroup: Bool { kind == .group }

    init(
        id: ChatID,
        title: String,
        kind: ConversationKind,
        participants: [Contact],
        lastMessagePreview: String,
        lastActivity: Date,
        unreadCount: Int,
        isPinned: Bool,
        avatarSymbol: String,
        avatarHue: Double,
        messenger: MessengerProtocol = .whatsapp
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.participants = participants
        self.lastMessagePreview = lastMessagePreview
        self.lastActivity = lastActivity
        self.unreadCount = unreadCount
        self.isPinned = isPinned
        self.avatarSymbol = avatarSymbol
        self.avatarHue = avatarHue
        self.messenger = messenger
    }
}

struct Contact: Identifiable, Hashable, Codable, Sendable {
    let id: ContactID
    var displayName: String
    var phoneNumber: String?
}

import Foundation

enum MessageDirection: String, Codable, Sendable {
    case incoming
    case outgoing
}

enum MessageStatus: String, Codable, Sendable {
    case pending
    case sent
    case delivered
    case read
    case failed
}

enum MessageBody: Hashable, Codable, Sendable {
    case text(String)
    case image(caption: String?)
    case document(fileName: String)
    case voice(duration: TimeInterval)
    case unsupported(description: String)

    var plainText: String? {
        switch self {
        case .text(let value):
            return value
        case .image(let caption):
            return caption
        case .document(let fileName):
            return fileName
        case .voice(let duration):
            return String(format: "Voice · %.0fs", duration)
        case .unsupported(let description):
            return description
        }
    }
}

struct Message: Identifiable, Hashable, Codable, Sendable {
    let id: MessageID
    let chatID: ChatID
    var senderName: String
    var direction: MessageDirection
    var body: MessageBody
    var timestamp: Date
    var status: MessageStatus
    var replyToID: MessageID?
    var reaction: String?
}

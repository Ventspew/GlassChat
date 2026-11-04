import Foundation

protocol MessagingService: AnyObject, Sendable {
    var connectionState: ConnectionState { get async }
    func observeConnectionState() -> AsyncStream<ConnectionState>
    func observeConversations() -> AsyncStream<[Conversation]>
    func observeMessages(in chatID: ChatID) -> AsyncStream<[Message]>
    func send(text: String, to chatID: ChatID, replyTo: MessageID?) async throws
    func setPinned(_ pinned: Bool, chatID: ChatID) async throws
    func markRead(chatID: ChatID) async throws
    func clearLocalData() async throws
}

enum MessagingBackendKind: String, CaseIterable, Identifiable, Sendable {
    case mock
    case whatsmeowBridge

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mock:
            return "Mock (local sample data)"
        case .whatsmeowBridge:
            return "WhatsApp (QR linked device)"
        }
    }
}

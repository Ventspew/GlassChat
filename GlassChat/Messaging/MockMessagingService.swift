import Foundation

actor MockMessagingService: MessagingService {
    private var conversations: [Conversation]
    private var messagesByChat: [ChatID: [Message]]
    private var connection: ConnectionState = .connected(accountLabel: "Demo Account")

    private var conversationContinuations: [UUID: AsyncStream<[Conversation]>.Continuation] = [:]
    private var messageContinuations: [ChatID: [UUID: AsyncStream<[Message]>.Continuation]] = [:]
    private var connectionContinuations: [UUID: AsyncStream<ConnectionState>.Continuation] = [:]

    init(seed: MockDataStore = .sample) {
        self.conversations = seed.conversations
        self.messagesByChat = seed.messagesByChat
    }

    var connectionState: ConnectionState {
        connection
    }

    func observeConnectionState() -> AsyncStream<ConnectionState> {
        AsyncStream { continuation in
            let id = UUID()
            connectionContinuations[id] = continuation
            continuation.yield(connection)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeConnectionContinuation(id) }
            }
        }
    }

    func observeConversations() -> AsyncStream<[Conversation]> {
        AsyncStream { continuation in
            let id = UUID()
            conversationContinuations[id] = continuation
            continuation.yield(sortedConversations())
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeConversationContinuation(id) }
            }
        }
    }

    func observeMessages(in chatID: ChatID) -> AsyncStream<[Message]> {
        AsyncStream { continuation in
            let id = UUID()
            var bucket = messageContinuations[chatID] ?? [:]
            bucket[id] = continuation
            messageContinuations[chatID] = bucket
            continuation.yield(messagesByChat[chatID] ?? [])
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeMessageContinuation(chatID: chatID, id: id) }
            }
        }
    }

    func send(text: String, to chatID: ChatID, replyTo: MessageID?) async throws {
        guard case .connected = connection else {
            throw MessagingError.notConnected
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let message = Message(
            id: MessageID(),
            chatID: chatID,
            senderName: "You",
            direction: .outgoing,
            body: .text(trimmed),
            timestamp: .now,
            status: .sent,
            replyToID: replyTo,
            reaction: nil
        )

        var list = messagesByChat[chatID] ?? []
        list.append(message)
        messagesByChat[chatID] = list
        publishMessages(chatID)

        if let index = conversations.firstIndex(where: { $0.id == chatID }) {
            conversations[index].lastMessagePreview = trimmed
            conversations[index].lastActivity = message.timestamp
            conversations[index].unreadCount = 0
            publishConversations()
        }

        // Simulate a short reply for demo feel in the first personal chat.
        if chatID.rawValue == "chat-emma", Bool.random() {
            try? await Task.sleep(for: .milliseconds(800))
            await appendIncomingDemoReply(in: chatID)
        }
    }

    func setPinned(_ pinned: Bool, chatID: ChatID) async throws {
        guard let index = conversations.firstIndex(where: { $0.id == chatID }) else { return }
        conversations[index].isPinned = pinned
        publishConversations()
    }

    func markRead(chatID: ChatID) async throws {
        guard let index = conversations.firstIndex(where: { $0.id == chatID }) else { return }
        conversations[index].unreadCount = 0
        publishConversations()
    }

    func clearLocalData() async throws {
        conversations = []
        messagesByChat = [:]
        publishConversations()
        for chatID in messageContinuations.keys {
            publishMessages(chatID)
        }
    }

    func resetToSampleData() {
        let seed = MockDataStore.sample
        conversations = seed.conversations
        messagesByChat = seed.messagesByChat
        connection = .connected(accountLabel: "Demo Account")
        publishConversations()
        publishConnection()
        for chatID in messagesByChat.keys {
            publishMessages(chatID)
        }
    }

    private func appendIncomingDemoReply(in chatID: ChatID) {
        let replies = [
            "Klinkt goed!",
            "Thanks — see you soon.",
            "Perfect, tot zo!",
            "Got it 👍"
        ]
        let reply = Message(
            id: MessageID(),
            chatID: chatID,
            senderName: "Emma",
            direction: .incoming,
            body: .text(replies.randomElement() ?? "Ok"),
            timestamp: .now,
            status: .delivered,
            replyToID: nil,
            reaction: nil
        )
        var list = messagesByChat[chatID] ?? []
        list.append(reply)
        messagesByChat[chatID] = list
        publishMessages(chatID)

        if let index = conversations.firstIndex(where: { $0.id == chatID }) {
            conversations[index].lastMessagePreview = reply.body.plainText ?? ""
            conversations[index].lastActivity = reply.timestamp
            conversations[index].unreadCount += 1
            publishConversations()
        }
    }

    private func sortedConversations() -> [Conversation] {
        conversations.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned && !rhs.isPinned
            }
            return lhs.lastActivity > rhs.lastActivity
        }
    }

    private func publishConversations() {
        let snapshot = sortedConversations()
        for continuation in conversationContinuations.values {
            continuation.yield(snapshot)
        }
    }

    private func publishMessages(_ chatID: ChatID) {
        let snapshot = messagesByChat[chatID] ?? []
        guard let values = messageContinuations[chatID]?.values else { return }
        for continuation in values {
            continuation.yield(snapshot)
        }
    }

    private func publishConnection() {
        for continuation in connectionContinuations.values {
            continuation.yield(connection)
        }
    }

    private func removeConversationContinuation(_ id: UUID) {
        conversationContinuations.removeValue(forKey: id)
    }

    private func removeMessageContinuation(chatID: ChatID, id: UUID) {
        messageContinuations[chatID]?.removeValue(forKey: id)
    }

    private func removeConnectionContinuation(_ id: UUID) {
        connectionContinuations.removeValue(forKey: id)
    }
}

struct MockDataStore: Sendable {
    var conversations: [Conversation]
    var messagesByChat: [ChatID: [Message]]

    static let sample: MockDataStore = {
        let emma = Contact(id: ContactID("c-emma"), displayName: "Emma de Vries", phoneNumber: "+31612345678")
        let lucas = Contact(id: ContactID("c-lucas"), displayName: "Lucas", phoneNumber: "+31687654321")
        let team = Contact(id: ContactID("c-team"), displayName: "Design Team", phoneNumber: nil)

        let chatEmma = ChatID("chat-emma")
        let chatLucas = ChatID("chat-lucas")
        let chatTeam = ChatID("chat-team")

        let conversations: [Conversation] = [
            Conversation(
                id: chatEmma,
                title: "Emma de Vries",
                kind: .individual,
                participants: [emma],
                lastMessagePreview: "Tot zo bij het café!",
                lastActivity: Date().addingTimeInterval(-120),
                unreadCount: 2,
                isPinned: true,
                avatarSymbol: "person.fill",
                avatarHue: 0.58
            ),
            Conversation(
                id: chatLucas,
                title: "Lucas",
                kind: .individual,
                participants: [lucas],
                lastMessagePreview: "Can you send the PDF?",
                lastActivity: Date().addingTimeInterval(-3600),
                unreadCount: 0,
                isPinned: false,
                avatarSymbol: "person.fill",
                avatarHue: 0.12
            ),
            Conversation(
                id: chatTeam,
                title: "Design Team",
                kind: .group,
                participants: [emma, lucas, team],
                lastMessagePreview: "New mockups look great ✨",
                lastActivity: Date().addingTimeInterval(-7200),
                unreadCount: 5,
                isPinned: true,
                avatarSymbol: "person.3.fill",
                avatarHue: 0.78
            )
        ]

        let messages: [ChatID: [Message]] = [
            chatEmma: [
                Message(id: MessageID("m1"), chatID: chatEmma, senderName: "Emma", direction: .incoming, body: .text("Hé! Ben je er om 10:00?"), timestamp: Date().addingTimeInterval(-900), status: .read, replyToID: nil, reaction: nil),
                Message(id: MessageID("m2"), chatID: chatEmma, senderName: "You", direction: .outgoing, body: .text("Ja, ik fiets zo die kant op."), timestamp: Date().addingTimeInterval(-700), status: .read, replyToID: nil, reaction: "👍"),
                Message(id: MessageID("m3"), chatID: chatEmma, senderName: "Emma", direction: .incoming, body: .text("Perfect. Ik neem koffie mee ☕"), timestamp: Date().addingTimeInterval(-400), status: .delivered, replyToID: nil, reaction: nil),
                Message(id: MessageID("m4"), chatID: chatEmma, senderName: "Emma", direction: .incoming, body: .text("Tot zo bij het café!"), timestamp: Date().addingTimeInterval(-120), status: .delivered, replyToID: nil, reaction: nil)
            ],
            chatLucas: [
                Message(id: MessageID("m5"), chatID: chatLucas, senderName: "Lucas", direction: .incoming, body: .text("Hey, do you still have yesterday's notes?"), timestamp: Date().addingTimeInterval(-5000), status: .read, replyToID: nil, reaction: nil),
                Message(id: MessageID("m6"), chatID: chatLucas, senderName: "You", direction: .outgoing, body: .text("Yes — I'll share them after lunch."), timestamp: Date().addingTimeInterval(-4200), status: .read, replyToID: nil, reaction: nil),
                Message(id: MessageID("m7"), chatID: chatLucas, senderName: "Lucas", direction: .incoming, body: .text("Can you send the PDF?"), timestamp: Date().addingTimeInterval(-3600), status: .delivered, replyToID: nil, reaction: nil)
            ],
            chatTeam: [
                Message(id: MessageID("m8"), chatID: chatTeam, senderName: "Lucas", direction: .incoming, body: .text("Dropping v2 of the sidebar tonight."), timestamp: Date().addingTimeInterval(-9000), status: .read, replyToID: nil, reaction: nil),
                Message(id: MessageID("m9"), chatID: chatTeam, senderName: "Emma", direction: .incoming, body: .text("New mockups look great ✨"), timestamp: Date().addingTimeInterval(-7200), status: .delivered, replyToID: nil, reaction: nil),
                Message(id: MessageID("m10"), chatID: chatTeam, senderName: "You", direction: .outgoing, body: .text("I'll polish the composer translation UI next."), timestamp: Date().addingTimeInterval(-7000), status: .read, replyToID: nil, reaction: nil)
            ]
        ]

        return MockDataStore(conversations: conversations, messagesByChat: messages)
    }()
}

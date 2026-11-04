import Foundation

/// Live messaging backend that talks to the local whatsmeow Go bridge.
actor WhatsmeowMessagingService: MessagingService {
    private let processManager: BridgeProcessManager
    private var client: BridgeClient?

    private var connection: ConnectionState = .disconnected
    private var conversations: [Conversation] = []
    private var messagesByChat: [ChatID: [Message]] = [:]

    private var connectionContinuations: [UUID: AsyncStream<ConnectionState>.Continuation] = [:]
    private var conversationContinuations: [UUID: AsyncStream<[Conversation]>.Continuation] = [:]
    private var messageContinuations: [ChatID: [UUID: AsyncStream<[Message]>.Continuation]] = [:]

    private var eventHandlerID: UUID?
    private(set) var latestQRCode: String?

    init(processManager: BridgeProcessManager) {
        self.processManager = processManager
    }

    init() {
        self.processManager = BridgeProcessManager()
    }

    var connectionState: ConnectionState { connection }

    var currentQRCode: String? { latestQRCode }

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
            continuation.yield(conversations)
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

    func observeQRCodes() -> AsyncStream<String?> {
        AsyncStream { continuation in
            continuation.yield(latestQRCode)
            // Poll lightly via connection events; UI also reads latestQRCode after pair start.
            continuation.finish()
        }
    }

    func startBridgeAndConnect() async throws {
        setConnection(.connecting)
        try processManager.ensureRunning()
        try await processManager.waitForSocket()
        let socketPath = processManager.socketURL.path
        let bridge = BridgeClient(socketPath: socketPath)
        try await bridge.start()
        client = bridge

        if let eventHandlerID {
            await bridge.removeEventHandler(eventHandlerID)
        }
        eventHandlerID = await bridge.onEvent { [weak self] envelope in
            Task { await self?.handleEvent(envelope) }
        }

        do {
            _ = try await bridge.request(method: .sessionConnect)
        } catch {
            // Not paired yet is expected until the user scans a QR code.
            setConnection(.disconnected)
        }
    }

    func startPairing() async throws {
        setConnection(.awaitingPairing)
        latestQRCode = nil
        try await ensureClient()
        guard let client else {
            throw MessagingError.bridgeUnavailable("Bridge client missing")
        }
        _ = try await client.request(method: .sessionPairStart)
    }

    func logout() async throws {
        guard let client else { return }
        _ = try await client.request(method: .sessionLogout)
        latestQRCode = nil
        conversations = []
        messagesByChat = [:]
        setConnection(.disconnected)
        publishConversations()
    }

    func send(text: String, to chatID: ChatID, replyTo: MessageID?) async throws {
        guard let client else {
            throw MessagingError.notConnected
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var payload: [String: BridgeJSON] = [
            "chatId": .string(chatID.rawValue),
            "text": .string(trimmed)
        ]
        if let replyTo {
            payload["replyToId"] = .string(replyTo.rawValue)
        }

        let response = try await client.request(method: .messagesSendText, payload: payload)
        let messageID = response.payloadString("id") ?? UUID().uuidString
        let message = Message(
            id: MessageID(messageID),
            chatID: chatID,
            senderName: "You",
            direction: .outgoing,
            body: .text(trimmed),
            timestamp: .now,
            status: .sent,
            replyToID: replyTo,
            reaction: nil
        )
        appendMessage(message)
    }

    func setPinned(_ pinned: Bool, chatID: ChatID) async throws {
        throw MessagingError.featureUnsupported("Pin sync via bridge")
    }

    func markRead(chatID: ChatID) async throws {
        // Local-only for now.
        if let index = conversations.firstIndex(where: { $0.id == chatID }) {
            conversations[index].unreadCount = 0
            publishConversations()
        }
    }

    func clearLocalData() async throws {
        try await logout()
    }

    // MARK: - Events

    private func handleEvent(_ envelope: BridgeEnvelope) {
        switch BridgeEvent(rawValue: envelope.method) {
        case .pairQR:
            latestQRCode = envelope.payloadString("code")
            setConnection(.awaitingPairing)
        case .pairSuccess:
            latestQRCode = nil
            let label = envelope.payloadString("accountLabel") ?? "WhatsApp"
            setConnection(.connected(accountLabel: label))
        case .pairTimeout:
            latestQRCode = nil
            setConnection(.error("QR code expired — start pairing again"))
        case .pairError:
            latestQRCode = nil
            setConnection(.error(envelope.payloadString("detail") ?? envelope.error ?? "Pairing failed"))
        case .sessionStatus:
            applyStatusPayload(envelope)
        case .messageEvent:
            ingestIncoming(envelope)
        case .none:
            break
        }
    }

    private func applyStatusPayload(_ envelope: BridgeEnvelope) {
        let state = envelope.payloadString("state") ?? ""
        let label = envelope.payloadString("accountLabel") ?? "WhatsApp"
        switch state {
        case "connected":
            setConnection(.connected(accountLabel: label))
        case "awaiting_pairing":
            setConnection(.awaitingPairing)
        case "connecting":
            setConnection(.connecting)
        case "error":
            setConnection(.error(envelope.payloadString("detail") ?? "Bridge error"))
        default:
            setConnection(.disconnected)
        }
    }

    private func ingestIncoming(_ envelope: BridgeEnvelope) {
        guard let chat = envelope.payloadString("chatId"),
              let text = envelope.payloadString("text"),
              let id = envelope.payloadString("id") else { return }
        let fromMe = {
            if case .bool(let value) = envelope.payload?["fromMe"] { return value }
            return false
        }()
        let sender = envelope.payloadString("senderName") ?? "Contact"
        let chatID = ChatID(chat)
        ensureConversation(chatID: chatID, title: sender)

        let message = Message(
            id: MessageID(id),
            chatID: chatID,
            senderName: fromMe ? "You" : sender,
            direction: fromMe ? .outgoing : .incoming,
            body: .text(text),
            timestamp: .now,
            status: .delivered,
            replyToID: nil,
            reaction: nil
        )
        appendMessage(message)
    }

    private func ensureConversation(chatID: ChatID, title: String) {
        if conversations.contains(where: { $0.id == chatID }) { return }
        conversations.insert(
            Conversation(
                id: chatID,
                title: title,
                kind: .individual,
                participants: [Contact(id: ContactID(chatID.rawValue), displayName: title, phoneNumber: nil)],
                lastMessagePreview: "",
                lastActivity: .now,
                unreadCount: 0,
                isPinned: false,
                avatarSymbol: "person.fill",
                avatarHue: Double.random(in: 0...1)
            ),
            at: 0
        )
        publishConversations()
    }

    private func appendMessage(_ message: Message) {
        var list = messagesByChat[message.chatID] ?? []
        list.append(message)
        messagesByChat[message.chatID] = list
        publishMessages(message.chatID)

        if let index = conversations.firstIndex(where: { $0.id == message.chatID }) {
            conversations[index].lastMessagePreview = message.body.plainText ?? ""
            conversations[index].lastActivity = message.timestamp
            if message.direction == .incoming {
                conversations[index].unreadCount += 1
            }
            publishConversations()
        }
    }

    private func ensureClient() async throws {
        if client == nil {
            try await startBridgeAndConnect()
        }
        // Ignore connect failure when unpaired — pairing creates the session.
        if client == nil {
            try processManager.ensureRunning()
            try await processManager.waitForSocket()
            let socketPath = processManager.socketURL.path
            let bridge = BridgeClient(socketPath: socketPath)
            try await bridge.start()
            client = bridge
            eventHandlerID = await bridge.onEvent { [weak self] envelope in
                Task { await self?.handleEvent(envelope) }
            }
        }
    }

    private func setConnection(_ state: ConnectionState) {
        connection = state
        for continuation in connectionContinuations.values {
            continuation.yield(state)
        }
    }

    private func publishConversations() {
        for continuation in conversationContinuations.values {
            continuation.yield(conversations)
        }
    }

    private func publishMessages(_ chatID: ChatID) {
        let snapshot = messagesByChat[chatID] ?? []
        guard let values = messageContinuations[chatID]?.values else { return }
        for continuation in values {
            continuation.yield(snapshot)
        }
    }

    private func removeConnectionContinuation(_ id: UUID) {
        connectionContinuations.removeValue(forKey: id)
    }

    private func removeConversationContinuation(_ id: UUID) {
        conversationContinuations.removeValue(forKey: id)
    }

    private func removeMessageContinuation(chatID: ChatID, id: UUID) {
        messageContinuations[chatID]?.removeValue(forKey: id)
    }
}

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

    func startPairing(
        protocolKind: MessengerProtocol = .whatsapp,
        telegramAPIID: String? = nil,
        telegramAPIHash: String? = nil,
        discordToken: String? = nil,
        discordBot: Bool = true
    ) async throws {
        setConnection(.awaitingPairing)
        latestQRCode = nil
        try await ensureClient()
        guard let client else {
            throw MessagingError.bridgeUnavailable("Bridge client missing")
        }
        var payload: [String: BridgeJSON] = [
            "protocol": .string(protocolKind == .all ? "whatsapp" : protocolKind.rawValue)
        ]
        if let telegramAPIID { payload["apiId"] = .string(telegramAPIID) }
        if let telegramAPIHash { payload["apiHash"] = .string(telegramAPIHash) }
        if let discordToken { payload["token"] = .string(discordToken) }
        payload["bot"] = .bool(discordBot)
        _ = try await client.request(method: .sessionPairStart, payload: payload)
    }

    func logout(protocolKind: MessengerProtocol = .whatsapp) async throws {
        guard let client else { return }
        _ = try await client.request(
            method: .sessionLogout,
            payload: ["protocol": .string(protocolKind == .all ? "whatsapp" : protocolKind.rawValue)]
        )
        latestQRCode = nil
        if protocolKind == .all || protocolKind == .whatsapp {
            conversations.removeAll { $0.messenger == .whatsapp || protocolKind == .all }
            if protocolKind == .all {
                conversations = []
                messagesByChat = [:]
            }
        } else {
            conversations.removeAll { $0.messenger == protocolKind }
        }
        setConnection(.disconnected)
        publishConversations()
    }

    func refreshChats(protocolKind: MessengerProtocol = .all) async {
        guard let client else { return }
        do {
            let response = try await client.request(
                method: .chatsList,
                payload: ["protocol": .string(protocolKind.rawValue)]
            )
            applyChatsPayload(response.payload?["chats"])
        } catch {
            // Keep existing local cache.
        }
    }

    func loadMessages(for chatID: ChatID) async {
        guard let client else { return }
        do {
            let response = try await client.request(
                method: .messagesList,
                payload: ["chatId": .string(chatID.rawValue)]
            )
            guard let rows = response.payload?["messages"]?.arrayValue else { return }
            var list: [Message] = []
            for row in rows {
                guard let obj = row.objectValue else { continue }
                let id = obj["id"]?.stringValue ?? UUID().uuidString
                let text = obj["text"]?.stringValue ?? ""
                let fromMe = {
                    if case .bool(let value) = obj["fromMe"] { return value }
                    return false
                }()
                let ts = obj["timestamp"]?.intValue.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? .now
                list.append(
                    Message(
                        id: MessageID(id),
                        chatID: chatID,
                        senderName: obj["senderName"]?.stringValue ?? (fromMe ? "You" : "Contact"),
                        direction: fromMe ? .outgoing : .incoming,
                        body: .text(text),
                        timestamp: ts,
                        status: .delivered,
                        replyToID: nil,
                        reaction: nil
                    )
                )
            }
            messagesByChat[chatID] = list.sorted { $0.timestamp < $1.timestamp }
            publishMessages(chatID)
        } catch {
            // Ignore — live events still work.
        }
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
        if let index = conversations.firstIndex(where: { $0.id == chatID }) {
            conversations[index].unreadCount = 0
            publishConversations()
        }
        guard let client else { return }
        // Only WhatsApp JIDs go through whatsmeow mark-read.
        let raw = chatID.rawValue
        if raw.hasPrefix("tg:") || raw.hasPrefix("dc:") { return }
        _ = try? await client.request(
            method: .messagesMarkRead,
            payload: ["chatId": .string(raw)]
        )
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
            let label = envelope.payloadString("accountLabel") ?? "Connected"
            setConnection(.connected(accountLabel: label))
            Task { await refreshChats(protocolKind: .all) }
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
        case .chatsUpdated:
            applyChatsPayload(envelope.payload?["chats"])
        case .none:
            break
        }
    }

    private func applyChatsPayload(_ value: BridgeJSON?) {
        guard let rows = value?.arrayValue else { return }
        var mapped: [Conversation] = []
        for row in rows {
            guard let obj = row.objectValue,
                  let id = obj["id"]?.stringValue else { continue }
            let title = obj["title"]?.stringValue ?? id
            let kindRaw = obj["kind"]?.stringValue ?? "individual"
            let kind: ConversationKind = kindRaw == "group" ? .group : .individual
            let protocolRaw = obj["protocol"]?.stringValue ?? "whatsapp"
            let messenger = MessengerProtocol(rawValue: protocolRaw) ?? .whatsapp
            let preview = obj["lastPreview"]?.stringValue ?? ""
            let unread = obj["unreadCount"]?.intValue ?? 0
            let pinned = {
                if case .bool(let value) = obj["isPinned"] { return value }
                return false
            }()
            let activity = obj["lastActivity"]?.intValue.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? .now
            mapped.append(
                Conversation(
                    id: ChatID(id),
                    title: title,
                    kind: kind,
                    participants: [Contact(id: ContactID(id), displayName: title, phoneNumber: nil)],
                    lastMessagePreview: preview,
                    lastActivity: activity,
                    unreadCount: unread,
                    isPinned: pinned,
                    avatarSymbol: kind == .group ? "person.3.fill" : messenger.symbolName,
                    avatarHue: Double(abs(id.hashValue % 1000)) / 1000.0,
                    messenger: messenger
                )
            )
        }
        // Merge by id so other protocols aren't wiped when one emits an update.
        var byID = Dictionary(uniqueKeysWithValues: conversations.map { ($0.id, $0) })
        for chat in mapped {
            byID[chat.id] = chat
        }
        conversations = byID.values.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned && !$1.isPinned }
            return $0.lastActivity > $1.lastActivity
        }
        publishConversations()
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
        let protocolRaw = envelope.payloadString("protocol") ?? "whatsapp"
        let messenger = MessengerProtocol(rawValue: protocolRaw) ?? .whatsapp
        ensureConversation(chatID: chatID, title: sender, messenger: messenger)

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

    private func ensureConversation(chatID: ChatID, title: String, messenger: MessengerProtocol) {
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
                avatarSymbol: messenger.symbolName,
                avatarHue: Double.random(in: 0...1),
                messenger: messenger
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

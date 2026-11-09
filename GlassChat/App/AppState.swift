import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class AppState {
    let themeEngine = ThemeEngine()
    let translationPreferences = TranslationPreferencesStore()
    let keychain = KeychainStore()

    private(set) var conversations: [Conversation] = []
    private(set) var messages: [Message] = []
    private(set) var connectionState: ConnectionState = .disconnected
    private(set) var selectedChatID: ChatID?
    private(set) var searchText: String = ""
    private(set) var sidebarWidth: Double = 280
    private(set) var backendKind: MessagingBackendKind = .whatsmeowBridge
    private(set) var protocolFilter: MessengerProtocol = .all
    private(set) var needsFirstLogin = false

    var translationService: any TranslationServicing = CompositeTranslationService()

    private var mockService = MockMessagingService()
    private var whatsmeowService = WhatsmeowMessagingService()
    private var conversationTask: Task<Void, Never>?
    private var messageTask: Task<Void, Never>?
    private var connectionTask: Task<Void, Never>?

    var filteredConversations: [Conversation] {
        var list = conversations
        if protocolFilter != .all {
            list = list.filter { $0.messenger == protocolFilter }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return list }
        return list.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.lastMessagePreview.localizedCaseInsensitiveContains(query)
        }
    }

    var selectedConversation: Conversation? {
        conversations.first(where: { $0.id == selectedChatID })
    }

    var isLiveBackend: Bool { backendKind == .whatsmeowBridge }

    var hasLinkedChats: Bool { !conversations.isEmpty }

    init() {
        migrateAwayFromDemoIfNeeded()
        startObserving()
        if backendKind == .whatsmeowBridge {
            Task { try? await whatsmeowService.startBridgeAndConnect() }
        }
    }

    func selectChat(_ id: ChatID?) {
        selectedChatID = id
        messageTask?.cancel()
        guard let id else {
            messages = []
            return
        }
        messageTask = Task {
            if backendKind == .whatsmeowBridge {
                await whatsmeowService.loadMessages(for: id)
            }
            let stream = await activeService().observeMessages(in: id)
            for await list in stream {
                guard !Task.isCancelled else { break }
                messages = list
            }
        }
        Task {
            try? await activeService().markRead(chatID: id)
        }
    }

    func setProtocolFilter(_ filter: MessengerProtocol) {
        protocolFilter = filter
        UserDefaults.standard.set(filter.rawValue, forKey: "glasschat.protocolFilter")
        if backendKind == .whatsmeowBridge {
            Task { await whatsmeowService.refreshChats(protocolKind: filter) }
        }
    }

    func updateSearch(_ text: String) {
        searchText = text
    }

    func updateSidebarWidth(_ width: Double) {
        sidebarWidth = min(420, max(220, width))
        UserDefaults.standard.set(sidebarWidth, forKey: "glasschat.sidebar.width")
    }

    func send(text: String, replyTo: MessageID?) async throws {
        guard let chatID = selectedChatID else { return }
        try await activeService().send(text: text, to: chatID, replyTo: replyTo)
    }

    func togglePin(_ conversation: Conversation) {
        Task {
            try? await activeService().setPinned(!conversation.isPinned, chatID: conversation.id)
        }
    }

    func switchBackend(_ kind: MessagingBackendKind) {
        backendKind = kind
        UserDefaults.standard.set(kind.rawValue, forKey: "glasschat.backend")
        if kind == .mock {
            UserDefaults.standard.set(true, forKey: "glasschat.allowDemo")
        }
        selectedChatID = nil
        messages = []
        startObserving()
        if kind == .whatsmeowBridge {
            Task {
                try? await whatsmeowService.startBridgeAndConnect()
            }
        }
    }

    func startWhatsAppPairing() async throws {
        try await startPairing(protocolKind: .whatsapp)
    }

    func startPairing(
        protocolKind: MessengerProtocol,
        telegramAPIID: String? = nil,
        telegramAPIHash: String? = nil,
        discordToken: String? = nil,
        discordBot: Bool = false
    ) async throws {
        backendKind = .whatsmeowBridge
        UserDefaults.standard.set(MessagingBackendKind.whatsmeowBridge.rawValue, forKey: "glasschat.backend")
        startObserving()
        try await whatsmeowService.startPairing(
            protocolKind: protocolKind,
            telegramAPIID: telegramAPIID,
            telegramAPIHash: telegramAPIHash,
            discordToken: discordToken,
            discordBot: discordBot
        )
    }

    func logoutWhatsApp() async throws {
        try await whatsmeowService.logout(protocolKind: .whatsapp)
    }

    func logout(protocolKind: MessengerProtocol) async throws {
        try await whatsmeowService.logout(protocolKind: protocolKind)
    }

    func currentPairingQRCode() async -> String? {
        await whatsmeowService.currentQRCode
    }

    func clearLocalData() async {
        try? await activeService().clearLocalData()
        translationPreferences.clearAll()
        if backendKind == .mock {
            await mockService.resetToSampleData()
        }
        selectedChatID = nil
        messages = []
    }

    func restoreSidebarWidth() {
        let stored = UserDefaults.standard.double(forKey: "glasschat.sidebar.width")
        if stored >= 220 {
            sidebarWidth = stored
        }
        if let filter = UserDefaults.standard.string(forKey: "glasschat.protocolFilter"),
           let kind = MessengerProtocol(rawValue: filter) {
            protocolFilter = kind
        }
        needsFirstLogin = isLiveBackend && !hasLinkedChats
    }

    func consumeFirstLoginPrompt() {
        needsFirstLogin = false
    }

    private func migrateAwayFromDemoIfNeeded() {
        let defaults = UserDefaults.standard
        let migratedKey = "glasschat.migratedLive.v1"
        if !defaults.bool(forKey: migratedKey) {
            // Force everyone off demo sample chats once.
            defaults.set(MessagingBackendKind.whatsmeowBridge.rawValue, forKey: "glasschat.backend")
            defaults.set(true, forKey: migratedKey)
            defaults.set(false, forKey: "glasschat.allowDemo")
            needsFirstLogin = true
        }

        if let backend = defaults.string(forKey: "glasschat.backend"),
           let kind = MessagingBackendKind(rawValue: backend) {
            if kind == .mock && !defaults.bool(forKey: "glasschat.allowDemo") {
                backendKind = .whatsmeowBridge
                defaults.set(MessagingBackendKind.whatsmeowBridge.rawValue, forKey: "glasschat.backend")
            } else {
                backendKind = kind
            }
        } else {
            backendKind = .whatsmeowBridge
        }
    }

    private func startObserving() {
        conversationTask?.cancel()
        connectionTask?.cancel()
        messageTask?.cancel()

        conversationTask = Task {
            let stream = await activeService().observeConversations()
            for await list in stream {
                guard !Task.isCancelled else { break }
                conversations = list
                if list.isEmpty {
                    selectedChatID = nil
                    messages = []
                } else if selectedChatID == nil {
                    // Don't auto-open a chat on empty→first sync; wait for user pick.
                } else if let selectedChatID, !list.contains(where: { $0.id == selectedChatID }) {
                    selectChat(list.first?.id)
                }
                needsFirstLogin = backendKind == .whatsmeowBridge && list.isEmpty
            }
        }

        connectionTask = Task {
            let stream = await activeService().observeConnectionState()
            for await state in stream {
                guard !Task.isCancelled else { break }
                connectionState = state
            }
        }

        if let selectedChatID {
            selectChat(selectedChatID)
        }
    }

    private func activeService() -> any MessagingService {
        switch backendKind {
        case .mock:
            return mockService
        case .whatsmeowBridge:
            return whatsmeowService
        }
    }
}

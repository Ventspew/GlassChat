import SwiftUI

struct ConversationView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeEngine.self) private var themeEngine
    @Environment(TranslationPreferencesStore.self) private var translationPreferences

    @State private var incomingTranslations: [MessageID: String] = [:]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            messageList
            ComposerView()
        }
        .background(themeEngine.current.chatBackground.opacity(themeEngine.current.usesMaterialBackground ? 0.35 : 1))
        .task(id: appState.selectedChatID) {
            await translateIncomingIfNeeded()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(appState.selectedConversation?.title ?? "Chat")
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                chatTranslationMenu
            } label: {
                Label("Translation", systemImage: "globe")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var subtitle: String {
        guard let conversation = appState.selectedConversation else { return "" }
        if conversation.isGroup {
            return "\(conversation.participants.count) participants · Group"
        }
        let settings = translationPreferences.settings(for: conversation.id)
        return "Target language: \(settings.targetLanguageCode.uppercased())"
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: themeEngine.current.messageSpacing) {
                    ForEach(appState.messages) { message in
                        MessageBubbleView(
                            message: message,
                            translatedText: incomingTranslations[message.id]
                        )
                        .id(message.id)
                    }
                }
                .padding(.vertical, 12)
            }
            .onChange(of: appState.messages.count) { _, _ in
                if let last = appState.messages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
                Task { await translateIncomingIfNeeded() }
            }
        }
    }

    @ViewBuilder
    private var chatTranslationMenu: some View {
        if let chatID = appState.selectedChatID {
            let settings = translationPreferences.settings(for: chatID)
            Picker("Target language", selection: Binding(
                get: { settings.targetLanguageCode },
                set: { code in
                    var updated = settings
                    updated.targetLanguageCode = code
                    translationPreferences.update(updated, for: chatID)
                }
            )) {
                Text("English").tag("en")
                Text("Dutch").tag("nl")
                Text("German").tag("de")
                Text("French").tag("fr")
                Text("Spanish").tag("es")
            }
            Toggle("Auto-translate outgoing", isOn: Binding(
                get: { settings.autoTranslateOutgoing },
                set: { value in
                    var updated = settings
                    updated.autoTranslateOutgoing = value
                    translationPreferences.update(updated, for: chatID)
                }
            ))
            Toggle("Translate incoming", isOn: Binding(
                get: { settings.translateIncoming },
                set: { value in
                    var updated = settings
                    updated.translateIncoming = value
                    translationPreferences.update(updated, for: chatID)
                    Task { await translateIncomingIfNeeded() }
                }
            ))
        }
    }

    private func translateIncomingIfNeeded() async {
        guard let chatID = appState.selectedChatID else { return }
        let settings = translationPreferences.settings(for: chatID)
        guard settings.translateIncoming else {
            incomingTranslations = [:]
            return
        }

        var results: [MessageID: String] = [:]
        for message in appState.messages where message.direction == .incoming {
            guard let text = message.body.plainText else { continue }
            do {
                let translated = try await appState.translationService.translate(
                    TranslationRequest(
                        text: text,
                        sourceLanguageCode: nil,
                        targetLanguageCode: settings.targetLanguageCode == "nl" ? "en" : "nl"
                    )
                )
                if translated.translatedText != text {
                    results[message.id] = translated.translatedText
                }
            } catch {
                continue
            }
        }
        incomingTranslations = results
    }
}

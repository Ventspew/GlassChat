import Foundation
import Observation

struct ChatTranslationSettings: Codable, Hashable, Sendable {
    var targetLanguageCode: String
    var autoTranslateOutgoing: Bool
    var translateIncoming: Bool

    static let `default` = ChatTranslationSettings(
        targetLanguageCode: "en",
        autoTranslateOutgoing: false,
        translateIncoming: false
    )
}

@Observable
@MainActor
final class TranslationPreferencesStore {
    private static let defaultsKey = "glasschat.translation.defaults"
    private static let perChatKey = "glasschat.translation.perChat"

    var globalDefaults: ChatTranslationSettings
    private(set) var perChat: [String: ChatTranslationSettings]

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode(ChatTranslationSettings.self, from: data) {
            globalDefaults = decoded
        } else {
            globalDefaults = .default
        }

        if let data = UserDefaults.standard.data(forKey: Self.perChatKey),
           let decoded = try? JSONDecoder().decode([String: ChatTranslationSettings].self, from: data) {
            perChat = decoded
        } else {
            perChat = [:]
        }
    }

    func settings(for chatID: ChatID) -> ChatTranslationSettings {
        perChat[chatID.rawValue] ?? globalDefaults
    }

    func update(_ settings: ChatTranslationSettings, for chatID: ChatID?) {
        if let chatID {
            perChat[chatID.rawValue] = settings
            persistPerChat()
        } else {
            globalDefaults = settings
            persistDefaults()
        }
    }

    func clearAll() {
        perChat = [:]
        globalDefaults = .default
        UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.perChatKey)
    }

    private func persistDefaults() {
        if let data = try? JSONEncoder().encode(globalDefaults) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    private func persistPerChat() {
        if let data = try? JSONEncoder().encode(perChat) {
            UserDefaults.standard.set(data, forKey: Self.perChatKey)
        }
    }
}

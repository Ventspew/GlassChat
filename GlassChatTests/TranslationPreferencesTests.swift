import XCTest
@testable import GlassChat

@MainActor
final class TranslationPreferencesTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "glasschat.translation.defaults.v2")
        UserDefaults.standard.removeObject(forKey: "glasschat.translation.perChat.v2")
        UserDefaults.standard.removeObject(forKey: "glasschat.translation.defaults")
        UserDefaults.standard.removeObject(forKey: "glasschat.translation.perChat")
    }

    func testPerChatOverridesGlobal() {
        let store = TranslationPreferencesStore()
        var global = store.globalDefaults
        global.targetLanguageCode = "en"
        global.incomingLanguageCode = "nl"
        store.update(global, for: nil)

        let chat = ChatID("chat-emma")
        var chatSettings = ChatTranslationSettings.default
        chatSettings.targetLanguageCode = "de"
        chatSettings.incomingLanguageCode = "en"
        chatSettings.autoTranslateOutgoing = true
        store.update(chatSettings, for: chat)

        XCTAssertEqual(store.settings(for: chat).targetLanguageCode, "de")
        XCTAssertEqual(store.settings(for: chat).incomingLanguageCode, "en")
        XCTAssertTrue(store.settings(for: chat).autoTranslateOutgoing)
        XCTAssertEqual(store.settings(for: ChatID("other")).targetLanguageCode, "en")
    }

    func testClearAllResets() {
        let store = TranslationPreferencesStore()
        var settings = store.globalDefaults
        settings.translateIncoming = false
        settings.targetLanguageCode = "es"
        store.update(settings, for: nil)
        store.clearAll()
        XCTAssertEqual(store.globalDefaults, ChatTranslationSettings.default)
    }

    func testDefaultsEnableBidirectionalTranslation() {
        let defaults = ChatTranslationSettings.default
        XCTAssertTrue(defaults.autoTranslateOutgoing)
        XCTAssertTrue(defaults.translateIncoming)
        XCTAssertFalse(defaults.incomingLanguageCode.isEmpty)
        XCTAssertFalse(defaults.targetLanguageCode.isEmpty)
    }
}

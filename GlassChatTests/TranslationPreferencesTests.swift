import XCTest
@testable import GlassChat

@MainActor
final class TranslationPreferencesTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "glasschat.translation.defaults")
        UserDefaults.standard.removeObject(forKey: "glasschat.translation.perChat")
    }

    func testPerChatOverridesGlobal() {
        let store = TranslationPreferencesStore()
        var global = store.globalDefaults
        global.targetLanguageCode = "en"
        store.update(global, for: nil)

        let chat = ChatID("chat-emma")
        var chatSettings = ChatTranslationSettings.default
        chatSettings.targetLanguageCode = "de"
        chatSettings.autoTranslateOutgoing = true
        store.update(chatSettings, for: chat)

        XCTAssertEqual(store.settings(for: chat).targetLanguageCode, "de")
        XCTAssertTrue(store.settings(for: chat).autoTranslateOutgoing)
        XCTAssertEqual(store.settings(for: ChatID("other")).targetLanguageCode, "en")
    }

    func testClearAllResets() {
        let store = TranslationPreferencesStore()
        var settings = store.globalDefaults
        settings.translateIncoming = true
        store.update(settings, for: nil)
        store.clearAll()
        XCTAssertFalse(store.globalDefaults.translateIncoming)
        XCTAssertEqual(store.globalDefaults.targetLanguageCode, "en")
    }
}

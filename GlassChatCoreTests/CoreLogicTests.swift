import XCTest
@testable import GlassChatCore

final class TokenPreserverCoreTests: XCTestCase {
    func testPreservesURLAndEmoji() {
        let preserver = TokenPreserver()
        let input = "Meet me at https://example.com 😊 soon"
        let protected = preserver.protect(input)
        let restored = preserver.restore(protected.protectedText, tokens: protected.tokens)
        XCTAssertEqual(restored, input)
        XCTAssertFalse(protected.tokens.isEmpty)
    }
}

@MainActor
final class ThemeEngineCoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "glasschat.theme.id")
        UserDefaults.standard.removeObject(forKey: "glasschat.theme.overrides")
    }

    func testThemeSelectionAndOverrides() {
        let engine = ThemeEngine()
        engine.select(themeID: BuiltInThemes.midnight.id)
        engine.updateBubbleCornerRadius(20)
        XCTAssertEqual(engine.current.id, "midnight")
        XCTAssertEqual(engine.current.bubbleCornerRadius, 20)
        XCTAssertEqual(BuiltInThemes.all.count, 5)
    }
}

@MainActor
final class TranslationPreferencesCoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "glasschat.translation.defaults")
        UserDefaults.standard.removeObject(forKey: "glasschat.translation.perChat")
    }

    func testPerChatOverride() {
        let store = TranslationPreferencesStore()
        let chat = ChatID("chat-emma")
        var settings = ChatTranslationSettings.default
        settings.targetLanguageCode = "de"
        store.update(settings, for: chat)
        XCTAssertEqual(store.settings(for: chat).targetLanguageCode, "de")
    }
}

final class MockMessagingCoreTests: XCTestCase {
    func testSendMessage() async throws {
        let service = MockMessagingService()
        let chat = ChatID("chat-emma")
        let stream = await service.observeMessages(in: chat)
        var iterator = stream.makeAsyncIterator()
        _ = await iterator.next()
        try await service.send(text: "Testbericht", to: chat, replyTo: nil)
        let updated = await iterator.next()
        XCTAssertEqual(updated?.last?.body.plainText, "Testbericht")
    }
}

final class PreviewTranslationCoreTests: XCTestCase {
    func testDutchToEnglishSample() async throws {
        let service = PreviewTranslationService()
        let result = try await service.translate(
            TranslationRequest(
                text: "Ik ben over vijf minuten bij je.",
                sourceLanguageCode: "nl",
                targetLanguageCode: "en"
            )
        )
        XCTAssertEqual(result.translatedText, "I'll be there in five minutes.")
    }
}

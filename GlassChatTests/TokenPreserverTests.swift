import XCTest
@testable import GlassChat

final class TokenPreserverTests: XCTestCase {
    func testPreservesURLAndEmoji() {
        let preserver = TokenPreserver()
        let input = "Meet me at https://example.com 😊 soon"
        let protected = preserver.protect(input)

        XCTAssertFalse(protected.protectedText.contains("https://example.com"))
        XCTAssertFalse(protected.protectedText.contains("😊"))
        XCTAssertFalse(protected.tokens.isEmpty)

        let restored = preserver.restore(protected.protectedText, tokens: protected.tokens)
        XCTAssertEqual(restored, input)
    }

    func testPreservesMention() {
        let preserver = TokenPreserver()
        let input = "Ping @emma later"
        let protected = preserver.protect(input)
        let restored = preserver.restore(protected.protectedText, tokens: protected.tokens)
        XCTAssertEqual(restored, input)
        XCTAssertTrue(protected.tokens.values.contains("@emma"))
    }
}

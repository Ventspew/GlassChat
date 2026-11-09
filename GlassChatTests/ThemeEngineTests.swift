import XCTest
@testable import GlassChat

@MainActor
final class ThemeEngineTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "glasschat.theme.id")
        UserDefaults.standard.removeObject(forKey: "glasschat.theme.overrides")
    }

    func testSelectThemePersists() {
        let engine = ThemeEngine()
        engine.select(themeID: BuiltInThemes.midnight.id)
        XCTAssertEqual(engine.current.id, BuiltInThemes.midnight.id)

        let reloaded = ThemeEngine()
        XCTAssertEqual(reloaded.current.id, BuiltInThemes.midnight.id)
    }

    func testOverridesApplyImmediately() {
        let engine = ThemeEngine()
        engine.select(themeID: BuiltInThemes.minimal.id)
        engine.updateBubbleCornerRadius(22)
        engine.updateMessageSpacing(10)
        XCTAssertEqual(engine.current.bubbleCornerRadius, 22)
        XCTAssertEqual(engine.current.messageSpacing, 10)

        let reloaded = ThemeEngine()
        XCTAssertEqual(reloaded.current.bubbleCornerRadius, 22)
        XCTAssertEqual(reloaded.current.messageSpacing, 10)
    }

    func testBuiltInCount() {
        XCTAssertEqual(BuiltInThemes.all.count, 6)
    }
}

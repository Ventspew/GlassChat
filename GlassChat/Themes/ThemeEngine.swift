import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class ThemeEngine {
    private static let storageKey = "glasschat.theme.id"
    private static let customOverridesKey = "glasschat.theme.overrides"
    private static let migratedHarborKey = "glasschat.theme.migratedHarbor.v1"

    private(set) var current: Theme
    var availableThemes: [Theme] { BuiltInThemes.all }

    init() {
        Self.migrateWashedThemesIfNeeded()
        let savedID = UserDefaults.standard.string(forKey: Self.storageKey)
        var theme = BuiltInThemes.theme(id: savedID ?? BuiltInThemes.harbor.id)
        if let data = UserDefaults.standard.data(forKey: Self.customOverridesKey),
           let overrides = try? JSONDecoder().decode(ThemeOverrides.self, from: data) {
            theme = overrides.apply(to: theme)
        }
        self.current = theme
    }

    /// One-time bump away from washed flat-white defaults.
    private static func migrateWashedThemesIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: migratedHarborKey) else { return }
        let current = UserDefaults.standard.string(forKey: storageKey)
        if current == nil || current == "apple-messages" || current == "liquid-glass" || current == "minimal" {
            UserDefaults.standard.set(BuiltInThemes.harbor.id, forKey: storageKey)
            UserDefaults.standard.removeObject(forKey: customOverridesKey)
        }
        UserDefaults.standard.set(true, forKey: migratedHarborKey)
    }

    func select(themeID: String) {
        var theme = BuiltInThemes.theme(id: themeID)
        if let data = UserDefaults.standard.data(forKey: Self.customOverridesKey),
           let overrides = try? JSONDecoder().decode(ThemeOverrides.self, from: data) {
            theme = overrides.apply(to: theme)
        }
        current = theme
        UserDefaults.standard.set(themeID, forKey: Self.storageKey)
    }

    func updateAccentHex(_ hex: String) {
        current.accentHex = hex
        persistOverrides()
    }

    func updateBubbleCornerRadius(_ value: Double) {
        current.bubbleCornerRadius = min(28, max(6, value))
        persistOverrides()
    }

    func updateMessageSpacing(_ value: Double) {
        current.messageSpacing = min(16, max(2, value))
        persistOverrides()
    }

    func updateDensity(_ density: ThemeDensity) {
        current.conversationDensity = density
        persistOverrides()
    }

    func updateSidebarOpacity(_ value: Double) {
        current.sidebarOpacity = min(1, max(0.5, value))
        persistOverrides()
    }

    func resetOverrides() {
        UserDefaults.standard.removeObject(forKey: Self.customOverridesKey)
        current = BuiltInThemes.theme(id: current.id)
    }

    private func persistOverrides() {
        let overrides = ThemeOverrides(
            accentHex: current.accentHex,
            bubbleCornerRadius: current.bubbleCornerRadius,
            messageSpacing: current.messageSpacing,
            conversationDensity: current.conversationDensity,
            sidebarOpacity: current.sidebarOpacity
        )
        if let data = try? JSONEncoder().encode(overrides) {
            UserDefaults.standard.set(data, forKey: Self.customOverridesKey)
        }
    }
}

struct ThemeOverrides: Codable, Sendable {
    var accentHex: String?
    var bubbleCornerRadius: Double?
    var messageSpacing: Double?
    var conversationDensity: ThemeDensity?
    var sidebarOpacity: Double?

    func apply(to theme: Theme) -> Theme {
        var copy = theme
        if let accentHex { copy.accentHex = accentHex }
        if let bubbleCornerRadius { copy.bubbleCornerRadius = bubbleCornerRadius }
        if let messageSpacing { copy.messageSpacing = messageSpacing }
        if let conversationDensity { copy.conversationDensity = conversationDensity }
        if let sidebarOpacity { copy.sidebarOpacity = sidebarOpacity }
        return copy
    }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = BuiltInThemes.harbor
}

extension EnvironmentValues {
    var chatTheme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

import SwiftUI

struct Theme: Identifiable, Hashable, Codable, Sendable {
    let id: String
    var name: String
    var preferredColorScheme: ThemeColorScheme
    var accentHex: String
    var outgoingBubbleHex: String
    var incomingBubbleHex: String
    var outgoingTextHex: String
    var incomingTextHex: String
    var chatBackgroundHex: String
    var sidebarBackgroundHex: String
    var sidebarSelectionHex: String
    var composerBackgroundHex: String
    var bodyFontSize: Double
    var messageSpacing: Double
    var bubbleCornerRadius: Double
    var conversationDensity: ThemeDensity
    var sidebarOpacity: Double
    var usesMaterialBackground: Bool

    var accent: Color { Color(hex: accentHex) }
    var outgoingBubble: Color { Color(hex: outgoingBubbleHex) }
    var incomingBubble: Color { Color(hex: incomingBubbleHex) }
    var outgoingText: Color { Color(hex: outgoingTextHex) }
    var incomingText: Color { Color(hex: incomingTextHex) }
    var chatBackground: Color { Color(hex: chatBackgroundHex) }
    var sidebarBackground: Color { Color(hex: sidebarBackgroundHex) }
    var sidebarSelection: Color { Color(hex: sidebarSelectionHex) }
    var composerBackground: Color { Color(hex: composerBackgroundHex) }
}

enum ThemeColorScheme: String, Codable, Sendable {
    case system
    case light
    case dark

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum ThemeDensity: String, Codable, Sendable, CaseIterable {
    case comfortable
    case compact

    var rowPadding: CGFloat {
        switch self {
        case .comfortable: return 10
        case .compact: return 6
        }
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let a, r, g, b: UInt64
        switch cleaned.count {
        case 8:
            a = (value & 0xFF00_0000) >> 24
            r = (value & 0x00FF_0000) >> 16
            g = (value & 0x0000_FF00) >> 8
            b = value & 0x0000_00FF
        case 6:
            a = 255
            r = (value & 0xFF0000) >> 16
            g = (value & 0x00FF00) >> 8
            b = value & 0x0000FF
        default:
            a = 255; r = 0; g = 0; b = 0
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

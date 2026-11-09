import Foundation

enum SettingsTab: String, CaseIterable, Identifiable, Hashable {
    case appearance
    case translation
    case privacy
    case connection
    case features

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appearance: return "Appearance"
        case .translation: return "Translation"
        case .privacy: return "Privacy"
        case .connection: return "Connection"
        case .features: return "Features"
        }
    }

    var systemImage: String {
        switch self {
        case .appearance: return "paintbrush"
        case .translation: return "globe"
        case .privacy: return "lock.shield"
        case .connection: return "qrcode"
        case .features: return "checklist"
        }
    }
}

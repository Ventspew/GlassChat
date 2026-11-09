import Foundation

enum BuiltInThemes {
    static let all: [Theme] = [
        harbor,
        appleMessages,
        whatsAppClassic,
        minimal,
        midnight,
        liquidGlass
    ]

    /// Default: slate sidebar + cool chat plane — not flat white.
    static let harbor = Theme(
        id: "harbor",
        name: "Harbor",
        preferredColorScheme: .light,
        accentHex: "1F7A8C",
        outgoingBubbleHex: "1F7A8C",
        incomingBubbleHex: "F4F7F8",
        outgoingTextHex: "FFFFFF",
        incomingTextHex: "15202B",
        chatBackgroundHex: "C9D6DF",
        sidebarBackgroundHex: "243447",
        sidebarSelectionHex: "2F455C",
        composerBackgroundHex: "F7FAFB",
        bodyFontSize: 14,
        messageSpacing: 7,
        bubbleCornerRadius: 16,
        conversationDensity: .comfortable,
        sidebarOpacity: 1.0,
        usesMaterialBackground: false
    )

    static let appleMessages = Theme(
        id: "apple-messages",
        name: "Apple Messages",
        preferredColorScheme: .system,
        accentHex: "0A84FF",
        outgoingBubbleHex: "0A84FF",
        incomingBubbleHex: "E5E5EA",
        outgoingTextHex: "FFFFFF",
        incomingTextHex: "000000",
        chatBackgroundHex: "E8E8ED",
        sidebarBackgroundHex: "ECECF0",
        sidebarSelectionHex: "D6E4FF",
        composerBackgroundHex: "FFFFFF",
        bodyFontSize: 14,
        messageSpacing: 6,
        bubbleCornerRadius: 18,
        conversationDensity: .comfortable,
        sidebarOpacity: 1.0,
        usesMaterialBackground: false
    )

    static let whatsAppClassic = Theme(
        id: "whatsapp-classic",
        name: "WhatsApp Classic",
        preferredColorScheme: .light,
        accentHex: "25D366",
        outgoingBubbleHex: "DCF8C6",
        incomingBubbleHex: "FFFFFF",
        outgoingTextHex: "111B21",
        incomingTextHex: "111B21",
        chatBackgroundHex: "EFEAE2",
        sidebarBackgroundHex: "FFFFFF",
        sidebarSelectionHex: "F0F2F5",
        composerBackgroundHex: "F0F2F5",
        bodyFontSize: 14,
        messageSpacing: 4,
        bubbleCornerRadius: 12,
        conversationDensity: .comfortable,
        sidebarOpacity: 1.0,
        usesMaterialBackground: false
    )

    static let minimal = Theme(
        id: "minimal",
        name: "Minimal",
        preferredColorScheme: .light,
        accentHex: "1C1C1E",
        outgoingBubbleHex: "1C1C1E",
        incomingBubbleHex: "F2F2F2",
        outgoingTextHex: "FFFFFF",
        incomingTextHex: "1C1C1E",
        chatBackgroundHex: "FFFFFF",
        sidebarBackgroundHex: "FAFAFA",
        sidebarSelectionHex: "EEEEEE",
        composerBackgroundHex: "FFFFFF",
        bodyFontSize: 14,
        messageSpacing: 8,
        bubbleCornerRadius: 10,
        conversationDensity: .compact,
        sidebarOpacity: 1.0,
        usesMaterialBackground: false
    )

    static let midnight = Theme(
        id: "midnight",
        name: "Midnight",
        preferredColorScheme: .dark,
        accentHex: "64D2FF",
        outgoingBubbleHex: "0A84FF",
        incomingBubbleHex: "2C2C2E",
        outgoingTextHex: "FFFFFF",
        incomingTextHex: "F5F5F7",
        chatBackgroundHex: "000000",
        sidebarBackgroundHex: "1C1C1E",
        sidebarSelectionHex: "2C2C2E",
        composerBackgroundHex: "1C1C1E",
        bodyFontSize: 14,
        messageSpacing: 6,
        bubbleCornerRadius: 16,
        conversationDensity: .comfortable,
        sidebarOpacity: 1.0,
        usesMaterialBackground: false
    )

    static let liquidGlass = Theme(
        id: "liquid-glass",
        name: "Liquid Glass",
        preferredColorScheme: .system,
        accentHex: "1F7A8C",
        outgoingBubbleHex: "1F7A8C",
        incomingBubbleHex: "FFFFFF",
        outgoingTextHex: "FFFFFF",
        incomingTextHex: "1C1C1E",
        chatBackgroundHex: "B9CBD6",
        sidebarBackgroundHex: "2A3B4C",
        sidebarSelectionHex: "3A5166",
        composerBackgroundHex: "F4F8FA",
        bodyFontSize: 14,
        messageSpacing: 7,
        bubbleCornerRadius: 18,
        conversationDensity: .comfortable,
        sidebarOpacity: 1.0,
        usesMaterialBackground: false
    )

    static func theme(id: String) -> Theme {
        all.first(where: { $0.id == id }) ?? harbor
    }
}

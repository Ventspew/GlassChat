import Foundation

enum FeatureAvailability: String, Codable, Sendable, CaseIterable {
    case implemented
    case planned
    case unsupported
}

struct FeatureDescriptor: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let detail: String
    let availability: FeatureAvailability
}

enum FeatureCatalog {
    static let all: [FeatureDescriptor] = [
        .init(id: "text", title: "Text messaging", detail: "Send and receive plain text (mock backend today).", availability: .implemented),
        .init(id: "themes", title: "Theme engine", detail: "Five built-in themes with live switching.", availability: .implemented),
        .init(id: "translation", title: "Composer translation", detail: "On-device Apple Translation with preview before send.", availability: .implemented),
        .init(id: "search", title: "Conversation search", detail: "Filter chats in the sidebar.", availability: .implemented),
        .init(id: "pins", title: "Pinned conversations", detail: "Pin important chats to the top of the list.", availability: .implemented),
        .init(id: "mock", title: "Mock messaging service", detail: "Local sample data for UI development.", availability: .implemented),
        .init(id: "bridge", title: "Local protocol bridge", detail: "Go whatsmeow helper over a local Unix socket.", availability: .implemented),
        .init(id: "qr", title: "Device linking (QR)", detail: "Pair as a linked multi-device companion via QR code.", availability: .implemented),
        .init(id: "media", title: "Images & documents", detail: "Send and receive media attachments.", availability: .planned),
        .init(id: "voice", title: "Voice messages", detail: "Record and play voice notes.", availability: .planned),
        .init(id: "reactions", title: "Reactions", detail: "Emoji reactions synchronized with WhatsApp.", availability: .planned),
        .init(id: "groups-admin", title: "Group administration", detail: "Create groups and manage participants.", availability: .planned),
        .init(id: "calls", title: "Voice & video calls", detail: "Not supported by the companion protocol library.", availability: .unsupported),
        .init(id: "broadcast", title: "Broadcast lists", detail: "Not supported by WhatsApp Web multi-device API.", availability: .unsupported)
    ]
}

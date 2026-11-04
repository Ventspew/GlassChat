import Foundation

enum MessagingError: Error, LocalizedError, Sendable {
    case notConnected
    case featureUnsupported(String)
    case sendFailed(String)
    case bridgeUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to a messaging backend."
        case .featureUnsupported(let name):
            return "\(name) is not implemented yet."
        case .sendFailed(let reason):
            return "Failed to send message: \(reason)"
        case .bridgeUnavailable(let reason):
            return "Protocol bridge unavailable: \(reason)"
        }
    }
}

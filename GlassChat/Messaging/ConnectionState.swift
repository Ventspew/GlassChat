import Foundation

enum ConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case awaitingPairing
    case connected(accountLabel: String)
    case error(String)

    var label: String {
        switch self {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting…"
        case .awaitingPairing:
            return "Awaiting pairing"
        case .connected(let accountLabel):
            return "Connected · \(accountLabel)"
        case .error(let message):
            return "Error · \(message)"
        }
    }
}

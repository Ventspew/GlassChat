import AppKit
import SwiftUI

struct MessageBubbleView: View {
    @Environment(\.chatTheme) private var theme
    let message: Message
    var translatedText: String?

    private var isOutgoing: Bool { message.direction == .outgoing }

    var body: some View {
        HStack {
            if isOutgoing { Spacer(minLength: 60) }

            VStack(alignment: isOutgoing ? .trailing : .leading, spacing: 4) {
                if message.direction == .incoming {
                    Text(message.senderName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Text(primaryText)
                    .font(.system(size: theme.bodyFontSize))
                    .foregroundStyle(isOutgoing ? theme.outgoingText : theme.incomingText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        isOutgoing ? theme.outgoingBubble : theme.incomingBubble,
                        in: RoundedRectangle(cornerRadius: theme.bubbleCornerRadius, style: .continuous)
                    )
                    .contextMenu {
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(primaryText, forType: .string)
                        }
                        if let translatedText, translatedText != displayText {
                            Button("Copy original") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(displayText, forType: .string)
                            }
                        }
                        Button("Reply") {}
                            .disabled(true)
                        Button("React") {}
                            .disabled(true)
                    }

                if let translatedText, translatedText != displayText, !isOutgoing {
                    Text(displayText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }

                HStack(spacing: 4) {
                    Text(message.timestamp, style: .time)
                    if isOutgoing {
                        Image(systemName: statusIcon)
                    }
                    if let reaction = message.reaction {
                        Text(reaction)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            if !isOutgoing { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 16)
        .transition(.move(edge: isOutgoing ? .trailing : .leading).combined(with: .opacity))
    }

    private var displayText: String {
        message.body.plainText ?? "Unsupported message"
    }

    /// Incoming: show translation as primary when available. Outgoing: always original sent text.
    private var primaryText: String {
        if !isOutgoing, let translatedText, !translatedText.isEmpty {
            return translatedText
        }
        return displayText
    }

    private var statusIcon: String {
        switch message.status {
        case .pending: return "clock"
        case .sent: return "checkmark"
        case .delivered: return "checkmark.circle"
        case .read: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle"
        }
    }
}

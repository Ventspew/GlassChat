import SwiftUI

struct ConversationRowView: View {
    @Environment(\.chatTheme) private var theme
    let conversation: Conversation
    var onDarkSidebar: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            avatar

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(conversation.title)
                        .font(.system(size: theme.bodyFontSize, weight: .semibold))
                        .foregroundStyle(onDarkSidebar ? Color.white.opacity(0.95) : Color.primary)
                        .lineLimit(1)
                    Text(conversation.messenger.displayName)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(theme.accent.opacity(onDarkSidebar ? 0.28 : 0.12), in: Capsule())
                        .foregroundStyle(onDarkSidebar ? Color.white : theme.accent)
                    Spacer(minLength: 4)
                    Text(conversation.lastActivity, style: .time)
                        .font(.caption2)
                        .foregroundStyle(onDarkSidebar ? Color.white.opacity(0.55) : Color.secondary)
                }

                HStack(alignment: .firstTextBaseline) {
                    Text(conversation.lastMessagePreview)
                        .font(.system(size: theme.bodyFontSize - 1))
                        .foregroundStyle(onDarkSidebar ? Color.white.opacity(0.6) : Color.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if conversation.unreadCount > 0 {
                        Text("\(conversation.unreadCount)")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(theme.accent, in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .padding(.vertical, theme.conversationDensity.rowPadding / 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(conversation.title), \(conversation.lastMessagePreview)")
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(Color(hue: conversation.avatarHue, saturation: 0.45, brightness: 0.85))
            Image(systemName: conversation.avatarSymbol)
                .foregroundStyle(.white)
                .font(.system(size: 14, weight: .semibold))
        }
        .frame(width: 36, height: 36)
        .overlay(alignment: .topTrailing) {
            if conversation.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(theme.accent)
                    .offset(x: 2, y: -2)
            }
        }
    }
}

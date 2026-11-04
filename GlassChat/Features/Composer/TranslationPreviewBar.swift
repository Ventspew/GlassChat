import SwiftUI

struct TranslationPreviewBar: View {
    @Environment(\.chatTheme) private var theme

    let original: String
    @Binding var translated: String
    let targetLanguageCode: String
    let isEditing: Bool
    let isTranslating: Bool
    let errorMessage: String?

    var onEdit: () -> Void
    var onUseOriginal: () -> Void
    var onSendTranslation: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Translation preview", systemImage: "globe")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(targetLanguageCode.uppercased())
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(theme.accent.opacity(0.15), in: Capsule())
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Original")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(original)
                    .font(.callout)
                    .textSelection(.enabled)

                Divider()

                Text("Translated")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if isEditing {
                    TextEditor(text: $translated)
                        .font(.callout)
                        .frame(minHeight: 48, maxHeight: 90)
                } else if isTranslating {
                    ProgressView("Translating…")
                        .controlSize(.small)
                } else {
                    Text(translated)
                        .font(.callout.weight(.medium))
                        .textSelection(.enabled)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Edit", action: onEdit)
                Button("Use original", action: onUseOriginal)
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Send translation", action: onSendTranslation)
                    .buttonStyle(.borderedProminent)
                    .disabled(translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isTranslating)
            }
            .controlSize(.small)
        }
        .padding(12)
        .background(theme.composerBackground.opacity(0.95), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(theme.accent.opacity(0.25), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

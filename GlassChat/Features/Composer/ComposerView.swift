import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ComposerView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeEngine.self) private var themeEngine
    @Environment(TranslationPreferencesStore.self) private var translationPreferences

    @State private var draft = ""
    @State private var showPreview = false
    @State private var translatedDraft = ""
    @State private var isEditingTranslation = false
    @State private var isTranslating = false
    @State private var translationError: String?
    @State private var isDropTargeted = false
    @FocusState private var composerFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if showPreview {
                TranslationPreviewBar(
                    original: draft,
                    translated: $translatedDraft,
                    targetLanguageCode: currentSettings.targetLanguageCode,
                    isEditing: isEditingTranslation,
                    isTranslating: isTranslating,
                    errorMessage: translationError,
                    onEdit: { isEditingTranslation = true },
                    onUseOriginal: { Task { await sendOriginal() } },
                    onSendTranslation: { Task { await sendTranslation() } },
                    onCancel: { resetPreview() }
                )
            }

            HStack(alignment: .bottom, spacing: 10) {
                Button {
                    // Emoji picker placeholder — uses character palette.
                    NSApp.orderFrontCharacterPalette(nil)
                } label: {
                    Image(systemName: "face.smiling")
                }
                .buttonStyle(.plain)
                .help("Emoji")

                TextField("Message", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .focused($composerFocused)
                    .onSubmit {
                        Task { await handleSendShortcut() }
                    }

                Button {
                    Task { await translateDraft() }
                } label: {
                    Image(systemName: "globe")
                }
                .buttonStyle(.plain)
                .help("Translate")
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    Task { await handleSendShortcut() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(canSend ? themeEngine.current.accent : Color.secondary.opacity(0.4))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .keyboardShortcut(.return, modifiers: [])
                .help("Send")
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(themeEngine.current.composerBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(isDropTargeted ? themeEngine.current.accent : Color.clear, lineWidth: 2)
                    )
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            .onDrop(of: [UTType.fileURL, UTType.image], isTargeted: $isDropTargeted) { providers in
                // Attachment sending is Planned — accept drop visually only.
                _ = providers
                translationError = "Attachments are planned (Phase 5)."
                return true
            }
        }
        .background(.bar)
    }

    private var currentSettings: ChatTranslationSettings {
        guard let chatID = appState.selectedChatID else {
            return translationPreferences.globalDefaults
        }
        return translationPreferences.settings(for: chatID)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func handleSendShortcut() async {
        guard canSend else { return }
        if currentSettings.autoTranslateOutgoing {
            await translateDraft()
            return
        }
        await sendOriginal()
    }

    private func translateDraft() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        showPreview = true
        isEditingTranslation = false
        isTranslating = true
        translationError = nil

        do {
            let result = try await appState.translationService.translate(
                TranslationRequest(
                    text: text,
                    sourceLanguageCode: nil,
                    targetLanguageCode: currentSettings.targetLanguageCode
                )
            )
            translatedDraft = result.translatedText
        } catch {
            translationError = error.localizedDescription
            translatedDraft = text
        }

        isTranslating = false
    }

    private func sendOriginal() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        do {
            try await appState.send(text: text, replyTo: nil)
            draft = ""
            resetPreview()
        } catch {
            translationError = error.localizedDescription
        }
    }

    private func sendTranslation() async {
        let text = translatedDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        do {
            try await appState.send(text: text, replyTo: nil)
            draft = ""
            resetPreview()
        } catch {
            translationError = error.localizedDescription
        }
    }

    private func resetPreview() {
        showPreview = false
        translatedDraft = ""
        isEditingTranslation = false
        isTranslating = false
        translationError = nil
    }
}

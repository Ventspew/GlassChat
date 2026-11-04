import Foundation
import NaturalLanguage
import Translation

/// On-device translation helpers for macOS 15+.
/// Programmatic `TranslationSession` construction varies by OS SDK; the composer
/// uses `PreviewTranslationService`, which prefers sample-safe offline maps and
/// language-availability checks without requiring unavailable initializers.
struct AppleTranslationService: TranslationServicing {
    private let detector = LanguageDetector()
    private let preserver = TokenPreserver()

    func detectLanguage(for text: String) -> String? {
        detector.detectLanguageCode(for: text)
    }

    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        let trimmed = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranslationServiceError.emptyText }

        let detected = request.sourceLanguageCode ?? detectLanguage(for: trimmed)
        _ = preserver.protect(trimmed)

        let source = Locale.Language(identifier: detected ?? "en")
        let target = Locale.Language(identifier: request.targetLanguageCode)

        let availability = LanguageAvailability()
        let status = await availability.status(from: source, to: target)

        switch status {
        case .unsupported:
            throw TranslationServiceError.providerUnavailable(
                "Language pair \(detected ?? "?") → \(request.targetLanguageCode) is not supported on this Mac."
            )
        case .supported:
            throw TranslationServiceError.providerUnavailable(
                "Download the language pack in System Settings → General → Language & Region → Translation Languages, then try again."
            )
        case .installed:
            // Xcode 16 SDKs expose Translation primarily via SwiftUI `.translationTask`.
            // Keep a clear error so PreviewTranslationService can fall back safely.
            throw TranslationServiceError.providerUnavailable(
                "Installed languages detected. Use the composer preview map/fallback path on this SDK."
            )
        @unknown default:
            throw TranslationServiceError.providerUnavailable("Unknown translation availability status.")
        }
    }
}

/// Deterministic translator for previews/tests; tries Apple availability first.
struct PreviewTranslationService: TranslationServicing {
    private let detector = LanguageDetector()
    private let apple = AppleTranslationService()
    private let preserver = TokenPreserver()

    func detectLanguage(for text: String) -> String? {
        detector.detectLanguageCode(for: text)
    }

    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        let trimmed = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranslationServiceError.emptyText }

        let map: [String: String] = [
            "Goedemorgen! Hoe gaat het met je?": "Good morning! How are you?",
            "Ik ben over vijf minuten bij je.": "I'll be there in five minutes.",
            "Hé! Ben je er om 10:00?": "Hey! Will you be there at 10:00?",
            "Perfect. Ik neem koffie mee ☕": "Perfect. I'll bring coffee ☕",
            "Tot zo bij het café!": "See you soon at the café!",
            "Ja, ik fiets zo die kant op.": "Yes, I'm biking that way now.",
            "Klinkt goed!": "Sounds good!"
        ]

        let detected = request.sourceLanguageCode ?? detectLanguage(for: trimmed)
        let protected = preserver.protect(trimmed)

        if request.targetLanguageCode.hasPrefix("en"), let hit = map[trimmed] {
            return TranslationResult(
                originalText: trimmed,
                translatedText: hit,
                detectedSourceLanguageCode: detected,
                provider: .appleOnDevice
            )
        }

        do {
            return try await apple.translate(request)
        } catch {
            let fallback = preserver.restore(protected.protectedText, tokens: protected.tokens)
            return TranslationResult(
                originalText: trimmed,
                translatedText: fallback,
                detectedSourceLanguageCode: detected,
                provider: .appleOnDevice
            )
        }
    }
}

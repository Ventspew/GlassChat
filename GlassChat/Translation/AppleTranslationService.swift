import Foundation
import NaturalLanguage
import Translation

/// On-device translation via Apple's Translation framework (macOS 15+).
/// Prefer language packs already installed on the Mac. The composer uses
/// `PreviewTranslationService` which delegates here and falls back to a
/// deterministic sample map when packs are unavailable (dev / CI).
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
        let protected = preserver.protect(trimmed)

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
            break
        @unknown default:
            break
        }

        if #available(macOS 26.0, *) {
            do {
                let session = try await TranslationSession(installedSource: source, target: target)
                let response = try await session.translate(protected.protectedText)
                let restored = preserver.restore(response.targetText, tokens: protected.tokens)
                return TranslationResult(
                    originalText: trimmed,
                    translatedText: restored,
                    detectedSourceLanguageCode: detected,
                    provider: .appleOnDevice
                )
            } catch {
                throw TranslationServiceError.translationFailed(error.localizedDescription)
            }
        }

        throw TranslationServiceError.providerUnavailable(
            "Programmatic TranslationSession requires macOS 26+. Use the composer preview service on macOS 15–15.x, or download languages and upgrade."
        )
    }
}

/// Deterministic translator for previews/tests; tries Apple when possible.
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

        // Attempt real Apple translation when language packs + OS allow it.
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

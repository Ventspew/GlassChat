import Foundation
import NaturalLanguage

enum TranslationProviderKind: String, CaseIterable, Identifiable, Sendable {
    case appleOnDevice
    case deepLPlaceholder

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleOnDevice:
            return "Apple Translation (on-device)"
        case .deepLPlaceholder:
            return "DeepL (planned)"
        }
    }
}

struct TranslationRequest: Sendable {
    var text: String
    var sourceLanguageCode: String?
    var targetLanguageCode: String
}

struct TranslationResult: Sendable {
    var originalText: String
    var translatedText: String
    var detectedSourceLanguageCode: String?
    var provider: TranslationProviderKind
}

protocol TranslationServicing: Sendable {
    func detectLanguage(for text: String) -> String?
    func translate(_ request: TranslationRequest) async throws -> TranslationResult
}

enum TranslationServiceError: Error, LocalizedError, Sendable {
    case emptyText
    case providerUnavailable(String)
    case translationFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyText:
            return "Nothing to translate."
        case .providerUnavailable(let reason):
            return reason
        case .translationFailed(let reason):
            return reason
        }
    }
}

struct LanguageDetector: Sendable {
    func detectLanguageCode(for text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage else { return nil }
        return language.rawValue
    }
}

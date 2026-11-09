import Foundation

/// Free MyMemory translation fallback (no API key required for light use).
/// Used when on-device Apple Translation / local maps can't handle the text.
struct NetworkTranslationService: TranslationServicing, Sendable {
    private let detector = LanguageDetector()
    private let preserver = TokenPreserver()
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func detectLanguage(for text: String) -> String? {
        detector.detectLanguageCode(for: text)
    }

    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        let trimmed = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranslationServiceError.emptyText }

        let detected = request.sourceLanguageCode ?? detectLanguage(for: trimmed) ?? "auto"
        let protected = preserver.protect(trimmed)
        let source = detected == "und" ? "auto" : detected
        let pair = "\(source)|\(request.targetLanguageCode)"

        var components = URLComponents(string: "https://api.mymemory.translated.net/get")!
        components.queryItems = [
            URLQueryItem(name: "q", value: protected.protectedText),
            URLQueryItem(name: "langpair", value: pair)
        ]
        guard let url = components.url else {
            throw TranslationServiceError.translationFailed("Invalid translation URL")
        }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw TranslationServiceError.translationFailed("Translation network error")
        }

        let decoded = try JSONDecoder().decode(MyMemoryResponse.self, from: data)
        let translated = decoded.responseData?.translatedText ?? trimmed
        let restored = preserver.restore(translated, tokens: protected.tokens)
        return TranslationResult(
            originalText: trimmed,
            translatedText: restored,
            detectedSourceLanguageCode: detected,
            provider: .appleOnDevice
        )
    }
}

private struct MyMemoryResponse: Decodable {
    let responseData: MyMemoryData?
}

private struct MyMemoryData: Decodable {
    let translatedText: String?
}

/// Chains local phrase map → network translation for reliable send/receive translation.
struct CompositeTranslationService: TranslationServicing, Sendable {
    private let local = PreviewTranslationService()
    private let network = NetworkTranslationService()
    private let detector = LanguageDetector()

    func detectLanguage(for text: String) -> String? {
        detector.detectLanguageCode(for: text)
    }

    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        let localResult = try await local.translate(request)
        // If local map produced a real change, keep it (fast + private).
        if localResult.translatedText != localResult.originalText,
           !localResult.translatedText.hasPrefix("[\(request.targetLanguageCode)]") {
            return localResult
        }
        // Otherwise ask MyMemory.
        do {
            return try await network.translate(request)
        } catch {
            return localResult
        }
    }
}

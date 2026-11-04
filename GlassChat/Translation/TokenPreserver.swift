import Foundation

/// Protects URLs, emoji sequences, and @mentions from translation mangling.
struct TokenPreserver: Sendable {
    struct Result: Sendable {
        let protectedText: String
        let tokens: [String: String]
    }

    func protect(_ text: String) -> Result {
        var working = text
        var tokens: [String: String] = [:]
        var index = 0

        let patterns: [NSRegularExpression] = [
            try! NSRegularExpression(pattern: #"https?://\S+"#),
            try! NSRegularExpression(pattern: #"www\.\S+"#),
            try! NSRegularExpression(pattern: #"@[\p{L}0-9_]+"#),
            try! NSRegularExpression(pattern: #"[\p{Emoji_Presentation}\p{Extended_Pictographic}]"#)
        ]

        for regex in patterns {
            let matches = regex.matches(in: working, range: NSRange(working.startIndex..., in: working))
            for match in matches.reversed() {
                guard let range = Range(match.range, in: working) else { continue }
                let value = String(working[range])
                let key = "⟦T\(index)⟧"
                tokens[key] = value
                working.replaceSubrange(range, with: key)
                index += 1
            }
        }

        return Result(protectedText: working, tokens: tokens)
    }

    func restore(_ text: String, tokens: [String: String]) -> String {
        var working = text
        for (key, value) in tokens {
            working = working.replacingOccurrences(of: key, with: value)
        }
        return working
    }
}

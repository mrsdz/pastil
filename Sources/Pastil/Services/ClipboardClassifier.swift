import Foundation

enum ClipboardClassifier {
    static func classify(_ text: String) -> ClipboardKind {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if isHexColor(trimmed) {
            return .color
        }

        if let url = URL(string: trimmed), url.scheme != nil, url.host != nil {
            return .link
        }

        if looksLikeCode(trimmed) {
            return .code
        }

        return .text
    }

    private static func isHexColor(_ text: String) -> Bool {
        let pattern = #"^#?([A-Fa-f0-9]{6}|[A-Fa-f0-9]{8}|[A-Fa-f0-9]{3})$"#
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    private static func looksLikeCode(_ text: String) -> Bool {
        let codeSignals = [
            "func ", "class ", "struct ", "enum ", "import ", "let ", "var ",
            "const ", "return ", "=>", "{", "}", "</", "SELECT ", "FROM "
        ]
        let signalCount = codeSignals.filter { text.localizedCaseInsensitiveContains($0) }.count
        return text.contains("\n") && signalCount >= 2 || text.hasPrefix("#!") || text.hasPrefix("```")
    }
}

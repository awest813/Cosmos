import Foundation

/// Splits profile `args` strings into argv tokens for `run.command --game`.
/// Handles simple single- and double-quoted groups; backslashes are literal.
enum ShellArgumentParser {
    static func parse(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }

        enum QuoteState {
            case none
            case single
            case double
        }

        let whitespaceCharacters = CharacterSet.whitespacesAndNewlines
        var state: QuoteState = .none
        var current = ""
        var result: [String] = []

        for character in text {
            switch character {
            case "'" where state == .none:
                state = .single
            case "'" where state == .single:
                state = .none
            case "\"" where state == .none:
                state = .double
            case "\"" where state == .double:
                state = .none
            default:
                if state == .none, character.unicodeScalars.allSatisfy({ whitespaceCharacters.contains($0) }) {
                    if !current.isEmpty {
                        result.append(current)
                        current = ""
                    }
                } else {
                    current.append(character)
                }
            }
        }

        if !current.isEmpty {
            result.append(current)
        }

        return result
    }

    /// Wrap a value in single quotes for safe use as one shell word.
    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Escape a value for embedding inside an AppleScript double-quoted string.
    static func appleScriptEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

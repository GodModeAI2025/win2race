import Foundation

enum ShellWords {
    enum ParseError: LocalizedError {
        case unterminatedQuote(Character)

        var errorDescription: String? {
            switch self {
            case .unterminatedQuote(let quote):
                return "Nicht geschlossene Quote \(quote) in Extra-Argumenten."
            }
        }
    }

    static func split(_ input: String) throws -> [String] {
        var result: [String] = []
        var current = ""
        var quote: Character?
        var escaping = false

        for character in input {
            if escaping {
                current.append(character)
                escaping = false
                continue
            }

            if character == "\\" {
                escaping = true
                continue
            }

            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else {
                    current.append(character)
                }
                continue
            }

            if character == "\"" || character == "'" {
                quote = character
                continue
            }

            if character.isWhitespace {
                if !current.isEmpty {
                    result.append(current)
                    current = ""
                }
                continue
            }

            current.append(character)
        }

        if let quote {
            throw ParseError.unterminatedQuote(quote)
        }
        if escaping {
            current.append("\\")
        }
        if !current.isEmpty {
            result.append(current)
        }
        return result
    }

    static func quote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

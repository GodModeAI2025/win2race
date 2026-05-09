import Foundation

enum EnvironmentFileLoaderError: LocalizedError {
    case invalidSyntax([String])

    var errorDescription: String? {
        switch self {
        case .invalidSyntax(let messages):
            "ENV-Datei hat Syntaxfehler: \(messages.joined(separator: " "))"
        }
    }
}

enum EnvironmentFileLoader {
    static func load(url: URL) throws -> [String: String] {
        let content = try String(contentsOf: url, encoding: .utf8)
        let validationMessages = EnvironmentFileValidator.validationMessages(for: content)
        guard validationMessages.isEmpty else {
            throw EnvironmentFileLoaderError.invalidSyntax(validationMessages)
        }

        var result: [String: String] = [:]
        for rawLine in content.split(whereSeparator: \.isNewline).map(String.init) {
            var line = rawLine.trimmed
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }
            if line.hasPrefix("export ") {
                line = String(line.dropFirst("export ".count)).trimmed
            }
            guard let equals = line.firstIndex(of: "=") else {
                continue
            }
            let key = String(line[..<equals]).trimmed
            var value = String(line[line.index(after: equals)...]).trimmed
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            if value.hasPrefix("'"), value.hasSuffix("'"), value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            if !key.isEmpty {
                result[key] = value
            }
        }

        return result
    }
}

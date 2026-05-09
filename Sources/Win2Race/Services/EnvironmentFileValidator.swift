import Foundation

enum EnvironmentFileValidator {
    static func validationMessages(for content: String) -> [String] {
        content
            .components(separatedBy: .newlines)
            .enumerated()
            .compactMap { index, rawLine in
                validationMessage(for: rawLine, lineNumber: index + 1)
            }
    }

    private static func validationMessage(for rawLine: String, lineNumber: Int) -> String? {
        var line = rawLine.trimmed
        if line.isEmpty || line.hasPrefix("#") {
            return nil
        }

        if line.hasPrefix("export ") {
            line = String(line.dropFirst("export ".count)).trimmed
        }

        guard let equals = line.firstIndex(of: "=") else {
            return "Zeile \(lineNumber): erwartet `KEY=value` oder `export KEY=value`."
        }

        let key = String(line[..<equals]).trimmed
        guard key.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil else {
            return "Zeile \(lineNumber): `\(key)` ist kein gültiger ENV-Name."
        }

        return nil
    }
}

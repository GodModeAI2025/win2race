import Foundation

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmpty: String? {
        let value = trimmed
        return value.isEmpty ? nil : value
    }

    var linesWithoutEmpty: [String] {
        split(whereSeparator: \.isNewline)
            .map { String($0).trimmed }
            .map { line in
                if line.hasPrefix("- ") {
                    return String(line.dropFirst(2)).trimmed
                }
                return line
            }
            .filter { !$0.isEmpty }
    }
}

enum Slugger {
    static func slug(_ value: String) -> String {
        let lowered = value.lowercased()
        let scalars = lowered.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) {
                return Character(scalar)
            }
            return "-"
        }
        let collapsed = String(scalars)
            .split(separator: "-")
            .joined(separator: "-")
        return collapsed.isEmpty ? "task" : collapsed
    }
}

enum W2RDateFormatter {
    static let branchTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter
    }()

    static let displayDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

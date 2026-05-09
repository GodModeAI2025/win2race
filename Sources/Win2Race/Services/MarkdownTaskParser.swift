import Foundation

enum TaskParseError: LocalizedError {
    case missingSection(String)

    var errorDescription: String? {
        switch self {
        case .missingSection(let section):
            "Die Aufgaben-Datei enthält keinen Abschnitt \(section)."
        }
    }
}

enum MarkdownTaskParser {
    static func parse(contents: String, sourceURL: URL) throws -> ParsedTaskFile {
        var sections: [String: [String]] = [:]
        var current: String?

        for rawLine in contents.split(whereSeparator: \.isNewline).map(String.init) {
            let line = rawLine.trimmed
            if line.hasPrefix("## ") {
                current = String(line.dropFirst(3)).trimmed.lowercased()
                if let current {
                    sections[current, default: []] = []
                }
                continue
            }

            if let current {
                sections[current, default: []].append(rawLine)
            }
        }

        let repository = value(for: "repository", in: sections)
        let title = value(for: "title", in: sections)
        let description = value(for: "description", in: sections)
        let constraints = value(for: "constraints", in: sections, required: false)

        guard let repository, !repository.isEmpty else {
            throw TaskParseError.missingSection("Repository")
        }
        guard let title, !title.isEmpty else {
            throw TaskParseError.missingSection("Title")
        }
        guard let description, !description.isEmpty else {
            throw TaskParseError.missingSection("Description")
        }

        return ParsedTaskFile(
            sourceURL: sourceURL,
            draft: TaskDraft(
                repository: repository,
                title: title,
                description: description,
                constraints: constraints ?? "",
                exampleRepository: ""
            )
        )
    }

    private static func value(
        for key: String,
        in sections: [String: [String]],
        required: Bool = true
    ) -> String? {
        guard let lines = sections[key] else {
            return nil
        }
        return lines.joined(separator: "\n").trimmed
    }
}

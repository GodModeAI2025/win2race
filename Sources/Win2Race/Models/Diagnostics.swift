import Foundation

enum DiagnosticSeverity: String, Codable, CaseIterable, Hashable {
    case info
    case warning
    case error

    var label: String {
        switch self {
        case .info: "Info"
        case .warning: "Warnung"
        case .error: "Fehler"
        }
    }
}

struct DiagnosticRecord: Identifiable, Codable, Hashable {
    let id: UUID
    var createdAt: Date
    var severity: DiagnosticSeverity
    var title: String
    var message: String
    var context: String
    var details: String
    var filePath: String?
    var taskID: UUID?
    var runID: UUID?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        severity: DiagnosticSeverity,
        title: String,
        message: String,
        context: String,
        details: String = "",
        filePath: String? = nil,
        taskID: UUID? = nil,
        runID: UUID? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.severity = severity
        self.title = title
        self.message = message
        self.context = context
        self.details = details
        self.filePath = filePath
        self.taskID = taskID
        self.runID = runID
    }

    var copyText: String {
        """
        [\(severity.label)] \(title)
        Time: \(W2RDateFormatter.displayDateTime.string(from: createdAt))
        Context: \(context)
        Message: \(message)
        File: \(filePath ?? "n/a")
        Task ID: \(taskID?.uuidString ?? "n/a")
        Run ID: \(runID?.uuidString ?? "n/a")

        Details:
        \(details.trimmed.isEmpty ? "n/a" : details)
        """
    }
}

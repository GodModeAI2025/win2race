import Foundation

enum WorkMode: String, Codable, CaseIterable, Identifiable {
    case simple
    case advanced

    var id: String { rawValue }

    var label: String {
        switch self {
        case .simple: "Simple Mode"
        case .advanced: "Advanced Mode"
        }
    }
}

enum TaskStatus: String, Codable, CaseIterable {
    case draft
    case queued
    case running
    case waitingForUser
    case completed
    case failed
}

enum AgentRunStatus: String, Codable, CaseIterable {
    case pending
    case preparing
    case running
    case waitingForUser
    case succeeded
    case failed
    case cancelled

    var label: String {
        switch self {
        case .pending: "Wartet"
        case .preparing: "Vorbereitung"
        case .running: "Läuft"
        case .waitingForUser: "Rückfrage"
        case .succeeded: "Erfolgreich"
        case .failed: "Fehlgeschlagen"
        case .cancelled: "Abgebrochen"
        }
    }

    var isTerminal: Bool {
        switch self {
        case .succeeded, .failed, .cancelled: true
        default: false
        }
    }
}

enum FeedbackVerdict: String, Codable, CaseIterable, Identifiable {
    case confirmed
    case needsWork
    case unusable
    case alternativeUsed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .confirmed: "Bestätigt"
        case .needsWork: "Nacharbeiten"
        case .unusable: "Untauglich"
        case .alternativeUsed: "Alternative genutzt"
        }
    }
}

struct TaskDraft: Equatable, Hashable {
    var repository: String = ""
    var title: String = ""
    var description: String = ""
    var constraints: String = ""
    var exampleRepository: String = ""

    var isStartable: Bool {
        !repository.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct W2RTask: Identifiable, Codable, Hashable {
    let id: UUID
    var mode: WorkMode
    var repository: String
    var title: String
    var description: String
    var constraints: [String]
    var exampleRepository: String?
    var createdAt: Date
    var slug: String
    var status: TaskStatus
    var rootPath: String

    static func fromDraft(_ draft: TaskDraft, mode: WorkMode, rootPath: String) -> W2RTask {
        let title = draft.title.trimmed
        return W2RTask(
            id: UUID(),
            mode: mode,
            repository: draft.repository.trimmed,
            title: title,
            description: draft.description.trimmed,
            constraints: draft.constraints.linesWithoutEmpty,
            exampleRepository: draft.exampleRepository.trimmed.nilIfEmpty,
            createdAt: Date(),
            slug: Slugger.slug(title),
            status: .queued,
            rootPath: rootPath
        )
    }
}

struct AgentRunRecord: Identifiable, Codable, Hashable {
    let id: UUID
    var taskID: UUID
    var agent: AgentKind
    var status: AgentRunStatus
    var commandPath: String
    var branchName: String
    var workspacePath: String
    var logPath: String
    var adrPath: String
    var runtimePath: String
    var feedbackPath: String
    var startedAt: Date?
    var endedAt: Date?
    var exitCode: Int32?
    var estimatedTokens: Int
    var estimatedCost: Decimal?
    var lastAction: String
    var pendingQuestion: String?
    var errorSummary: String?
    var commitHash: String?

    var duration: TimeInterval? {
        guard let startedAt else { return nil }
        return (endedAt ?? Date()).timeIntervalSince(startedAt)
    }
}

struct FeedbackRecord: Codable, Hashable {
    var taskID: UUID
    var runID: UUID
    var agent: AgentKind
    var verdict: FeedbackVerdict
    var notes: String
    var createdAt: Date
}

struct LearningSummaryRow: Identifiable, Hashable {
    var id: AgentKind { agent }
    var agent: AgentKind
    var total: Int
    var confirmed: Int
    var needsWork: Int
    var unusable: Int
    var alternativeUsed: Int

    var successRate: Double {
        guard total > 0 else { return 0 }
        return Double(confirmed) / Double(total)
    }
}

struct ParsedTaskFile: Hashable {
    var sourceURL: URL
    var draft: TaskDraft
}

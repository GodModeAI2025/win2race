import Foundation

enum RuntimeHealth: String, Codable, CaseIterable {
    case ready
    case missing
    case misconfigured

    var label: String {
        switch self {
        case .ready: "Bereit"
        case .missing: "Fehlt"
        case .misconfigured: "Konfiguration prüfen"
        }
    }
}

struct RuntimeRecord: Identifiable, Codable, Hashable {
    var id: AgentKind { agent }
    var agent: AgentKind
    var commandPath: String?
    var strategy: CLIStrategy
    var health: RuntimeHealth
    var capabilities: [String]
    var lastCheckedAt: Date
    var message: String
}

struct AgentProfile: Identifiable, Codable, Hashable {
    var id: AgentKind { agent }
    var agent: AgentKind
    var commandPathOverride: String
    var modelOverride: String
    var extraArguments: String
    var sshIdentityPath: String
    var gitUserName: String
    var gitUserEmail: String
    var timeoutSeconds: Int

    static func `default`(for agent: AgentKind) -> AgentProfile {
        AgentProfile(
            agent: agent,
            commandPathOverride: "",
            modelOverride: agent.defaultModelName ?? "",
            extraArguments: "",
            sshIdentityPath: "",
            gitUserName: "",
            gitUserEmail: "",
            timeoutSeconds: 7_200
        )
    }
}

enum RunEventType: String, Codable, CaseIterable {
    case lifecycle
    case stdout
    case stderr
    case userInput
    case process
    case question
    case error
    case git
    case heartbeat

    var label: String {
        switch self {
        case .lifecycle: "Lifecycle"
        case .stdout: "Stdout"
        case .stderr: "Stderr"
        case .userInput: "User"
        case .process: "Process"
        case .question: "Rückfrage"
        case .error: "Fehler"
        case .git: "Git"
        case .heartbeat: "Heartbeat"
        }
    }
}

struct RunEvent: Identifiable, Codable, Hashable {
    let id: UUID
    var runID: UUID
    var taskID: UUID
    var agent: AgentKind
    var sequence: Int
    var type: RunEventType
    var createdAt: Date
    var message: String
    var isError: Bool
    var copyText: String {
        """
        [\(W2RDateFormatter.displayDateTime.string(from: createdAt))] \(agent.displayName) #\(sequence) \(type.label)
        Run: \(runID.uuidString)
        Task: \(taskID.uuidString)

        \(message)
        """
    }
}

struct WorkspaceCleanupReport: Hashable {
    var removedItems: Int
    var reclaimedBytes: UInt64
    var errors: [String]

    var summary: String {
        let megabytes = Double(reclaimedBytes) / 1_048_576
        let formatted = String(format: "%.1f MB", megabytes)
        if errors.isEmpty {
            return "\(removedItems) Artefakte entfernt, \(formatted) freigegeben."
        }
        return "\(removedItems) Artefakte entfernt, \(formatted) freigegeben, \(errors.count) Fehler."
    }
}

struct ProviderTokenTestResult: Identifiable, Codable, Hashable {
    var id: String { key }
    var key: String
    var provider: String
    var checkedAt: Date
    var succeeded: Bool
    var budgetLikelyAvailable: Bool
    var statusCode: Int?
    var summary: String
    var details: String

    var copyText: String {
        """
        Provider token test
        Key: \(key)
        Provider: \(provider)
        Checked: \(W2RDateFormatter.displayDateTime.string(from: checkedAt))
        HTTP: \(statusCode.map(String.init) ?? "n/a")
        Success: \(succeeded)
        Budget likely available: \(budgetLikelyAvailable)

        \(summary)

        Details:
        \(details.trimmed.isEmpty ? "n/a" : details)
        """
    }
}

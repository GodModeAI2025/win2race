import Foundation

final class FileBackedTaskStore {
    let rootURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(rootURL: URL = FileBackedTaskStore.defaultRootURL, fileManager: FileManager = .default) {
        self.rootURL = rootURL
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    static var defaultRootURL: URL {
        let fileManager = FileManager.default
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
        let base = documents ?? URL(fileURLWithPath: NSHomeDirectory())
        return base.appendingPathComponent("Win2Race/workspace", isDirectory: true)
    }

    var tasksURL: URL {
        rootURL.appendingPathComponent("tasks", isDirectory: true)
    }

    var configURL: URL {
        rootURL.appendingPathComponent("config", isDirectory: true)
    }

    var diagnosticsURL: URL {
        rootURL.appendingPathComponent("diagnostics.jsonl")
    }

    func ensureRoot() throws {
        try fileManager.createDirectory(at: tasksURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: configURL, withIntermediateDirectories: true)
        for agent in AgentKind.allCases {
            let url = envFileURL(for: agent)
            if fileManager.fileExists(atPath: url.path) == false {
                try envTemplate(for: agent).write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

    func taskRootURL(slug: String, id: UUID) -> URL {
        tasksURL.appendingPathComponent("\(slug)-\(id.uuidString.prefix(8))", isDirectory: true)
    }

    func envFileURL(for agent: AgentKind) -> URL {
        configURL.appendingPathComponent("\(agent.rawValue).env")
    }

    func envTemplate(for agent: AgentKind) -> String {
        let keys = agent.requiredEnvironmentKeys.map { "# export \($0)=..." }.joined(separator: "\n")
        return """
        # Win-to-Race ENV for \(agent.displayName)
        # Values in this file are merged into the process environment before the CLI starts.
        \(keys.isEmpty ? "# export PROVIDER_API_KEY=..." : keys)
        """
    }

    func readEnvFile(for agent: AgentKind) throws -> String {
        try ensureRoot()
        return try String(contentsOf: envFileURL(for: agent), encoding: .utf8)
    }

    func writeEnvFile(_ content: String, for agent: AgentKind) throws {
        try ensureRoot()
        try content.write(to: envFileURL(for: agent), atomically: true, encoding: .utf8)
    }

    func createTask(from draft: TaskDraft, mode: WorkMode) throws -> W2RTask {
        try ensureRoot()
        let temporary = W2RTask.fromDraft(draft, mode: mode, rootPath: "")
        let root = taskRootURL(slug: temporary.slug, id: temporary.id)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        var task = temporary
        task.rootPath = root.path
        try writeTask(task)
        return task
    }

    func writeTask(_ task: W2RTask) throws {
        let root = URL(fileURLWithPath: task.rootPath, isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try encode(task, to: root.appendingPathComponent("task.json"))
        try taskMarkdown(task).write(to: root.appendingPathComponent("task.md"), atomically: true, encoding: .utf8)
    }

    func writeRun(_ run: AgentRunRecord) throws {
        let runURL = URL(fileURLWithPath: run.runtimePath).deletingLastPathComponent()
        try fileManager.createDirectory(at: runURL, withIntermediateDirectories: true)
        try encode(run, to: runURL.appendingPathComponent("run.json"))
        try runtimeMarkdown(run).write(to: URL(fileURLWithPath: run.runtimePath), atomically: true, encoding: .utf8)
    }

    func appendLog(_ text: String, to run: AgentRunRecord) throws {
        let url = URL(fileURLWithPath: run.logPath)
        let data = Data(text.utf8)
        if fileManager.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer {
                try? handle.close()
            }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }
    }

    func writeADR(for task: W2RTask, run: AgentRunRecord, diffStat: String, validation: String) throws {
        let content = """
        # ADR

        ## Problem
        \(task.description)

        ## Decision
        \(run.agent.displayName) worked on branch `\(run.branchName)` in an isolated workspace.

        ## Why
        Win-to-Race selected the agent automatically from locally available coding CLIs. The run executed headlessly and streamed logs into `session.log`.

        ## Risks
        - The generated solution still requires human review.
        - CLI token usage and exact cost can only be recorded when the CLI exposes that data.
        - Sandbox enforcement depends on macOS `sandbox-exec` availability.

        ## Validation
        \(validation)

        ## Diff Stat
        ```text
        \(diffStat.trimmed.isEmpty ? "No diff stat available." : diffStat.trimmed)
        ```
        """
        try content.write(to: URL(fileURLWithPath: run.adrPath), atomically: true, encoding: .utf8)
    }

    func writeFeedback(_ feedback: FeedbackRecord, run: AgentRunRecord) throws {
        let content = """
        # Feedback

        - Task ID: \(feedback.taskID.uuidString)
        - Run ID: \(feedback.runID.uuidString)
        - Agent: \(feedback.agent.displayName)
        - Verdict: \(feedback.verdict.label)
        - Created: \(W2RDateFormatter.displayDateTime.string(from: feedback.createdAt))

        ## Notes
        \(feedback.notes.trimmed.isEmpty ? "No notes." : feedback.notes.trimmed)
        """
        try content.write(to: URL(fileURLWithPath: run.feedbackPath), atomically: true, encoding: .utf8)
    }

    func loadTasks() -> [W2RTask] {
        do {
            return try loadTasksReportingDiagnostics()
        } catch {
            return []
        }
    }

    func loadTasksReportingDiagnostics() throws -> [W2RTask] {
        let entries = try fileManager.contentsOfDirectory(
            at: tasksURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        var tasks: [W2RTask] = []
        for entry in entries {
            let taskURL = entry.appendingPathComponent("task.json")
            do {
                tasks.append(try decode(W2RTask.self, from: taskURL))
            } catch {
                try writeDiagnostic(
                    DiagnosticRecord(
                        severity: .warning,
                        title: "Task konnte nicht geladen werden",
                        message: error.localizedDescription,
                        context: "FileBackedTaskStore.loadTasks",
                        details: String(describing: error),
                        filePath: taskURL.path
                    )
                )
            }
        }

        return tasks.sorted { $0.createdAt > $1.createdAt }
    }

    func loadRuns(for task: W2RTask) -> [AgentRunRecord] {
        do {
            return try loadRunsReportingDiagnostics(for: task)
        } catch {
            return []
        }
    }

    func loadRunsReportingDiagnostics(for task: W2RTask) throws -> [AgentRunRecord] {
        let root = URL(fileURLWithPath: task.rootPath, isDirectory: true)
        let entries = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        var runs: [AgentRunRecord] = []
        for entry in entries {
            let runURL = entry.appendingPathComponent("run.json")
            do {
                runs.append(try decode(AgentRunRecord.self, from: runURL))
            } catch {
                try writeDiagnostic(
                    DiagnosticRecord(
                        severity: .warning,
                        title: "Run konnte nicht geladen werden",
                        message: error.localizedDescription,
                        context: "FileBackedTaskStore.loadRuns",
                        details: String(describing: error),
                        filePath: runURL.path,
                        taskID: task.id
                    )
                )
            }
        }

        return runs.sorted { ($0.startedAt ?? .distantPast) < ($1.startedAt ?? .distantPast) }
    }

    func writeDiagnostic(_ diagnostic: DiagnosticRecord) throws {
        try ensureRoot()
        var data = try encoder.encode(diagnostic)
        data.append(Data("\n".utf8))

        if fileManager.fileExists(atPath: diagnosticsURL.path) {
            let handle = try FileHandle(forWritingTo: diagnosticsURL)
            defer {
                try? handle.close()
            }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: diagnosticsURL, options: .atomic)
        }
    }

    func loadDiagnostics() -> [DiagnosticRecord] {
        guard fileManager.fileExists(atPath: diagnosticsURL.path) else {
            return []
        }

        let content: String
        do {
            content = try String(contentsOf: diagnosticsURL, encoding: .utf8)
        } catch {
            return [
                DiagnosticRecord(
                    severity: .error,
                    title: "Diagnostics-Datei konnte nicht gelesen werden",
                    message: error.localizedDescription,
                    context: "FileBackedTaskStore.loadDiagnostics",
                    details: String(describing: error),
                    filePath: diagnosticsURL.path
                )
            ]
        }

        var records: [DiagnosticRecord] = []
        for (index, line) in content.split(whereSeparator: \.isNewline).enumerated() {
            do {
                records.append(try decoder.decode(DiagnosticRecord.self, from: Data(line.utf8)))
            } catch {
                records.append(
                    DiagnosticRecord(
                        severity: .warning,
                        title: "Diagnostics-Eintrag konnte nicht gelesen werden",
                        message: error.localizedDescription,
                        context: "FileBackedTaskStore.loadDiagnostics.line.\(index + 1)",
                        details: "Raw line:\n\(line)\n\nError:\n\(String(describing: error))",
                        filePath: diagnosticsURL.path
                    )
                )
            }
        }

        return records.sorted { $0.createdAt > $1.createdAt }
    }

    func learningSummary(for tasks: [W2RTask]) -> [LearningSummaryRow] {
        var rows: [AgentKind: LearningSummaryRow] = [:]

        for task in tasks {
            for run in loadRuns(for: task) {
                guard let feedback = parseFeedback(at: URL(fileURLWithPath: run.feedbackPath), taskID: task.id, runID: run.id, agent: run.agent) else {
                    continue
                }
                var row = rows[run.agent] ?? LearningSummaryRow(agent: run.agent, total: 0, confirmed: 0, needsWork: 0, unusable: 0, alternativeUsed: 0)
                row.total += 1
                switch feedback.verdict {
                case .confirmed: row.confirmed += 1
                case .needsWork: row.needsWork += 1
                case .unusable: row.unusable += 1
                case .alternativeUsed: row.alternativeUsed += 1
                }
                rows[run.agent] = row
            }
        }

        return rows.values.sorted { $0.agent.displayName < $1.agent.displayName }
    }

    private func parseFeedback(at url: URL, taskID: UUID, runID: UUID, agent: AgentKind) -> FeedbackRecord? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        guard let line = content.split(whereSeparator: \.isNewline).first(where: { $0.contains("- Verdict:") }) else {
            return nil
        }
        let verdictText = String(line).replacingOccurrences(of: "- Verdict:", with: "").trimmed
        guard let verdict = FeedbackVerdict.allCases.first(where: { $0.label == verdictText }) else {
            return nil
        }
        return FeedbackRecord(taskID: taskID, runID: runID, agent: agent, verdict: verdict, notes: "", createdAt: Date())
    }

    private func taskMarkdown(_ task: W2RTask) -> String {
        """
        # \(task.title)

        - ID: \(task.id.uuidString)
        - Mode: \(task.mode.label)
        - Status: \(task.status.rawValue)
        - Created: \(W2RDateFormatter.displayDateTime.string(from: task.createdAt))

        ## Repository
        \(task.repository)

        ## Description
        \(task.description)

        ## Constraints
        \(task.constraints.isEmpty ? "No constraints." : task.constraints.map { "- \($0)" }.joined(separator: "\n"))

        ## Example Repository
        \(task.exampleRepository ?? "Not provided.")
        """
    }

    private func runtimeMarkdown(_ run: AgentRunRecord) -> String {
        """
        # Runtime

        - Run ID: \(run.id.uuidString)
        - Agent: \(run.agent.displayName)
        - Status: \(run.status.label)
        - Branch: \(run.branchName)
        - Workspace: \(run.workspacePath)
        - Command: \(run.commandPath)
        - Started: \(run.startedAt.map(W2RDateFormatter.displayDateTime.string(from:)) ?? "Not started")
        - Ended: \(run.endedAt.map(W2RDateFormatter.displayDateTime.string(from:)) ?? "Still running")
        - Exit Code: \(run.exitCode.map(String.init) ?? "n/a")
        - Estimated Tokens: \(run.estimatedTokens)
        - Estimated Cost: \(run.estimatedCost.map(String.init(describing:)) ?? "Unavailable")
        - Commit: \(run.commitHash ?? "Unavailable")

        ## Last Action
        \(run.lastAction)

        ## Error
        \(run.errorSummary ?? "No error recorded.")
        """
    }

    private func encode<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }

    private func decode<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let data = try Data(contentsOf: url)
        return try decoder.decode(type, from: data)
    }
}

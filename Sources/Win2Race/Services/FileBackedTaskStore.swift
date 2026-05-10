import Foundation

final class FileBackedTaskStore {
    let rootURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let lineEncoder: JSONEncoder
    private let decoder: JSONDecoder

    init(rootURL: URL = FileBackedTaskStore.defaultRootURL, fileManager: FileManager = .default) {
        self.rootURL = rootURL
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.lineEncoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        lineEncoder.outputFormatting = [.sortedKeys]
        lineEncoder.dateEncodingStrategy = .iso8601
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

    var agentProfilesURL: URL {
        configURL.appendingPathComponent("agent-profiles.json")
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
        try removeLegacyEnvironmentKeys(["DASHSCOPE_API_KEY"], from: [.qwen])
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

    func loadAgentProfiles() -> [AgentKind: AgentProfile] {
        guard fileManager.fileExists(atPath: agentProfilesURL.path) else {
            return Dictionary(uniqueKeysWithValues: AgentKind.allCases.map { ($0, .default(for: $0)) })
        }

        do {
            let profiles = try decode([AgentProfile].self, from: agentProfilesURL)
            var result = Dictionary(uniqueKeysWithValues: profiles.map { ($0.agent, $0) })
            for agent in AgentKind.allCases where result[agent] == nil {
                result[agent] = .default(for: agent)
            }
            return result
        } catch {
            try? writeDiagnostic(
                DiagnosticRecord(
                    severity: .warning,
                    title: "Agent-Profile konnten nicht geladen werden",
                    message: error.localizedDescription,
                    context: "FileBackedTaskStore.loadAgentProfiles",
                    details: String(describing: error),
                    filePath: agentProfilesURL.path
                )
            )
            return Dictionary(uniqueKeysWithValues: AgentKind.allCases.map { ($0, .default(for: $0)) })
        }
    }

    func writeAgentProfiles(_ profiles: [AgentKind: AgentProfile]) throws {
        try ensureRoot()
        let ordered = AgentKind.allCases.map { profiles[$0] ?? .default(for: $0) }
        try encode(ordered, to: agentProfilesURL)
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

    func appendRunEvent(_ event: RunEvent, to run: AgentRunRecord) throws {
        let url = URL(fileURLWithPath: run.eventsPath ?? defaultEventsPath(for: run))
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var data = try lineEncoder.encode(event)
        data.append(Data("\n".utf8))

        if fileManager.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer {
                try? handle.close()
            }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: url, options: .atomic)
        }
    }

    func loadRunEvents(for run: AgentRunRecord) -> [RunEvent] {
        let url = URL(fileURLWithPath: run.eventsPath ?? defaultEventsPath(for: run))
        guard fileManager.fileExists(atPath: url.path),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }

        var events: [RunEvent] = []
        for (index, line) in content.split(whereSeparator: \.isNewline).enumerated() {
            do {
                events.append(try decoder.decode(RunEvent.self, from: Data(line.utf8)))
            } catch {
                try? writeDiagnostic(
                    DiagnosticRecord(
                        severity: .warning,
                        title: "Run-Event konnte nicht gelesen werden",
                        message: error.localizedDescription,
                        context: "FileBackedTaskStore.loadRunEvents.line.\(index + 1)",
                        details: "Raw line:\n\(line)\n\nError:\n\(String(describing: error))",
                        filePath: url.path,
                        taskID: run.taskID,
                        runID: run.id
                    )
                )
            }
        }

        return events.sorted { $0.sequence < $1.sequence }
    }

    func cleanupArtifacts(patterns: [String] = ["node_modules", ".next", ".turbo", ".build", "DerivedData"]) -> WorkspaceCleanupReport {
        let normalizedPatterns = Set(patterns.map(\.trimmed).filter { !$0.isEmpty && !$0.contains("/") && !$0.contains("\\") })
        guard !normalizedPatterns.isEmpty else {
            return WorkspaceCleanupReport(removedItems: 0, reclaimedBytes: 0, errors: ["Keine gültigen Artifact-Patterns konfiguriert."])
        }

        var removed = 0
        var bytes: UInt64 = 0
        var errors: [String] = []

        guard let enumerator = fileManager.enumerator(
            at: tasksURL,
            includingPropertiesForKeys: [.isDirectoryKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
            options: []
        ) else {
            return WorkspaceCleanupReport(removedItems: 0, reclaimedBytes: 0, errors: ["Tasks-Verzeichnis konnte nicht durchsucht werden: \(tasksURL.path)"])
        }

        for case let url as URL in enumerator {
            if url.lastPathComponent == ".git" {
                enumerator.skipDescendants()
                continue
            }

            guard normalizedPatterns.contains(url.lastPathComponent) else {
                continue
            }

            do {
                let size = allocatedSize(of: url)
                try fileManager.removeItem(at: url)
                removed += 1
                bytes += size
                enumerator.skipDescendants()
            } catch {
                errors.append("\(url.path): \(error.localizedDescription)")
            }
        }

        return WorkspaceCleanupReport(removedItems: removed, reclaimedBytes: bytes, errors: errors)
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
        var data = try lineEncoder.encode(diagnostic)
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
        - Events: \(run.eventsPath ?? defaultEventsPath(for: run))
        - Started: \(run.startedAt.map(W2RDateFormatter.displayDateTime.string(from:)) ?? "Not started")
        - Ended: \(run.endedAt.map(W2RDateFormatter.displayDateTime.string(from:)) ?? "Still running")
        - Last Output: \(run.lastOutputAt.map(W2RDateFormatter.displayDateTime.string(from:)) ?? "Unavailable")
        - Last Heartbeat: \(run.lastHeartbeatAt.map(W2RDateFormatter.displayDateTime.string(from:)) ?? "Unavailable")
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

    private func defaultEventsPath(for run: AgentRunRecord) -> String {
        URL(fileURLWithPath: run.runtimePath).deletingLastPathComponent().appendingPathComponent("events.jsonl").path
    }

    private func removeLegacyEnvironmentKeys(_ keys: [String], from agents: [AgentKind]) throws {
        let legacyKeys = Set(keys.map { $0.uppercased() })
        for agent in agents {
            let url = envFileURL(for: agent)
            guard fileManager.fileExists(atPath: url.path) else {
                continue
            }

            let content = try String(contentsOf: url, encoding: .utf8)
            let filteredLines = content.components(separatedBy: .newlines).filter { line in
                let uppercased = line.uppercased()
                return legacyKeys.contains { uppercased.contains($0) } == false
            }
            let filtered = filteredLines.joined(separator: "\n")
            if filtered != content {
                try filtered.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

    private func allocatedSize(of url: URL) -> UInt64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey],
            options: []
        ) else {
            return 0
        }

        var total: UInt64 = 0
        for case let item as URL in enumerator {
            let values = try? item.resourceValues(forKeys: [.isRegularFileKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey])
            total += UInt64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
        }
        return total
    }
}

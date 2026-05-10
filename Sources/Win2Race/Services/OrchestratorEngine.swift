import Foundation

@MainActor
protocol OrchestratorEngineDelegate: AnyObject {
    func orchestratorDidUpdate(_ run: AgentRunRecord)
    func orchestratorDidAppendLog(runID: UUID, line: String)
    func orchestratorDidAppendEvent(runID: UUID, event: RunEvent)
    func orchestratorDidUpdateTask(_ task: W2RTask)
    func orchestratorDidRecordDiagnostic(_ diagnostic: DiagnosticRecord)
}

@MainActor
final class OrchestratorEngine {
    weak var delegate: OrchestratorEngineDelegate?

    private let store: FileBackedTaskStore
    private var runningHandles: [UUID: RunningAgentHandle] = [:]
    private var contexts: [UUID: RunContext] = [:]
    private var expectedRunCounts: [UUID: Int] = [:]
    private var eventSequences: [UUID: Int] = [:]

    init(store: FileBackedTaskStore) {
        self.store = store
    }

    func start(task: W2RTask, installations: [CLIInstallation], secrets: [String: String], profiles: [AgentKind: AgentProfile]) {
        let ready = installations.filter { $0.isInstalled && $0.commandPath != nil }
        guard !ready.isEmpty else {
            var failedTask = task
            failedTask.status = .failed
            do {
                try store.writeTask(failedTask)
            } catch {
                recordDiagnostic(
                    severity: .error,
                    title: "Task-Status konnte nicht gespeichert werden",
                    message: error.localizedDescription,
                    context: "OrchestratorEngine.start.noReadyAgents",
                    details: String(describing: error),
                    filePath: failedTask.rootPath,
                    taskID: failedTask.id
                )
            }
            delegate?.orchestratorDidUpdateTask(failedTask)
            return
        }

        var runningTask = task
        runningTask.status = .running
        expectedRunCounts[runningTask.id] = ready.count
        do {
            try store.writeTask(runningTask)
        } catch {
            recordDiagnostic(
                severity: .error,
                title: "Task-Status konnte nicht gespeichert werden",
                message: error.localizedDescription,
                context: "OrchestratorEngine.start.runningTask",
                details: String(describing: error),
                filePath: runningTask.rootPath,
                taskID: runningTask.id
            )
        }
        delegate?.orchestratorDidUpdateTask(runningTask)

        for installation in ready {
            let profile = profiles[installation.agent] ?? .default(for: installation.agent)
            Task { @MainActor in
                await prepareAndRun(task: runningTask, installation: installation, secrets: secrets, profile: profile)
            }
        }
    }

    func answer(runID: UUID, text: String) {
        guard var context = contexts[runID] else {
            return
        }
        guard let handle = runningHandles[runID], context.run.status == .waitingForUser else {
            context.run.lastAction = "Antwort konnte nicht gesendet werden, weil der Agent nicht mehr auf Eingabe wartet."
            publish(context.run)
            return
        }
        handle.send(text)
        appendLog("[user] \(text)\n", runID: runID)
        appendEvent(.userInput, message: text, runID: runID)
        context.run.status = .running
        context.run.pendingQuestion = nil
        context.run.lastAction = "Nutzerantwort gesendet."
        publish(context.run)
    }

    func cancel(runID: UUID) {
        runningHandles[runID]?.terminate()
        runningHandles[runID] = nil
        guard var context = contexts[runID] else {
            return
        }
        context.run.status = .cancelled
        context.run.endedAt = Date()
        context.run.lastAction = "Run wurde abgebrochen."
        context.run.lastHeartbeatAt = Date()
        appendEvent(.lifecycle, message: "Run wurde durch den Nutzer abgebrochen.", runID: runID)
        publish(context.run)
        contexts[runID] = nil
        eventSequences[runID] = nil
        updateTaskStatusIfNeeded(task: context.task)
    }

    private func prepareAndRun(task: W2RTask, installation: CLIInstallation, secrets: [String: String], profile: AgentProfile) async {
        let commandPath = profile.commandPathOverride.trimmed.nilIfEmpty ?? installation.commandPath
        guard let commandPath else {
            recordDiagnostic(
                severity: .error,
                title: "Installierte CLI ohne ausführbaren Pfad",
                message: "\(installation.agent.displayName) ist als installiert markiert, hat aber keinen commandPath.",
                context: "OrchestratorEngine.prepareAndRun",
                taskID: task.id
            )
            return
        }

        let taskRoot = URL(fileURLWithPath: task.rootPath, isDirectory: true)
        let runDirectory = taskRoot.appendingPathComponent(installation.agent.rawValue, isDirectory: true)
        let workspaceURL = runDirectory.appendingPathComponent("workspace", isDirectory: true)
        let timestamp = W2RDateFormatter.branchTimestamp.string(from: Date())
        let branch = "task/\(task.slug)/\(installation.agent.rawValue)/\(timestamp)"
        let runID = UUID()

        var run = AgentRunRecord(
            id: runID,
            taskID: task.id,
            agent: installation.agent,
            status: .preparing,
            commandPath: commandPath,
            branchName: branch,
            workspacePath: workspaceURL.path,
            logPath: runDirectory.appendingPathComponent("session.log").path,
            eventsPath: runDirectory.appendingPathComponent("events.jsonl").path,
            adrPath: runDirectory.appendingPathComponent("adr.md").path,
            runtimePath: runDirectory.appendingPathComponent("runtime.md").path,
            feedbackPath: runDirectory.appendingPathComponent("feedback.md").path,
            startedAt: nil,
            endedAt: nil,
            exitCode: nil,
            estimatedTokens: 0,
            estimatedCost: nil,
            lastAction: "Run wird vorbereitet.",
            pendingQuestion: nil,
            errorSummary: nil,
            commitHash: nil,
            lastOutputAt: nil,
            lastHeartbeatAt: Date()
        )

        contexts[runID] = RunContext(task: task, installation: installation, profile: profile, run: run, runDirectory: runDirectory, workspaceURL: workspaceURL)
        eventSequences[runID] = 0
        publish(run)

        do {
            try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
            let prompt = AgentPromptFactory.prompt(for: task, agent: installation.agent)
            try prompt.write(to: runDirectory.appendingPathComponent("prompt.md"), atomically: true, encoding: .utf8)
            appendLog("[w2r] Preparing \(installation.agent.displayName) in \(workspaceURL.path)\n", runID: runID)
            appendEvent(.lifecycle, message: "Run vorbereitet in \(workspaceURL.path).", runID: runID)

            let clone = await ProcessRunner.run(
                executable: "/usr/bin/git",
                arguments: ["clone", task.repository, workspaceURL.path],
                environment: gitEnvironment(for: profile),
                timeout: 1_200
            )
            appendProcessResult("git clone", clone, runID: runID)
            guard clone.succeeded else {
                fail(runID: runID, summary: "Repository konnte nicht geklont werden.")
                return
            }

            await configureGitAuthIfNeeded(profile: profile, workspaceURL: workspaceURL, runID: runID)

            let checkout = await ProcessRunner.run(
                executable: "/usr/bin/git",
                arguments: ["checkout", "-b", branch],
                currentDirectory: workspaceURL,
                timeout: 120
            )
            appendProcessResult("git checkout", checkout, runID: runID)
            guard checkout.succeeded else {
                fail(runID: runID, summary: "Branch konnte nicht erstellt werden.")
                return
            }

            let profileURL: URL?
            do {
                profileURL = try SandboxProfileBuilder.writeProfile(workspaceURL: workspaceURL, runDirectoryURL: runDirectory)
            } catch {
                profileURL = nil
                recordDiagnostic(
                    severity: .warning,
                    title: "Sandbox-Profil konnte nicht geschrieben werden",
                    message: error.localizedDescription,
                    context: "OrchestratorEngine.prepareAndRun.sandboxProfile",
                    details: String(describing: error),
                    filePath: runDirectory.appendingPathComponent("sandbox.sb").path,
                    taskID: task.id,
                    runID: runID
                )
            }
            let extraArguments: [String]
            do {
                extraArguments = try ShellWords.split(profile.extraArguments)
            } catch {
                recordDiagnostic(
                    severity: .error,
                    title: "\(installation.agent.displayName)-Extra-Argumente sind ungültig",
                    message: error.localizedDescription,
                    context: "OrchestratorEngine.prepareAndRun.extraArguments",
                    details: profile.extraArguments,
                    taskID: task.id,
                    runID: runID
                )
                fail(runID: runID, summary: "\(installation.agent.displayName)-Extra-Argumente sind ungültig: \(error.localizedDescription)")
                return
            }
            let agentArguments = installation.agent.defaultArguments(prompt: prompt, modelOverride: profile.modelOverride) + extraArguments
            let wrapped = SandboxProfileBuilder.wrapIfAvailable(executable: commandPath, arguments: agentArguments, profileURL: profileURL)
            appendLog("[w2r] \(wrapped.2)\n", runID: runID)
            appendLog("[w2r] Starting command: \(wrapped.0) \(wrapped.1.joined(separator: " "))\n", runID: runID)
            appendEvent(.process, message: "Starting command: \(wrapped.0) \(wrapped.1.joined(separator: " "))", runID: runID)

            var environment = secrets
            environment.merge(agentEnvironment(task: task, run: run, profile: profile)) { _, new in new }
            let envFile = store.envFileURL(for: installation.agent)
            do {
                environment.merge(try EnvironmentFileLoader.load(url: envFile)) { _, new in new }
            } catch {
                recordDiagnostic(
                    severity: .error,
                    title: "\(installation.agent.displayName)-ENV konnte nicht geladen werden",
                    message: error.localizedDescription,
                    context: "OrchestratorEngine.prepareAndRun.environment",
                    details: String(describing: error),
                    filePath: envFile.path,
                    taskID: task.id,
                    runID: runID
                )
                fail(runID: runID, summary: "\(installation.agent.displayName)-ENV konnte nicht geladen werden: \(error.localizedDescription)")
                return
            }

            run.status = .running
            run.startedAt = Date()
            run.lastHeartbeatAt = Date()
            run.lastAction = "CLI gestartet."
            publish(run)
            appendEvent(.heartbeat, message: "CLI gestartet.", runID: runID)
            scheduleTimeout(runID: runID, seconds: profile.timeoutSeconds)

            _ = try AgentRuntime.start(
                runID: runID,
                executable: wrapped.0,
                arguments: wrapped.1,
                currentDirectory: workspaceURL,
                environment: environment,
                onStarted: { [weak self] handle in
                    self?.runningHandles[runID] = handle
                },
                onOutput: { [weak self] text, isError in
                    self?.handleOutput(text, isError: isError, runID: runID)
                },
                onExit: { [weak self] exitCode in
                    Task { @MainActor in
                        await self?.complete(runID: runID, exitCode: exitCode)
                    }
                }
            )
        } catch {
            runningHandles[runID] = nil
            fail(runID: runID, summary: error.localizedDescription)
        }
    }

    private func handleOutput(_ text: String, isError: Bool, runID: UUID) {
        let prefix = isError ? "[stderr] " : ""
        appendLog(prefix + text, runID: runID)
        appendEvent(isError ? .stderr : .stdout, message: text, isError: isError, runID: runID)

        guard var context = contexts[runID] else {
            return
        }

        context.run.estimatedTokens += max(1, text.count / 4)
        context.run.lastOutputAt = Date()
        context.run.lastHeartbeatAt = Date()
        if let question = QuestionDetector.question(in: text) {
            context.run.status = .waitingForUser
            context.run.pendingQuestion = question
            context.run.lastAction = "Agent wartet auf Nutzerantwort."
            appendEvent(.question, message: question, runID: runID)
        } else {
            context.run.lastAction = text.components(separatedBy: .newlines).last(where: { !$0.trimmed.isEmpty })?.trimmed ?? context.run.lastAction
        }

        publish(context.run)
    }

    private func complete(runID: UUID, exitCode: Int32) async {
        runningHandles[runID] = nil
        guard var context = contexts[runID] else {
            return
        }

        if context.run.status == .cancelled {
            contexts[runID] = nil
            eventSequences[runID] = nil
            updateTaskStatusIfNeeded(task: context.task)
            return
        }

        appendLog("[w2r] Process exited with code \(exitCode).\n", runID: runID)
        appendEvent(.lifecycle, message: "Process exited with code \(exitCode).", isError: exitCode != 0, runID: runID)
        let diffStat = await ProcessRunner.run(
            executable: "/usr/bin/git",
            arguments: ["diff", "--stat"],
            currentDirectory: context.workspaceURL,
            timeout: 120
        ).stdout

        var validation = "Exit code: \(exitCode)"
        var commitHash: String?

        if exitCode == 0 {
            let commitResult = await commitChanges(context: context)
            validation += "\n\(commitResult.validation)"
            commitHash = commitResult.commitHash
        }

        context.run.status = exitCode == 0 ? .succeeded : .failed
        context.run.exitCode = exitCode
        context.run.endedAt = Date()
        context.run.lastHeartbeatAt = Date()
        context.run.commitHash = commitHash
        context.run.lastAction = exitCode == 0 ? "Run abgeschlossen." : "Run fehlgeschlagen."
        if exitCode != 0 {
            context.run.errorSummary = "CLI beendete sich mit Exit-Code \(exitCode)."
            recordDiagnostic(
                severity: .error,
                title: "\(context.run.agent.displayName)-Run fehlgeschlagen",
                message: context.run.errorSummary ?? "CLI beendete sich mit Exit-Code \(exitCode).",
                context: "OrchestratorEngine.complete",
                details: "Branch: \(context.run.branchName)\nWorkspace: \(context.run.workspacePath)\nLog: \(context.run.logPath)",
                filePath: context.run.logPath,
                taskID: context.task.id,
                runID: context.run.id
            )
        }

        do {
            try store.writeADR(for: context.task, run: context.run, diffStat: diffStat, validation: validation)
        } catch {
            recordDiagnostic(
                severity: .error,
                title: "ADR konnte nicht geschrieben werden",
                message: error.localizedDescription,
                context: "OrchestratorEngine.complete.writeADR",
                details: String(describing: error),
                filePath: context.run.adrPath,
                taskID: context.task.id,
                runID: context.run.id
            )
        }

        do {
            try writeResult(context: context, diffStat: diffStat, validation: validation)
        } catch {
            recordDiagnostic(
                severity: .error,
                title: "Result-Datei konnte nicht geschrieben werden",
                message: error.localizedDescription,
                context: "OrchestratorEngine.complete.writeResult",
                details: String(describing: error),
                filePath: context.run.runDirectoryResultURL.path,
                taskID: context.task.id,
                runID: context.run.id
            )
        }
        publish(context.run)
        contexts[runID] = nil
        eventSequences[runID] = nil

        updateTaskStatusIfNeeded(task: context.task)
    }

    private func commitChanges(context: RunContext) async -> (validation: String, commitHash: String?) {
        let status = await ProcessRunner.run(
            executable: "/usr/bin/git",
            arguments: ["status", "--porcelain"],
            currentDirectory: context.workspaceURL,
            timeout: 120
        )
        guard status.succeeded else {
            appendProcessResult("git status", status, runID: context.run.id)
            return ("git status failed; changes were not committed.", nil)
        }

        guard !status.stdout.trimmed.isEmpty else {
            return ("No file changes detected; nothing committed.", nil)
        }

        let add = await ProcessRunner.run(
            executable: "/usr/bin/git",
            arguments: ["add", "-A"],
            currentDirectory: context.workspaceURL,
            timeout: 120
        )
        appendProcessResult("git add", add, runID: context.run.id)
        guard add.succeeded else {
            return ("git add failed; changes were not committed.", nil)
        }

        let commit = await ProcessRunner.run(
            executable: "/usr/bin/git",
            arguments: [
                "-c", "user.name=\(context.profile.gitUserName.trimmed.nilIfEmpty ?? "Win2Race")",
                "-c", "user.email=\(context.profile.gitUserEmail.trimmed.nilIfEmpty ?? "win2race@local")",
                "commit",
                "-m", "W2R: \(context.task.title) by \(context.installation.agent.displayName)"
            ],
            currentDirectory: context.workspaceURL,
            timeout: 120
        )
        appendProcessResult("git commit", commit, runID: context.run.id)
        guard commit.succeeded else {
            return ("git commit failed; changes remain in workspace.", nil)
        }

        let rev = await ProcessRunner.run(
            executable: "/usr/bin/git",
            arguments: ["rev-parse", "--short", "HEAD"],
            currentDirectory: context.workspaceURL,
            timeout: 120
        )
        let hash = rev.stdout.trimmed.nilIfEmpty
        let suffix = hash.map { " as \($0)." } ?? "."
        return ("Changes committed\(suffix)", hash)
    }

    private func fail(runID: UUID, summary: String) {
        guard var context = contexts[runID] else {
            return
        }
        appendLog("[w2r] ERROR: \(summary)\n", runID: runID)
        context.run.status = .failed
        context.run.endedAt = Date()
        context.run.lastHeartbeatAt = Date()
        context.run.errorSummary = summary
        context.run.lastAction = summary
        appendEvent(.error, message: summary, isError: true, runID: runID)
        recordDiagnostic(
            severity: .error,
            title: "\(context.run.agent.displayName)-Run fehlgeschlagen",
            message: summary,
            context: "OrchestratorEngine.fail",
            details: "Branch: \(context.run.branchName)\nWorkspace: \(context.run.workspacePath)\nLog: \(context.run.logPath)",
            filePath: context.run.logPath,
            taskID: context.task.id,
            runID: context.run.id
        )
        publish(context.run)
        contexts[runID] = nil
        eventSequences[runID] = nil
        updateTaskStatusIfNeeded(task: context.task)
    }

    private func appendProcessResult(_ label: String, _ result: ProcessResult, runID: UUID) {
        appendLog("[w2r] \(label) exited \(result.exitCode) in \(String(format: "%.1f", result.duration))s\n", runID: runID)
        appendEvent(label.hasPrefix("git ") ? .git : .process, message: "\(label) exited \(result.exitCode) in \(String(format: "%.1f", result.duration))s", isError: result.exitCode != 0, runID: runID)
        if !result.stdout.trimmed.isEmpty {
            appendLog(result.stdout + "\n", runID: runID)
        }
        if !result.stderr.trimmed.isEmpty {
            appendLog("[stderr] \(result.stderr)\n", runID: runID)
        }
    }

    private func appendLog(_ text: String, runID: UUID) {
        guard let context = contexts[runID] else {
            recordDiagnostic(
                severity: .warning,
                title: "Log-Zeile ohne Run-Kontext empfangen",
                message: "Eine Log-Zeile konnte keinem aktiven Run-Kontext zugeordnet werden.",
                context: "OrchestratorEngine.appendLog",
                details: text,
                runID: runID
            )
            return
        }
        do {
            try store.appendLog(text, to: context.run)
        } catch {
            recordDiagnostic(
                severity: .error,
                title: "Session-Log konnte nicht geschrieben werden",
                message: error.localizedDescription,
                context: "OrchestratorEngine.appendLog",
                details: String(describing: error),
                filePath: context.run.logPath,
                taskID: context.task.id,
                runID: context.run.id
            )
        }
        delegate?.orchestratorDidAppendLog(runID: runID, line: text)
    }

    private func appendEvent(_ type: RunEventType, message: String, isError: Bool = false, runID: UUID) {
        guard let context = contexts[runID] else {
            return
        }
        let sequence = (eventSequences[runID] ?? 0) + 1
        eventSequences[runID] = sequence
        let event = RunEvent(
            id: UUID(),
            runID: runID,
            taskID: context.task.id,
            agent: context.run.agent,
            sequence: sequence,
            type: type,
            createdAt: Date(),
            message: message,
            isError: isError
        )
        do {
            try store.appendRunEvent(event, to: context.run)
        } catch {
            recordDiagnostic(
                severity: .error,
                title: "Run-Event konnte nicht geschrieben werden",
                message: error.localizedDescription,
                context: "OrchestratorEngine.appendEvent",
                details: String(describing: error),
                filePath: context.run.eventsPath,
                taskID: context.task.id,
                runID: context.run.id
            )
        }
        delegate?.orchestratorDidAppendEvent(runID: runID, event: event)
    }

    private func publish(_ run: AgentRunRecord) {
        if var context = contexts[run.id] {
            context.run = run
            contexts[run.id] = context
        }
        do {
            try store.writeRun(run)
        } catch {
            recordDiagnostic(
                severity: .error,
                title: "Run-Runtime konnte nicht gespeichert werden",
                message: error.localizedDescription,
                context: "OrchestratorEngine.publish",
                details: String(describing: error),
                filePath: run.runtimePath,
                taskID: run.taskID,
                runID: run.id
            )
        }
        delegate?.orchestratorDidUpdate(run)
    }

    private func updateTaskStatusIfNeeded(task: W2RTask) {
        let runs = store.loadRuns(for: task)
        let expected = expectedRunCounts[task.id] ?? runs.count
        guard runs.count >= expected, !runs.isEmpty, runs.allSatisfy({ $0.status.isTerminal }) else {
            return
        }
        var updated = task
        updated.status = runs.contains(where: { $0.status == .succeeded }) ? .completed : .failed
        do {
            try store.writeTask(updated)
        } catch {
            recordDiagnostic(
                severity: .error,
                title: "Finaler Task-Status konnte nicht gespeichert werden",
                message: error.localizedDescription,
                context: "OrchestratorEngine.updateTaskStatusIfNeeded",
                details: String(describing: error),
                filePath: updated.rootPath,
                taskID: updated.id
            )
        }
        delegate?.orchestratorDidUpdateTask(updated)
        expectedRunCounts[task.id] = nil
    }

    private func writeResult(context: RunContext, diffStat: String, validation: String) throws {
        let resultURL = context.run.runDirectoryResultURL
        let content = """
        # Result

        - Agent: \(context.run.agent.displayName)
        - Branch: \(context.run.branchName)
        - Workspace: \(context.run.workspacePath)
        - Status: \(context.run.status.label)
        - Commit: \(context.run.commitHash ?? "Unavailable")

        ## Validation
        \(validation)

        ## Diff Stat
        ```text
        \(diffStat.trimmed.isEmpty ? "No diff stat available." : diffStat.trimmed)
        ```

        ## Next Human Step
        Review the branch, inspect the generated diff, run product-specific validation, and record feedback in Win-to-Race.
        """
        try content.write(to: resultURL, atomically: true, encoding: .utf8)
    }

    private func configureGitAuthIfNeeded(profile: AgentProfile, workspaceURL: URL, runID: UUID) async {
        guard let sshCommand = sshCommand(for: profile) else {
            return
        }
        let config = await ProcessRunner.run(
            executable: "/usr/bin/git",
            arguments: ["config", "core.sshCommand", sshCommand],
            currentDirectory: workspaceURL,
            timeout: 120
        )
        appendProcessResult("git config core.sshCommand", config, runID: runID)
    }

    private func gitEnvironment(for profile: AgentProfile) -> [String: String] {
        guard let sshCommand = sshCommand(for: profile) else {
            return [:]
        }
        return ["GIT_SSH_COMMAND": sshCommand]
    }

    private func sshCommand(for profile: AgentProfile) -> String? {
        guard let keyPath = profile.sshIdentityPath.trimmed.nilIfEmpty else {
            return nil
        }
        return "ssh -i \(ShellWords.quote(keyPath)) -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
    }

    private func agentEnvironment(task: W2RTask, run: AgentRunRecord, profile: AgentProfile) -> [String: String] {
        var environment = [
            "W2R_TASK_ID": task.id.uuidString,
            "W2R_RUN_ID": run.id.uuidString,
            "W2R_AGENT_NAME": run.agent.rawValue,
            "AGENT_NAME": run.agent.rawValue,
            "W2R_WORKSPACE_PATH": run.workspacePath
        ]
        if let model = profile.modelOverride.trimmed.nilIfEmpty {
            environment["W2R_MODEL"] = model
        }
        return environment
    }

    private func scheduleTimeout(runID: UUID, seconds: Int) {
        guard seconds > 0 else {
            return
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
            guard let context = contexts[runID], context.run.status.isTerminal == false else {
                return
            }
            appendLog("[w2r] ERROR: Agent timeout after \(seconds) seconds.\n", runID: runID)
            appendEvent(.error, message: "Agent timeout after \(seconds) seconds.", isError: true, runID: runID)
            runningHandles[runID]?.terminate()
        }
    }

    private func recordDiagnostic(
        severity: DiagnosticSeverity,
        title: String,
        message: String,
        context: String,
        details: String = "",
        filePath: String? = nil,
        taskID: UUID? = nil,
        runID: UUID? = nil
    ) {
        var diagnostic = DiagnosticRecord(
            severity: severity,
            title: title,
            message: message,
            context: context,
            details: details,
            filePath: filePath,
            taskID: taskID,
            runID: runID
        )

        do {
            try store.writeDiagnostic(diagnostic)
        } catch {
            diagnostic.details = [
                diagnostic.details,
                "Diagnostic persistence failed: \(error.localizedDescription)",
                String(describing: error)
            ]
            .filter { !$0.trimmed.isEmpty }
            .joined(separator: "\n\n")
        }

        delegate?.orchestratorDidRecordDiagnostic(diagnostic)
    }
}

private struct RunContext {
    var task: W2RTask
    var installation: CLIInstallation
    var profile: AgentProfile
    var run: AgentRunRecord
    var runDirectory: URL
    var workspaceURL: URL
}

private extension AgentRunRecord {
    var runDirectoryResultURL: URL {
        URL(fileURLWithPath: runtimePath).deletingLastPathComponent().appendingPathComponent("result.md")
    }
}

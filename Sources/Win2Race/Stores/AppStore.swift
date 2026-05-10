import AppKit
import Combine
import Foundation

enum AppSection: String, CaseIterable, Identifiable {
    case dashboard
    case simple
    case advanced
    case setup
    case learning
    case diagnostics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Runs"
        case .simple: "Simple"
        case .advanced: "Advanced"
        case .setup: "Setup"
        case .learning: "Learning"
        case .diagnostics: "Diagnostics"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: "rectangle.3.group"
        case .simple: "play.circle"
        case .advanced: "tray.full"
        case .setup: "gearshape"
        case .learning: "chart.bar"
        case .diagnostics: "exclamationmark.bubble"
        }
    }
}

@MainActor
final class AppStore: ObservableObject, OrchestratorEngineDelegate {
    @Published var selectedSection: AppSection = .simple
    @Published var tasks: [W2RTask] = []
    @Published var runsByTaskID: [UUID: [AgentRunRecord]] = [:]
    @Published var logsByRunID: [UUID: [String]] = [:]
    @Published var runEventsByRunID: [UUID: [RunEvent]] = [:]
    @Published var installations: [CLIInstallation] = []
    @Published var runtimeRecords: [RuntimeRecord] = []
    @Published var agentProfiles: [AgentKind: AgentProfile] = [:]
    @Published var providerSecretStates: [ProviderSecretState] = []
    @Published var learningRows: [LearningSummaryRow] = []
    @Published var draft = TaskDraft()
    @Published var parsedAdvancedTasks: [ParsedTaskFile] = []
    @Published var selectedTaskID: UUID?
    @Published var selectedRunID: UUID?
    @Published var statusMessage: String = "Bereit."
    @Published var advancedFolderPath: String = ""
    @Published var secretDrafts: [String: String] = [:]
    @Published var tokenTestResults: [String: ProviderTokenTestResult] = [:]
    @Published var tokenTestsInFlight: Set<String> = []
    @Published var envDrafts: [AgentKind: String] = [:]
    @Published var envValidationMessages: [AgentKind: [String]] = [:]
    @Published var feedbackNotes: [UUID: String] = [:]
    @Published var feedbackVerdicts: [UUID: FeedbackVerdict] = [:]
    @Published var diagnostics: [DiagnosticRecord] = []

    let fileStore: FileBackedTaskStore
    private let orchestrator: OrchestratorEngine

    init(fileStore: FileBackedTaskStore = FileBackedTaskStore()) {
        self.fileStore = fileStore
        self.orchestrator = OrchestratorEngine(store: fileStore)
        self.orchestrator.delegate = self
    }

    func bootstrap() async {
        do {
            try fileStore.ensureRoot()
            tasks = []
            runsByTaskID = [:]
            logsByRunID = [:]
            runEventsByRunID = [:]
            agentProfiles = fileStore.loadAgentProfiles()
            tasks = try fileStore.loadTasksReportingDiagnostics()
            for task in tasks {
                let runs = try fileStore.loadRunsReportingDiagnostics(for: task)
                runsByTaskID[task.id] = runs
                for run in runs {
                    logsByRunID[run.id] = loadLog(run: run)
                    runEventsByRunID[run.id] = fileStore.loadRunEvents(for: run)
                }
            }
            selectedTaskID = tasks.first?.id
            selectedRunID = selectedTask.flatMap { runsByTaskID[$0.id]?.first?.id }
            refreshSetupState()
            refreshLearning()
            statusMessage = "Workspace: \(fileStore.rootURL.path)"
        } catch {
            recordDiagnostic(
                severity: .error,
                title: "App-Setup fehlgeschlagen",
                message: error.localizedDescription,
                context: "AppStore.bootstrap",
                details: String(describing: error)
            )
            statusMessage = "Setup fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    var selectedTask: W2RTask? {
        guard let selectedTaskID else {
            return nil
        }
        return tasks.first(where: { $0.id == selectedTaskID })
    }

    var selectedRuns: [AgentRunRecord] {
        guard let selectedTaskID else {
            return []
        }
        return runsByTaskID[selectedTaskID] ?? []
    }

    var selectedRun: AgentRunRecord? {
        guard let selectedRunID else {
            return selectedRuns.first
        }
        return selectedRuns.first(where: { $0.id == selectedRunID }) ?? selectedRuns.first
    }

    var installedInstallations: [CLIInstallation] {
        installations
            .map(resolvedInstallation)
            .filter { $0.isInstalled && $0.commandPath != nil }
    }

    var startButtonTitle: String {
        let count = autoSelectedInstallations().count
        return count == 1 ? "1 Agent starten" : "\(count) Agenten starten"
    }

    func refreshTooling() {
        installations = CLIDetector.detect()
        refreshRuntimeRecords()
    }

    func refreshSetupState() {
        refreshTooling()
        refreshSecretStates()
        reloadEnvironmentDrafts()
        diagnostics = fileStore.loadDiagnostics()
        refreshRuntimeRecords()
        statusMessage = "Setup neu geprüft."
    }

    func refreshRuntimeRecords() {
        runtimeRecords = RuntimeRegistry.records(installations: installations, profiles: agentProfiles)
    }

    func refreshSecretStates() {
        let keys = Array(Set(AgentKind.allCases.flatMap(\.requiredEnvironmentKeys))).sorted()
        providerSecretStates = keys.map { key in
            ProviderSecretState(key: key, provider: providerName(for: key), isPresent: KeychainService.read(account: key) != nil)
        }
    }

    func saveSecret(key: String) {
        let value = secretDrafts[key, default: ""].trimmed
        guard !value.isEmpty else {
            statusMessage = "\(key): Wert einfügen, dann speichern."
            return
        }

        do {
            try KeychainService.save(value, account: key)
            secretDrafts[key] = ""
            tokenTestResults.removeValue(forKey: key)
            refreshSecretStates()
            statusMessage = "\(key) gespeichert. Jetzt mit „Test“ Auth und Budget prüfen."
        } catch {
            recordDiagnostic(
                severity: .error,
                title: "API-Key konnte nicht gespeichert werden",
                message: error.localizedDescription,
                context: "AppStore.saveSecret",
                details: String(describing: error)
            )
            statusMessage = "\(key) konnte nicht gespeichert werden: \(error.localizedDescription)"
        }
    }

    func testSecret(key: String, provider: String) {
        guard tokenTestsInFlight.contains(key) == false else {
            statusMessage = "\(key) wird bereits getestet."
            return
        }

        guard let token = KeychainService.read(account: key), !token.trimmed.isEmpty else {
            let result = ProviderTokenTestResult(
                key: key,
                provider: provider,
                checkedAt: Date(),
                succeeded: false,
                budgetLikelyAvailable: false,
                statusCode: nil,
                summary: "\(key) ist noch nicht gespeichert.",
                details: "Speichere zuerst den Key im macOS Keychain und starte danach den Test."
            )
            tokenTestResults[key] = result
            statusMessage = result.summary
            return
        }

        tokenTestsInFlight.insert(key)
        statusMessage = "Teste \(provider)-Key \(key) ..."

        Task {
            let result = await ProviderTokenTester.test(key: key, provider: provider, token: token)
            await MainActor.run {
                tokenTestsInFlight.remove(key)
                guard KeychainService.read(account: key) == token else {
                    statusMessage = "\(key) wurde während des Tests geändert; altes Testergebnis verworfen."
                    return
                }
                tokenTestResults[key] = result
                statusMessage = result.summary
                if !result.succeeded || !result.budgetLikelyAvailable {
                    recordDiagnostic(
                        severity: result.succeeded ? .warning : .error,
                        title: "\(provider)-Key-Test nicht grün",
                        message: result.summary,
                        context: "AppStore.testSecret",
                        details: result.copyText
                    )
                }
            }
        }
    }

    func reloadEnvironmentDrafts() {
        for agent in AgentKind.allCases {
            reloadEnvironmentDraft(for: agent, updateStatus: false)
        }
    }

    func reloadEnvironmentDraft(for agent: AgentKind, updateStatus: Bool = true) {
        do {
            let content = try fileStore.readEnvFile(for: agent)
            envDrafts[agent] = content
            envValidationMessages[agent] = EnvironmentFileValidator.validationMessages(for: content)
            if updateStatus {
                statusMessage = "\(agent.displayName)-ENV neu geladen."
            }
        } catch {
            envDrafts[agent] = fileStore.envTemplate(for: agent)
            envValidationMessages[agent] = []
            recordDiagnostic(
                severity: .warning,
                title: "\(agent.displayName)-ENV konnte nicht geladen werden",
                message: error.localizedDescription,
                context: "AppStore.reloadEnvironmentDraft",
                details: String(describing: error),
                filePath: fileStore.envFileURL(for: agent).path
            )
            if updateStatus {
                statusMessage = "\(agent.displayName)-ENV konnte nicht geladen werden: \(error.localizedDescription)"
            }
        }
    }

    func updateEnvironmentDraft(for agent: AgentKind, content: String) {
        envDrafts[agent] = content
        envValidationMessages[agent] = EnvironmentFileValidator.validationMessages(for: content)
    }

    func saveEnvironmentDraft(for agent: AgentKind) {
        let content = envDrafts[agent, default: fileStore.envTemplate(for: agent)]
        let messages = EnvironmentFileValidator.validationMessages(for: content)
        envValidationMessages[agent] = messages

        guard messages.isEmpty else {
            statusMessage = "\(agent.displayName)-ENV hat Syntaxfehler. Korrigiere die markierten Zeilen."
            return
        }

        do {
            try fileStore.writeEnvFile(content, for: agent)
            statusMessage = "\(agent.displayName)-ENV gespeichert."
        } catch {
            recordDiagnostic(
                severity: .error,
                title: "\(agent.displayName)-ENV konnte nicht gespeichert werden",
                message: error.localizedDescription,
                context: "AppStore.saveEnvironmentDraft",
                details: String(describing: error),
                filePath: fileStore.envFileURL(for: agent).path
            )
            statusMessage = "\(agent.displayName)-ENV konnte nicht gespeichert werden: \(error.localizedDescription)"
        }
    }

    func resetEnvironmentDraft(for agent: AgentKind) {
        let template = fileStore.envTemplate(for: agent)
        envDrafts[agent] = template
        envValidationMessages[agent] = EnvironmentFileValidator.validationMessages(for: template)
        saveEnvironmentDraft(for: agent)
    }

    func startSimpleTask() {
        guard draft.isStartable else {
            statusMessage = "Repository, Titel und Beschreibung sind erforderlich."
            return
        }

        let selected = autoSelectedInstallations()
        guard !selected.isEmpty else {
            statusMessage = "Keine unterstützte Coding-CLI gefunden. Öffne Setup und installiere mindestens eine CLI."
            selectedSection = .setup
            return
        }

        do {
            let task = try fileStore.createTask(from: draft, mode: .simple)
            tasks.insert(task, at: 0)
            selectedTaskID = task.id
            selectedRunID = nil
            selectedSection = .dashboard
            statusMessage = "Starte \(selected.count) Agenten für \(task.title)."
            orchestrator.start(task: task, installations: selected, secrets: secretValues(), profiles: agentProfiles)
            draft = TaskDraft()
        } catch {
            recordDiagnostic(
                severity: .error,
                title: "Task konnte nicht erstellt werden",
                message: error.localizedDescription,
                context: "AppStore.startSimpleTask",
                details: String(describing: error)
            )
            statusMessage = "Task konnte nicht erstellt werden: \(error.localizedDescription)"
        }
    }

    func importAdvancedFolder(_ url: URL) {
        advancedFolderPath = url.path
        let fileManager = FileManager.default
        let files: [URL]
        do {
            files = try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        } catch {
            recordDiagnostic(
                severity: .error,
                title: "Advanced-Ordner konnte nicht gelesen werden",
                message: error.localizedDescription,
                context: "AppStore.importAdvancedFolder",
                details: String(describing: error),
                filePath: url.path
            )
            statusMessage = "Ordner konnte nicht gelesen werden."
            return
        }

        var parsed: [ParsedTaskFile] = []
        var failures = 0
        for file in files where file.pathExtension.lowercased() == "md" {
            do {
                let content = try String(contentsOf: file, encoding: .utf8)
                parsed.append(try MarkdownTaskParser.parse(contents: content, sourceURL: file))
            } catch {
                failures += 1
                recordDiagnostic(
                    severity: .warning,
                    title: "Advanced-Task konnte nicht importiert werden",
                    message: error.localizedDescription,
                    context: "AppStore.importAdvancedFolder",
                    details: String(describing: error),
                    filePath: file.path
                )
            }
        }

        parsedAdvancedTasks = parsed
        statusMessage = failures == 0
            ? "\(parsedAdvancedTasks.count) Markdown-Aufgaben importiert."
            : "\(parsedAdvancedTasks.count) Markdown-Aufgaben importiert, \(failures) Fehler in Diagnostics."
    }

    func startAdvancedTask(_ parsed: ParsedTaskFile) {
        let selected = autoSelectedInstallations()
        guard !selected.isEmpty else {
            statusMessage = "Keine unterstützte Coding-CLI gefunden."
            selectedSection = .setup
            return
        }

        do {
            let task = try fileStore.createTask(from: parsed.draft, mode: .advanced)
            tasks.insert(task, at: 0)
            selectedTaskID = task.id
            selectedRunID = nil
            selectedSection = .dashboard
            statusMessage = "Advanced-Task gestartet: \(task.title)"
            orchestrator.start(task: task, installations: selected, secrets: secretValues(), profiles: agentProfiles)
        } catch {
            recordDiagnostic(
                severity: .error,
                title: "Advanced-Task konnte nicht gestartet werden",
                message: error.localizedDescription,
                context: "AppStore.startAdvancedTask",
                details: String(describing: error),
                filePath: parsed.sourceURL.path
            )
            statusMessage = "Advanced-Task konnte nicht gestartet werden: \(error.localizedDescription)"
        }
    }

    func answerSelectedRun(_ text: String) {
        guard let selectedRunID, !text.trimmed.isEmpty else {
            return
        }
        orchestrator.answer(runID: selectedRunID, text: text)
    }

    func cancel(run: AgentRunRecord) {
        orchestrator.cancel(runID: run.id)
    }

    func profile(for agent: AgentKind) -> AgentProfile {
        agentProfiles[agent] ?? .default(for: agent)
    }

    func updateAgentProfile(for agent: AgentKind, mutate: (inout AgentProfile) -> Void) {
        var profile = self.profile(for: agent)
        mutate(&profile)
        agentProfiles[agent] = profile
        refreshRuntimeRecords()
    }

    func saveAgentProfiles() {
        do {
            try fileStore.writeAgentProfiles(agentProfiles)
            refreshRuntimeRecords()
            statusMessage = "Agent-Profile gespeichert."
        } catch {
            recordDiagnostic(
                severity: .error,
                title: "Agent-Profile konnten nicht gespeichert werden",
                message: error.localizedDescription,
                context: "AppStore.saveAgentProfiles",
                details: String(describing: error),
                filePath: fileStore.agentProfilesURL.path
            )
            statusMessage = "Agent-Profile konnten nicht gespeichert werden: \(error.localizedDescription)"
        }
    }

    func resetAgentProfile(for agent: AgentKind) {
        agentProfiles[agent] = .default(for: agent)
        saveAgentProfiles()
    }

    func cleanupWorkspaceArtifacts() {
        let activeRuns = runsByTaskID.values.flatMap { $0 }.filter { !$0.status.isTerminal }
        guard activeRuns.isEmpty else {
            statusMessage = "Cleanup blockiert: \(activeRuns.count) Agent-Run\(activeRuns.count == 1 ? "" : "s") laufen noch."
            return
        }

        let report = fileStore.cleanupArtifacts()
        statusMessage = report.summary
        if !report.errors.isEmpty {
            recordDiagnostic(
                severity: .warning,
                title: "Workspace-Cleanup teilweise fehlgeschlagen",
                message: report.summary,
                context: "AppStore.cleanupWorkspaceArtifacts",
                details: report.errors.joined(separator: "\n"),
                filePath: fileStore.tasksURL.path
            )
        }
    }

    func recordFeedback(run: AgentRunRecord) {
        let verdict = feedbackVerdicts[run.id] ?? .confirmed
        let feedback = FeedbackRecord(
            taskID: run.taskID,
            runID: run.id,
            agent: run.agent,
            verdict: verdict,
            notes: feedbackNotes[run.id, default: ""],
            createdAt: Date()
        )

        do {
            try fileStore.writeFeedback(feedback, run: run)
            refreshLearning()
            statusMessage = "Feedback für \(run.agent.displayName) gespeichert."
        } catch {
            recordDiagnostic(
                severity: .error,
                title: "Feedback konnte nicht gespeichert werden",
                message: error.localizedDescription,
                context: "AppStore.recordFeedback",
                details: String(describing: error),
                filePath: run.feedbackPath,
                taskID: run.taskID,
                runID: run.id
            )
            statusMessage = "Feedback konnte nicht gespeichert werden: \(error.localizedDescription)"
        }
    }

    func reveal(path: String) {
        let url = URL(fileURLWithPath: path)
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            statusMessage = "Im Finder geöffnet: \(url.lastPathComponent)"
            return
        }

        let parent = url.deletingLastPathComponent()
        if fileManager.fileExists(atPath: parent.path) {
            NSWorkspace.shared.open(parent)
            recordDiagnostic(
                severity: .warning,
                title: "Pfad existiert noch nicht",
                message: "Der angeforderte Pfad existiert noch nicht. Der übergeordnete Ordner wurde geöffnet.",
                context: "AppStore.reveal",
                details: "Missing path:\n\(url.path)",
                filePath: url.path
            )
            statusMessage = "Pfad existiert noch nicht: \(url.path)"
            return
        }

        recordDiagnostic(
            severity: .error,
            title: "Pfad kann nicht geöffnet werden",
            message: "Weder der angeforderte Pfad noch der übergeordnete Ordner existieren.",
            context: "AppStore.reveal",
            details: "Missing path:\n\(url.path)\n\nMissing parent:\n\(parent.path)",
            filePath: url.path
        )
        statusMessage = "Pfad kann nicht geöffnet werden: \(url.path)"
    }

    func revealDiagnosticsFile() {
        do {
            try fileStore.ensureRoot()
            if FileManager.default.fileExists(atPath: fileStore.diagnosticsURL.path) == false {
                try Data().write(to: fileStore.diagnosticsURL, options: .atomic)
            }
            reveal(path: fileStore.diagnosticsURL.path)
        } catch {
            recordDiagnostic(
                severity: .error,
                title: "Diagnostics-Datei kann nicht geöffnet werden",
                message: error.localizedDescription,
                context: "AppStore.revealDiagnosticsFile",
                details: String(describing: error),
                filePath: fileStore.diagnosticsURL.path
            )
            statusMessage = "Diagnostics-Datei kann nicht geöffnet werden: \(error.localizedDescription)"
        }
    }

    func revealAgentProfilesFile() {
        do {
            try fileStore.writeAgentProfiles(agentProfiles)
            reveal(path: fileStore.agentProfilesURL.path)
        } catch {
            recordDiagnostic(
                severity: .error,
                title: "Agent-Profil-Datei kann nicht geöffnet werden",
                message: error.localizedDescription,
                context: "AppStore.revealAgentProfilesFile",
                details: String(describing: error),
                filePath: fileStore.agentProfilesURL.path
            )
            statusMessage = "Agent-Profil-Datei kann nicht geöffnet werden: \(error.localizedDescription)"
        }
    }

    func showSimpleComposer() {
        selectedSection = .simple
    }

    func showDashboard() {
        selectedSection = .dashboard
    }

    func orchestratorDidUpdate(_ run: AgentRunRecord) {
        var runs = runsByTaskID[run.taskID] ?? []
        if let index = runs.firstIndex(where: { $0.id == run.id }) {
            runs[index] = run
        } else {
            runs.append(run)
        }
        runsByTaskID[run.taskID] = runs.sorted { ($0.startedAt ?? .distantPast) < ($1.startedAt ?? .distantPast) }
        if selectedTaskID == nil {
            selectedTaskID = run.taskID
        }
        if selectedRunID == nil || selectedRuns.contains(where: { $0.id == selectedRunID }) == false {
            selectedRunID = run.id
        }
        refreshLearning()
    }

    func orchestratorDidAppendLog(runID: UUID, line: String) {
        logsByRunID[runID, default: []].append(line)
    }

    func orchestratorDidAppendEvent(runID: UUID, event: RunEvent) {
        runEventsByRunID[runID, default: []].append(event)
    }

    func orchestratorDidUpdateTask(_ task: W2RTask) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
        } else {
            tasks.insert(task, at: 0)
        }
    }

    func orchestratorDidRecordDiagnostic(_ diagnostic: DiagnosticRecord) {
        insertDiagnostic(diagnostic)
        statusMessage = "\(diagnostic.severity.label): \(diagnostic.title)"
    }

    func recordDiagnostic(
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
            try fileStore.writeDiagnostic(diagnostic)
        } catch {
            diagnostic.details = [
                diagnostic.details,
                "Diagnostic persistence failed: \(error.localizedDescription)",
                String(describing: error)
            ]
            .filter { !$0.trimmed.isEmpty }
            .joined(separator: "\n\n")
        }

        insertDiagnostic(diagnostic)
    }

    func copyDiagnostic(_ diagnostic: DiagnosticRecord) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(diagnostic.copyText, forType: .string)
        statusMessage = "Diagnose in die Zwischenablage kopiert."
    }

    func copyAllDiagnostics() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(diagnostics.map(\.copyText).joined(separator: "\n\n---\n\n"), forType: .string)
        statusMessage = "Alle Diagnostics in die Zwischenablage kopiert."
    }

    func copyText(_ text: String, label: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        statusMessage = "\(label) in die Zwischenablage kopiert."
    }

    func openExternalURL(_ urlString: String, label: String) {
        guard let url = URL(string: urlString) else {
            recordDiagnostic(
                severity: .error,
                title: "URL kann nicht geöffnet werden",
                message: "Die URL ist ungültig: \(urlString)",
                context: "AppStore.openExternalURL",
                details: urlString
            )
            return
        }
        NSWorkspace.shared.open(url)
        statusMessage = "\(label) geöffnet: \(url.absoluteString)"
    }

    func openProviderKeyURL(for key: String, provider: String) {
        guard let urlString = SetupGuidance.providerKeyURL(for: key) else {
            recordDiagnostic(
                severity: .error,
                title: "Provider-Key-Seite unbekannt",
                message: "Für \(key) ist keine Provider-Key-Seite hinterlegt.",
                context: "AppStore.openProviderKeyURL",
                details: key
            )
            statusMessage = "Keine Key-Seite für \(key) hinterlegt."
            return
        }
        openExternalURL(urlString, label: "\(provider)-Key-Seite für \(key)")
    }

    private func autoSelectedInstallations() -> [CLIInstallation] {
        let installed = installedInstallations
        let native = installed.filter { $0.strategy == .native }
        let wrappers = installed.filter { $0.strategy == .wrapper }
        return Array((native + wrappers).prefix(6))
    }

    private func resolvedInstallation(_ installation: CLIInstallation) -> CLIInstallation {
        let profile = profile(for: installation.agent)
        guard let override = profile.commandPathOverride.trimmed.nilIfEmpty else {
            return installation
        }

        guard FileManager.default.isExecutableFile(atPath: override) else {
            return CLIInstallation(
                agent: installation.agent,
                commandName: URL(fileURLWithPath: override).lastPathComponent,
                commandPath: nil,
                isInstalled: false,
                strategy: installation.strategy,
                notes: "CLI-Override ist nicht ausführbar: \(override)"
            )
        }

        return CLIInstallation(
            agent: installation.agent,
            commandName: URL(fileURLWithPath: override).lastPathComponent,
            commandPath: override,
            isInstalled: true,
            strategy: installation.strategy,
            notes: "CLI-Override aus Agent-Profil."
        )
    }

    private func secretValues() -> [String: String] {
        var result: [String: String] = [:]
        for state in providerSecretStates {
            if let value = KeychainService.read(account: state.key) {
                result[state.key] = value
            }
        }
        return result
    }

    private func refreshLearning() {
        learningRows = fileStore.learningSummary(for: tasks)
    }

    private func insertDiagnostic(_ diagnostic: DiagnosticRecord) {
        diagnostics.removeAll { $0.id == diagnostic.id }
        diagnostics.insert(diagnostic, at: 0)
        diagnostics.sort { $0.createdAt > $1.createdAt }
    }

    private func providerName(for key: String) -> String {
        if key.contains("ANTHROPIC") { return "Claude/Anthropic" }
        if key.contains("OPENAI") { return "OpenAI" }
        if key.contains("GEMINI") || key.contains("GOOGLE") { return "Google" }
        if key.contains("GROQ") { return "Groq" }
        if key.contains("DEEPSEEK") { return "DeepSeek" }
        if key.contains("MOONSHOT") { return "Kimi" }
        if key.contains("OPENROUTER") { return "OpenRouter" }
        if key.contains("ZAI") { return "Z.ai / GLM" }
        return "Provider"
    }

    private func loadLog(run: AgentRunRecord) -> [String] {
        do {
            let content = try String(contentsOfFile: run.logPath, encoding: .utf8)
            guard !content.isEmpty else {
                return []
            }
            return content.components(separatedBy: .newlines).map { "\($0)\n" }
        } catch {
            recordDiagnostic(
                severity: .warning,
                title: "Session-Log konnte nicht geladen werden",
                message: error.localizedDescription,
                context: "AppStore.loadLog",
                details: String(describing: error),
                filePath: run.logPath,
                taskID: run.taskID,
                runID: run.id
            )
            return []
        }
    }
}

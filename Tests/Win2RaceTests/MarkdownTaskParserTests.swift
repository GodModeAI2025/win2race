import XCTest
@testable import Win2Race

final class MarkdownTaskParserTests: XCTestCase {
    func testParsesRequiredMarkdownTaskSections() throws {
        let markdown = """
        # task.md

        ## Repository
        https://github.com/org/project

        ## Title
        Fix websocket reconnect issue

        ## Description
        Users lose connection after sleep mode.

        ## Constraints
        - Do not modify auth layer
        - Keep API compatibility
        - Add tests
        """

        let parsed = try MarkdownTaskParser.parse(
            contents: markdown,
            sourceURL: URL(fileURLWithPath: "/tmp/task.md")
        )

        XCTAssertEqual(parsed.draft.repository, "https://github.com/org/project")
        XCTAssertEqual(parsed.draft.title, "Fix websocket reconnect issue")
        XCTAssertEqual(parsed.draft.description, "Users lose connection after sleep mode.")
        XCTAssertEqual(parsed.draft.constraints.linesWithoutEmpty, [
            "Do not modify auth layer",
            "Keep API compatibility",
            "Add tests"
        ])
    }

    func testSluggerCreatesStableBranchSafeSlug() {
        XCTAssertEqual(Slugger.slug("Fix WebSocket Reconnect Issue!"), "fix-websocket-reconnect-issue")
    }

    func testEnvironmentFileValidatorAcceptsExportAndAssignmentSyntax() {
        let messages = EnvironmentFileValidator.validationMessages(for: """
        # comment
        export OPENAI_API_KEY=abc
        W2R_MODE=dev
        EMPTY_VALUE=
        """)

        XCTAssertTrue(messages.isEmpty)
    }

    func testEnvironmentFileValidatorReportsActionableLineNumbers() {
        let messages = EnvironmentFileValidator.validationMessages(for: """
        export OPENAI_API_KEY=abc
        broken line
        1BAD=value
        """)

        XCTAssertEqual(messages, [
            "Zeile 2: erwartet `KEY=value` oder `export KEY=value`.",
            "Zeile 3: `1BAD` ist kein gültiger ENV-Name."
        ])
    }

    func testProcessRunnerTimesOutHangingProcesses() async {
        let result = await ProcessRunner.run(
            executable: "/bin/sleep",
            arguments: ["2"],
            timeout: 0.1
        )

        XCTAssertEqual(result.exitCode, -2)
        XCTAssertTrue(result.stderr.contains("timed out"))
    }

    func testProcessRunnerDrainsLargeOutputWithoutBlocking() async {
        let result = await ProcessRunner.run(
            executable: "/bin/sh",
            arguments: ["-c", "i=0; while [ $i -lt 20000 ]; do echo line-$i; i=$((i+1)); done"],
            timeout: 5
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("line-19999"))
    }

    func testEnvironmentFileLoaderThrowsOnInvalidSyntax() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("env")
        try "broken line".write(to: url, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try EnvironmentFileLoader.load(url: url))
    }

    func testDiagnosticsLoaderReportsCorruptLines() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = FileBackedTaskStore(rootURL: root)
        try store.ensureRoot()
        try "{not-json}\n".write(to: store.diagnosticsURL, atomically: true, encoding: .utf8)

        let diagnostics = store.loadDiagnostics()

        XCTAssertEqual(diagnostics.count, 1)
        XCTAssertEqual(diagnostics[0].severity, .warning)
        XCTAssertEqual(diagnostics[0].title, "Diagnostics-Eintrag konnte nicht gelesen werden")
    }

    func testShellWordsSplitsQuotedExtraArguments() throws {
        let words = try ShellWords.split("--model \"gpt test\" --flag 'two words' plain")

        XCTAssertEqual(words, ["--model", "gpt test", "--flag", "two words", "plain"])
    }

    func testShellWordsReportsUnterminatedQuotes() {
        XCTAssertThrowsError(try ShellWords.split("--model \"broken")) { error in
            XCTAssertTrue(error.localizedDescription.contains("Quote"))
        }
    }

    func testRunEventsPersistAsJSONLines() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = FileBackedTaskStore(rootURL: root)
        try store.ensureRoot()

        let run = AgentRunRecord(
            id: UUID(),
            taskID: UUID(),
            agent: .openAI,
            status: .running,
            commandPath: "/usr/bin/true",
            branchName: "task/test/openai/2026",
            workspacePath: root.appendingPathComponent("workspace").path,
            logPath: root.appendingPathComponent("session.log").path,
            eventsPath: root.appendingPathComponent("events.jsonl").path,
            adrPath: root.appendingPathComponent("adr.md").path,
            runtimePath: root.appendingPathComponent("runtime.md").path,
            feedbackPath: root.appendingPathComponent("feedback.md").path,
            startedAt: Date(),
            endedAt: nil,
            exitCode: nil,
            estimatedTokens: 0,
            estimatedCost: nil,
            lastAction: "testing",
            pendingQuestion: nil,
            errorSummary: nil,
            commitHash: nil
        )
        let event = RunEvent(
            id: UUID(),
            runID: run.id,
            taskID: run.taskID,
            agent: run.agent,
            sequence: 1,
            type: .stdout,
            createdAt: Date(),
            message: "hello",
            isError: false
        )

        try store.appendRunEvent(event, to: run)

        let loaded = try XCTUnwrap(store.loadRunEvents(for: run).first)
        XCTAssertEqual(loaded.id, event.id)
        XCTAssertEqual(loaded.runID, event.runID)
        XCTAssertEqual(loaded.taskID, event.taskID)
        XCTAssertEqual(loaded.agent, event.agent)
        XCTAssertEqual(loaded.sequence, event.sequence)
        XCTAssertEqual(loaded.type, event.type)
        XCTAssertEqual(loaded.message, event.message)
        XCTAssertEqual(loaded.isError, event.isError)
    }

    func testLoadRunsSupportsTimestampedAndLegacyRunDirectories() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = FileBackedTaskStore(rootURL: root)
        try store.ensureRoot()

        var task = W2RTask.fromDraft(
            TaskDraft(repository: "https://github.com/org/repo", title: "Race", description: "Run twice"),
            mode: .simple,
            rootPath: ""
        )
        task.rootPath = store.taskRootURL(slug: task.slug, id: task.id).path
        try store.writeTask(task)

        let legacyRun = runRecord(
            taskID: task.id,
            agent: .claude,
            baseURL: URL(fileURLWithPath: task.rootPath).appendingPathComponent("claude", isDirectory: true)
        )
        let timestampedRun = runRecord(
            taskID: task.id,
            agent: .openAI,
            baseURL: URL(fileURLWithPath: task.rootPath)
                .appendingPathComponent("openAI", isDirectory: true)
                .appendingPathComponent("2026-05-10-1245-abcdef12", isDirectory: true)
        )
        try store.writeRun(legacyRun)
        try store.writeRun(timestampedRun)

        let workspace = URL(fileURLWithPath: task.rootPath)
            .appendingPathComponent("claude/workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try #"{"not":"a w2r run"}"#.write(to: workspace.appendingPathComponent("run.json"), atomically: true, encoding: .utf8)

        let runs = try store.loadRunsReportingDiagnostics(for: task)

        XCTAssertEqual(Set(runs.map(\.id)), Set([legacyRun.id, timestampedRun.id]))
    }

    @MainActor
    func testAgentRuntimeDrainsFinalOutputOnExit() async throws {
        let outputExpectation = expectation(description: "final output")
        let exitExpectation = expectation(description: "exit")
        var receivedOutput = ""
        var outputFulfilled = false

        _ = try AgentRuntime.start(
            runID: UUID(),
            executable: "/bin/sh",
            arguments: ["-c", "printf final-output"],
            currentDirectory: FileManager.default.temporaryDirectory,
            environment: [:],
            onStarted: { _ in },
            onOutput: { text, isError in
                XCTAssertFalse(isError)
                receivedOutput += text
                if !outputFulfilled, receivedOutput.contains("final-output") {
                    outputFulfilled = true
                    outputExpectation.fulfill()
                }
            },
            onExit: { exitCode in
                XCTAssertEqual(exitCode, 0)
                exitExpectation.fulfill()
            }
        )

        await fulfillment(of: [outputExpectation, exitExpectation], timeout: 2)
        XCTAssertTrue(receivedOutput.contains("final-output"))
    }

    func testWorkspaceCleanupRemovesArtifactsButPreservesGit() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = FileBackedTaskStore(rootURL: root)
        try store.ensureRoot()
        let workspace = store.tasksURL.appendingPathComponent("task/workspace", isDirectory: true)
        let artifact = workspace.appendingPathComponent("node_modules/pkg", isDirectory: true)
        let git = workspace.appendingPathComponent(".git/objects", isDirectory: true)
        try FileManager.default.createDirectory(at: artifact, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: git, withIntermediateDirectories: true)
        try "artifact".write(to: artifact.appendingPathComponent("index.js"), atomically: true, encoding: .utf8)
        try "git".write(to: git.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)

        let report = store.cleanupArtifacts(patterns: ["node_modules"])

        XCTAssertEqual(report.removedItems, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.appendingPathComponent("node_modules").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: git.appendingPathComponent("HEAD").path))
    }

    func testCLIDetectorSearchesUserInstallDirectories() {
        let home = "/Users/example"
        let directories = CLIDetector.candidateDirectories(pathValue: "/usr/bin", homeDirectory: home)

        XCTAssertTrue(directories.contains("/Users/example/.opencode/bin"))
        XCTAssertTrue(directories.contains("/Users/example/.local/bin"))
        XCTAssertTrue(directories.contains("/Users/example/.bun/bin"))
        XCTAssertEqual(directories.filter { $0 == "/usr/bin" }.count, 1)
    }

    func testProviderKeyURLsDoNotCrossOpenAnthropicAndOpenAI() {
        XCTAssertEqual(
            SetupGuidance.providerKeyURL(for: "ANTHROPIC_API_KEY"),
            "https://platform.claude.com/settings/keys"
        )
        XCTAssertEqual(
            SetupGuidance.providerKeyURL(for: "OPENAI_API_KEY"),
            "https://platform.openai.com/api-keys"
        )
    }

    func testDashScopeIsNotRequiredForQwen() {
        XCTAssertEqual(AgentKind.qwen.requiredEnvironmentKeys, ["OPENROUTER_API_KEY"])
        XCTAssertNil(SetupGuidance.providerKeyURL(for: "DASHSCOPE_API_KEY"))
    }

    func testOpenRouterBackedAgentsDoNotRequireDirectVendorKeys() {
        XCTAssertEqual(AgentKind.qwen.requiredEnvironmentKeys, ["OPENROUTER_API_KEY"])
        XCTAssertEqual(AgentKind.kimi.requiredEnvironmentKeys, ["OPENROUTER_API_KEY"])
        XCTAssertEqual(AgentKind.glm.requiredEnvironmentKeys, ["OPENROUTER_API_KEY"])
    }

    func testDashScopeIsRemovedFromExistingQwenEnv() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = FileBackedTaskStore(rootURL: root)
        try store.ensureRoot()
        try """
        export OPENROUTER_API_KEY=keep
        export DASHSCOPE_API_KEY=remove
        # export DASHSCOPE_API_KEY=remove-comment
        """.write(to: store.envFileURL(for: .qwen), atomically: true, encoding: .utf8)

        try store.ensureRoot()

        let content = try String(contentsOf: store.envFileURL(for: .qwen), encoding: .utf8)
        XCTAssertTrue(content.contains("OPENROUTER_API_KEY"))
        XCTAssertFalse(content.contains("DASHSCOPE_API_KEY"))
    }

    func testProviderTokenTesterBuildsAnthropicBudgetProbe() throws {
        let plan = try XCTUnwrap(
            ProviderTokenTester.plan(for: "ANTHROPIC_API_KEY", provider: "Claude/Anthropic", token: "test-token")
        )

        XCTAssertEqual(plan.url.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(plan.headers["x-api-key"], "test-token")
        XCTAssertEqual(plan.headers["anthropic-version"], "2023-06-01")
        XCTAssertTrue(plan.budgetProbe)
    }

    func testProviderTokenTesterUsesOpenRouterKeyMetadataEndpoint() throws {
        let plan = try XCTUnwrap(
            ProviderTokenTester.plan(for: "OPENROUTER_API_KEY", provider: "OpenRouter", token: "test-token")
        )

        XCTAssertEqual(plan.method, "GET")
        XCTAssertEqual(plan.url.absoluteString, "https://openrouter.ai/api/v1/auth/key")
        XCTAssertEqual(plan.headers["Authorization"], "Bearer test-token")
        XCTAssertTrue(plan.budgetProbe)
    }

    func testProviderTokenTesterEncodesGeminiKeyInURL() throws {
        let plan = try XCTUnwrap(
            ProviderTokenTester.plan(for: "GEMINI_API_KEY", provider: "Google", token: "a+b/c")
        )

        XCTAssertEqual(plan.url.host, "generativelanguage.googleapis.com")
        let components = try XCTUnwrap(URLComponents(url: plan.url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "key" })?.value, "a+b/c")
    }

    func testProviderTokenTesterClassifiesQuotaErrors() throws {
        let plan = try XCTUnwrap(
            ProviderTokenTester.plan(for: "OPENAI_API_KEY", provider: "OpenAI", token: "test-token")
        )

        let result = ProviderTokenTester.classify(
            key: "OPENAI_API_KEY",
            provider: "OpenAI",
            plan: plan,
            statusCode: 429,
            responseBody: #"{"error":{"code":"insufficient_quota","message":"billing hard limit reached"}}"#
        )

        XCTAssertFalse(result.succeeded)
        XCTAssertFalse(result.budgetLikelyAvailable)
        XCTAssertTrue(result.summary.contains("Budget"))
    }

    func testProviderTokenTesterSupportsEveryRequiredProviderKey() throws {
        let keys = Set(AgentKind.allCases.flatMap(\.requiredEnvironmentKeys))

        for key in keys {
            XCTAssertNotNil(
                ProviderTokenTester.plan(for: key, provider: "Provider", token: "test-token"),
                "\(key) needs a token test plan"
            )
        }
    }

    func testProviderTokenTesterDetectsOpenRouterExhaustedLimit() throws {
        let plan = try XCTUnwrap(
            ProviderTokenTester.plan(for: "OPENROUTER_API_KEY", provider: "OpenRouter", token: "test-token")
        )

        let result = ProviderTokenTester.classify(
            key: "OPENROUTER_API_KEY",
            provider: "OpenRouter",
            plan: plan,
            statusCode: 200,
            responseBody: #"{"data":{"usage":10,"limit":10}}"#
        )

        XCTAssertTrue(result.succeeded)
        XCTAssertFalse(result.budgetLikelyAvailable)
        XCTAssertTrue(result.summary.contains("Budget"))
        XCTAssertTrue(result.details.contains("Usage 10.0 von Limit 10.0"))
    }

    private func runRecord(taskID: UUID, agent: AgentKind, baseURL: URL) -> AgentRunRecord {
        AgentRunRecord(
            id: UUID(),
            taskID: taskID,
            agent: agent,
            status: .succeeded,
            commandPath: "/usr/bin/true",
            branchName: "task/race/\(agent.rawValue)/2026-05-10-1245",
            workspacePath: baseURL.appendingPathComponent("workspace", isDirectory: true).path,
            logPath: baseURL.appendingPathComponent("session.log").path,
            eventsPath: baseURL.appendingPathComponent("events.jsonl").path,
            adrPath: baseURL.appendingPathComponent("adr.md").path,
            runtimePath: baseURL.appendingPathComponent("runtime.md").path,
            feedbackPath: baseURL.appendingPathComponent("feedback.md").path,
            startedAt: Date(),
            endedAt: Date(),
            exitCode: 0,
            estimatedTokens: 0,
            estimatedCost: nil,
            lastAction: "done",
            pendingQuestion: nil,
            errorSummary: nil,
            commitHash: "abc123"
        )
    }
}

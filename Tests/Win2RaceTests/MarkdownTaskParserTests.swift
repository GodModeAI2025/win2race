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
}

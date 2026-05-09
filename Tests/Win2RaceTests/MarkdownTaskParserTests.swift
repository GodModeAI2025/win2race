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
}

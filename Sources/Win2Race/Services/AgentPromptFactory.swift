import Foundation

enum AgentPromptFactory {
    static func prompt(for task: W2RTask, agent: AgentKind) -> String {
        let constraints = task.constraints.isEmpty
            ? "No explicit constraints."
            : task.constraints.map { "- \($0)" }.joined(separator: "\n")

        let example = task.exampleRepository.map {
            """

            Additional reference repository to inspect for reusable ideas:
            \($0)
            If you find relevant concepts, explain what should or should not be adopted.
            """
        } ?? ""

        return """
        You are \(agent.displayName), running inside Win-to-Race on an isolated branch and workspace.

        Solve this real software-development task in the repository you are currently in.

        Repository:
        \(task.repository)

        Title:
        \(task.title)

        Problem:
        \(task.description)

        Constraints:
        \(constraints)
        \(example)

        Required workflow:
        1. Inspect the codebase before editing.
        2. Make the smallest coherent change that solves the problem.
        3. Run relevant tests or validation commands when practical.
        4. If you are blocked by missing product context, ask exactly one question prefixed with `W2R_QUESTION:`.
        5. Summarize the implementation, validation, residual risks, and files changed.

        Win-to-Race will collect logs, commit changes, and generate the external ADR after your process exits.
        """
    }
}

enum QuestionDetector {
    static func question(in output: String) -> String? {
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmed
            if trimmed.localizedCaseInsensitiveContains("W2R_QUESTION:") {
                return trimmed
            }

            let lowercased = trimmed.lowercased()
            if trimmed.hasSuffix("?"),
               lowercased.contains("should") || lowercased.contains("clarify") || lowercased.contains("confirm") {
                return trimmed
            }
        }
        return nil
    }
}

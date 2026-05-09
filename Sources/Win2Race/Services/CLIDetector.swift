import Foundation

enum CLIDetector {
    static func detect() -> [CLIInstallation] {
        AgentKind.allCases.map { agent in
            let commandPath = findExecutable(named: agent.preferredCommands)
            let commandName = commandPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? agent.preferredCommands[0]
            let strategy: CLIStrategy = {
                switch agent {
                case .claude, .gemini, .openAI:
                    return .native
                default:
                    return agent.preferredCommands.contains("aider") ? .wrapper : .native
                }
            }()

            let notes: String
            if commandPath == nil {
                notes = "CLI nicht im PATH gefunden: \(agent.preferredCommands.joined(separator: ", "))"
            } else if strategy == .wrapper {
                notes = "Wird über \(commandName) ausgeführt."
            } else {
                notes = "Native CLI erkannt."
            }

            return CLIInstallation(
                agent: agent,
                commandName: commandName,
                commandPath: commandPath,
                isInstalled: commandPath != nil,
                strategy: strategy,
                notes: notes
            )
        }
    }

    private static func findExecutable(named names: [String]) -> String? {
        let fileManager = FileManager.default
        let pathValue = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let pathCandidates = pathValue
            .split(separator: ":")
            .map(String.init) + [
                "/opt/homebrew/bin",
                "/usr/local/bin",
                "/usr/bin",
                "/bin"
            ]

        var seen = Set<String>()
        let directories = pathCandidates.filter { seen.insert($0).inserted }

        for name in names {
            if name.hasPrefix("/") && fileManager.isExecutableFile(atPath: name) {
                return name
            }

            for directory in directories {
                let candidate = URL(fileURLWithPath: directory).appendingPathComponent(name).path
                if fileManager.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
        }

        return nil
    }
}

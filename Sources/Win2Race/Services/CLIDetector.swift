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

    static func candidateDirectories(pathValue: String, homeDirectory: String = NSHomeDirectory()) -> [String] {
        let home = URL(fileURLWithPath: homeDirectory, isDirectory: true)
        let pathCandidates = pathValue
            .split(separator: ":")
            .map(String.init) + [
                home.appendingPathComponent(".opencode/bin", isDirectory: true).path,
                home.appendingPathComponent(".local/bin", isDirectory: true).path,
                home.appendingPathComponent("bin", isDirectory: true).path,
                home.appendingPathComponent(".bun/bin", isDirectory: true).path,
                home.appendingPathComponent(".cargo/bin", isDirectory: true).path,
                home.appendingPathComponent(".volta/bin", isDirectory: true).path,
                home.appendingPathComponent(".npm-global/bin", isDirectory: true).path,
                home.appendingPathComponent(".asdf/shims", isDirectory: true).path,
                home.appendingPathComponent(".mise/shims", isDirectory: true).path,
                home.appendingPathComponent("Library/pnpm", isDirectory: true).path,
                "/opt/homebrew/bin",
                "/opt/homebrew/sbin",
                "/usr/local/bin",
                "/usr/local/sbin",
                "/usr/bin",
                "/bin",
                "/usr/sbin",
                "/sbin"
            ] + versionManagerBinDirectories(home: home)

        var seen = Set<String>()
        return pathCandidates.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private static func findExecutable(named names: [String]) -> String? {
        let fileManager = FileManager.default
        let pathValue = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let directories = candidateDirectories(pathValue: pathValue)

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

    private static func versionManagerBinDirectories(home: URL) -> [String] {
        let fileManager = FileManager.default
        let roots = [
            home.appendingPathComponent(".nvm/versions/node", isDirectory: true),
            home.appendingPathComponent(".fnm/node-versions", isDirectory: true)
        ]

        return roots.flatMap { root in
            guard let versions = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                return [String]()
            }

            return versions.map { $0.appendingPathComponent("bin", isDirectory: true).path }
        }
    }
}

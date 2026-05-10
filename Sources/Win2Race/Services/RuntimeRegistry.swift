import Foundation

enum RuntimeRegistry {
    static func records(installations: [CLIInstallation], profiles: [AgentKind: AgentProfile]) -> [RuntimeRecord] {
        installations.map { installation in
            let profile = profiles[installation.agent] ?? .default(for: installation.agent)
            let override = profile.commandPathOverride.trimmed
            let overridePath = override.nilIfEmpty
            let overrideIsExecutable = overridePath.map { FileManager.default.isExecutableFile(atPath: $0) } ?? false
            let commandPath = overrideIsExecutable ? overridePath : installation.commandPath

            let health: RuntimeHealth
            let message: String
            if overridePath != nil, !overrideIsExecutable {
                health = .misconfigured
                message = "CLI-Override ist gesetzt, aber nicht ausführbar: \(override)"
            } else if commandPath == nil {
                health = .missing
                message = installation.notes
            } else {
                health = .ready
                message = "Runtime kann \(installation.agent.displayName) über \(URL(fileURLWithPath: commandPath ?? installation.commandName).lastPathComponent) starten."
            }

            return RuntimeRecord(
                agent: installation.agent,
                commandPath: commandPath,
                strategy: installation.strategy,
                health: health,
                capabilities: capabilities(for: installation.agent, profile: profile),
                lastCheckedAt: Date(),
                message: message
            )
        }
    }

    private static func capabilities(for agent: AgentKind, profile: AgentProfile) -> [String] {
        var values = ["headless", "logs", "adr", "feedback"]
        if !agent.requiredEnvironmentKeys.isEmpty {
            values.append("provider-env")
        }
        if !profile.modelOverride.trimmed.isEmpty {
            values.append("model-override")
        }
        if !profile.extraArguments.trimmed.isEmpty {
            values.append("custom-args")
        }
        if !profile.sshIdentityPath.trimmed.isEmpty {
            values.append("agent-git-ssh")
        }
        return values
    }
}

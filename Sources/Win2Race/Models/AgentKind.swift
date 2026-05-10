import Foundation

enum AgentKind: String, CaseIterable, Codable, Hashable, Identifiable {
    case claude
    case gemini
    case openAI
    case deepSeek
    case qwen
    case kimi
    case groq
    case glm
    case aider
    case openCode

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: "Claude"
        case .gemini: "Gemini"
        case .openAI: "OpenAI Codex"
        case .deepSeek: "DeepSeek"
        case .qwen: "Qwen"
        case .kimi: "Kimi"
        case .groq: "Groq"
        case .glm: "GLM"
        case .aider: "aider"
        case .openCode: "OpenCode"
        }
    }

    var providerName: String {
        switch self {
        case .openAI: "OpenAI"
        case .openCode: "OpenCode"
        default: displayName
        }
    }

    var systemImage: String {
        switch self {
        case .claude: "sparkles"
        case .gemini: "diamond"
        case .openAI: "circle.hexagongrid"
        case .deepSeek: "scope"
        case .qwen: "q.circle"
        case .kimi: "moon.stars"
        case .groq: "bolt"
        case .glm: "brain"
        case .aider: "terminal"
        case .openCode: "curlybraces"
        }
    }

    var preferredCommands: [String] {
        switch self {
        case .claude: ["claude"]
        case .gemini: ["gemini"]
        case .openAI: ["codex"]
        case .openCode: ["opencode"]
        case .aider, .deepSeek, .qwen, .kimi, .groq, .glm: ["aider"]
        }
    }

    var defaultModelName: String? {
        switch self {
        case .deepSeek: "deepseek/deepseek-chat"
        case .qwen: "openrouter/qwen/qwen3-coder"
        case .kimi: "openrouter/moonshotai/kimi-k2"
        case .groq: "groq/llama-3.3-70b-versatile"
        case .glm: "openrouter/z-ai/glm-4.5"
        default: nil
        }
    }

    var requiredEnvironmentKeys: [String] {
        switch self {
        case .claude: ["ANTHROPIC_API_KEY"]
        case .gemini: ["GEMINI_API_KEY", "GOOGLE_API_KEY"]
        case .openAI: ["OPENAI_API_KEY"]
        case .deepSeek: ["DEEPSEEK_API_KEY"]
        case .qwen: ["OPENROUTER_API_KEY", "DASHSCOPE_API_KEY"]
        case .kimi: ["OPENROUTER_API_KEY", "MOONSHOT_API_KEY"]
        case .groq: ["GROQ_API_KEY"]
        case .glm: ["OPENROUTER_API_KEY", "ZAI_API_KEY"]
        case .aider, .openCode: []
        }
    }

    func defaultArguments(prompt: String, modelOverride: String? = nil) -> [String] {
        let resolvedModel = modelOverride?.trimmed.nilIfEmpty ?? defaultModelName
        switch self {
        case .claude:
            var arguments = ["-p", prompt]
            if let resolvedModel {
                arguments.append(contentsOf: ["--model", resolvedModel])
            }
            return arguments
        case .gemini:
            var arguments = ["--prompt", prompt]
            if let resolvedModel {
                arguments.append(contentsOf: ["--model", resolvedModel])
            }
            return arguments
        case .openAI:
            var arguments = ["exec"]
            if let resolvedModel {
                arguments.append(contentsOf: ["--model", resolvedModel])
            }
            arguments.append(prompt)
            return arguments
        case .openCode:
            var arguments = ["run"]
            if let resolvedModel {
                arguments.append(contentsOf: ["--model", resolvedModel])
            }
            arguments.append(prompt)
            return arguments
        case .aider:
            var arguments = ["--yes-always"]
            if let resolvedModel {
                arguments.append(contentsOf: ["--model", resolvedModel])
            }
            arguments.append(contentsOf: ["--message", prompt])
            return arguments
        case .deepSeek, .qwen, .kimi, .groq, .glm:
            var arguments = ["--yes-always"]
            if let resolvedModel {
                arguments.append(contentsOf: ["--model", resolvedModel])
            }
            arguments.append(contentsOf: ["--message", prompt])
            return arguments
        }
    }
}

struct CLIInstallation: Identifiable, Codable, Hashable {
    var id: String { "\(agent.rawValue):\(commandPath ?? "missing")" }
    let agent: AgentKind
    let commandName: String
    let commandPath: String?
    let isInstalled: Bool
    let strategy: CLIStrategy
    let notes: String

    var readinessLabel: String {
        isInstalled ? "Bereit" : "Fehlt"
    }
}

enum CLIStrategy: String, Codable, Hashable {
    case native
    case wrapper
}

struct ProviderSecretState: Identifiable, Hashable {
    var id: String { key }
    let key: String
    let provider: String
    var isPresent: Bool
}

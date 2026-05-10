import Foundation

enum SetupGuidance {
    private static let providerKeyURLs: [String: String] = [
        "ANTHROPIC_API_KEY": "https://platform.claude.com/settings/keys",
        "OPENAI_API_KEY": "https://platform.openai.com/api-keys",
        "GEMINI_API_KEY": "https://aistudio.google.com/app/apikey",
        "GOOGLE_API_KEY": "https://aistudio.google.com/app/apikey",
        "GROQ_API_KEY": "https://console.groq.com/keys",
        "DEEPSEEK_API_KEY": "https://platform.deepseek.com/api_keys",
        "OPENROUTER_API_KEY": "https://openrouter.ai/settings/keys"
    ]

    static func providerKeyURL(for key: String) -> String? {
        providerKeyURLs[key.trimmed.uppercased()]
    }
}

import Foundation

enum ProviderTokenTester {
    struct Plan: Hashable {
        var provider: String
        var url: URL
        var method: String
        var headers: [String: String]
        var body: Data?
        var budgetProbe: Bool
        var note: String
    }

    static func test(key: String, provider: String, token: String) async -> ProviderTokenTestResult {
        guard let plan = plan(for: key, provider: provider, token: token) else {
            return ProviderTokenTestResult(
                key: key,
                provider: provider,
                checkedAt: Date(),
                succeeded: false,
                budgetLikelyAvailable: false,
                statusCode: nil,
                summary: "Für \(key) ist noch kein Provider-Test hinterlegt.",
                details: "Provider: \(provider)"
            )
        }

        do {
            var request = URLRequest(url: plan.url)
            request.httpMethod = plan.method
            request.timeoutInterval = 30
            for (header, value) in plan.headers {
                request.setValue(value, forHTTPHeaderField: header)
            }
            request.httpBody = plan.body

            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            let body = String(data: data, encoding: .utf8) ?? ""
            return classify(
                key: key,
                provider: provider,
                plan: plan,
                statusCode: statusCode,
                responseBody: body
            )
        } catch {
            return ProviderTokenTestResult(
                key: key,
                provider: provider,
                checkedAt: Date(),
                succeeded: false,
                budgetLikelyAvailable: false,
                statusCode: nil,
                summary: "\(provider)-Test konnte nicht ausgeführt werden.",
                details: [
                    "Plan: \(plan.note)",
                    "Endpoint: \(plan.method) \(redactedURL(plan.url))",
                    "Error: \(error.localizedDescription)",
                    String(describing: error)
                ].joined(separator: "\n")
            )
        }
    }

    static func plan(for key: String, provider: String, token: String) -> Plan? {
        switch key.trimmed.uppercased() {
        case "OPENAI_API_KEY":
            return jsonPlan(
                provider: provider,
                url: "https://api.openai.com/v1/responses",
                bearer: token,
                body: [
                    "model": "gpt-4.1-mini",
                    "input": "ping",
                    "max_output_tokens": 1
                ],
                budgetProbe: true,
                note: "Minimale Responses-Anfrage. Prüft Authentifizierung und erkennt typische Quota/Billing-Fehler."
            )
        case "ANTHROPIC_API_KEY":
            return jsonPlan(
                provider: provider,
                url: "https://api.anthropic.com/v1/messages",
                bearer: nil,
                extraHeaders: [
                    "x-api-key": token,
                    "anthropic-version": "2023-06-01"
                ],
                body: [
                    "model": "claude-3-5-haiku-latest",
                    "max_tokens": 1,
                    "messages": [
                        [
                            "role": "user",
                            "content": "ping"
                        ]
                    ]
                ],
                budgetProbe: true,
                note: "Minimale Claude-Anfrage. Prüft Authentifizierung und erkennt typische Credit/Billing-Fehler."
            )
        case "GEMINI_API_KEY", "GOOGLE_API_KEY":
            guard let url = geminiURL(token: token) else {
                return nil
            }
            return jsonPlan(
                provider: provider,
                url: url.absoluteString,
                bearer: nil,
                body: [
                    "contents": [
                        [
                            "parts": [
                                ["text": "ping"]
                            ]
                        ]
                    ],
                    "generationConfig": [
                        "maxOutputTokens": 1
                    ]
                ],
                budgetProbe: true,
                note: "Minimale Gemini-Anfrage. Prüft Authentifizierung und erkennt typische Quota/Billing-Fehler."
            )
        case "GROQ_API_KEY":
            return chatCompletionsPlan(
                provider: provider,
                url: "https://api.groq.com/openai/v1/chat/completions",
                bearer: token,
                model: "llama-3.3-70b-versatile"
            )
        case "DEEPSEEK_API_KEY":
            return chatCompletionsPlan(
                provider: provider,
                url: "https://api.deepseek.com/chat/completions",
                bearer: token,
                model: "deepseek-chat"
            )
        case "OPENROUTER_API_KEY":
            guard let url = URL(string: "https://openrouter.ai/api/v1/auth/key") else {
                return nil
            }
            return Plan(
                provider: provider,
                url: url,
                method: "GET",
                headers: [
                    "Authorization": "Bearer \(token)",
                    "Accept": "application/json"
                ],
                body: nil,
                budgetProbe: true,
                note: "OpenRouter-Key-Metadaten inklusive Limit/Usage, wenn der Provider sie liefert."
            )
        case "MOONSHOT_API_KEY":
            return chatCompletionsPlan(
                provider: provider,
                url: "https://api.moonshot.ai/v1/chat/completions",
                bearer: token,
                model: "moonshot-v1-8k"
            )
        case "ZAI_API_KEY":
            return chatCompletionsPlan(
                provider: provider,
                url: "https://open.bigmodel.cn/api/paas/v4/chat/completions",
                bearer: token,
                model: "glm-4-flash"
            )
        default:
            return nil
        }
    }

    static func classify(
        key: String,
        provider: String,
        plan: Plan,
        statusCode: Int?,
        responseBody: String
    ) -> ProviderTokenTestResult {
        let normalized = responseBody.lowercased()
        let hasBudgetProblem = normalized.contains("insufficient_quota") ||
            normalized.contains("insufficient quota") ||
            normalized.contains("quota") ||
            normalized.contains("billing") ||
            normalized.contains("credit") ||
            normalized.contains("payment") ||
            statusCode == 402 ||
            statusCode == 429
        let hasAuthProblem = statusCode == 401 || statusCode == 403 ||
            normalized.contains("invalid api key") ||
            normalized.contains("unauthorized") ||
            normalized.contains("forbidden")
        let succeeded = statusCode.map { 200..<300 ~= $0 } ?? false
        let budgetStatus = budgetAvailability(from: responseBody, plan: plan, succeeded: succeeded)
        let budgetLikelyAvailable = budgetStatus.isLikelyAvailable

        let summary: String
        if succeeded {
            summary = budgetStatus.summary(provider: provider)
        } else if hasBudgetProblem {
            summary = "\(provider)-Key wurde erreicht, aber Budget/Quota/Billing scheint zu blockieren."
        } else if hasAuthProblem {
            summary = "\(provider)-Key ist ungültig oder hat keinen Zugriff."
        } else {
            summary = "\(provider)-Test fehlgeschlagen."
        }

        return ProviderTokenTestResult(
            key: key,
            provider: provider,
            checkedAt: Date(),
            succeeded: succeeded,
            budgetLikelyAvailable: budgetLikelyAvailable,
            statusCode: statusCode,
            summary: summary,
            details: [
                "Plan: \(plan.note)",
                "Endpoint: \(plan.method) \(redactedURL(plan.url))",
                "HTTP: \(statusCode.map(String.init) ?? "n/a")",
                "Budget: \(budgetStatus.detail)",
                "Response:",
                responseBody.trimmed.prefix(4_000).description
            ].joined(separator: "\n")
        )
    }

    private struct BudgetStatus {
        var isLikelyAvailable: Bool
        var detail: String

        func summary(provider: String) -> String {
            if isLikelyAvailable {
                "\(provider)-Key ist nutzbar; \(detail)"
            } else {
                "\(provider)-Key ist gültig, aber Budget/Quota ist nicht nutzbar."
            }
        }
    }

    private static func budgetAvailability(from responseBody: String, plan: Plan, succeeded: Bool) -> BudgetStatus {
        guard succeeded else {
            return BudgetStatus(isLikelyAvailable: false, detail: "Test nicht erfolgreich.")
        }
        guard plan.budgetProbe else {
            return BudgetStatus(isLikelyAvailable: false, detail: "Dieser Test bestätigt kein Budget.")
        }
        guard plan.url.host?.contains("openrouter.ai") == true else {
            return BudgetStatus(
                isLikelyAvailable: true,
                detail: "die minimale Anfrage wurde akzeptiert. Budget/Quota ist damit wahrscheinlich verfügbar."
            )
        }

        guard let data = responseBody.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return BudgetStatus(
                isLikelyAvailable: true,
                detail: "OpenRouter hat den Key akzeptiert; Budgetdaten konnten nicht gelesen werden."
            )
        }

        let payload = (object["data"] as? [String: Any]) ?? object
        let usage = numericValue(payload["usage"])
        let limit = numericValue(payload["limit"])
        if let usage, let limit {
            if limit <= 0 || usage >= limit {
                return BudgetStatus(
                    isLikelyAvailable: false,
                    detail: "OpenRouter Usage \(usage) von Limit \(limit); Limit ist erreicht oder nicht nutzbar."
                )
            }
            return BudgetStatus(
                isLikelyAvailable: true,
                detail: "OpenRouter Usage \(usage) von Limit \(limit); Budget ist wahrscheinlich verfügbar."
            )
        }
        if payload.keys.contains("limit"), limit == nil {
            return BudgetStatus(
                isLikelyAvailable: true,
                detail: "OpenRouter-Key ist gültig; kein festes Limit gemeldet."
            )
        }
        return BudgetStatus(
            isLikelyAvailable: true,
            detail: "OpenRouter-Key ist gültig; keine Budgetgrenze im Ergebnis gemeldet."
        )
    }

    private static func numericValue(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber:
            number.doubleValue
        case let string as String:
            Double(string)
        default:
            nil
        }
    }

    private static func geminiURL(token: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "generativelanguage.googleapis.com"
        components.path = "/v1beta/models/gemini-2.0-flash:generateContent"
        components.queryItems = [URLQueryItem(name: "key", value: token)]
        return components.url
    }

    private static func chatCompletionsPlan(provider: String, url: String, bearer: String, model: String) -> Plan? {
        jsonPlan(
            provider: provider,
            url: url,
            bearer: bearer,
            body: [
                "model": model,
                "messages": [
                    [
                        "role": "user",
                        "content": "ping"
                    ]
                ],
                "max_tokens": 1
            ],
            budgetProbe: true,
            note: "Minimale OpenAI-kompatible Chat-Anfrage. Prüft Authentifizierung und erkennt typische Quota/Billing-Fehler."
        )
    }

    private static func jsonPlan(
        provider: String,
        url: String,
        bearer: String?,
        extraHeaders: [String: String] = [:],
        body: [String: Any],
        budgetProbe: Bool,
        note: String
    ) -> Plan? {
        guard let url = URL(string: url),
              JSONSerialization.isValidJSONObject(body),
              let bodyData = try? JSONSerialization.data(withJSONObject: body, options: []) else {
            return nil
        }

        var headers = extraHeaders
        headers["Content-Type"] = "application/json"
        headers["Accept"] = "application/json"
        if let bearer {
            headers["Authorization"] = "Bearer \(bearer)"
        }

        return Plan(
            provider: provider,
            url: url,
            method: "POST",
            headers: headers,
            body: bodyData,
            budgetProbe: budgetProbe,
            note: note
        )
    }

    private static func redactedURL(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems,
              !queryItems.isEmpty else {
            return url.absoluteString
        }

        components.queryItems = queryItems.map { item in
            if item.name.lowercased() == "key" {
                return URLQueryItem(name: item.name, value: "REDACTED")
            }
            return item
        }
        return components.url?.absoluteString ?? url.absoluteString
    }
}

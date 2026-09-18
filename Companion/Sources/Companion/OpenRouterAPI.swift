import Foundation

final class OpenRouterAPI {
    static let shared = OpenRouterAPI()
    private let client: OpenAICompatibleAPI

    init(client: OpenAICompatibleAPI = .shared) {
        self.client = client
    }

    func rewrite(_ text: String, systemPrompt: String, model: String, images: [PromptImageAttachment], apiKey: String? = nil) async throws -> String {
        try await generate(text, systemPrompt: systemPrompt, model: model, images: images, apiKey: apiKey).text
    }

    func generate(_ text: String, systemPrompt: String, model: String, images: [PromptImageAttachment], apiKey: String? = nil, webSearch: Bool = false) async throws -> TextCompletion {
        let key = apiKey ?? UserSettings.shared.openRouterAPIKey
        let canonicalModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let isGeminiLite = canonicalModel == "google/gemini-3.5-flash-lite"
        // Prioritize complete rewrite speed, without changing the selected model.
        // OpenRouter max_price uses USD per million tokens, not per-token prices.
        // Keep caps scoped to the tested models so other routes still work.
        let speedPreferences: [String: Any]? = (canonicalModel == "deepseek/deepseek-v4.1-flash" || isGeminiLite) ? [
            "sort": "throughput",
            "allow_fallbacks": true,
            "require_parameters": true,
            "max_price": ["prompt": 0.30, "completion": isGeminiLite ? 2.50 : 1.20]
        ] : nil
        return try await client.complete(
            text, systemPrompt: systemPrompt, providerName: "OpenRouter",
            endpoint: URL(string: "https://openrouter.ai/api/v1/chat/completions")!,
            apiKey: key, authorizationHeader: "Bearer \(key)", model: model, images: images,
            disableReasoning: true,
            reasoningEffort: isGeminiLite ? "minimal" : nil,
            providerPreferences: speedPreferences,
            webSearch: webSearch
        )
    }
}

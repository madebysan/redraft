import Foundation

final class OpenRouterAPI {
    static let shared = OpenRouterAPI()
    func rewrite(_ text: String, systemPrompt: String, model: String, images: [PromptImageAttachment]) async throws -> String {
        let key = UserSettings.shared.openRouterAPIKey
        return try await OpenAICompatibleAPI.shared.rewrite(
            text, systemPrompt: systemPrompt, providerName: "OpenRouter",
            endpoint: URL(string: "https://openrouter.ai/api/v1/chat/completions")!,
            apiKey: key, authorizationHeader: "Bearer \(key)", model: model, images: images,
            disableReasoning: true
        )
    }
}

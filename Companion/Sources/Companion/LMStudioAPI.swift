import Foundation

// Handles communication with a local LM Studio server (OpenAI-compatible API).
// Any OpenAI-compatible local server (Ollama, llama.cpp, vLLM) works through the same path.
final class LMStudioAPI {
    static let shared = LMStudioAPI()
    private let session: URLSession

    // Local servers may need to load the model into memory before answering, and
    // thinking models spend tokens before the visible answer, so this is generous.
    static let chatTimeout: TimeInterval = 180
    static let listTimeout: TimeInterval = 5

    init(session: URLSession = .shared) {
        self.session = session
    }

    enum APIError: Error, LocalizedError, Equatable {
        case invalidURL(String)
        case notReachable(String, String)
        case timedOut(String, Int)
        case insecureHostBlocked(String)
        case noModelConfigured
        case modelNotFound(String)
        case requestFailed(String)
        case invalidResponse
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .invalidURL(let url):
                return "“\(url)” isn't a usable server address. Use something like http://127.0.0.1:1234 in Settings."
            case .notReachable(let url, let detail):
                return "Couldn't connect to the local server at \(url). Check that LM Studio's server is running and the address is right. (\(detail))"
            case .timedOut(let url, let seconds):
                return "The local server at \(url) didn't answer within \(seconds) seconds. The model may still be loading or is too slow for this Mac. Try again, or pick a smaller model."
            case .insecureHostBlocked(let url):
                return "macOS blocked the plain http connection to \(url). Use the server's IP address or a .local name, or enable https on the server."
            case .noModelConfigured:
                return "No local model selected. Pick one in Settings."
            case .modelNotFound(let model):
                return "The local server has no model named “\(model)”. In Settings, click Refresh and pick one of the listed models."
            case .requestFailed(let msg):
                return "Local server request failed: \(msg)"
            case .invalidResponse:
                return "Invalid response from the local server."
            case .emptyResponse:
                return "Empty response from the local server."
            }
        }
    }

    // Rewrite text via LM Studio chat completions
    func rewrite(
        _ text: String,
        systemPrompt: String,
        model overrideModel: String? = nil,
        images: [PromptImageAttachment] = []
    ) async throws -> String {
        let baseURL = UserSettings.shared.lmStudioBaseURL
        let model = (overrideModel ?? UserSettings.shared.lmStudioModel)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !model.isEmpty else { throw APIError.noModelConfigured }
        let url = try Self.endpoint(baseURL: baseURL, path: "/v1/chat/completions")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userContent(text: text, images: images)]
            ],
            "temperature": 0.3,
            "max_tokens": 4096
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = Self.chatTimeout

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw Self.transportError(error, baseURL: baseURL, timeout: Self.chatTimeout)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw Self.httpError(status: httpResponse.statusCode, data: data, model: model)
        }

        return try CompletionValidator.openAI(data)
    }

    private func userContent(text: String, images: [PromptImageAttachment]) -> Any {
        guard !images.isEmpty else { return text }

        var content: [[String: Any]] = [
            ["type": "text", "text": text]
        ]

        for image in images {
            let encoded = image.data.base64EncodedString()
            let dataURL = "data:\(image.mimeType);base64,\(encoded)"
            content.append([
                "type": "image_url",
                "image_url": ["url": dataURL]
            ])
        }

        return content
    }

    // List available models at the configured base URL
    func listModels() async throws -> [String] {
        let baseURL = UserSettings.shared.lmStudioBaseURL
        let url = try Self.endpoint(baseURL: baseURL, path: "/v1/models")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = Self.listTimeout

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw Self.transportError(error, baseURL: baseURL, timeout: Self.listTimeout)
        }

        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard httpResponse.statusCode == 200 else {
            throw Self.httpError(status: httpResponse.statusCode, data: data, model: "")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["data"] as? [[String: Any]] else {
            throw APIError.invalidResponse
        }

        // Filter out embedding models — they can't do chat completions
        return models.compactMap { $0["id"] as? String }
            .filter { !$0.contains("embed") }
    }

    // MARK: - Address and error handling

    // Builds a request URL from whatever address the user typed.
    static func endpoint(baseURL: String, path: String) throws -> URL {
        let normalized = UserSettings.normalizedLMStudioBaseURL(baseURL)
        guard let url = URL(string: normalized + path),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else {
            throw APIError.invalidURL(baseURL)
        }
        return url
    }

    // Maps URLSession failures to messages that say what to fix instead of "not reachable" for everything.
    static func transportError(_ error: Error, baseURL: String, timeout: TimeInterval) -> Error {
        if error is CancellationError { return error }
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else {
            return APIError.notReachable(baseURL, nsError.localizedDescription)
        }
        switch nsError.code {
        case NSURLErrorCancelled:
            return CancellationError()
        case NSURLErrorTimedOut:
            return APIError.timedOut(baseURL, Int(timeout))
        case NSURLErrorAppTransportSecurityRequiresSecureConnection:
            return APIError.insecureHostBlocked(baseURL)
        case NSURLErrorBadURL, NSURLErrorUnsupportedURL:
            return APIError.invalidURL(baseURL)
        default:
            return APIError.notReachable(baseURL, nsError.localizedDescription)
        }
    }

    static func httpError(status: Int, data: Data, model: String) -> APIError {
        var message = String(data: data, encoding: .utf8) ?? "Unknown error"
        var code = ""
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let error = json["error"] as? [String: Any]
            message = (error?["message"] as? String)
                ?? (json["error"] as? String)
                ?? (json["message"] as? String)
                ?? message
            code = (error?["code"] as? String) ?? ""
        }
        let lower = message.lowercased()
        let looksLikeMissingModel = code == "model_not_found"
            || (lower.contains("model") && (lower.contains("not found") || lower.contains("invalid model") || lower.contains("not loaded")))
        if !model.isEmpty, looksLikeMissingModel {
            return .modelNotFound(model)
        }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let shown = trimmed.count > 220 ? "\(trimmed.prefix(220))..." : trimmed
        return .requestFailed("HTTP \(status): \(shown)")
    }
}

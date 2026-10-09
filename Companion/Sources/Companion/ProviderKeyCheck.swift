import Foundation

// Confirms an API key works with a free, read-only request so people find out in Settings
// instead of in the Capsule.
enum ProviderKeyCheck {
    enum CheckError: Error, LocalizedError, Equatable {
        case emptyKey
        case rejected
        case failed(Int)
        case unsupported
        case network(String)

        var errorDescription: String? {
            switch self {
            case .emptyKey: return "Paste a key first."
            case .rejected: return "That key was rejected. Check it and try again."
            case .failed(let status): return "The provider answered with HTTP \(status). Try again in a moment."
            case .unsupported: return "This provider has no free key check. Run a rewrite to test it."
            case .network(let detail): return "Couldn't reach the provider. \(detail)"
            }
        }
    }

    static func request(provider: UserSettings.Provider, key: String) -> URLRequest? {
        var request: URLRequest
        switch provider {
        case .openRouter:
            request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/auth/key")!)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        case .openAI:
            request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        case .deepSeek:
            request = URLRequest(url: URL(string: "https://api.deepseek.com/models")!)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        case .claude:
            request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models")!)
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .fal, .lmStudio:
            return nil
        }
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.timeoutInterval = 15
        return request
    }

    // Returns a short success message.
    static func check(provider: UserSettings.Provider, key: String, session: URLSession = .shared) async throws -> String {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw CheckError.emptyKey }
        guard let request = request(provider: provider, key: key) else { throw CheckError.unsupported }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw CheckError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw CheckError.failed(0) }
        switch http.statusCode {
        case 200..<300:
            return successMessage(provider: provider, data: data)
        case 401, 403:
            throw CheckError.rejected
        default:
            throw CheckError.failed(http.statusCode)
        }
    }

    private static func successMessage(provider: UserSettings.Provider, data: Data) -> String {
        if provider == .openRouter,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let info = json["data"] as? [String: Any] {
            if let limit = info["limit"] as? Double, let usage = info["usage"] as? Double {
                return String(format: "Key works. $%.2f of $%.2f used.", usage, limit)
            }
            if let label = info["label"] as? String, !label.isEmpty {
                return "Key works (\(label))."
            }
        }
        return "Key works."
    }
}

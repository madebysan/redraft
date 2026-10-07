import Foundation

enum CompletionError: LocalizedError {
    case incomplete(String)
    case refused
    case invalid
    case empty

    var errorDescription: String? {
        switch self {
        case .incomplete: return "The model stopped before finishing. Your original text is unchanged."
        case .refused: return "The model declined this rewrite. Your original text is unchanged."
        case .invalid: return "The provider returned an unrecognized response. Your original text is unchanged."
        case .empty: return "The model returned no text. Your original text is unchanged."
        }
    }
}

enum CompletionValidator {
    static func openAI(_ data: Data) throws -> String {
        let root = try object(data)
        let body = root["data"] as? [String: Any] ?? root
        guard let choice = (body["choices"] as? [[String: Any]])?.first,
              let message = choice["message"] as? [String: Any] else { throw CompletionError.invalid }
        let text = stripReasoning(message["content"] as? String ?? "")
        if let refusal = message["refusal"] as? String, !refusal.isEmpty { throw CompletionError.refused }
        switch choice["finish_reason"] as? String {
        case "stop": return try nonempty(text)
        case "length": throw CompletionError.incomplete(text)
        case "content_filter": throw CompletionError.refused
        // Some local servers omit finish_reason on a normal completion.
        case nil, "": return try nonempty(text)
        default: throw CompletionError.invalid
        }
    }

    // Local thinking models (Qwen, DeepSeek R1, LFM) can leak their reasoning into the answer as
    // <think>…</think>, or as a bare </think> when the chat template opened the tag. Pasting that
    // into the user's document is never wanted.
    static func stripReasoning(_ text: String) -> String {
        var output = text
        for tag in ["think", "thinking", "reasoning"] {
            let open = "<\(tag)>", close = "</\(tag)>"
            while let start = output.range(of: open) {
                if let end = output.range(of: close, range: start.upperBound..<output.endIndex) {
                    output.removeSubrange(start.lowerBound..<end.upperBound)
                } else {
                    output.removeSubrange(start.lowerBound..<output.endIndex)
                }
            }
            if let end = output.range(of: close) {
                output.removeSubrange(output.startIndex..<end.upperBound)
            }
        }
        return output
    }

    static func anthropic(_ data: Data) throws -> String {
        let body = try object(data)
        guard let content = body["content"] as? [[String: Any]] else { throw CompletionError.invalid }
        let text = content.filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }.joined(separator: "\n")
        switch body["stop_reason"] as? String {
        case "end_turn", "stop_sequence": return try nonempty(text)
        case "max_tokens": throw CompletionError.incomplete(text)
        case "refusal": throw CompletionError.refused
        default: throw CompletionError.invalid
        }
    }

    private static func object(_ data: Data) throws -> [String: Any] {
        guard let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CompletionError.invalid
        }
        return value
    }

    private static func nonempty(_ text: String) throws -> String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw CompletionError.empty }
        return cleaned
    }
}

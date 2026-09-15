import XCTest
@testable import Companion

final class CompletionValidatorTests: XCTestCase {
    private func response(_ reason: String, text: String = "Fixed sentence.") throws -> Data {
        try JSONSerialization.data(withJSONObject: ["choices": [["finish_reason": reason, "message": ["content": text]]]])
    }

    func testCompleteAndWrappedResponses() throws {
        let data = try response("stop")
        XCTAssertEqual(try CompletionValidator.openAI(data), "Fixed sentence.")
        let wrapper = try JSONSerialization.data(withJSONObject: ["data": JSONSerialization.jsonObject(with: data)])
        XCTAssertEqual(try CompletionValidator.openAI(wrapper), "Fixed sentence.")
    }

    func testTruncatedResponsePreservesPartialTextButCannotBePasted() throws {
        XCTAssertThrowsError(try CompletionValidator.openAI(response("length", text: "Partial"))) { error in
            guard case CompletionError.incomplete(let text) = error else { return XCTFail("Expected incomplete output") }
            XCTAssertEqual(text, "Partial")
        }
    }

    func testRefusalUnknownStopEmptyAndMalformedResponsesAreRejected() throws {
        for reason in ["content_filter", "tool_calls", "unknown"] {
            XCTAssertThrowsError(try CompletionValidator.openAI(response(reason)))
        }
        XCTAssertThrowsError(try CompletionValidator.openAI(response("stop", text: " \n")))
        XCTAssertThrowsError(try CompletionValidator.openAI(Data("{}".utf8)))
        let refusal = Data(#"{"choices":[{"finish_reason":"stop","message":{"content":"No","refusal":"Declined"}}]}"#.utf8)
        XCTAssertThrowsError(try CompletionValidator.openAI(refusal))
    }

    func testAnthropicSkipsThinkingAndValidatesStopReason() throws {
        let blocks: [[String: Any]] = [["type":"thinking", "thinking":"private"], ["type":"text", "text":"Fixed."]]
        let complete = try JSONSerialization.data(withJSONObject: ["content":blocks, "stop_reason":"end_turn"])
        XCTAssertEqual(try CompletionValidator.anthropic(complete), "Fixed.")
        let truncated = try JSONSerialization.data(withJSONObject: ["content":blocks, "stop_reason":"max_tokens"])
        XCTAssertThrowsError(try CompletionValidator.anthropic(truncated))
    }
}

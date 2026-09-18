import XCTest
@testable import Companion

final class WebSearchTests: XCTestCase {
    func testSourcesPersistWithoutChangingCopyableResult() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("CompanionSearch-\(UUID().uuidString)")
        let store = GenerationHistoryStore(directory: folder)
        let sources = [WebSource(title: "Example", url: URL(string: "https://example.com")!)]
        try await store.add(result: "Plain result", actionLabel: "Custom prompt", provider: .openRouter,
            model: "test", selectedWordCount: 0, imageFileNames: [], sources: sources, usedWebSearch: true)
        let entries = try await GenerationHistoryStore(directory: folder).entries()
        XCTAssertEqual(entries.first?.result, "Plain result")
        XCTAssertEqual(entries.first?.sources, sources)
        XCTAssertEqual(entries.first?.usedWebSearch, true)
    }

    func testLiveWebSearchWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["COMPANION_WEB_SMOKE"] == "1",
              let key = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"] else {
            throw XCTSkip("Paid smoke test requires explicit opt-in")
        }
        let prompt = try RewriteDispatcher.customPrompt(text: "", instruction: "Use web search. In one sentence, describe what the official Blender application does.")
        let result = try await OpenRouterAPI.shared.generate(prompt.userText, systemPrompt: prompt.systemPrompt,
            model: "google/gemini-3.5-flash-lite", images: [], apiKey: key, webSearch: true)
        XCTAssertFalse(result.sources.isEmpty)
        XCTAssertTrue(result.sources.contains { $0.url.host?.contains("blender.org") == true })
        XCTAssertFalse(result.text.contains("https://"))
        XCTAssertFalse(result.text.contains("http://"))
        print("Search smoke result: \(result.text)")
        print("Search smoke sources: \(result.sources.map { $0.url.absoluteString })")
    }

    func testOnlyExplicitInstructionEnablesSearch() throws {
        for instruction in ["Use web search: describe a library", "describe it; USE WEB SEARCH"] {
            XCTAssertTrue(WebSearch.requested(in: instruction))
        }
        for instruction in ["summarize", "search", "don't use web search", "do not use web search", "reuse web search results"] {
            XCTAssertFalse(WebSearch.requested(in: instruction))
        }
        let prompt = try RewriteDispatcher.customPrompt(text: "use web search", instruction: "summarize")
        XCTAssertFalse(prompt.systemPrompt.contains(WebSearch.grounding))
        let search = try RewriteDispatcher.customPrompt(text: "", instruction: "use web search: describe it")
        XCTAssertTrue(search.systemPrompt.contains(WebSearch.grounding))
    }

    func testSourcesAreSeparateAndUnsafeLinksRejected() throws {
        let data = try JSONSerialization.data(withJSONObject: ["choices": [["finish_reason": "stop", "message": [
            "content": "A library. [1](https://example.com/library)",
            "annotations": [
                ["type": "url_citation", "url_citation": ["url": "https://example.com/library", "title": "Library"]],
                ["type": "url_citation", "url_citation": ["url": "file:///private", "title": "Bad"]]
            ]
        ]]]])
        let result = try WebSearch.completion(from: data)
        XCTAssertEqual(result.text, "A library.")
        XCTAssertEqual(result.sources.count, 1)
        XCTAssertEqual(result.sources.first?.title, "Library")
    }

    func testNoSourcesDoesNotPretendSearchSucceeded() throws {
        let data = Data(#"{"choices":[{"finish_reason":"stop","message":{"content":"Unverified claim"}}]}"#.utf8)
        XCTAssertThrowsError(try WebSearch.completion(from: data))
    }
}

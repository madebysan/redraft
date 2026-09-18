import XCTest
@testable import Companion

final class OpenRouterRequestTests: XCTestCase {
    func testSearchPluginIsAbsentUnlessExplicitlyRequested() async throws {
        let plain = try await requestBody(model: "google/gemini-3.5-flash-lite")
        XCTAssertNil(plain["plugins"])
        let search = try await requestBody(model: "google/gemini-3.5-flash-lite", webSearch: true)
        let plugin = try XCTUnwrap((search["plugins"] as? [[String: Any]])?.first)
        XCTAssertEqual(plugin["id"] as? String, "web")
        XCTAssertEqual(plugin["engine"] as? String, "exa")
        XCTAssertEqual(plugin["max_results"] as? Int, 3)
    }

    func testGeminiUsesMinimumReasoningAndItsOwnPriceCap() async throws {
        let body = try await requestBody(model: "google/gemini-3.5-flash-lite")
        let reasoning = try XCTUnwrap(body["reasoning"] as? [String: Any])
        XCTAssertEqual(reasoning["effort"] as? String, "minimal")
        XCTAssertNil(reasoning["enabled"])
        let provider = try XCTUnwrap(body["provider"] as? [String: Any])
        XCTAssertEqual(provider["sort"] as? String, "throughput")
        XCTAssertEqual((provider["max_price"] as? [String: Double])?["completion"], 2.50)
        XCTAssertEqual(body["model"] as? String, "google/gemini-3.5-flash-lite")
    }

    func testFlashRequestPrioritizesSpeedWithinBudget() async throws {
        let body = try await requestBody(model: "deepseek/deepseek-v4.1-flash")
        XCTAssertEqual(body["model"] as? String, "deepseek/deepseek-v4.1-flash")
        let provider = try XCTUnwrap(body["provider"] as? [String: Any])
        XCTAssertEqual(provider["sort"] as? String, "throughput")
        XCTAssertEqual(provider["allow_fallbacks"] as? Bool, true)
        XCTAssertEqual(provider["require_parameters"] as? Bool, true)
        let prices = try XCTUnwrap(provider["max_price"] as? [String: Double])
        XCTAssertEqual(prices["prompt"], 0.30)
        XCTAssertEqual(prices["completion"], 1.20)
        XCTAssertEqual((body["reasoning"] as? [String: Bool])?["enabled"], false)
        XCTAssertEqual(body["max_tokens"] as? Int, 4096)
    }

    func testOtherOpenRouterModelsKeepExistingRouting() async throws {
        let body = try await requestBody(model: "google/gemma-3-12b-it")
        XCTAssertNil(body["provider"])
        XCTAssertEqual(body["model"] as? String, "google/gemma-3-12b-it")
    }

    private func requestBody(model: String, webSearch: Bool = false) async throws -> [String: Any] {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RewriteRequestProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let client = OpenRouterAPI(client: OpenAICompatibleAPI(session: session))
        let result = try await client.generate("A test.", systemPrompt: "Fix grammar.", model: model, images: [], apiKey: "test-only", webSearch: webSearch).text
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any])
    }
}

private final class RewriteRequestProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            var body = request.httpBody ?? Data()
            if body.isEmpty, let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while true {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    body.append(contentsOf: buffer.prefix(count))
                }
            }
            let responseBody: [String: Any] = ["choices": [["finish_reason": "stop", "message": ["content": String(decoding: body, as: UTF8.self),
                "annotations": [["type": "url_citation", "url_citation": ["url": "https://example.com", "title": "Test"]]]]]]]
            let data = try JSONSerialization.data(withJSONObject: responseBody)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

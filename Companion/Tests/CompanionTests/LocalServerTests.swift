import XCTest
@testable import Companion

// Covers the ways a different Mac's local setup breaks Companion: other server
// addresses, other model names, slower hardware, and thinking models.
final class LocalServerTests: XCTestCase {
    func testTypedServerAddressesAreNormalized() {
        let cases: [(String, String)] = [
            ("", "http://127.0.0.1:1234"),
            ("   ", "http://127.0.0.1:1234"),
            ("localhost:1234", "http://localhost:1234"),
            ("192.168.1.20:1234/", "http://192.168.1.20:1234"),
            ("http://mac-studio.local:1234/v1", "http://mac-studio.local:1234"),
            ("http://mac-studio.local:1234/v1/", "http://mac-studio.local:1234"),
            ("https://studio.tailnet.ts.net:1234", "https://studio.tailnet.ts.net:1234"),
        ]
        for (typed, expected) in cases {
            XCTAssertEqual(UserSettings.normalizedLMStudioBaseURL(typed), expected, "input: \(typed)")
        }
        let url = try? LMStudioAPI.endpoint(baseURL: "localhost:1234/v1", path: "/v1/chat/completions")
        XCTAssertEqual(url?.absoluteString, "http://localhost:1234/v1/chat/completions")
        XCTAssertThrowsError(try LMStudioAPI.endpoint(baseURL: "not a url", path: "/v1/models"))
    }

    func testThinkingTagsNeverReachThePaste() throws {
        func response(_ content: String, reason: String? = "stop") throws -> Data {
            var choice: [String: Any] = ["message": ["content": content]]
            if let reason { choice["finish_reason"] = reason }
            return try JSONSerialization.data(withJSONObject: ["choices": [choice]])
        }
        XCTAssertEqual(try CompletionValidator.openAI(response("<think>plan the fix</think>\n\nFixed.")), "Fixed.")
        XCTAssertEqual(try CompletionValidator.openAI(response("plan the fix</think>\n\nFixed.")), "Fixed.")
        XCTAssertEqual(try CompletionValidator.openAI(response("Fixed.", reason: nil)), "Fixed.")
        XCTAssertThrowsError(try CompletionValidator.openAI(response("<think>still thinking", reason: "length"))) { error in
            guard case CompletionError.incomplete(let partial) = error else { return XCTFail("Expected incomplete") }
            XCTAssertEqual(partial, "")
        }
        XCTAssertThrowsError(try CompletionValidator.openAI(response("<think>only thoughts</think>")))
    }

    func testStaleModelNameIsExplainedInsteadOfDumpingJSON() async {
        LocalServerStub.handler = { _ in
            let body = #"{"error":{"message":"Invalid model identifier \"old-model\". Please specify a valid downloaded model.","type":"invalid_request_error","param":"model","code":"model_not_found"}}"#
            return .success((400, Data(body.utf8)))
        }
        do {
            _ = try await stubbedClient().rewrite("A test.", systemPrompt: "Fix grammar.", model: "old-model")
            XCTFail("Expected failure")
        } catch {
            XCTAssertEqual(error as? LMStudioAPI.APIError, .modelNotFound("old-model"))
            XCTAssertTrue(error.localizedDescription.contains("Refresh"))
        }
    }

    func testSlowModelLoadIsReportedAsATimeoutNotAsUnreachable() async {
        LocalServerStub.handler = { _ in .failure(URLError(.timedOut)) }
        do {
            _ = try await stubbedClient().rewrite("A test.", systemPrompt: "Fix grammar.", model: "big-model")
            XCTFail("Expected failure")
        } catch {
            guard case LMStudioAPI.APIError.timedOut(_, let seconds) = error else { return XCTFail("Got \(error)") }
            XCTAssertEqual(seconds, Int(LMStudioAPI.chatTimeout))
            XCTAssertTrue(error.localizedDescription.contains("still be loading"))
        }
        LocalServerStub.handler = { _ in .failure(URLError(.cannotConnectToHost)) }
        do {
            _ = try await stubbedClient().rewrite("A test.", systemPrompt: "Fix grammar.", model: "big-model")
            XCTFail("Expected failure")
        } catch {
            guard case LMStudioAPI.APIError.notReachable = error else { return XCTFail("Got \(error)") }
        }
    }

    func testLoadingLocalModelsPointsKeylessWritingRoutesAtTheLocalModel() {
        let defaults = UserDefaults(suiteName: "CompanionLocal-\(UUID().uuidString)")!
        let settings = UserSettings(defaults: defaults, credentials: CredentialStore(backend: MemoryCredentialBackend()))
        XCTAssertFalse(settings.adoptLocalRouteWhereCurrentIsUnavailable(), "nothing to adopt before a model list loads")
        settings.lmStudioKnownModels = ["gemma-4-12b-it", "qwen3-8b"]
        settings.lmStudioModel = "qwen3-8b"
        XCTAssertTrue(settings.adoptLocalRouteWhereCurrentIsUnavailable())
        XCTAssertEqual(settings.customPromptRouteID.flatMap { settings.modelRoute(for: $0)?.model }, "qwen3-8b")
        // A route the user can actually use is left alone.
        settings.openRouterAPIKey = "test-only"
        settings.useRecommendedWritingModel()
        XCTAssertFalse(settings.adoptLocalRouteWhereCurrentIsUnavailable())
        XCTAssertEqual(settings.customPromptRouteID.flatMap { settings.modelRoute(for: $0)?.provider }, .openRouter)
    }

    // Full dispatcher path against a real local server. Opt in with COMPANION_LOCAL_SMOKE=1;
    // COMPANION_LOCAL_MODEL picks a model, otherwise the first listed one is used.
    func testLiveLocalServerFixesGrammarThroughTheDispatcher() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["COMPANION_LOCAL_SMOKE"] == "1" else {
            throw XCTSkip("Needs a running local server; opt in with COMPANION_LOCAL_SMOKE=1")
        }
        let settings = UserSettings.shared
        if let url = environment["COMPANION_LOCAL_URL"] { settings.lmStudioBaseURL = url }
        let models = try await LMStudioAPI.shared.listModels()
        let model = try XCTUnwrap(environment["COMPANION_LOCAL_MODEL"] ?? models.first)
        settings.lmStudioKnownModels = models
        settings.lmStudioModel = model
        settings.fallbackToClaude = false
        XCTAssertTrue(settings.adoptLocalRouteWhereCurrentIsUnavailable())
        let started = Date()
        let result = try await RewriteDispatcher.shared.generate("Tomorrow I wont make it to dinner sorry maybe sunday?",
            customInstruction: "fix grammar", route: .auto, images: [])
        print("live local model \(model): \(Int(Date().timeIntervalSince(started)))s -> \(result.text)")
        XCTAssertEqual(result.provider, .lmStudio)
        XCTAssertEqual(result.model, model)
        XCTAssertTrue(result.text.localizedCaseInsensitiveContains("won't"), result.text)
        XCTAssertFalse(result.text.contains("<think>") || result.text.contains("</think>"), result.text)
    }

    private func stubbedClient() -> LMStudioAPI {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LocalServerStub.self]
        return LMStudioAPI(session: URLSession(configuration: config))
    }
}

private final class LocalServerStub: URLProtocol {
    static var handler: ((URLRequest) -> Result<(Int, Data), Error>)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        switch Self.handler?(request) ?? .failure(URLError(.unknown)) {
        case .success(let (status, data)):
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

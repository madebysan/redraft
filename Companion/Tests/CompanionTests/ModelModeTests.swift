import XCTest
@testable import Companion

final class ModelModeTests: XCTestCase {
    private func makeSettings() -> (UserSettings, UserDefaults) {
        let defaults = UserDefaults(suiteName: "CompanionModelMode-\(UUID().uuidString)")!
        let settings = UserSettings(defaults: defaults, credentials: CredentialStore(backend: MemoryCredentialBackend()))
        return (settings, defaults)
    }

    func testFreshInstallIsCloudWithRecommendedOpenRouterModel() {
        let (settings, _) = makeSettings()
        XCTAssertEqual(settings.modelMode, .cloud)
        XCTAssertEqual(settings.cloudProvider, .openRouter)
        XCTAssertEqual(settings.openRouterSelection, .recommended)
        XCTAssertEqual(settings.setupSummary, "Cloud · OpenRouter · Recommended · no key")
    }

    func testUpgradeFromLocalRoutesStartsInLocalMode() {
        let (settings, _) = makeSettings()
        settings.lmStudioKnownModels = ["qwen3-8b"]
        settings.lmStudioModel = "qwen3-8b"
        XCTAssertTrue(settings.adoptLocalRouteWhereCurrentIsUnavailable())
        XCTAssertEqual(settings.modelMode, .local)
        XCTAssertEqual(settings.setupSummary, "Local · qwen3-8b")
    }

    func testUpgradeFromAnOlderOpenRouterChoiceKeepsThatModel() {
        let (settings, defaults) = makeSettings()
        settings.openRouterAPIKey = "test-only"
        let b = UserSettings.ModelRoute(id: UserSettings.ModelRoute.makeID(provider: .openRouter, model: "x/b"),
            name: "B", provider: .openRouter, model: "x/b", supportsImages: false)
        settings.configuredModelRoutes = [b]
        settings.customPromptRouteID = b.id
        defaults.set("custom", forKey: "cloudOpenRouterModel")   // value written by a pre-release build
        XCTAssertEqual(settings.openRouterSelection, .recommended, "the retired 'custom' value reads as Recommended")
        defaults.removeObject(forKey: "cloudOpenRouterModel")
        XCTAssertEqual(settings.openRouterSelection, .model("x/b"))
        XCTAssertEqual(settings.modelMode, .cloud)
        settings.applyCloudSelection()
        XCTAssertEqual(settings.customPromptRouteID, b.id)
        XCTAssertEqual(settings.setupSummary, "Cloud · OpenRouter · x/b")
    }

    func testPickingOneCatalogModelRoutesTheCapsuleToIt() {
        let (settings, _) = makeSettings()
        settings.openRouterAPIKey = "test-only"
        settings.openRouterSelection = .model("google/gemma-4-26b-a4b-it")
        let route = settings.customPromptRouteID.flatMap { settings.modelRoute(for: $0) }
        XCTAssertEqual(route?.model, "google/gemma-4-26b-a4b-it")
        XCTAssertTrue(route?.supportsImages == true, "catalog metadata is kept")
        settings.openRouterSelection = .recommended
        XCTAssertEqual(settings.customPromptRouteID, UserSettings.recommendedInstructionRoute.id)
    }

    func testSwitchingToLocalAndBackRestoresTheCloudChoice() {
        let (settings, _) = makeSettings()
        settings.openAIAPIKey = "test-only"
        settings.cloudProvider = .openAI
        XCTAssertEqual(settings.customPromptRouteID.flatMap { settings.modelRoute(for: $0)?.provider }, .openAI)
        settings.lmStudioKnownModels = ["local-a"]
        settings.lmStudioModel = "local-a"
        settings.modelMode = .local
        XCTAssertEqual(settings.customPromptRouteID.flatMap { settings.modelRoute(for: $0)?.provider }, .lmStudio)
        XCTAssertEqual(settings.cloudProvider, .openAI, "cloud choice is remembered while local is active")
        settings.modelMode = .cloud
        XCTAssertEqual(settings.customPromptRouteID.flatMap { settings.modelRoute(for: $0)?.provider }, .openAI)
    }

    func testChangingADirectModelNameKeepsTheRouteValid() {
        let (settings, _) = makeSettings()
        settings.deepSeekAPIKey = "test-only"
        settings.cloudProvider = .deepSeek
        settings.deepSeekModel = "deepseek-v4-pro"
        settings.applyCloudSelection()
        XCTAssertEqual(settings.customPromptRouteID.flatMap { settings.modelRoute(for: $0)?.model }, "deepseek-v4-pro")
        XCTAssertEqual(settings.setupSummary, "Cloud · DeepSeek · deepseek-v4-pro")
    }

    func testLocalModeWithoutAModelIsHonestAndCloudProviderNeverBecomesLocal() {
        let (settings, _) = makeSettings()
        settings.modelMode = .local
        XCTAssertEqual(settings.modelMode, .local)
        XCTAssertEqual(settings.setupSummary, "Local · no model loaded")
        settings.cloudProvider = .lmStudio
        XCTAssertEqual(settings.cloudProvider, .openRouter)
    }

    func testFallbackPrefersTheCloudChoiceThenTheTestedOpenRouterModel() {
        let (settings, _) = makeSettings()
        XCTAssertNil(settings.cloudFallbackRoute)
        settings.claudeAPIKeyForTests("test-only")
        settings.cloudProvider = .claude
        XCTAssertEqual(settings.cloudFallbackRoute?.provider, .claude)
        settings.cloudProvider = .openAI   // no OpenAI key saved
        settings.openRouterAPIKey = "test-only"
        XCTAssertEqual(settings.cloudFallbackRoute, UserSettings.recommendedWritingRoute)
    }

    func testKeyCheckRequestsAreReadOnlyAndCarryTheRightHeaders() throws {
        let openRouter = try XCTUnwrap(ProviderKeyCheck.request(provider: .openRouter, key: "k1"))
        XCTAssertEqual(openRouter.httpMethod, "GET")
        XCTAssertEqual(openRouter.url?.absoluteString, "https://openrouter.ai/api/v1/auth/key")
        XCTAssertEqual(openRouter.value(forHTTPHeaderField: "Authorization"), "Bearer k1")
        let claude = try XCTUnwrap(ProviderKeyCheck.request(provider: .claude, key: "k2"))
        XCTAssertEqual(claude.value(forHTTPHeaderField: "x-api-key"), "k2")
        XCTAssertNotNil(claude.value(forHTTPHeaderField: "anthropic-version"))
        XCTAssertNil(ProviderKeyCheck.request(provider: .fal, key: "k3"))
        XCTAssertNil(ProviderKeyCheck.request(provider: .lmStudio, key: "k4"))
    }
}

private extension UserSettings {
    func claudeAPIKeyForTests(_ value: String) { apiKey = value }
}

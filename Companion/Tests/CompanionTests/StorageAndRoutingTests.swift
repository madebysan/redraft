import XCTest
@testable import Companion

final class StorageAndRoutingTests: XCTestCase {
    func testRequestTimingPersistsAndOldHistoryStillDecodes() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("CompanionTimingTests-\(UUID().uuidString)")
        let store = GenerationHistoryStore(directory: folder)
        try await store.add(result: "Test result", actionLabel: "Fix Grammar", provider: .openRouter,
            model: "test", selectedWordCount: 2, imageFileNames: [], requestDurationSeconds: 1.25)
        let entries = try await store.entries()
        XCTAssertEqual(entries.first?.requestDurationSeconds, 1.25)
        let legacy: [String: Any] = ["id": UUID().uuidString, "createdAt": "2026-09-15T12:00:00Z",
            "actionLabel": "Fix Grammar", "provider": "OpenRouter", "model": "test",
            "selectedWordCount": 2, "hadImages": false, "imageFileNames": [String](), "result": "Old result"]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let oldEntry = try decoder.decode(GenerationHistoryStore.Entry.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(oldEntry.requestDurationSeconds)
    }

    private func isolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "CompanionTests-\(UUID().uuidString)")!
    }

    func testCredentialsMigrateOnlyAfterVerifiedWriteAndDoNotOverwriteSecureValue() throws {
        let defaults = isolatedDefaults()
        let backend = MemoryCredentialBackend()
        let store = CredentialStore(backend: backend)
        defaults.set("test-only-value", forKey: "key")
        try store.migrate(accounts: ["key"], from: defaults)
        XCTAssertNil(defaults.string(forKey: "key"))
        XCTAssertEqual(try store.value(for: "key"), "test-only-value")
        defaults.set("stale-value", forKey: "key")
        try store.migrate(accounts: ["key"], from: defaults)
        XCTAssertEqual(try store.value(for: "key"), "test-only-value")
        try store.set("", for: "key")
        XCTAssertEqual(try store.value(for: "key"), "")
    }

    func testFailedKeychainVerificationPreservesLegacyCredential() {
        struct FailingBackend: CredentialBackend {
            func read(_ account: String) throws -> String? { nil }
            func write(_ value: String, account: String) throws { }
            func remove(_ account: String) throws { }
        }
        let defaults = isolatedDefaults()
        defaults.set("test-only-value", forKey: "key")
        let store = CredentialStore(backend: FailingBackend())
        XCTAssertThrowsError(try store.migrate(accounts: ["key"], from: defaults))
        XCTAssertEqual(defaults.string(forKey: "key"), "test-only-value")
    }

    func testWritingMigrationKeepsTheChosenRouteAndExportsRetiredActionsOnce() throws {
        let defaults = isolatedDefaults()
        let backend = MemoryCredentialBackend()
        let credentials = CredentialStore(backend: backend)
        let route = UserSettings.ModelRoute.makeID(provider: .claude, model: UserSettings.defaultClaudeModel)
        let actions = [
            ["id": "fix_grammar", "name": "My grammar", "prompt": "My edited grammar prompt",
             "provider": "claude", "symbolName": "star", "routeID": route],
            ["id": "my-action", "name": "Private custom action", "prompt": "Do my thing",
             "provider": "claude", "symbolName": "star", "routeID": "custom-route"]
        ]
        let original = try JSONSerialization.data(withJSONObject: actions)
        defaults.set(original, forKey: "savedActions")
        defaults.set("Existing one-off prompt route", forKey: "customPromptRouteID")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("WritingRecovery-\(UUID().uuidString)")
        let settings = UserSettings(defaults: defaults, credentials: credentials, recoveryDirectory: directory)
        XCTAssertNil(settings.writingMigrationError)
        XCTAssertNil(defaults.string(forKey: "grammarPrompt"), "the grammar prompt is retired, not carried over")
        XCTAssertEqual(defaults.string(forKey: "customPromptRouteID"), "Existing one-off prompt route",
            "an existing Capsule route wins over the legacy grammar route (\(route))")
        XCTAssertNil(defaults.data(forKey: "savedActions"))
        let recovery = try XCTUnwrap(settings.retiredActionsRecoveryURL)
        let export = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: recovery)) as? [String: Any])
        XCTAssertEqual(export["originalSavedActionsDataBase64"] as? String, original.base64EncodedString())
        XCTAssertEqual((export["savedActions"] as? [[String: String]])?.last?["prompt"], "Do my thing")
        XCTAssertNil(export["apiKey"])

        settings.apiKey = "dummy-claude"
        XCTAssertNil(settings.cloudFallbackRoute)
        settings.openRouterAPIKey = "dummy-openrouter"
        XCTAssertEqual(settings.cloudFallbackRoute, UserSettings.recommendedWritingRoute)
        settings.customPromptRouteID = UserSettings.recommendedWritingRoute.id
        let relaunched = UserSettings(defaults: defaults, credentials: credentials, recoveryDirectory: directory)
        XCTAssertEqual(relaunched.customPromptRouteID, UserSettings.recommendedWritingRoute.id)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 1)
        relaunched.useRecommendedWritingModel()
        XCTAssertEqual(relaunched.customPromptRouteID, UserSettings.recommendedInstructionRoute.id)
    }

    func testRecoveryFailureDoesNotRemoveOrMigrateOldPreferences() throws {
        let defaults = isolatedDefaults()
        defaults.set("Original grammar prompt", forKey: "rewritePrompt")
        let blocked = FileManager.default.temporaryDirectory.appendingPathComponent("WritingRecoveryBlocked-\(UUID().uuidString)")
        try Data("Not a directory".utf8).write(to: blocked)
        let settings = UserSettings(defaults: defaults, credentials: CredentialStore(backend: MemoryCredentialBackend()), recoveryDirectory: blocked)
        XCTAssertNotNil(settings.writingMigrationError)
        XCTAssertEqual(defaults.string(forKey: "rewritePrompt"), "Original grammar prompt")
        XCTAssertNil(defaults.string(forKey: "grammarPrompt"))
        XCTAssertFalse(defaults.bool(forKey: "didMigrateWritingSettings"))
    }

    func testLegacyGrammarOnlySettingsMigrateWithoutSavedActions() {
        let defaults = isolatedDefaults()
        defaults.set("Legacy grammar prompt", forKey: "rewritePrompt")
        defaults.set("deepseek", forKey: "providerFixGrammar")
        defaults.set("old humanizer customization", forKey: "humanizePrompt")
        let settings = UserSettings(defaults: defaults, credentials: CredentialStore(backend: MemoryCredentialBackend()))
        XCTAssertNil(settings.writingMigrationError)
        XCTAssertEqual(settings.customPromptRouteID, UserSettings.ModelRoute.makeID(provider: .deepSeek, model: UserSettings.defaultDeepSeekModel),
            "the provider the old grammar action ran on becomes the single Capsule model")
        XCTAssertNil(defaults.object(forKey: "humanizePrompt"))
        XCTAssertNotNil(settings.retiredActionsRecoveryURL)
    }

    func testMalformedActionsRemainRecoverableWithoutFinishingMigration() {
        let defaults = isolatedDefaults()
        let original = Data("incomplete old data".utf8)
        defaults.set(original, forKey: "savedActions")
        let settings = UserSettings(defaults: defaults, credentials: CredentialStore(backend: MemoryCredentialBackend()))
        XCTAssertNotNil(settings.writingMigrationError)
        XCTAssertEqual(defaults.data(forKey: "savedActions"), original)
        XCTAssertFalse(defaults.bool(forKey: "didMigrateWritingSettings"))
    }

    func testCatalogRefreshUsesAgeInsteadOfModelCount() {
        let defaults = isolatedDefaults()
        let settings = UserSettings(defaults: defaults, credentials: CredentialStore(backend: MemoryCredentialBackend()))
        XCTAssertTrue(settings.remoteCatalogNeedsRefresh())
        settings.remoteCatalogModels = [.init(id: "test/model", name: "Test", supportsImages: false)]
        XCTAssertFalse(settings.remoteCatalogNeedsRefresh())
        XCTAssertTrue(settings.remoteCatalogNeedsRefresh(now: Date().addingTimeInterval(86_401)))
    }

    func testHistoryPreservesArchiveAndWritesIndividualResults() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("CompanionHistoryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let original = Data("[]".utf8)
        try original.write(to: folder.appendingPathComponent("history.json"))
        let store = GenerationHistoryStore(directory: folder)
        for index in 0..<502 {
            try await store.add(result: "Result \(index)", actionLabel: "Test", provider: .openRouter,
                                model: "test", selectedWordCount: 1, imageFileNames: [])
        }
        let entries = try await store.entries()
        XCTAssertEqual(entries.count, 500)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("history.json")), original)
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent("entries").path)
        XCTAssertEqual(files.count, 502, "The UI limit must not delete older records")
        try await store.clear()
        let cleared = try await store.entries()
        XCTAssertTrue(cleared.isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: folder.path).contains { $0.hasPrefix("cleared-") })
    }
}

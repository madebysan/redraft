import XCTest
@testable import Companion

final class ModelRoutingTests: XCTestCase {
    func testCatalogModelUsesFalDocumentedModelID() {
        let model = UserSettings.RemoteCatalogModel(
            id: "google/gemma-4-26b-a4b-it",
            name: "Gemma 4",
            supportsImages: true
        )

        XCTAssertEqual(model.routeModel, "google/gemma-4-26b-a4b-it")
    }

    func testLegacyTildePrefixIsRemoved() {
        XCTAssertEqual(
            UserSettings.canonicalFalModel("~deepseek/deepseek-v4-pro"),
            "deepseek/deepseek-v4-pro"
        )
    }

    func testRetiredClaudeAliasesMigrateToCurrentModels() {
        XCTAssertEqual(
            UserSettings.canonicalFalModel("~anthropic/claude-sonnet-latest"),
            "anthropic/claude-sonnet-5"
        )
        XCTAssertEqual(
            UserSettings.canonicalFalModel("anthropic/claude-haiku-latest"),
            "anthropic/claude-haiku-4.5"
        )
    }
}

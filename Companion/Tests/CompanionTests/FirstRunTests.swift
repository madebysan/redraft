import AppKit
import XCTest
@testable import Companion

final class FirstRunTests: XCTestCase {
    @MainActor
    func testTypingAPIKeyEnablesGetStartedWithoutAnExtraReturn() {
        let onboarding = OnboardingWindow()
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let views = descendants(onboarding.window!.contentView!)
        let field = views.compactMap { $0 as? NSSecureTextField }.first!
        let start = views.compactMap { $0 as? NSButton }.first { $0.title == "Get Started" }!
        XCTAssertFalse(start.isEnabled)
        XCTAssertTrue(field.delegate === onboarding)
        field.stringValue = "test-only-key"
        onboarding.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        XCTAssertTrue(start.isEnabled)
    }

    func testChoosingProviderDuringSetupRoutesBothActionsToThatProvider() {
        for provider in [UserSettings.Provider.openAI, .claude, .fal, .openRouter] {
            let defaults = UserDefaults(suiteName: "CompanionFirstRun-\(UUID().uuidString)")!
            let settings = UserSettings(defaults: defaults, credentials: CredentialStore(backend: MemoryCredentialBackend()))
            XCTAssertTrue(settings.useWritingProvider(provider))
            XCTAssertEqual(settings.modelRoute(for: settings.grammarRouteID)?.provider, provider)
            XCTAssertEqual(settings.customPromptRouteID.flatMap { settings.modelRoute(for: $0)?.provider }, provider)
        }
    }

    func testLocalSetupCannotPretendACloudDefaultIsAConfiguredLocalModel() {
        let defaults = UserDefaults(suiteName: "CompanionFirstRun-\(UUID().uuidString)")!
        let settings = UserSettings(defaults: defaults, credentials: CredentialStore(backend: MemoryCredentialBackend()))
        XCTAssertFalse(settings.useWritingProvider(.lmStudio))
        settings.lmStudioModel = "local-model"
        XCTAssertTrue(settings.useWritingProvider(.lmStudio))
        XCTAssertEqual(settings.modelRoute(for: settings.grammarRouteID)?.provider, .lmStudio)
        XCTAssertEqual(settings.customPromptRouteID.flatMap { settings.modelRoute(for: $0)?.provider }, .lmStudio)
    }
}

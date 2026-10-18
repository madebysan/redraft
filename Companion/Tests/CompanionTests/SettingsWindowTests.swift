import AppKit
import XCTest
@testable import Companion

final class SettingsWindowTests: XCTestCase {
    func testHistorySwitchDefaultsOnAndPersistsOff() {
        let defaults = UserDefaults(suiteName: "CompanionHistory-\(UUID().uuidString)")!
        let credentials = CredentialStore(backend: MemoryCredentialBackend())
        let settings = UserSettings(defaults: defaults, credentials: credentials)
        XCTAssertTrue(settings.saveHistory, "existing installs keep saving without a migration")
        settings.saveHistory = false
        XCTAssertFalse(UserSettings(defaults: defaults, credentials: credentials).saveHistory)
    }

    @MainActor
    func testCatalogGroupsByVendorAndSortsTitles() {
        let models = [
            UserSettings.RemoteCatalogModel(id: "google/gemini-3.5-flash-lite", name: "Google: Gemini 3.5 Flash Lite", supportsImages: true),
            UserSettings.RemoteCatalogModel(id: "aion-labs/aion-3.5", name: "AionLabs: Aion 3.5", supportsImages: false),
            UserSettings.RemoteCatalogModel(id: "aion-labs/aion-2.0", name: "AionLabs: Aion-2.0", supportsImages: false),
            UserSettings.RemoteCatalogModel(id: "mistralai/mistral-small", name: "", supportsImages: false),
        ]
        let groups = ModelsSettingsPane.catalogGroups(models)
        XCTAssertEqual(groups.map(\.vendor), ["AionLabs", "Google", "mistralai"])
        XCTAssertEqual(groups[0].models.map(\.title), ["Aion 3.5", "Aion-2.0"])
        XCTAssertEqual(groups[2].models.first?.title, "mistralai/mistral-small", "a nameless model shows its id")
        XCTAssertTrue(groups[1].models[0].supportsImages)
    }

    @MainActor
    func testSettingsAndHistoryWindowsBuildWithoutASidebar() {
        let settings = SettingsWindow()
        defer { settings.close() }
        func views(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(views) }
        let all = views(settings.window!.contentView!)
        XCTAssertTrue(all.allSatisfy { !($0 is NSSplitView) }, "one page, no sidebar")
        let titles = all.compactMap { $0 as? NSButton }.map(\.title)
        XCTAssertTrue(titles.contains("Keep a history of results on this Mac"))
        XCTAssertTrue(titles.contains("Show History…"))
        XCTAssertFalse(titles.contains("Check key"), "the key is checked automatically")
        let history = HistoryWindow()
        defer { history.close() }
        XCTAssertEqual(history.window?.title, "Redraft History")
    }

    @MainActor
    func testMenuBarMenuIsUseConfigureAppQuitWithTheShortcutShown() {
        let controller = StatusBarController(appDelegate: AppDelegate())
        controller.setup()
        defer { if let item = controller.statusItem { NSStatusBar.system.removeStatusItem(item) } }
        let menu = try! XCTUnwrap(controller.statusItem?.menu)
        let visible = menu.items.filter { !$0.isSeparatorItem && !$0.isHidden }.map(\.title)
        XCTAssertEqual(visible.first, "Redraft Selection")
        XCTAssertTrue(visible.contains { $0.hasPrefix("Model: ") })
        let order = visible.filter { !$0.hasPrefix("Model: ") && $0 != "Check for Updates…" }
        XCTAssertEqual(order, ["Redraft Selection", "History…", "Settings…", "About Redraft", "Quit Redraft"])
        XCTAssertFalse(visible.contains { $0.hasPrefix("Status:") || $0.hasPrefix("Using:") || $0.contains("Palette") })
        // macOS adds its own symbols to the standard Settings and Quit items; ours carry none.
        let ours = menu.items.filter { ["Redraft Selection", "History…", "About Redraft"].contains($0.title) || $0.title.hasPrefix("Model: ") }
        XCTAssertEqual(ours.count, 4)
        XCTAssertTrue(ours.allSatisfy { $0.image == nil }, "no custom icons in the menu")
        let rewrite = menu.items[0]
        XCTAssertEqual(rewrite.keyEquivalent, "e")
        XCTAssertEqual(rewrite.keyEquivalentModifierMask, [.command, .shift])
        let model = try! XCTUnwrap(menu.items.first { $0.title.hasPrefix("Model: ") }?.submenu)
        XCTAssertEqual(model.items.filter { !$0.isSeparatorItem }.map(\.title).last, "Change in Settings…")
        XCTAssertEqual(model.items.filter { $0.state == .on }.count, 1, "exactly one mode is checked")
    }
}

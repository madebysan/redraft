import AppKit
import Sparkle

// In-app updates. The feed lives on the repo's GitHub Releases (Info.plist
// SUFeedURL). Started only from a bundle that has a feed URL, so `swift run`
// and tests don't show Sparkle's "failed to start" alert.
enum Updates {
    static let controller = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil
    )

    static func start() {
        if Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil {
            controller.startUpdater()
        }
    }

    static func menuItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        item.target = controller
        return item
    }
}

import AppKit

// Manages the menu bar icon and dropdown menu
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private(set) var statusItem: NSStatusItem?
    private weak var appDelegate: AppDelegate?
    private var animationTimer: Timer?
    private var statusMenuItem: NSMenuItem?
    private var setupMenuItem: NSMenuItem?
    private var rewriteMenuItem: NSMenuItem?
    private var hasPermissionWarning = false

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        super.init()
    }

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            setDefaultIcon(button)
        }

        let menu = NSMenu()

        // The same thing as the shortcut; its key equivalent mirrors the saved shortcut.
        rewriteMenuItem = NSMenuItem(title: "Redraft Selection", action: #selector(triggerRewrite), keyEquivalent: "")
        rewriteMenuItem?.target = self
        menu.addItem(rewriteMenuItem!)
        syncShortcutEquivalent()

        menu.addItem(NSMenuItem.separator())

        // Shown only while Accessibility is missing; everything else is hidden behind the icon.
        statusMenuItem = NSMenuItem(title: "Accessibility needed. Open System Settings…",
            action: #selector(openAccessibilitySettings), keyEquivalent: "")
        statusMenuItem?.target = self
        statusMenuItem?.isHidden = Permissions.isGranted
        menu.addItem(statusMenuItem!)

        // Local or Cloud, switchable here; details live in Settings.
        setupMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        setupMenuItem?.submenu = NSMenu(title: "Model")
        menu.addItem(setupMenuItem!)
        syncModelMenu()

        let historyItem = NSMenuItem(title: "History…", action: #selector(AppDelegate.openHistory), keyEquivalent: "")
        historyItem.target = appDelegate
        menu.addItem(historyItem)

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(AppDelegate.openSettings), keyEquivalent: ",")
        settingsItem.target = appDelegate
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        if let updates = Updates.menuItem() { menu.addItem(updates) }
        let aboutItem = NSMenuItem(title: "About Redraft", action: #selector(AppDelegate.openAbout), keyEquivalent: "")
        aboutItem.target = appDelegate
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(
            title: "Quit Redraft",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        menu.delegate = self
        statusItem?.menu = menu

        // Show warning icon if permissions missing on launch
        if !Permissions.isGranted {
            hasPermissionWarning = true
            if let button = statusItem?.button {
                setWarningIcon(button)
            }
        }

        // Listen for rewrite status changes
        TextGrabber.shared.onStatusChange = { [weak self] status in
            self?.handleStatus(status)
        }
    }

    // Recheck permissions every time the menu opens so state stays fresh
    // after the user grants permissions in System Settings.
    nonisolated func menuWillOpen(_ menu: NSMenu) {
        Task { @MainActor in
            self.showPermissionWarning(!Permissions.isGranted)
            self.syncModelMenu()
            self.syncShortcutEquivalent()
        }
    }

    private func syncShortcutEquivalent() {
        let settings = UserSettings.shared
        if let keyCode = settings.shortcutKeyCode, let modifiers = settings.shortcutModifiers,
           let name = SettingsWindow.keyName(for: UInt16(keyCode)) {
            rewriteMenuItem?.keyEquivalent = name.lowercased()
            rewriteMenuItem?.keyEquivalentModifierMask = NSEvent.ModifierFlags(rawValue: modifiers)
                .intersection([.command, .shift, .option, .control])
        } else {
            rewriteMenuItem?.keyEquivalent = "e"
            rewriteMenuItem?.keyEquivalentModifierMask = [.command, .shift]
        }
    }

    private func syncModelMenu() {
        let settings = UserSettings.shared
        setupMenuItem?.title = "Model: \(settings.menuSummary(for: settings.modelMode))"
        guard let submenu = setupMenuItem?.submenu else { return }
        submenu.removeAllItems()
        for mode in UserSettings.ModelMode.allCases {
            let item = NSMenuItem(title: settings.menuSummary(for: mode), action: #selector(chooseMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = settings.modelMode == mode ? .on : .off
            if mode == .local, settings.lmStudioKnownModels.isEmpty, settings.modelMode != .local {
                item.title = "Local · set up in Settings"
                item.isEnabled = false
            }
            submenu.addItem(item)
        }
        submenu.addItem(.separator())
        let change = NSMenuItem(title: "Change in Settings…", action: #selector(AppDelegate.openSettings), keyEquivalent: "")
        change.target = appDelegate
        submenu.addItem(change)
    }

    @objc private func chooseMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = UserSettings.ModelMode(rawValue: raw) else { return }
        UserSettings.shared.modelMode = mode
        syncModelMenu()
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func showPermissionWarning(_ show: Bool) {
        hasPermissionWarning = show
        guard let button = statusItem?.button else { return }

        statusMenuItem?.isHidden = !show
        if show { setWarningIcon(button) } else { setDefaultIcon(button) }
    }


    @objc private func triggerRewrite() {
        TextGrabber.shared.grabSelectionAndShowPalette()
    }

    private func setDefaultIcon(_ button: NSStatusBarButton) {
        if let image = NSImage(systemSymbolName: "sparkle.magnifyingglass", accessibilityDescription: "Redraft") {
            image.isTemplate = true
            button.image = image
        } else {
            button.title = "R"
        }
    }

    private func setWarningIcon(_ button: NSStatusBarButton) {
        if let image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Redraft — missing permissions") {
            image.isTemplate = true
            button.image = image
        }
    }

    private func handleStatus(_ status: TextGrabber.RewriteStatus) {
        guard let button = statusItem?.button else { return }

        switch status {
        case .rewriting:
            startAnimation(button)
        case .done:
            stopAnimation(button)
        case .error:
            stopAnimation(button)
            // Brief flash to red to indicate failure
            if let errorImage = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Error") {
                errorImage.isTemplate = true
                button.image = errorImage
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    self?.setDefaultIcon(button)
                }
            }
        }
    }

    private func startAnimation(_ button: NSStatusBarButton) {
        // Cycle through ellipsis-style SF Symbols to show activity
        let frames = ["ellipsis", "ellipsis.circle", "ellipsis.circle.fill"]
        var frameIndex = 0

        animationTimer?.invalidate()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            guard self != nil else { return }
            if let image = NSImage(systemSymbolName: frames[frameIndex % frames.count], accessibilityDescription: "Rewriting...") {
                image.isTemplate = true
                button.image = image
            }
            frameIndex += 1
        }
    }

    private func stopAnimation(_ button: NSStatusBarButton) {
        animationTimer?.invalidate()
        animationTimer = nil
        if hasPermissionWarning {
            setWarningIcon(button)
        } else {
            setDefaultIcon(button)
        }
    }
}

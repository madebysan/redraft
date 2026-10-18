import AppKit
import Carbon.HIToolbox
import ServiceManagement

private final class FlippedPaneDocumentView: NSView {
    override var isFlipped: Bool { true }
}

// Settings is one page: the model (Local or Cloud) on top, then shortcut, launch at login and
// history. Accessibility appears only while it is missing. About holds version and credits.
final class SettingsWindow: NSWindowController, NSWindowDelegate {
    private var modelsPane: ModelsSettingsPane!
    private var launchAtLoginCheckbox: NSButton!
    private var historyCheckbox: NSButton!
    private var shortcutLabel: NSTextField!
    private var shortcutHint: NSTextField!
    private var shortcutMonitor: Any?
    private var permissionRow: NSView!

    private let labelWidth: CGFloat = 110

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 600, height: 560)),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Redraft Settings"
        window.minSize = NSSize(width: 560, height: 420)
        window.setFrameAutosaveName("CompanionSettingsWindow")
        window.center()
        window.isReleasedWhenClosed = false
        self.init(window: window)
        window.delegate = self
        setupUI()
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        refresh()
    }

    // Re-read anything that can change while the window is closed or another app is in front.
    func refresh() {
        modelsPane.paneDidAppear()
        permissionRow.isHidden = Permissions.isGranted
        launchAtLoginCheckbox.state = UserSettings.shared.launchAtLogin ? .on : .off
        historyCheckbox.state = UserSettings.shared.saveHistory ? .on : .off
    }

    func windowDidBecomeKey(_ notification: Notification) { refresh() }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        contentView.addSubview(scrollView)

        let container = FlippedPaneDocumentView()
        container.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = container

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 16
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            container.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -22),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
        ])

        if let error = UserSettings.shared.writingMigrationError {
            let warning = makeHelpLabel(error)
            warning.textColor = .systemOrange
            stack.addArrangedSubview(warning)
        }

        modelsPane = ModelsSettingsPane()
        stack.addArrangedSubview(modelsPane.view)
        modelsPane.view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let options = makeBox { section in
            shortcutLabel = NSTextField(labelWithString: currentShortcutLabel())
            shortcutLabel.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
            let change = makeSmallButton("Change…", action: #selector(recordShortcut))
            let shortcutControl = NSStackView(views: [shortcutLabel, change])
            shortcutControl.orientation = .horizontal
            shortcutControl.alignment = .centerY
            shortcutControl.spacing = 10
            section.addArrangedSubview(makeRow(label: "Shortcut", control: shortcutControl))
            shortcutHint = makeHelpLabel("Opens the Capsule from any app; press it again to close.")
            section.addArrangedSubview(makeRow(label: "", control: shortcutHint))

            launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch Redraft at login", target: self, action: #selector(toggleLaunchAtLogin))
            section.addArrangedSubview(makeRow(label: "", control: launchAtLoginCheckbox))

            historyCheckbox = NSButton(checkboxWithTitle: "Keep a history of results on this Mac", target: self, action: #selector(toggleHistory))
            let show = makeSmallButton("Show History…", action: #selector(showHistory))
            let historyControl = NSStackView(views: [historyCheckbox, show])
            historyControl.orientation = .horizontal
            historyControl.alignment = .centerY
            historyControl.spacing = 12
            section.addArrangedSubview(makeRow(label: "", control: historyControl))
        }
        stack.addArrangedSubview(options)
        options.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        permissionRow = makePermissionRow()
        stack.addArrangedSubview(permissionRow)
        permissionRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    // MARK: Rows

    private func makeBox(build: (NSStackView) -> Void) -> NSView {
        let box = NSBox()
        box.translatesAutoresizingMaskIntoConstraints = false
        box.boxType = .custom
        box.titlePosition = .noTitle
        box.borderColor = .separatorColor
        box.borderWidth = 1
        box.cornerRadius = 8
        box.fillColor = .controlBackgroundColor
        let section = NSStackView()
        section.translatesAutoresizingMaskIntoConstraints = false
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 10
        box.addSubview(section)
        build(section)
        NSLayoutConstraint.activate([
            section.topAnchor.constraint(equalTo: box.topAnchor, constant: 14),
            section.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 14),
            section.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -14),
            section.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -14),
        ])
        return box
    }

    private func makeRow(label: String, control: NSView) -> NSStackView {
        let row = NSStackView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        let labelField = NSTextField(labelWithString: label)
        labelField.font = .systemFont(ofSize: 12)
        labelField.textColor = .secondaryLabelColor
        labelField.alignment = .right
        labelField.widthAnchor.constraint(equalToConstant: labelWidth).isActive = true
        labelField.setContentHuggingPriority(.required, for: .horizontal)
        row.addArrangedSubview(labelField)
        row.addArrangedSubview(control)
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return row
    }

    private func makeHelpLabel(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .tertiaryLabelColor
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.widthAnchor.constraint(lessThanOrEqualToConstant: 440).isActive = true
        return label
    }

    private func makeSmallButton(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .small
        return button
    }

    // Shown only while Accessibility is missing; Redraft can't copy or paste without it.
    private func makePermissionRow() -> NSView {
        let box = NSBox()
        box.translatesAutoresizingMaskIntoConstraints = false
        box.boxType = .custom
        box.titlePosition = .noTitle
        box.borderColor = .systemOrange.withAlphaComponent(0.6)
        box.borderWidth = 1
        box.cornerRadius = 8
        box.fillColor = .controlBackgroundColor

        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
        icon.contentTintColor = .systemOrange
        let text = NSTextField(wrappingLabelWithString: "Accessibility is off. Redraft can't copy the selection or paste the result until it's granted in System Settings → Privacy & Security.")
        text.font = .systemFont(ofSize: 12)
        text.maximumNumberOfLines = 0
        let button = makeSmallButton("Open System Settings", action: #selector(openAccessibilitySettings))
        let row = NSStackView(views: [icon, text, button])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        text.setContentHuggingPriority(.defaultLow, for: .horizontal)
        box.addSubview(row)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),
            row.topAnchor.constraint(equalTo: box.topAnchor, constant: 12),
            row.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -14),
            row.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -12),
        ])
        box.isHidden = Permissions.isGranted
        return box
    }

    // MARK: Actions

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func showHistory() {
        (NSApp.delegate as? AppDelegate)?.openHistory()
    }

    @objc private func toggleHistory() {
        UserSettings.shared.saveHistory = historyCheckbox.state == .on
    }

    @objc private func toggleLaunchAtLogin() {
        let enabled = launchAtLoginCheckbox.state == .on
        UserSettings.shared.launchAtLogin = enabled
        if #available(macOS 13.0, *) {
            do {
                if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Failed to update launch at login: \(error)")
            }
        }
    }

    // Change…: press the new keys. Delete restores ⌘⇧E, Escape keeps the current one.
    @objc private func recordShortcut() {
        stopRecording()
        shortcutLabel.stringValue = "Press keys…"
        shortcutLabel.textColor = .systemOrange
        shortcutHint.stringValue = "Press the new shortcut. Delete restores ⌘⇧E; Escape keeps the current one."

        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
            if event.keyCode == kVK_Escape {
                self.finishRecording()
                return nil
            }
            if event.keyCode == kVK_Delete || event.keyCode == kVK_ForwardDelete {
                HotkeyManager.shared.resetToDefault()
                self.finishRecording()
                return nil
            }
            guard !mods.isEmpty else { return event }
            HotkeyManager.shared.updateShortcut(keyCode: UInt32(event.keyCode), modifiers: mods)
            self.finishRecording()
            return nil
        }
    }

    private func finishRecording() {
        stopRecording()
        shortcutLabel.stringValue = currentShortcutLabel()
        shortcutLabel.textColor = .labelColor
        shortcutHint.stringValue = "Opens the Capsule from any app; press it again to close."
    }

    private func stopRecording() {
        if let monitor = shortcutMonitor {
            NSEvent.removeMonitor(monitor)
            shortcutMonitor = nil
        }
    }

    private func currentShortcutLabel() -> String {
        let settings = UserSettings.shared
        guard let keyCode = settings.shortcutKeyCode, let modifiers = settings.shortcutModifiers else {
            return "Shift + Cmd + E"
        }
        return Self.formatShortcut(modifiers: NSEvent.ModifierFlags(rawValue: modifiers), keyCode: UInt16(keyCode))
    }

    static func formatShortcut(modifiers: NSEvent.ModifierFlags, keyCode: UInt16) -> String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("Ctrl") }
        if modifiers.contains(.option) { parts.append("Opt") }
        if modifiers.contains(.shift) { parts.append("Shift") }
        if modifiers.contains(.command) { parts.append("Cmd") }
        parts.append(keyName(for: keyCode) ?? "Key(\(keyCode))")
        return parts.joined(separator: " + ")
    }

    static func keyName(for keyCode: UInt16) -> String? {
        let letters: [Int: String] = [
            kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E", kVK_ANSI_F: "F",
            kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
            kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R",
            kVK_ANSI_S: "S", kVK_ANSI_T: "T", kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
            kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
        ]
        return letters[Int(keyCode)]
    }

    func windowWillClose(_ notification: Notification) {
        stopRecording()
    }
}

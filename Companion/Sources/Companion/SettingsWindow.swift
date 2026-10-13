import AppKit
import Carbon.HIToolbox
import ServiceManagement

private final class FlippedPaneDocumentView: NSView {
    override var isFlipped: Bool { true }
}

private let settingsDefaultWindowSize = NSSize(width: 740, height: 520)
private let settingsMinimumWindowSize = NSSize(width: 700, height: 420)
private let settingsPreferredMaximumWindowSize = NSSize(width: 780, height: 620)
private let settingsWindowScreenMargin: CGFloat = 64

// Settings window: general, models (Local or Cloud), writing, history, shortcut, permissions.
final class SettingsWindow: NSWindowController, NSWindowDelegate {
    private struct SettingsPaneItem {
        let title: String
        let symbolName: String
        let view: NSView
    }

    private var modelsPane: ModelsSettingsPane!
    private var launchAtLoginCheckbox: NSButton!
    private var paletteDefaultViewPopup: NSPopUpButton!
    private var shortcutLabel: NSTextField!
    private var shortcutMonitor: Any?
    private var permissionsStack: NSStackView!
    private var sidebarTable: NSTableView!
    private var paneContainer: NSView!
    private var paneItems: [SettingsPaneItem] = []
    private var currentPaneConstraints: [NSLayoutConstraint] = []
    private var historyEntries: [GenerationHistoryStore.Entry] = []
    private var historyLoadTask: Task<Void, Never>?
    private var historyTable: NSTableView!
    private var historyResultView: NSTextView!
    private var historyMetadataLabel: NSTextField!
    private var copyHistoryButton: NSButton!

    private let labelWidth: CGFloat = 126

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: settingsDefaultWindowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Companion Settings"
        window.minSize = settingsMinimumWindowSize
        window.setFrameAutosaveName("CompanionSettingsWindow")
        window.center()
        window.isReleasedWhenClosed = false
        self.init(window: window)
        window.delegate = self
        setupUI()
        fitWindowToVisibleScreen()
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        fitWindowToVisibleScreen()
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        paneItems = [
            SettingsPaneItem(title: "General", symbolName: "gearshape", view: makeGeneralPane()),
            SettingsPaneItem(title: "Models", symbolName: "cpu", view: makeModelsPane()),
            SettingsPaneItem(title: "History", symbolName: "clock.arrow.circlepath", view: makeHistoryPane()),
            SettingsPaneItem(title: "Shortcut", symbolName: "keyboard", view: makeShortcutPane()),
            SettingsPaneItem(title: "Permissions", symbolName: "hand.raised", view: makePermissionsPane()),
        ]

        let splitView = NSSplitView()
        splitView.translatesAutoresizingMaskIntoConstraints = false
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        contentView.addSubview(splitView)

        let sidebarScroll = NSScrollView()
        sidebarScroll.translatesAutoresizingMaskIntoConstraints = false
        sidebarScroll.drawsBackground = false
        sidebarScroll.hasVerticalScroller = false
        sidebarScroll.borderType = .noBorder

        sidebarTable = NSTableView()
        sidebarTable.headerView = nil
        sidebarTable.rowHeight = 34
        sidebarTable.intercellSpacing = NSSize(width: 0, height: 2)
        sidebarTable.backgroundColor = .clear
        sidebarTable.style = .sourceList
        sidebarTable.delegate = self
        sidebarTable.dataSource = self

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("pane"))
        column.resizingMask = .autoresizingMask
        sidebarTable.addTableColumn(column)
        sidebarScroll.documentView = sidebarTable

        paneContainer = NSView()
        paneContainer.translatesAutoresizingMaskIntoConstraints = false

        splitView.addArrangedSubview(sidebarScroll)
        splitView.addArrangedSubview(paneContainer)

        sidebarTable.reloadData()
        sidebarTable.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        showPane(at: 0)

        NSLayoutConstraint.activate([
            splitView.topAnchor.constraint(equalTo: contentView.topAnchor),
            splitView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            splitView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            sidebarScroll.widthAnchor.constraint(equalToConstant: 168),
        ])
    }

    func selectPane(named title: String) {
        guard let index = paneItems.firstIndex(where: { $0.title == title }) else { return }
        sidebarTable.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        showPane(at: index)
        window?.layoutIfNeeded()
    }

    private func showPane(at index: Int) {
        guard paneItems.indices.contains(index) else { return }

        NSLayoutConstraint.deactivate(currentPaneConstraints)
        currentPaneConstraints.removeAll()
        paneContainer.subviews.forEach { $0.removeFromSuperview() }

        let pane = paneItems[index].view
        pane.translatesAutoresizingMaskIntoConstraints = false
        paneContainer.addSubview(pane)

        currentPaneConstraints = [
            pane.topAnchor.constraint(equalTo: paneContainer.topAnchor),
            pane.leadingAnchor.constraint(equalTo: paneContainer.leadingAnchor),
            pane.trailingAnchor.constraint(equalTo: paneContainer.trailingAnchor),
            pane.bottomAnchor.constraint(equalTo: paneContainer.bottomAnchor),
        ]
        NSLayoutConstraint.activate(currentPaneConstraints)
        resetScrollPositionIfNeeded(for: pane)
        if paneItems[index].title == "Models" { modelsPane.paneDidAppear() }
        if paneItems[index].title == "History" { reloadHistory(selectFirst: true) }
    }

    private func fitWindowToVisibleScreen() {
        guard let window else { return }
        guard let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame else { return }

        let visibleMaxWidth = max(window.minSize.width, visibleFrame.width - settingsWindowScreenMargin)
        let visibleMaxHeight = max(window.minSize.height, visibleFrame.height - settingsWindowScreenMargin)
        let maxWidth = min(settingsPreferredMaximumWindowSize.width, visibleMaxWidth)
        let maxHeight = min(settingsPreferredMaximumWindowSize.height, visibleMaxHeight)
        window.maxSize = NSSize(width: maxWidth, height: maxHeight)

        var frame = window.frame
        frame.size.width = min(max(frame.width, window.minSize.width), maxWidth)
        frame.size.height = min(max(frame.height, window.minSize.height), maxHeight)

        if frame.maxX > visibleFrame.maxX {
            frame.origin.x = visibleFrame.maxX - frame.width
        }
        if frame.minX < visibleFrame.minX {
            frame.origin.x = visibleFrame.minX
        }
        if frame.maxY > visibleFrame.maxY {
            frame.origin.y = visibleFrame.maxY - frame.height
        }
        if frame.minY < visibleFrame.minY {
            frame.origin.y = visibleFrame.minY
        }

        window.setFrame(frame, display: false)
    }

    private func resetScrollPositionIfNeeded(for pane: NSView) {
        guard let scrollView = pane as? NSScrollView else { return }

        scrollView.layoutSubtreeIfNeeded()
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)

        DispatchQueue.main.async { [weak scrollView] in
            guard let scrollView else { return }
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    private func makeGeneralPane() -> NSView {
        makePane { stack in
            if let error = UserSettings.shared.writingMigrationError {
                let warning = makeHelpLabel(error)
                warning.textColor = .systemOrange
                stack.addArrangedSubview(warning)
            }
            if UserSettings.shared.retiredActionsRecoveryURL != nil {
                stack.addArrangedSubview(makeSmallButton("Show recovered action presets", action: #selector(showRecoveredActions)))
            }
            addSection(
                "Behavior",
                help: "Control how Companion runs in the background.",
                to: stack
            ) { section in
                launchAtLoginCheckbox = NSButton(
                    checkboxWithTitle: "Launch Companion at login",
                    target: self,
                    action: #selector(toggleLaunchAtLogin)
                )
                launchAtLoginCheckbox.state = UserSettings.shared.launchAtLogin ? .on : .off
                section.addArrangedSubview(launchAtLoginCheckbox)

                paletteDefaultViewPopup = NSPopUpButton(frame: .zero, pullsDown: false)
                paletteDefaultViewPopup.addItems(withTitles: UserSettings.PaletteDefaultView.allCases.map(\.title))
                paletteDefaultViewPopup.selectItem(withTitle: UserSettings.shared.paletteDefaultView.title)
                paletteDefaultViewPopup.target = self
                paletteDefaultViewPopup.action = #selector(paletteDefaultViewChanged)
                section.addArrangedSubview(makeSettingsRow(label: "Open with", control: paletteDefaultViewPopup))
                section.addArrangedSubview(makeHelpLabel("Open directly into an instruction, or show the two action icons first."))

                section.addArrangedSubview(makeHelpLabel(
                    "Companion stays in the menu bar and opens the command palette with your global shortcut."
                ))
            }

            addSection(
                "App",
                help: "Version and support links live outside provider/action setup.",
                to: stack
            ) { section in
                section.addArrangedSubview(makeInfoRow(label: "Version", value: appVersionString()))
                section.addArrangedSubview(makeInfoRow(label: "Bundle ID", value: Bundle.main.bundleIdentifier ?? "Unknown"))
                section.addArrangedSubview(makeHelpLabel(
                    "About, quit, and status commands are available from the Companion menu bar icon."
                ))
            }

            addSection(
                "Credits",
                help: "Companion is made by Santiago Alonso.",
                to: stack
            ) { section in
                section.addArrangedSubview(makeInfoRow(label: "Made by", value: "Santiago Alonso"))
                section.addArrangedSubview(makeSettingsRow(
                    label: "Website",
                    control: makeLinkButton("santiagoalonso.com", action: #selector(openCreatorWebsite))
                ))
            }
        }
    }

    @objc private func paletteDefaultViewChanged() {
        let choices = UserSettings.PaletteDefaultView.allCases
        guard choices.indices.contains(paletteDefaultViewPopup.indexOfSelectedItem) else { return }
        UserSettings.shared.paletteDefaultView = choices[paletteDefaultViewPopup.indexOfSelectedItem]
    }

    private func makeModelsPane() -> NSView {
        modelsPane = ModelsSettingsPane()
        return modelsPane.view
    }

    private func makeHistoryPane() -> NSView {
        makePane { stack in
            addSection(
                "Generated Text History",
                help: "The latest 500 results are shown. Older results stay on this Mac. Source text and image bytes are not stored.",
                to: stack
            ) { section in
                historyEntries = []

                let buttonRow = NSStackView()
                buttonRow.orientation = .horizontal
                buttonRow.alignment = .centerY
                buttonRow.spacing = 8
                copyHistoryButton = makeSmallButton("Copy Result", action: #selector(copyHistoryResult))
                buttonRow.addArrangedSubview(copyHistoryButton)
                buttonRow.addArrangedSubview(makeSmallButton("Clear History", action: #selector(clearHistory)))
                section.addArrangedSubview(buttonRow)

                historyTable = NSTableView()
                historyTable.headerView = nil
                historyTable.rowHeight = 44
                historyTable.intercellSpacing = NSSize(width: 0, height: 2)
                historyTable.backgroundColor = .clear
                historyTable.delegate = self
                historyTable.dataSource = self
                historyTable.style = .inset

                let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("history"))
                column.resizingMask = .autoresizingMask
                historyTable.addTableColumn(column)

                let historyScroll = NSScrollView()
                historyScroll.translatesAutoresizingMaskIntoConstraints = false
                historyScroll.hasVerticalScroller = true
                historyScroll.borderType = .bezelBorder
                historyScroll.documentView = historyTable
                section.addArrangedSubview(historyScroll)
                historyScroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 500).isActive = true
                historyScroll.heightAnchor.constraint(equalToConstant: 168).isActive = true

                historyMetadataLabel = makeHelpLabel("")
                section.addArrangedSubview(historyMetadataLabel)

                let resultScroll = NSTextView.scrollableTextView()
                resultScroll.translatesAutoresizingMaskIntoConstraints = false
                resultScroll.hasVerticalScroller = true
                resultScroll.borderType = .bezelBorder

                historyResultView = resultScroll.documentView as? NSTextView
                historyResultView.isEditable = false
                historyResultView.isSelectable = true
                historyResultView.isRichText = true
                historyResultView.font = .systemFont(ofSize: 12)
                historyResultView.textColor = .labelColor
                historyResultView.textContainerInset = NSSize(width: 8, height: 8)
                historyResultView.string = ""
                section.addArrangedSubview(resultScroll)
                resultScroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 500).isActive = true
                resultScroll.heightAnchor.constraint(equalToConstant: 190).isActive = true

                reloadHistory(selectFirst: true)
            }
        }
    }

    private func makeShortcutPane() -> NSView {
        makePane { stack in
            addSection(
                "Global Shortcut",
                help: "The shortcut opens the palette from any app. Press it again to close the palette.",
                to: stack
            ) { section in
                shortcutLabel = NSTextField(labelWithString: currentShortcutLabel())
                shortcutLabel.font = .monospacedSystemFont(ofSize: 13, weight: .medium)

                let shortcutControl = NSStackView()
                shortcutControl.orientation = .horizontal
                shortcutControl.alignment = .centerY
                shortcutControl.spacing = 8
                shortcutControl.addArrangedSubview(shortcutLabel)
                shortcutControl.addArrangedSubview(makeSmallButton("Change...", action: #selector(recordShortcut)))
                shortcutControl.addArrangedSubview(makeSmallButton("Reset", action: #selector(resetShortcut)))
                section.addArrangedSubview(makeSettingsRow(label: "Shortcut", control: shortcutControl))

                section.addArrangedSubview(makeHelpLabel(
                    "If the shortcut does not trigger, another app may already own it. Record a different combination."
                ))
            }
        }
    }

    private func makePermissionsPane() -> NSView {
        makePane { stack in
            addSection(
                "Required Permissions",
                help: "Companion needs both permissions before it can work reliably across apps.",
                to: stack
            ) { section in
                permissionsStack = NSStackView()
                permissionsStack.orientation = .vertical
                permissionsStack.alignment = .width
                permissionsStack.spacing = 10
                section.addArrangedSubview(permissionsStack)
                permissionsStack.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
                renderPermissionRows()

                section.addArrangedSubview(makeSmallButton("Recheck Permissions", action: #selector(recheckPermissions)))
                section.addArrangedSubview(makeHelpLabel(
                    "After an app update, macOS may keep stale permission entries. If Companion stops working, remove and re-add it in each privacy list, then relaunch."
                ))
            }
        }
    }

    private func makePane(build: (NSStackView) -> Void) -> NSView {
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

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
            container.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -22),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
        ])

        build(stack)
        return scrollView
    }

    private func addSection(
        _ title: String,
        help: String?,
        to stack: NSStackView,
        build: (NSStackView) -> Void
    ) {
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

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.alignment = .left
        section.addArrangedSubview(titleLabel)

        if let help {
            section.addArrangedSubview(makeHelpLabel(help))
        }

        build(section)

        stack.addArrangedSubview(box)
        box.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        NSLayoutConstraint.activate([
            section.topAnchor.constraint(equalTo: box.topAnchor, constant: 12),
            section.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 14),
            section.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -14),
            section.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -12),
        ])
    }

    private func makeSettingsRow(label: String, control: NSView) -> NSStackView {
        let row = NSStackView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.distribution = .fill

        row.addArrangedSubview(makeRowLabel(label))
        row.addArrangedSubview(control)
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        control.widthAnchor.constraint(greaterThanOrEqualToConstant: 330).isActive = true

        return row
    }

    private func makeRowLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        label.widthAnchor.constraint(equalToConstant: labelWidth).isActive = true
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }

    private func makeHelpLabel(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .tertiaryLabelColor
        label.alignment = .left
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.widthAnchor.constraint(lessThanOrEqualToConstant: 440).isActive = true
        return label
    }

    private func makeInfoRow(label: String, value: String) -> NSStackView {
        let valueLabel = NSTextField(labelWithString: value)
        valueLabel.font = .systemFont(ofSize: 12)
        valueLabel.textColor = .labelColor
        valueLabel.lineBreakMode = .byTruncatingTail
        return makeSettingsRow(label: label, control: valueLabel)
    }

    private func appVersionString() -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = info?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? version : "\(version) (\(build))"
    }

    private func makeTextField(value: String, placeholder: String, monospaced: Bool) -> NSTextField {
        let field = NSTextField(frame: .zero)
        field.stringValue = value
        field.placeholderString = placeholder
        field.font = monospaced
            ? .monospacedSystemFont(ofSize: 12, weight: .regular)
            : .systemFont(ofSize: 12)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.widthAnchor.constraint(greaterThanOrEqualToConstant: 330).isActive = true
        return field
    }

    private func makeSecureField(value: String, placeholder: String) -> NSSecureTextField {
        let field = NSSecureTextField(frame: .zero)
        field.stringValue = value
        field.placeholderString = placeholder
        field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.widthAnchor.constraint(greaterThanOrEqualToConstant: 330).isActive = true
        return field
    }

    private func makeSmallButton(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .small
        return button
    }

    private func makeLinkButton(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.isBordered = false
        button.font = .systemFont(ofSize: 12)
        button.contentTintColor = .linkColor
        button.alignment = .left
        button.setButtonType(.momentaryChange)
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    private func renderPermissionRows() {
        permissionsStack.arrangedSubviews.forEach { view in
            permissionsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        permissionsStack.addArrangedSubview(makePermissionRow(
            granted: AXIsProcessTrusted(),
            name: "Accessibility",
            detail: "Lets Companion copy selected text and paste the replacement.",
            action: #selector(openAccessibilitySettings)
        ))
    }

    private func makePermissionRow(granted: Bool, name: String, detail: String, action: Selector) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.image = NSImage(
            systemSymbolName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
            accessibilityDescription: nil
        )
        icon.contentTintColor = granted ? .systemGreen : .systemOrange
        row.addSubview(icon)

        let textStack = NSStackView()
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1
        row.addSubview(textStack)

        let title = NSTextField(labelWithString: granted ? "\(name): Granted" : "\(name): Needs attention")
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        textStack.addArrangedSubview(title)

        let detailLabel = makeHelpLabel(detail)
        textStack.addArrangedSubview(detailLabel)

        let button = makeSmallButton("Open System Settings", action: action)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = granted
        row.addSubview(button)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            icon.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),

            textStack.topAnchor.constraint(equalTo: row.topAnchor),
            textStack.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            textStack.bottomAnchor.constraint(equalTo: row.bottomAnchor),

            button.leadingAnchor.constraint(greaterThanOrEqualTo: textStack.trailingAnchor, constant: 12),
            button.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            button.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])

        return row
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func recheckPermissions() {
        renderPermissionRows()
    }

    @objc private func openCreatorWebsite() {
        guard let url = URL(string: "https://santiagoalonso.com") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func copyHistoryResult() {
        let row = historyTable.selectedRow
        guard historyEntries.indices.contains(row) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(historyEntries[row].result, forType: .string)
    }

    @objc private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear generated text history?"
        alert.informativeText = "This clears the visible history. A recovery archive stays in Companion's Application Support folder."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear History")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        historyLoadTask?.cancel()
        Task { @MainActor in
            do {
                try await GenerationHistoryStore.shared.clear()
                reloadHistory(selectFirst: false)
            } catch { showStorageError("History couldn't be cleared. Your saved files are still on this Mac.") }
        }
    }

    private func reloadHistory(selectFirst: Bool) {
        guard historyTable != nil else { return }
        historyLoadTask?.cancel()
        historyLoadTask = Task { @MainActor in
            do {
                let entries = try await GenerationHistoryStore.shared.entries()
                try Task.checkCancellation()
                historyEntries = entries
                historyTable.reloadData()
                if selectFirst, !historyEntries.isEmpty {
                    historyTable.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
                }
                updateHistoryDetail()
            } catch is CancellationError { }
            catch { showStorageError("History couldn't be read. Existing files have been preserved.") }
        }
    }

    private func showStorageError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Couldn't save changes"
        alert.informativeText = message
        alert.runModal()
    }

    private func updateHistoryDetail() {
        guard historyResultView != nil, historyMetadataLabel != nil else { return }
        let row = historyTable.selectedRow
        guard historyEntries.indices.contains(row) else {
            historyResultView.string = ""
            historyMetadataLabel.stringValue = historyEntries.isEmpty
                ? "No generated text has been saved yet."
                : "Select a history entry."
            copyHistoryButton?.isEnabled = false
            return
        }

        let entry = historyEntries[row]
        historyResultView.string = entry.result
        if let sources = entry.sources, !sources.isEmpty {
            let detail = NSMutableAttributedString(string: entry.result + "\n\nSources\n", attributes: [
                .font: historyResultView.font ?? NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor
            ])
            for source in sources where ["http", "https"].contains(source.url.scheme?.lowercased() ?? "") {
                detail.append(NSAttributedString(string: "\(source.title)\n\(source.url.absoluteString)\n\n", attributes: [
                    .font: NSFont.systemFont(ofSize: 12), .link: source.url,
                    .foregroundColor: NSColor.linkColor
                ]))
            }
            historyResultView.textStorage?.setAttributedString(detail)
        }
        let date = Self.historyDateFormatter.string(from: entry.createdAt)
        let imageText = entry.hadImages
            ? " · images: \(entry.imageFileNames.joined(separator: ", "))"
            : ""
        let durationText = (entry.requestDurationSeconds.map { " · " + String(format: "%.1f s request", $0) } ?? "")
            + (entry.usedWebSearch == true ? " · Web search" : "")
        historyMetadataLabel.stringValue = "\(date) · \(entry.actionLabel) · \(entry.provider) · \(entry.model) · \(entry.selectedWordCount) selected words\(durationText)\(imageText)"
        copyHistoryButton?.isEnabled = true
    }

    private static let historyDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    @objc private func showRecoveredActions() {
        guard let url = UserSettings.shared.retiredActionsRecoveryURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func recordShortcut() {
        if let monitor = shortcutMonitor {
            NSEvent.removeMonitor(monitor)
            shortcutMonitor = nil
        }

        shortcutLabel.stringValue = "Press shortcut..."
        shortcutLabel.textColor = .systemOrange

        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }

            let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
            guard !mods.isEmpty else { return event }

            let keyCode = UInt32(event.keyCode)
            HotkeyManager.shared.updateShortcut(keyCode: keyCode, modifiers: mods)

            self.shortcutLabel.stringValue = self.formatShortcut(modifiers: mods, keyCode: event.keyCode)
            self.shortcutLabel.textColor = .labelColor

            if let monitor = self.shortcutMonitor {
                NSEvent.removeMonitor(monitor)
                self.shortcutMonitor = nil
            }

            return nil
        }
    }

    @objc private func resetShortcut() {
        HotkeyManager.shared.resetToDefault()
        shortcutLabel.stringValue = currentShortcutLabel()
        shortcutLabel.textColor = .labelColor
    }

    @objc private func toggleLaunchAtLogin() {
        let enabled = launchAtLoginCheckbox.state == .on
        UserSettings.shared.launchAtLogin = enabled

        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("Failed to update launch at login: \(error)")
            }
        }
    }

    private func currentShortcutLabel() -> String {
        let settings = UserSettings.shared
        guard let keyCode = settings.shortcutKeyCode,
              let modifiers = settings.shortcutModifiers else {
            return "Cmd + Shift + E"
        }
        return formatShortcut(
            modifiers: NSEvent.ModifierFlags(rawValue: modifiers),
            keyCode: UInt16(keyCode)
        )
    }

    private func formatShortcut(modifiers: NSEvent.ModifierFlags, keyCode: UInt16) -> String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("Ctrl") }
        if modifiers.contains(.option) { parts.append("Opt") }
        if modifiers.contains(.shift) { parts.append("Shift") }
        if modifiers.contains(.command) { parts.append("Cmd") }

        let keyName: String
        switch Int(keyCode) {
        case kVK_ANSI_A: keyName = "A"
        case kVK_ANSI_B: keyName = "B"
        case kVK_ANSI_C: keyName = "C"
        case kVK_ANSI_D: keyName = "D"
        case kVK_ANSI_E: keyName = "E"
        case kVK_ANSI_F: keyName = "F"
        case kVK_ANSI_G: keyName = "G"
        case kVK_ANSI_H: keyName = "H"
        case kVK_ANSI_I: keyName = "I"
        case kVK_ANSI_J: keyName = "J"
        case kVK_ANSI_K: keyName = "K"
        case kVK_ANSI_L: keyName = "L"
        case kVK_ANSI_M: keyName = "M"
        case kVK_ANSI_N: keyName = "N"
        case kVK_ANSI_O: keyName = "O"
        case kVK_ANSI_P: keyName = "P"
        case kVK_ANSI_Q: keyName = "Q"
        case kVK_ANSI_R: keyName = "R"
        case kVK_ANSI_S: keyName = "S"
        case kVK_ANSI_T: keyName = "T"
        case kVK_ANSI_U: keyName = "U"
        case kVK_ANSI_V: keyName = "V"
        case kVK_ANSI_W: keyName = "W"
        case kVK_ANSI_X: keyName = "X"
        case kVK_ANSI_Y: keyName = "Y"
        case kVK_ANSI_Z: keyName = "Z"
        default: keyName = "Key(\(keyCode))"
        }

        parts.append(keyName)
        return parts.joined(separator: " + ")
    }

    func windowWillClose(_ notification: Notification) {
        if let monitor = shortcutMonitor {
            NSEvent.removeMonitor(monitor)
            shortcutMonitor = nil
        }
    }
}

extension SettingsWindow: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        if historyTable != nil, tableView === historyTable {
            return historyEntries.count
        }
        return paneItems.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if historyTable != nil, tableView === historyTable {
            guard historyEntries.indices.contains(row) else { return nil }
            return makeHistoryCell(entry: historyEntries[row])
        }

        guard paneItems.indices.contains(row) else { return nil }

        let identifier = NSUserInterfaceItemIdentifier("SettingsPaneCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
            ?? makePaneCell(identifier: identifier)

        let item = paneItems[row]
        cell.textField?.stringValue = item.title
        cell.imageView?.image = NSImage(systemSymbolName: item.symbolName, accessibilityDescription: item.title)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        if let tableView = notification.object as? NSTableView,
           historyTable != nil,
           tableView === historyTable {
            updateHistoryDetail()
            return
        }
        showPane(at: sidebarTable.selectedRow)
    }

    private func makeHistoryCell(entry: GenerationHistoryStore.Entry) -> NSView {
        let cell = NSTableCellView()
        cell.identifier = NSUserInterfaceItemIdentifier("HistoryCell")

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        cell.addSubview(stack)

        let title = NSTextField(labelWithString: entry.actionLabel)
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        title.lineBreakMode = .byTruncatingTail
        stack.addArrangedSubview(title)

        let date = Self.historyDateFormatter.string(from: entry.createdAt)
        let imageMark = entry.hadImages ? " · images" : ""
        let detail = NSTextField(labelWithString: "\(date) · \(entry.provider) · \(entry.model)\(imageMark)")
        detail.font = .systemFont(ofSize: 10.5)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingMiddle
        stack.addArrangedSubview(detail)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])

        return cell
    }

    private func makePaneCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier

        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        imageView.contentTintColor = .secondaryLabelColor
        cell.addSubview(imageView)
        cell.imageView = imageView

        let textField = NSTextField(labelWithString: "")
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.font = .systemFont(ofSize: 13, weight: .medium)
        textField.lineBreakMode = .byTruncatingTail
        cell.addSubview(textField)
        cell.textField = textField

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
            imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 18),
            imageView.heightAnchor.constraint(equalToConstant: 18),

            textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 8),
            textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -10),
            textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])

        return cell
    }
}

private final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}

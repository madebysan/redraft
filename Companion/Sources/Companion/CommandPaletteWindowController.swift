import AppKit
import QuartzCore
import Carbon.HIToolbox

// The keyboard-first writing surface: two actions, one input, icon-sized feedback.
@MainActor
final class CommandPaletteWindowController: NSWindowController, NSTextFieldDelegate {
    static let shared = CommandPaletteWindowController()

    private enum Mode { case actions, instruction, loading, success, error, recovery }
    private let inset: CGFloat = 10
    private var mode: Mode = .actions
    private var selectedText = ""
    private var instructionDraft = ""
    private var resultText = ""
    private var errorMessage = ""
    private var inputField: NSTextField?
    private var actionButtons: [NSButton] = []
    private var selectedAction = 0
    private var spinner: NSProgressIndicator?
    private var dismissalTask: Task<Void, Never>?
    private var keyMonitor: Any?
    private var outsideClickMonitor: Any?
    private var errorPopover: NSPopover?

    var isPaletteVisible: Bool { window?.isVisible == true }

    private var reduceMotion: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--reduce-motion-preview") { return true }
        #endif
        return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    convenience init() {
        let panel = CommandPalettePanel(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 56),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Companion"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false // The system glass supplies its own depth.
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        self.init(window: panel)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidResignActive),
            name: NSApplication.didResignActiveNotification, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    func show(selectedText: String, anchorRect: CGRect? = nil) {
        self.selectedText = selectedText
        instructionDraft = ""
        resultText = ""
        showActions()
        position(anchorRect: anchorRect)
        activate()
    }

    private func activate() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        installMonitors()
    }

    private func showActions() {
        mode = .actions
        selectedAction = 0
        let content = installSurface(size: NSSize(width: 80, height: 36), animated: false)
        let grammar = button("text.badge.checkmark", label: "Fix Grammar (Return)",
            frame: NSRect(x: 4, y: 0, width: 36, height: 36), action: #selector(fixGrammar))
        let instruction = button("pencil", label: "Write an instruction (Tab)",
            frame: NSRect(x: 40, y: 0, width: 36, height: 36), action: #selector(openInstruction))
        content.addSubview(grammar)
        content.addSubview(instruction)
        actionButtons = [grammar, instruction]
        window?.makeFirstResponder(grammar)
    }

    @objc private func fixGrammar() {
        guard !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            openInstruction()
            return
        }
        TextGrabber.shared.runFixGrammar()
    }

    @objc private func openInstruction() {
        mode = .instruction
        let content = installSurface(size: NSSize(width: 320, height: 40))
        let field = NSTextField(frame: NSRect(x: 18, y: 9, width: 252, height: 22))
        field.font = .systemFont(ofSize: 14)
        field.stringValue = instructionDraft
        field.placeholderString = selectedText.isEmpty ? "Write something…" : "What should change?"
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.setAccessibilityLabel("Writing instruction")
        field.target = self
        field.action = #selector(runInstruction)
        field.delegate = self
        content.addSubview(field)
        content.addSubview(button("arrow.up", label: "Run instruction (Return)",
            frame: NSRect(x: 280, y: 4, width: 32, height: 32), action: #selector(runInstruction)))
        inputField = field
        window?.makeFirstResponder(field)
    }

    @objc private func runInstruction() {
        guard let instruction = inputField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
              !instruction.isEmpty else { NSSound.beep(); return }
        instructionDraft = instruction
        TextGrabber.shared.runCustomInstruction(instruction)
    }

    func controlTextDidChange(_ notification: Notification) {
        instructionDraft = inputField?.stringValue ?? ""
    }

    func showPreviewInstruction(_ instruction: String) {
        instructionDraft = instruction
        openInstruction()
    }

    func showRunning(title: String, subtitle: String = "Replacing selected text") {
        mode = .loading
        let content = installSurface(size: NSSize(width: 30, height: 30))
        if !reduceMotion {
            let progress = NSProgressIndicator(frame: NSRect(x: 8, y: 8, width: 14, height: 14))
            progress.style = .spinning
            progress.controlSize = .small
            progress.setAccessibilityLabel(title)
            content.addSubview(progress)
            progress.startAnimation(nil)
            spinner = progress
        }
        let cancel = button(reduceMotion ? "ellipsis" : nil, label: "\(title). Cancel rewrite (Escape)",
            frame: content.bounds, action: #selector(dismiss))
        content.addSubview(cancel)
    }

    func showSuccess(subtitle: String = "Selection replaced") {
        mode = .success
        let content = installSurface(size: NSSize(width: 30, height: 30))
        content.addSubview(button("checkmark", label: "\(subtitle). Dismiss",
            frame: content.bounds, action: #selector(dismiss)))
        window?.orderFrontRegardless() // Passive feedback; never take focus back from the editor.
        dismissalTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 700_000_000) }
            catch { return }
            self?.closePalette()
        }
    }

    func showError(_ message: String) {
        mode = .error
        errorMessage = message
        let content = installSurface(size: NSSize(width: 30, height: 30))
        content.addSubview(button("exclamationmark", label: "\(message) Click for details.",
            frame: content.bounds, action: #selector(showErrorDetails(_:))))
    }

    @objc private func showErrorDetails(_ sender: NSButton) {
        let controller = NSViewController()
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 292, height: 156))
        let message = NSTextField(wrappingLabelWithString: errorMessage)
        message.frame = NSRect(x: 16, y: 50, width: 260, height: 90)
        message.font = .systemFont(ofSize: 12)
        message.isSelectable = true
        content.addSubview(message)
        let settings = NSButton(title: "Open Settings", target: self, action: #selector(openSettings))
        settings.frame = NSRect(x: 14, y: 12, width: 130, height: 28)
        settings.bezelStyle = .rounded
        content.addSubview(settings)
        controller.view = content
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = controller
        errorPopover = popover
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
    }

    @objc private func openSettings() {
        close()
        (NSApp.delegate as? AppDelegate)?.openSettings()
    }

    // Recovery is deliberately separate from the normal two-action flow.
    func showTextResult(text: String, title: String, subtitle: String, images: [PromptImageAttachment] = []) {
        mode = .recovery
        resultText = text
        let content = installSurface(size: NSSize(width: 360, height: 234))
        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        heading.frame = NSRect(x: 16, y: 202, width: 296, height: 18)
        content.addSubview(heading)
        let explanation = NSTextField(wrappingLabelWithString: subtitle)
        explanation.font = .systemFont(ofSize: 11)
        explanation.textColor = .secondaryLabelColor
        explanation.frame = NSRect(x: 16, y: 156, width: 328, height: 40)
        content.addSubview(explanation)
        let scroll = NSScrollView(frame: NSRect(x: 16, y: 44, width: 328, height: 106))
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let textView = NSTextView(frame: scroll.bounds)
        textView.string = text
        textView.font = .systemFont(ofSize: 13)
        textView.isEditable = false
        textView.isRichText = false
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = .width
        textView.textContainer?.widthTracksTextView = true
        scroll.documentView = textView
        content.addSubview(scroll)
        let copy = NSButton(title: "Copy rewrite", target: self, action: #selector(copyResult))
        copy.bezelStyle = .rounded
        copy.frame = NSRect(x: 244, y: 10, width: 104, height: 26)
        content.addSubview(copy)
        content.addSubview(button("xmark", label: "Close", frame: NSRect(x: 324, y: 196, width: 28, height: 28), action: #selector(dismiss)))
        activate()
    }

    func showImageResult(text: String, images: [PromptImageAttachment], subtitle: String) {
        showTextResult(text: text, title: "Your rewrite", subtitle: subtitle, images: images)
    }

    @objc private func copyResult() {
        guard !TextGrabber.shared.copyPreviewResult() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(resultText, forType: .string)
    }

    func dismissAfterPreviewAction() { closePalette() }

    func prepareForReplacement() {
        // End the custom instruction's field editor before returning to another app.
        window?.makeFirstResponder(nil)
        spinner?.stopAnimation(nil)
        removeMonitors()
        window?.orderOut(nil)
    }

    @objc private func dismiss() { close() }

    override func close() {
        TextGrabber.shared.cancelPaletteSession()
        closePalette()
    }

    @objc private func appDidResignActive() {
        guard Bundle.main.bundleIdentifier?.hasSuffix(".preview") != true else { return }
        if mode == .actions || mode == .instruction { close() }
    }

    private func installSurface(size: NSSize, animated: Bool = true) -> NSView {
        dismissalTask?.cancel()
        dismissalTask = nil
        spinner?.stopAnimation(nil)
        spinner = nil
        inputField = nil
        actionButtons = []
        errorPopover?.close()
        errorPopover = nil
        guard let window else { return NSView() }
        let wasVisible = window.isVisible
        let old = window.frame
        let windowSize = NSSize(width: size.width + inset * 2, height: size.height + inset * 2)
        var frame = NSRect(x: old.minX, y: old.maxY - windowSize.height, width: windowSize.width, height: windowSize.height)
        frame = clamped(frame)
        window.setFrame(frame, display: false)
        let root = NSView(frame: NSRect(origin: .zero, size: windowSize))
        let content = NSView(frame: NSRect(origin: .zero, size: size))
        let surfaceFrame = NSRect(origin: NSPoint(x: inset, y: inset), size: size)
        if #available(macOS 26.0, *) {
            let group = NSGlassEffectContainerView(frame: root.bounds)
            let glass = NSGlassEffectView(frame: surfaceFrame)
            glass.style = .clear
            glass.cornerRadius = size.height > 100 ? 18 : size.height / 2
            glass.contentView = content
            let groupContent = NSView(frame: root.bounds)
            groupContent.addSubview(glass)
            group.contentView = groupContent
            root.addSubview(group)
        } else {
            let material = NSVisualEffectView(frame: surfaceFrame)
            material.material = .popover
            material.blendingMode = .behindWindow
            material.state = .active
            material.wantsLayer = true
            material.layer?.cornerRadius = size.height > 100 ? 18 : size.height / 2
            material.layer?.masksToBounds = true
            material.addSubview(content)
            root.addSubview(material)
        }
        window.contentView = root
        if animated && wasVisible && !reduceMotion {
            root.wantsLayer = true
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = 0.16
            fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
            root.layer?.add(fade, forKey: "state")
        }
        return content
    }

    private func button(_ symbol: String?, label: String, frame: NSRect, action: Selector) -> NSButton {
        let button = CapsuleActionButton(frame: frame)
        button.target = self
        button.action = action
        button.isBordered = false
        button.focusRingType = .none
        button.imagePosition = .imageOnly
        button.title = ""
        if let symbol {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
                .withSymbolConfiguration(.init(pointSize: frame.height <= 30 ? 13 : 16, weight: .medium))
        }
        button.contentTintColor = .labelColor
        button.toolTip = label
        button.setAccessibilityLabel(label)
        return button
    }

    private func position(anchorRect: CGRect?) {
        guard let window else { return }
        let size = window.frame.size
        var origin: NSPoint
        if let rect = anchorRect, !rect.isNull, !rect.isEmpty {
            // Accessibility uses top-left Quartz coordinates, AppKit uses bottom-left.
            let top = NSScreen.screens.first?.frame.maxY ?? 0
            let anchor = NSRect(x: rect.minX, y: top - rect.maxY, width: rect.width, height: rect.height)
            origin = NSPoint(x: anchor.minX - inset, y: anchor.minY - size.height - 4)
            let screen = NSScreen.screens.first { NSIntersectsRect($0.frame, anchor) } ?? NSScreen.main
            if let screen, origin.y < screen.visibleFrame.minY { origin.y = anchor.maxY + 4 }
        } else {
            let cursor = NSEvent.mouseLocation
            origin = NSPoint(x: cursor.x + 12, y: cursor.y - size.height - 8)
        }
        window.setFrame(clamped(NSRect(origin: origin, size: size)), display: true)
    }

    private func clamped(_ frame: NSRect) -> NSRect {
        guard let screen = NSScreen.screens.first(where: { NSIntersectsRect($0.frame, frame) }) ?? NSScreen.main else { return frame }
        let bounds = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        var result = frame
        result.origin.x = min(max(result.minX, bounds.minX), bounds.maxX - result.width)
        result.origin.y = min(max(result.minY, bounds.minY), bounds.maxY - result.height)
        return result
    }

    private func installMonitors() {
        removeMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event) == true ? nil : event
        }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.mode != .loading, self.mode != .recovery else { return }
                guard Bundle.main.bundleIdentifier?.hasSuffix(".preview") != true else { return }
                self.close()
            }
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock)
        let settings = UserSettings.shared
        let shortcutKey = settings.shortcutKeyCode ?? UInt32(kVK_ANSI_E)
        let shortcutFlags = settings.shortcutModifiers ?? UInt(NSEvent.ModifierFlags([.command, .shift]).rawValue)
        if UInt32(event.keyCode) == shortcutKey && UInt(flags.rawValue) == shortcutFlags {
            close()
            return true
        }
        if event.keyCode == kVK_Escape {
            if mode == .instruction { showActions() } else { close() }
            return true
        }
        if flags == .command && event.keyCode == kVK_ANSI_Comma { openSettings(); return true }
        guard mode == .actions || mode == .instruction else { return false }
        if flags == .command && event.keyCode == kVK_ANSI_1 { fixGrammar(); return true }
        if flags == .command && event.keyCode == kVK_ANSI_2 { openInstruction(); return true }
        guard mode == .actions, flags.isEmpty else { return false }
        switch Int(event.keyCode) {
        case kVK_Return, kVK_ANSI_KeypadEnter:
            selectedAction == 0 ? fixGrammar() : openInstruction()
        case kVK_Tab:
            openInstruction()
        case kVK_LeftArrow, kVK_RightArrow:
            selectedAction = event.keyCode == kVK_LeftArrow ? 0 : 1
            if actionButtons.indices.contains(selectedAction) { window?.makeFirstResponder(actionButtons[selectedAction]) }
        default: return false
        }
        return true
    }

    private func removeMonitors() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor); self.outsideClickMonitor = nil }
    }

    private func closePalette() {
        dismissalTask?.cancel()
        dismissalTask = nil
        spinner?.stopAnimation(nil)
        spinner = nil
        errorPopover?.close()
        errorPopover = nil
        removeMonitors()
        window?.orderOut(nil)
    }
}

private final class CommandPalettePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class CapsuleActionButton: NSButton {
    private var tracking: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: bounds, options: [.activeInActiveApp, .mouseEnteredAndExited, .inVisibleRect], owner: self)
        addTrackingArea(tracking!)
    }
    override func mouseEntered(with event: NSEvent) {
        wantsLayer = true
        layer?.cornerRadius = bounds.height / 2
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.07).cgColor
    }
    override func mouseExited(with event: NSEvent) { layer?.backgroundColor = NSColor.clear.cgColor }
}

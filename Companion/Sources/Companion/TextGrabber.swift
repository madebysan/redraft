import AppKit
import Carbon.HIToolbox
import UserNotifications
import os.log

private let logger = Logger(subsystem: "com.santiagoalonso.companion", category: "TextGrabber")

// Handles grabbing selected text via clipboard and pasting results back
@MainActor
final class TextGrabber {
    static let shared = TextGrabber()

    // Called when rewrite status changes (for menu bar feedback)
    var onStatusChange: ((RewriteStatus) -> Void)?

    // Prevent overlapping triggers
    private var isProcessing = false
    private var activeSession: RewriteSession?
    private var activeRequestID: UUID?
    private var activeRewriteTask: Task<Void, Never>?
    private var pendingPreview: PendingPreview?
    private var didCopyPendingPreview = false

    private struct RewriteSession {
        let selectedText: String
        let selectedWordCount: Int
        let sourceApp: NSRunningApplication?
        let savedItems: [NSPasteboardItem]
        var selectionSnapshot: TextSelectionSnapshot? = nil
    }

    private struct PendingPreview {
        let result: String
        let session: RewriteSession
        let images: [PromptImageAttachment]
        var canPaste = true
    }

    private enum PastePresentation {
        case status
        case closePreview
    }

    enum RewriteStatus {
        case rewriting
        case done
        case error(String)
    }

    // Grab selected text and show the command palette near the cursor.
    func grabSelectionAndShowPalette() {
        // Block re-entrant calls — ignore if already processing
        guard !isProcessing else {
            logger.notice("rewrite already in progress — ignoring trigger")
            return
        }
        guard AXIsProcessTrusted() else {
            CommandPaletteWindowController.shared.showSetupRequired(
                "Enable Companion in System Settings → Privacy & Security → Accessibility on this Mac, then reopen Companion. This permission is needed to read and replace selected text."
            )
            return
        }
        isProcessing = true

        // Remember which app was frontmost so we can paste back into it
        let sourceApp = NSWorkspace.shared.frontmostApplication
        let selectionSnapshot = sourceApp.flatMap { TextSelectionSnapshot.capture(processID: $0.processIdentifier) }

        let pasteboard = NSPasteboard.general
        let changeCountBefore = pasteboard.changeCount

        // Save original clipboard contents to restore later
        let savedItems = saveClipboard(pasteboard)

        let anchorRect = selectionSnapshot.flatMap { selectedTextBounds(from: $0.element) }
        if let capturedText = selectionSnapshot?.fingerprint.resolvedSelectedText, !capturedText.isEmpty {
            activeSession = RewriteSession(
                selectedText: capturedText,
                selectedWordCount: Self.wordCount(in: capturedText),
                sourceApp: sourceApp,
                savedItems: savedItems,
                selectionSnapshot: selectionSnapshot
            )
            CommandPaletteWindowController.shared.show(
                selectedText: capturedText,
                anchorRect: anchorRect
            )
            return
        }

        // A caret rectangle does not prove there is no selected text. Confirm an
        // empty/omitted AX result with Copy before the palette can take focus.
        simulateKeyPress(keyCode: UInt16(kVK_ANSI_C), modifiers: .maskCommand)

        // Poll for clipboard change instead of fixed delay (up to 500ms)
        pollClipboardChange(pasteboard: pasteboard, expected: changeCountBefore, attempts: 10, interval: 0.05) { changed in
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == sourceApp?.processIdentifier else {
                self.isProcessing = false
                return
            }
            if !changed {
                logger.notice("clipboard unchanged — opening palette with no selected text")
            }

            let refreshedSnapshot = sourceApp.flatMap { TextSelectionSnapshot.capture(processID: $0.processIdentifier) }
            let selectedText = changed ? (pasteboard.string(forType: .string) ?? "")
                : (refreshedSnapshot?.fingerprint.resolvedSelectedText ?? "")
            if selectedText.isEmpty, (refreshedSnapshot?.fingerprint.range?.length ?? selectionSnapshot?.fingerprint.range?.length ?? 0) > 0 {
                self.restoreClipboard(pasteboard, items: savedItems)
                self.isProcessing = false
                self.showErrorNotification("Couldn't read the selected text. Select it again and reopen Companion.")
                return
            }

            self.activeSession = RewriteSession(
                selectedText: selectedText,
                selectedWordCount: Self.wordCount(in: selectedText),
                sourceApp: sourceApp,
                savedItems: savedItems,
                selectionSnapshot: refreshedSnapshot ?? selectionSnapshot
            )
            CommandPaletteWindowController.shared.show(selectedText: selectedText, anchorRect: anchorRect)
        }
    }

    private func selectedTextBounds(from element: AXUIElement) -> CGRect? {
        var rangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeValue
        ) == .success,
              let rangeAXValue = rangeValue,
              CFGetTypeID(rangeAXValue) == AXValueGetTypeID() else {
            return nil
        }

        var range = CFRange()
        guard AXValueGetValue(rangeAXValue as! AXValue, .cfRange, &range) else {
            return nil
        }

        var lookupRange = range
        if lookupRange.length == 0 {
            lookupRange.length = 1
        }

        guard let lookupRangeValue = AXValueCreate(.cfRange, &lookupRange) else {
            return nil
        }

        var boundsValue: CFTypeRef?
        var result = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            lookupRangeValue,
            &boundsValue
        )

        if result != .success, range.length == 0 {
            lookupRange.length = 0
            if let insertionRangeValue = AXValueCreate(.cfRange, &lookupRange) {
                result = AXUIElementCopyParameterizedAttributeValue(
                    element,
                    kAXBoundsForRangeParameterizedAttribute as CFString,
                    insertionRangeValue,
                    &boundsValue
                )
            }
        }

        guard result == .success,
              let boundsAXValue = boundsValue,
              CFGetTypeID(boundsAXValue) == AXValueGetTypeID() else {
            return nil
        }

        var rect = CGRect.zero
        guard AXValueGetValue(boundsAXValue as! AXValue, .cgRect, &rect), !rect.isNull else {
            return nil
        }
        return rect
    }

    func cancelPaletteSession() {
        activeRewriteTask?.cancel()
        activeRewriteTask = nil
        activeRequestID = nil

        if let pendingPreview {
            if !didCopyPendingPreview {
                restoreClipboard(NSPasteboard.general, items: pendingPreview.session.savedItems)
            }
        } else if let session = activeSession {
            restoreClipboard(NSPasteboard.general, items: session.savedItems)
        }

        pendingPreview = nil
        didCopyPendingPreview = false
        activeSession = nil
        onStatusChange?(.done)
        isProcessing = false
    }

    @discardableResult
    func copyPreviewResult() -> Bool {
        guard let pendingPreview else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(pendingPreview.result, forType: .string)
        didCopyPendingPreview = true
        return true
    }

    func pastePreviewResult() {
        guard let pendingPreview, pendingPreview.canPaste else { return }
        let preview = pendingPreview
        self.pendingPreview = nil
        didCopyPendingPreview = false
        paste(
            preview.result,
            into: preview.session,
            previewImages: preview.images,
            presentation: .closePreview
        )
    }

    func runFixGrammar() {
        runPaletteRewrite(title: "Fix Grammar", historyLabel: "Fix Grammar", images: []) { text in
            try await RewriteDispatcher.shared.generateGrammar(text)
        }
    }

    func runCustomInstruction(
        _ instruction: String,
        route: GenerationRoute = .auto,
        images: [PromptImageAttachment] = []
    ) {
        runPaletteRewrite(
            title: "Running custom prompt",
            historyLabel: "Custom prompt",
            images: images
        ) { text in
            try await RewriteDispatcher.shared.generate(
                text,
                customInstruction: instruction,
                route: route,
                images: images
            )
        }
    }

    private func runPaletteRewrite(
        title: String,
        historyLabel: String,
        images: [PromptImageAttachment],
        request: @escaping (String) async throws -> GenerationResult
    ) {
        guard let session = activeSession else {
            isProcessing = false
            CommandPaletteWindowController.shared.showSetupRequired(
                "The selection session ended. Select your text and reopen Companion to try again."
            )
            return
        }
        let requestID = UUID()
        activeRequestID = requestID
        let startedAt = ProcessInfo.processInfo.systemUptime
        logger.info("Generation started request=\(requestID.uuidString, privacy: .public)")

        onStatusChange?(.rewriting)
        let isGenerating = session.selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        CommandPaletteWindowController.shared.showRunning(
            title: title,
            subtitle: isGenerating ? "Generating text" : "Replacing selected text"
        )

        activeRewriteTask?.cancel()
        activeRewriteTask = Task {
            do {
                let generation = try await request(session.selectedText)
                await MainActor.run {
                    guard self.activeRequestID == requestID else { return }
                    let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
                    logger.info("Generation finished request=\(requestID.uuidString, privacy: .public) provider=\(generation.provider.rawValue, privacy: .public) elapsed_ms=\(Int(elapsed * 1000))")
                    self.recordHistory(
                        result: generation.text,
                        actionLabel: historyLabel,
                        provider: generation.provider,
                        model: generation.model,
                        selectedWordCount: session.selectedWordCount,
                        imageFileNames: images.map(\.fileName),
                        requestDurationSeconds: elapsed,
                        sources: generation.sources, usedWebSearch: generation.usedWebSearch
                    )
                    self.pendingPreview = nil
                    self.didCopyPendingPreview = false
                    self.paste(
                        generation.text,
                        into: session,
                        previewImages: images
                    )
                }
            } catch {
                let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
                logger.error("Generation failed request=\(requestID.uuidString, privacy: .public) elapsed_ms=\(Int(elapsed * 1000)): \(error.localizedDescription)")
                await MainActor.run {
                    guard self.activeRequestID == requestID else { return }
                    if case CompletionError.incomplete(let partial) = error, !partial.isEmpty {
                        self.preserveResultForManualPaste(partial, session: session, images: images,
                            explanation: "Incomplete response · copied to clipboard. Original text unchanged.", canPaste: false)
                        return
                    }
                    self.activeRewriteTask = nil
                    self.restoreClipboard(NSPasteboard.general, items: session.savedItems)
                    self.activeRequestID = nil
                    self.activeSession = nil
                    self.onStatusChange?(.error(error.localizedDescription))
                    if case RewriteDispatcher.DispatchError.noProviderAvailable = error {
                        CommandPaletteWindowController.shared.showSetupRequired(error.localizedDescription)
                    } else {
                        CommandPaletteWindowController.shared.showError(error.localizedDescription)
                    }
                    self.showErrorNotification(error.localizedDescription)
                    self.isProcessing = false
                }
            }
        }
    }

    private func recordHistory(result: String, actionLabel: String, provider: UserSettings.Provider,
        model: String, selectedWordCount: Int, imageFileNames: [String], requestDurationSeconds: Double,
        sources: [WebSource], usedWebSearch: Bool) {
        Task {
            do {
                try await GenerationHistoryStore.shared.add(result: result, actionLabel: actionLabel,
                    provider: provider, model: model, selectedWordCount: selectedWordCount,
                    imageFileNames: imageFileNames, requestDurationSeconds: requestDurationSeconds,
                    sources: sources, usedWebSearch: usedWebSearch)
            } catch {
                self.showErrorNotification("The rewrite is available, but history couldn't be saved.")
            }
        }
    }

    private func paste(
        _ rewritten: String,
        into session: RewriteSession,
        previewImages: [PromptImageAttachment] = [],
        presentation: PastePresentation = .status
    ) {
        let pasteID = UUID()
        activeRequestID = pasteID
        let pasteboard = NSPasteboard.general
        // Generated text stays available even when target validation prevents insertion.
        pasteboard.clearContents()
        pasteboard.setString(rewritten, forType: .string)
        activeSession = nil
        let isGenerating = session.selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        // Re-activate the original app before pasting
        CommandPaletteWindowController.shared.prepareForReplacement()
        guard let sourceApp = session.sourceApp, !sourceApp.isTerminated else {
            preserveResultForManualPaste(rewritten, session: session, images: previewImages)
            return
        }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != sourceApp.processIdentifier,
           !sourceApp.activate() {
            preserveResultForManualPaste(rewritten, session: session, images: previewImages)
            return
        }

        // Small delay to let the app come to front
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard self.activeRequestID == pasteID else { return }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == sourceApp.processIdentifier else {
                self.preserveResultForManualPaste(rewritten, session: session, images: previewImages)
                return
            }
            guard AXIsProcessTrusted(),
                  session.selectionSnapshot?.stillMatches(processID: sourceApp.processIdentifier, selectedText: session.selectedText) == true else {
                self.preserveResultForManualPaste(rewritten, session: session, images: previewImages,
                    explanation: "Selection changed or couldn't be verified. Rewrite copied; paste it where you want.", canPaste: false)
                return
            }
            pasteboard.clearContents()
            pasteboard.setString(rewritten, forType: .string)

            // Simulate Cmd+V to paste
            self.simulateKeyPress(keyCode: UInt16(kVK_ANSI_V), modifiers: .maskCommand)

            // The result now belongs on the clipboard, even if the status is dismissed.
            self.activeSession = nil

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard self.activeRequestID == pasteID else { return }
                self.activeRewriteTask = nil
                self.activeRequestID = nil
                self.activeSession = nil
                self.onStatusChange?(.done)
                switch presentation {
                case .status:
                    CommandPaletteWindowController.shared.showSuccess(
                        subtitle: isGenerating ? "Text inserted · copied to clipboard" : "Replacement sent · copied to clipboard"
                    )
                case .closePreview:
                    CommandPaletteWindowController.shared.dismissAfterPreviewAction()
                }
                self.isProcessing = false
            }
        }
    }

    private func preserveResultForManualPaste(_ result: String, session: RewriteSession, images: [PromptImageAttachment],
        explanation: String = "Couldn't return to the original app. Rewrite copied; paste it where you want.", canPaste: Bool = true) {
        logger.notice("Generated text retained for manual recovery; no automatic replacement")
        activeRewriteTask = nil
        activeRequestID = nil
        activeSession = nil
        pendingPreview = PendingPreview(result: result, session: session, images: images, canPaste: canPaste)
        didCopyPendingPreview = true
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result, forType: .string)
        onStatusChange?(.done)
        CommandPaletteWindowController.shared.showTextResult(
            text: result,
            title: "Your rewrite",
            subtitle: explanation,
            images: images
        )
    }

    // Poll clipboard changeCount instead of assuming a fixed delay is enough
    private func pollClipboardChange(pasteboard: NSPasteboard, expected: Int, attempts: Int, interval: TimeInterval, completion: @escaping (Bool) -> Void) {
        if pasteboard.changeCount != expected {
            completion(true)
            return
        }
        if attempts <= 0 {
            completion(false)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
            self.pollClipboardChange(pasteboard: pasteboard, expected: expected, attempts: attempts - 1, interval: interval, completion: completion)
        }
    }

    // Save all clipboard items so we can restore them later
    private func saveClipboard(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        var saved: [NSPasteboardItem] = []
        for item in pasteboard.pasteboardItems ?? [] {
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            saved.append(copy)
        }
        return saved
    }

    // Restore previously saved clipboard contents
    private func restoreClipboard(_ pasteboard: NSPasteboard, items: [NSPasteboardItem]) {
        pasteboard.clearContents()
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }

    private static func wordCount(in text: String) -> Int {
        text
            .split { $0.isWhitespace || $0.isNewline }
            .count
    }

    // Show a macOS notification for errors
    private func showErrorNotification(_ message: String) {
        let content = UNMutableNotificationContent()
        content.title = "Companion"
        content.body = "Companion failed: \(message)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // Simulate a key press with modifiers using CGEvent
    private func simulateKeyPress(keyCode: UInt16, modifiers: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return
        }

        keyDown.flags = modifiers
        keyUp.flags = modifiers

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}

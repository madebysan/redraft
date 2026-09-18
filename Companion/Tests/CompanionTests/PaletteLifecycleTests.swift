import AppKit
import XCTest
@testable import Companion

final class PaletteLifecycleTests: XCTestCase {
    @MainActor
    func testInstructionCanBeTheInitialViewWithoutActivatingTheApplication() {
        let palette = CommandPaletteWindowController()
        defer { palette.close() }
        let originalApp = NSWorkspace.shared.frontmostApplication?.processIdentifier
        palette.show(selectedText: "A sample selection", defaultView: .instruction)
        XCTAssertTrue(palette.window!.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(palette.window!.canBecomeMain)
        XCTAssertEqual(palette.window!.frame.width, 340)
        XCTAssertNotNil(palette.window!.firstResponder as? NSTextView)
        XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier, originalApp)
    }

    @MainActor
    func testClickInsideCapsuleCannotBeTreatedAsOutsideDismissal() {
        let palette = CommandPaletteWindowController()
        defer { palette.close() }
        palette.show(selectedText: "Sample selection")
        let frame = palette.window!.frame
        palette.handleOutsideClick(at: NSPoint(x: frame.midX, y: frame.midY))
        XCTAssertTrue(palette.isPaletteVisible, "A click activating the pill must not cancel its action.")
        palette.handleOutsideClick(at: NSPoint(x: frame.maxX + 50, y: frame.midY))
        XCTAssertFalse(palette.isPaletteVisible)
    }

    @MainActor
    func testCapsuleHasTwoActionsAndPencilOpensFocusedInput() {
        let palette = CommandPaletteWindowController()
        defer { palette.close() }
        palette.show(selectedText: "A sample selection")
        func buttons(in view: NSView) -> [NSButton] {
            (view as? NSButton).map { [$0] } ?? view.subviews.flatMap { buttons(in: $0) }
        }
        let actions = buttons(in: palette.window!.contentView!)
        XCTAssertEqual(actions.count, 2)
        XCTAssertTrue(actions.allSatisfy { $0.acceptsFirstMouse(for: nil) })
        XCTAssertTrue(actions.allSatisfy { $0.focusRingType == .none })
        XCTAssertEqual(palette.window!.frame.width, 100) // 80 pt glass + shadow inset.
        let pencil = actions.first { $0.toolTip == "Write an instruction (Tab)" }
        XCTAssertNotNil(pencil)
        pencil?.performClick(nil)
        XCTAssertEqual(palette.window!.frame.width, 340)
        XCTAssertNotNil(palette.window!.firstResponder as? NSTextView)
    }

    @MainActor
    func testCustomInputReleasesFocusBeforeReplacement() {
        let palette = CommandPaletteWindowController()
        defer { palette.close() }
        palette.show(selectedText: "A sample selection")
        palette.showPreviewInstruction("Translate into Spanish")
        XCTAssertNotNil(palette.window!.firstResponder as? NSTextView)
        palette.prepareForReplacement()
        XCTAssertFalse(palette.isPaletteVisible)
        XCTAssertNil(palette.window!.firstResponder as? NSTextView)
        palette.showSuccess()
        XCTAssertTrue(palette.isPaletteVisible)
    }

    @MainActor
    func testLoadingAndCompletionStayIconSized() {
        let palette = CommandPaletteWindowController()
        defer { palette.close() }
        palette.show(selectedText: "A sample selection")
        palette.showRunning(title: "Fix Grammar")
        XCTAssertEqual(palette.window!.frame.size, NSSize(width: 50, height: 50))
        palette.showSuccess()
        XCTAssertEqual(palette.window!.frame.size, NSSize(width: 50, height: 50))
        palette.showError("Try again")
        XCTAssertEqual(palette.window!.frame.size, NSSize(width: 50, height: 50))
    }

    @MainActor
    func testPreviousSuccessDoesNotDismissReopenedPalette() async throws {
        let palette = CommandPaletteWindowController()
        defer { palette.close() }
        palette.show(selectedText: "A sample selection")
        palette.showSuccess()
        palette.show(selectedText: "A new selection")

        try await Task.sleep(nanoseconds: 1_200_000_000)

        XCTAssertTrue(palette.isPaletteVisible, "An old completion must not close a new command.")
    }
}

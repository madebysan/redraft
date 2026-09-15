import AppKit
import XCTest
@testable import Companion

final class NativePasteTests: XCTestCase {
    @MainActor
    func testNativePasteReplacesSelectionSupportsUndoAndKeepsClipboard() {
        let pasteboard = NSPasteboard.general
        let saved = (pasteboard.pasteboardItems ?? []).map { item -> NSPasteboardItem in
            let copy = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { copy.setData(data, forType: type) } }
            return copy
        }
        defer { pasteboard.clearContents(); pasteboard.writeObjects(saved) }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200), styleMask: .titled, backing: .buffered, defer: false)
        let text = NSTextView(frame: window.contentView!.bounds)
        text.allowsUndo = true
        text.isRichText = false
        window.contentView = text
        window.makeFirstResponder(text)
        let original = "Before: he are late. After."
        text.string = original
        text.setSelectedRange((original as NSString).range(of: "he are late"))
        pasteboard.clearContents()
        pasteboard.setString("he is late", forType: .string)
        text.paste(nil)
        XCTAssertEqual(text.string, "Before: he is late. After.")
        XCTAssertEqual(pasteboard.string(forType: .string), "he is late")
        XCTAssertTrue(text.undoManager?.canUndo == true)
        text.undoManager?.undo()
        XCTAssertEqual(text.string, original)
        XCTAssertEqual(pasteboard.string(forType: .string), "he is late")
    }
}

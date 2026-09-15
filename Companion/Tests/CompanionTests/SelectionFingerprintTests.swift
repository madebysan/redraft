import XCTest
@testable import Companion

final class SelectionFingerprintTests: XCTestCase {
    func testSelectionCanBeReadWhenAccessibilityOmitsSelectedText() {
        let document = "Before: The meeting are tomorrow. After."
        let selection = "The meeting are tomorrow."
        let range = (document as NSString).range(of: selection)
        let initial = SelectionFingerprint(text: "", range: range, value: document)
        let afterFocusReturns = SelectionFingerprint(text: selection, range: range, value: document)
        XCTAssertEqual(initial.resolvedSelectedText, selection)
        XCTAssertTrue(initial.matches(afterFocusReturns, expectedText: selection, sameElement: true))
    }

    func testOptionalAccessibilityTextChangingDoesNotInvalidateSameRange() {
        let document = "A café ☕️ needs good coffee."
        let selection = "café ☕️"
        let range = (document as NSString).range(of: selection)
        let initial = SelectionFingerprint(text: selection, range: range, value: document)
        let afterFocusReturns = SelectionFingerprint(text: nil, range: range, value: document)
        XCTAssertTrue(initial.matches(afterFocusReturns, expectedText: selection, sameElement: true))
    }

    func testUnchangedSelectionMatches() {
        let selection = SelectionFingerprint(text: "hello", range: NSRange(location: 0, length: 5), value: "hello world")
        XCTAssertTrue(selection.matches(selection, expectedText: "hello", sameElement: true))
        XCTAssertFalse(selection.matches(selection, expectedText: "hello", sameElement: false))
        XCTAssertFalse(selection.matches(selection, expectedText: "different", sameElement: true))
        let moved = SelectionFingerprint(text: "hello", range: NSRange(location: 6, length: 5), value: "hello hello")
        XCTAssertFalse(selection.matches(moved, expectedText: "hello", sameElement: true))
    }

    func testUnverifiableCaretDoesNotMatch() {
        let unavailable = SelectionFingerprint(text: nil, range: nil, value: nil)
        XCTAssertFalse(unavailable.matches(unavailable, expectedText: "", sameElement: true))
        let caret = SelectionFingerprint(text: "", range: NSRange(location: 2, length: 0), value: "Hi")
        XCTAssertTrue(caret.matches(caret, expectedText: "", sameElement: true))
    }
}

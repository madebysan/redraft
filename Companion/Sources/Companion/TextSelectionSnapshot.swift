import AppKit

struct SelectionFingerprint: Equatable {
    let text: String?
    let range: NSRange?
    let value: String?

    // Some editors omit AXSelectedText, or expose it only while focused. The
    // selected range into AXValue is the same selection, expressed in UTF-16.
    var resolvedSelectedText: String? {
        if let range, let value, let stringRange = Range(range, in: value) {
            return String(value[stringRange])
        }
        if let text, !text.isEmpty { return text }
        if range?.length == 0 { return "" }
        return nil
    }

    func matches(_ current: SelectionFingerprint, expectedText: String, sameElement: Bool) -> Bool {
        guard sameElement,
              resolvedSelectedText == expectedText,
              current.resolvedSelectedText == expectedText else { return false }
        if let range, current.range != range { return false }
        // For insertion, also ensure the surrounding document hasn't changed.
        if expectedText.isEmpty, value != current.value { return false }
        return range != nil || !expectedText.isEmpty
    }
}

struct TextSelectionSnapshot {
    let element: AXUIElement
    let fingerprint: SelectionFingerprint

    static func capture(processID: pid_t) -> TextSelectionSnapshot? {
        let application = AXUIElementCreateApplication(processID)
        guard let focused = attribute(kAXFocusedUIElementAttribute, of: application),
              CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = unsafeBitCast(focused, to: AXUIElement.self)
        var range: NSRange?
        if let value = attribute(kAXSelectedTextRangeAttribute, of: element), CFGetTypeID(value) == AXValueGetTypeID() {
            var cfRange = CFRange()
            if AXValueGetValue(unsafeBitCast(value, to: AXValue.self), .cfRange, &cfRange) {
                range = NSRange(location: cfRange.location, length: cfRange.length)
            }
        }
        return TextSelectionSnapshot(element: element, fingerprint: SelectionFingerprint(
            text: attribute(kAXSelectedTextAttribute, of: element) as? String,
            range: range,
            value: attribute(kAXValueAttribute, of: element) as? String
        ))
    }

    func stillMatches(processID: pid_t, selectedText: String) -> Bool {
        guard let current = Self.capture(processID: processID) else { return false }
        return fingerprint.matches(current.fingerprint, expectedText: selectedText, sameElement: CFEqual(element, current.element))
    }

    private static func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
        return result
    }
}

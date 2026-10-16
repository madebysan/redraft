import AppKit
import ApplicationServices

// The one permission Redraft needs. Both kinds are listed under Privacy & Security → Accessibility.
// The direct build uses the Accessibility API to read and verify the selection. The Mac App Store
// build is sandboxed, where that API is unavailable; it only sends ⌘C and ⌘V (the "post event"
// permission) and verifies the selection by copying it again.
enum Permissions {
    static var isGranted: Bool {
        #if APP_STORE
        CGPreflightPostEventAccess()
        #else
        AXIsProcessTrusted()
        #endif
    }

    // Shows the system prompt and adds Redraft to the Accessibility list if it is missing.
    @discardableResult
    static func request() -> Bool {
        #if APP_STORE
        return CGRequestPostEventAccess()
        #else
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
        #endif
    }
}

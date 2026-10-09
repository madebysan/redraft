import AppKit

@main
struct CompanionApp {
    static func main() {
        // Explicit local configuration command; never print the credential.
        if ProcessInfo.processInfo.arguments.contains("--import-openrouter-key") {
            guard let key = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"], !key.isEmpty else {
                fputs("OPENROUTER_API_KEY is not set.\n", stderr)
                exit(1)
            }
            do {
                let store = CredentialStore(backend: KeychainCredentialBackend(service: "com.santiagoalonso.companion.providers"))
                try store.set(key, for: "openRouterAPIKey")
                print("OpenRouter key saved and verified in Keychain.")
                return
            } catch {
                fputs("Couldn't save the OpenRouter key in Keychain.\n", stderr)
                exit(1)
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--verify-configuration") {
            let settings = UserSettings.shared
            let configured = settings.customPromptRouteID.flatMap { settings.modelRoute(for: $0) } != nil
            let accessible = settings.hasAccess(to: .openRouter)
            let secure = settings.credentialStorageError == nil && settings.writingMigrationError == nil
            print("Capsule model route configured: \(configured)")
            print("OpenRouter key accessible in Keychain: \(accessible)")
            print("Credential migration completed without errors: \(secure)")
            if let recovery = settings.retiredActionsRecoveryURL {
                print("Retired actions recovery: \(recovery.path)")
            }
            exit(configured && accessible && secure ? 0 : 1)
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

import Foundation

// The only remaining saved-action compatibility code. Export first, then retire it.
enum WritingSettingsMigration {
    static let legacyKeys = [
        "savedActions", "savedActionsTemplateVersion", "rewritePrompt", "rewriteMode",
        "improveWritingPrompt", "humanizePrompt", "providerFixGrammar",
        "providerImproveWriting", "providerHumanize", "didAdoptPaidWritingDefault"
    ]
    private struct LegacyAction: Decodable {
        let id: String
        let prompt: String
        let provider: String
        let routeID: String?
    }

    static func migrate(defaults: UserDefaults, recoveryDirectory: URL, defaultPrompt: String,
                        defaultRouteID: String, routeForProvider: (String) -> String?) throws {
        guard !defaults.bool(forKey: "didMigrateWritingSettings") else { return }
        let legacy = legacyKeys.reduce(into: [String: Any]()) { values, key in
            if let value = defaults.object(forKey: key) { values[key] = value }
        }
        let grammar: LegacyAction?
        if let data = defaults.data(forKey: "savedActions") {
            grammar = try JSONDecoder().decode([LegacyAction].self, from: data).first { $0.id == "fix_grammar" }
        } else { grammar = nil }
        let prompt = defaults.string(forKey: "grammarPrompt") ?? grammar?.prompt
            ?? defaults.string(forKey: "rewritePrompt") ?? defaultPrompt
        let routeID = defaults.string(forKey: "grammarRouteID") ?? grammar?.routeID
            ?? (grammar?.provider ?? defaults.string(forKey: "providerFixGrammar")).flatMap(routeForProvider)
            ?? defaultRouteID

        if !legacy.isEmpty {
            let file = recoveryDirectory.appendingPathComponent("saved-actions-\(UUID().uuidString).json")
            var export = legacy
            if let original = defaults.data(forKey: "savedActions") {
                export["savedActions"] = try JSONSerialization.jsonObject(with: original)
                export["originalSavedActionsDataBase64"] = original.base64EncodedString()
            }
            let data = try JSONSerialization.data(withJSONObject: export, options: [.prettyPrinted, .sortedKeys])
            try FileManager.default.createDirectory(at: recoveryDirectory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try data.write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            guard try Data(contentsOf: file) == data else { throw CocoaError(.fileWriteUnknown) }
            defaults.set(file.path, forKey: "retiredActionsRecoveryPath")
        }
        defaults.set(prompt, forKey: "grammarPrompt")
        defaults.set(routeID, forKey: "grammarRouteID")
        if defaults.string(forKey: "customPromptRouteID") == nil {
            defaults.set(defaultRouteID, forKey: "customPromptRouteID")
        }
        defaults.set(true, forKey: "didMigrateWritingSettings")
        for key in legacyKeys { defaults.removeObject(forKey: key) }
    }
}

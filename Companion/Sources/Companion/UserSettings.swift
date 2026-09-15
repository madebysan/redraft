import Foundation

// Wraps UserDefaults for all app settings
final class UserSettings {
    static let shared = UserSettings()

    private let defaults: UserDefaults
    private let credentials: CredentialStore
    private(set) var credentialStorageError: String?
    private(set) var writingMigrationError: String?
    private static let legacyCompanionV2BundleID = "com.santiagoalonso.companion.v2"
    private static let legacyRewriteBundleID = "com.santiagoalonso.rewrite"

    init(defaults suppliedDefaults: UserDefaults? = nil, credentials suppliedCredentials: CredentialStore? = nil, recoveryDirectory suppliedRecoveryDirectory: URL? = nil) {
        let isolated = Bundle.main.bundleIdentifier?.hasSuffix(".preview") == true
            || ProcessInfo.processInfo.processName.hasSuffix("xctest")
            || Bundle.main.bundleURL.pathExtension == "xctest"
            || ProcessInfo.processInfo.arguments.first?.contains(".xctest/") == true
        defaults = suppliedDefaults ?? (isolated ? UserDefaults(suiteName: "CompanionPreview-\(UUID().uuidString)")! : .standard)
        credentials = suppliedCredentials ?? CredentialStore(backend: isolated
            ? MemoryCredentialBackend()
            : KeychainCredentialBackend(service: "com.santiagoalonso.companion.providers"))
        if !isolated && suppliedDefaults == nil {
            migrateLegacyCompanionV2DefaultsIfNeeded()
            migrateLegacyRewriteDefaultsIfNeeded()
        }
        let accounts = [Keys.apiKey, Keys.openAIAPIKey, Keys.deepSeekAPIKey, Keys.falAPIKey, "openRouterAPIKey"]
        do {
            try credentials.migrate(accounts: accounts, from: defaults)
            if !isolated && suppliedDefaults == nil {
                for domain in [Self.legacyCompanionV2BundleID, Self.legacyRewriteBundleID] {
                    if let legacy = UserDefaults(suiteName: domain) { try credentials.migrate(accounts: accounts, from: legacy) }
                }
            }
        } catch { credentialStorageError = error.localizedDescription }
        let recoveryDirectory = suppliedRecoveryDirectory ?? ((isolated || suppliedDefaults != nil)
            ? FileManager.default.temporaryDirectory.appendingPathComponent("CompanionMigration-\(UUID().uuidString)")
            : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Companion/Recovery"))
        do {
            try WritingSettingsMigration.migrate(defaults: defaults, recoveryDirectory: recoveryDirectory,
                defaultPrompt: Self.defaultFixPrompt, defaultRouteID: Self.recommendedWritingRoute.id,
                routeForProvider: { raw in Provider(rawValue: raw).flatMap { self.defaultModelRoute(for: $0)?.id } })
        } catch {
            writingMigrationError = "Couldn't migrate writing settings. Old actions are preserved. Check available disk space and reopen Companion."
        }
    }

    enum Provider: String, CaseIterable, Codable {
        case openAI = "openai"
        case claude = "claude"
        case lmStudio = "lm_studio"
        case deepSeek = "deepseek"
        case fal = "fal"
        case openRouter = "openrouter"

        var label: String {
            switch self {
            case .openAI: return "OpenAI (Cloud)"
            case .claude: return "Claude (Cloud)"
            case .lmStudio: return "LM Studio (Local)"
            case .deepSeek: return "DeepSeek (Cloud)"
            case .fal: return "fal / OpenRouter (Remote)"
            case .openRouter: return "OpenRouter (Cloud)"
            }
        }

        var shortLabel: String {
            switch self {
            case .openAI: return "OpenAI"
            case .claude: return "Claude"
            case .lmStudio: return "Local"
            case .deepSeek: return "DeepSeek"
            case .fal: return "Remote"
            case .openRouter: return "OpenRouter"
            }
        }
    }

    struct ModelRoute: Codable, Equatable, Identifiable {
        let id: String
        var name: String
        var provider: Provider
        var model: String
        var supportsImages: Bool

        var menuTitle: String {
            if provider == .fal {
                return displayModel
            }
            return "\(provider.shortLabel) · \(displayModel)"
        }

        var displayModel: String {
            let cleaned = model.replacingOccurrences(of: "~", with: "")
            guard cleaned.count > 44 else { return cleaned }
            return "\(cleaned.prefix(41))..."
        }

        static func makeID(provider: Provider, model: String) -> String {
            let cleaned = model
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: "~", with: "")
            return "\(provider.rawValue):\(cleaned)"
        }
    }

    struct RemoteCatalogModel: Codable, Equatable, Identifiable {
        let id: String
        var name: String
        var supportsImages: Bool

        var routeModel: String {
            UserSettings.canonicalFalModel(id)
        }

        var displayTitle: String {
            name.isEmpty ? routeModel : name
        }
    }

    private enum Keys {
        static let apiKey = "apiKey"
        static let openAIAPIKey = "openAIAPIKey"
        static let openAIModel = "openAIModel"
        static let claudeModel = "claudeModel"
        static let deepSeekAPIKey = "deepSeekAPIKey"
        static let deepSeekModel = "deepSeekModel"
        static let falAPIKey = "falAPIKey"
        static let falModel = "falModel"
        static let falModelSupportsImages = "falModelSupportsImages"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let launchAtLogin = "launchAtLogin"
        static let shortcutKeyCode = "shortcutKeyCode"
        static let shortcutModifiers = "shortcutModifiers"
        static let lmStudioBaseURL = "lmStudioBaseURL"
        static let lmStudioModel = "lmStudioModel"
        static let lmStudioModelSupportsImages = "lmStudioModelSupportsImages"
        static let lmStudioVisionModels = "lmStudioVisionModels"
        static let fallbackToClaude = "fallbackToClaude"
        static let hasSetFallbackDefault = "hasSetFallbackDefault"
        static let customPromptProvider = "customPromptProvider"
        static let customPromptRouteID = "customPromptRouteID"
        static let configuredModelRoutes = "configuredModelRoutes"
        static let lmStudioKnownModels = "lmStudioKnownModels"
        static let remoteCatalogModels = "remoteCatalogModels"
        static let didImportLegacyCompanionV2Defaults = "didImportLegacyCompanionV2Defaults"
        static let didImportLegacyRewriteDefaults = "didImportLegacyRewriteDefaults"
    }

    // Default prompt — minimal corrections only
    static let defaultFixPrompt = """
        Rewrite the following text, fixing any grammar, spelling, and punctuation errors. \
        Preserve the original tone, style, and meaning. Do not add or remove information. \
        Only return the corrected text with no preamble, explanation, or quotes.
        """

    static let defaultLMStudioBaseURL = "http://127.0.0.1:1234"
    static let defaultOpenAIModel = OpenAIAPI.defaultModelName
    static let defaultClaudeModel = ClaudeAPI.modelName
    static let defaultDeepSeekModel = "deepseek-v4-flash"
    static let defaultFalModel = "deepseek/deepseek-v4.1-flash"
    static let recommendedWritingRoute = ModelRoute(
        id: ModelRoute.makeID(provider: .openRouter, model: "deepseek/deepseek-v4.1-flash"),
        name: "DeepSeek V4.1 Flash", provider: .openRouter,
        model: "deepseek/deepseek-v4.1-flash", supportsImages: true
    )
    static let defaultRemoteCatalogModelCount = defaultRemoteCatalogModels.count
    private static let unavailableFalModels: Set<String> = []

    private func migrateLegacyRewriteDefaultsIfNeeded() {
        importLegacyDefaults(
            from: Self.legacyRewriteBundleID,
            flagKey: Keys.didImportLegacyRewriteDefaults,
            overwriteExisting: false
        )
    }

    private func migrateLegacyCompanionV2DefaultsIfNeeded() {
        importLegacyDefaults(
            from: Self.legacyCompanionV2BundleID,
            flagKey: Keys.didImportLegacyCompanionV2Defaults,
            overwriteExisting: true
        )
    }

    private func importLegacyDefaults(from bundleID: String, flagKey: String, overwriteExisting: Bool) {
        guard !defaults.bool(forKey: flagKey) else { return }
        defer { defaults.set(true, forKey: flagKey) }

        guard let legacyDomain = defaults.persistentDomain(forName: bundleID),
              !legacyDomain.isEmpty else { return }

        let keysToImport = [
            Keys.apiKey,
            Keys.openAIAPIKey,
            Keys.openAIModel,
            Keys.claudeModel,
            Keys.deepSeekAPIKey,
            Keys.deepSeekModel,
            Keys.falAPIKey,
            Keys.falModel,
            Keys.falModelSupportsImages,
            Keys.hasCompletedOnboarding,
            Keys.launchAtLogin,
            Keys.shortcutKeyCode,
            Keys.shortcutModifiers,
            Keys.lmStudioBaseURL,
            Keys.lmStudioModel,
            Keys.lmStudioModelSupportsImages,
            Keys.lmStudioVisionModels,
            Keys.fallbackToClaude,
            Keys.hasSetFallbackDefault,
            Keys.customPromptProvider,
            Keys.customPromptRouteID,
            Keys.configuredModelRoutes,
            Keys.lmStudioKnownModels,
            Keys.remoteCatalogModels,
        ] + WritingSettingsMigration.legacyKeys

        for key in keysToImport where overwriteExisting || defaults.object(forKey: key) == nil {
            if let value = legacyDomain[key] {
                defaults.set(value, forKey: key)
            }
        }
    }

    var customPromptProvider: Provider {
        get {
            guard let raw = defaults.string(forKey: Keys.customPromptProvider),
                  let provider = Provider(rawValue: raw) else {
                return .openRouter
            }
            return provider
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.customPromptProvider) }
    }

    var customPromptRouteID: String? {
        get {
            if let routeID = defaults.string(forKey: Keys.customPromptRouteID),
               modelRoute(for: routeID) != nil {
                return routeID
            }
            return defaultModelRoute(for: customPromptProvider)?.id
        }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Keys.customPromptRouteID)
                if let route = modelRoute(for: newValue) {
                    customPromptProvider = route.provider
                }
            } else {
                defaults.removeObject(forKey: Keys.customPromptRouteID)
            }
        }
    }

    var configuredModelRoutes: [ModelRoute] {
        get {
            let decoded = defaults.data(forKey: Keys.configuredModelRoutes).flatMap {
                try? JSONDecoder().decode([ModelRoute].self, from: $0)
            }
            let routes = decoded?
                .filter { $0.provider == .fal || $0.provider == .openRouter }
                .filter { !$0.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .filter { !Self.isUnavailableFalModel($0.model) }
            if let routes, !routes.isEmpty {
                return normalizedModelRoutes(routes)
            }
            return defaultCloudModelRoutes
        }
        set {
            let normalized = normalizedModelRoutes(newValue)
            guard let data = try? JSONEncoder().encode(normalized) else { return }
            defaults.set(data, forKey: Keys.configuredModelRoutes)
        }
    }

    var lmStudioKnownModels: [String] {
        get {
            guard let data = defaults.data(forKey: Keys.lmStudioKnownModels),
                  let models = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return uniqueModels(models)
        }
        set {
            guard let data = try? JSONEncoder().encode(uniqueModels(newValue)) else { return }
            defaults.set(data, forKey: Keys.lmStudioKnownModels)
        }
    }

    var lmStudioVisionModels: [String] {
        get {
            guard let data = defaults.data(forKey: Keys.lmStudioVisionModels),
                  let models = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return uniqueModels(models)
        }
        set {
            guard let data = try? JSONEncoder().encode(uniqueModels(newValue)) else { return }
            defaults.set(data, forKey: Keys.lmStudioVisionModels)
        }
    }

    func localModelSupportsImages(_ model: String) -> Bool {
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { return false }
        if Self.isKnownLocalVisionModel(model) {
            return true
        }

        let key = normalizedModelKey(model)
        if lmStudioVisionModels.contains(where: { normalizedModelKey($0) == key }) {
            return true
        }

        let selectedKey = normalizedModelKey(lmStudioModel)
        return key == selectedKey && defaults.bool(forKey: Keys.lmStudioModelSupportsImages)
    }

    func setLocalModel(_ model: String, supportsImages: Bool) {
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { return }

        var models = lmStudioVisionModels
        let key = normalizedModelKey(model)
        models.removeAll { normalizedModelKey($0) == key }
        if supportsImages {
            models.append(model)
        }
        lmStudioVisionModels = models

        if normalizedModelKey(lmStudioModel) == key {
            defaults.set(supportsImages, forKey: Keys.lmStudioModelSupportsImages)
        }
    }

    var remoteCatalogModels: [RemoteCatalogModel] {
        get {
            guard let data = defaults.data(forKey: Keys.remoteCatalogModels),
                  let models = try? JSONDecoder().decode([RemoteCatalogModel].self, from: data) else {
                return Self.defaultRemoteCatalogModels
            }
            let availableModels = models.filter { !Self.isUnavailableFalModel($0.routeModel) }
            return availableModels.isEmpty ? Self.defaultRemoteCatalogModels : availableModels
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: Keys.remoteCatalogModels)
            defaults.set(Date(), forKey: "remoteCatalogUpdatedAt")
        }
    }

    func remoteCatalogNeedsRefresh(now: Date = Date()) -> Bool {
        guard let updated = defaults.object(forKey: "remoteCatalogUpdatedAt") as? Date else { return true }
        return now.timeIntervalSince(updated) >= 24 * 60 * 60 || updated > now
    }

    var grammarPrompt: String {
        get {
            let value = defaults.string(forKey: "grammarPrompt") ?? Self.defaultFixPrompt
            return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Self.defaultFixPrompt : value
        }
        set { defaults.set(newValue, forKey: "grammarPrompt") }
    }

    var grammarRouteID: String {
        get { defaults.string(forKey: "grammarRouteID") ?? Self.recommendedWritingRoute.id }
        set { defaults.set(newValue, forKey: "grammarRouteID") }
    }

    var retiredActionsRecoveryURL: URL? {
        defaults.string(forKey: "retiredActionsRecoveryPath").map { URL(fileURLWithPath: $0) }
    }

    func useRecommendedWritingModel() {
        let route = Self.recommendedWritingRoute
        var routes = configuredModelRoutes
        if !routes.contains(where: { $0.id == route.id }) { routes.insert(route, at: 0) }
        configuredModelRoutes = routes
        grammarRouteID = route.id
        customPromptRouteID = route.id
    }

    var inexpensiveFallbackRoute: ModelRoute? {
        let route = Self.recommendedWritingRoute
        return hasAccess(to: route.provider) ? route : nil
    }

    var allModelRoutes: [ModelRoute] {
        normalizedModelRoutes(directModelRoutes + localModelRoutes + configuredModelRoutes)
    }

    var availableModelRoutes: [ModelRoute] {
        allModelRoutes.filter { route in
            hasAccess(to: route.provider)
        }
    }

    func modelRoute(for routeID: String) -> ModelRoute? {
        allModelRoutes.first { $0.id == routeID }
    }

    func availableModelRoute(for routeID: String) -> ModelRoute? {
        availableModelRoutes.first { $0.id == routeID }
    }

    func defaultModelRoute(for provider: Provider) -> ModelRoute? {
        switch provider {
        case .lmStudio, .openAI, .deepSeek, .openRouter:
            return allModelRoutes.first { $0.provider == provider }
        case .claude:
            if hasAccess(to: .claude),
               let claudeRoute = allModelRoutes.first(where: { $0.provider == .claude }) {
                return claudeRoute
            }
            return allModelRoutes.first { $0.provider == .fal }
        case .fal:
            return allModelRoutes.first { $0.provider == .fal }
        }
    }

    func hasAccess(to provider: Provider) -> Bool {
        switch provider {
        case .openAI:
            return !openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .claude:
            return !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .deepSeek:
            return !deepSeekAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .fal:
            return !falAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .openRouter:
            return !openRouterAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .lmStudio:
            return !localModelRoutes.isEmpty
        }
    }

    private var directModelRoutes: [ModelRoute] {
        [
            ModelRoute(
                id: ModelRoute.makeID(provider: .openAI, model: openAIModel),
                name: "OpenAI",
                provider: .openAI,
                model: openAIModel,
                supportsImages: Self.defaultSupportsImages(provider: .openAI, model: openAIModel)
            ),
            ModelRoute(
                id: ModelRoute.makeID(provider: .claude, model: claudeModel),
                name: "Claude",
                provider: .claude,
                model: claudeModel,
                supportsImages: Self.defaultSupportsImages(provider: .claude, model: claudeModel)
            ),
            ModelRoute(
                id: ModelRoute.makeID(provider: .deepSeek, model: deepSeekModel),
                name: "DeepSeek",
                provider: .deepSeek,
                model: deepSeekModel,
                supportsImages: Self.defaultSupportsImages(provider: .deepSeek, model: deepSeekModel)
            )
        ]
    }

    private var defaultCloudModelRoutes: [ModelRoute] {
        [Self.recommendedWritingRoute]
    }

    private static let defaultRemoteCatalogModels: [RemoteCatalogModel] = [
        RemoteCatalogModel(
            id: "deepseek/deepseek-v4.1-flash",
            name: "DeepSeek V4.1 Flash",
            supportsImages: true
        ),
        RemoteCatalogModel(
            id: "google/gemma-3-12b-it",
            name: "Gemma 3 12B",
            supportsImages: true
        ),
        RemoteCatalogModel(
            id: "deepseek/deepseek-v4-flash-0731",
            name: "DeepSeek V4 Flash 0731",
            supportsImages: false
        ),
        RemoteCatalogModel(
            id: "google/gemma-4-26b-a4b-it",
            name: "Gemma 4 26B A4B",
            supportsImages: true
        ),
        RemoteCatalogModel(
            id: "google/gemma-4-26b-a4b-it:free",
            name: "Gemma 4 26B A4B (Free)",
            supportsImages: true
        )
    ]

    private var localModelRoutes: [ModelRoute] {
        let models = preferredLocalModels(uniqueModels(lmStudioKnownModels + [lmStudioModel]))
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return models.map { model in
            ModelRoute(
                id: ModelRoute.makeID(provider: .lmStudio, model: model),
                name: "Local",
                provider: .lmStudio,
                model: model,
                supportsImages: localModelSupportsImages(model)
            )
        }
    }

    private func normalizedModelRoutes(_ routes: [ModelRoute]) -> [ModelRoute] {
        var seen: Set<String> = []
        var normalized: [ModelRoute] = []
        for route in routes {
            let model = route.provider == .fal
                ? Self.canonicalFalModel(route.model)
                : route.model.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !model.isEmpty else { continue }
            let id = Self.ModelRoute.makeID(provider: route.provider, model: model)
            guard !seen.contains(id) else { continue }
            seen.insert(id)
            var copy = route
            copy.model = model
            copy = ModelRoute(
                id: id,
                name: route.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? route.provider.shortLabel
                    : route.name,
                provider: route.provider,
                model: model,
                supportsImages: route.supportsImages || Self.defaultSupportsImages(provider: route.provider, model: model)
            )
            normalized.append(copy)
        }
        return normalized
    }

    static func canonicalFalModel(_ model: String) -> String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutLegacyPrefix = trimmed.hasPrefix("~") ? String(trimmed.dropFirst()) : trimmed

        switch withoutLegacyPrefix.lowercased() {
        case "anthropic/claude-sonnet-latest":
            return "anthropic/claude-sonnet-5"
        case "anthropic/claude-haiku-latest":
            return "anthropic/claude-haiku-4.5"
        default:
            return withoutLegacyPrefix
        }
    }

    private func preferredLocalModels(_ models: [String]) -> [String] {
        models.sorted { lhs, rhs in
            let lhsPriority = localModelPriority(lhs)
            let rhsPriority = localModelPriority(rhs)
            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }

    private func localModelPriority(_ model: String) -> Int {
        let lower = model.lowercased()
        if lower.contains("gemma-4-12b") || lower.contains("gemma4-12b") {
            return 0
        }
        if lower.contains("gemma") {
            return 1
        }
        if normalizedModelKey(model) == normalizedModelKey(lmStudioModel) {
            return 2
        }
        return 3
    }

    private func uniqueModels(_ models: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for model in models {
            let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(trimmed)
        }
        return result
    }

    static func isKnownVisionModel(_ model: String) -> Bool {
        let lower = model.lowercased()
        let markers = [
            "claude",
            "gemini",
            "gpt-4o",
            "gpt-4.1",
            "gpt-5",
            "o3",
            "o4",
            "vision",
            "pixtral",
            "llava",
            "qwen-vl",
            "qwen2-vl",
            "qwen2.5-vl",
            "vlm",
            "omni"
        ]
        return markers.contains { lower.contains($0) }
    }

    static func isKnownLocalVisionModel(_ model: String) -> Bool {
        let lower = model.lowercased()
        let markers = [
            "vision",
            "pixtral",
            "llava",
            "qwen-vl",
            "qwen2-vl",
            "qwen2.5-vl",
            "vlm",
            "omni",
            "moondream",
            "minicpm-v"
        ]
        return markers.contains { lower.contains($0) }
    }

    static func defaultSupportsImages(provider: Provider, model: String) -> Bool {
        switch provider {
        case .openAI:
            return isKnownVisionModel(model)
        case .lmStudio:
            return isKnownLocalVisionModel(model)
        case .claude:
            return true
        case .deepSeek:
            return false
        case .fal:
            return isKnownVisionModel(model)
        case .openRouter:
            return model == Self.recommendedWritingRoute.model || isKnownVisionModel(model)
        }
    }

    static func isUnavailableFalModel(_ model: String) -> Bool {
        unavailableFalModels.contains(normalizedFalModel(model))
    }

    private static func normalizedFalModel(_ model: String) -> String {
        model
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "~", with: "")
    }

    private func normalizedModelKey(_ model: String) -> String {
        model
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    var apiKey: String {
        get { readCredential(Keys.apiKey) }
        set { saveCredential(newValue, account: Keys.apiKey) }
    }

    var openAIAPIKey: String {
        get { readCredential(Keys.openAIAPIKey) }
        set { saveCredential(newValue, account: Keys.openAIAPIKey) }
    }

    var openAIModel: String {
        get {
            let value = defaults.string(forKey: Keys.openAIModel) ?? ""
            return value.isEmpty ? Self.defaultOpenAIModel : value
        }
        set { defaults.set(newValue, forKey: Keys.openAIModel) }
    }

    var claudeModel: String {
        get {
            let value = defaults.string(forKey: Keys.claudeModel) ?? ""
            return value.isEmpty ? Self.defaultClaudeModel : value
        }
        set { defaults.set(newValue, forKey: Keys.claudeModel) }
    }

    var deepSeekAPIKey: String {
        get { readCredential(Keys.deepSeekAPIKey) }
        set { saveCredential(newValue, account: Keys.deepSeekAPIKey) }
    }

    var deepSeekModel: String {
        get {
            let value = defaults.string(forKey: Keys.deepSeekModel) ?? ""
            return value.isEmpty ? Self.defaultDeepSeekModel : value
        }
        set { defaults.set(newValue, forKey: Keys.deepSeekModel) }
    }

    var falAPIKey: String {
        get { readCredential(Keys.falAPIKey) }
        set { saveCredential(newValue, account: Keys.falAPIKey) }
    }

    var openRouterAPIKey: String {
        get { readCredential("openRouterAPIKey") }
        set { saveCredential(newValue, account: "openRouterAPIKey") }
    }

    private func readCredential(_ account: String) -> String {
        do { return try credentials.value(for: account) }
        catch { credentialStorageError = error.localizedDescription; return "" }
    }

    private func saveCredential(_ value: String, account: String) {
        do {
            try credentials.set(value.trimmingCharacters(in: .whitespacesAndNewlines), for: account)
            defaults.removeObject(forKey: account)
            credentialStorageError = nil
        } catch { credentialStorageError = error.localizedDescription }
    }

    var falModel: String {
        get {
            let value = defaults.string(forKey: Keys.falModel) ?? ""
            return value.isEmpty ? Self.defaultFalModel : value
        }
        set { defaults.set(newValue, forKey: Keys.falModel) }
    }

    var falModelSupportsImages: Bool {
        get { defaults.bool(forKey: Keys.falModelSupportsImages) }
        set { defaults.set(newValue, forKey: Keys.falModelSupportsImages) }
    }

    var lmStudioBaseURL: String {
        get {
            let value = defaults.string(forKey: Keys.lmStudioBaseURL) ?? ""
            return value.isEmpty ? Self.defaultLMStudioBaseURL : value
        }
        set { defaults.set(newValue, forKey: Keys.lmStudioBaseURL) }
    }

    var lmStudioModel: String {
        get { defaults.string(forKey: Keys.lmStudioModel) ?? "" }
        set { defaults.set(newValue, forKey: Keys.lmStudioModel) }
    }

    var lmStudioModelSupportsImages: Bool {
        get { localModelSupportsImages(lmStudioModel) }
        set { setLocalModel(lmStudioModel, supportsImages: newValue) }
    }

    var fallbackToClaude: Bool {
        get {
            if !defaults.bool(forKey: Keys.hasSetFallbackDefault) {
                return true
            }
            return defaults.bool(forKey: Keys.fallbackToClaude)
        }
        set {
            defaults.set(newValue, forKey: Keys.fallbackToClaude)
            defaults.set(true, forKey: Keys.hasSetFallbackDefault)
        }
    }

    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Keys.hasCompletedOnboarding) }
        set { defaults.set(newValue, forKey: Keys.hasCompletedOnboarding) }
    }

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: Keys.launchAtLogin) }
        set { defaults.set(newValue, forKey: Keys.launchAtLogin) }
    }

    // Store custom shortcut key code (nil = use default Cmd+Shift+E)
    var shortcutKeyCode: UInt32? {
        get {
            let val = defaults.integer(forKey: Keys.shortcutKeyCode)
            return val == 0 && !defaults.bool(forKey: "hasCustomShortcut") ? nil : UInt32(val)
        }
        set {
            if let newValue {
                defaults.set(Int(newValue), forKey: Keys.shortcutKeyCode)
                defaults.set(true, forKey: "hasCustomShortcut")
            } else {
                defaults.removeObject(forKey: Keys.shortcutKeyCode)
                defaults.set(false, forKey: "hasCustomShortcut")
            }
        }
    }

    var shortcutModifiers: UInt? {
        get {
            let val = defaults.integer(forKey: Keys.shortcutModifiers)
            return val == 0 && !defaults.bool(forKey: "hasCustomShortcut") ? nil : UInt(val)
        }
        set {
            if let newValue {
                defaults.set(Int(newValue), forKey: Keys.shortcutModifiers)
            } else {
                defaults.removeObject(forKey: Keys.shortcutModifiers)
            }
        }
    }
}

import AppKit

// The model block of Settings: one switch between Local and Cloud, and only that branch's controls.
@MainActor
final class ModelsSettingsPane: NSObject, NSTextFieldDelegate {
    let view: NSStackView

    private let settings = UserSettings.shared
    private var modeControl: NSSegmentedControl!
    private var localBox: NSView!
    private var cloudBox: NSView!

    // Local
    private var localStatusIcon: NSImageView!
    private var localStatusLabel: NSTextField!
    private var localRefreshButton: NSButton!
    private var localModelPopup: NSPopUpButton!
    private var localVisionCheckbox: NSButton!
    private var fallbackCheckbox: NSButton!
    private var fallbackHelp: NSTextField!
    private var moreButton: NSButton!
    private var moreStack: NSStackView!
    private var serverField: NSTextField!

    // Cloud
    private var providerPopup: NSPopUpButton!
    private var keyField: NSSecureTextField!
    private var keyLinkButton: NSButton!
    private var keyStatusLabel: NSTextField!
    private var keyCheckTask: Task<Void, Never>?
    private var openRouterModelRow: NSView!
    private var openRouterPopup: NSPopUpButton!
    private var catalogStatusLabel: NSTextField!
    private var directModelRow: NSView!
    private var directModelField: NSTextField!

    private var catalogModels: [UserSettings.RemoteCatalogModel] = []
    private var isLoadingCatalog = false
    private var isLoadingLocalModels = false

    private let labelWidth: CGFloat = 110
    private static let recommendedTitle = "Recommended · Gemini Flash Lite"

    override init() {
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 16
        view = stack
        super.init()
        build(in: stack)
        catalogModels = settings.remoteCatalogModels
        syncFromSettings()
    }

    // Called when the pane becomes visible.
    func paneDidAppear() {
        syncFromSettings()
        if settings.modelMode == .local {
            Task { @MainActor in await self.loadLocalModels(userInitiated: false) }
        } else if settings.cloudProvider == .openRouter, settings.remoteCatalogNeedsRefresh() {
            Task { @MainActor in await self.loadCatalog() }
        }
    }

    // MARK: Layout

    private func build(in stack: NSStackView) {
        modeControl = NSSegmentedControl(labels: UserSettings.ModelMode.allCases.map(\.title),
            trackingMode: .selectOne, target: self, action: #selector(modeChanged))
        modeControl.segmentStyle = .rounded
        modeControl.setContentHuggingPriority(.defaultLow, for: .horizontal)
        for index in 0..<modeControl.segmentCount { modeControl.setWidth(0, forSegment: index) }
        let modeRow = NSStackView(views: [modeControl])
        modeRow.orientation = .horizontal
        modeRow.alignment = .centerY
        stack.addArrangedSubview(modeRow)
        modeControl.widthAnchor.constraint(equalTo: modeRow.widthAnchor).isActive = true
        modeRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        localBox = makeBox { section in buildLocal(section) }
        stack.addArrangedSubview(localBox)
        localBox.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        cloudBox = makeBox { section in buildCloud(section) }
        stack.addArrangedSubview(cloudBox)
        cloudBox.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func buildLocal(_ section: NSStackView) {
        let intro = NSStackView()
        intro.orientation = .horizontal
        intro.alignment = .firstBaseline
        intro.spacing = 4
        intro.addArrangedSubview(makeHelp("Runs a model on this Mac through LM Studio. Nothing leaves your computer."))
        intro.addArrangedSubview(makeLink("Set up LM Studio", action: #selector(openLMStudioSite)))
        section.addArrangedSubview(intro)

        localStatusIcon = NSImageView()
        localStatusIcon.translatesAutoresizingMaskIntoConstraints = false
        localStatusIcon.widthAnchor.constraint(equalToConstant: 16).isActive = true
        localStatusIcon.heightAnchor.constraint(equalToConstant: 16).isActive = true
        localStatusLabel = NSTextField(labelWithString: "")
        localStatusLabel.font = .systemFont(ofSize: 12)
        localStatusLabel.lineBreakMode = .byTruncatingTail
        localStatusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        localRefreshButton = makeButton("Refresh", action: #selector(refreshLocalModels))
        let statusRow = NSStackView(views: [localStatusIcon, localStatusLabel, localRefreshButton])
        statusRow.orientation = .horizontal
        statusRow.alignment = .centerY
        statusRow.spacing = 8
        section.addArrangedSubview(statusRow)
        statusRow.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true

        localModelPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        localModelPopup.target = self
        localModelPopup.action = #selector(localModelChanged)
        localModelPopup.setContentHuggingPriority(.defaultLow, for: .horizontal)
        section.addArrangedSubview(makeRow(label: "Model", control: localModelPopup))

        fallbackCheckbox = NSButton(checkboxWithTitle: "If the local model fails, use the cloud model", target: self, action: #selector(toggleFallback))
        section.addArrangedSubview(makeRow(label: "", control: fallbackCheckbox))
        fallbackHelp = makeHelp("")
        section.addArrangedSubview(makeRow(label: "", control: fallbackHelp))

        moreButton = makeLink("More options", action: #selector(toggleMore))
        section.addArrangedSubview(makeRow(label: "", control: moreButton))

        localVisionCheckbox = NSButton(checkboxWithTitle: "This model can read images", target: self, action: #selector(toggleLocalVision))
        serverField = makeTextField(value: settings.lmStudioBaseURL, placeholder: UserSettings.defaultLMStudioBaseURL, monospaced: true)
        serverField.delegate = self
        serverField.target = self
        serverField.action = #selector(serverChanged)
        moreStack = NSStackView(views: [makeRow(label: "", control: localVisionCheckbox), makeRow(label: "Server address", control: serverField)])
        moreStack.orientation = .vertical
        moreStack.alignment = .leading
        moreStack.spacing = 10
        section.addArrangedSubview(moreStack)
        moreStack.isHidden = settings.lmStudioBaseURL == UserSettings.defaultLMStudioBaseURL
        moreButton.title = moreStack.isHidden ? "More options" : "Fewer options"
    }

    private func buildCloud(_ section: NSStackView) {
        section.addArrangedSubview(makeHelp("Uses your own API key. The provider bills you directly; the key stays in macOS Keychain."))

        providerPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        providerPopup.target = self
        providerPopup.action = #selector(providerChanged)
        providerPopup.setContentHuggingPriority(.defaultLow, for: .horizontal)
        section.addArrangedSubview(makeRow(label: "Provider", control: providerPopup))

        keyField = NSSecureTextField(frame: .zero)
        keyField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        keyField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        keyField.delegate = self
        keyField.target = self
        keyField.action = #selector(keyChanged)
        section.addArrangedSubview(makeRow(label: "API key", control: keyField))

        keyLinkButton = makeLink("Get a key", action: #selector(openKeyPage))
        keyStatusLabel = makeHelp("")
        let keyFooter = NSStackView(views: [keyLinkButton, keyStatusLabel])
        keyFooter.orientation = .horizontal
        keyFooter.alignment = .firstBaseline
        keyFooter.spacing = 12
        section.addArrangedSubview(makeRow(label: "", control: keyFooter))

        openRouterPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        openRouterPopup.target = self
        openRouterPopup.action = #selector(openRouterPopupChanged)
        openRouterPopup.setContentHuggingPriority(.defaultLow, for: .horizontal)
        openRouterPopup.autoenablesItems = false
        openRouterModelRow = makeRow(label: "Model", control: openRouterPopup)
        section.addArrangedSubview(openRouterModelRow)
        catalogStatusLabel = makeHelp("")
        section.addArrangedSubview(makeRow(label: "", control: catalogStatusLabel))

        directModelField = makeTextField(value: "", placeholder: "", monospaced: true)
        directModelField.delegate = self
        directModelField.target = self
        directModelField.action = #selector(directModelChanged)
        directModelRow = makeRow(label: "Model", control: directModelField)
        section.addArrangedSubview(directModelRow)
    }

    // MARK: Sync

    private func syncFromSettings() {
        let mode = settings.modelMode
        modeControl.selectedSegment = mode == .local ? 0 : 1
        localBox.isHidden = mode != .local
        cloudBox.isHidden = mode != .cloud
        syncLocal()
        syncCloud()
    }

    private func syncLocal() {
        let models = settings.lmStudioKnownModels
        localModelPopup.removeAllItems()
        if models.isEmpty {
            localModelPopup.addItem(withTitle: "- no models loaded -")
            localModelPopup.isEnabled = false
        } else {
            localModelPopup.addItems(withTitles: models)
            localModelPopup.isEnabled = true
            if models.contains(settings.lmStudioModel) {
                localModelPopup.selectItem(withTitle: settings.lmStudioModel)
            } else {
                localModelPopup.selectItem(at: 0)
            }
        }
        updateLocalVisionCheckbox()
        if localStatusLabel.stringValue.isEmpty {
            setLocalStatus(models.isEmpty ? "Not connected yet." : "\(models.count) model\(models.count == 1 ? "" : "s") known.", tone: .neutral)
        }
        fallbackCheckbox.state = settings.fallbackToClaude ? .on : .off
        if let fallback = settings.cloudFallbackRoute {
            fallbackCheckbox.isEnabled = true
            fallbackHelp.stringValue = "Falls back to \(fallback.menuTitle)."
        } else {
            fallbackCheckbox.isEnabled = false
            fallbackHelp.stringValue = "Add a key under Cloud to enable a fallback."
        }
        serverField.stringValue = settings.lmStudioBaseURL
    }

    private func syncCloud() {
        let provider = settings.cloudProvider
        providerPopup.removeAllItems()
        var providers: [UserSettings.Provider] = [.openRouter, .openAI, .claude, .deepSeek]
        if provider == .fal || !settings.falAPIKey.isEmpty { providers.append(.fal) }
        for candidate in providers {
            providerPopup.addItem(withTitle: Self.providerTitle(candidate))
            providerPopup.lastItem?.representedObject = candidate.rawValue
        }
        if let index = providers.firstIndex(of: provider) { providerPopup.selectItem(at: index) }

        keyField.stringValue = settings.apiKey(for: provider)
        keyField.placeholderString = Self.keyPlaceholder(provider)
        keyLinkButton.title = "Get \(Self.providerTitle(provider).hasPrefix("O") ? "an" : "a") \(Self.providerTitle(provider)) key"
        keyLinkButton.isHidden = Self.keyPageURL(provider) == nil
        if let error = settings.credentialStorageError {
            setKeyStatus(error, tone: .warning)
        } else if keyStatusLabel.textColor != .systemGreen {
            setKeyStatus(settings.hasAccess(to: provider) ? "Saved in Keychain." : "", tone: .neutral)
        }

        let isOpenRouter = provider == .openRouter
        openRouterModelRow.isHidden = !isOpenRouter
        catalogStatusLabel.isHidden = !isOpenRouter
        directModelRow.isHidden = isOpenRouter
        if isOpenRouter {
            syncOpenRouterPopup()
        } else {
            directModelField.stringValue = Self.directModel(provider, settings)
            directModelField.placeholderString = Self.directModelDefault(provider)
        }
    }

    // Recommended first, then the current pick if it is something else, then the whole catalog
    // grouped by vendor in submenus. Submenu items set the selection themselves.
    private func syncOpenRouterPopup() {
        openRouterPopup.removeAllItems()
        openRouterPopup.addItem(withTitle: Self.recommendedTitle)
        openRouterPopup.lastItem?.representedObject = UserSettings.OpenRouterSelection.recommended.storedValue
        switch settings.openRouterSelection {
        case .recommended:
            openRouterPopup.selectItem(at: 0)
        case .model(let model):
            let title = catalogModels.first { $0.id == model }?.displayTitle ?? model
            openRouterPopup.addItem(withTitle: "\(title)  (\(model))")
            openRouterPopup.lastItem?.representedObject = model
            openRouterPopup.selectItem(at: 1)
        }
        openRouterPopup.menu?.addItem(.separator())
        for group in Self.catalogGroups(catalogModels) {
            let item = NSMenuItem(title: group.vendor, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: group.vendor)
            for model in group.models {
                let entry = NSMenuItem(title: model.title + (model.supportsImages ? "  · Images" : ""),
                    action: #selector(catalogItemChosen(_:)), keyEquivalent: "")
                entry.target = self
                entry.representedObject = model.id
                entry.toolTip = model.id
                submenu.addItem(entry)
            }
            item.submenu = submenu
            openRouterPopup.menu?.addItem(item)
        }
        openRouterPopup.menu?.addItem(.separator())
        let refresh = NSMenuItem(title: "Refresh catalog", action: #selector(refreshCatalog), keyEquivalent: "")
        refresh.target = self
        openRouterPopup.menu?.addItem(refresh)
        if !isLoadingCatalog {
            catalogStatusLabel.stringValue = catalogModels.isEmpty ? "The catalog hasn't loaded yet." : "\(catalogModels.count) models in the menu, grouped by vendor."
            catalogStatusLabel.textColor = .tertiaryLabelColor
        }
    }

    struct CatalogGroup: Equatable {
        struct Model: Equatable { let id: String; let title: String; let supportsImages: Bool }
        let vendor: String
        let models: [Model]
    }

    // "AionLabs: Aion 3.5" groups under AionLabs; a name without a colon groups by its id prefix.
    static func catalogGroups(_ models: [UserSettings.RemoteCatalogModel]) -> [CatalogGroup] {
        var buckets: [String: [CatalogGroup.Model]] = [:]
        for model in models {
            let name = model.displayTitle
            let vendor: String
            let title: String
            if let range = name.range(of: ": ") {
                vendor = String(name[..<range.lowerBound])
                title = String(name[range.upperBound...])
            } else {
                vendor = model.id.split(separator: "/").first.map(String.init) ?? "Other"
                title = name
            }
            buckets[vendor, default: []].append(.init(id: model.id, title: title, supportsImages: model.supportsImages))
        }
        return buckets.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }.map { vendor in
            CatalogGroup(vendor: vendor, models: buckets[vendor]!.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending })
        }
    }

    @objc private func catalogItemChosen(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        settings.openRouterSelection = .model(id)
        syncCloud()
    }

    // MARK: Actions

    @objc private func modeChanged() {
        settings.modelMode = modeControl.selectedSegment == 0 ? .local : .cloud
        syncFromSettings()
        if settings.modelMode == .local {
            Task { @MainActor in await self.loadLocalModels(userInitiated: false) }
        }
    }

    @objc private func openLMStudioSite() {
        if let url = URL(string: "https://lmstudio.ai") { NSWorkspace.shared.open(url) }
    }

    @objc private func refreshLocalModels() {
        Task { @MainActor in await self.loadLocalModels(userInitiated: true) }
    }

    @objc private func localModelChanged() {
        guard let title = localModelPopup.selectedItem?.title, !title.hasPrefix("-") else { return }
        settings.lmStudioModel = title
        settings.applyLocalSelection()
        updateLocalVisionCheckbox()
    }

    @objc private func toggleLocalVision() {
        guard let title = localModelPopup.selectedItem?.title, !title.hasPrefix("-") else { return }
        settings.setLocalModel(title, supportsImages: localVisionCheckbox.state == .on)
    }

    @objc private func toggleFallback() {
        settings.fallbackToClaude = fallbackCheckbox.state == .on
    }

    @objc private func toggleMore() {
        moreStack.isHidden.toggle()
        moreButton.title = moreStack.isHidden ? "More options" : "Fewer options"
    }

    @objc private func serverChanged() {
        settings.lmStudioBaseURL = serverField.stringValue
        serverField.stringValue = settings.lmStudioBaseURL
    }

    @objc private func providerChanged() {
        guard let raw = providerPopup.selectedItem?.representedObject as? String,
              let provider = UserSettings.Provider(rawValue: raw) else { return }
        settings.cloudProvider = provider
        setKeyStatus("", tone: .neutral)
        syncCloud()
        if provider == .openRouter, settings.remoteCatalogNeedsRefresh() {
            Task { @MainActor in await self.loadCatalog() }
        }
    }

    @objc private func keyChanged() {
        settings.setAPIKey(keyField.stringValue, for: settings.cloudProvider)
        settings.applyCloudSelection()
        if let error = settings.credentialStorageError {
            setKeyStatus(error, tone: .warning)
            return
        }
        scheduleKeyCheck()
    }

    // Checks the key a moment after typing stops, with a free read-only request where the
    // provider offers one. Nothing to press.
    private func scheduleKeyCheck() {
        keyCheckTask?.cancel()
        let provider = settings.cloudProvider
        let key = keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { setKeyStatus("", tone: .neutral); return }
        guard ProviderKeyCheck.request(provider: provider, key: key) != nil else {
            setKeyStatus("Saved in Keychain.", tone: .neutral)
            return
        }
        setKeyStatus("Checking…", tone: .neutral)
        keyCheckTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            do {
                let message = try await ProviderKeyCheck.check(provider: provider, key: key)
                guard !Task.isCancelled else { return }
                self.setKeyStatus(message, tone: .success)
            } catch {
                guard !Task.isCancelled else { return }
                self.setKeyStatus(error.localizedDescription, tone: .warning)
            }
        }
    }

    @objc private func openKeyPage() {
        if let url = Self.keyPageURL(settings.cloudProvider) { NSWorkspace.shared.open(url) }
    }

    @objc private func openRouterPopupChanged() {
        guard let raw = openRouterPopup.selectedItem?.representedObject as? String else { return }
        settings.openRouterSelection = UserSettings.OpenRouterSelection(storedValue: raw)
        syncCloud()
    }

    @objc private func refreshCatalog() {
        Task { @MainActor in await self.loadCatalog() }
    }

    @objc private func directModelChanged() {
        let provider = settings.cloudProvider
        let value = directModelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        switch provider {
        case .openAI: settings.openAIModel = value
        case .claude: settings.claudeModel = value
        case .deepSeek: settings.deepSeekModel = value
        case .fal: settings.falModel = value
        default: break
        }
        // Direct route IDs include the model name, so re-point the Capsule at the new one.
        settings.applyCloudSelection()
    }

    // MARK: Loading

    @MainActor
    private func loadLocalModels(userInitiated: Bool) async {
        guard !isLoadingLocalModels else { return }
        isLoadingLocalModels = true
        defer { isLoadingLocalModels = false }
        localRefreshButton.isEnabled = false
        setLocalStatus("Connecting to \(settings.lmStudioBaseURL)...", tone: .neutral)
        do {
            let models = try await LMStudioAPI.shared.listModels()
            settings.lmStudioKnownModels = models
            if models.isEmpty {
                setLocalStatus("LM Studio is running, but no model is loaded. Load one in LM Studio, then Refresh.", tone: .warning)
            } else {
                if !models.contains(settings.lmStudioModel) { settings.lmStudioModel = models[0] }
                if settings.modelMode == .local { settings.applyLocalSelection() }
                setLocalStatus("Connected. \(models.count) model\(models.count == 1 ? "" : "s") loaded.", tone: .success)
            }
        } catch {
            setLocalStatus(userInitiated ? error.localizedDescription
                : "LM Studio isn't reachable. Start its server, then Refresh.", tone: userInitiated ? .error : .warning)
        }
        localRefreshButton.isEnabled = true
        syncLocal()
    }

    @MainActor
    private func loadCatalog() async {
        guard !isLoadingCatalog else { return }
        isLoadingCatalog = true
        catalogStatusLabel.stringValue = "Loading the OpenRouter catalog…"
        catalogStatusLabel.textColor = .tertiaryLabelColor
        var failed = false
        do {
            let models = try await OpenRouterModelsAPI.shared.listModels()
            settings.remoteCatalogModels = models
            catalogModels = models
        } catch {
            catalogModels = settings.remoteCatalogModels
            failed = true
        }
        isLoadingCatalog = false
        syncOpenRouterPopup()
        if failed {
            catalogStatusLabel.stringValue = "Couldn't refresh the catalog. Showing the saved list."
            catalogStatusLabel.textColor = .systemOrange
        }
    }

    // MARK: Text fields

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        if field === keyField { keyChanged() }
        else if field === directModelField { directModelChanged() }
        else if field === serverField { serverChanged() }
    }

    // MARK: Helpers

    private enum Tone { case neutral, success, warning, error }

    private func setLocalStatus(_ text: String, tone: Tone) {
        localStatusLabel.stringValue = text
        let (symbol, color): (String, NSColor) = {
            switch tone {
            case .neutral: return ("circle.dotted", .tertiaryLabelColor)
            case .success: return ("checkmark.circle.fill", .systemGreen)
            case .warning: return ("exclamationmark.circle.fill", .systemOrange)
            case .error: return ("xmark.circle.fill", .systemRed)
            }
        }()
        localStatusIcon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        localStatusIcon.contentTintColor = color
        localStatusLabel.textColor = tone == .neutral ? .secondaryLabelColor : .labelColor
    }

    private func setKeyStatus(_ text: String, tone: Tone) {
        keyStatusLabel.stringValue = text
        switch tone {
        case .neutral: keyStatusLabel.textColor = .tertiaryLabelColor
        case .success: keyStatusLabel.textColor = .systemGreen
        case .warning, .error: keyStatusLabel.textColor = .systemOrange
        }
    }

    private func updateLocalVisionCheckbox() {
        let selected = localModelPopup.selectedItem?.title ?? ""
        let isReal = !selected.isEmpty && !selected.hasPrefix("-")
        localVisionCheckbox.isEnabled = isReal
        localVisionCheckbox.state = isReal && settings.localModelSupportsImages(selected) ? .on : .off
    }

    private func makeBox(build: (NSStackView) -> Void) -> NSView {
        let box = NSBox()
        box.translatesAutoresizingMaskIntoConstraints = false
        box.boxType = .custom
        box.titlePosition = .noTitle
        box.borderColor = .separatorColor
        box.borderWidth = 1
        box.cornerRadius = 8
        box.fillColor = .controlBackgroundColor
        let section = NSStackView()
        section.translatesAutoresizingMaskIntoConstraints = false
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 10
        box.addSubview(section)
        build(section)
        NSLayoutConstraint.activate([
            section.topAnchor.constraint(equalTo: box.topAnchor, constant: 14),
            section.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 14),
            section.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -14),
            section.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -14),
        ])
        return box
    }

    private func makeRow(label: String, control: NSView) -> NSStackView {
        let row = NSStackView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        let labelField = NSTextField(labelWithString: label)
        labelField.font = .systemFont(ofSize: 12)
        labelField.textColor = .secondaryLabelColor
        labelField.alignment = .right
        labelField.widthAnchor.constraint(equalToConstant: labelWidth).isActive = true
        labelField.setContentHuggingPriority(.required, for: .horizontal)
        row.addArrangedSubview(labelField)
        row.addArrangedSubview(control)
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        control.widthAnchor.constraint(greaterThanOrEqualToConstant: 330).isActive = true
        return row
    }

    private func makeHelp(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .tertiaryLabelColor
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.widthAnchor.constraint(lessThanOrEqualToConstant: 460).isActive = true
        return label
    }

    private func makeTextField(value: String, placeholder: String, monospaced: Bool) -> NSTextField {
        let field = NSTextField(frame: .zero)
        field.stringValue = value
        field.placeholderString = placeholder
        field.font = monospaced ? .monospacedSystemFont(ofSize: 12, weight: .regular) : .systemFont(ofSize: 12)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }

    private func makeButton(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .small
        return button
    }

    private func makeLink(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.isBordered = false
        button.font = .systemFont(ofSize: 11)
        button.contentTintColor = .linkColor
        button.alignment = .left
        button.setButtonType(.momentaryChange)
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    static func providerTitle(_ provider: UserSettings.Provider) -> String {
        switch provider {
        case .openRouter: return "OpenRouter"
        case .openAI: return "OpenAI"
        case .claude: return "Claude"
        case .deepSeek: return "DeepSeek"
        case .fal: return "fal (legacy)"
        case .lmStudio: return "Local"
        }
    }

    static func keyPlaceholder(_ provider: UserSettings.Provider) -> String {
        switch provider {
        case .openRouter: return "OPENROUTER_API_KEY"
        case .openAI: return "OPENAI_API_KEY"
        case .claude: return "ANTHROPIC_API_KEY"
        case .deepSeek: return "DEEPSEEK_API_KEY"
        case .fal: return "FAL_KEY"
        case .lmStudio: return ""
        }
    }

    static func keyPageURL(_ provider: UserSettings.Provider) -> URL? {
        switch provider {
        case .openRouter: return URL(string: "https://openrouter.ai/settings/keys")
        case .openAI: return URL(string: "https://platform.openai.com/api-keys")
        case .claude: return URL(string: "https://console.anthropic.com/settings/keys")
        case .deepSeek: return URL(string: "https://platform.deepseek.com/api_keys")
        case .fal: return URL(string: "https://fal.ai/dashboard/keys")
        case .lmStudio: return nil
        }
    }

    static func directModel(_ provider: UserSettings.Provider, _ settings: UserSettings) -> String {
        switch provider {
        case .openAI: return settings.openAIModel
        case .claude: return settings.claudeModel
        case .deepSeek: return settings.deepSeekModel
        case .fal: return settings.falModel
        default: return ""
        }
    }

    static func directModelDefault(_ provider: UserSettings.Provider) -> String {
        switch provider {
        case .openAI: return UserSettings.defaultOpenAIModel
        case .claude: return UserSettings.defaultClaudeModel
        case .deepSeek: return UserSettings.defaultDeepSeekModel
        case .fal: return UserSettings.defaultFalModel
        default: return ""
        }
    }
}

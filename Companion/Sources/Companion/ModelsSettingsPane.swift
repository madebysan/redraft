import AppKit

// Settings → Models: one switch between Local and Cloud, and only that branch's controls.
@MainActor
final class ModelsSettingsPane: NSObject, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    let view: NSView

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
    private var advancedButton: NSButton!
    private var serverRow: NSView!
    private var serverField: NSTextField!

    // Cloud
    private var providerPopup: NSPopUpButton!
    private var keyField: NSSecureTextField!
    private var checkKeyButton: NSButton!
    private var keyLinkButton: NSButton!
    private var keyStatusLabel: NSTextField!
    private var openRouterModelRow: NSView!
    private var openRouterPopup: NSPopUpButton!
    private var catalogRow: NSView!
    private var catalogFilterField: NSTextField!
    private var catalogRefreshButton: NSButton!
    private var catalogTable: NSTableView!
    private var catalogScroll: NSScrollView!
    private var catalogStatusLabel: NSTextField!
    private var directModelRow: NSView!
    private var directModelField: NSTextField!
    private var cloudSummaryLabel: NSTextField!

    private var catalogModels: [UserSettings.RemoteCatalogModel] = []
    private var visibleCatalogModels: [UserSettings.RemoteCatalogModel] = []
    private var isLoadingCatalog = false
    private var isLoadingLocalModels = false
    private var isSelectingCatalogRow = false

    private let labelWidth: CGFloat = 110
    private static let recommendedTitle = "Recommended · Gemini Flash Lite"

    override init() {
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        view = scrollView
        super.init()
        build(in: scrollView)
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

    private func build(in scrollView: NSScrollView) {
        let container = FlippedModelsDocumentView()
        container.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = container

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 16
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -22),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
        ])

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

        localVisionCheckbox = NSButton(checkboxWithTitle: "This model can read images", target: self, action: #selector(toggleLocalVision))
        section.addArrangedSubview(localVisionCheckbox)

        fallbackCheckbox = NSButton(checkboxWithTitle: "If the local model fails, use the cloud model", target: self, action: #selector(toggleFallback))
        section.addArrangedSubview(fallbackCheckbox)
        fallbackHelp = makeHelp("")
        section.addArrangedSubview(fallbackHelp)

        advancedButton = makeLink("Advanced", action: #selector(toggleAdvanced))
        section.addArrangedSubview(advancedButton)

        serverField = makeTextField(value: settings.lmStudioBaseURL, placeholder: UserSettings.defaultLMStudioBaseURL, monospaced: true)
        serverField.delegate = self
        serverField.target = self
        serverField.action = #selector(serverChanged)
        serverRow = makeRow(label: "Server address", control: serverField)
        section.addArrangedSubview(serverRow)
        serverRow.isHidden = settings.lmStudioBaseURL == UserSettings.defaultLMStudioBaseURL
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
        checkKeyButton = makeButton("Check key", action: #selector(checkKey))
        let keyControl = NSStackView(views: [keyField, checkKeyButton])
        keyControl.orientation = .horizontal
        keyControl.alignment = .centerY
        keyControl.spacing = 8
        section.addArrangedSubview(makeRow(label: "API key", control: keyControl))

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
        openRouterModelRow = makeRow(label: "Model", control: openRouterPopup)
        section.addArrangedSubview(openRouterModelRow)

        catalogFilterField = makeTextField(value: "", placeholder: "Search the OpenRouter catalog", monospaced: false)
        catalogFilterField.delegate = self
        catalogRefreshButton = makeButton("Refresh", action: #selector(refreshCatalog))
        let filterControl = NSStackView(views: [catalogFilterField, catalogRefreshButton])
        filterControl.orientation = .horizontal
        filterControl.alignment = .centerY
        filterControl.spacing = 8

        catalogTable = NSTableView()
        catalogTable.headerView = nil
        catalogTable.rowHeight = 36
        catalogTable.intercellSpacing = NSSize(width: 0, height: 2)
        catalogTable.backgroundColor = .clear
        catalogTable.style = .inset
        catalogTable.allowsEmptySelection = true
        catalogTable.delegate = self
        catalogTable.dataSource = self
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("model"))
        column.resizingMask = .autoresizingMask
        catalogTable.addTableColumn(column)
        catalogScroll = NSScrollView()
        catalogScroll.translatesAutoresizingMaskIntoConstraints = false
        catalogScroll.hasVerticalScroller = true
        catalogScroll.borderType = .bezelBorder
        catalogScroll.documentView = catalogTable
        catalogScroll.heightAnchor.constraint(equalToConstant: 170).isActive = true
        catalogStatusLabel = makeHelp("")

        let catalogStack = NSStackView(views: [filterControl, catalogScroll, catalogStatusLabel])
        catalogStack.orientation = .vertical
        catalogStack.alignment = .width
        catalogStack.spacing = 6
        catalogRow = makeRow(label: "Or pick one", control: catalogStack)
        section.addArrangedSubview(catalogRow)
        catalogScroll.widthAnchor.constraint(equalTo: catalogStack.widthAnchor).isActive = true

        directModelField = makeTextField(value: "", placeholder: "", monospaced: true)
        directModelField.delegate = self
        directModelField.target = self
        directModelField.action = #selector(directModelChanged)
        directModelRow = makeRow(label: "Model", control: directModelField)
        section.addArrangedSubview(directModelRow)

        cloudSummaryLabel = makeHelp("")
        section.addArrangedSubview(cloudSummaryLabel)
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
        checkKeyButton.isEnabled = ProviderKeyCheck.request(provider: provider, key: "x") != nil
        if let error = settings.credentialStorageError {
            setKeyStatus(error, tone: .warning)
        } else if keyStatusLabel.textColor != .systemGreen {
            setKeyStatus(settings.hasAccess(to: provider) ? "Saved in Keychain." : "", tone: .neutral)
        }

        let isOpenRouter = provider == .openRouter
        openRouterModelRow.isHidden = !isOpenRouter
        catalogRow.isHidden = !isOpenRouter
        directModelRow.isHidden = isOpenRouter
        if isOpenRouter {
            syncOpenRouterPopup()
            refreshCatalogTable()
        } else {
            directModelField.stringValue = Self.directModel(provider, settings)
            directModelField.placeholderString = Self.directModelDefault(provider)
        }
        cloudSummaryLabel.stringValue = "The Capsule uses: \(settings.setupSummary)"
    }

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

    @objc private func toggleAdvanced() {
        serverRow.isHidden.toggle()
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
        if let error = settings.credentialStorageError {
            setKeyStatus(error, tone: .warning)
        } else {
            setKeyStatus(settings.hasAccess(to: settings.cloudProvider) ? "Saved in Keychain." : "", tone: .neutral)
        }
        settings.applyCloudSelection()
        cloudSummaryLabel.stringValue = "The Capsule uses: \(settings.setupSummary)"
    }

    @objc private func checkKey() {
        let provider = settings.cloudProvider
        let key = keyField.stringValue
        checkKeyButton.isEnabled = false
        setKeyStatus("Checking...", tone: .neutral)
        Task { @MainActor in
            do {
                let message = try await ProviderKeyCheck.check(provider: provider, key: key)
                self.setKeyStatus(message, tone: .success)
            } catch {
                self.setKeyStatus(error.localizedDescription, tone: .warning)
            }
            self.checkKeyButton.isEnabled = true
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
        // Direct route IDs include the model name, so re-point both actions at the new one.
        settings.applyCloudSelection()
        cloudSummaryLabel.stringValue = "The Capsule uses: \(settings.setupSummary)"
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
        defer { isLoadingCatalog = false }
        catalogRefreshButton.isEnabled = false
        catalogStatusLabel.stringValue = "Loading OpenRouter models..."
        catalogStatusLabel.textColor = .tertiaryLabelColor
        do {
            let models = try await OpenRouterModelsAPI.shared.listModels()
            settings.remoteCatalogModels = models
            catalogModels = models
            refreshCatalogTable()
        } catch {
            catalogModels = settings.remoteCatalogModels
            refreshCatalogTable()
            catalogStatusLabel.stringValue = "Couldn't refresh the catalog. Showing the saved list."
            catalogStatusLabel.textColor = .systemOrange
        }
        catalogRefreshButton.isEnabled = true
    }

    private func refreshCatalogTable() {
        guard catalogTable != nil else { return }
        let query = catalogFilterField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        visibleCatalogModels = query.isEmpty ? catalogModels : catalogModels.filter {
            $0.id.lowercased().contains(query) || $0.displayTitle.lowercased().contains(query)
        }
        isSelectingCatalogRow = true
        catalogTable.reloadData()
        if case .model(let selected) = settings.openRouterSelection,
           let row = visibleCatalogModels.firstIndex(where: { $0.id == selected }) {
            catalogTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            catalogTable.scrollRowToVisible(row)
        } else {
            catalogTable.deselectAll(nil)
        }
        isSelectingCatalogRow = false
        if visibleCatalogModels.isEmpty {
            catalogStatusLabel.stringValue = catalogModels.isEmpty ? "No saved models. Click Refresh." : "No models match."
        } else {
            catalogStatusLabel.stringValue = "\(visibleCatalogModels.count) of \(catalogModels.count) models. Click one to use it for both actions."
        }
        catalogStatusLabel.textColor = .tertiaryLabelColor
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { visibleCatalogModels.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard visibleCatalogModels.indices.contains(row) else { return nil }
        let model = visibleCatalogModels[row]
        let cell = NSTableCellView()
        let textStack = NSStackView()
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1
        let title = NSTextField(labelWithString: model.displayTitle + (model.supportsImages ? "  · Images" : ""))
        title.font = .systemFont(ofSize: 12, weight: .medium)
        title.lineBreakMode = .byTruncatingTail
        let slug = NSTextField(labelWithString: model.routeModel)
        slug.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
        slug.textColor = .secondaryLabelColor
        slug.lineBreakMode = .byTruncatingMiddle
        textStack.addArrangedSubview(title)
        textStack.addArrangedSubview(slug)
        cell.addSubview(textStack)
        NSLayoutConstraint.activate([
            textStack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            textStack.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            textStack.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isSelectingCatalogRow else { return }
        let row = catalogTable.selectedRow
        guard visibleCatalogModels.indices.contains(row) else { return }
        settings.openRouterSelection = .model(visibleCatalogModels[row].id)
        syncOpenRouterPopup()
        cloudSummaryLabel.stringValue = "The Capsule uses: \(settings.setupSummary)"
    }

    // MARK: Text fields

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        if field === keyField { keyChanged() }
        else if field === catalogFilterField { refreshCatalogTable() }
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

private final class FlippedModelsDocumentView: NSView {
    override var isFlipped: Bool { true }
}

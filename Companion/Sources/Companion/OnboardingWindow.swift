import AppKit

// First-launch welcome: pick Local or Cloud, add one key if Cloud, then grant permissions.
final class OnboardingWindow: NSWindowController, NSTextFieldDelegate {
    private var modeControl: NSSegmentedControl!
    private var modeHintLabel: NSTextField!
    private var providerLabel: NSTextField!
    private var providerPopup: NSPopUpButton!
    private var apiKeyLabel: NSTextField!
    private var apiKeyField: NSSecureTextField!
    private var apiHintLabel: NSTextField!
    private var apiKeyLinkButton: NSButton!
    private var getStartedButton: NSButton!
    private var skipButton: NSButton!
    private var statusLabel: NSTextField!

    private let cloudProviders: [UserSettings.Provider] = [.openRouter, .openAI, .claude, .deepSeek]

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Redraft"
        window.center()
        window.isReleasedWhenClosed = false
        self.init(window: window)
        setupUI()
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true

        let iconView = NSImageView(frame: .zero)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        if let image = NSImage(systemSymbolName: "sparkle.magnifyingglass", accessibilityDescription: "Redraft") {
            let config = NSImage.SymbolConfiguration(pointSize: 48, weight: .light)
            iconView.image = image.withSymbolConfiguration(config)
            iconView.contentTintColor = .controlAccentColor
        }
        contentView.addSubview(iconView)

        let titleLabel = NSTextField(labelWithString: "Redraft")
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        titleLabel.alignment = .center
        contentView.addSubview(titleLabel)

        let descLabel = NSTextField(wrappingLabelWithString:
            "Select text, press the shortcut, fix grammar or type an instruction.\n\n" +
            "Choose where the model runs. You can change this any time in Settings → Models."
        )
        descLabel.translatesAutoresizingMaskIntoConstraints = false
        descLabel.font = .systemFont(ofSize: 13)
        descLabel.alignment = .center
        descLabel.textColor = .secondaryLabelColor
        contentView.addSubview(descLabel)

        modeControl = NSSegmentedControl(labels: UserSettings.ModelMode.allCases.map(\.title),
            trackingMode: .selectOne, target: self, action: #selector(modeChanged))
        modeControl.translatesAutoresizingMaskIntoConstraints = false
        modeControl.segmentStyle = .rounded
        for index in 0..<modeControl.segmentCount { modeControl.setWidth(0, forSegment: index) }
        modeControl.selectedSegment = 1
        contentView.addSubview(modeControl)

        modeHintLabel = NSTextField(wrappingLabelWithString: "")
        modeHintLabel.translatesAutoresizingMaskIntoConstraints = false
        modeHintLabel.font = .systemFont(ofSize: 12)
        modeHintLabel.textColor = .secondaryLabelColor
        modeHintLabel.alignment = .center
        contentView.addSubview(modeHintLabel)

        providerLabel = NSTextField(labelWithString: "Provider")
        providerLabel.translatesAutoresizingMaskIntoConstraints = false
        providerLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        providerLabel.textColor = .secondaryLabelColor
        contentView.addSubview(providerLabel)

        providerPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        providerPopup.translatesAutoresizingMaskIntoConstraints = false
        providerPopup.target = self
        providerPopup.action = #selector(providerChanged)
        for provider in cloudProviders {
            providerPopup.addItem(withTitle: provider == .openRouter
                ? "OpenRouter · recommended models" : ModelsSettingsPane.providerTitle(provider))
            providerPopup.lastItem?.representedObject = provider.rawValue
        }
        contentView.addSubview(providerPopup)

        apiKeyLabel = NSTextField(labelWithString: "API key")
        apiKeyLabel.translatesAutoresizingMaskIntoConstraints = false
        apiKeyLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        apiKeyLabel.textColor = .secondaryLabelColor
        contentView.addSubview(apiKeyLabel)

        apiHintLabel = NSTextField(wrappingLabelWithString: "")
        apiHintLabel.translatesAutoresizingMaskIntoConstraints = false
        apiHintLabel.font = .systemFont(ofSize: 11)
        apiHintLabel.textColor = .tertiaryLabelColor
        contentView.addSubview(apiHintLabel)

        apiKeyField = NSSecureTextField(frame: .zero)
        apiKeyField.translatesAutoresizingMaskIntoConstraints = false
        apiKeyField.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        apiKeyField.target = self
        apiKeyField.action = #selector(apiKeyChanged)
        apiKeyField.delegate = self
        contentView.addSubview(apiKeyField)

        apiKeyLinkButton = NSButton(title: "", target: self, action: #selector(openAPIKeyPage))
        apiKeyLinkButton.translatesAutoresizingMaskIntoConstraints = false
        apiKeyLinkButton.isBordered = false
        apiKeyLinkButton.contentTintColor = .linkColor
        apiKeyLinkButton.font = .systemFont(ofSize: 12)
        contentView.addSubview(apiKeyLinkButton)

        let permBox = NSBox()
        permBox.translatesAutoresizingMaskIntoConstraints = false
        permBox.boxType = .custom
        permBox.cornerRadius = 8
        permBox.borderColor = .separatorColor
        permBox.borderWidth = 1
        permBox.fillColor = NSColor.controlBackgroundColor
        permBox.titlePosition = .noTitle
        contentView.addSubview(permBox)

        let permLabel = NSTextField(wrappingLabelWithString:
            "After setup, macOS asks for one permission in System Settings → Privacy & Security:\n" +
            "Accessibility, so Redraft can copy and paste text. " +
            "You may need to relaunch Redraft after granting it."
        )
        permLabel.translatesAutoresizingMaskIntoConstraints = false
        permLabel.font = .systemFont(ofSize: 11.5)
        permLabel.textColor = .secondaryLabelColor
        permBox.addSubview(permLabel)

        statusLabel = NSTextField(wrappingLabelWithString: "")
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.alignment = .center
        contentView.addSubview(statusLabel)

        getStartedButton = NSButton(title: "Get Started", target: self, action: #selector(getStarted))
        getStartedButton.translatesAutoresizingMaskIntoConstraints = false
        getStartedButton.bezelStyle = .rounded
        getStartedButton.controlSize = .large
        getStartedButton.keyEquivalent = "\r"
        getStartedButton.isEnabled = false
        contentView.addSubview(getStartedButton)

        skipButton = NSButton(title: "Skip for now", target: self, action: #selector(skipOnboarding))
        skipButton.translatesAutoresizingMaskIntoConstraints = false
        skipButton.bezelStyle = .accessoryBarAction
        skipButton.controlSize = .regular
        skipButton.isBordered = false
        skipButton.contentTintColor = .secondaryLabelColor
        contentView.addSubview(skipButton)

        let margin: CGFloat = 60
        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            iconView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 32),
            iconView.widthAnchor.constraint(equalToConstant: 64),
            iconView.heightAnchor.constraint(equalToConstant: 64),

            titleLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 10),

            descLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            descLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            descLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 40),
            descLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -40),

            modeControl.topAnchor.constraint(equalTo: descLabel.bottomAnchor, constant: 18),
            modeControl.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: margin),
            modeControl.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -margin),

            modeHintLabel.topAnchor.constraint(equalTo: modeControl.bottomAnchor, constant: 8),
            modeHintLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: margin),
            modeHintLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -margin),

            providerLabel.topAnchor.constraint(equalTo: modeHintLabel.bottomAnchor, constant: 16),
            providerLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: margin),

            providerPopup.topAnchor.constraint(equalTo: providerLabel.bottomAnchor, constant: 6),
            providerPopup.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: margin),
            providerPopup.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -margin),

            apiKeyLabel.topAnchor.constraint(equalTo: providerPopup.bottomAnchor, constant: 12),
            apiKeyLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: margin),

            apiHintLabel.topAnchor.constraint(equalTo: apiKeyLabel.bottomAnchor, constant: 2),
            apiHintLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: margin),
            apiHintLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -margin),

            apiKeyField.topAnchor.constraint(equalTo: apiHintLabel.bottomAnchor, constant: 6),
            apiKeyField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: margin),
            apiKeyField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -margin),

            apiKeyLinkButton.topAnchor.constraint(equalTo: apiKeyField.bottomAnchor, constant: 6),
            apiKeyLinkButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            permBox.topAnchor.constraint(equalTo: apiKeyLinkButton.bottomAnchor, constant: 16),
            permBox.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 32),
            permBox.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -32),

            permLabel.topAnchor.constraint(equalTo: permBox.topAnchor, constant: 12),
            permLabel.leadingAnchor.constraint(equalTo: permBox.leadingAnchor, constant: 14),
            permLabel.trailingAnchor.constraint(equalTo: permBox.trailingAnchor, constant: -14),
            permLabel.bottomAnchor.constraint(equalTo: permBox.bottomAnchor, constant: -12),

            statusLabel.topAnchor.constraint(equalTo: permBox.bottomAnchor, constant: 10),
            statusLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 40),
            statusLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -40),

            getStartedButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 10),
            getStartedButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            skipButton.topAnchor.constraint(equalTo: getStartedButton.bottomAnchor, constant: 4),
            skipButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            skipButton.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20),
        ])

        updateModeSelection()
    }

    private var isLocal: Bool { modeControl.selectedSegment == 0 }

    private var selectedProvider: UserSettings.Provider {
        guard let raw = providerPopup.selectedItem?.representedObject as? String,
              let provider = UserSettings.Provider(rawValue: raw) else { return .openRouter }
        return provider
    }

    @objc private func modeChanged() {
        statusLabel.stringValue = ""
        updateModeSelection()
    }

    @objc private func providerChanged() {
        apiKeyField.stringValue = ""
        statusLabel.stringValue = ""
        updateModeSelection()
    }

    @objc private func apiKeyChanged() {
        updateGetStartedState()
        statusLabel.stringValue = ""
    }

    func controlTextDidChange(_ notification: Notification) { apiKeyChanged() }

    @objc private func skipOnboarding() {
        UserSettings.shared.hasCompletedOnboarding = true
        self.close()
    }

    @objc private func openAPIKeyPage() {
        if let url = ModelsSettingsPane.keyPageURL(selectedProvider) { NSWorkspace.shared.open(url) }
    }

    @objc private func getStarted() {
        let settings = UserSettings.shared
        if isLocal {
            settings.modelMode = .local
            settings.hasCompletedOnboarding = true
            close()
            // The local model list loads in Settings → Models; open it so the first run finishes there.
            (NSApp.delegate as? AppDelegate)?.openSettingsPane(named: "Models")
            return
        }

        let key = apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        settings.setAPIKey(key, for: selectedProvider)
        if let error = settings.credentialStorageError {
            statusLabel.stringValue = error
            return
        }
        settings.useWritingProvider(selectedProvider)
        settings.hasCompletedOnboarding = true
        statusLabel.stringValue = ""
        close()
    }

    private func updateModeSelection() {
        let cloudControls: [NSView] = [providerLabel, providerPopup, apiKeyLabel, apiHintLabel, apiKeyField, apiKeyLinkButton]
        cloudControls.forEach { $0.isHidden = isLocal }
        if isLocal {
            modeHintLabel.stringValue = "Runs a model on this Mac with LM Studio. Install it, load a model, start its server. Nothing leaves your computer."
        } else {
            modeHintLabel.stringValue = "Uses your own API key. The provider bills you directly; the key stays in macOS Keychain."
            let provider = selectedProvider
            apiKeyLabel.stringValue = "\(ModelsSettingsPane.providerTitle(provider)) API key"
            apiKeyField.placeholderString = ModelsSettingsPane.keyPlaceholder(provider)
            apiKeyLinkButton.title = "Get a \(ModelsSettingsPane.providerTitle(provider)) key"
            switch provider {
            case .openRouter:
                apiHintLabel.stringValue = "Starts with the tested model, Gemini Flash Lite. DeepSeek Flash is kept as the fallback for local models."
            default:
                apiHintLabel.stringValue = "Uses \(ModelsSettingsPane.directModelDefault(provider)). Change the model later in Settings → Models."
            }
        }
        updateGetStartedState()
    }

    private func updateGetStartedState() {
        if isLocal {
            getStartedButton.isEnabled = true
            return
        }
        let key = apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        getStartedButton.isEnabled = !key.isEmpty
    }
}

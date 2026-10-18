import AppKit

// Generated text history in its own window, opened from Settings or the menu bar.
final class HistoryWindow: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private var entries: [GenerationHistoryStore.Entry] = []
    private var loadTask: Task<Void, Never>?
    private var table: NSTableView!
    private var resultView: NSTextView!
    private var metadataLabel: NSTextField!
    private var copyButton: NSButton!

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 640, height: 540)),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Redraft History"
        window.minSize = NSSize(width: 520, height: 400)
        window.setFrameAutosaveName("CompanionHistoryWindow")
        window.center()
        window.isReleasedWhenClosed = false
        self.init(window: window)
        build()
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        reload(selectFirst: true)
    }

    private func build() {
        guard let content = window?.contentView else { return }
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 10
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
        ])

        let help = NSTextField(wrappingLabelWithString: "The latest 500 results. Source text and images are never stored. Turn history off in Settings to stop saving new results.")
        help.font = .systemFont(ofSize: 11)
        help.textColor = .tertiaryLabelColor
        stack.addArrangedSubview(help)

        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 8
        copyButton = makeButton("Copy Result", action: #selector(copyResult))
        buttons.addArrangedSubview(copyButton)
        buttons.addArrangedSubview(makeButton("Clear History", action: #selector(clear)))
        stack.addArrangedSubview(buttons)

        table = NSTableView()
        table.headerView = nil
        table.rowHeight = 44
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.backgroundColor = .clear
        table.style = .inset
        table.delegate = self
        table.dataSource = self
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("history"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        let tableScroll = NSScrollView()
        tableScroll.translatesAutoresizingMaskIntoConstraints = false
        tableScroll.hasVerticalScroller = true
        tableScroll.borderType = .bezelBorder
        tableScroll.documentView = table
        stack.addArrangedSubview(tableScroll)

        metadataLabel = NSTextField(wrappingLabelWithString: "")
        metadataLabel.font = .systemFont(ofSize: 11)
        metadataLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(metadataLabel)

        let resultScroll = NSTextView.scrollableTextView()
        resultScroll.translatesAutoresizingMaskIntoConstraints = false
        resultScroll.hasVerticalScroller = true
        resultScroll.borderType = .bezelBorder
        resultView = resultScroll.documentView as? NSTextView
        resultView.isEditable = false
        resultView.isSelectable = true
        resultView.isRichText = true
        resultView.font = .systemFont(ofSize: 12)
        resultView.textColor = .labelColor
        resultView.textContainerInset = NSSize(width: 8, height: 8)
        stack.addArrangedSubview(resultScroll)
        tableScroll.heightAnchor.constraint(equalTo: resultScroll.heightAnchor).isActive = true
    }

    private func makeButton(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .small
        return button
    }

    @objc private func copyResult() {
        let row = table.selectedRow
        guard entries.indices.contains(row) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entries[row].result, forType: .string)
    }

    @objc private func clear() {
        let alert = NSAlert()
        alert.messageText = "Clear generated text history?"
        alert.informativeText = "This clears the visible history. A recovery archive stays in Application Support › Companion (the folder keeps the app's original name)."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear History")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        loadTask?.cancel()
        Task { @MainActor in
            do {
                try await GenerationHistoryStore.shared.clear()
                reload(selectFirst: false)
            } catch { showStorageError("History couldn't be cleared. Your saved files are still on this Mac.") }
        }
    }

    func reload(selectFirst: Bool) {
        loadTask?.cancel()
        loadTask = Task { @MainActor in
            do {
                let loaded = try await GenerationHistoryStore.shared.entries()
                try Task.checkCancellation()
                entries = loaded
                table.reloadData()
                if selectFirst, !entries.isEmpty {
                    table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
                }
                updateDetail()
            } catch is CancellationError { }
            catch { showStorageError("History couldn't be read. Existing files have been preserved.") }
        }
    }

    private func showStorageError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Couldn't save changes"
        alert.informativeText = message
        alert.runModal()
    }

    private func updateDetail() {
        let row = table.selectedRow
        guard entries.indices.contains(row) else {
            resultView.string = ""
            metadataLabel.stringValue = entries.isEmpty ? "No results saved yet." : "Select an entry."
            copyButton.isEnabled = false
            return
        }
        let entry = entries[row]
        resultView.string = entry.result
        if let sources = entry.sources, !sources.isEmpty {
            let detail = NSMutableAttributedString(string: entry.result + "\n\nSources\n", attributes: [
                .font: resultView.font ?? NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor
            ])
            for source in sources where ["http", "https"].contains(source.url.scheme?.lowercased() ?? "") {
                detail.append(NSAttributedString(string: "\(source.title)\n\(source.url.absoluteString)\n\n", attributes: [
                    .font: NSFont.systemFont(ofSize: 12), .link: source.url, .foregroundColor: NSColor.linkColor
                ]))
            }
            resultView.textStorage?.setAttributedString(detail)
        }
        let date = Self.dateFormatter.string(from: entry.createdAt)
        let imageText = entry.hadImages ? " · images: \(entry.imageFileNames.joined(separator: ", "))" : ""
        let durationText = (entry.requestDurationSeconds.map { " · " + String(format: "%.1f s request", $0) } ?? "")
            + (entry.usedWebSearch == true ? " · Web search" : "")
        metadataLabel.stringValue = "\(date) · \(entry.provider) · \(entry.model) · \(entry.selectedWordCount) selected words\(durationText)\(imageText)"
        copyButton.isEnabled = true
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard entries.indices.contains(row) else { return nil }
        let entry = entries[row]
        let cell = NSTableCellView()
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        cell.addSubview(stack)
        let preview = NSTextField(labelWithString: entry.result.replacingOccurrences(of: "\n", with: " "))
        preview.font = .systemFont(ofSize: 12, weight: .medium)
        preview.lineBreakMode = .byTruncatingTail
        stack.addArrangedSubview(preview)
        let date = Self.dateFormatter.string(from: entry.createdAt)
        let detail = NSTextField(labelWithString: "\(date) · \(entry.provider) · \(entry.model)\(entry.hadImages ? " · images" : "")")
        detail.font = .systemFont(ofSize: 10.5)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingMiddle
        stack.addArrangedSubview(detail)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) { updateDetail() }
}

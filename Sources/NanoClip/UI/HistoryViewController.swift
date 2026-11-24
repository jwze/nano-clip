import AppKit
import NanoClipCore

/// History list: search field, view-based table, footer hint. Rebuilt on every panel show and
/// released when the panel hides, so its thumbnails do not linger in memory.
@MainActor
final class HistoryViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    var onActivate: ((ClipItem) -> Void)?
    var onDelete: ((ClipItem) -> Void)?
    var onTogglePin: ((ClipItem) -> Void)?
    var onRequestAccessibility: (() -> Void)?

    private let store: ClipStore
    private let prefs: Prefs
    private let thumbnails = ThumbnailCache()

    private var items: [ClipItem] = []
    var query = ""
    private var appNames: [String: String] = [:]

    let searchField = NSSearchField()
    let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let footerLabel = NSTextField(labelWithString: "")
    private let permissionButton = NSButton()
    private let emptyLabel = NSTextField(labelWithString: "暂无剪贴板历史")

    private let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh-Hans-CN")
        formatter.unitsStyle = .short
        formatter.dateTimeStyle = .named
        return formatter
    }()

    init(store: ClipStore, prefs: Prefs) {
        self.store = store
        self.prefs = prefs
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    deinit {
        // Released whenever the panel hides; if this stops firing, the panel leaks.
        Log.info("history view controller released")
    }

    override func loadView() {
        let root = NSVisualEffectView(frame: NSRect(origin: .zero, size: HistoryPanel.size))
        root.material = .hudWindow
        root.blendingMode = .behindWindow
        root.state = .active
        root.wantsLayer = true
        root.layer?.cornerRadius = 12
        root.layer?.masksToBounds = true
        view = root
        preferredContentSize = HistoryPanel.size

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "搜索剪贴板历史"
        searchField.font = .systemFont(ofSize: 13)
        searchField.focusRingType = .none
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        searchField.delegate = self

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder
        scrollView.documentView = tableView

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("clip"))
        column.resizingMask = .autoresizingMask
        column.width = HistoryPanel.size.width - 16
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .plain
        tableView.rowHeight = ClipRowView.rowHeight
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.backgroundColor = .clear
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.selectionHighlightStyle = .regular
        tableView.allowsEmptySelection = false
        tableView.allowsMultipleSelection = false
        tableView.focusRingType = .none
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(handleDoubleClick)

        footerLabel.translatesAutoresizingMaskIntoConstraints = false
        footerLabel.font = .systemFont(ofSize: 10.5)
        footerLabel.textColor = .secondaryLabelColor
        footerLabel.lineBreakMode = .byTruncatingTail
        footerLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        permissionButton.translatesAutoresizingMaskIntoConstraints = false
        permissionButton.title = "去授权"
        permissionButton.bezelStyle = .inline
        permissionButton.controlSize = .small
        permissionButton.font = .systemFont(ofSize: 10.5)
        permissionButton.target = self
        permissionButton.action = #selector(handlePermissionButton)
        permissionButton.isHidden = true

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center

        root.addSubview(searchField)
        root.addSubview(scrollView)
        root.addSubview(footerLabel)
        root.addSubview(permissionButton)
        root.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: root.topAnchor, constant: 10),
            searchField.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            scrollView.bottomAnchor.constraint(equalTo: footerLabel.topAnchor, constant: -6),

            footerLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            footerLabel.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -9),
            footerLabel.heightAnchor.constraint(equalToConstant: 14),

            permissionButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            permissionButton.centerYAnchor.constraint(equalTo: footerLabel.centerYAnchor),
            permissionButton.leadingAnchor.constraint(greaterThanOrEqualTo: footerLabel.trailingAnchor, constant: 8),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
        ])
    }

    // MARK: - Public API used by the panel controller

    func reload() {
        let previousSelection = selectedItem?.id
        items = store.fetch(query: query, limit: 200)
        tableView.reloadData()
        if let previousSelection,
           let index = items.firstIndex(where: { $0.id == previousSelection }) {
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            tableView.scrollRowToVisible(index)
        } else if !items.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            tableView.scrollRowToVisible(0)
        }
        emptyLabel.isHidden = !items.isEmpty
        emptyLabel.stringValue = query.isEmpty ? "暂无剪贴板历史" : "没有匹配的记录"
        updateFooter()
    }

    func focusSearch() {
        view.window?.makeFirstResponder(searchField)
    }

    /// True while an input method (Chinese/Japanese IME) is composing. Enter, arrows and Esc belong
    /// to the IME in that state and must not be hijacked by the panel.
    var isComposingText: Bool {
        (searchField.currentEditor() as? NSTextView)?.hasMarkedText() ?? false
    }

    var selectedItem: ClipItem? {
        let row = tableView.selectedRow
        guard row >= 0, row < items.count else { return nil }
        return items[row]
    }

    func moveSelection(by delta: Int) {
        guard !items.isEmpty else { return }
        let current = tableView.selectedRow
        var next = current + delta
        if current < 0 { next = delta > 0 ? 0 : items.count - 1 }
        next = min(max(next, 0), items.count - 1)
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }

    func activateSelected() {
        guard let item = selectedItem else { return }
        onActivate?(item)
    }

    func deleteSelected() {
        guard let item = selectedItem else { return }
        onDelete?(item)
        reload()
    }

    func togglePinSelected() {
        guard let item = selectedItem else { return }
        onTogglePin?(item)
        reload()
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < items.count else { return nil }
        let item = items[row]
        let cell = tableView.makeView(withIdentifier: ClipRowView.reuseIdentifier, owner: self) as? ClipRowView
            ?? ClipRowView(frame: NSRect(x: 0, y: 0, width: tableView.bounds.width, height: ClipRowView.rowHeight))
        cell.configure(
            icon: icon(for: item),
            text: title(for: item),
            subtitle: subtitle(for: item),
            pinned: item.pinned
        )
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        if view.window?.firstResponder !== searchField {
            view.window?.makeFirstResponder(searchField)
        }
        updateFooter()
    }

    @objc private func handleDoubleClick() {
        activateSelected()
    }

    @objc private func handlePermissionButton() {
        onRequestAccessibility?()
    }

    // MARK: - Search field

    func controlTextDidChange(_ obj: Notification) {
        let newQuery = searchField.stringValue
        guard newQuery != query else { return }
        query = newQuery
        reload()
    }

    // MARK: - Row content

    private func icon(for item: ClipItem) -> NSImage? {
        switch item.kind {
        case .image:
            guard let url = store.imageURL(for: item) else { return nil }
            return thumbnails.image(for: url)
        case .text:
            return NSImage(systemSymbolName: "text.alignleft", accessibilityDescription: "文本")?
                .withSymbolConfiguration(.init(pointSize: 15, weight: .regular))
        }
    }

    private func title(for item: ClipItem) -> String {
        switch item.kind {
        case .image:
            return "图片"
        case .text:
            let text = item.text ?? ""
            let firstLine = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
                .first.map(String.init) ?? ""
            let preview = String(firstLine.prefix(240))
            return text.contains("\n") ? preview + " …" : preview
        }
    }

    private func subtitle(for item: ClipItem) -> String {
        var parts: [String] = []
        if let name = appName(for: item.sourceApp) { parts.append(name) }
        parts.append(relativeFormatter.localizedString(for: item.createdAt, relativeTo: Date()))
        if item.kind == .image { parts.append(byteLabel(item.imageBytes)) }
        if item.truncated { parts.append("已截断") }
        return parts.joined(separator: " · ")
    }

    private func appName(for bundleID: String?) -> String? {
        guard let bundleID, !bundleID.isEmpty else { return nil }
        if let cached = appNames[bundleID] { return cached }
        let name: String
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           let bundle = Bundle(url: url) {
            name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? bundleID
        } else {
            name = bundleID
        }
        appNames[bundleID] = name
        return name
    }

    private func byteLabel(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func updateFooter() {
        let needsPermission = PastePolicy.shouldShowPermissionHint(
            autoPasteEnabled: prefs.autoPaste,
            accessibilityTrusted: Accessibility.isTrusted
        )
        permissionButton.isHidden = !needsPermission
        if needsPermission {
            footerLabel.stringValue = "未授予辅助功能权限：回车仅复制到剪贴板"
            return
        }
        var hints = "↑↓ 选择 · ↩ 粘贴 · ⌘⌫ 删除 · ⌘P 置顶"
        if let item = selectedItem {
            hints = "\(items.count) 条 · " + hints
            if item.kind == .image, item.imageBytes > 0 {
                hints = "\(items.count) 条 · \(byteLabel(item.imageBytes)) · " + "↑↓ 选择 · ↩ 粘贴"
            }
        }
        footerLabel.stringValue = hints
    }
}

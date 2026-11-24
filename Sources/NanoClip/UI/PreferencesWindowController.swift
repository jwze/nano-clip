import AppKit
import UniformTypeIdentifiers
import NanoClipCore

/// Click-to-record shortcut button. While recording it becomes first responder and swallows the
/// next key combo; Esc cancels.
@MainActor
final class HotKeyRecorderButton: NSButton {
    var onChange: ((KeyCombo) -> Void)?
    private var isRecording = false
    private(set) var combo: KeyCombo

    init(combo: KeyCombo) {
        self.combo = combo
        super.init(frame: .zero)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(beginRecording)
        font = .systemFont(ofSize: 12)
        updateTitle()
        widthAnchor.constraint(greaterThanOrEqualToConstant: 92).isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var acceptsFirstResponder: Bool { true }

    func setCombo(_ newCombo: KeyCombo) {
        combo = newCombo
        updateTitle()
    }

    @objc private func beginRecording() {
        isRecording = true
        title = "按下快捷键…"
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        if event.keyCode == 53 {  // esc cancels
            endRecording(commit: false)
            return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let converted = KeyCombo(keyCode: UInt32(event.keyCode), cocoaModifiers: UInt32(flags.rawValue))
        guard converted.hasModifier else {
            NSSound.beep()
            title = "需要修饰键，请重按…"
            return
        }
        combo = converted
        endRecording(commit: true)
        onChange?(converted)
    }

    override func resignFirstResponder() -> Bool {
        if isRecording {
            endRecording(commit: false)
        }
        return super.resignFirstResponder()
    }

    private func endRecording(commit: Bool) {
        isRecording = false
        updateTitle()
    }

    private func updateTitle() {
        title = isRecording ? "按下快捷键…" : combo.displayString
    }
}

@MainActor
final class PreferencesViewController: NSViewController,
    NSTableViewDataSource,
    NSTableViewDelegate,
    NSTextFieldDelegate
{
    var onHotKeyChanged: ((KeyCombo) -> Void)?
    var onLoginItemChanged: ((Bool) -> Void)?
    var onAutoPasteChanged: ((Bool) -> Void)?
    var onRequestAccessibility: (() -> Void)?

    private let prefs: Prefs
    private let store: ClipStore

    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: "登录时自动启动 NanoClip", target: nil, action: nil)
    private let autoPasteCheckbox = NSButton(checkboxWithTitle: "回车后自动粘贴到当前应用", target: nil, action: nil)
    private let hotKeyButton: HotKeyRecorderButton
    private let maxItemsField = NSTextField(string: "500")
    private let maxItemsStepper = NSStepper()
    private let recordImagesCheckbox = NSButton(checkboxWithTitle: "记录图片（PNG 无损保存）", target: nil, action: nil)
    private let maxImagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let clearHistoryButton = NSButton(title: "清空历史…", target: nil, action: nil)
    private let historyStatsLabel = NSTextField(labelWithString: "")
    private let permissionLabel = NSTextField(labelWithString: "")
    private let permissionButton = NSButton(title: "打开系统设置", target: nil, action: nil)
    private let loginStatusLabel = NSTextField(labelWithString: "")
    private let ignoredTable = NSTableView()
    private let ignoredScrollView = NSScrollView()
    private let removeIgnoredButton = NSButton(title: "移除选中", target: nil, action: nil)

    private var ignoredIDs: [String] = []

    init(store: ClipStore, prefs: Prefs) {
        self.store = store
        self.prefs = prefs
        hotKeyButton = HotKeyRecorderButton(combo: prefs.hotKey)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func loadView() {
        let root = NSView()

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -22),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -18),
        ])

        // 通用
        stack.addArrangedSubview(sectionHeader("通用"))

        launchAtLoginCheckbox.target = self
        launchAtLoginCheckbox.action = #selector(toggleLaunchAtLogin)
        stack.addArrangedSubview(launchAtLoginCheckbox)

        loginStatusLabel.font = .systemFont(ofSize: 10.5)
        loginStatusLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(indent(loginStatusLabel))

        hotKeyButton.onChange = { [weak self] combo in
            guard let self else { return }
            self.prefs.hotKey = combo
            self.onHotKeyChanged?(combo)
            self.refreshRuntimeState()
        }
        let resetHotKeyButton = NSButton(title: "恢复默认 ⌘⇧V", target: self, action: #selector(resetHotKey))
        resetHotKeyButton.bezelStyle = .rounded
        resetHotKeyButton.font = .systemFont(ofSize: 11)
        stack.addArrangedSubview(row("呼出快捷键", controls: [hotKeyButton, resetHotKeyButton]))

        autoPasteCheckbox.target = self
        autoPasteCheckbox.action = #selector(toggleAutoPaste)
        stack.addArrangedSubview(autoPasteCheckbox)

        permissionButton.target = self
        permissionButton.action = #selector(openAccessibilitySettings)
        permissionButton.bezelStyle = .rounded
        permissionButton.font = .systemFont(ofSize: 11)
        permissionLabel.font = .systemFont(ofSize: 11)
        permissionLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(row("辅助功能权限", controls: [permissionLabel, permissionButton]))

        stack.addArrangedSubview(separator())

        // 历史
        stack.addArrangedSubview(sectionHeader("历史"))

        maxItemsField.font = .systemFont(ofSize: 12)
        maxItemsField.alignment = .right
        maxItemsField.delegate = self
        maxItemsField.widthAnchor.constraint(equalToConstant: 64).isActive = true
        maxItemsStepper.minValue = 50
        maxItemsStepper.maxValue = 2000
        maxItemsStepper.increment = 50
        maxItemsStepper.valueWraps = false
        maxItemsStepper.target = self
        maxItemsStepper.action = #selector(maxItemsStepperChanged)
        stack.addArrangedSubview(row("保留条数", controls: [maxItemsField, maxItemsStepper, smallLabel("条（50–2000）")]))

        recordImagesCheckbox.target = self
        recordImagesCheckbox.action = #selector(toggleRecordImages)
        stack.addArrangedSubview(recordImagesCheckbox)

        maxImagePopup.addItems(withTitles: ["5 MB", "10 MB", "20 MB"])
        maxImagePopup.target = self
        maxImagePopup.action = #selector(maxImagePopupChanged)
        maxImagePopup.font = .systemFont(ofSize: 12)
        stack.addArrangedSubview(row("单图上限", controls: [maxImagePopup]))

        clearHistoryButton.target = self
        clearHistoryButton.action = #selector(clearHistory)
        clearHistoryButton.bezelStyle = .rounded
        clearHistoryButton.font = .systemFont(ofSize: 12)
        historyStatsLabel.font = .systemFont(ofSize: 10.5)
        historyStatsLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(row("历史数据", controls: [historyStatsLabel, clearHistoryButton]))

        stack.addArrangedSubview(separator())

        // 忽略列表
        stack.addArrangedSubview(sectionHeader("忽略的 App"))
        let hint = NSTextField(labelWithString: "这些 App 复制的内容不会被记录。密码类 App 已默认加入。")
        hint.font = .systemFont(ofSize: 10.5)
        hint.textColor = .secondaryLabelColor
        stack.addArrangedSubview(hint)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ignored"))
        column.resizingMask = .autoresizingMask
        ignoredTable.addTableColumn(column)
        ignoredTable.headerView = nil
        ignoredTable.rowHeight = 22
        ignoredTable.style = .plain
        ignoredTable.allowsMultipleSelection = true
        ignoredTable.dataSource = self
        ignoredTable.delegate = self
        ignoredScrollView.documentView = ignoredTable
        ignoredScrollView.hasVerticalScroller = true
        ignoredScrollView.borderType = .bezelBorder
        ignoredScrollView.translatesAutoresizingMaskIntoConstraints = false
        ignoredScrollView.heightAnchor.constraint(equalToConstant: 120).isActive = true
        ignoredScrollView.widthAnchor.constraint(equalToConstant: 470).isActive = true

        let addAppButton = NSButton(title: "添加应用…", target: self, action: #selector(addIgnoredApp))
        addAppButton.bezelStyle = .rounded
        addAppButton.font = .systemFont(ofSize: 12)
        removeIgnoredButton.bezelStyle = .rounded
        removeIgnoredButton.font = .systemFont(ofSize: 12)
        removeIgnoredButton.target = self
        removeIgnoredButton.action = #selector(removeIgnoredApps)

        let ignoredButtons = NSStackView(views: [addAppButton, removeIgnoredButton])
        ignoredButtons.orientation = .horizontal
        ignoredButtons.spacing = 8

        stack.addArrangedSubview(ignoredScrollView)
        stack.addArrangedSubview(ignoredButtons)

        stack.addArrangedSubview(separator())

        let footer = NSTextField(
            labelWithString: "NanoClip \(AppInfo.version) · 数据位置：~/Library/Application Support/NanoClip"
        )
        footer.font = .systemFont(ofSize: 10)
        footer.textColor = .tertiaryLabelColor
        stack.addArrangedSubview(footer)

        view = root

        syncControls()
        reloadIgnored()
        refreshRuntimeState()

        root.layoutSubtreeIfNeeded()
        preferredContentSize = NSSize(width: 520, height: max(520, stack.fittingSize.height + 36))
    }

    // MARK: - Runtime state

    func refreshRuntimeState() {
        let trusted = Accessibility.isTrusted
        permissionLabel.stringValue = trusted ? "已授权，回车可自动粘贴" : "未授权，回车只会复制到剪贴板"
        permissionButton.isHidden = trusted
        loginStatusLabel.stringValue = "系统登录项状态：\(LoginItem.statusDescription)"
        let stats = store.statistics()
        historyStatsLabel.stringValue = "\(stats.count) 条记录 · 图片 \(ByteCountFormatter.string(fromByteCount: Int64(stats.imageBytes), countStyle: .file))"
        if !prefs.recordImages {
            historyStatsLabel.stringValue += " · 图片记录已关闭"
        }
    }

    private func syncControls() {
        launchAtLoginCheckbox.state = prefs.launchAtLogin ? .on : .off
        autoPasteCheckbox.state = prefs.autoPaste ? .on : .off
        recordImagesCheckbox.state = prefs.recordImages ? .on : .off
        maxItemsField.stringValue = "\(prefs.maxItems)"
        maxItemsStepper.integerValue = prefs.maxItems
        hotKeyButton.setCombo(prefs.hotKey)

        let megabytes = prefs.maxImageBytes / (1024 * 1024)
        switch megabytes {
        case ..<8: maxImagePopup.selectItem(withTitle: "5 MB")
        case 8..<16: maxImagePopup.selectItem(withTitle: "10 MB")
        default: maxImagePopup.selectItem(withTitle: "20 MB")
        }
    }

    private func reloadIgnored() {
        ignoredIDs = prefs.ignoredBundleIDs
        ignoredTable.reloadData()
    }

    private func ignoredID(at row: Int) -> String? {
        guard row >= 0, row < ignoredIDs.count else { return nil }
        return ignoredIDs[row]
    }

    // MARK: - Actions

    @objc private func toggleLaunchAtLogin() {
        let enabled = launchAtLoginCheckbox.state == .on
        prefs.launchAtLogin = enabled
        onLoginItemChanged?(enabled)
        refreshRuntimeState()
    }

    @objc private func toggleAutoPaste() {
        let enabled = autoPasteCheckbox.state == .on
        prefs.autoPaste = enabled
        onAutoPasteChanged?(enabled)
        if enabled && !Accessibility.isTrusted {
            onRequestAccessibility?()
        }
        refreshRuntimeState()
    }

    @objc private func resetHotKey() {
        prefs.hotKey = .default
        hotKeyButton.setCombo(.default)
        onHotKeyChanged?(.default)
        refreshRuntimeState()
    }

    @objc private func maxItemsStepperChanged() {
        let value = maxItemsStepper.integerValue
        prefs.maxItems = value
        maxItemsField.stringValue = "\(prefs.maxItems)"
        store.trim(limits: prefs.limits)
        refreshRuntimeState()
    }

    @objc private func toggleRecordImages() {
        prefs.recordImages = recordImagesCheckbox.state == .on
        refreshRuntimeState()
    }

    @objc private func maxImagePopupChanged() {
        let megabytes: Int
        switch maxImagePopup.indexOfSelectedItem {
        case 0: megabytes = 5
        case 1: megabytes = 10
        default: megabytes = 20
        }
        prefs.maxImageBytes = megabytes * 1024 * 1024
        refreshRuntimeState()
    }

    @objc private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "清空所有剪贴板历史？"
        alert.informativeText = "文本与图片都会被删除，置顶项也会一并清除。此操作不可撤销。"
        alert.addButton(withTitle: "清空")
        alert.addButton(withTitle: "取消")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.clearAll()
        NotificationCenter.default.post(name: Prefs.didChangeNotification, object: prefs)
        refreshRuntimeState()
    }

    @objc private func openAccessibilitySettings() {
        onRequestAccessibility?()
        refreshRuntimeState()
    }

    @objc private func addIgnoredApp() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.prompt = "忽略"
        panel.message = "选择要忽略的 App：它复制的内容不会被记录"
        guard panel.runModal() == .OK else { return }
        var ids = prefs.ignoredBundleIDs
        for url in panel.urls {
            guard let bundleID = Bundle(url: url)?.bundleIdentifier else { continue }
            if !ids.contains(bundleID) { ids.append(bundleID) }
        }
        prefs.ignoredBundleIDs = ids
        reloadIgnored()
    }

    @objc private func removeIgnoredApps() {
        let rows = ignoredTable.selectedRowIndexes
        guard !rows.isEmpty else { return }
        var ids = prefs.ignoredBundleIDs
        for row in rows.reversed() {
            if let id = ignoredID(at: row), let index = ids.firstIndex(of: id) {
                ids.remove(at: index)
            }
        }
        prefs.ignoredBundleIDs = ids
        reloadIgnored()
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int {
        ignoredIDs.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let bundleID = ignoredID(at: row) else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("ignoredCell")
        let label = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField
            ?? makeCellLabel(identifier: identifier)
        label.stringValue = appDisplayName(for: bundleID).map { "\($0)  (\(bundleID))" } ?? bundleID
        return label
    }

    private func makeCellLabel(identifier: NSUserInterfaceItemIdentifier) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.identifier = identifier
        label.font = .systemFont(ofSize: 11.5)
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    private func appDisplayName(for bundleID: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
              let bundle = Bundle(url: url)
        else { return nil }
        return (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidEndEditing(_ obj: Notification) {
        guard obj.object as? NSTextField === maxItemsField else { return }
        if let value = Int(maxItemsField.stringValue) {
            prefs.maxItems = value
        }
        store.trim(limits: prefs.limits)
        syncControls()
        refreshRuntimeState()
    }

    // MARK: - Layout helpers

    private func sectionHeader(_ title: String) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        return label
    }

    private func smallLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 10.5)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalToConstant: 470).isActive = true
        return box
    }

    private func indent(_ control: NSView) -> NSView {
        let stack = NSStackView(views: [control])
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 18, bottom: 0, right: 0)
        return stack
    }

    private func row(_ title: String, controls: [NSView]) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12)
        label.alignment = .right
        label.widthAnchor.constraint(equalToConstant: 96).isActive = true

        let row = NSStackView(views: [label] + controls)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }
}

@MainActor
final class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    private let viewController: PreferencesViewController

    init(
        store: ClipStore,
        prefs: Prefs,
        onHotKeyChanged: @escaping (KeyCombo) -> Void,
        onLoginItemChanged: @escaping (Bool) -> Void,
        onAutoPasteChanged: @escaping (Bool) -> Void,
        onRequestAccessibility: @escaping () -> Void
    ) {
        viewController = PreferencesViewController(store: store, prefs: prefs)
        viewController.onHotKeyChanged = onHotKeyChanged
        viewController.onLoginItemChanged = onLoginItemChanged
        viewController.onAutoPasteChanged = onAutoPasteChanged
        viewController.onRequestAccessibility = onRequestAccessibility

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "NanoClip 偏好设置"
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = false
        super.init(window: window)
        window.contentViewController = viewController
        window.delegate = self
        window.setContentSize(viewController.preferredContentSize)
        window.center()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func windowDidBecomeKey(_ notification: Notification) {
        viewController.refreshRuntimeState()
    }
}
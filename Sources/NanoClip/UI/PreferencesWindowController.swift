import AppKit
import UniformTypeIdentifiers
import NanoClipCore

/// Click-to-record shortcut button. While recording it becomes first responder and swallows the
/// next key combo (or a double tap of one modifier); Esc cancels.
@MainActor
final class HotKeyRecorderButton: NSButton {
    var onChange: ((HotKeyTrigger) -> Void)?
    private var isRecording = false
    private var tappedModifier: (modifier: ModifierKey, at: TimeInterval)?
    private var heldModifier: ModifierKey?
    private(set) var trigger: HotKeyTrigger

    /// Same window as `DoubleTapMonitor`, so what feels like a double tap while recording is what
    /// will feel like a double tap at run time.
    private static let doubleTapGap: TimeInterval = 0.45

    init(trigger: HotKeyTrigger) {
        self.trigger = trigger
        super.init(frame: .zero)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(beginRecording)
        font = Theme.Font.button
        controlSize = .regular
        updateTitle()
        widthAnchor.constraint(greaterThanOrEqualToConstant: 112).isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var acceptsFirstResponder: Bool { true }

    func setTrigger(_ newTrigger: HotKeyTrigger) {
        trigger = newTrigger
        updateTitle()
    }

    @objc private func beginRecording() {
        isRecording = true
        tappedModifier = nil
        heldModifier = nil
        updateTitle()
        window?.makeFirstResponder(self)
    }

    /// A modifier tapped twice on its own becomes a double-tap trigger. Only `flagsChanged` can
    /// see a bare modifier press, which `keyDown` never delivers.
    override func flagsChanged(with event: NSEvent) {
        guard isRecording else {
            super.flagsChanged(with: event)
            return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let pressedModifiers = ModifierKey.allCases.filter { flags.contains(Self.cgFlag(for: $0)) }

        if pressedModifiers.count > 1 {
            // Chord (⌥⌘…): whatever was pending is not a double tap any more.
            tappedModifier = nil
            heldModifier = nil
            return
        }
        guard let modifier = pressedModifiers.first else {
            // Release: the pending tap stays valid, that release *is* the end of the first tap.
            heldModifier = nil
            return
        }
        guard heldModifier != modifier else { return }  // same press, repeated flags change
        heldModifier = modifier

        let now = ProcessInfo.processInfo.systemUptime
        if let previous = tappedModifier,
           previous.modifier == modifier,
           now - previous.at <= Self.doubleTapGap {
            tappedModifier = nil
            commit(.doubleTap(modifier))
        } else {
            tappedModifier = (modifier, now)
        }
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        if event.keyCode == 53 {  // esc cancels
            endRecording()
            return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let converted = KeyCombo(keyCode: UInt32(event.keyCode), cocoaModifiers: UInt32(flags.rawValue))
        guard converted.hasModifier else {
            NSSound.beep()
            title = "需要修饰键，请重按…"
            return
        }
        commit(.keyCombo(converted))
    }

    override func resignFirstResponder() -> Bool {
        if isRecording {
            endRecording()
        }
        return super.resignFirstResponder()
    }

    private func commit(_ newTrigger: HotKeyTrigger) {
        trigger = newTrigger
        endRecording()
        onChange?(newTrigger)
    }

    private func endRecording() {
        isRecording = false
        tappedModifier = nil
        heldModifier = nil
        updateTitle()
    }

    private func updateTitle() {
        title = isRecording ? "录制中…" : trigger.displayString
    }

    private static func cgFlag(for modifier: ModifierKey) -> NSEvent.ModifierFlags {
        switch modifier {
        case .command: return .command
        case .option: return .option
        case .control: return .control
        case .shift: return .shift
        }
    }
}

@MainActor
final class PreferencesViewController: NSViewController,
    NSTableViewDataSource,
    NSTableViewDelegate,
    NSTextFieldDelegate
{
    var onHotKeyChanged: ((HotKeyTrigger) -> Void)?
    var onLoginItemChanged: ((Bool) -> Void)?

    private let prefs: Prefs
    private let store: ClipStore

    private let launchAtLoginSwitch = NSSwitch()
    private let hotKeyButton: HotKeyRecorderButton
    private let maxItemsField = NSTextField(string: "0")
    private let maxItemsStepper = NSStepper()
    private let unlimitedItemsSwitch = NSSwitch()
    private let recordImagesSwitch = NSSwitch()
    private let clearHistoryButton = NSButton(title: "清空历史…", target: nil, action: nil)
    private let historyStatsLabel = NSTextField(labelWithString: "")
    private let loginStatusLabel = NSTextField(labelWithString: "")
    private let ignoredTable = NSTableView()
    private let ignoredScrollView = NSScrollView()
    private let removeIgnoredButton = NSButton(title: "移除选中", target: nil, action: nil)
    private let ignoredCountLabel = NSTextField(labelWithString: "")

    private var ignoredIDs: [String] = []

    init(store: ClipStore, prefs: Prefs) {
        self.store = store
        self.prefs = prefs
        hotKeyButton = HotKeyRecorderButton(trigger: prefs.hotKeyTrigger)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func loadView() {
        let root = AppearanceObservingView()
        root.wantsLayer = true
        root.onAppearanceChange = { [weak self] in self?.applyCardChrome() }

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -16),
        ])

        // MARK: 通用
        launchAtLoginSwitch.target = self
        launchAtLoginSwitch.action = #selector(toggleLaunchAtLogin)
        launchAtLoginSwitch.controlSize = .small

        loginStatusLabel.font = Theme.Font.hint
        loginStatusLabel.textColor = .secondaryLabelColor

        hotKeyButton.onChange = { [weak self] trigger in
            guard let self else { return }
            self.prefs.hotKeyTrigger = trigger
            self.onHotKeyChanged?(trigger)
            self.refreshRuntimeState()
        }
        let resetHotKeyButton = NSButton(title: "恢复默认", target: self, action: #selector(resetHotKey))
        styleSecondaryButton(resetHotKeyButton)

        stack.addArrangedSubview(
            sectionHeader("通用", symbol: "gearshape")
        )
        addCard([
            toggleRow("登录时自动启动 NanoClip", toggle: launchAtLoginSwitch),
            indented(loginStatusLabel),
            settingRow("呼出快捷键", controls: [hotKeyButton, resetHotKeyButton]),
            Theme.hairline(),
            hintRow("默认双击 ⌥ 呼出；也可以点上面按钮后录一个组合键。"),
            hintRow("选中条目只会复制到剪贴板，不会自动粘贴；粘贴请按 ⌘V。"),
        ], to: stack)

        // MARK: 历史
        maxItemsField.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        maxItemsField.textColor = .labelColor
        maxItemsField.alignment = .right
        maxItemsField.delegate = self
        maxItemsField.bezelStyle = .roundedBezel
        maxItemsField.widthAnchor.constraint(equalToConstant: 62).isActive = true
        maxItemsStepper.minValue = 1
        maxItemsStepper.maxValue = 5000
        maxItemsStepper.increment = 50
        maxItemsStepper.valueWraps = false
        maxItemsStepper.target = self
        maxItemsStepper.action = #selector(maxItemsStepperChanged)

        unlimitedItemsSwitch.target = self
        unlimitedItemsSwitch.action = #selector(toggleUnlimitedItems)
        unlimitedItemsSwitch.controlSize = .small

        recordImagesSwitch.target = self
        recordImagesSwitch.action = #selector(toggleRecordImages)
        recordImagesSwitch.controlSize = .small
        recordImagesSwitch.target = self
        recordImagesSwitch.action = #selector(toggleRecordImages)
        recordImagesSwitch.controlSize = .small

        clearHistoryButton.target = self
        clearHistoryButton.action = #selector(clearHistory)
        styleSecondaryButton(clearHistoryButton)
        historyStatsLabel.font = Theme.Font.hint
        historyStatsLabel.textColor = .secondaryLabelColor

        stack.addArrangedSubview(sectionHeader("历史", symbol: "clock.arrow.circlepath"))
        addCard([
            toggleRow("不限制保留条数", toggle: unlimitedItemsSwitch),
            settingRow("保留条数", controls: [maxItemsField, maxItemsStepper, captionLabel("条")]),
            toggleRow("记录图片（保持原始格式）", toggle: recordImagesSwitch),
            hintRow("图片不压缩、不转换，也不设大小上限；只保存你复制时的那份数据。"),
            Theme.hairline(),
            settingRow("历史数据", controls: [historyStatsLabel, clearHistoryButton]),
        ], to: stack)

        // MARK: 忽略的 App
        ignoredCountLabel.font = Theme.Font.hint
        ignoredCountLabel.textColor = .tertiaryLabelColor

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ignored"))
        column.resizingMask = .autoresizingMask
        ignoredTable.addTableColumn(column)
        ignoredTable.headerView = nil
        ignoredTable.rowHeight = 24
        ignoredTable.style = .plain
        ignoredTable.backgroundColor = .clear
        ignoredTable.usesAlternatingRowBackgroundColors = false
        ignoredTable.allowsMultipleSelection = true
        ignoredTable.dataSource = self
        ignoredTable.delegate = self
        ignoredScrollView.documentView = ignoredTable
        ignoredScrollView.hasVerticalScroller = true
        ignoredScrollView.drawsBackground = false
        ignoredScrollView.borderType = .noBorder
        ignoredScrollView.wantsLayer = true
        ignoredScrollView.layer?.cornerRadius = 8
        ignoredScrollView.layer?.borderWidth = 1
        ignoredScrollView.translatesAutoresizingMaskIntoConstraints = false
        ignoredScrollView.heightAnchor.constraint(equalToConstant: 120).isActive = true

        let addAppButton = NSButton(title: "添加应用…", target: self, action: #selector(addIgnoredApp))
        styleSecondaryButton(addAppButton)
        styleSecondaryButton(removeIgnoredButton)
        removeIgnoredButton.target = self
        removeIgnoredButton.action = #selector(removeIgnoredApps)

        let ignoredButtons = NSStackView(views: [addAppButton, removeIgnoredButton, NSView(), ignoredCountLabel])
        ignoredButtons.orientation = .horizontal
        ignoredButtons.spacing = 8
        ignoredButtons.alignment = .centerY

        let ignoredHint = Theme.label(
            "这些 App 复制的内容不会被记录。密码类 App 已默认加入。",
            font: Theme.Font.hint,
            color: .secondaryLabelColor
        )

        stack.addArrangedSubview(sectionHeader("忽略的 App", symbol: "eye.slash"))
        addCard([ignoredHint, ignoredScrollView, ignoredButtons], to: stack)

        // MARK: footer
        let footer = Theme.label(
            "NanoClip \(AppInfo.version) · 数据位置：~/Library/Application Support/NanoClip",
            font: .systemFont(ofSize: 10),
            color: .tertiaryLabelColor,
            alignment: .center
        )
        stack.addArrangedSubview(footer)

        view = root

        syncControls()
        reloadIgnored()
        refreshRuntimeState()

        root.layoutSubtreeIfNeeded()
        preferredContentSize = NSSize(width: 560, height: max(560, stack.fittingSize.height + 34))
        applyCardChrome()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        applyCardChrome()
    }

    private func applyCardChrome() {
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            ignoredScrollView.layer?.backgroundColor = Theme.searchBackground.cgColor
            ignoredScrollView.layer?.borderColor = Theme.cardBorder.cgColor
        }
    }

    // MARK: - Runtime state

    func refreshRuntimeState() {
        loginStatusLabel.stringValue = "系统登录项状态：\(LoginItem.statusDescription)"
        let stats = store.statistics()
        var statsText = "\(stats.count) 条记录 · 图片 "
            + ByteCountFormatter.string(fromByteCount: Int64(stats.imageBytes), countStyle: .file)
        statsText += prefs.keepsEverything ? " · 不限制条数" : " · 最多 \(prefs.maxItems) 条"
        if !prefs.recordImages {
            statsText += " · 图片记录已关闭"
        }
        historyStatsLabel.stringValue = statsText
        ignoredCountLabel.stringValue = "共 \(ignoredIDs.count) 个"
    }

    private func syncControls() {
        launchAtLoginSwitch.state = prefs.launchAtLogin ? .on : .off
        recordImagesSwitch.state = prefs.recordImages ? .on : .off
        unlimitedItemsSwitch.state = prefs.keepsEverything ? .on : .off
        maxItemsField.stringValue = prefs.keepsEverything ? "不限" : "\(prefs.maxItems)"
        maxItemsField.isEnabled = !prefs.keepsEverything
        maxItemsStepper.integerValue = max(prefs.maxItems, 1)
        maxItemsStepper.isEnabled = !prefs.keepsEverything
        hotKeyButton.setTrigger(prefs.hotKeyTrigger)
    }

    private func reloadIgnored() {
        ignoredIDs = prefs.ignoredBundleIDs
        ignoredTable.reloadData()
        ignoredCountLabel.stringValue = "共 \(ignoredIDs.count) 个"
        // Reloading before the scroll view has its final height can leave it scrolled to the end.
        ignoredTable.scrollRowToVisible(0)
    }

    private func ignoredID(at row: Int) -> String? {
        guard row >= 0, row < ignoredIDs.count else { return nil }
        return ignoredIDs[row]
    }

    // MARK: - Actions

    @objc private func toggleLaunchAtLogin() {
        let enabled = launchAtLoginSwitch.state == .on
        prefs.launchAtLogin = enabled
        onLoginItemChanged?(enabled)
        refreshRuntimeState()
    }

    @objc private func resetHotKey() {
        prefs.hotKeyTrigger = .default
        hotKeyButton.setTrigger(.default)
        onHotKeyChanged?(.default)
        refreshRuntimeState()
    }

    @objc private func maxItemsStepperChanged() {
        prefs.maxItems = max(1, maxItemsStepper.integerValue)
        store.trim(limits: prefs.limits)
        syncControls()
        refreshRuntimeState()
    }

    @objc private func toggleUnlimitedItems() {
        if unlimitedItemsSwitch.state == .on {
            prefs.maxItems = Prefs.unlimitedItems
        } else {
            // Turning the cap on for the first time starts from a sane 500 rather than 1, so it
            // cannot wipe the history the moment the switch flips.
            let existing = maxItemsStepper.integerValue
            prefs.maxItems = existing > 1 ? existing : 500
        }
        store.trim(limits: prefs.limits)
        syncControls()
        refreshRuntimeState()
    }

    @objc private func toggleRecordImages() {
        prefs.recordImages = recordImagesSwitch.state == .on
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
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? IgnoredAppCellView
            ?? IgnoredAppCellView(identifier: identifier)
        cell.configure(displayName: appDisplayName(for: bundleID), bundleID: bundleID)
        return cell
    }

    /// Installed apps report their bundle name; the built-in password managers are listed by
    /// their product name even when they are not installed.
    private static let knownAppNames: [String: String] = [
        "com.1password.1password": "1Password",
        "com.1password.1password7": "1Password 7",
        "com.agilebits.onepassword7": "1Password 7",
        "com.bitwarden.desktop": "Bitwarden",
        "com.lastpass.LastPass": "LastPass",
        "com.apple.Passwords": "密码",
        "com.apple.keychainaccess": "钥匙串访问",
        "org.keepassxc.keepassxc": "KeePassXC",
        "com.dashlane.dashlane": "Dashlane",
        "com.enpass.Enpass": "Enpass",
    ]

    private func appDisplayName(for bundleID: String) -> String? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           let bundle = Bundle(url: url) {
            return (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
        }
        return Self.knownAppNames[bundleID]
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidEndEditing(_ obj: Notification) {
        guard obj.object as? NSTextField === maxItemsField else { return }
        if let value = Int(maxItemsField.stringValue), value > 0 {
            prefs.maxItems = value
        }
        store.trim(limits: prefs.limits)
        syncControls()
        refreshRuntimeState()
    }

    // MARK: - Layout helpers

    private func sectionHeader(_ title: String, symbol: String) -> NSView {
        let icon = NSImageView()
        icon.image = Theme.symbol(symbol, pointSize: 10.5, weight: .semibold)
        icon.contentTintColor = .tertiaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 14).isActive = true

        let label = Theme.label(title, font: Theme.Font.sectionHeader, color: .secondaryLabelColor)

        let row = NSStackView(views: [icon, label])
        row.orientation = .horizontal
        row.spacing = 5
        row.alignment = .centerY
        return row
    }

    private func styleSecondaryButton(_ button: NSButton) {
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = Theme.Font.button
    }

    /// Adds a card to the column and pins it to the full width (a `.leading` stack does not stretch).
    private func addCard(_ rows: [NSView], to stack: NSStackView) {
        let card = CardView(rows: rows)
        stack.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func captionLabel(_ text: String) -> NSTextField {
        Theme.label(text, font: Theme.Font.hint, color: .secondaryLabelColor)
    }

    private func indented(_ control: NSView) -> NSView {
        let stack = NSStackView(views: [control])
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 0)
        return stack
    }

    /// Dimmed explanatory line inside a card.
    private func hintRow(_ text: String) -> NSView {
        Theme.label(text, font: Theme.Font.hint, color: .secondaryLabelColor)
    }

    /// Leading label with the switch pushed to the trailing edge.
    private func toggleRow(_ title: String, toggle: NSSwitch) -> NSView {
        let label = Theme.label(title, font: Theme.Font.body)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let row = NSStackView(views: [label, spacer, toggle])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    /// Label at the leading edge, controls pushed to the trailing edge.
    private func settingRow(_ title: String, controls: [NSView]) -> NSView {
        let label = Theme.label(title, font: Theme.Font.body)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)

        let row = NSStackView(views: [label, spacer] + controls)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }
}

/// Ignored-app row: a small app icon plus name and bundle id.
@MainActor
final class IgnoredAppCellView: NSTableCellView {
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let idLabel = NSTextField(labelWithString: "")
    private var nameWithIcon: NSLayoutConstraint?
    private var nameWithoutIcon: NSLayoutConstraint?

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = Theme.Font.caption
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        idLabel.font = .systemFont(ofSize: 10)
        idLabel.textColor = .tertiaryLabelColor
        idLabel.lineBreakMode = .byTruncatingTail
        idLabel.translatesAutoresizingMaskIntoConstraints = false
        idLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        addSubview(iconView)
        addSubview(nameLabel)
        addSubview(idLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            idLabel.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 6),
            idLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            idLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
        ])

        nameWithIcon = nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 7)
        nameWithoutIcon = nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8)
        nameWithIcon?.isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func configure(displayName: String?, bundleID: String) {
        nameLabel.stringValue = displayName ?? bundleID
        idLabel.stringValue = displayName == nil ? "" : bundleID
        let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        if let installed {
            iconView.image = NSWorkspace.shared.icon(forFile: installed.path)
        }
        iconView.isHidden = installed == nil
        // Not installed: drop the icon and close the gap it would have left.
        nameWithIcon?.isActive = installed != nil
        nameWithoutIcon?.isActive = installed == nil
    }
}

@MainActor
final class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    private let viewController: PreferencesViewController

    init(
        store: ClipStore,
        prefs: Prefs,
        onHotKeyChanged: @escaping (HotKeyTrigger) -> Void,
        onLoginItemChanged: @escaping (Bool) -> Void
    ) {
        viewController = PreferencesViewController(store: store, prefs: prefs)
        viewController.onHotKeyChanged = onHotKeyChanged
        viewController.onLoginItemChanged = onLoginItemChanged

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 640),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "NanoClip 偏好设置"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = .windowBackgroundColor
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

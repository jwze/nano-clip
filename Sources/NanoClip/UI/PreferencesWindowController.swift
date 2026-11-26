// nano-clip — 轻量 macOS 剪贴板历史
// Copyright © 2026 jvz <them@live.cn>. All rights reserved.
// Watermark: jvz·NanoClip — 电子水印，请勿移除本署名头。

import AppKit
import UniformTypeIdentifiers
import NanoClipCore

/// Click-to-record shortcut button. While recording it becomes first responder and swallows the
/// next key combo (or a double tap of one modifier); Esc cancels.
@MainActor
final class HotKeyRecorderButton: TechButton {
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
        super.init(title: trigger.displayString)
        target = self
        action = #selector(beginRecording)
        widthAnchor.constraint(greaterThanOrEqualToConstant: 118).isActive = true
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
            setDisplayTitle("需要修饰键…")
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
        setDisplayTitle(isRecording ? "录制中…" : trigger.displayString)
        captionColor = isRecording ? Theme.neon : nil
        if isRecording {
            layer?.borderColor = Theme.neonSoft.cgColor
        } else {
            refresh()
        }
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
    private let showStatusItemSwitch = NSSwitch()
    private let hotKeyButton: HotKeyRecorderButton
    private let maxItemsField = NSTextField(string: "0")
    private let maxItemsStepper = NSStepper()
    private let unlimitedItemsSwitch = NSSwitch()
    private let recordImagesSwitch = NSSwitch()
    private let clearHistoryButton = TechButton(title: "清空历史…")
    private let historyStatsLabel = NSTextField(labelWithString: "")
    private let loginStatusLabel = NSTextField(labelWithString: "")
    private let ignoredTable = NSTableView()
    private let ignoredScrollView = NSScrollView()
    private let removeIgnoredButton = TechButton(title: "移除选中")
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
        let root = HUDSolidView()

        buildHeader(in: root)

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.borderType = .noBorder
        // The overlay scroller floats above the content, so the document view is inset on the right
        // instead of the scroll view: the cards keep clear of the scroller and nothing is covered.
        scroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 14, right: 0)
        scroll.automaticallyAdjustsContentInsets = false

        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 13
        stack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        scroll.documentView = document
        root.addSubview(scroll)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: root.topAnchor, constant: 52),
            // The scroll view runs nearly to the window edges; the symmetric inset lives on the
            // content stack instead, so the overlay scroller can sit in the gutter on the right
            // without the cards being asymmetric.
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 4),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -4),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 2),
            // 16 + the 4 above = the 20pt margin the window had before, equal on both sides. The
            // right gutter is wide enough for the floating scroller to clear the cards.
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -8),
        ])

        // MARK: 通用
        launchAtLoginSwitch.target = self
        launchAtLoginSwitch.action = #selector(toggleLaunchAtLogin)
        launchAtLoginSwitch.controlSize = .small

        showStatusItemSwitch.target = self
        showStatusItemSwitch.action = #selector(toggleShowStatusItem)
        showStatusItemSwitch.controlSize = .small

        loginStatusLabel.font = Theme.Font.monoHint
        loginStatusLabel.textColor = Theme.textTertiary

        hotKeyButton.onChange = { [weak self] trigger in
            guard let self else { return }
            self.prefs.hotKeyTrigger = trigger
            self.onHotKeyChanged?(trigger)
            self.refreshRuntimeState()
        }
        let resetHotKeyButton = TechButton(title: "恢复默认")
        resetHotKeyButton.target = self
        resetHotKeyButton.action = #selector(resetHotKey)

        stack.addArrangedSubview(sectionHeader("通用", latin: "GENERAL"))
        addCard([
            toggleRow("登录时自动启动", toggle: launchAtLoginSwitch),
            indented(loginStatusLabel),
            settingRow("呼出快捷键", controls: [hotKeyButton, resetHotKeyButton]),
            toggleRow("在状态栏显示图标", toggle: showStatusItemSwitch),
        ], to: stack)

        // MARK: 历史
        maxItemsField.font = Theme.Font.mono(11.5, weight: .regular)
        maxItemsField.textColor = Theme.textPrimary
        maxItemsField.alignment = .center
        maxItemsField.delegate = self
        maxItemsField.isBezeled = true
        maxItemsField.bezelStyle = .roundedBezel
        maxItemsField.drawsBackground = true
        maxItemsField.backgroundColor = Theme.glass
        maxItemsField.focusRingType = .none
        maxItemsField.widthAnchor.constraint(equalToConstant: 64).isActive = true

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

        clearHistoryButton.target = self
        clearHistoryButton.action = #selector(clearHistory)

        historyStatsLabel.font = Theme.Font.monoHint
        historyStatsLabel.textColor = Theme.textSecondary

        stack.addArrangedSubview(sectionHeader("历史", latin: "HISTORY"))
        addCard([
            toggleRow("不限制保留条数", toggle: unlimitedItemsSwitch),
            settingRow("保留条数", controls: [maxItemsField, maxItemsStepper, captionLabel("条")]),
            toggleRow("记录图片（保持原始格式）", toggle: recordImagesSwitch),
            Theme.hairline(),
            settingRow("历史数据", controls: [historyStatsLabel, clearHistoryButton]),
        ], to: stack)

        // MARK: 忽略的 App
        ignoredCountLabel.font = Theme.Font.monoHint
        ignoredCountLabel.textColor = Theme.textTertiary

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
        ignoredScrollView.layer?.cornerRadius = Theme.Metrics.controlCornerRadius
        ignoredScrollView.layer?.borderWidth = 1
        ignoredScrollView.translatesAutoresizingMaskIntoConstraints = false
        ignoredScrollView.heightAnchor.constraint(equalToConstant: 132).isActive = true

        let addAppButton = TechButton(title: "添加应用…")
        addAppButton.target = self
        addAppButton.action = #selector(addIgnoredApp)
        removeIgnoredButton.target = self
        removeIgnoredButton.action = #selector(removeIgnoredApps)

        let ignoredButtons = NSStackView(views: [
            addAppButton, removeIgnoredButton, NSView(), ignoredCountLabel,
        ])
        ignoredButtons.orientation = .horizontal
        ignoredButtons.spacing = 8
        ignoredButtons.alignment = .centerY

        stack.addArrangedSubview(sectionHeader("忽略的 App", latin: "EXCLUSIONS"))
        addCard([
            ignoredScrollView,
            ignoredButtons,
        ], to: stack)

        // MARK: footer
        let footer = Theme.monoLabel(
            "NANOCLIP \(AppInfo.version) · ~/LIBRARY/APPLICATION SUPPORT/NANOCLIP",
            size: 8.5,
            weight: .regular,
            color: Theme.textTertiary,
            tracking: 0.6
        )
        footer.alignment = .center
        let footerHolder = FlippedView()
        footerHolder.translatesAutoresizingMaskIntoConstraints = false
        footerHolder.addSubview(footer)
        NSLayoutConstraint.activate([
            footer.topAnchor.constraint(equalTo: footerHolder.topAnchor, constant: 4),
            footer.bottomAnchor.constraint(equalTo: footerHolder.bottomAnchor),
            footer.centerXAnchor.constraint(equalTo: footerHolder.centerXAnchor),
        ])
        stack.addArrangedSubview(footerHolder)
        footerHolder.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        view = root

        syncControls()
        reloadIgnored()
        refreshRuntimeState()
        applyChrome()

        preferredContentSize = NSSize(width: 580, height: 652)
    }

    private func buildHeader(in root: HUDSolidView) {
        let brand = NSImageView()
        brand.image = BrandMark.neonImage(size: 20, color: Theme.neon)
        brand.translatesAutoresizingMaskIntoConstraints = false

        let wordmark = Theme.monoLabel(
            "NANOCLIP",
            size: 11,
            weight: .semibold,
            color: Theme.textPrimary,
            tracking: 2.8
        )
        let caption = Theme.monoLabel(
            "设置 · SETTINGS",
            size: 8.5,
            weight: .regular,
            color: Theme.textTertiary,
            tracking: 1.4
        )
        let titles = NSStackView(views: [wordmark, caption])
        titles.orientation = .vertical
        titles.alignment = .leading
        titles.spacing = 1
        titles.translatesAutoresizingMaskIntoConstraints = false

        let version = HUDBadge(text: "v\(AppInfo.version)", color: Theme.textSecondary)

        let separator = Theme.hairline()
        root.addSubview(brand)
        root.addSubview(titles)
        root.addSubview(version)
        root.addSubview(separator)

        NSLayoutConstraint.activate([
            // Clear of the traffic-light buttons: the window uses .fullSizeContentView, so the
            // header shares the titlebar band and would otherwise sit on top of the close button.
            brand.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 84),
            brand.centerYAnchor.constraint(equalTo: root.topAnchor, constant: 28),

            titles.leadingAnchor.constraint(equalTo: brand.trailingAnchor, constant: 10),
            titles.centerYAnchor.constraint(equalTo: brand.centerYAnchor),

            version.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -22),
            version.centerYAnchor.constraint(equalTo: brand.centerYAnchor),

            separator.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            separator.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            separator.topAnchor.constraint(equalTo: root.topAnchor, constant: 48),
        ])
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        applyChrome()

    }

    private func applyChrome() {
        ignoredScrollView.layer?.backgroundColor = Theme.glass.cgColor
        ignoredScrollView.layer?.borderColor = Theme.borderSoft.cgColor
        maxItemsField.backgroundColor = Theme.glass
    }

    // MARK: - Runtime state

    func refreshRuntimeState() {
        loginStatusLabel.stringValue = "系统登录项：\(LoginItem.statusDescription)"
        let stats = store.statistics()
        var statsText = "\(stats.count) 条 · 图片 "
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
        showStatusItemSwitch.state = prefs.showStatusItem ? .on : .off
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

    /// The status item itself is torn down or created by `AppDelegate` in response to the prefs
    /// notification, so nothing has to be wired up here beyond storing the new value.
    @objc private func toggleShowStatusItem() {
        prefs.showStatusItem = showStatusItemSwitch.state == .on
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

    private func sectionHeader(_ title: String, latin: String) -> NSView {
        let tick = FlippedView()
        tick.wantsLayer = true
        tick.layer?.cornerRadius = 1.5
        tick.layer?.backgroundColor = Theme.neon.cgColor
        tick.translatesAutoresizingMaskIntoConstraints = false

        let label = Theme.monoLabel(
            "\(title)  \(latin)",
            size: 9,
            weight: .semibold,
            color: Theme.textSecondary,
            tracking: 1.6
        )

        let row = NSStackView(views: [tick, label])
        row.orientation = .horizontal
        row.spacing = 7
        row.alignment = .centerY
        NSLayoutConstraint.activate([
            tick.widthAnchor.constraint(equalToConstant: 3),
            tick.heightAnchor.constraint(equalToConstant: 10),
        ])
        return row
    }

    /// Adds a card to the column and pins it to the full width (a `.leading` stack does not stretch).
    private func addCard(_ rows: [NSView], to stack: NSStackView) {
        let card = CardView(rows: rows)
        stack.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func captionLabel(_ text: String) -> NSTextField {
        Theme.label(text, font: Theme.Font.caption, color: Theme.textSecondary)
    }

    private func indented(_ control: NSView) -> NSView {
        let stack = NSStackView(views: [control])
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 0)
        return stack
    }

    /// Leading label with the switch pushed to the trailing edge.
    private func toggleRow(_ title: String, toggle: NSSwitch) -> NSView {
        let label = Theme.label(title, font: Theme.Font.body, color: Theme.textPrimary)
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
        let label = Theme.label(title, font: Theme.Font.body, color: Theme.textPrimary)
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
        nameLabel.textColor = Theme.textPrimary
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        idLabel.font = Theme.Font.mono(9, weight: .regular)
        idLabel.textColor = Theme.textTertiary
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
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 652),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "NanoClip 设置"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        // Keep the settings window on screen when the app is deactivated: it is opened alongside the
        // history panel, and losing key to that panel (or to another app) must not close it.
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.fullScreenAuxiliary]
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = Theme.base
        window.minSize = NSSize(width: 560, height: 480)
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
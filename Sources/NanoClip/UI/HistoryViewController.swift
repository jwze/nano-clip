// nano-clip — 轻量 macOS 剪贴板历史
// Copyright © 2026 jvz <them@live.cn>. All rights reserved.
// Watermark: jvz·NanoClip — 电子水印，请勿移除本署名头。

import AppKit
import NanoClipCore

/// History panel: a vertical navigation rail on the left (brand, category filters, settings) and a
/// content column on the right (search, meta strip, list, key hints).
/// Rebuilt on every panel show and released when the panel hides, so thumbnails do not linger.
@MainActor
final class HistoryViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate,
    NSTextFieldDelegate
{
    /// Called when the user picks an entry, by click or by ⏎. Copying is the only action.
    var onActivate: ((ClipItem) -> Void)?
    var onDelete: ((ClipItem) -> Void)?
    var onOpenPreferences: (() -> Void)?
    /// The panel is the only route to quitting once the menu-bar icon is hidden, so it carries one.
    var onQuit: (() -> Void)?

    private let store: ClipStore
    private let thumbnails = ThumbnailCache()

    private var items: [ClipItem] = []
    var query = ""
    private var categoryFilter: ClipCategory?
    private var dateFilter: ClipDateRange = .all
    private var appNames: [String: String] = [:]
    /// Row that currently paints the hover pill, or `nil` when the pointer is elsewhere.
    private var hoveredRow: Int?

    let searchField = NSTextField()
    let tableView = NSTableView()

    // MARK: rail
    private let rail = FlippedView()
    private let brandImage = NSImageView()
    private var categoryButtons: [HUDIconButton] = []
    private let settingsButton = HUDIconButton(symbol: "gearshape", tooltip: "设置")
    private let quitButton = HUDIconButton(symbol: "power", tooltip: "退出 NanoClip")

    // MARK: content column
    private let content = FlippedView()  // autolayout: pinned below
    private let searchBar = FlippedView()
    private let searchIcon = NSImageView()
    private let clearButton = NSButton()
    private let escHint = NSTextField(labelWithString: "ESC")
    private let metaBar = FlippedView()
    private let countLabel = NSTextField(labelWithString: "0")
    private let dateChip = TechChip(title: ClipDateRange.all.title + " ⌄")
    private let dateMenu = NSMenu()
    private let scrollView = NSScrollView()
    private let footerBar = FlippedView()
    private let footerLeft = NSTextField(labelWithString: "")
    private let footerRight = NSTextField(labelWithString: "")

    private let emptyIcon = NSImageView()
    private let emptyLabel = NSTextField(labelWithString: "")
    private let emptyHint = NSTextField(labelWithString: "")

    private let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh-Hans-CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh-Hans-CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()

    private let fullDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh-Hans-CN")
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        return formatter
    }()

    init(store: ClipStore) {
        self.store = store
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
        let root = HUDView()
        root.onAppearanceChange = { [weak self] in self?.applyChrome() }
        view = root
        preferredContentSize = Theme.Metrics.panelSize

        buildRail()
        buildSearchBar()
        buildMetaBar()
        buildList()
        buildFooter()
        buildEmptyState()
        content.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(content)

        let railWidth = Theme.Metrics.railWidth
        NSLayoutConstraint.activate([
            rail.topAnchor.constraint(equalTo: root.topAnchor),
            rail.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            rail.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            rail.widthAnchor.constraint(equalToConstant: railWidth),

            content.topAnchor.constraint(equalTo: root.topAnchor),
            content.leadingAnchor.constraint(equalTo: rail.trailingAnchor),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            searchBar.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            searchBar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            searchBar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
            searchBar.heightAnchor.constraint(equalToConstant: Theme.Metrics.searchBarHeight),

            metaBar.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 10),
            metaBar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 13),
            metaBar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
            metaBar.heightAnchor.constraint(equalToConstant: Theme.Metrics.chipHeight),

            scrollView.topAnchor.constraint(equalTo: metaBar.bottomAnchor, constant: 7),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 2),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -2),
            scrollView.bottomAnchor.constraint(equalTo: footerBar.topAnchor),

            footerBar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            footerBar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            footerBar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            footerBar.heightAnchor.constraint(equalToConstant: Theme.Metrics.footerHeight),
        ])

        applyChrome()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        applyChrome()
    }

    // MARK: - Rail

    private func buildRail() {
        rail.translatesAutoresizingMaskIntoConstraints = false
        rail.wantsLayer = true
        rail.layer?.backgroundColor = Theme.railBackground.cgColor

        brandImage.image = BrandMark.neonImage(size: 20, color: Theme.neon)
        brandImage.translatesAutoresizingMaskIntoConstraints = false

        let categories: [(symbol: String, title: String)] = [
            ("square.grid.2x2", "全部"),
            ("text.alignleft", "文本"),
            ("link", "链接"),
            ("photo", "图片"),
        ]
        categoryButtons = categories.enumerated().map { index, entry in
            let button = HUDIconButton(symbol: entry.symbol, tooltip: entry.title)
            button.tag = index
            button.target = self
            button.action = #selector(categoryButtonTapped(_:))
            button.setActive(index == 0)
            return button
        }

        settingsButton.target = self
        settingsButton.action = #selector(openPreferences)

        quitButton.target = self
        quitButton.action = #selector(quitApp)

        let stack = NSStackView(views: categoryButtons)
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        let divider = FlippedView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = Theme.borderSoft.cgColor
        divider.translatesAutoresizingMaskIntoConstraints = false

        rail.addSubview(brandImage)
        rail.addSubview(divider)
        rail.addSubview(stack)
        rail.addSubview(settingsButton)
        rail.addSubview(quitButton)

        NSLayoutConstraint.activate([
            brandImage.topAnchor.constraint(equalTo: rail.topAnchor, constant: 14),
            brandImage.centerXAnchor.constraint(equalTo: rail.centerXAnchor),
            brandImage.widthAnchor.constraint(equalToConstant: 20),
            brandImage.heightAnchor.constraint(equalToConstant: 20),

            divider.topAnchor.constraint(equalTo: rail.topAnchor),
            divider.bottomAnchor.constraint(equalTo: rail.bottomAnchor),
            divider.trailingAnchor.constraint(equalTo: rail.trailingAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),

            stack.topAnchor.constraint(equalTo: brandImage.bottomAnchor, constant: 16),
            stack.centerXAnchor.constraint(equalTo: rail.centerXAnchor),

            settingsButton.centerXAnchor.constraint(equalTo: rail.centerXAnchor),
            quitButton.bottomAnchor.constraint(equalTo: settingsButton.topAnchor, constant: -6),
            quitButton.centerXAnchor.constraint(equalTo: rail.centerXAnchor),
            settingsButton.bottomAnchor.constraint(equalTo: rail.bottomAnchor, constant: -12),
        ])

        view.addSubview(rail)
    }

    // MARK: - Content column

    private func buildSearchBar() {
        searchBar.wantsLayer = true
        searchBar.layer?.cornerRadius = Theme.Metrics.controlCornerRadius
        searchBar.layer?.borderWidth = 1
        searchBar.translatesAutoresizingMaskIntoConstraints = false

        searchIcon.image = Theme.symbol("magnifyingglass", pointSize: 11, weight: .semibold)
        searchIcon.contentTintColor = Theme.textTertiary
        searchIcon.translatesAutoresizingMaskIntoConstraints = false

        // A plain editable field: no custom cell, no bezel. The old search field swapped in a
        // subclassed cell and ended up read-only, which is why typing into it did nothing.
        searchField.isEditable = true
        searchField.isSelectable = true
        searchField.isBezeled = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.font = Theme.Font.body
        searchField.textColor = Theme.textPrimary
        searchField.placeholderAttributedString = NSAttributedString(
            string: "搜索剪贴板…",
            attributes: [
                .font: Theme.Font.body,
                .foregroundColor: Theme.textTertiary,
            ]
        )
        searchField.cell?.usesSingleLineMode = true
        searchField.cell?.isScrollable = true
        searchField.lineBreakMode = .byClipping
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        // The field editor's own notification also covers IME composition (marked text), where
        // `controlTextDidChange` stays silent until the composition is committed.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(fieldEditorTextChanged(_:)),
            name: NSText.didChangeNotification,
            object: nil
        )

        clearButton.isBordered = false
        clearButton.bezelStyle = .inline
        clearButton.image = Theme.symbol("xmark.circle.fill", pointSize: 11, weight: .regular)
        clearButton.contentTintColor = Theme.textTertiary
        clearButton.target = self
        clearButton.action = #selector(clearSearch)
        clearButton.isHidden = true
        clearButton.translatesAutoresizingMaskIntoConstraints = false

        escHint.attributedStringValue = NSAttributedString(
            string: "ESC",
            attributes: [
                .font: Theme.Font.mono(8, weight: .medium),
                .foregroundColor: Theme.textTertiary,
                .kern: 1.0,
            ]
        )
        escHint.translatesAutoresizingMaskIntoConstraints = false

        searchBar.addSubview(searchIcon)
        searchBar.addSubview(searchField)
        searchBar.addSubview(clearButton)
        searchBar.addSubview(escHint)

        NSLayoutConstraint.activate([
            searchIcon.leadingAnchor.constraint(equalTo: searchBar.leadingAnchor, constant: 10),
            searchIcon.centerYAnchor.constraint(equalTo: searchBar.centerYAnchor),
            searchIcon.widthAnchor.constraint(equalToConstant: 13),
            searchIcon.heightAnchor.constraint(equalToConstant: 13),

            searchField.leadingAnchor.constraint(equalTo: searchIcon.trailingAnchor, constant: 7),
            searchField.centerYAnchor.constraint(equalTo: searchBar.centerYAnchor),
            searchField.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -6),

            clearButton.widthAnchor.constraint(equalToConstant: 14),
            clearButton.heightAnchor.constraint(equalToConstant: 14),
            clearButton.centerYAnchor.constraint(equalTo: searchBar.centerYAnchor),
            clearButton.trailingAnchor.constraint(equalTo: escHint.leadingAnchor, constant: -8),

            escHint.trailingAnchor.constraint(equalTo: searchBar.trailingAnchor, constant: -10),
            escHint.centerYAnchor.constraint(equalTo: searchBar.centerYAnchor),
        ])

        content.addSubview(searchBar)
    }

    private func buildMetaBar() {
        metaBar.translatesAutoresizingMaskIntoConstraints = false

        countLabel.attributedStringValue = NSAttributedString(
            string: "0 ITEMS",
            attributes: [
                .font: Theme.Font.mono(9, weight: .medium),
                .foregroundColor: Theme.textTertiary,
                .kern: 1.0,
            ]
        )
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        dateChip.target = self
        dateChip.action = #selector(dateChipTapped)
        for range in ClipDateRange.allCases {
            let item = NSMenuItem(title: range.title, action: #selector(dateItemPicked(_:)), keyEquivalent: "")
            item.target = self
            item.tag = range.rawValue
            item.state = range == dateFilter ? .on : .off
            dateMenu.addItem(item)
        }

        metaBar.addSubview(countLabel)
        metaBar.addSubview(dateChip)

        NSLayoutConstraint.activate([
            countLabel.leadingAnchor.constraint(equalTo: metaBar.leadingAnchor),
            countLabel.centerYAnchor.constraint(equalTo: metaBar.centerYAnchor),

            dateChip.trailingAnchor.constraint(equalTo: metaBar.trailingAnchor),
            dateChip.centerYAnchor.constraint(equalTo: metaBar.centerYAnchor),
            dateChip.leadingAnchor.constraint(greaterThanOrEqualTo: countLabel.trailingAnchor, constant: 8),
        ])

        content.addSubview(metaBar)
    }

    private func buildList() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder
        scrollView.contentInsets = NSEdgeInsets(top: 2, left: 0, bottom: 4, right: 0)
        scrollView.documentView = tableView

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("clip"))
        column.resizingMask = .autoresizingMask
        column.width = Theme.Metrics.panelSize.width - Theme.Metrics.railWidth - 8
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .plain
        tableView.rowHeight = ClipRowView.rowHeight
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.backgroundColor = .clear
        tableView.usesAlternatingRowBackgroundColors = false
        // The rows draw their own HUD pill, so the stock highlight must stay out of the way.
        tableView.selectionHighlightStyle = .none
        tableView.allowsEmptySelection = false
        tableView.allowsMultipleSelection = false
        tableView.focusRingType = .none
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.dataSource = self
        tableView.delegate = self
        // A single click copies straight away: there is nothing to confirm, no paste to arm.
        tableView.target = self
        tableView.action = #selector(handleRowClick)
        // Hover lives on the table, not on the rows: a row's tracking area is re-registered whenever
        // the list scrolls, which used to fire enter/exit for whichever row slid under a stationary
        // pointer. One area for the whole table keeps the highlight tied to real pointer movement.
        tableView.addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
                owner: self
            )
        )
        // The list moves under the pointer while scrolling, so any hover we kept would be a leftover.
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(listDidScroll),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        content.addSubview(scrollView)
    }

    private func buildFooter() {
        footerBar.translatesAutoresizingMaskIntoConstraints = false

        footerLeft.font = Theme.Font.mono(8.5, weight: .regular)
        footerLeft.textColor = Theme.textTertiary
        footerLeft.translatesAutoresizingMaskIntoConstraints = false

        footerRight.font = Theme.Font.mono(8.5, weight: .regular)
        footerRight.textColor = Theme.textTertiary
        footerRight.alignment = .right
        footerRight.lineBreakMode = .byTruncatingTail
        footerRight.translatesAutoresizingMaskIntoConstraints = false

        let separator = Theme.hairline()

        footerBar.addSubview(separator)
        footerBar.addSubview(footerLeft)
        footerBar.addSubview(footerRight)

        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: footerBar.topAnchor),
            separator.leadingAnchor.constraint(equalTo: footerBar.leadingAnchor, constant: 11),
            separator.trailingAnchor.constraint(equalTo: footerBar.trailingAnchor, constant: -10),

            footerLeft.leadingAnchor.constraint(equalTo: footerBar.leadingAnchor, constant: 13),
            footerLeft.centerYAnchor.constraint(equalTo: footerBar.centerYAnchor, constant: 1),

            footerRight.trailingAnchor.constraint(equalTo: footerBar.trailingAnchor, constant: -12),
            footerRight.centerYAnchor.constraint(equalTo: footerBar.centerYAnchor, constant: 1),
            footerRight.leadingAnchor.constraint(
                greaterThanOrEqualTo: footerLeft.trailingAnchor,
                constant: 10
            ),
        ])

        content.addSubview(footerBar)
    }

    private func buildEmptyState() {
        emptyIcon.image = BrandMark.neonImage(size: 44, color: Theme.neon.withAlphaComponent(0.45))
        emptyIcon.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        emptyHint.font = Theme.Font.caption
        emptyHint.textColor = Theme.textTertiary
        emptyHint.alignment = .center
        emptyHint.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(emptyIcon)
        content.addSubview(emptyLabel)
        content.addSubview(emptyHint)

        NSLayoutConstraint.activate([
            emptyIcon.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyIcon.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor, constant: -28),
            emptyIcon.widthAnchor.constraint(equalToConstant: 44),
            emptyIcon.heightAnchor.constraint(equalToConstant: 44),

            emptyLabel.topAnchor.constraint(equalTo: emptyIcon.bottomAnchor, constant: 12),
            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),

            emptyHint.topAnchor.constraint(equalTo: emptyLabel.bottomAnchor, constant: 6),
            emptyHint.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
        ])
    }

    private func applyChrome() {
        searchBar.layer?.backgroundColor = Theme.glass.cgColor
        searchBar.layer?.borderColor = searchBorderColor.cgColor
    }

    private var isSearchFocused: Bool {
        view.window?.firstResponder === searchField.currentEditor()
    }

    private var searchBorderColor: NSColor {
        isSearchFocused ? Theme.neonSoft : Theme.borderSoft
    }

    // MARK: - Public API used by the panel controller

    func reload() {
        let previousSelection = selectedItem?.id
        items = store.fetch(
            query: query,
            category: categoryFilter,
            dateRange: dateFilter,
            limit: 500
        )
        hoveredRow = nil
        tableView.reloadData()
        if let previousSelection,
           let index = items.firstIndex(where: { $0.id == previousSelection }) {
            selectRow(index)
        } else if !items.isEmpty {
            selectRow(0)
        }
        let isEmpty = items.isEmpty
        emptyLabel.isHidden = !isEmpty
        emptyIcon.isHidden = !isEmpty
        emptyHint.isHidden = !isEmpty
        emptyLabel.attributedStringValue = NSAttributedString(
            string: hasActiveFilter ? "NO MATCH · 没有匹配的记录" : "NO DATA · 暂无剪贴板历史",
            attributes: [
                .font: Theme.Font.mono(10, weight: .medium),
                .foregroundColor: Theme.textSecondary,
                .kern: 0.8,
            ]
        )
        emptyHint.stringValue = hasActiveFilter ? "换个关键词或放宽筛选条件" : "复制任意内容后会自动出现在这里"
        updateFooter()
    }

    private var hasActiveFilter: Bool {
        !query.isEmpty || categoryFilter != nil || dateFilter != .all
    }

    func focusSearch() {
        view.window?.makeFirstResponder(searchField)
        applyChrome()
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
        selectRow(next)
    }

    private func selectRow(_ index: Int) {
        tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        tableView.scrollRowToVisible(index)
        syncPills()
        updateFooter()
    }

    /// Repaints every visible row's selection pill after a programmatic selection change.
    private func syncPills() {
        let selected = tableView.selectedRow
        for row in 0..<tableView.numberOfRows {
            guard let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? ClipRowView else {
                continue
            }
            cell.setPillSelected(row == selected)
        }
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

    // MARK: - Hover

    override func mouseEntered(with event: NSEvent) {
        hoverRows(at: event)
    }

    override func mouseMoved(with event: NSEvent) {
        hoverRows(at: event)
    }

    override func mouseExited(with event: NSEvent) {
        setHoveredRow(nil)
    }

    /// Scrolling slides the content under a pointer that never moves, so any hovered row would point
    /// at the wrong entry; drop it and let the next real pointer move highlight again.
    @objc private func listDidScroll() {
        setHoveredRow(nil)
    }

    private func hoverRows(at event: NSEvent) {
        let point = tableView.convert(event.locationInWindow, from: nil)
        guard tableView.bounds.contains(point) else { return setHoveredRow(nil) }
        let row = tableView.row(at: point)
        setHoveredRow(row >= 0 ? row : nil)
    }

    private func setHoveredRow(_ row: Int?) {
        guard row != hoveredRow else { return }
        let previous = hoveredRow
        hoveredRow = row
        // Only the two rows that change need a repaint.
        for index in [previous, row].compactMap({ $0 }) where index < tableView.numberOfRows {
            let cell = tableView.view(atColumn: 0, row: index, makeIfNecessary: false) as? ClipRowView
            cell?.setHovered(index == row)
        }
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
            isImage: item.kind == .image
        )
        cell.setPillSelected(row == tableView.selectedRow)
        // Reused cells keep the previous row's hover, so state it explicitly.
        cell.setHovered(row == hoveredRow)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        syncPills()
        if view.window?.firstResponder !== searchField.currentEditor() {
            view.window?.makeFirstResponder(searchField)
        }
        updateFooter()
    }

    @objc private func handleRowClick() {
        let row = tableView.clickedRow
        guard row >= 0, row < items.count else { return }
        activate(items[row])
    }

    /// Copies one entry. The panel closes itself through the app delegate once the write lands.
    private func activate(_ item: ClipItem) {
        onActivate?(item)
    }

    // MARK: - Search field

    func controlTextDidChange(_ obj: Notification) {
        applyQuery(searchField.stringValue)
    }

    /// Live text from the field editor, including text an input method is still composing.
    @objc private func fieldEditorTextChanged(_ notification: Notification) {
        guard let editor = notification.object as? NSTextView,
              editor === searchField.currentEditor() else { return }
        applyQuery(editor.string)
    }

    /// Pulls the current editor text. Input methods keep text marked (uncommitted), and no
    /// text-change notification arrives for that, so the panel nudges this on every keystroke.
    func syncQueryFromField() {
        applyQuery(searchField.currentEditor()?.string ?? searchField.stringValue)
    }

    private func applyQuery(_ newQuery: String) {
        clearButton.isHidden = newQuery.isEmpty
        guard newQuery != query else { return }
        query = newQuery
        reload()
    }

    func controlTextDidBeginEditing(_ obj: Notification) {
        applyChrome()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        applyChrome()
    }

    @objc private func clearSearch() {
        guard !searchField.stringValue.isEmpty else { return }
        searchField.stringValue = ""
        clearButton.isHidden = true
        query = ""
        reload()
        view.window?.makeFirstResponder(searchField)
    }

    // MARK: - Filters

    @objc private func categoryButtonTapped(_ sender: HUDIconButton) {
        switch sender.tag {
        case 1: categoryFilter = .text
        case 2: categoryFilter = .link
        case 3: categoryFilter = .image
        default: categoryFilter = nil
        }
        for button in categoryButtons {
            button.setActive(button === sender)
        }
        reload()
    }

    @objc private func openPreferences() {
        onOpenPreferences?()
    }

    @objc private func quitApp() {
        onQuit?()
    }

    @objc private func dateChipTapped() {
        for item in dateMenu.items {
            item.state = item.tag == dateFilter.rawValue ? .on : .off
        }
        dateMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: -6), in: dateChip)
    }

    @objc private func dateItemPicked(_ sender: NSMenuItem) {
        dateFilter = ClipDateRange(rawValue: sender.tag) ?? .all
        dateChip.setDisplayTitle(dateFilter.title + " ⌄")
        reload()
    }

    // MARK: - Row content

    private func icon(for item: ClipItem) -> NSImage? {
        switch item.kind {
        case .image:
            guard let url = store.imageURL(for: item) else { return nil }
            return thumbnails.image(for: url)
        case .text:
            let symbol = item.category == .link ? "link" : "text.alignleft"
            return Theme.symbol(symbol, pointSize: 12, weight: .medium)
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

    /// Category and time are the two fields the list can be browsed by, so both are in the
    /// subtitle: "链接 · Safari · 今天 14:32".
    private func subtitle(for item: ClipItem) -> String {
        var parts: [String] = []
        if item.category == .link { parts.append(item.category.title) }
        if let name = appName(for: item.sourceApp) { parts.append(name) }
        parts.append(timeLabel(for: item.createdAt))
        if item.kind == .image { parts.append(byteLabel(item.imageBytes)) }
        if item.truncated { parts.append("已截断") }
        return parts.joined(separator: " · ")
    }

    private func timeLabel(for date: Date) -> String {
        let calendar = Calendar.current
        let clock = clockFormatter.string(from: date)
        if calendar.isDateInToday(date) { return "今天 \(clock)" }
        if calendar.isDateInYesterday(date) { return "昨天 \(clock)" }
        if calendar.component(.year, from: date) == calendar.component(.year, from: Date()) {
            return monthDayFormatter.string(from: date)
        }
        return fullDateFormatter.string(from: date)
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
        countLabel.attributedStringValue = NSAttributedString(
            string: "\(items.count) ITEMS",
            attributes: [
                .font: Theme.Font.mono(9, weight: .medium),
                .foregroundColor: items.isEmpty ? Theme.textTertiary : Theme.neon,
                .kern: 1.0,
            ]
        )
        footerLeft.stringValue = "↑↓ 选择 · ↩ 复制"
        if let item = selectedItem, item.kind == .image, item.imageBytes > 0 {
            footerLeft.stringValue = "\(byteLabel(item.imageBytes)) · ↩ 复制"
        }
        footerRight.stringValue = "⌘⌫ 删除 · esc 关闭"
    }
}
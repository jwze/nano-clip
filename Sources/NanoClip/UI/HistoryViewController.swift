import AppKit
import NanoClipCore

/// History list: search field, view-based table, footer hint. Rebuilt on every panel show and
/// released when the panel hides, so its thumbnails do not linger in memory.
@MainActor
final class HistoryViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    /// Called when the user picks an entry, by click or by ⏎. Copying is the only action.
    var onActivate: ((ClipItem) -> Void)?
    var onDelete: ((ClipItem) -> Void)?

    private let store: ClipStore
    private let thumbnails = ThumbnailCache()

    private var items: [ClipItem] = []
    var query = ""
    private var categoryFilter: ClipCategory?
    private var dateFilter: ClipDateRange = .all
    private var appNames: [String: String] = [:]

    let searchField = PaddedSearchField()
    let tableView = NSTableView()
    private let searchCapsule = FlippedView()
    private let filterBar = FlippedView()
    private let categoryControl = NSSegmentedControl(
        labels: ["全部", "文本", "链接", "图片"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let datePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let scrollView = NSScrollView()
    private let footerBar = FlippedView()
    private let footerLabel = NSTextField(labelWithString: "")
    private let countBadge = NSTextField(labelWithString: "")
    private let emptyIcon = NSImageView()
    private let emptyLabel = NSTextField(labelWithString: "暂无剪贴板历史")

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
        let root = BackdropView(frame: NSRect(origin: .zero, size: Theme.Metrics.panelSize))
        root.wantsLayer = true
        root.layer?.cornerRadius = Theme.Metrics.panelCornerRadius
        root.layer?.masksToBounds = true
        root.onAppearanceChange = { [weak self] in self?.applyThemeColors() }
        view = root
        preferredContentSize = Theme.Metrics.panelSize

        // MARK: search capsule
        searchCapsule.wantsLayer = true
        searchCapsule.layer?.cornerRadius = Theme.Metrics.searchBarCornerRadius
        searchCapsule.translatesAutoresizingMaskIntoConstraints = false

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "搜索剪贴板历史"
        searchField.font = Theme.Font.body
        searchField.isBezeled = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        searchField.delegate = self
        searchCapsule.addSubview(searchField)

        // MARK: list
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder
        scrollView.documentView = tableView

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("clip"))
        column.resizingMask = .autoresizingMask
        column.width = Theme.Metrics.panelSize.width - 16
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .plain
        tableView.rowHeight = ClipRowView.rowHeight
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.backgroundColor = .clear
        tableView.usesAlternatingRowBackgroundColors = false
        // The rows draw their own pill, so the stock highlight must stay out of the way.
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

        // MARK: footer
        footerBar.wantsLayer = true
        footerBar.translatesAutoresizingMaskIntoConstraints = false

        footerLabel.translatesAutoresizingMaskIntoConstraints = false
        footerLabel.font = Theme.Font.hint
        footerLabel.textColor = .secondaryLabelColor
        footerLabel.lineBreakMode = .byTruncatingTail
        footerLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        countBadge.translatesAutoresizingMaskIntoConstraints = false
        countBadge.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        countBadge.textColor = .secondaryLabelColor
        countBadge.alignment = .center
        countBadge.wantsLayer = true
        countBadge.layer?.cornerRadius = 5
        countBadge.layer?.borderWidth = 1
        countBadge.setContentHuggingPriority(.required, for: .horizontal)
        countBadge.setContentCompressionResistancePriority(.required, for: .horizontal)


        // MARK: empty state
        emptyIcon.translatesAutoresizingMaskIntoConstraints = false
        emptyIcon.image = Theme.symbol("tray", pointSize: 26, weight: .light)
        emptyIcon.contentTintColor = .tertiaryLabelColor

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.font = Theme.Font.caption
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.alignment = .center

        // MARK: filter bar (category + time)
        filterBar.translatesAutoresizingMaskIntoConstraints = false

        categoryControl.translatesAutoresizingMaskIntoConstraints = false
        categoryControl.segmentStyle = .rounded
        categoryControl.controlSize = .small
        categoryControl.selectedSegment = 0
        categoryControl.target = self
        categoryControl.action = #selector(categoryChanged)
        for index in 0..<categoryControl.segmentCount {
            categoryControl.setWidth(56, forSegment: index)
        }

        datePopup.translatesAutoresizingMaskIntoConstraints = false
        datePopup.addItems(withTitles: ClipDateRange.allCases.map(\.title))
        datePopup.selectItem(at: 0)
        datePopup.target = self
        datePopup.action = #selector(dateRangeChanged)
        datePopup.controlSize = .small
        datePopup.font = Theme.Font.buttonSmall
        // Borderless: the filter row should read as one quiet strip, not a row of boxes.
        datePopup.bezelStyle = .inline
        datePopup.isBordered = false
        datePopup.contentTintColor = .secondaryLabelColor
        datePopup.setContentHuggingPriority(.required, for: .horizontal)
        datePopup.setContentCompressionResistancePriority(.required, for: .horizontal)

        filterBar.addSubview(categoryControl)
        filterBar.addSubview(datePopup)

        root.addSubview(searchCapsule)
        root.addSubview(filterBar)
        root.addSubview(scrollView)
        root.addSubview(footerBar)
        footerBar.addSubview(footerLabel)
        footerBar.addSubview(countBadge)
        root.addSubview(emptyIcon)
        root.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            searchCapsule.topAnchor.constraint(equalTo: root.topAnchor, constant: 11),
            searchCapsule.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            searchCapsule.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            searchCapsule.heightAnchor.constraint(equalToConstant: Theme.Metrics.searchBarHeight),

            searchField.leadingAnchor.constraint(equalTo: searchCapsule.leadingAnchor, constant: 8),
            searchField.trailingAnchor.constraint(equalTo: searchCapsule.trailingAnchor, constant: -8),
            searchField.centerYAnchor.constraint(equalTo: searchCapsule.centerYAnchor),

            filterBar.topAnchor.constraint(equalTo: searchCapsule.bottomAnchor, constant: 8),
            filterBar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            filterBar.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            filterBar.heightAnchor.constraint(equalToConstant: 22),

            categoryControl.leadingAnchor.constraint(equalTo: filterBar.leadingAnchor),
            categoryControl.centerYAnchor.constraint(equalTo: filterBar.centerYAnchor),
            datePopup.trailingAnchor.constraint(equalTo: filterBar.trailingAnchor),
            datePopup.centerYAnchor.constraint(equalTo: filterBar.centerYAnchor),
            datePopup.leadingAnchor.constraint(
                greaterThanOrEqualTo: categoryControl.trailingAnchor,
                constant: 6
            ),

            scrollView.topAnchor.constraint(equalTo: filterBar.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 3),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -3),
            scrollView.bottomAnchor.constraint(equalTo: footerBar.topAnchor),

            footerBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            footerBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            footerBar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            footerBar.heightAnchor.constraint(equalToConstant: 34),

            countBadge.leadingAnchor.constraint(equalTo: footerBar.leadingAnchor, constant: 13),
            countBadge.centerYAnchor.constraint(equalTo: footerBar.centerYAnchor),
            countBadge.heightAnchor.constraint(equalToConstant: 16),
            countBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 32),

            footerLabel.leadingAnchor.constraint(equalTo: countBadge.trailingAnchor, constant: 8),
            footerLabel.centerYAnchor.constraint(equalTo: footerBar.centerYAnchor),
            footerLabel.trailingAnchor.constraint(lessThanOrEqualTo: footerBar.trailingAnchor, constant: -12),

            emptyIcon.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyIcon.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor, constant: -14),
            emptyLabel.topAnchor.constraint(equalTo: emptyIcon.bottomAnchor, constant: 8),
            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
        ])

        // Footer hairline sits on the bar's top edge.
        let footerLine = Theme.hairline()
        footerBar.addSubview(footerLine)
        NSLayoutConstraint.activate([
            footerLine.topAnchor.constraint(equalTo: footerBar.topAnchor),
            footerLine.leadingAnchor.constraint(equalTo: footerBar.leadingAnchor),
            footerLine.trailingAnchor.constraint(equalTo: footerBar.trailingAnchor),
        ])
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        applyThemeColors()
    }

    private func applyThemeColors() {
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            searchCapsule.layer?.backgroundColor = Theme.searchBackground.cgColor
            countBadge.layer?.backgroundColor = Theme.searchBackground.cgColor
            countBadge.layer?.borderColor = Theme.cardBorder.cgColor
        }
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
        tableView.reloadData()
        if let previousSelection,
           let index = items.firstIndex(where: { $0.id == previousSelection }) {
            selectRow(index)
        } else if !items.isEmpty {
            selectRow(0)
        }
        emptyLabel.isHidden = !items.isEmpty
        emptyIcon.isHidden = !items.isEmpty
        emptyLabel.stringValue = hasActiveFilter ? "没有匹配的记录" : "暂无剪贴板历史"
        updateFooter()
    }

    private var hasActiveFilter: Bool {
        !query.isEmpty || categoryFilter != nil || dateFilter != .all
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
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        syncPills()
        if view.window?.firstResponder !== searchField {
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
        let newQuery = searchField.stringValue
        guard newQuery != query else { return }
        query = newQuery
        reload()
    }

    // MARK: - Filters

    @objc private func categoryChanged() {
        switch categoryControl.selectedSegment {
        case 1: categoryFilter = .text
        case 2: categoryFilter = .link
        case 3: categoryFilter = .image
        default: categoryFilter = nil
        }
        reload()
    }

    @objc private func dateRangeChanged() {
        dateFilter = ClipDateRange(rawValue: datePopup.indexOfSelectedItem) ?? .all
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
            return Theme.symbol(symbol, pointSize: 13, weight: .regular)
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
        countBadge.stringValue = "\(items.count)"
        var hints = "单击复制 · ↑↓ 选择 · ↩ 复制 · ⌘⌫ 删除"
        if let item = selectedItem, item.kind == .image, item.imageBytes > 0 {
            hints = "\(byteLabel(item.imageBytes)) · 单击复制 · ↑↓ 选择 · ↩ 复制"
        }
        footerLabel.stringValue = hints
    }
}

/// Search field whose text starts after the magnifier glyph. A bezel-less `NSSearchField`
/// draws the glyph but keeps the text inset for its (now invisible) bezel at zero.
@MainActor
final class PaddedSearchField: NSSearchField {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        cell = PaddedSearchFieldCell(textCell: "")
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        cell = PaddedSearchFieldCell(textCell: "")
    }
}

@MainActor
final class PaddedSearchFieldCell: NSSearchFieldCell {
    private let leadingInset: CGFloat = 26

    override func searchTextRect(forBounds rect: NSRect) -> NSRect {
        var inset = super.searchTextRect(forBounds: rect)
        inset.origin.x += leadingInset
        inset.size.width -= leadingInset
        return inset
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: searchTextRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(
            withFrame: searchTextRect(forBounds: rect),
            in: controlView,
            editor: textObj,
            delegate: delegate,
            start: selStart,
            length: selLength
        )
    }
}

/// Blur backdrop with an extra tint layer, so text stays readable over a bright desktop.
@MainActor
final class BackdropView: NSVisualEffectView {
    /// Fired whenever the window switches light/dark, so sibling layers can re-resolve their colors.
    var onAppearanceChange: (() -> Void)?

    private let tint = FlippedView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    private func setup() {
        wantsLayer = true
        material = .popover
        blendingMode = .behindWindow
        state = .active
        layer?.cornerRadius = Theme.Metrics.panelCornerRadius
        layer?.masksToBounds = true

        // The tint rides along as a subview so the blur still samples the desktop.
        tint.wantsLayer = true
        tint.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tint)
        NSLayoutConstraint.activate([
            tint.topAnchor.constraint(equalTo: topAnchor),
            tint.leadingAnchor.constraint(equalTo: leadingAnchor),
            tint.trailingAnchor.constraint(equalTo: trailingAnchor),
            tint.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        applyTint()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTint()
        onAppearanceChange?()
    }

    private func applyTint() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            tint.layer?.backgroundColor = Theme.backdropTint.cgColor
        }
    }
}

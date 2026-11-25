import AppKit
import NanoClipCore

/// One row of the status-bar popup: icon, title, shortcut, and a cyan hover band.
///
/// This is a plain view rather than an `NSButton`: a borderless button keeps drawing its cell title
/// underneath any custom label, which showed up as doubled text.
@MainActor
final class HUDMenuRow: NSView {
    var onPick: (() -> Void)?

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let shortcutLabel = NSTextField(labelWithString: "")
    private var isHovered = false {
        didSet { refresh() }
    }

    init(title: String, symbol: String, shortcut: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)

        iconView.image = Theme.symbol(symbol, pointSize: 11.5, weight: .medium)
        iconView.contentTintColor = Theme.textSecondary
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.stringValue = title
        titleLabel.font = Theme.Font.body
        titleLabel.textColor = Theme.textPrimary
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        shortcutLabel.stringValue = shortcut
        shortcutLabel.font = Theme.Font.mono(9, weight: .regular)
        shortcutLabel.textColor = Theme.textTertiary
        shortcutLabel.translatesAutoresizingMaskIntoConstraints = false
        shortcutLabel.setContentHuggingPriority(.required, for: .horizontal)

        addSubview(iconView)
        addSubview(titleLabel)
        addSubview(shortcutLabel)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 32),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalToConstant: 14),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 9),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            shortcutLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            shortcutLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            shortcutLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 8),
        ])

        refresh()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self
            )
        )
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onPick?()
    }

    private func refresh() {
        layer?.backgroundColor = isHovered ? Theme.selectionFill.cgColor : NSColor.clear.cgColor
        iconView.contentTintColor = isHovered ? Theme.neon : Theme.textSecondary
        titleLabel.textColor = isHovered ? Theme.textPrimary : Theme.textSecondary
        shortcutLabel.textColor = isHovered ? Theme.textSecondary : Theme.textTertiary
    }
}

/// The menu-bar popup: a borderless HUD panel with exactly two actions, settings and quit.
/// `NSMenu` cannot be restyled, so the popup is a real window that behaves like a menu.
@MainActor
final class StatusMenuController: NSObject, NSWindowDelegate {
    var itemCount: () -> Int = { 0 }
    var onShowPreferences: (() -> Void)?
    var onQuit: (() -> Void)?

    private var panel: NSPanel?
    private var keyMonitor: Any?
    private var globalClickMonitor: Any?
    /// When the popup last dismissed itself. The outside-click monitor fires on mouse-down, before
    /// the status button's mouse-up that would re-open it, so that same click must be swallowed.
    private var lastDismissAt: TimeInterval = 0

    /// How long after a dismissal the status button ignores a click, in seconds.
    private static let dismissGuard: TimeInterval = 0.25

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    func toggle(relativeTo button: NSStatusBarButton) {
        if isVisible {
            hide()
            return
        }
        // The click that just dismissed the popup still has a mouse-up on its way; if it lands here
        // it must not re-open what the mouse-down already closed.
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastDismissAt > Self.dismissGuard else { return }
        show(relativeTo: button)
    }

    private func show(relativeTo button: NSStatusBarButton) {
        let panel = makePanel()
        self.panel = panel

        let size = panel.frame.size
        guard let buttonWindow = button.window else { return }
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        var origin = NSPoint(
            x: anchor.midX - size.width / 2,
            y: anchor.minY - size.height - 6
        )
        if let screen = buttonWindow.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
            origin.y = max(origin.y, visible.minY + 8)
        }
        panel.setFrameOrigin(origin)

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        installMonitors()
        Log.info("status menu shown at \(panel.frame)")
    }

    func hide() {
        removeMonitors()
        if let panel, panel.isVisible {
            lastDismissAt = ProcessInfo.processInfo.systemUptime
        }
        panel?.orderOut(nil)
        panel = nil
    }

    private func makePanel() -> NSPanel {
        let content = makeContentView()
        let height = content.fittingSize.height
        let size = NSSize(width: 252, height: height)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.appearance = NSAppearance(named: .aqua)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.contentView = content
        panel.setContentSize(size)
        return panel
    }

    private func makeContentView() -> NSView {
        let root = HUDView(cornerRadius: 12, showsEdge: false)
        root.translatesAutoresizingMaskIntoConstraints = false

        let brand = NSImageView()
        brand.image = BrandMark.neonImage(size: 16, color: Theme.neon)
        brand.translatesAutoresizingMaskIntoConstraints = false

        let wordmark = Theme.monoLabel(
            "NANOCLIP",
            size: 9.5,
            weight: .semibold,
            color: Theme.textPrimary,
            tracking: 2.4
        )
        let status = Theme.monoLabel(
            "\(itemCount()) ITEMS",
            size: 8.5,
            weight: .regular,
            color: Theme.textTertiary,
            tracking: 0.6
        )
        let titles = NSStackView(views: [wordmark, status])
        titles.orientation = .vertical
        titles.alignment = .leading
        titles.spacing = 1
        titles.translatesAutoresizingMaskIntoConstraints = false

        let separator = Theme.hairline()

        let settingsRow = HUDMenuRow(title: "设置…", symbol: "gearshape", shortcut: "⌘,")
        settingsRow.onPick = { [weak self] in self?.showPreferences() }

        let quitRow = HUDMenuRow(title: "退出", symbol: "power", shortcut: "⌘Q")
        quitRow.onPick = { [weak self] in self?.quit() }

        let rows = NSStackView(views: [settingsRow, quitRow])
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 2
        rows.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(brand)
        root.addSubview(titles)
        root.addSubview(separator)
        root.addSubview(rows)

        NSLayoutConstraint.activate([
            brand.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            brand.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            brand.widthAnchor.constraint(equalToConstant: 16),
            brand.heightAnchor.constraint(equalToConstant: 16),

            titles.leadingAnchor.constraint(equalTo: brand.trailingAnchor, constant: 9),
            titles.centerYAnchor.constraint(equalTo: brand.centerYAnchor),
            titles.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -12),

            separator.topAnchor.constraint(equalTo: brand.bottomAnchor, constant: 10),
            separator.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            separator.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),

            rows.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 6),
            rows.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 6),
            rows.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -6),
            rows.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -8),
        ])

        root.layoutSubtreeIfNeeded()
        return root
    }

    private func installMonitors() {
        removeMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible else { return event }
            if event.keyCode == 53 {  // esc
                self.hide()
                return nil
            }
            return event
        }
        // Any click that is not inside the popup dismisses it, mirroring menu behaviour even when
        // the app never becomes active.
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
    }

    private func removeMonitors() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
    }

    private func showPreferences() {
        hide()
        onShowPreferences?()
    }

    private func quit() {
        hide()
        onQuit?()
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }
}
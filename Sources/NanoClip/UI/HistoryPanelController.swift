import AppKit
import NanoClipCore

@MainActor
final class HistoryPanelController: NSObject, NSWindowDelegate {
    private let store: ClipStore
    private let prefs: Prefs

    private var panel: HistoryPanel?
    private var contentController: HistoryViewController?
    private var keyMonitor: Any?
    private var activationObserver: NSObjectProtocol?
    private var isHiding = false

    /// The app that was frontmost when the panel was opened; that is where ⌘V goes.
    private(set) var targetApplication: NSRunningApplication?
    /// Used when NanoClip itself is frontmost (e.g. the panel was reopened without switching apps).
    var fallbackTargetProvider: (() -> NSRunningApplication?)?

    var onActivate: ((ClipItem) -> Void)?
    var onDelete: ((ClipItem) -> Void)?
    var onTogglePin: ((ClipItem) -> Void)?
    var onOpenPreferences: (() -> Void)?
    var onRequestAccessibility: (() -> Void)?

    init(store: ClipStore, prefs: Prefs) {
        self.store = store
        self.prefs = prefs
        super.init()
    }

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    func show() {
        if isVisible {
            hide()
            return
        }
        captureTargetApplication()

        let panel = ensurePanel()
        let controller = HistoryViewController(store: store, prefs: prefs)
        controller.onActivate = { [weak self] item in self?.onActivate?(item) }
        controller.onDelete = { [weak self] item in self?.onDelete?(item) }
        controller.onTogglePin = { [weak self] item in self?.onTogglePin?(item) }
        controller.onRequestAccessibility = { [weak self] in
            self?.hide()
            self?.onRequestAccessibility?()
        }
        panel.contentViewController = controller
        contentController = controller
        // Assigning a content view controller re-sizes the panel to its fitting size; force the
        // intended geometry back so the HUD keeps its 360×470 layout.
        panel.setContentSize(HistoryPanel.size)
        controller.reload()

        position(panel)
        // An accessory app still has to be *active* for its panel to receive keystrokes; the target
        // app is re-activated on close, so the switch stays invisible to the user.
        // Verified on macOS 27: bare `activate()` is a no-op for an accessory app, while the
        // (deprecated) ignoring-other-apps variant really activates. Without activation the panel
        // can be key but keystrokes keep going to the previously active app.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeKey()
        controller.focusSearch()
        // Activation is asynchronous; claim key window + focus once the app is really active.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.focusPanel() }
        }
        DispatchQueue.main.async { [weak self] in
            self?.focusPanel()
        }
        installKeyMonitor()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(prefsDidChange),
            name: Prefs.didChangeNotification,
            object: nil
        )
        Log.info(
            "history panel shown: frame=\(panel.frame) key=\(panel.isKeyWindow) "
                + "target=\(targetApplication?.bundleIdentifier ?? "none")"
        )
    }

    func hide(restoreFocus: Bool = true) {
        guard !isHiding else { return }
        isHiding = true
        defer { isHiding = false }

        removeKeyMonitor()
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        NotificationCenter.default.removeObserver(self, name: Prefs.didChangeNotification, object: nil)
        panel?.orderOut(nil)
        // Drop the view controller so its table data and thumbnails are freed while hidden.
        panel?.contentViewController = nil
        contentController = nil
        if restoreFocus {
            targetApplication?.activate()
        }
        Log.info("history panel hidden (restoreFocus=\(restoreFocus))")
    }

    private func focusPanel() {
        guard let panel, panel.isVisible else { return }
        panel.makeKey()
        contentController?.focusSearch()
        Log.info("panel focused: key=\(panel.isKeyWindow) appActive=\(NSApp.isActive)")
    }

    func refreshIfVisible() {
        guard isVisible else { return }
        contentController?.reload()
    }

    // MARK: - Internals

    private func captureTargetApplication() {
        // Only real (Dock-level) apps are paste targets; system agents such as notification banners
        // can be "frontmost" and would steal the ⌘V.
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.bundleIdentifier != AppInfo.bundleID,
           frontmost.activationPolicy == .regular {
            targetApplication = frontmost
            return
        }
        if let fallback = fallbackTargetProvider?(), !fallback.isTerminated {
            targetApplication = fallback
        }
    }

    private func ensurePanel() -> HistoryPanel {
        if let panel {
            panel.delegate = self
            return panel
        }
        let panel = HistoryPanel()
        panel.delegate = self
        self.panel = panel
        return panel
    }

    private func position(_ panel: HistoryPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.frame.size
        var x = visible.midX - size.width / 2
        var y = visible.minY + visible.height * 2 / 3 - size.height / 2
        // Keep the whole panel on-screen for short visible frames.
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        y = min(max(y, visible.minY + 8), visible.maxY - size.height - 8)
        panel.setFrameOrigin(NSPoint(x: x.rounded(), y: y.rounded()))
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let panel = self.panel, panel.isVisible, panel.isKeyWindow else {
                return event
            }
            return self.handleKeyDown(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    func handleKeyDown(_ event: NSEvent) -> Bool {
        if contentController?.isComposingText == true { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch event.keyCode {
        case 53:  // esc
            hide()
            return true
        case 36, 76:  // return, enter
            contentController?.activateSelected()
            return true
        case 125:  // down
            contentController?.moveSelection(by: 1)
            return true
        case 126:  // up
            contentController?.moveSelection(by: -1)
            return true
        case 51 where flags.contains(.command):  // ⌘⌫
            contentController?.deleteSelected()
            return true
        case 35 where flags.contains(.command):  // ⌘P
            contentController?.togglePinSelected()
            return true
        case 43 where flags.contains(.command):  // ⌘,
            hide()
            onOpenPreferences?()
            return true
        default:
            return false
        }
    }

    @objc private func prefsDidChange() {
        refreshIfVisible()
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        guard !isHiding else { return }
        // Focus moved to another app because the user clicked away: do not yank it back.
        hide(restoreFocus: NSApp.isActive)
    }
}
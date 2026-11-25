import AppKit
import NanoClipCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let prefs = Prefs.shared

    private var store: ClipStore?
    private var monitor: PasteboardMonitor?
    private var capture: CaptureService?
    private var hotKey: HotKeyManager?
    private var doubleTap: DoubleTapMonitor?
    private var appliedTrigger: HotKeyTrigger?
    private var frontmostTracker: FrontmostTracker?
    private var statusItemController: StatusItemController?
    private var historyController: HistoryPanelController?
    private var preferencesController: PreferencesWindowController?
    private var prefsObserver: NSObjectProtocol?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installMainMenu()
        if !CommandLine.arguments.contains("--diagnostics") {
            SingleInstance.exitIfAlreadyRunning()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.info("NanoClip \(AppInfo.version) launching (pid \(getpid()))")

        if CommandLine.arguments.contains("--diagnostics") {
            runDiagnostics()
            return
        }

        guard openStore() else { return }
        startCapture()
        startHotKey()
        startStatusItem()
        configureLoginItemOnLaunch()
        observePreferences()
        handleLaunchArguments()

        Log.info(
            "ready: hotkey=\(prefs.hotKeyTrigger.displayString) store=\(store?.directory.path ?? "?") "
                + "rss=\(ProcessMemory.residentDescription)"
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// A minimal main menu. Accessory apps still need one: ⌘V/⌘C inside the panel's search field
    /// only work when the standard Edit commands exist in the responder chain.
    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        appMenu.addItem(
            withTitle: "关于 NanoClip",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        let preferencesMenuItem = NSMenuItem(
            title: "偏好设置…",
            action: #selector(menuShowPreferences),
            keyEquivalent: ","
        )
        preferencesMenuItem.target = self
        appMenu.addItem(preferencesMenuItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 NanoClip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        NSApp.mainMenu = mainMenu
    }

    @objc private func menuShowPreferences() {
        showPreferences()
    }

    // MARK: - Setup

    private func openStore() -> Bool {
        do {
            let store = try ClipStore()
            self.store = store
            store.trim(limits: prefs.limits)
            let orphans = store.gcOrphanImages()
            if orphans > 0 { Log.info("removed \(orphans) orphan image files") }
            let stats = store.statistics()
            Log.info("store ready: \(stats.count) items, images \(stats.imageBytes) bytes")
            return true
        } catch {
            Log.error("store could not be opened: \(error)")
            let alert = NSAlert()
            alert.messageText = "NanoClip 无法打开历史数据库"
            alert.informativeText = "\(error)"
            alert.alertStyle = .critical
            alert.runModal()
            NSApp.terminate(nil)
            return false
        }
    }

    private func startCapture() {
        guard let store else { return }
        frontmostTracker = FrontmostTracker()

        let capture = CaptureService(store: store, prefs: prefs)
        capture.onHistoryChanged = { [weak self] in
            self?.historyController?.refreshIfVisible()
        }
        self.capture = capture

        let monitor = PasteboardMonitor()
        monitor.onCapture = { snapshot, _ in capture.handle(snapshot) }
        monitor.sourceAppProvider = { [weak self] in self?.frontmostTracker?.currentBundleID }
        monitor.start()
        self.monitor = monitor
        Log.info("pasteboard monitor started")
    }

    private func startHotKey() {
        let manager = HotKeyManager()
        manager.onTrigger = { [weak self] in self?.showHistory() }
        hotKey = manager

        let monitor = DoubleTapMonitor()
        monitor.onTrigger = { [weak self] in self?.showHistory() }
        doubleTap = monitor

        applyHotKey(notifyOnFailure: false)
    }

    /// Registers whichever trigger the user chose. Key combos go through Carbon; a double tap is
    /// read from the global modifier state, so neither path needs Accessibility permission.
    private func applyHotKey(notifyOnFailure: Bool) {
        let trigger = prefs.hotKeyTrigger
        guard trigger != appliedTrigger else {
            statusItemController?.refreshHotKeyTitle()
            return
        }
        appliedTrigger = trigger

        hotKey?.unregister()
        doubleTap?.stop()

        switch trigger {
        case .keyCombo(let combo):
            let ok = hotKey?.register(combo) ?? false
            statusItemController?.refreshHotKeyTitle()
            guard !ok, notifyOnFailure else { return }
            presentHotKeyFailure(combo.displayString)
        case .doubleTap(let modifier):
            doubleTap?.start(modifier: modifier)
            Log.info("double tap \(modifier.name) registered")
            statusItemController?.refreshHotKeyTitle()
        }
    }

    private func presentHotKeyFailure(_ display: String) {
        let alert = NSAlert()
        alert.messageText = "快捷键 \(display) 注册失败"
        alert.informativeText = "可能已被其他程序占用。请在偏好设置里换一个组合键。"
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func startStatusItem() {
        let controller = StatusItemController()
        controller.hotKeyDisplay = { [weak self] in self?.prefs.hotKeyTrigger.menuString ?? "" }
        controller.itemCount = { [weak self] in self?.store?.statistics().count ?? 0 }
        controller.onShowPreferences = { [weak self] in self?.showPreferences() }
        statusItemController = controller
    }

    private func configureLoginItemOnLaunch() {
        if prefs.launchAtLogin {
            guard LoginItem.status != .enabled, !prefs.didAttemptLoginItem else { return }
            let ok = LoginItem.register()
            prefs.didAttemptLoginItem = true
            Log.info("first-run login item registration: \(ok)")
        } else if LoginItem.status == .enabled {
            LoginItem.unregister()
        }
    }

    private func observePreferences() {
        prefsObserver = NotificationCenter.default.addObserver(
            forName: Prefs.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.preferencesDidChange()
            }
        }
    }

    private func preferencesDidChange() {
        store?.trim(limits: prefs.limits)
        applyHotKey(notifyOnFailure: true)
        statusItemController?.refreshHotKeyTitle()
        historyController?.refreshIfVisible()

        // Keep the system login item aligned with the stored intent (idempotent).
        if prefs.launchAtLogin, LoginItem.status == .notRegistered {
            LoginItem.register()
        } else if !prefs.launchAtLogin, LoginItem.status == .enabled {
            LoginItem.unregister()
        }
    }

    private func handleLaunchArguments() {
        let arguments = CommandLine.arguments
        if arguments.contains("--show-history") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showHistory()
            }
        }
        if arguments.contains("--show-preferences") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showPreferences()
            }
        }
    }

    // MARK: - Panel

    func showHistory() {
        guard let store else { return }
        if historyController == nil {
            let controller = HistoryPanelController(store: store)
            controller.fallbackTargetProvider = { [weak self] in
                self?.frontmostTracker?.lastExternalApplication
            }
            controller.onActivate = { [weak self] item in self?.copyToPasteboard(item) }
            controller.onDelete = { [weak self] item in
                self?.store?.delete(id: item.id)
                self?.historyController?.refreshIfVisible()
            }
            controller.onOpenPreferences = { [weak self] in self?.showPreferences() }
            historyController = controller
        }
        historyController?.show()
    }

    /// Puts the chosen item back on the pasteboard. Re-copying an existing entry never creates a
    /// second row: the write is announced to the monitor, so the poller ignores its own change,
    /// and the row is bumped to the front of the list by refreshing its timestamp.
    private func copyToPasteboard(_ item: ClipItem) {
        guard let store else { return }

        let changeCount: Int
        switch item.kind {
        case .text:
            changeCount = PasteboardWriter.writePlainText(item.text ?? "")
        case .image:
            guard let url = store.imageURL(for: item), let data = try? Data(contentsOf: url) else {
                Log.error("image file missing for item \(item.id)")
                return
            }
            changeCount = PasteboardWriter.writeImage(data, uti: store.imageUTI(for: item))
        }
        monitor?.expectChange(changeCount)
        store.touch(id: item.id)

        let target = historyController?.targetApplication
        Log.info(
            "copied item \(item.id) kind=\(item.kind == .text ? "text" : "image") "
                + "target=\(target?.bundleIdentifier ?? "none")"
        )

        // Hide on the next run loop turn: the panel controller must not be torn down while its own
        // callback is still on the stack. Focus goes back to the app the user came from, so a
        // manual ⌘V lands in the right place.
        DispatchQueue.main.async { [weak self] in
            self?.historyController?.hide(restoreFocus: false)
            target?.activate()
        }
    }

    // MARK: - Preferences

    func showPreferences() {
        guard let store else { return }
        if preferencesController == nil {
            preferencesController = PreferencesWindowController(
                store: store,
                prefs: prefs,
                onHotKeyChanged: { [weak self] _ in
                    self?.applyHotKey(notifyOnFailure: true)
                },
                onLoginItemChanged: { enabled in
                    LoginItem.apply(enabled: enabled)
                }
            )
        }
        NSApp.activate()
        preferencesController?.showWindow(nil)
        preferencesController?.window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Diagnostics

    private func runDiagnostics() {
        let bundleID = Bundle.main.bundleIdentifier ?? "none"
        print("bundle: \(bundleID)")
        print("version: \(AppInfo.version)")
        print("hotkey: \(prefs.hotKeyTrigger.displayString)")
        print("launchAtLogin(pref): \(prefs.launchAtLogin)")
        print("launchAtLogin(system): \(LoginItem.statusDescription)")
        print("maxItems: \(prefs.keepsEverything ? "unlimited" : String(prefs.maxItems))")
        print("recordImages: \(prefs.recordImages)")
        print("ignoredApps: \(prefs.ignoredBundleIDs.count)")

        if let store = try? ClipStore() {
            let stats = store.statistics()
            print("store: \(store.directory.path)")
            print("items: \(stats.count)")
            print("imageItems: \(stats.imageCount)")
            print("imageBytes: \(stats.imageBytes)")
            let orphans = store.gcOrphanImages()
            print("orphanImagesRemoved: \(orphans)")
        } else {
            print("store: <failed to open>")
        }
        print("rssBytes: \(ProcessMemory.residentBytes)")
        print("rss: \(ProcessMemory.residentDescription)")
        exit(0)
    }
}
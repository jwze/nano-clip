import AppKit
import NanoClipCore

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()

    private let historyItem = NSMenuItem()
    private let preferencesItem = NSMenuItem()
    private let loginItemCheckbox = NSMenuItem()
    private let quitItem = NSMenuItem()

    var onShowHistory: (() -> Void)?
    var onShowPreferences: (() -> Void)?
    var onToggleLoginItem: (() -> Void)?
    var hotKeyDisplay: () -> String = { "" }
    var loginItemOn: () -> Bool = { false }

    override init() {
        super.init()
        configureButton()
        configureMenu()
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        // A configured template symbol reads cleaner than the default-size glyph at 18pt.
        let configuration = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        let image = (NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "NanoClip")
            ?? NSImage(systemSymbolName: "list.clipboard", accessibilityDescription: "NanoClip"))?
            .withSymbolConfiguration(configuration)
        image?.isTemplate = true
        button.image = image
        button.toolTip = "NanoClip 剪贴板历史"
        statusItem.menu = menu
    }

    private func configureMenu() {
        menu.delegate = self
        menu.autoenablesItems = false

        historyItem.target = self
        historyItem.action = #selector(showHistory)
        historyItem.image = Theme.symbol("clock.arrow.circlepath", pointSize: 13)
        menu.addItem(historyItem)

        preferencesItem.title = "偏好设置…"
        preferencesItem.target = self
        preferencesItem.action = #selector(showPreferences)
        preferencesItem.keyEquivalent = ","
        preferencesItem.keyEquivalentModifierMask = [.command]
        preferencesItem.image = Theme.symbol("gearshape", pointSize: 13)
        menu.addItem(preferencesItem)

        menu.addItem(.separator())

        loginItemCheckbox.title = "登录时自动启动"
        loginItemCheckbox.target = self
        loginItemCheckbox.action = #selector(toggleLoginItem)
        loginItemCheckbox.image = Theme.symbol("power", pointSize: 13)
        menu.addItem(loginItemCheckbox)

        let aboutItem = NSMenuItem(title: "关于 NanoClip", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        aboutItem.image = Theme.symbol("info.circle", pointSize: 13)
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        quitItem.title = "退出 NanoClip"
        quitItem.target = self
        quitItem.action = #selector(quit)
        quitItem.keyEquivalent = "q"
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.image = Theme.symbol("xmark.circle", pointSize: 13)
        menu.addItem(quitItem)

        Log.info(
            "status item ready: image=\(statusItem.button?.image == nil ? "nil" : "SF Symbol") "
                + "menuItems=\(menu.items.count) visible=\(statusItem.isVisible)"
        )
    }

    func refreshHotKeyTitle() {
        historyItem.title = "显示剪贴板历史    \(hotKeyDisplay())"
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshHotKeyTitle()
        loginItemCheckbox.state = loginItemOn() ? .on : .off
    }

    @objc private func showHistory() {
        onShowHistory?()
    }

    @objc private func showPreferences() {
        onShowPreferences?()
    }

    @objc private func toggleLoginItem() {
        onToggleLoginItem?()
    }
    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: AppInfo.name,
            .applicationVersion: AppInfo.version,
            .credits: NSAttributedString(
                string: "本地剪贴板历史 · 数据只保存在本机",
                attributes: [.font: NSFont.systemFont(ofSize: 11)]
            ),
        ])
        NSApp.activate()
    }


    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
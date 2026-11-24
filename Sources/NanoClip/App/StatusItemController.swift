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
        let image = NSImage(systemSymbolName: "list.clipboard", accessibilityDescription: "NanoClip")
            ?? NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "NanoClip")
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
        menu.addItem(historyItem)

        preferencesItem.title = "偏好设置…"
        preferencesItem.target = self
        preferencesItem.action = #selector(showPreferences)
        preferencesItem.keyEquivalent = ","
        preferencesItem.keyEquivalentModifierMask = [.command]
        menu.addItem(preferencesItem)

        menu.addItem(.separator())

        loginItemCheckbox.title = "登录时自动启动"
        loginItemCheckbox.target = self
        loginItemCheckbox.action = #selector(toggleLoginItem)
        menu.addItem(loginItemCheckbox)

        menu.addItem(.separator())

        quitItem.title = "退出 NanoClip"
        quitItem.target = self
        quitItem.action = #selector(quit)
        quitItem.keyEquivalent = "q"
        quitItem.keyEquivalentModifierMask = [.command]
        menu.addItem(quitItem)
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

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
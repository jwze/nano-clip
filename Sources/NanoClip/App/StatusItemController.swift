import AppKit
import NanoClipCore

/// Menu-bar presence: the brand glyph plus a HUD popup with exactly "设置…" and "退出".
@MainActor
final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = StatusMenuController()

    var onShowPreferences: (() -> Void)?
    var hotKeyDisplay: () -> String = { "" }
    var itemCount: () -> Int = { 0 }

    override init() {
        super.init()
        configureButton()

        menu.hotKeyDisplay = { [weak self] in self?.hotKeyDisplay() ?? "" }
        menu.itemCount = { [weak self] in self?.itemCount() ?? 0 }
        menu.onShowPreferences = { [weak self] in self?.onShowPreferences?() }
        menu.onQuit = { NSApp.terminate(nil) }
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        // The same geometry as the app icon, flattened to an alpha-only template glyph.
        let image = BrandMark.menuBarImage()
        image.isTemplate = true
        button.image = image
        button.imagePosition = .imageOnly
        button.toolTip = "NanoClip 剪贴板历史"
        button.target = self
        button.action = #selector(toggleMenu)
        button.sendAction(on: [.leftMouseUp])
        statusItem.menu = nil

        Log.info("status item ready: brand glyph menu=popup visible=\(statusItem.isVisible)")
    }

    func refreshHotKeyTitle() {
        // The popup rebuilds its status line on every open, so nothing to precompute here.
    }

    @objc private func toggleMenu() {
        guard let button = statusItem.button else { return }
        menu.toggle(relativeTo: button)
    }
}
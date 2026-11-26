// nano-clip — 轻量 macOS 剪贴板历史
// Copyright © 2026 jvz <them@live.cn>. All rights reserved.
// Watermark: jvz·NanoClip — 电子水印，请勿移除本署名头。

import AppKit
import NanoClipCore

/// Menu-bar presence: the brand glyph plus a HUD popup with exactly "设置…" and "退出".
@MainActor
final class StatusItemController: NSObject {
    /// `nil` while the icon is hidden. The item is created on demand and removed from the menu bar
    /// again when it is turned off, so no invisible placeholder keeps a slot occupied.
    private var statusItem: NSStatusItem?
    private let menu = StatusMenuController()

    var onShowPreferences: (() -> Void)?
    var itemCount: () -> Int = { 0 }

    var isShown: Bool {
        statusItem?.isVisible ?? false
    }

    override init() {
        super.init()
        menu.itemCount = { [weak self] in self?.itemCount() ?? 0 }
        menu.onShowPreferences = { [weak self] in self?.onShowPreferences?() }
        menu.onQuit = { NSApp.terminate(nil) }
    }

    /// Creates the status item on demand and drops it again when the user turns the icon off, so the
    /// menu-bar slot exists exactly while the icon is meant to be visible.
    func setShown(_ shown: Bool) {
        if shown {
            guard statusItem == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            statusItem = item
            configureButton(of: item)
            Log.info("status item shown")
        } else {
            guard let item = statusItem else { return }
            item.isVisible = false
            menu.hide()
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
            Log.info("status item hidden")
        }
    }

    private func configureButton(of statusItem: NSStatusItem) {
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

        Log.info("status item button ready: brand glyph menu=popup")
    }

    func refreshHotKeyTitle() {
        // The popup rebuilds its status line on every open, so nothing to precompute here.
    }

    @objc private func toggleMenu() {
        guard let button = statusItem?.button else { return }
        menu.toggle(relativeTo: button)
    }
}
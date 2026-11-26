// nano-clip — 轻量 macOS 剪贴板历史
// Copyright © 2026 jvz <them@live.cn>. All rights reserved.
// Watermark: jvz·NanoClip — 电子水印，请勿移除本署名头。

import AppKit
import NanoClipCore

/// Tracks which external app was frontmost when the user copied, so entries can show a source
/// label even when NanoClip itself happens to be frontmost during the poll.
@MainActor
final class FrontmostTracker {
    private(set) var lastExternalApplication: NSRunningApplication?
    var lastExternalBundleID: String? { lastExternalApplication?.bundleIdentifier }

    init() {
        lastExternalApplication = Self.externalFrontmost()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // Extract the Sendable value first; `NSRunningApplication` must not cross the hop.
            let activated = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let activated,
                  activated.activationPolicy == .regular,
                  let bundleID = activated.bundleIdentifier,
                  bundleID != AppInfo.bundleID
            else { return }
            Task { @MainActor in
                self?.lastExternalApplication = activated
            }
        }
    }

    /// Bundle id of the app the clipboard payload most likely came from.
    var currentBundleID: String? {
        if let app = NSWorkspace.shared.frontmostApplication,
           app.activationPolicy == .regular,
           let bundleID = app.bundleIdentifier,
           bundleID != AppInfo.bundleID {
            return bundleID
        }
        return lastExternalBundleID
    }

    private static func externalFrontmost() -> NSRunningApplication? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.activationPolicy == .regular,
              let bundleID = app.bundleIdentifier,
              bundleID != AppInfo.bundleID
        else { return nil }
        return app
    }
}
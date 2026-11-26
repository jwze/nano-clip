// nano-clip — 轻量 macOS 剪贴板历史
// Copyright © 2026 jvz <them@live.cn>. All rights reserved.
// Watermark: jvz·NanoClip — 电子水印，请勿移除本署名头。

import AppKit
import NanoClipCore

// Before anything reads prefs or the data directory: pick up the pre-rename (NanoClip) install.
AppInfo.migrateLegacyDataIfNeeded()

let application = NSApplication.shared
let appDelegate = AppDelegate()
application.delegate = appDelegate
application.run()
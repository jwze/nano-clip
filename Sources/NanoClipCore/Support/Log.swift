// nano-clip — 轻量 macOS 剪贴板历史
// Copyright © 2026 jvz <them@live.cn>. All rights reserved.
// Watermark: jvz·NanoClip — 电子水印，请勿移除本署名头。

import Foundation
import os

/// Tiny append-only log: unified logging + a capped plain-text file, so the app can be verified
/// from a shell without extra tooling.
public enum Log {
    private static let logger = Logger(subsystem: AppInfo.bundleID, category: "app")
    private static let state = State()

    public static var fileURL: URL { state.url }

    public static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        state.append("INFO", message)
    }

    public static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        state.append("ERROR", message)
    }

    private final class State: @unchecked Sendable {
        let url: URL
        private let lock = NSLock()
        private let maxBytes = 512 * 1024
        private let formatter = ISO8601DateFormatter()

        init() {
            let dir = AppInfo.applicationSupportDirectory()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            url = dir.appendingPathComponent("\(AppInfo.name).log")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        func append(_ level: String, _ message: String) {
            lock.lock()
            defer { lock.unlock() }
            let line = "\(formatter.string(from: Date())) [\(level)] \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            let fm = FileManager.default
            if let attrs = try? fm.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? Int, size > maxBytes {
                try? fm.removeItem(at: url)
            }
            if !fm.fileExists(atPath: url.path) {
                fm.createFile(atPath: url.path, contents: nil)
            }
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            }
        }
    }
}
// nano-clip — 轻量 macOS 剪贴板历史
// Copyright © 2026 jvz <them@live.cn>. All rights reserved.
// Watermark: jvz·NanoClip — 电子水印，请勿移除本署名头。

import Foundation

public enum AppInfo {
    /// App name, SwiftPM package name and the folder everything is keyed by. The repository is
    /// called `nano-clip`; the shipped artifact, module and bundle identifier are `NanoClip`
    /// (module identifiers cannot contain a hyphen anyway).
    public static let name = "NanoClip"
    public static let bundleID = "com.jvz.nanoclip"
    public static let version = "1.0.0"
    public static let build = "1"

    // MARK: - Author watermark
    //
    // Stamped into every source file header and referenced at runtime (About panel, `--diagnostics`
    // banner) so the signature also survives into the shipped binary.

    public static let author = "jvz <them@live.cn>"
    public static let watermark = "jvz·NanoClip"
    /// Long form, kept as a plain literal so it is greppable inside the built binary
    /// (`strings NanoClip | grep jvz`).
    public static let signature = "NanoClip by jvz <them@live.cn> -- watermark jvz-NanoClip"
    public static let copyright = "© 2026 jvz <them@live.cn>. All rights reserved."

    /// Identities this app has been built under besides `name` / `bundleID`, newest last.
    ///
    /// `nano-clip` was a local rename that was never released; a build of it may still have written
    /// a data directory and a preferences domain, which are adopted back on the next launch.
    enum Legacy {
        static let names = ["nano-clip"]
        static let bundleIDs = ["com.jvz.nano-clip"]
    }

    /// ~/Library/Application Support/NanoClip
    public static func applicationSupportDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent(name, isDirectory: true)
    }

    /// Adopts the data directory and the preferences of a legacy identity, once.
    ///
    /// Both are keyed by name / bundle id, so a rename would otherwise look like a fresh install.
    /// Safe to call on every launch: it only fills what the current location does not have yet.
    public static func migrateLegacyDataIfNeeded() {
        migrateLegacyDirectories()
        migrateLegacyDefaults()
    }

    private static func migrateLegacyDirectories() {
        let fileManager = FileManager.default
        let current = applicationSupportDirectory()
        let parent = current.deletingLastPathComponent()
        for name in Legacy.names {
            let legacy = parent.appendingPathComponent(name, isDirectory: true)
            guard fileManager.fileExists(atPath: legacy.path) else { continue }
            // Two store directories are never merged automatically: the current one wins.
            guard !fileManager.fileExists(atPath: current.path) else {
                Log.info("ignoring legacy data directory \(name): \(self.name) already has one")
                continue
            }
            do {
                try fileManager.moveItem(at: legacy, to: current)
                Log.info("adopted data directory from \(name)")
            } catch {
                Log.error("could not adopt \(legacy.path): \(error)")
            }
        }
    }

    private static func migrateLegacyDefaults() {
        let defaults = UserDefaults.standard
        // Per key, not per domain: `Prefs` may already have registered its own defaults, and those
        // are only fallbacks — anything a build actually stored wins until it is stored here.
        let current = defaults.persistentDomain(forName: bundleID) ?? [:]
        for legacyID in Legacy.bundleIDs {
            guard let legacy = defaults.persistentDomain(forName: legacyID), !legacy.isEmpty else { continue }
            var copied = 0
            for (key, value) in legacy where current[key] == nil {
                defaults.set(value, forKey: key)
                copied += 1
            }
            guard copied > 0 else { continue }
            Log.info("copied \(copied) legacy preference keys from \(legacyID)")
        }
    }
}
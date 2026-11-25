import Foundation

/// UserDefaults-backed preferences, plus the default ignore list.
public final class Prefs: @unchecked Sendable {
    public static let shared = Prefs()
    public static let didChangeNotification = Notification.Name("NanoClipPrefsDidChange")

    public static let defaultIgnoredBundleIDs: [String] = [
        "com.1password.1password",
        "com.1password.1password7",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "com.lastpass.LastPass",
        "com.apple.Passwords",
        "com.apple.keychainaccess",
        "org.keepassxc.keepassxc",
        "com.dashlane.dashlane",
        "com.enpass.Enpass",
    ]

    /// `maxItems == 0` means "keep everything".
    public static let unlimitedItems = 0

    private enum Key {
        static let launchAtLogin = "launchAtLogin"
        static let didAttemptLoginItem = "didAttemptLoginItem"
        static let maxItems = "maxItems"
        static let recordImages = "recordImages"
        static let hotKeyTrigger = "hotKeyTrigger"
        static let ignoredBundleIDs = "ignoredBundleIDs"
        static let didMigrateRetention = "didMigrateRetention"
    }

    private let defaults: UserDefaults
    private let notificationCenter: NotificationCenter

    public init(defaults: UserDefaults = .standard, notificationCenter: NotificationCenter = .default) {
        self.defaults = defaults
        self.notificationCenter = notificationCenter
        defaults.register(defaults: [
            Key.launchAtLogin: true,
            Key.didAttemptLoginItem: false,
            Key.maxItems: Self.unlimitedItems,
            Key.recordImages: true,
        ])
        if defaults.object(forKey: Key.ignoredBundleIDs) == nil {
            defaults.set(Self.defaultIgnoredBundleIDs, forKey: Key.ignoredBundleIDs)
        }
        migrateRetention()
    }

    /// 1.x wrote its 500-entry default to disk; the new default is "keep everything", so a stored
    /// 500 is treated as the old default rather than a deliberate cap. Runs once.
    private func migrateRetention() {
        guard !defaults.bool(forKey: Key.didMigrateRetention) else { return }
        if defaults.object(forKey: Key.maxItems) != nil, defaults.integer(forKey: Key.maxItems) == 500 {
            defaults.set(Self.unlimitedItems, forKey: Key.maxItems)
        }
        defaults.set(true, forKey: Key.didMigrateRetention)
    }

    private func changed() {
        notificationCenter.post(name: Self.didChangeNotification, object: self)
    }

    public var launchAtLogin: Bool {
        get { defaults.bool(forKey: Key.launchAtLogin) }
        set { defaults.set(newValue, forKey: Key.launchAtLogin); changed() }
    }

    public var didAttemptLoginItem: Bool {
        get { defaults.bool(forKey: Key.didAttemptLoginItem) }
        set { defaults.set(newValue, forKey: Key.didAttemptLoginItem) }
    }

    /// 0 keeps every entry (the default); a positive value caps the history length.
    public var maxItems: Int {
        get { max(0, defaults.integer(forKey: Key.maxItems)) }
        set { defaults.set(max(0, newValue), forKey: Key.maxItems); changed() }
    }

    public var keepsEverything: Bool { maxItems == Self.unlimitedItems }

    public var recordImages: Bool {
        get { defaults.bool(forKey: Key.recordImages) }
        set { defaults.set(newValue, forKey: Key.recordImages); changed() }
    }

    public var hotKeyTrigger: HotKeyTrigger {
        get {
            if let raw = defaults.string(forKey: Key.hotKeyTrigger),
               let data = raw.data(using: .utf8),
               let trigger = try? JSONDecoder().decode(HotKeyTrigger.self, from: data) {
                return trigger
            }
            return .default
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue),
                  let raw = String(data: data, encoding: .utf8) else { return }
            defaults.set(raw, forKey: Key.hotKeyTrigger)
            changed()
        }
    }

    public var ignoredBundleIDs: [String] {
        get { defaults.stringArray(forKey: Key.ignoredBundleIDs) ?? Self.defaultIgnoredBundleIDs }
        set {
            let cleaned = Array(Set(newValue.map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty })).sorted()
            defaults.set(cleaned, forKey: Key.ignoredBundleIDs)
            changed()
        }
    }

    public func isIgnored(bundleID: String?) -> Bool {
        guard let bundleID, !bundleID.isEmpty else { return false }
        return ignoredBundleIDs.contains(bundleID)
    }

    /// Images are never capped and no longer configurable; only the entry count is a limit.
    public var limits: ClipLimits {
        ClipLimits(maxItems: maxItems)
    }
}

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

    private enum Key {
        static let launchAtLogin = "launchAtLogin"
        static let didAttemptLoginItem = "didAttemptLoginItem"
        static let autoPaste = "autoPaste"
        static let maxItems = "maxItems"
        static let recordImages = "recordImages"
        static let maxImageBytes = "maxImageBytes"
        static let maxTotalImageBytes = "maxTotalImageBytes"
        static let hotKeyCode = "hotKeyCode"
        static let hotKeyModifiers = "hotKeyModifiers"
        static let ignoredBundleIDs = "ignoredBundleIDs"
    }

    private let defaults: UserDefaults
    private let notificationCenter: NotificationCenter

    public init(defaults: UserDefaults = .standard, notificationCenter: NotificationCenter = .default) {
        self.defaults = defaults
        self.notificationCenter = notificationCenter
        defaults.register(defaults: [
            Key.launchAtLogin: true,
            Key.didAttemptLoginItem: false,
            Key.autoPaste: true,
            Key.maxItems: 500,
            Key.recordImages: true,
            Key.maxImageBytes: 20 * 1024 * 1024,
            Key.maxTotalImageBytes: 500 * 1024 * 1024,
            Key.hotKeyCode: Int(KeyCombo.default.keyCode),
            Key.hotKeyModifiers: Int(KeyCombo.default.modifiers),
        ])
        if defaults.object(forKey: Key.ignoredBundleIDs) == nil {
            defaults.set(Self.defaultIgnoredBundleIDs, forKey: Key.ignoredBundleIDs)
        }
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

    public var autoPaste: Bool {
        get { defaults.bool(forKey: Key.autoPaste) }
        set { defaults.set(newValue, forKey: Key.autoPaste); changed() }
    }

    public var maxItems: Int {
        get { min(max(defaults.integer(forKey: Key.maxItems), 50), 2000) }
        set { defaults.set(min(max(newValue, 50), 2000), forKey: Key.maxItems); changed() }
    }

    public var recordImages: Bool {
        get { defaults.bool(forKey: Key.recordImages) }
        set { defaults.set(newValue, forKey: Key.recordImages); changed() }
    }

    public var maxImageBytes: Int {
        get {
            let value = defaults.integer(forKey: Key.maxImageBytes)
            return value > 0 ? value : 20 * 1024 * 1024
        }
        set { defaults.set(newValue, forKey: Key.maxImageBytes); changed() }
    }

    public var maxTotalImageBytes: Int {
        get {
            let value = defaults.integer(forKey: Key.maxTotalImageBytes)
            return value > 0 ? value : 500 * 1024 * 1024
        }
        set { defaults.set(newValue, forKey: Key.maxTotalImageBytes); changed() }
    }

    public var hotKey: KeyCombo {
        get {
            let code = UInt32(defaults.integer(forKey: Key.hotKeyCode))
            let modifiers = UInt32(defaults.integer(forKey: Key.hotKeyModifiers))
            let combo = KeyCombo(keyCode: code, modifiers: modifiers)
            return combo.hasModifier ? combo : .default
        }
        set {
            defaults.set(Int(newValue.keyCode), forKey: Key.hotKeyCode)
            defaults.set(Int(newValue.modifiers), forKey: Key.hotKeyModifiers)
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

    public var limits: ClipLimits {
        ClipLimits(
            maxItems: maxItems,
            maxImageBytes: maxImageBytes,
            maxTotalImageBytes: maxTotalImageBytes
        )
    }
}
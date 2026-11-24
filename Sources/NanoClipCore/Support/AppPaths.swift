import Foundation

public enum AppInfo {
    public static let name = "NanoClip"
    public static let bundleID = "com.jvz.nanoclip"
    public static let version = "1.0.0"
    public static let build = "1"

    /// ~/Library/Application Support/NanoClip
    public static func applicationSupportDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent(name, isDirectory: true)
    }
}
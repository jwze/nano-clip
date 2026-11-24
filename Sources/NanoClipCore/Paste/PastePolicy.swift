import Foundation

/// Single place that decides whether NanoClip may synthesize ⌘V, so the panel footer, the
/// activation path and the tests cannot drift apart.
public enum PastePolicy {
    public static func shouldAutoPaste(autoPasteEnabled: Bool, accessibilityTrusted: Bool) -> Bool {
        autoPasteEnabled && accessibilityTrusted
    }

    public static func shouldShowPermissionHint(autoPasteEnabled: Bool, accessibilityTrusted: Bool) -> Bool {
        autoPasteEnabled && !accessibilityTrusted
    }
}
import AppKit
import ApplicationServices
import Carbon.HIToolbox

public enum Accessibility {
    public static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt (once per signature) and returns the current trust state.
    @discardableResult
    public static func requestAccess(prompt: Bool = true) -> Bool {
        // The exported `kAXTrustedCheckOptionPrompt` is a mutable global; the documented key
        // string is stable, so use it directly instead of touching shared mutable state.
        let key = "AXTrustedCheckOptionPrompt"
        let options = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public static var settingsURL: URL? {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    public static func openSettings() {
        if let url = settingsURL {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Posts a synthetic ⌘V. Requires Accessibility permission for the *app bundle* doing the
/// posting; callers must check `Accessibility.isTrusted` and degrade to copy-only otherwise.
public enum Paster {
    /// Standard key codes (available here because AppKit/macOS clients use HID virtual codes).
    private static let vKeyCode = CGKeyCode(kVK_ANSI_V)

    public static func sendPasteCommand() {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        else {
            Log.error("could not create CGEvent for ⌘V")
            return
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        usleep(20_000)
        up.post(tap: .cghidEventTap)
    }
}
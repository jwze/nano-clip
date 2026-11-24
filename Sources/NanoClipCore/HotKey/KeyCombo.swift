import Foundation
import Carbon.HIToolbox

/// A global hot key described in Carbon terms (`RegisterEventHotKey` does not need
/// Accessibility permission, unlike `NSEvent` global monitors for keyDown).
public struct KeyCombo: Equatable, Sendable, Codable {
    /// Carbon virtual key code, identical to `NSEvent.keyCode` for the same physical key.
    public var keyCode: UInt32
    /// Carbon modifier mask (`cmdKey`, `shiftKey`, `optionKey`, `controlKey`).
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// ⌘⇧V — also "Paste and Match Style", which has the same intent as this app.
    public static let `default` = KeyCombo(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | shiftKey))
    /// ⌘⌥V — the documented alternative when the default clashes with another tool.
    public static let alternative = KeyCombo(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | optionKey))

    public var hasModifier: Bool {
        modifiers & UInt32(cmdKey | shiftKey | optionKey | controlKey) != 0
    }

    // MARK: - Carbon <-> Cocoa

    public init(keyCode: UInt32, cocoaModifiers: UInt32) {
        var carbon: UInt32 = 0
        if cocoaModifiers & (1 << 20) != 0 { carbon |= UInt32(cmdKey) }      // .command
        if cocoaModifiers & (1 << 17) != 0 { carbon |= UInt32(shiftKey) }    // .shift
        if cocoaModifiers & (1 << 19) != 0 { carbon |= UInt32(optionKey) }   // .option
        if cocoaModifiers & (1 << 18) != 0 { carbon |= UInt32(controlKey) }  // .control
        self.init(keyCode: keyCode, modifiers: carbon)
    }

    /// Carbon modifiers are not the same bits as `NSEvent.ModifierFlags`; convert for Carbon APIs.
    public var carbonModifiers: UInt32 { modifiers }

    // MARK: - Display

    public var displayString: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        text += Self.keyCharacter(for: keyCode) ?? "键码 \(keyCode)"
        return text
    }

    /// Layout-aware character for a virtual key code (falls back to a static map).
    public static func keyCharacter(for keyCode: UInt32) -> String? {
        if let translated = translateWithKeyboardLayout(keyCode: keyCode) {
            return translated
        }
        return fallbackKeyNames[keyCode]
    }

    private static func translateWithKeyboardLayout(keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutPointer).takeUnretainedValue() as Data
        return layoutData.withUnsafeBytes { raw -> String? in
            guard let base = raw.baseAddress else { return nil }
            let layout = base.assumingMemoryBound(to: UCKeyboardLayout.self)
            var deadKeyState: UInt32 = 0
            var characters = [UniChar](repeating: 0, count: 8)
            var length = 0
            let status = UCKeyTranslate(
                layout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )
            guard status == noErr, length > 0 else { return nil }
            let string = String(utf16CodeUnits: characters, count: length)
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed.uppercased()
        }
    }

    private static let fallbackKeyNames: [UInt32: String] = [
        UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
        UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
        UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
        UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
        UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
        UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
        UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
        UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
        UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
        UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
        UInt32(kVK_ANSI_9): "9",
        UInt32(kVK_Space): "空格", UInt32(kVK_Return): "↩", UInt32(kVK_Escape): "⎋",
        UInt32(kVK_Delete): "⌫", UInt32(kVK_ForwardDelete): "⌦",
        UInt32(kVK_LeftArrow): "←", UInt32(kVK_RightArrow): "→",
        UInt32(kVK_UpArrow): "↑", UInt32(kVK_DownArrow): "↓",
        UInt32(kVK_Tab): "⇥", UInt32(kVK_ANSI_Minus): "-", UInt32(kVK_ANSI_Equal): "=",
        UInt32(kVK_ANSI_LeftBracket): "[", UInt32(kVK_ANSI_RightBracket): "]",
        UInt32(kVK_ANSI_Backslash): "\\", UInt32(kVK_ANSI_Semicolon): ";",
        UInt32(kVK_ANSI_Quote): "'", UInt32(kVK_ANSI_Comma): ",",
        UInt32(kVK_ANSI_Period): ".", UInt32(kVK_ANSI_Slash): "/",
        UInt32(kVK_ANSI_Grave): "`",
    ]
}
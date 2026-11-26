// nano-clip — 轻量 macOS 剪贴板历史
// Copyright © 2026 jvz <them@live.cn>. All rights reserved.
// Watermark: jvz·NanoClip — 电子水印，请勿移除本署名头。

import Foundation
import Carbon.HIToolbox
import CoreGraphics

/// One modifier key, used by the double-tap trigger.
public enum ModifierKey: String, Sendable, Codable, CaseIterable {
    case command
    case option
    case control
    case shift

    /// Symbol shown in menus and buttons, e.g. `⌥`.
    public var symbol: String {
        switch self {
        case .command: return "⌘"
        case .option: return "⌥"
        case .control: return "⌃"
        case .shift: return "⇧"
        }
    }

    /// Spoken name, used in hints ("双击 Option").
    public var name: String {
        switch self {
        case .command: return "Command"
        case .option: return "Option"
        case .control: return "Control"
        case .shift: return "Shift"
        }
    }

    public var cgFlag: CGEventFlags {
        switch self {
        case .command: return .maskCommand
        case .option: return .maskAlternate
        case .control: return .maskControl
        case .shift: return .maskShift
        }
    }

    public var carbonModifier: UInt32 {
        switch self {
        case .command: return UInt32(cmdKey)
        case .option: return UInt32(optionKey)
        case .control: return UInt32(controlKey)
        case .shift: return UInt32(shiftKey)
        }
    }

    public init?(cocoaFlag flag: CGEventFlags) {
        switch flag {
        case .maskCommand: self = .command
        case .maskAlternate: self = .option
        case .maskControl: self = .control
        case .maskShift: self = .shift
        default: return nil
        }
    }
}

/// How the history panel is summoned. The default is a double tap of the Option key, which needs
/// no Accessibility permission; a recorded Carbon key combo stays available as an alternative.
public enum HotKeyTrigger: Sendable, Equatable, Codable {
    case doubleTap(ModifierKey)
    case keyCombo(KeyCombo)

    public static let `default` = HotKeyTrigger.doubleTap(.option)

    public var displayString: String {
        switch self {
        case .doubleTap(let modifier):
            return "双击 \(modifier.symbol)"
        case .keyCombo(let combo):
            return combo.displayString
        }
    }

    /// Short form for the status-bar menu, where "双击 ⌥" reads better right-aligned than
    /// "双击 Option".
    public var menuString: String {
        switch self {
        case .doubleTap(let modifier):
            return "双击\(modifier.symbol)\(modifier.symbol)"
        case .keyCombo(let combo):
            return combo.displayString
        }
    }
}

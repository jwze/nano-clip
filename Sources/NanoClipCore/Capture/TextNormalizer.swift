// nano-clip — 轻量 macOS 剪贴板历史
// Copyright © 2026 jvz <them@live.cn>. All rights reserved.
// Watermark: jvz·NanoClip — 电子水印，请勿移除本署名头。

import Foundation

public struct NormalizedText: Sendable, Equatable {
    public var text: String
    public var truncated: Bool

    public init(text: String, truncated: Bool) {
        self.text = text
        self.truncated = truncated
    }
}

public enum TextNormalizer {
    /// Hard cap for a single text entry (characters). Longer payloads are truncated and flagged.
    public static let maxLength = 1_000_000

    /// Newlines are unified, edge blank lines dropped and trailing whitespace trimmed. Leading
    /// spaces are preserved on purpose: copying indented code must paste back intact.
    public static func normalize(_ raw: String, maxLength: Int = TextNormalizer.maxLength) -> NormalizedText? {
        var text = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        while text.first == "\n" { text.removeFirst() }
        while let last = text.last, last.isWhitespace { text.removeLast() }

        guard !text.isEmpty, !text.allSatisfy({ $0.isWhitespace }) else { return nil }

        let truncated = text.count > maxLength
        if truncated { text = String(text.prefix(maxLength)) }
        return NormalizedText(text: text, truncated: truncated)
    }
}
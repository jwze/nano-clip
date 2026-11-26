// nano-clip — 轻量 macOS 剪贴板历史
// Copyright © 2026 jvz <them@live.cn>. All rights reserved.
// Watermark: jvz·NanoClip — 电子水印，请勿移除本署名头。

import AppKit

/// One raw image representation lifted from the pasteboard without decoding or transcoding.
public struct ImageCandidate: Sendable, Equatable {
    /// Pasteboard type as declared by the source app, e.g. `public.png`.
    public var uti: String
    public var data: Data

    public init(uti: String, data: Data) {
        self.uti = uti
        self.data = data
    }
}

public enum PasteboardReader {
    static let plainTextTypes: Set<String> = [
        "public.utf8-plain-text",
        "public.plain-text",
        "public.text",
        "NSStringPboardType",
    ]
    static let richTextTypes: Set<String> = ["public.rtf", "public.html"]

    /// Reads one pasteboard state into plain values. Text is always plain: rich payloads
    /// (`rtf`/`html`) are flattened to their string when no plain-text representation exists.
    ///
    /// A file copy is never inspected further: Finder puts the file *name* on the pasteboard as
    /// text, which is how file names used to end up in the history.
    public static func snapshot(from pasteboard: NSPasteboard, sourceApp: String?) -> PasteboardSnapshot? {
        let pasteboardTypes = Set((pasteboard.types ?? []).map(\.rawValue))
        guard let item = pasteboard.pasteboardItems?.first else { return nil }
        var types = Set(item.types.map(\.rawValue))
        types.formUnion(pasteboardTypes)

        if !types.isDisjoint(with: CaptureRules.fileTypes) {
            return PasteboardSnapshot(types: types, sourceApp: sourceApp)
        }

        let hasTextType = !types.isDisjoint(with: plainTextTypes) || !types.isDisjoint(with: richTextTypes)
        var text: String?
        if hasTextType {
            text = plainText(pasteboard: pasteboard, item: item)
        }

        var images: [ImageCandidate] = []
        if text == nil {
            images = imageCandidates(pasteboard: pasteboard, item: item)
        }

        return PasteboardSnapshot(
            types: types,
            string: text,
            images: images,
            sourceApp: sourceApp
        )
    }

    /// Every image representation on the pasteboard, in the order the source app listed them so
    /// the stored file keeps the format the user actually copied.
    static func imageCandidates(pasteboard: NSPasteboard, item: NSPasteboardItem) -> [ImageCandidate] {
        var seen = Set<String>()
        var candidates: [ImageCandidate] = []
        for type in item.types + (pasteboard.types ?? []) {
            let uti = type.rawValue
            guard ImageFormats.isImageUTI(uti), seen.insert(uti).inserted else { continue }
            guard let data = item.data(forType: type) ?? pasteboard.data(forType: type), !data.isEmpty else {
                continue
            }
            candidates.append(ImageCandidate(uti: uti, data: data))
        }
        // The pasteboard's own order is usually already the source app's preference; these two
        // only matter when that order is empty (e.g. a lazy provider that failed above).
        if candidates.isEmpty {
            for type in [NSPasteboard.PasteboardType.png, .tiff] {
                if let data = item.data(forType: type) ?? pasteboard.data(forType: type), !data.isEmpty {
                    candidates.append(ImageCandidate(uti: type.rawValue, data: data))
                }
            }
        }
        return candidates
    }

    static func plainText(pasteboard: NSPasteboard, item: NSPasteboardItem) -> String? {
        if let plain = pasteboard.string(forType: .string), !plain.isEmpty {
            return plain
        }
        if let rtf = item.data(forType: .rtf) ?? pasteboard.data(forType: .rtf),
           let attributed = try? NSAttributedString(
               data: rtf,
               options: [.documentType: NSAttributedString.DocumentType.rtf],
               documentAttributes: nil
           ),
           !attributed.string.isEmpty {
            return attributed.string
        }
        if let html = item.data(forType: .html) ?? pasteboard.data(forType: .html),
           let attributed = try? NSAttributedString(
               data: html,
               options: [.documentType: NSAttributedString.DocumentType.html],
               documentAttributes: nil
           ),
           !attributed.string.isEmpty {
            return attributed.string
        }
        return nil
    }
}

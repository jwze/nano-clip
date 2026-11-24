import AppKit

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
    public static func snapshot(from pasteboard: NSPasteboard, sourceApp: String?) -> PasteboardSnapshot? {
        let pasteboardTypes = Set((pasteboard.types ?? []).map(\.rawValue))
        guard let item = pasteboard.pasteboardItems?.first else { return nil }
        var types = Set(item.types.map(\.rawValue))
        types.formUnion(pasteboardTypes)

        let hasTextType = !types.isDisjoint(with: plainTextTypes) || !types.isDisjoint(with: richTextTypes)
        let hasFileType = !types.isDisjoint(with: CaptureRules.fileTypes)

        // A Finder file copy advertises `public.file-url`; only read text when the payload really
        // carries a text type, otherwise `.string` would hand back a file path.
        var text: String?
        if !hasFileType || hasTextType {
            text = plainText(pasteboard: pasteboard, item: item)
        }

        var png: Data?
        var tiff: Data?
        if text == nil {
            png = item.data(forType: .png) ?? pasteboard.data(forType: .png)
            tiff = item.data(forType: .tiff) ?? pasteboard.data(forType: .tiff)
        }

        return PasteboardSnapshot(types: types, string: text, tiff: tiff, png: png, sourceApp: sourceApp)
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
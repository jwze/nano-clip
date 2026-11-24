import AppKit

/// Writes only plain-content pasteboard types: text as `public.utf8-plain-text`, images as
/// `public.png`. No RTF, HTML or style payload is ever written back, so pasting into any app
/// yields unformatted content.
public enum PasteboardWriter {
    @discardableResult
    public static func writePlainText(_ text: String, to pasteboard: NSPasteboard = .general) -> Int {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return pasteboard.changeCount
    }

    @discardableResult
    public static func writePNG(_ png: Data, to pasteboard: NSPasteboard = .general) -> Int {
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
        return pasteboard.changeCount
    }
}
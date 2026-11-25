import AppKit

/// Writes only plain-content pasteboard types: text as `public.utf8-plain-text`, images in the
/// format they were captured in. No RTF, HTML or style payload is ever written back, so pasting
/// into any app yields unformatted content.
public enum PasteboardWriter {
    @discardableResult
    public static func writePlainText(_ text: String, to pasteboard: NSPasteboard = .general) -> Int {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return pasteboard.changeCount
    }

    /// Writes the stored bytes under their original UTI. A TIFF fallback is added for formats
    /// many apps cannot read directly (e.g. HEIC); it is generated here, never stored.
    @discardableResult
    public static func writeImage(
        _ data: Data,
        uti: String,
        to pasteboard: NSPasteboard = .general
    ) -> Int {
        let type = NSPasteboard.PasteboardType(uti)
        pasteboard.clearContents()
        pasteboard.setData(data, forType: type)
        if type != .png, type != .tiff,
           ImageFormats.isImageUTI(uti),
           let image = ImageFormats.image(from: data),
           let tiff = ImageFormats.convertToTIFF(image) {
            pasteboard.setData(tiff, forType: .tiff)
        }
        return pasteboard.changeCount
    }
}

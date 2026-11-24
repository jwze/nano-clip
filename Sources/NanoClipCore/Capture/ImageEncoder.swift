import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Everything stores as PNG: lossless, alpha preserving, and predictable on disk.
public enum ImageEncoder {
    /// Prefers the pasteboard's PNG payload when it already is a valid PNG, otherwise re-encodes
    /// the TIFF payload. Returns `nil` when neither payload decodes.
    public static func normalizedPNG(tiff: Data?, png: Data?) -> Data? {
        if let png, isPNG(png) { return png }
        if let tiff, let image = image(from: tiff) { return encodePNG(image) }
        if let png, let image = image(from: png) { return encodePNG(image) }
        return nil
    }

    public static func isPNG(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source)
        else { return false }
        return (type as String) == UTType.png.identifier && CGImageSourceGetCount(source) > 0
    }

    public static func image(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    public static func encodePNG(_ image: CGImage) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
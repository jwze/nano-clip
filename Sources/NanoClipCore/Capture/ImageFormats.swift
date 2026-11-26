// nano-clip — 轻量 macOS 剪贴板历史
// Copyright © 2026 jvz <them@live.cn>. All rights reserved.
// Watermark: jvz·NanoClip — 电子水印，请勿移除本署名头。

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// One image payload exactly as it arrived on the pasteboard: nothing is re-encoded, so a JPEG
/// stays a JPEG and a screenshot's PNG keeps its exact bytes.
public struct ImagePayload: Sendable, Equatable {
    public let data: Data
    /// Uniform type identifier of `data`, e.g. `public.png`.
    public let uti: String
    /// File extension that matches `uti`, without the dot.
    public let fileExtension: String

    public init(data: Data, uti: String, fileExtension: String) {
        self.data = data
        self.uti = uti
        self.fileExtension = fileExtension
    }
}

public enum ImageFormats {
    /// Preference order used when the pasteboard offers several representations of the same image.
    /// Lossless, alpha-capable formats come first, but nothing is ever transcoded: the first
    /// representation that carries data is stored as-is.
    static let preferredUTIs: [String] = [
        UTType.png.identifier,
        UTType.heic.identifier,
        UTType.jpeg.identifier,
        UTType.gif.identifier,
        "org.webmproject.webp",
        UTType.tiff.identifier,
        UTType.bmp.identifier,
        UTType.icns.identifier,
    ]

    /// Extension for a stored UTI, falling back to the pasteboard type mapping.
    public static func fileExtension(forUTI uti: String) -> String {
        if let type = UTType(uti), let ext = type.preferredFilenameExtension {
            return ext
        }
        switch uti {
        case UTType.png.identifier: return "png"
        case UTType.tiff.identifier: return "tiff"
        case UTType.jpeg.identifier: return "jpg"
        case UTType.gif.identifier: return "gif"
        case UTType.heic.identifier: return "heic"
        case UTType.bmp.identifier: return "bmp"
        case UTType.icns.identifier: return "icns"
        default: return "img"
        }
    }

    /// UTI guessed from a stored file name, used when a legacy row has no `image_uti` column value.
    public static func uti(forPathExtension ext: String) -> String {
        if let type = UTType(filenameExtension: ext) {
            return type.identifier
        }
        return UTType.png.identifier
    }

    public static func isImageUTI(_ uti: String) -> Bool {
        UTType(uti)?.conforms(to: .image) ?? false
    }

    /// Reads the format of `data` from its header, so a mislabelled pasteboard type cannot make
    /// the store write a `.png` file that actually contains JPEG bytes.
    public static func detectedUTI(_ data: Data, declared: String? = nil) -> String? {
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let type = CGImageSourceGetType(source) as String?,
           CGImageSourceGetCount(source) > 0 {
            return type
        }
        if let declared, isImageUTI(declared), CGImageSourceCreateWithData(data as CFData, nil) != nil {
            return declared
        }
        return nil
    }

    public static func payload(data: Data, declaredUTI: String?) -> ImagePayload? {
        guard let uti = detectedUTI(data, declared: declaredUTI) else { return nil }
        return ImagePayload(data: data, uti: uti, fileExtension: fileExtension(forUTI: uti))
    }

    public static func image(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// TIFF rendering used only when pasting a format the target app may not read. Never stored.
    public static func convertToTIFF(_ image: CGImage) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData,
            UTType.tiff.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

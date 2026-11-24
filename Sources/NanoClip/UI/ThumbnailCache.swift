import AppKit
import ImageIO

/// Small, bounded thumbnail cache. Cleared when the history panel closes so a closed panel does
/// not keep decoded bitmaps in memory.
@MainActor
final class ThumbnailCache {
    private let cache = NSCache<NSString, NSImage>()

    init() {
        cache.countLimit = 60
        cache.totalCostLimit = 32 * 1024 * 1024
    }

    func image(for url: URL, maxPixel: CGFloat = 96) -> NSImage? {
        let key = url.lastPathComponent as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixel * 2),
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        cache.setObject(image, forKey: key, cost: cgImage.bytesPerRow * cgImage.height)
        return image
    }

    func clear() {
        cache.removeAllObjects()
    }
}
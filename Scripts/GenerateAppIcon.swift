// nano-clip — 轻量 macOS 剪贴板历史
// Copyright © 2026 jvz <them@live.cn>. All rights reserved.
// Watermark: jvz·NanoClip — 电子水印，请勿移除本署名头。

import AppKit
import Foundation

// Renders the NanoClip app icon into an .icns bundle, using the shared brand geometry in
// Sources/NanoClip/UI/BrandMark.swift.
// Usage: swiftc -O Scripts/GenerateAppIcon.swift Sources/NanoClip/UI/BrandMark.swift -o <bin>

@main
struct GenerateAppIcon {
    static func main() throws {
        let arguments = CommandLine.arguments
        let outputPath = arguments.count > 1 ? arguments[1] : "Resources/AppIcon.icns"
        let outputURL = URL(fileURLWithPath: outputPath)
        let iconsetURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NanoClip-icon-\(UUID().uuidString).iconset")

        try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

        func pngData(size: Int) -> Data {
            guard let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: size,
                pixelsHigh: size,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ) else { fatalError("could not allocate \(size)x\(size) bitmap") }
            rep.size = NSSize(width: size, height: size)

            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            BrandIcon.draw(in: CGRect(x: 0, y: 0, width: CGFloat(size), height: CGFloat(size)))
            NSGraphicsContext.restoreGraphicsState()

            guard let data = rep.representation(using: .png, properties: [:]) else {
                fatalError("could not encode PNG at \(size)")
            }
            return data
        }

        if arguments.count > 2 {
            // Debug mode: dump one PNG so the artwork can be eyeballed during design.
            try pngData(size: Int(arguments[2]) ?? 1024).write(to: outputURL)
            print("wrote \(outputURL.path)")
            exit(0)
        }

        let variants: [(name: String, size: Int)] = [
            ("icon_16x16", 16),
            ("icon_16x16@2x", 32),
            ("icon_32x32", 32),
            ("icon_32x32@2x", 64),
            ("icon_128x128", 128),
            ("icon_128x128@2x", 256),
            ("icon_256x256", 256),
            ("icon_256x256@2x", 512),
            ("icon_512x512", 512),
            ("icon_512x512@2x", 1024),
        ]

        for variant in variants {
            let url = iconsetURL.appendingPathComponent("\(variant.name).png")
            try pngData(size: variant.size).write(to: url)
        }

        let iconutil = Process()
        iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        iconutil.arguments = ["-c", "icns", iconsetURL.path, "-o", outputURL.path]
        try iconutil.run()
        iconutil.waitUntilExit()

        try? FileManager.default.removeItem(at: iconsetURL)
        guard iconutil.terminationStatus == 0 else {
            fatalError("iconutil failed with status \(iconutil.terminationStatus)")
        }
    }
}

#!/usr/bin/env swift
import AppKit
import Foundation

// Renders the NanoClip app icon (gradient squircle + clipboard) into an .icns bundle.
// Usage: swift Scripts/GenerateAppIcon.swift <output.icns>

let arguments = CommandLine.arguments
let outputPath = arguments.count > 1 ? arguments[1] : "Resources/AppIcon.icns"
let outputURL = URL(fileURLWithPath: outputPath)
let iconsetURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("NanoClip-icon-\(UUID().uuidString).iconset")

try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

func drawIcon(in rect: CGRect) {
    let scale = rect.width / 1024.0
    func p(_ value: CGFloat) -> CGFloat { value * scale }

    NSGraphicsContext.current?.shouldAntialias = true

    // Background squircle with gradient.
    let background = NSBezierPath(
        roundedRect: rect.insetBy(dx: p(40), dy: p(40)),
        xRadius: p(205),
        yRadius: p(205)
    )
    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.33, green: 0.53, blue: 0.98, alpha: 1.0),
        NSColor(srgbRed: 0.17, green: 0.24, blue: 0.62, alpha: 1.0),
    ])!
    gradient.draw(in: background, angle: -90)

    // Soft highlight at the top.
    let highlight = NSBezierPath(
        roundedRect: CGRect(x: p(120), y: p(650), width: p(784), height: p(300)),
        xRadius: p(150),
        yRadius: p(150)
    )
    NSColor.white.withAlphaComponent(0.10).setFill()
    highlight.fill()

    // Clipboard body.
    let body = NSBezierPath(
        roundedRect: CGRect(x: p(232), y: p(168), width: p(560), height: p(688)),
        xRadius: p(72),
        yRadius: p(72)
    )
    NSColor.white.setFill()
    body.fill()

    // Clipboard clip.
    let clip = NSBezierPath(
        roundedRect: CGRect(x: p(392), y: p(770), width: p(240), height: p(128)),
        xRadius: p(46),
        yRadius: p(46)
    )
    NSColor(srgbRed: 0.86, green: 0.90, blue: 1.0, alpha: 1.0).setFill()
    clip.fill()

    // History lines.
    let lineColor = NSColor(srgbRed: 0.36, green: 0.47, blue: 0.78, alpha: 1.0)
    lineColor.setFill()
    let widths: [CGFloat] = [392, 392, 264]
    let ys: [CGFloat] = [606, 486, 366]
    for (width, y) in zip(widths, ys) {
        let line = NSBezierPath(
            roundedRect: CGRect(x: p(316), y: p(y), width: p(width), height: p(56)),
            xRadius: p(28),
            yRadius: p(28)
        )
        line.fill()
    }
}

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
    drawIcon(in: CGRect(x: 0, y: 0, width: CGFloat(size), height: CGFloat(size)))
    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("could not encode PNG at \(size)")
    }
    return data
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
print("wrote \(outputURL.path)")
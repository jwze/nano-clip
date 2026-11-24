#!/usr/bin/env swift
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Fixture generator for manual verification: puts a specific kind of payload on the clipboard so
// NanoClip's capture rules can be checked from a shell.
//
//   swift Scripts/TestPasteboard.swift text "hello"
//   swift Scripts/TestPasteboard.swift rtf            # rich text + plain fallback
//   swift Scripts/TestPasteboard.swift rtf-only       # RTF without any plain representation
//   swift Scripts/TestPasteboard.swift png            # PNG with a transparent corner
//   swift Scripts/TestPasteboard.swift tiff           # TIFF only (must be re-encoded as PNG)
//   swift Scripts/TestPasteboard.swift file           # copied file (must not be captured)
//   swift Scripts/TestPasteboard.swift concealed      # password-manager style payload
//   swift Scripts/TestPasteboard.swift list <types>   # print current pasteboard types

let arguments = CommandLine.arguments
let mode = arguments.count > 1 ? arguments[1] : "text"
let pasteboard = NSPasteboard.general

func rgbaPNG(size: Int) -> Data {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: size * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.clear(CGRect(x: 0, y: 0, width: size, height: size))
    context.setFillColor(red: 0.95, green: 0.25, blue: 0.25, alpha: 1)
    context.fillEllipse(in: CGRect(x: 10, y: 10, width: size - 20, height: size - 20))
    let image = context.makeImage()!
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
    return data as Data
}

func rgbaTIFF(size: Int) -> Data {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: size * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.clear(CGRect(x: 0, y: 0, width: size, height: size))
    context.setFillColor(red: 0.2, green: 0.4, blue: 0.95, alpha: 1)
    context.fillEllipse(in: CGRect(x: 8, y: 8, width: size - 16, height: size - 16))
    let image = context.makeImage()!
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, UTType.tiff.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
    return data as Data
}

let marker = "NanoClip-fixture-\(Int(Date().timeIntervalSince1970))"

func attributedSample() -> NSAttributedString {
    let string = NSMutableAttributedString(string: "\(marker) 富文本样本")
    string.addAttribute(
        .font,
        value: NSFont.boldSystemFont(ofSize: 20),
        range: NSRange(location: 0, length: string.length)
    )
    string.addAttribute(
        .foregroundColor,
        value: NSColor.systemRed,
        range: NSRange(location: 0, length: 8)
    )
    return string
}

switch mode {
case "text":
    let text = arguments.count > 2 ? arguments[2] : marker
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
    print("text: \(text)")

case "rtf", "rtf-only":
    let attributed = attributedSample()
    let range = NSRange(location: 0, length: attributed.length)
    let rtf = try attributed.data(
        from: range,
        documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
    )
    let item = NSPasteboardItem()
    item.setData(rtf, forType: .rtf)
    if mode == "rtf" {
        item.setString(attributed.string, forType: .string)
    }
    pasteboard.clearContents()
    pasteboard.writeObjects([item])
    print("\(mode): \(marker)")

case "png":
    pasteboard.clearContents()
    pasteboard.setData(rgbaPNG(size: 64), forType: .png)
    print("png 64x64 with transparent corner")

case "tiff":
    pasteboard.clearContents()
    pasteboard.setData(rgbaTIFF(size: 64), forType: .tiff)
    print("tiff 64x64 with transparent corner")

case "file":
    let url = URL(fileURLWithPath: "/tmp/NanoClip-file-fixture.txt")
    try "file payload must never be captured".write(to: url, atomically: true, encoding: .utf8)
    pasteboard.clearContents()
    pasteboard.writeObjects([url as NSURL])
    print("file: \(url.path)")

case "concealed":
    let item = NSPasteboardItem()
    item.setString("\(marker)-secret", forType: .string)
    item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
    pasteboard.clearContents()
    pasteboard.writeObjects([item])
    print("concealed: \(marker)-secret")

case "list":
    print((pasteboard.types ?? []).map(\.rawValue).joined(separator: ", "))

default:
    print("unknown mode: \(mode)")
    exit(1)
}
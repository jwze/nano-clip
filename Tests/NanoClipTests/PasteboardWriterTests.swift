import XCTest
import AppKit
@testable import NanoClipCore

final class PasteboardWriterTests: XCTestCase {
    private var pasteboard: NSPasteboard!

    override func setUp() {
        pasteboard = NSPasteboard(name: NSPasteboard.Name("NanoClipTests-\(UUID().uuidString)"))
    }

    override func tearDown() {
        pasteboard.releaseGlobally()
        pasteboard = nil
    }

    func testPlainTextWritesOnlyPlainTextType() {
        PasteboardWriter.writePlainText("styled? no thanks", to: pasteboard)

        let types = Set((pasteboard.types ?? []).map(\.rawValue))
        // AppKit also publishes the legacy alias; both are plain text. Nothing rich may appear.
        XCTAssertTrue(types.contains("public.utf8-plain-text"))
        XCTAssertTrue(types.isSubset(of: ["public.utf8-plain-text", "NSStringPboardType"]), "unexpected types: \(types)")
        XCTAssertEqual(pasteboard.string(forType: .string), "styled? no thanks")
        XCTAssertNil(pasteboard.data(forType: .rtf))
        XCTAssertNil(pasteboard.data(forType: .html))
    }

    func testPNGWritesOnlyPNGType() {
        let png = TestImages.png(width: 12, height: 12)
        PasteboardWriter.writePNG(png, to: pasteboard)

        let types = Set((pasteboard.types ?? []).map(\.rawValue))
        XCTAssertTrue(types.contains("public.png"))
        XCTAssertTrue(types.isDisjoint(with: ["public.utf8-plain-text", "public.rtf", "public.html"]))
        XCTAssertEqual(pasteboard.data(forType: .png), png)
    }

    func testChangeCountAdvancesOnWrite() {
        let before = pasteboard.changeCount
        let after = PasteboardWriter.writePlainText("counting", to: pasteboard)
        XCTAssertGreaterThan(after, before)
        XCTAssertEqual(after, pasteboard.changeCount)
    }
}

final class ImageEncoderTests: XCTestCase {
    func testPNGPayloadPassesThrough() {
        let png = TestImages.png(width: 24, height: 24)
        XCTAssertTrue(ImageEncoder.isPNG(png))
        XCTAssertEqual(ImageEncoder.normalizedPNG(tiff: nil, png: png), png)
    }

    func testTIFFIsReencodedAsPNG() throws {
        let tiff = TestImages.tiff(width: 25, height: 15)
        let png = try XCTUnwrap(ImageEncoder.normalizedPNG(tiff: tiff, png: nil))
        XCTAssertTrue(ImageEncoder.isPNG(png))
        XCTAssertFalse(png.isEmpty)

        let image = try XCTUnwrap(ImageEncoder.image(from: png))
        XCTAssertEqual(image.width, 25)
        XCTAssertEqual(image.height, 15)
    }

    func testGarbageDataIsRejected() {
        XCTAssertNil(ImageEncoder.normalizedPNG(tiff: Data([0xDE, 0xAD]), png: Data([0xBE, 0xEF])))
        XCTAssertFalse(ImageEncoder.isPNG(Data([0x00])))
    }
}

final class KeyComboTests: XCTestCase {
    func testDefaultComboIsCommandShiftV() {
        XCTAssertEqual(KeyCombo.default.keyCode, 9)
        XCTAssertEqual(KeyCombo.default.displayString, "⇧⌘V")
        XCTAssertTrue(KeyCombo.default.hasModifier)
    }

    func testModifierConversionFromCocoaFlags() {
        let flags = NSEvent.ModifierFlags([.command, .shift])
        let combo = KeyCombo(keyCode: 9, cocoaModifiers: UInt32(flags.rawValue))
        XCTAssertEqual(combo.modifiers, KeyCombo.default.modifiers)
    }

    func testModifierlessComboIsRejectedByPrefs() {
        let suiteName = "NanoClipTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let prefs = Prefs(defaults: defaults)

        prefs.hotKey = KeyCombo(keyCode: 9, modifiers: 0)
        XCTAssertEqual(prefs.hotKey, .default, "a combo without modifiers falls back to the default")
    }
}
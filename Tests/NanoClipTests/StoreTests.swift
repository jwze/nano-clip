import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import NanoClipCore

final class StoreTests: XCTestCase {
    private var temp: TempDirectory!
    private var store: ClipStore!

    override func setUpWithError() throws {
        temp = TempDirectory()
        store = try ClipStore(directory: temp.url)
    }

    override func tearDownWithError() throws {
        store = nil
        temp = nil
    }

    private var testLimits: ClipLimits {
        ClipLimits(maxItems: 500, maxImageBytes: 20 * 1024 * 1024, maxTotalImageBytes: 500 * 1024 * 1024)
    }

    private func insertText(_ text: String, sourceApp: String? = nil) throws -> ClipItem {
        let result = try store.insertText(text, sourceApp: sourceApp, limits: testLimits)
        guard let item = result.item else {
            XCTFail("insert rejected: \(result)")
            throw XCTSkip("insert rejected")
        }
        return item
    }

    func testInsertAndFetchText() throws {
        let item = try insertText("hello world", sourceApp: "com.apple.TextEdit")
        XCTAssertEqual(item.kind, .text)
        XCTAssertEqual(item.text, "hello world")
        XCTAssertEqual(item.sourceApp, "com.apple.TextEdit")

        let fetched = store.fetch()
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.text, "hello world")
        XCTAssertEqual(store.statistics().count, 1)
    }

    func testDeduplicationBumpsToTop() throws {
        let first = try insertText("duplicate")
        usleep(20_000)
        let second = try insertText("other")
        usleep(20_000)
        let result = try store.insertText("duplicate", sourceApp: nil, limits: testLimits)

        guard case .deduped(let deduped) = result else {
            return XCTFail("expected dedupe, got \(result)")
        }
        XCTAssertEqual(deduped.id, first.id)
        XCTAssertGreaterThan(deduped.createdAt, second.createdAt)
        XCTAssertEqual(store.fetch().count, 2)
        XCTAssertNotEqual(second.id, first.id)
    }

    func testPinnedItemsSurviveTrim() throws {
        let pinned = try insertText("keep me")
        store.setPinned(id: pinned.id, pinned: true)
        for index in 0..<5 {
            usleep(5_000)
            _ = try insertText("filler \(index)")
        }

        let limits = ClipLimits(maxItems: 3, maxImageBytes: 1_048_576, maxTotalImageBytes: 1_048_576)
        store.trim(limits: limits)

        let remaining = store.fetch()
        // The cap applies to unpinned entries only, so a pinned item is additive.
        XCTAssertEqual(remaining.count, 4, "pinned + three newest unpinned")
        XCTAssertTrue(remaining.contains { $0.id == pinned.id && $0.pinned })
        XCTAssertFalse(remaining.contains { $0.text == "filler 0" })
        XCTAssertFalse(remaining.contains { $0.text == "filler 1" })
    }

    func testMaxItemsTrimsOldestFirst() throws {
        for index in 0..<10 {
            usleep(5_000)
            _ = try insertText("item \(index)")
        }
        let limits = ClipLimits(maxItems: 4, maxImageBytes: 1_048_576, maxTotalImageBytes: 1_048_576)
        store.trim(limits: limits)

        let remaining = store.fetch()
        XCTAssertEqual(remaining.count, 4)
        XCTAssertEqual(remaining.first?.text, "item 9")
        XCTAssertEqual(remaining.last?.text, "item 6")
    }

    func testDeleteRemovesRowAndImageFile() throws {
        let png = TestImages.png(width: 40, height: 30)
        let result = try store.insertImage(png: png, sourceApp: nil, limits: testLimits)
        guard let item = result.item else { return XCTFail("image rejected") }

        XCTAssertEqual(store.statistics().imageCount, 1)
        XCTAssertEqual(temp.imageFiles().count, 1)
        let url = try XCTUnwrap(store.imageURL(for: item))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        store.delete(id: item.id)
        XCTAssertEqual(store.fetch().count, 0)
        XCTAssertTrue(temp.imageFiles().isEmpty, "image file must be removed with its row")
    }

    func testImageDeduplicationDoesNotGrowDisk() throws {
        let png = TestImages.png(width: 50, height: 50)
        let first = try store.insertImage(png: png, sourceApp: nil, limits: testLimits)
        usleep(20_000)
        let second = try store.insertImage(png: png, sourceApp: nil, limits: testLimits)

        guard let firstItem = first.item, let secondItem = second.item else {
            return XCTFail("image rejected")
        }
        XCTAssertEqual(firstItem.id, secondItem.id)
        if case .deduped = second {
        } else {
            XCTFail("second insert must dedupe")
        }
        XCTAssertEqual(temp.imageFiles().count, 1)
    }

    func testTotalImageBytesLimitDeletesOldestImages() throws {
        let small = TestImages.png(width: 20, height: 20)
        let large = TestImages.png(width: 120, height: 120)

        let first = try store.insertImage(png: small, sourceApp: nil, limits: testLimits)
        usleep(20_000)
        let second = try store.insertImage(png: large, sourceApp: nil, limits: testLimits)
        guard let firstItem = first.item, let secondItem = second.item else {
            return XCTFail("image rejected")
        }
        let bytes = firstItem.imageBytes + secondItem.imageBytes
        let limits = ClipLimits(
            maxItems: 500,
            maxImageBytes: 20 * 1024 * 1024,
            maxTotalImageBytes: bytes - 1
        )
        store.trim(limits: limits)

        let remaining = store.fetch()
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.id, secondItem.id, "oldest image goes first")
        XCTAssertEqual(temp.imageFiles().count, 1)
    }

    func testImageOverLimitIsRejected() throws {
        let png = TestImages.png(width: 100, height: 100)
        let limits = ClipLimits(maxItems: 10, maxImageBytes: png.count - 1, maxTotalImageBytes: 10_000_000)
        let result = try store.insertImage(png: png, sourceApp: nil, limits: limits)
        guard case .rejected = result else {
            return XCTFail("expected rejection, got \(result)")
        }
        XCTAssertEqual(store.fetch().count, 0)
        XCTAssertTrue(temp.imageFiles().isEmpty)
    }

    func testClearAllRemovesEverything() throws {
        _ = try insertText("one")
        _ = try store.insertImage(png: TestImages.png(width: 30, height: 30), sourceApp: nil, limits: testLimits)
        XCTAssertEqual(store.statistics().count, 2)

        store.clearAll()
        XCTAssertEqual(store.fetch().count, 0)
        XCTAssertEqual(store.statistics(), .empty)
        XCTAssertTrue(temp.imageFiles().isEmpty)
    }

    func testSearchEscapesLikeWildcards() throws {
        _ = try insertText("100% done")
        _ = try insertText("abc_def")
        _ = try insertText("abcXdef")
        _ = try insertText("plain text")

        XCTAssertEqual(store.fetch(query: "%").map(\.text), ["100% done"])
        XCTAssertEqual(store.fetch(query: "_").map(\.text), ["abc_def"])
        XCTAssertEqual(store.fetch(query: "abc").count, 2)
        XCTAssertEqual(store.fetch(query: "plain").map(\.text), ["plain text"])
    }

    func testSearchWithQueryExcludesImages() throws {
        _ = try insertText("text entry")
        _ = try store.insertImage(png: TestImages.png(width: 30, height: 30), sourceApp: nil, limits: testLimits)
        XCTAssertEqual(store.fetch(query: "").count, 2)
        XCTAssertEqual(store.fetch(query: "text").count, 1)
        XCTAssertTrue(store.fetch(query: "").contains { $0.kind == .image })
    }

    func testSearchMatchesSourceApp() throws {
        _ = try insertText("payload", sourceApp: "com.apple.Safari")
        _ = try insertText("other", sourceApp: "com.apple.TextEdit")
        XCTAssertEqual(store.fetch(query: "Safari").count, 1)
    }

    func testOrphanImageGarbageCollection() throws {
        let png = TestImages.png(width: 30, height: 30)
        _ = try store.insertImage(png: png, sourceApp: nil, limits: testLimits)
        let orphan = temp.imagesDirectory.appendingPathComponent("deadbeef.png")
        try Data([0x00]).write(to: orphan)

        XCTAssertEqual(temp.imageFiles().count, 2)
        XCTAssertEqual(store.gcOrphanImages(), 1)
        XCTAssertEqual(temp.imageFiles().count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
    }

    func testTruncatedFlagRoundTrips() throws {
        let result = try store.insertText("short", sourceApp: nil, truncated: true, limits: testLimits)
        XCTAssertEqual(result.item?.truncated, true)
        XCTAssertEqual(store.fetch().first?.truncated, true)
    }

    func testTouchMovesItemToTop() throws {
        let first = try insertText("first")
        usleep(20_000)
        _ = try insertText("second")
        usleep(20_000)
        XCTAssertEqual(store.fetch().first?.text, "second")

        store.touch(id: first.id)
        XCTAssertEqual(store.fetch().first?.text, "first")
    }

    func testPersistenceAcrossStoreInstances() throws {
        _ = try insertText("persisted")
        store = nil
        let reopened = try ClipStore(directory: temp.url)
        XCTAssertEqual(reopened.fetch().first?.text, "persisted")
        store = reopened
    }
}

enum TestImages {
    static func png(width: Int, height: Int, gray: CGFloat = 0.5) -> Data {
        let image = cgImage(width: width, height: height, gray: gray)
        return encode(image, type: UTType.png)
    }

    static func tiff(width: Int, height: Int, gray: CGFloat = 0.5) -> Data {
        let image = cgImage(width: width, height: height, gray: gray)
        return encode(image, type: UTType.tiff)
    }

    private static func cgImage(width: Int, height: Int, gray: CGFloat) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: gray, green: gray, blue: gray, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private static func encode(_ image: CGImage, type: UTType) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssert(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
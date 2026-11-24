import XCTest
@testable import NanoClipCore

@MainActor
final class CaptureServiceTests: XCTestCase {
    private var temp: TempDirectory!
    private var store: ClipStore!
    private var suite: String!
    private var prefs: Prefs!

    override func setUp() {
        temp = TempDirectory()
        store = try! ClipStore(directory: temp.url)
        suite = "NanoClipCaptureTests-\(UUID().uuidString)"
        prefs = Prefs(defaults: UserDefaults(suiteName: suite)!)
    }

    override func tearDown() {
        store = nil
        prefs = nil
        UserDefaults().removePersistentDomain(forName: suite)
        temp = nil
    }

    private func waitForHistoryChange() {
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            if store.statistics().count > 0 { return }
        }
    }

    func testIgnoredSourceAppIsNotCaptured() {
        prefs.ignoredBundleIDs = ["com.apple.Safari"]
        let service = CaptureService(store: store, prefs: prefs)
        service.handle(
            PasteboardSnapshot(types: ["public.utf8-plain-text"], string: "secret", sourceApp: "com.apple.Safari")
        )
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        XCTAssertEqual(store.statistics().count, 0, "content from an ignored app must never be stored")
    }

    func testNonIgnoredSourceAppIsCaptured() {
        prefs.ignoredBundleIDs = ["com.apple.Safari"]
        let service = CaptureService(store: store, prefs: prefs)
        service.handle(
            PasteboardSnapshot(types: ["public.utf8-plain-text"], string: "kept", sourceApp: "com.apple.TextEdit")
        )
        waitForHistoryChange()
        XCTAssertEqual(store.fetch().first?.text, "kept")
        XCTAssertEqual(store.fetch().first?.sourceApp, "com.apple.TextEdit")
    }

    func testImagesDisabledSkipsImagePayloads() {
        prefs.recordImages = false
        let service = CaptureService(store: store, prefs: prefs)
        service.handle(PasteboardSnapshot(types: ["public.png"], png: TestImages.png(width: 20, height: 20)))
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        XCTAssertEqual(store.statistics().count, 0)
    }

    func testImagePayloadIsStoredAsPNG() {
        prefs.recordImages = true
        let service = CaptureService(store: store, prefs: prefs)
        service.handle(PasteboardSnapshot(types: ["public.tiff"], tiff: TestImages.tiff(width: 32, height: 18)))

        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline, store.statistics().imageCount == 0 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertEqual(store.statistics().imageCount, 1)
        let item = try! XCTUnwrap(store.fetch().first)
        let url = try! XCTUnwrap(store.imageURL(for: item))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(url.lastPathComponent.hasSuffix(".png"))
    }

    func testConcealedPayloadNeverReachesTheStore() {
        let service = CaptureService(store: store, prefs: prefs)
        service.handle(
            PasteboardSnapshot(
                types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"],
                string: "password"
            )
        )
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        XCTAssertEqual(store.statistics().count, 0)
    }
}

final class PrefsTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private var prefs: Prefs!

    override func setUp() {
        suite = "NanoClipPrefsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        prefs = Prefs(defaults: defaults)
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suite)
        prefs = nil
        defaults = nil
        suite = nil
    }

    func testDefaultsMatchThePlan() {
        XCTAssertTrue(prefs.launchAtLogin)
        XCTAssertTrue(prefs.autoPaste)
        XCTAssertEqual(prefs.maxItems, 500)
        XCTAssertTrue(prefs.recordImages)
        XCTAssertEqual(prefs.maxImageBytes, 20 * 1024 * 1024)
        XCTAssertEqual(prefs.maxTotalImageBytes, 500 * 1024 * 1024)
        XCTAssertEqual(prefs.hotKey, .default)
        XCTAssertEqual(Set(prefs.ignoredBundleIDs), Set(Prefs.defaultIgnoredBundleIDs))
        XCTAssertTrue(prefs.ignoredBundleIDs.contains("com.1password.1password"))
    }

    func testValuesRoundTripAndAreClamped() {
        prefs.maxItems = 10
        XCTAssertEqual(prefs.maxItems, 50, "clamped to the documented minimum")
        prefs.maxItems = 5000
        XCTAssertEqual(prefs.maxItems, 2000, "clamped to the documented maximum")
        prefs.maxItems = 800
        XCTAssertEqual(prefs.maxItems, 800)

        prefs.recordImages = false
        XCTAssertFalse(prefs.recordImages)
        prefs.autoPaste = false
        XCTAssertFalse(prefs.autoPaste)
        prefs.launchAtLogin = false
        XCTAssertFalse(prefs.launchAtLogin)
    }

    func testLimitsMirrorPreferences() {
        prefs.maxItems = 250
        prefs.maxImageBytes = 5 * 1024 * 1024
        XCTAssertEqual(prefs.limits.maxItems, 250)
        XCTAssertEqual(prefs.limits.maxImageBytes, 5 * 1024 * 1024)
        XCTAssertEqual(prefs.limits.maxTotalImageBytes, prefs.maxTotalImageBytes)
    }

    func testIgnoredListDeduplicatesAndSorts() {
        prefs.ignoredBundleIDs = ["b.app", "a.app", "b.app", "  "]
        XCTAssertEqual(prefs.ignoredBundleIDs, ["a.app", "b.app"])
        XCTAssertTrue(prefs.isIgnored(bundleID: "a.app"))
        XCTAssertFalse(prefs.isIgnored(bundleID: "c.app"))
        XCTAssertFalse(prefs.isIgnored(bundleID: nil))
    }

    func testChangesPostNotification() {
        var changes = 0
        let observer = NotificationCenter.default.addObserver(
            forName: Prefs.didChangeNotification,
            object: nil,
            queue: nil
        ) { _ in changes += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }

        prefs.autoPaste = false
        prefs.maxItems = 600
        XCTAssertEqual(changes, 2)
    }
}

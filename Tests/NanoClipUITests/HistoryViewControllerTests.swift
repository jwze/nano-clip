import XCTest
import AppKit
@testable import NanoClip
@testable import NanoClipCore

/// In-process UI tests. Synthetic keyboard events cannot be injected from a shell without the
/// Accessibility grant, so typing is fed through the real field-editor path instead: the same
/// insertText → controlTextDidChange → filter → table pipeline a keystroke triggers.
@MainActor
extension HistoryViewController {
    /// Feeds text through the real field-editor path — the same insertText → controlTextDidChange
    /// chain a keystroke triggers — so the search/filter wiring is exercised without synthetic HID
    /// events (which need the Accessibility grant).
    func typeIntoSearchForTesting(_ text: String) {
        view.window?.makeFirstResponder(searchField)
        guard let editor = searchField.currentEditor() as? NSTextView else {
            return XCTFailLoudly("missing field editor")
        }
        editor.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    var rowCountForTesting: Int { tableView.numberOfRows }
}

func XCTFailLoudly(_ message: String) {
    assertionFailure(message)
}

@MainActor
final class HistoryViewControllerTests: XCTestCase {
    private struct Fixture {
        let temp: URL
        let store: ClipStore
        let prefs: Prefs
        let suite: String
        let panel: HistoryPanel
        let controller: HistoryViewController
    }

    private let limits = ClipLimits(maxItems: 100, maxImageBytes: 1_048_576, maxTotalImageBytes: 8_388_608)

    private func makeFixture() throws -> Fixture {
        _ = NSApplication.shared
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("NanoClipUITests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)

        let store = try ClipStore(directory: temp)
        try store.insertText("alpha entry", sourceApp: "com.apple.Safari", limits: limits)
        usleep(10_000)
        try store.insertText("beta entry", sourceApp: "com.apple.TextEdit", limits: limits)

        let suite = "NanoClipUITests-\(UUID().uuidString)"
        let prefs = Prefs(defaults: UserDefaults(suiteName: suite)!)

        let controller = HistoryViewController(store: store, prefs: prefs)
        let panel = HistoryPanel()
        panel.contentViewController = controller
        panel.setContentSize(HistoryPanel.size)
        panel.orderFront(nil)
        panel.makeKey()
        controller.reload()

        return Fixture(
            temp: temp,
            store: store,
            prefs: prefs,
            suite: suite,
            panel: panel,
            controller: controller
        )
    }

    private func withFixture(_ body: (Fixture) throws -> Void) rethrows {
        let fixture = try! makeFixture()
        defer {
            fixture.panel.orderOut(nil)
            fixture.panel.contentViewController = nil
            UserDefaults().removePersistentDomain(forName: fixture.suite)
            try? FileManager.default.removeItem(at: fixture.temp)
        }
        try body(fixture)
    }

    func testReloadShowsStoredItems() {
        withFixture { fixture in
            XCTAssertEqual(fixture.controller.rowCountForTesting, 2)
            XCTAssertEqual(
                fixture.controller.selectedItem?.text,
                "beta entry",
                "newest entry is selected by default"
            )
        }
    }

    func testTypingFiltersTheList() {
        withFixture { fixture in
            fixture.controller.typeIntoSearchForTesting("beta")
            XCTAssertEqual(fixture.controller.query, "beta")
            XCTAssertEqual(fixture.controller.rowCountForTesting, 1)
            XCTAssertEqual(fixture.controller.selectedItem?.text, "beta entry")
        }
    }

    func testTypingMatchesSourceAppName() {
        withFixture { fixture in
            fixture.controller.typeIntoSearchForTesting("Safari")
            XCTAssertEqual(fixture.controller.rowCountForTesting, 1)
            XCTAssertEqual(fixture.controller.selectedItem?.text, "alpha entry")
        }
    }

    func testClearingSearchRestoresAllRows() {
        withFixture { fixture in
            fixture.controller.typeIntoSearchForTesting("beta")
            XCTAssertEqual(fixture.controller.rowCountForTesting, 1)
            fixture.controller.typeIntoSearchForTesting("")
            XCTAssertEqual(fixture.controller.rowCountForTesting, 2)
        }
    }

    func testNoMatchesShowsEmptyList() {
        withFixture { fixture in
            fixture.controller.typeIntoSearchForTesting("zzz-not-there")
            XCTAssertEqual(fixture.controller.rowCountForTesting, 0)
            XCTAssertNil(fixture.controller.selectedItem)
        }
    }

    func testArrowKeysMoveAndClampSelection() {
        withFixture { fixture in
            fixture.controller.moveSelection(by: 1)
            XCTAssertEqual(fixture.controller.selectedItem?.text, "alpha entry")
            fixture.controller.moveSelection(by: -1)
            XCTAssertEqual(fixture.controller.selectedItem?.text, "beta entry")
            fixture.controller.moveSelection(by: -5)
            XCTAssertEqual(fixture.controller.selectedItem?.text, "beta entry")
            fixture.controller.moveSelection(by: 10)
            XCTAssertEqual(fixture.controller.selectedItem?.text, "alpha entry")
        }
    }

    func testActivateDelegatesSelectedItem() {
        withFixture { fixture in
            var activated: ClipItem?
            fixture.controller.onActivate = { activated = $0 }
            fixture.controller.activateSelected()
            XCTAssertEqual(activated?.text, "beta entry")
        }
    }

    func testDeleteRemovesRowThroughCallback() {
        withFixture { fixture in
            fixture.controller.onDelete = { item in
                fixture.store.delete(id: item.id)
            }
            fixture.controller.deleteSelected()
            XCTAssertEqual(fixture.controller.rowCountForTesting, 1)
            XCTAssertEqual(fixture.store.statistics().count, 1)
            XCTAssertEqual(fixture.store.fetch().first?.text, "alpha entry")
        }
    }

    func testTogglePinMovesItemToTop() {
        withFixture { fixture in
            fixture.controller.onTogglePin = { item in
                fixture.store.setPinned(id: item.id, pinned: !item.pinned)
            }
            fixture.controller.togglePinSelected()
            XCTAssertEqual(fixture.controller.rowCountForTesting, 2)
            XCTAssertEqual(fixture.controller.selectedItem?.pinned, true)
        }
    }

    func testPanelUsesIntendedGeometry() {
        withFixture { fixture in
            XCTAssertEqual(fixture.panel.contentLayoutRect.width, HistoryPanel.size.width)
            XCTAssertEqual(fixture.panel.contentLayoutRect.height, HistoryPanel.size.height)
            XCTAssertTrue(fixture.panel.canBecomeKey)
            XCTAssertFalse(fixture.panel.canBecomeMain)
        }
    }

    func testImageRowsRenderThumbnailIcon() throws {
        let fixture = try makeFixture()
        defer {
            fixture.panel.orderOut(nil)
            fixture.panel.contentViewController = nil
            UserDefaults().removePersistentDomain(forName: fixture.suite)
            try? FileManager.default.removeItem(at: fixture.temp)
        }

        let png = try XCTUnwrap(makePNG(width: 64, height: 64))
        let result = try fixture.store.insertImage(png: png, sourceApp: "com.apple.Screenshot", limits: limits)
        let item = try XCTUnwrap(result.item)
        fixture.controller.reload()

        XCTAssertEqual(fixture.controller.rowCountForTesting, 3)
        let url = try XCTUnwrap(fixture.store.imageURL(for: item))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        XCTAssertEqual(fixture.store.fetch().first?.kind, .image, "newest item is the image")
        let row = try XCTUnwrap(
            fixture.controller.tableView.view(atColumn: 0, row: 0, makeIfNecessary: true) as? ClipRowView
        )
        row.display()
        XCTAssertNotNil(row.superview)
    }

    /// Renders the filtered panel to /tmp/NanoClip-filtered-panel.png as visual evidence that the
    /// search result list draws correctly (the shell cannot inject keystrokes to do it live).
    func testRendersFilteredPanelImage() throws {
        let fixture = try makeFixture()
        defer {
            fixture.panel.orderOut(nil)
            fixture.panel.contentViewController = nil
            UserDefaults().removePersistentDomain(forName: fixture.suite)
            try? FileManager.default.removeItem(at: fixture.temp)
        }

        fixture.controller.typeIntoSearchForTesting("beta")
        XCTAssertEqual(fixture.controller.rowCountForTesting, 1)

        let view = fixture.controller.view
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 1000)
        try png.write(to: URL(fileURLWithPath: "/tmp/NanoClip-filtered-panel.png"))
    }

    private func makePNG(width: Int, height: Int) -> Data? {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(red: 0.4, green: 0.6, blue: 0.9, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            "public.png" as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
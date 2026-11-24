import XCTest
import AppKit
@testable import NanoClip
@testable import NanoClipCore

/// Drives the panel's key handling with real `NSEvent`s. HID-level injection needs the
/// Accessibility grant, but the handler itself is plain AppKit, so this covers the full
/// Enter/Esc/arrow/⌘⌫/⌘P/⌘, contract.
@MainActor
final class HistoryPanelControllerTests: XCTestCase {
    private struct Fixture {
        let temp: URL
        let store: ClipStore
        let prefs: Prefs
        let suite: String
        let controller: HistoryPanelController
    }

    private let limits = ClipLimits(maxItems: 100, maxImageBytes: 1_048_576, maxTotalImageBytes: 8_388_608)

    private func makeFixture() throws -> Fixture {
        _ = NSApplication.shared
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("NanoClipPanelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let store = try ClipStore(directory: temp)
        try store.insertText("first entry", sourceApp: nil, limits: limits)
        usleep(10_000)
        try store.insertText("second entry", sourceApp: nil, limits: limits)

        let suite = "NanoClipPanelTests-\(UUID().uuidString)"
        let prefs = Prefs(defaults: UserDefaults(suiteName: suite)!)
        let controller = HistoryPanelController(store: store, prefs: prefs)
        controller.show()
        return Fixture(temp: temp, store: store, prefs: prefs, suite: suite, controller: controller)
    }

    private func withFixture(_ body: (Fixture) throws -> Void) rethrows {
        let fixture = try! makeFixture()
        defer {
            fixture.controller.hide(restoreFocus: false)
            UserDefaults().removePersistentDomain(forName: fixture.suite)
            try? FileManager.default.removeItem(at: fixture.temp)
        }
        try body(fixture)
    }

    private func keyEvent(
        keyCode: UInt16,
        flags: NSEvent.ModifierFlags = [],
        characters: String = ""
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: flags,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )!
    }

    func testShowMakesPanelVisible() {
        withFixture { fixture in
            XCTAssertTrue(fixture.controller.isVisible)
        }
    }

    func testReturnActivatesSelectedItem() {
        withFixture { fixture in
            var activated: ClipItem?
            fixture.controller.onActivate = { activated = $0 }
            XCTAssertTrue(fixture.controller.handleKeyDown(keyEvent(keyCode: 36, characters: "\r")))
            XCTAssertEqual(activated?.text, "second entry")
        }
    }

    func testEscapeHidesPanel() {
        withFixture { fixture in
            XCTAssertTrue(fixture.controller.handleKeyDown(keyEvent(keyCode: 53, characters: "\u{1b}")))
            XCTAssertFalse(fixture.controller.isVisible)
        }
    }

    func testArrowKeysMoveSelectionInsidePanel() {
        withFixture { fixture in
            var activated: ClipItem?
            fixture.controller.onActivate = { activated = $0 }
            XCTAssertTrue(fixture.controller.handleKeyDown(keyEvent(keyCode: 125)))
            fixture.controller.handleKeyDown(keyEvent(keyCode: 36, characters: "\r"))
            XCTAssertEqual(activated?.text, "first entry")
        }
    }

    func testCommandDeleteRemovesSelectedItem() {
        withFixture { fixture in
            fixture.controller.onDelete = { [store = fixture.store] item in
                store.delete(id: item.id)
            }
            fixture.controller.handleKeyDown(keyEvent(keyCode: 125))
            XCTAssertTrue(fixture.controller.handleKeyDown(keyEvent(keyCode: 51, flags: .command)))
            XCTAssertEqual(fixture.store.statistics().count, 1)
        }
    }

    func testCommandPTogglesPin() {
        withFixture { fixture in
            fixture.controller.onTogglePin = { [store = fixture.store] item in
                store.setPinned(id: item.id, pinned: !item.pinned)
            }
            XCTAssertTrue(fixture.controller.handleKeyDown(keyEvent(keyCode: 35, flags: .command, characters: "p")))
            XCTAssertEqual(fixture.store.fetch().first?.pinned, true)
        }
    }

    func testCommandCommaOpensPreferencesAndClosesPanel() {
        withFixture { fixture in
            var opened = false
            fixture.controller.onOpenPreferences = { opened = true }
            XCTAssertTrue(fixture.controller.handleKeyDown(keyEvent(keyCode: 43, flags: .command, characters: ",")))
            XCTAssertTrue(opened)
            XCTAssertFalse(fixture.controller.isVisible)
        }
    }

    func testUnhandledKeysPassThrough() {
        withFixture { fixture in
            XCTAssertFalse(fixture.controller.handleKeyDown(keyEvent(keyCode: 0, characters: "a")))
        }
    }

    func testShowingWhileVisibleTogglesPanelOff() {
        withFixture { fixture in
            XCTAssertTrue(fixture.controller.isVisible)
            fixture.controller.show()
            XCTAssertFalse(fixture.controller.isVisible, "second ⌘⇧V closes the panel")
        }
    }
}
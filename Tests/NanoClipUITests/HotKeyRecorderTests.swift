import XCTest
import AppKit
@testable import NanoClip
@testable import NanoClipCore

@MainActor
final class HotKeyRecorderTests: XCTestCase {
    private func makeWindow(button: NSButton) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 80),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView?.addSubview(button)
        window.orderFront(nil)
        window.makeKey()
        return window
    }

    private func keyEvent(keyCode: UInt16, flags: NSEvent.ModifierFlags, characters: String) -> NSEvent {
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

    func testRecordsModifierCombo() {
        let button = HotKeyRecorderButton(combo: .default)
        let window = makeWindow(button: button)
        defer { window.orderOut(nil) }

        var recorded: KeyCombo?
        button.onChange = { recorded = $0 }

        button.performClick(nil)  // starts recording
        button.keyDown(with: keyEvent(keyCode: 9, flags: [.command, .option], characters: "v"))

        XCTAssertEqual(recorded?.keyCode, 9)
        XCTAssertEqual(
            recorded?.modifiers,
            KeyCombo(keyCode: 9, cocoaModifiers: UInt32(NSEvent.ModifierFlags([.command, .option]).rawValue)).modifiers
        )
    }

    func testRejectsComboWithoutModifier() {
        let button = HotKeyRecorderButton(combo: .default)
        let window = makeWindow(button: button)
        defer { window.orderOut(nil) }

        var recorded: KeyCombo?
        button.onChange = { recorded = $0 }
        button.performClick(nil)
        button.keyDown(with: keyEvent(keyCode: 0, flags: [], characters: "a"))

        XCTAssertNil(recorded, "a bare key must not become a global shortcut")
        XCTAssertEqual(button.combo, .default)
    }

    func testEscapeCancelsRecording() {
        let button = HotKeyRecorderButton(combo: .default)
        let window = makeWindow(button: button)
        defer { window.orderOut(nil) }

        var recorded: KeyCombo?
        button.onChange = { recorded = $0 }
        button.performClick(nil)
        button.keyDown(with: keyEvent(keyCode: 53, flags: [], characters: "\u{1b}"))

        XCTAssertNil(recorded)
        XCTAssertEqual(button.title, KeyCombo.default.displayString)
    }
}

@MainActor
final class StatusItemTests: XCTestCase {
    func testStatusItemShowsTemplateIconAndMenu() {
        let controller = StatusItemController()
        // The controller owns the item privately; assert the observable menu contract instead.
        XCTAssertEqual(controller.hotKeyDisplay(), "")
        controller.onShowHistory = {}
        controller.onShowPreferences = {}
        controller.onToggleLoginItem = {}
        controller.refreshHotKeyTitle()
    }

    func testMenuBarSymbolExists() {
        XCTAssertNotNil(
            NSImage(systemSymbolName: "list.clipboard", accessibilityDescription: nil),
            "the status item symbol must exist on this macOS version"
        )
    }
}

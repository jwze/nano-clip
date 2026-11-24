import AppKit

/// Spotlight-style floating panel: borderless and non-activating. A non-activating panel can
/// become the key window and receive keystrokes *without* pulling the whole app forward, so the
/// app the user is working in stays active and the focus switch is invisible.
@MainActor
final class HistoryPanel: NSPanel {
    static let size = NSSize(width: 360, height: 470)

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow
        becomesKeyOnlyIfNeeded = false
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}